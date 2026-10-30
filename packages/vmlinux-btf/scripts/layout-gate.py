#!/usr/bin/env python3
# 门 3：生成的 BTF 必须与官方内核的真实布局一致。
#
# 输入是两份 pahole 文本输出：
#   官方 kernel-debug 的 vmlinux：pahole -F dwarf --suppress_aligned_attribute
#   影子内核编出的 BTF：         pahole -F btf   --suppress_aligned_attribute
#
# 比较对象：两边都有完整定义的具名 struct/union。比较结构体大小，以及按顺序的
# 每个成员（含匿名 struct/union 内展开的成员）的名字、字节偏移、位偏移。
# 不比成员大小：官方 DWARF 开了 REDUCED，只有声明的类型成员大小会显示为 0。
#
# 同名结构体：不同驱动可以各自定义同名的局部结构体（例如 urb_priv），pahole 会
# 把每个变体都打印出来。所以按名字收集"布局集合"，要求官方的每个变体都能在 BTF
# 里找到完全相同的一份。官方只出现部分变体是 REDUCED 造成的，不算差异。
#
# 用法：layout-gate.py <官方.txt> <btf.txt>
import re
import sys
from collections import defaultdict

HEAD = re.compile(r'^(struct|union) (\w+) \{')
# 成员行以 "/* 偏移[:位偏移] 大小 */" 结尾
MEMBER = re.compile(r';\s*/\*\s*(\d+)(?::\s*(\d+))?\s+(\d+)\s*\*/\s*$')
SIZE = re.compile(r'/\* size: (\d+),')
FUNC_PTR = re.compile(r'\(\s*\*\s*(\w+)\s*\)')
PLAIN = re.compile(r'(\w+)\s*(?:\[[^\]]*\]\s*)*(?::\s*\d+\s*)?;')

# 这些是 dae 一定会通过 CO-RE 访问的，必须在比较范围内，防止解析失效时空跑通过
# （task_struct、net_device 等在官方 REDUCED DWARF 里只有声明，无法纳入比较）
MUST_COVER = ['struct sk_buff', 'struct sock', 'struct sock_common', 'struct tcp_sock',
              'struct tcphdr', 'struct udphdr', 'struct socket', 'struct msghdr',
              'struct pt_regs', 'struct bpf_sock_ops_kern']
MIN_COMMON = 3000


def member_name(decl):
    """取成员名；匿名 struct/union 的收尾行 '};' 记为空名。"""
    decl = decl.strip()
    if decl.startswith('}') and re.fullmatch(r'\}\s*;', decl):
        return ''
    m = FUNC_PTR.search(decl)
    if m:
        return m.group(1)
    m = PLAIN.search(decl)
    return m.group(1) if m else '?'


def parse(path):
    layouts = defaultdict(set)
    cur = None
    with open(path, errors='replace') as f:
        for line in f:
            if cur is None:
                m = HEAD.match(line)
                if m:
                    cur, depth, size, members = f'{m.group(1)} {m.group(2)}', 1, None, []
                continue
            depth += line.count('{') - line.count('}')
            if depth <= 0:
                # pahole 不给 union 打印 size 行，此时只比成员
                layouts[cur].add((size, tuple(members)))
                cur = None
                continue
            m = SIZE.search(line)
            if m and depth == 1:
                size = int(m.group(1))
                continue
            m = MEMBER.search(line)
            if m:
                decl = line[:m.start() + 1]
                members.append((member_name(decl), int(m.group(1)), int(m.group(2) or 0)))
    return layouts


def describe(a, b):
    """给出两个布局之间的前几个差异，便于定位。"""
    lines = [f'      size: 官方={a[0]} BTF={b[0]}']
    for i, (x, y) in enumerate(zip(a[1], b[1])):
        if x != y:
            lines.append(f'      #{i} 官方={x} BTF={y}')
            if len(lines) > 4:
                break
    if len(a[1]) != len(b[1]):
        lines.append(f'      成员数: 官方={len(a[1])} BTF={len(b[1])}')
    return '\n'.join(lines)


def main():
    official, btf = parse(sys.argv[1]), parse(sys.argv[2])
    common = sorted(set(official) & set(btf))
    bad = [k for k in common if not official[k] <= btf[k]]
    multi = [k for k in common if k not in bad and (len(official[k]) > 1 or len(btf[k]) > 1)]
    missing = [k for k in MUST_COVER if k not in common]

    print(f'官方有完整定义: {len(official)}  BTF: {len(btf)}  两边都有: {len(common)}')
    print(f'布局一致: {len(common) - len(bad)}  布局不一致: {len(bad)}')
    if multi:
        print(f'同名多定义 {len(multi)} 个，官方的每个变体都在 BTF 中找到了完全相同的一份：')
        for k in multi:
            print(f'  {k}: 官方 {len(official[k])} 个变体，BTF {len(btf[k])} 个变体')
    for k in bad:
        print(f'  不一致 {k}')
        for a in sorted(official[k] - btf[k]):
            b = min(btf[k], key=lambda v: (v[0] != a[0], sum(x != y for x, y in zip(a[1], v[1]))))
            print(describe(a, b))

    if missing or len(common) < MIN_COMMON:
        print(f'门 3 失败：比较范围异常（共同 {len(common)} 个，缺少 {missing}），解析可能失效')
        return 1
    if bad:
        print('门 3 失败')
        return 1
    print('门 3 通过：0 差异')
    return 0


if __name__ == '__main__':
    sys.exit(main())
