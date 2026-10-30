#!/usr/bin/env python3
# 门 2：影子内核 .config 相对官方 .config 只允许调试信息类选项变化。
# 结构体布局由 .config 决定，多开或少开一个非调试选项都可能让 BTF 与官方内核错位。
#
# 用法：kconfig-gate.py <官方 .config> <影子 .config>
import re
import sys

# 只改 DEBUG_INFO_REDUCED，olddefconfig 可能连带的也只会是这几类
ALLOWED = re.compile(r'^CONFIG_(DEBUG_INFO(_\w+)?|PAHOLE_\w+|GDB_SCRIPTS)$')

LINE_SET = re.compile(r'^(CONFIG_\w+)=(.*)$')
LINE_UNSET = re.compile(r'^# (CONFIG_\w+) is not set$')


def load(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip('\n')
            m = LINE_SET.match(line)
            if m:
                out[m.group(1)] = m.group(2)
                continue
            m = LINE_UNSET.match(line)
            if m:
                out[m.group(1)] = 'n'
    return out


def main():
    official, shadow = load(sys.argv[1]), load(sys.argv[2])
    changed = sorted(k for k in set(official) | set(shadow)
                     if official.get(k) != shadow.get(k))
    bad = [k for k in changed if not ALLOWED.match(k)]

    for k in changed:
        mark = '  ' if ALLOWED.match(k) else '!!'
        print(f'{mark} {k}: {official.get(k, "(无)")} -> {shadow.get(k, "(无)")}')

    if shadow.get('CONFIG_DEBUG_INFO') != 'y' or shadow.get('CONFIG_DEBUG_INFO_REDUCED', 'n') != 'n':
        print('门 2 失败：没有得到完整 DWARF（DEBUG_INFO=y 且 DEBUG_INFO_REDUCED 关闭）')
        return 1
    if bad:
        print(f'门 2 失败：{len(bad)} 个非调试信息选项与官方不同')
        return 1
    print(f'门 2 通过：共 {len(official)} 个符号，变化 {len(changed)} 个，均为调试信息类')
    return 0


if __name__ == '__main__':
    sys.exit(main())
