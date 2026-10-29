# SPDX-License-Identifier: AGPL-3.0-or-later
# pylint: disable=missing-module-docstring,disable=missing-class-docstring,invalid-name
"""Regression tests for the fixes of the Windows fork (searxng_windows).

They pass on every OS, but only on Windows (``os.sep == '\\'``) do they catch
the bugs they were written for.
"""

import asyncio
import os
import sys
import unittest
from types import SimpleNamespace

import mock

from searx import searx_parent_dir, settings, valkeydb, webutils
from searx.metrics import error_recorder
from searx.network import client
from tests import SearxTestCase


class TestTemplateAndStaticNames(SearxTestCase):

    def test_result_templates_use_slash(self):
        templates = webutils.get_result_templates(settings['ui']['templates_path'])
        self.assertIn('simple/result_templates/default.html', templates)
        self.assertFalse([t for t in templates if '\\' in t])

    def test_static_files_use_slash(self):
        static_files = webutils.get_static_file_list()
        self.assertIn('themes/simple/sxng-ltr.min.css', static_files)
        self.assertFalse([f for f in static_files if '\\' in f])


class TestErrorRecorderPaths(SearxTestCase):

    @staticmethod
    def _frame(*parts: str):
        return SimpleNamespace(
            filename=os.path.join(searx_parent_dir, *parts),
            function='request',
            lineno=42,
            code_context=['raise ValueError()\n'],
        )

    def test_get_trace_finds_engine_frame(self):
        engine_frame = self._frame('searx', 'engines', 'dummy.py')
        other_frame = self._frame('searx', 'utils.py')
        self.assertIs(error_recorder.get_trace([engine_frame, other_frame]), engine_frame)

    def test_error_context_filename_uses_slash(self):
        frames = [self._frame('searx', 'engines', 'dummy.py')]
        context = error_recorder.get_error_context(frames, 'ValueError', None, (), False)
        self.assertEqual(context.filename, 'searx/engines/dummy.py')


class TestValkeyDB(SearxTestCase):

    def test_initialize_unreachable_does_not_crash(self):
        # used pwd.getpwuid(), which does not exist on Windows
        url = 'valkey://127.0.0.1:1/0?socket_connect_timeout=0.5'
        with mock.patch('searx.valkeydb.get_setting', lambda name: url if name == 'valkey.url' else None):
            with self.assertLogs(valkeydb.logger, level='ERROR'):
                self.assertFalse(valkeydb.initialize())
        self.assertIsNone(valkeydb.client())


class TestNetworkLoop(SearxTestCase):

    @unittest.skipUnless(sys.platform == 'win32', 'Windows only')
    def test_selector_event_loop_on_windows(self):
        # curl_cffi needs add_reader(), which the ProactorEventLoop lacks
        self.assertIsInstance(client.get_loop(), asyncio.SelectorEventLoop)
