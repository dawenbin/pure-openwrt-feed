#!/usr/bin/env bash
# 本地/CI 构建入口：下载并校验官方 SDK → 构建编译宿主镜像 → 容器内编译、签名、出索引。
#
# 本仓库不放 workflow，由外部（pure-openwrt 的流水线）以参数方式调用。
#
# 用法：scripts/build.sh --openwrt-version VER [--cache DIR] [--work DIR] [--key-dir DIR]
#                        [--out DIR] [--packages "a b"] [--download-only] [--reuse-sdk]
#                        [--fix-hashes]
#
#   --openwrt-version  OpenWrt 版本，其余版本信息全部由 scripts/derive.sh 派生
#   --cache     SDK tarball 与 dl/ 下载缓存，跨构建复用
#   --work      SDK 解压与编译目录、构建日志
#   --key-dir   private-key.pem / public-key.pem，apk v3 签名密钥（ECDSA prime256v1）
#   --out       产物：<out>/<arch>/{packages.adb,*.apk}，<out>/keys/*.pem
#   --packages  只构建这些包
#   --download-only  只下载并校验源码
#   --reuse-sdk      沿用 work 里已解开的 SDK（调试用）
#   --fix-hashes     不编译：下载后用 SDK 的 check FIXUP 重算 hash，
#                    修正后的 Makefile 写到 <work>/logs/<包>.Makefile（scripts/bump-daed.sh 用）
#
# 各项也可用同名环境变量给出（OPENWRT_VERSION CACHE WORK KEY_DIR OUT PACKAGES
# DOWNLOAD_ONLY REUSE_SDK FIX_HASHES）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TARGET=x86/64
ARCH_PACKAGES=x86_64

PACKAGES="${PACKAGES:-vmlinux-btf daed luci-app-daede}"
CACHE="${CACHE:-$HOME/build/feed-cache}"
WORK="${WORK:-$HOME/build/feed-work}"
KEY_DIR="${KEY_DIR:-$HOME/build/feed-keys}"
OUT="${OUT:-$HOME/build/feed-out}"

while [ $# -gt 0 ]; do
	case "$1" in
		--openwrt-version) OPENWRT_VERSION="$2"; shift 2 ;;
		--cache) CACHE="$2"; shift 2 ;;
		--work) WORK="$2"; shift 2 ;;
		--key-dir) KEY_DIR="$2"; shift 2 ;;
		--out) OUT="$2"; shift 2 ;;
		--packages) PACKAGES="$2"; shift 2 ;;
		--download-only) DOWNLOAD_ONLY=1; shift ;;
		--reuse-sdk) REUSE_SDK=1; shift ;;
		--fix-hashes) FIX_HASHES=1; shift ;;
		*) echo "未知参数: $1"; exit 2 ;;
	esac
done

: "${OPENWRT_VERSION:?需要 --openwrt-version}"
for f in private-key.pem public-key.pem; do
	[ -s "$KEY_DIR/$f" ] || { echo "缺少签名密钥 $KEY_DIR/$f"; exit 1; }
done
mkdir -p "$CACHE/dl" "$WORK/logs" "$OUT"

# 第三方文件必须与钉住的提交一致
(cd "$ROOT/packages/luci-app-daede" && sha256sum -c --quiet UPSTREAM.sha256)

derived="$(bash "$ROOT/scripts/derive.sh" "$OPENWRT_VERSION")"
echo "$derived"
eval "$derived"

sdk="$CACHE/$SDK_TARBALL"
if ! echo "$SDK_SHA256  $sdk" | sha256sum -c --quiet 2>/dev/null; then
	rm -f "$sdk"
	for m in ${BASE_URL%/releases/*} https://downloads.openwrt.org https://mirror.sjtu.edu.cn/openwrt; do
		url="$m/releases/$OPENWRT_VERSION/targets/$TARGET/$SDK_TARBALL"
		echo "下载 $url"
		curl -fsSL --retry 5 --retry-all-errors -o "$sdk.part" "$url" && break || true
	done
	mv "$sdk.part" "$sdk"
	echo "$SDK_SHA256  $sdk" | sha256sum -c
fi
# 旧版本的 SDK 不再有用
find "$CACHE" -maxdepth 1 -name 'openwrt-sdk-*' ! -name "$SDK_TARBALL" -delete

# 镜像 tag 跟随 Dockerfile 内容，Dockerfile 一改就重建
image="pure-openwrt-feed-builder:$(sha256sum "$ROOT/builder/Dockerfile" | cut -c1-12)"
# Docker Hub 与 apt 源偶尔断连，重试整个构建，已完成的层有缓存
if ! docker image inspect "$image" >/dev/null 2>&1; then
	for attempt in 1 2 3 4 5; do
		docker build -t "$image" "$ROOT/builder" && break
		[ "$attempt" = 5 ] && { echo "构建宿主镜像失败"; exit 1; }
		sleep 30
	done
fi

start=$(date +%s)
docker run --rm \
	-v "$ROOT:/feed:ro" \
	-v "$CACHE:/cache" \
	-v "$WORK:/builder" \
	-v "$WORK/logs:/logs" \
	-v "$KEY_DIR:/keys:ro" \
	-v "$OUT:/out" \
	-e SDK_TARBALL="$SDK_TARBALL" \
	-e KERNEL_DEBUG_SHA256="$KERNEL_DEBUG_SHA256" \
	-e PACKAGES="$PACKAGES" \
	-e ARCH_PACKAGES="$ARCH_PACKAGES" \
	-e REUSE_SDK="${REUSE_SDK:-0}" \
	-e DOWNLOAD_ONLY="${DOWNLOAD_ONLY:-0}" \
	-e FIX_HASHES="${FIX_HASHES:-0}" \
	"$image" bash /feed/scripts/in-container.sh
echo "总用时 $(( $(date +%s) - start )) 秒"
