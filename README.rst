.. SPDX-License-Identifier: AGPL-3.0-or-later

.. _metasearch engine: https://en.wikipedia.org/wiki/Metasearch_engine
.. _Installation guide: https://docs.searxng.org/admin/installation.html
.. _Configuration guide: https://docs.searxng.org/admin/settings/index.html
.. _CONTRIBUTING: https://github.com/searxng/searxng/blob/master/CONTRIBUTING.rst
.. _LICENSE: https://github.com/searxng/searxng/blob/master/LICENSE

.. figure:: https://raw.githubusercontent.com/searxng/searxng/master/client/simple/src/brand/searxng.svg
   :target: https://searxng.org
   :alt: SearXNG
   :width: 512px


SearXNG is a `metasearch engine`_. Users are neither tracked nor profiled.

.. note::

   **This is searxng_windows, an unofficial fork of** `searxng/searxng
   <https://github.com/searxng/searxng>`_ **that runs natively on Windows** (no
   Docker, no WSL).  It is not affiliated with or endorsed by the SearXNG
   project.  Please report Windows-specific problems here, not upstream.

Running on Windows
==================

Needs Python 3.10 or newer (`python.org <https://www.python.org/downloads/windows/>`_).
The unit tests run on Windows with Python 3.11 to 3.14 on every push.

.. code:: powershell

   git clone https://github.com/danflaviuscioara-max/searxng_windows.git
   cd searxng_windows
   powershell -ExecutionPolicy Bypass -File .\start-searxng.ps1

Then open http://127.0.0.1:8888.  On the first run ``start-searxng.ps1``

- creates a virtual environment in ``.venv`` and installs the requirements
  (again automatically whenever they change),
- creates ``%APPDATA%\searxng\settings.yml`` with a random, permanent secret
  key.  Edit this file to configure SearXNG (see `Configuration guide`_); only
  the values you want to change are needed there,

and then starts SearXNG with `Granian <https://github.com/emmett-framework/granian>`_,
the web server the official SearXNG container uses.  Stop it with ``Ctrl+C``.

Options: ``-Port 9000`` to use another port, ``-BindAddress 0.0.0.0`` to make
SearXNG reachable from other devices in your network, ``-ConfigDir <folder>``
for another settings folder and ``-Update`` to reinstall the requirements.

Valkey (used only by the bot limiter of public instances) is optional and not
needed on a personal instance.

Using SearXNG with AI agents
----------------------------

The settings created by ``start-searxng.ps1`` enable the JSON API
(``/search?q=...&format=json``), which upstream disables by default.  If you
created your ``settings.yml`` before this, add ``json`` to ``search.formats``.

``searxng_mcp/server.py`` is an `MCP <https://modelcontextprotocol.io>`_
server that gives agents such as Claude Code or Claude Desktop two tools:

- ``search``: web search through your local SearXNG.  Returns titles, URLs
  and short snippets.
- ``fetch``: reads the main text of a web page as Markdown, without menus,
  ads and footers (using `Trafilatura <https://trafilatura.readthedocs.io>`_).
  Long pages come in parts (``start`` / ``max_chars``).  HTML and text pages
  only; PDFs, pages that need JavaScript and pages behind a bot check can't be
  read and return an error saying so.  For safety it refuses ``localhost`` and
  private network addresses unless ``SEARXNG_MCP_ALLOW_PRIVATE=1`` is set.

Install its dependencies once:

.. code:: powershell

   .\.venv\Scripts\python.exe -m pip install -r searxng_mcp\requirements.txt

Add it to Claude Code (run in the repository folder, with SearXNG running):

.. code:: powershell

   claude mcp add searxng -- "$PWD\.venv\Scripts\python.exe" "$PWD\searxng_mcp\server.py"

For other MCP clients, run ``.venv\Scripts\python.exe searxng_mcp\server.py``
as a stdio server.  ``SEARXNG_URL`` selects another instance (default
``http://127.0.0.1:8888``).

Keep in mind that the search engines behind SearXNG block heavy automated use
(CAPTCHAs, temporary bans), so an agent that sends many queries in a row will
see fewer results.  Fetched pages are untrusted content; the server tells the
agent to treat instructions inside them as data.

The MCP server has its own offline tests:
``.venv\Scripts\python.exe -m unittest discover -s searxng_mcp -t searxng_mcp``.

Changes from upstream
---------------------

Modified by `danflaviuscioara-max <https://github.com/danflaviuscioara-max>`_, October 2026 (see the git history for full details):

- ``utils/``: renamed the ``*:socket`` templates to ``*@socket``; Windows does
  not allow ``:`` in filenames, so the repository could not be checked out.
- ``searx/valkeydb.py``: removed the Unix-only ``pwd`` / ``os.getuid()`` call.
- ``searx/webutils.py``: result-template and static-file names now use ``/``
  on every OS (fixes "Internal Server Error" on every search).
- ``searx/metrics/error_recorder.py``: engine error paths work with Windows
  ``\`` separators and are reported as ``searx/engines/..``.
- ``searx/network/client.py``: use a ``SelectorEventLoop`` on Windows, which
  curl_cffi needs (removes a warning and an extra thread at startup).
- Added ``searxng_mcp/`` (MCP server with ``search`` and ``fetch`` tools for
  AI agents); the settings created by
  ``start-searxng.ps1`` enable the JSON API.
- Added ``start-searxng.ps1``, the Windows regression tests in
  ``tests/unit/test_windows_compat.py`` and the ``Windows`` GitHub Actions
  workflow.

Upstream changes are merged in regularly from ``searxng/searxng``.

.. image:: https://img.shields.io/badge/organization-3050ff?style=flat-square&logo=searxng&logoColor=fff&cacheSeconds=86400
   :target: https://github.com/searxng
   :alt: Organization

.. image:: https://img.shields.io/badge/documentation-3050ff?style=flat-square&logo=readthedocs&logoColor=fff&cacheSeconds=86400
   :target: https://docs.searxng.org
   :alt: Documentation

.. image:: https://img.shields.io/github/license/searxng/searxng?style=flat-square&label=license&color=3050ff&cacheSeconds=86400
   :target: https://github.com/searxng/searxng/blob/master/LICENSE
   :alt: License

.. image:: https://img.shields.io/github/commit-activity/y/searxng/searxng/master?style=flat-square&label=commits&color=3050ff&cacheSeconds=3600
   :target: https://github.com/searxng/searxng/commits/master/
   :alt: Commits

.. image:: https://img.shields.io/weblate/progress/searxng?server=https%3A%2F%2Ftranslate.codeberg.org&style=flat-square&label=translated&color=3050ff&cacheSeconds=86400
   :target: https://translate.codeberg.org/projects/searxng/
   :alt: Translated

Setup
=====

To install SearXNG, see `Installation guide`_.

To fine-tune SearXNG, see `Configuration guide`_.

Further information on *how-to* can be found `here <https://docs.searxng.org/admin/index.html>`_.

Connect
=======

If you have questions or want to connect with others in the community:

- `#searxng:matrix.org <https://matrix.to/#/#searxng:matrix.org>`_

Contributing
============

See CONTRIBUTING_ for more details.

License
=======

This project is licensed under the GNU Affero General Public License (AGPL-3.0).
See LICENSE_ for more details.

This fork is distributed under the same license.  SearXNG is copyright its
contributors (see ``AUTHORS.rst``); the Windows changes listed above are also
released under AGPL-3.0-or-later.
