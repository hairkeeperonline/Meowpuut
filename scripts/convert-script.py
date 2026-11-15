#!/usr/bin/env python3
"""Windows 上 scripts/ConvertScript.swift 的等价替代品。

ConvertScript.swift 用 macOS Foundation 的 `Traditional-Simplified` 字符串变换，
从 stdin 逐行读入、逐行输出，供 compile-native-lexicon.py 做简繁转换：

    converter            # 繁体 -> 简体
    converter --traditional   # 简体 -> 繁体

这里用 OpenCC 实现同样的行为，保证「输入行数 == 输出行数」。
"""
import sys

from opencc import OpenCC


def main() -> int:
    traditional = "--traditional" in sys.argv[1:]
    cc = OpenCC("s2t" if traditional else "t2s")
    for line in sys.stdin:
        text = line.rstrip("\n")
        sys.stdout.write(cc.convert(text) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
