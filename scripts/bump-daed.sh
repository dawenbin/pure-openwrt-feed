#!/usr/bin/env bash
# 把 packages/daed/Makefile 更新到指定的 daed 版本：改版本号与 wing 提交，hash 由 SDK 官方的
# check FIXUP 重算（web.zip 与带子模块的源码归档都这样取得）。版本未变时什么都不做。
#
# daed 与 dae-wing 上游已归档，正常不会再有新版本；这里保留是为了上游恢复或换源时仍能自动走通。
# 新版本的 wing 取自该 daed tag 钉的子模块提交，当前钉的 b089b568 比 v2.1.1 的 tag 更新，
# 所以只有版本号真的变化时才会替换。
#
# 用法：scripts/bump-daed.sh <daed 版本，不带 v> <build.sh 的参数…>
#   例：scripts/bump-daed.sh 2.2.0 --openwrt-version 25.12.6 --cache DIR --work DIR --key-dir DIR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MK="$ROOT/packages/daed/Makefile"
VER="${1:?用法: bump-daed.sh <daed 版本> <build.sh 参数…>}"
shift
printf '%s' "$VER" | grep -qE '^[0-9]+(\.[0-9]+)+$' || { echo "daed 版本号异常: $VER"; exit 1; }

cur="$(sed -n 's/^PKG_VERSION:=//p' "$MK")"
if [ "$cur" = "$VER" ] && ! grep -qE '^\s*(PKG_MIRROR_HASH|HASH):=skip$' "$MK"; then
	echo "daed 已是 $VER"
	exit 0
fi

work=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
	[ "${args[$i]}" = --work ] && work="${args[$((i + 1))]}"
done
: "${work:=${WORK:-$HOME/build/feed-work}}"

if [ "$cur" != "$VER" ]; then
	tag="$(mktemp -d)"
	trap 'rm -rf "$tag"' EXIT
	git clone -q --depth 1 -b "v$VER" https://github.com/daeuniverse/daed.git "$tag"
	wing="$(git -C "$tag" ls-tree HEAD wing | awk '{print $3}')"
	printf '%s' "$wing" | grep -qE '^[0-9a-f]{40}$' || { echo "取不到 v$VER 钉的 wing 提交"; exit 1; }
	sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$wing/" "$MK"
fi
sed -i -E \
	-e "s/^PKG_VERSION:=.*/PKG_VERSION:=$VER/" \
	-e "$([ "$cur" = "$VER" ] || echo 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/')" \
	-e 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/' \
	-e 's/^(\s*)HASH:=.*/\1HASH:=skip/' \
	"$MK"
bash "$ROOT/scripts/build.sh" "$@" --packages daed --fix-hashes
cp -f "$work/logs/daed.Makefile" "$MK"

if grep -qE '^\s*(PKG_MIRROR_HASH|HASH):=skip$' "$MK"; then
	echo "hash 未能回填"
	exit 1
fi
grep -nE '^(PKG_VERSION|PKG_RELEASE|PKG_MIRROR_HASH):=|^\s*HASH:=' "$MK"
