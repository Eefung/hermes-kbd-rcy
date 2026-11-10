#!/usr/bin/env python3
"""kbdprobe 应答解析的单元测试。

不依赖 pty、不碰真实终端，可在 CI 里跑：python3 -m unittest discover -s tests
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import kbdprobe  # noqa: E402  路径依赖导入，放在 sys.path 调整之后


class ParseFlagsTest(unittest.TestCase):
    def test_zero(self):
        self.assertEqual(kbdprobe.parse_flags(b'\x1b[?0u'), 0)

    def test_nonzero(self):
        self.assertEqual(kbdprobe.parse_flags(b'\x1b[?1u'), 1)

    def test_multi_digit(self):
        self.assertEqual(kbdprobe.parse_flags(b'\x1b[?31u'), 31)

    def test_no_reply(self):
        self.assertIsNone(kbdprobe.parse_flags(b''))

    def test_garbage_around(self):
        self.assertEqual(kbdprobe.parse_flags(b'abc\x1b[?0udef'), 0)

    def test_first_reply_wins(self):
        self.assertEqual(kbdprobe.parse_flags(b'\x1b[?1u\x1b[?0u'), 1)

    def test_plain_text_ignored(self):
        self.assertIsNone(kbdprobe.parse_flags(b'no reply here'))


if __name__ == '__main__':
    unittest.main()
