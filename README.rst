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

Tested on Windows 11 with Python 3.13.  All 359 unit tests pass.

.. code:: powershell

   git clone https://github.com/danflaviuscioara-max/searxng_windows.git
   cd searxng_windows
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt -r requirements-server.txt
   $env:SEARXNG_SECRET = [guid]::NewGuid().ToString('N')
   .\.venv\Scripts\python.exe -m searx.webapp

Then open http://127.0.0.1:8888.  This starts the built-in development server,
which is fine for personal use on your own machine.  To make the secret key
permanent, set ``server.secret_key`` in your settings file instead of the
environment variable (see `Configuration guide`_).

Valkey (used only by the bot limiter) is optional; leave ``valkey.url`` unset
on a personal instance.

Changes from upstream
---------------------

Modified by `danflaviuscioara-max <https://github.com/danflaviuscioara-max>`_, October 2026 (see the git history for full details):

- ``utils/``: renamed the ``*:socket`` templates to ``*@socket``; Windows does
  not allow ``:`` in filenames, so the repository could not be checked out.
- ``searx/valkeydb.py``: removed the Unix-only ``pwd`` / ``os.getuid()`` call.
- ``searx/webutils.py``: result-template and static-file names now use ``/``
  on every OS (fixes "Internal Server Error" on every search).
- ``searx/metrics/error_recorder.py``: engine error paths work with Windows
  ``\`` separators.

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
