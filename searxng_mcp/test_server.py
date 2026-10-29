# SPDX-License-Identifier: AGPL-3.0-or-later
# pylint: disable=missing-module-docstring,missing-class-docstring,missing-function-docstring,invalid-name
"""Offline tests of the MCP server; run with::

.venv\\Scripts\\python.exe -m unittest discover -s searxng_mcp -v
"""

import asyncio
import http.server
import threading
import unittest
from unittest import mock

import server

ARTICLE = (
    "<html><head><title>Test page</title></head><body>"
    "<nav><a href='/'>Home</a> | <a href='/about'>About</a></nav>"
    "<article><h1>Main heading</h1>"
    + "".join(f"<p>Paragraph {i}: the quick brown fox jumps over the lazy dog.</p>" for i in range(40))
    + "</article><footer>Copyright footer</footer></body></html>"
)

ROUTES = {
    "/article": (200, "text/html; charset=utf-8", ARTICLE.encode()),
    "/plain": (200, "text/plain; charset=utf-8", "just plain text ✓".encode()),
    "/file.pdf": (200, "application/pdf", b"%PDF-1.4 ..."),
    "/empty": (200, "text/html", b""),
    "/challenge": (
        200,
        "text/html",
        b"<html><head><title>Just a moment...</title></head><body><p>Enable JavaScript and cookies to "
        b"continue.</p></body></html>",
    ),
    "/missing": (404, "text/html", b"not found"),
}


class _Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/redirect-local":
            self.send_response(302)
            self.send_header("Location", "http://127.0.0.1:1/secret")
            self.end_headers()
            return
        code, ctype, body = ROUTES.get(self.path, ROUTES["/missing"])
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # silence
        pass


class FetchTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def fetch(self, path, allow_private=True, **kwargs):
        with mock.patch.object(server, "ALLOW_PRIVATE", allow_private):
            return asyncio.run(server.fetch(self.base + path, **kwargs))

    def test_main_text_as_markdown(self):
        out = self.fetch("/article")
        # trafilatura prefers the article's <h1> over <title>
        self.assertRegex(out, r"^Title: (Test page|Main heading)\n")
        self.assertIn("# Main heading", out)
        self.assertIn("Paragraph 0: the quick brown fox", out)
        self.assertNotIn("Copyright footer", out)
        self.assertNotIn("About", out)

    def test_long_page_in_parts(self):
        first = self.fetch("/article", max_chars=500)
        self.assertIn("Call fetch again with start=500", first)
        second = self.fetch("/article", start=500, max_chars=500)
        self.assertIn("[Showing characters 500-1000 of", second)

    def test_past_end(self):
        self.assertIn("past the end", self.fetch("/article", start=10**6))

    def test_plain_text(self):
        self.assertIn("just plain text ✓", self.fetch("/plain"))

    def test_unsupported_type(self):
        with self.assertRaisesRegex(server.SearXNGError, "application/pdf"):
            self.fetch("/file.pdf")

    def test_empty_html(self):
        with self.assertRaisesRegex(server.SearXNGError, "empty"):
            self.fetch("/empty")

    def test_bot_check_page_is_an_error(self):
        with self.assertRaisesRegex(server.SearXNGError, "bot check"):
            self.fetch("/challenge")

    def test_http_error(self):
        with self.assertRaisesRegex(server.SearXNGError, "HTTP 404"):
            self.fetch("/missing")

    def test_private_address_blocked(self):
        with self.assertRaisesRegex(server.SearXNGError, "private network"):
            self.fetch("/article", allow_private=False)

    def test_redirect_to_private_address_blocked(self):
        # the first hop is allowed, the redirect target is checked again
        with mock.patch.object(server, "check_url", side_effect=self._only_first_hop_allowed()):
            with self.assertRaisesRegex(server.SearXNGError, "redirect target"):
                asyncio.run(server.fetch(self.base + "/redirect-local"))

    def _only_first_hop_allowed(self):
        calls = []

        def check(url):
            calls.append(url)
            if len(calls) > 1:
                raise server.SearXNGError(f"redirect target {url} blocked")

        return check


class CheckUrlTests(unittest.TestCase):

    def test_rejects_other_schemes(self):
        for url in ("file:///C:/Windows/win.ini", "ftp://example.com/x", "javascript:alert(1)", "http://"):
            with self.subTest(url=url), self.assertRaises(server.SearXNGError):
                server.check_url(url)

    def test_rejects_local_and_private_addresses(self):
        for host in ("127.0.0.1", "localhost", "10.1.2.3", "192.168.0.1", "169.254.169.254", "[::1]", "0.0.0.0"):
            with self.subTest(host=host), mock.patch.object(server, "ALLOW_PRIVATE", False):
                with self.assertRaisesRegex(server.SearXNGError, "private network"):
                    server.check_url(f"http://{host}/")

    def test_accepts_public_address(self):
        with mock.patch.object(server, "ALLOW_PRIVATE", False):
            server.check_url("https://8.8.8.8/")


class FormatResultsTests(unittest.TestCase):

    def test_results_answers_and_failed_engines(self):
        data = {
            "answers": [{"answer": "42"}],
            "results": [
                {"title": "A", "url": "https://a.example", "content": "x " * 500, "engines": ["brave", "bing"]},
                {"title": "B", "url": "https://b.example", "content": "", "engines": []},
            ],
            "suggestions": ["more"],
            "unresponsive_engines": [["duckduckgo", "CAPTCHA"]],
        }
        out = server.format_results(data, max_results=1)
        self.assertIn("Answer: 42", out)
        self.assertIn("1. A", out)
        self.assertNotIn("2. B", out)
        self.assertIn("…", out)
        self.assertIn("(brave, bing)", out)
        self.assertIn("Related searches: more", out)
        self.assertIn("Engines that failed (results may be incomplete): duckduckgo", out)

    def test_no_results(self):
        self.assertEqual(server.format_results({"results": []}, 10), "No results.")


class TidyMarkdownTests(unittest.TestCase):

    def test_heading_anchors_removed(self):
        sphinx = "# Trafilatura#\n\n## Description#\ntext #1\n## Usage#"
        self.assertEqual(server.tidy_markdown(sphinx), "# Trafilatura\n\n## Description\ntext #1\n## Usage")

    def test_heading_anchors_removed_despite_code_comment(self):
        text = "# A#\n## B#\n## C#\n## D#\n```\n# a comment\n```"
        self.assertEqual(server.tidy_markdown(text), "# A\n## B\n## C\n## D\n```\n# a comment\n```")

    def test_single_pilcrow_heading(self):
        self.assertEqual(
            server.tidy_markdown("# `asyncio` — Asynchronous I/O¶\ntext"), "# `asyncio` — Asynchronous I/O\ntext"
        )

    def test_real_hash_in_heading_kept(self):
        self.assertEqual(server.tidy_markdown("# C#"), "# C#")
        self.assertEqual(server.tidy_markdown("# Learn C#\n## Basics"), "# Learn C#\n## Basics")

    def test_citations_removed(self):
        text = r"engine.<sup>\[1\]</sup><sup>\[2\]</sup> More<sup>\[citation needed\]</sup>. x<sup>2</sup>"
        self.assertEqual(server.tidy_markdown(text), "engine. More. x<sup>2</sup>")


if __name__ == "__main__":
    unittest.main()
