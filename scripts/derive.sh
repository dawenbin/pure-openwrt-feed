#!/usr/bin/env bash
# 从 OpenWrt 发布目录派生构建所需的全部版本信息，输出 KEY=value，可直接 source。
#
# 用法：scripts/derive.sh <OpenWrt 版本> [--with-commit]
#
#   SDK_TARBALL、SDK_SHA256、KERNEL_DEBUG_SHA256   取自 sha256sums
#   KERNEL_VERSION、KERNEL_VERMAGIC、KERNEL_RELEASE 取自官方 manifest 的 kernel 包
#   KERNEL_PKG_VERSION、KMOD_DIR                    由上面拼出
#   BASE_URL                                        本次实际可达的发布目录
#   OPENWRT_COMMIT   加 --with-commit 才给：流式读 SDK 里的 feeds.conf.default。
#                    构建时 Makefile 直接读解开的 SDK，这里只用于预检与 dry-run。
#
# 官方站 TLS 不稳定，所以每个文件都先重试官方，再回退镜像。
set -euo pipefail

VERSION="${1:?用法: derive.sh <OpenWrt 版本> [--with-commit]}"
WITH_COMMIT="${2:-}"
MIRRORS="${MIRRORS:-https://downloads.openwrt.org https://mirror.sjtu.edu.cn/openwrt}"
REL="releases/$VERSION/targets/x86/64"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { # fetch <发布目录下的文件名> <目标>；成功时在 stdout 打印所用站点
	local m
	for m in $MIRRORS; do
		if curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 --max-time 180 \
			-o "$2" "$m/$REL/$1"; then
			echo "$m"
			return 0
		fi
	done
	echo "取不到 $REL/$1" >&2
	return 1
}

site="$(fetch sha256sums "$tmp/sums")"
fetch "openwrt-$VERSION-x86-64.manifest" "$tmp/manifest" >/dev/null

sum_of() { sed -n "s/^\([0-9a-f]\{64\}\) \*$1\$/\1/p" "$tmp/sums"; }
sdk="$(sed -n "s/^[0-9a-f]\{64\} \*\(openwrt-sdk-$VERSION-x86-64_gcc-[^ ]*_musl\.Linux-x86_64\.tar\.zst\)\$/\1/p" "$tmp/sums")"
[ "$(echo "$sdk" | grep -c .)" = 1 ] || { echo "sha256sums 里找不到唯一的 SDK" >&2; exit 1; }
sdk_sha="$(sum_of "$sdk")"
kdbg_sha="$(sum_of 'kernel-debug\.tar\.zst')"
[ -n "$sdk_sha" ] && [ -n "$kdbg_sha" ] || { echo "sha256sums 缺 SDK 或 kernel-debug" >&2; exit 1; }

# 形如 kernel - 6.12.112~b4125196ecec75391093e1e2edeba490-r1
kpkg="$(sed -n 's/^kernel - //p' "$tmp/manifest")"
kver="${kpkg%%~*}"
rest="${kpkg#*~}"
vermagic="${rest%-r*}"
krel="${rest##*-r}"
printf '%s' "$kver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "manifest 里的内核版本异常: $kpkg" >&2; exit 1; }
printf '%s' "$vermagic" | grep -qE '^[0-9a-f]{32}$' || { echo "manifest 里的 vermagic 异常: $kpkg" >&2; exit 1; }

cat <<EOF
OPENWRT_VERSION=$VERSION
BASE_URL=$site/releases/$VERSION
SDK_TARBALL=$sdk
SDK_SHA256=$sdk_sha
KERNEL_DEBUG_SHA256=$kdbg_sha
KERNEL_VERSION=$kver
KERNEL_VERMAGIC=$vermagic
KERNEL_RELEASE=$krel
KERNEL_PKG_VERSION=$kpkg
KMOD_DIR=$kver-$krel-$vermagic
EOF

if [ "$WITH_COMMIT" = --with-commit ]; then
	# tar 读到目标文件即退出（--occurrence），不必下完整个 SDK；curl 随之收到 SIGPIPE，
	# 所以不能用 curl 的 --retry，在外层重试。
	commit=""
	for _ in 1 2 3 4 5; do
		feeds="$(set +o pipefail
			curl -fsSL --connect-timeout 15 "$site/$REL/$sdk" 2>/dev/null |
				zstd -dc 2>/dev/null |
				tar -xO --wildcards --occurrence=1 '*/feeds.conf.default' 2>/dev/null)" || true
		commit="$(echo "$feeds" | sed -n 's/^src-git --root=package base .*\^\([0-9a-f]\{40\}\)$/\1/p')"
		[ -z "$commit" ] || break
	done
	[ -n "$commit" ] || { echo "SDK 的 feeds.conf.default 里没有 base 的固定提交" >&2; exit 1; }
	echo "OPENWRT_COMMIT=$commit"
fi
