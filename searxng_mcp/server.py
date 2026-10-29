# SPDX-License-Identifier: AGPL-3.0-or-later
"""MCP server that gives AI agents a ``search`` tool backed by a SearXNG
instance (by default the local one started with ``start-searxng.ps1``).

Run it as a stdio MCP server, e.g. for Claude Code::

    claude mcp add searxng -- <repo>\\.venv\\Scripts\\python.exe <repo>\\searxng_mcp\\server.py

Environment:

``SEARXNG_URL``
  Base URL of the SearXNG instance (default ``http://127.0.0.1:8888``).  The
  instance must have the ``json`` output format enabled (``search.formats`` in
  settings.yml).

``SEARXNG_TIMEOUT``
  HTTP timeout in seconds (default 20).
"""

import json
import os
import typing as t
import urllib.error
import urllib.parse
import urllib.request

import anyio.to_thread
from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import ToolAnnotations

SEARXNG_URL = os.environ.get("SEARXNG_URL", "http://127.0.0.1:8888").rstrip("/")
TIMEOUT = float(os.environ.get("SEARXNG_TIMEOUT", "20"))
MAX_CONTENT = 400
"""Snippets are cut to this many characters to keep the tool output small."""

TimeRange = t.Literal["", "day", "week", "month", "year"]

server = MCPServer(
    name="searxng",
    instructions=(
        "Web search through a self-hosted SearXNG metasearch engine. Results are titles, URLs and "
        "short snippets, not full pages: fetch a URL with another tool to read it."
    ),
)


class SearXNGError(ToolError):
    """Error with a message meant for the agent (returned as a tool error)."""


def _get_json(params: dict[str, str]) -> dict[str, t.Any]:
    url = f"{SEARXNG_URL}/search?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "searxng-mcp"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        if exc.code == 403:
            raise SearXNGError(
                f"{SEARXNG_URL} refused the JSON format (HTTP 403). Add 'json' to search.formats "
                "in the SearXNG settings.yml and restart SearXNG."
            ) from exc
        if exc.code == 429:
            raise SearXNGError(f"{SEARXNG_URL} rate-limited this client (HTTP 429). Wait and retry.") from exc
        raise SearXNGError(f"{SEARXNG_URL} answered HTTP {exc.code}.") from exc
    except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
        reason = getattr(exc, "reason", exc)
        raise SearXNGError(
            f"Can't reach SearXNG at {SEARXNG_URL} ({reason}). Is it running? Start it with start-searxng.ps1."
        ) from exc


def _shorten(text: str | None) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= MAX_CONTENT else text[: MAX_CONTENT - 1] + "…"


def format_results(data: dict[str, t.Any], max_results: int) -> str:
    """Render a SearXNG JSON response as compact Markdown for an LLM."""
    lines: list[str] = []

    for answer in data.get("answers", []):
        text = answer.get("answer") if isinstance(answer, dict) else answer
        if text:
            lines.append(f"Answer: {_shorten(str(text))}")

    for box in data.get("infoboxes", [])[:1]:
        title = box.get("infobox", "")
        lines.append(f"Infobox: {title} — {_shorten(box.get('content'))}".rstrip(" —"))

    results = data.get("results", [])[:max_results]
    if lines and results:
        lines.append("")
    for i, res in enumerate(results, 1):
        lines.append(f"{i}. {res.get('title') or res.get('url')}")
        lines.append(f"   {res.get('url')}")
        meta = [res.get("publishedDate") or "", ", ".join(res.get("engines", []))]
        content = _shorten(res.get("content"))
        if content:
            lines.append(f"   {content}")
        meta_text = " · ".join(m for m in meta if m)
        if meta_text:
            lines.append(f"   ({meta_text})")

    if not results and not lines:
        lines.append("No results.")

    if data.get("suggestions"):
        lines.append("")
        lines.append("Related searches: " + "; ".join(data["suggestions"][:5]))

    unresponsive = [e[0] if isinstance(e, list) else str(e) for e in data.get("unresponsive_engines", [])]
    if unresponsive:
        lines.append("")
        lines.append("Engines that failed (results may be incomplete): " + ", ".join(unresponsive))

    return "\n".join(lines)


@server.tool(
    annotations=ToolAnnotations(title="Web search (SearXNG)", readOnlyHint=True, openWorldHint=True),
    structured_output=False,
)
async def search(
    query: str,
    categories: str = "general",
    language: str = "auto",
    time_range: TimeRange = "",
    page: int = 1,
    max_results: int = 10,
) -> str:
    """Search the web with SearXNG, a metasearch engine that combines results from Google,
    Bing, DuckDuckGo, Brave, Wikipedia and many more.

    Args:
        query: Search terms. SearXNG syntax works too, e.g. "!wp rust" (only Wikipedia)
            or "site:example.com".
        categories: Comma-separated SearXNG categories: general, news, science, it, images,
            videos, music, files, social media, map.
        language: Language code such as "en", "de" or "en-US"; "auto" lets SearXNG decide.
        time_range: Only results from the last "day", "week", "month" or "year"; empty for any time.
        page: Result page, starting at 1.
        max_results: Maximum number of results to return (1-50).
    """
    params = {"q": query, "format": "json", "categories": categories, "language": language, "pageno": str(page)}
    if time_range:
        params["time_range"] = time_range
    max_results = min(max(max_results, 1), 50)
    data = await anyio.to_thread.run_sync(_get_json, params)
    return format_results(data, max_results)


def main():
    server.run("stdio")


if __name__ == "__main__":
    main()
