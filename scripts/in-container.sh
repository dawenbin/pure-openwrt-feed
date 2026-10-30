#!/bin/bash
# 在编译宿主容器内执行：解开 SDK → 配置 feeds → 编译 → 签名 → 生成索引。
# 由 scripts/build.sh 调用，挂载点约定见那里。
set -euo pipefail

: "${SDK_TARBALL:?}" "${PACKAGES:?}" "${ARCH_PACKAGES:?}" "${KERNEL_DEBUG_SHA256:?}"
export KERNEL_DEBUG_SHA256
SDK=/builder/sdk
APK="$SDK/staging_dir/host/bin/apk"

if [ "${REUSE_SDK:-0}" != 1 ] || [ ! -f "$SDK/rules.mk" ]; then
	echo "=== 解开 SDK ==="
	rm -rf "$SDK"
	mkdir -p "$SDK"
	tar -C "$SDK" --strip-components=1 -xf "/cache/$SDK_TARBALL"
fi
cd "$SDK"

# 下载缓存跨构建复用，里面每个文件都有 hash 校验
rm -rf dl
ln -s /cache/dl dl

# 换成本源的签名密钥。SDK 自带的那把私钥随 SDK 公开发布，不能用来签发布的包
install -m 600 /keys/private-key.pem private-key.pem
install -m 644 /keys/public-key.pem public-key.pem

echo "=== feeds ==="
# base 提供 bpf-headers、ca-bundle，packages 提供 golang 构建框架；
# 两者的提交都取自 SDK 的 feeds.conf.default，其余 feed 用不到
grep -E '^src-git (--root=package )?(base|packages) ' feeds.conf.default > feeds.conf
# 放进 SDK 目录再 link：路径落在 TOPDIR 下时，包元数据的 origin 才是 pure/<包>，
# 而不是容器内绝对路径
rm -rf pure
cp -a /feed/packages pure
echo "src-link pure $SDK/pure" >> feeds.conf
cat feeds.conf
./scripts/feeds update base packages pure
# shellcheck disable=SC2086
./scripts/feeds install -p pure $PACKAGES

echo "=== 配置 ==="
# SDK 默认会开 CONFIG_ALL*（编出全部包）。只选目标包，依赖交给 defconfig 计算
{
	echo '# CONFIG_ALL is not set'
	echo '# CONFIG_ALL_KMODS is not set'
	echo '# CONFIG_ALL_NONSHARED is not set'
	for p in $PACKAGES; do echo "CONFIG_PACKAGE_$p=m"; done
} > .config
make defconfig >/dev/null
grep -q '^CONFIG_SIGNED_PACKAGES=y' .config

if [ "${DOWNLOAD_ONLY:-0}" = 1 ]; then
	for p in $PACKAGES; do make "package/$p/download" V=s; done
	exit 0
fi

if [ "${FIX_HASHES:-0}" = 1 ]; then
	# OpenWrt 官方的 hash 更新方式：Makefile 里写 skip 先下载，再由 check FIXUP 回填
	for p in $PACKAGES; do
		make "package/$p/download" V=s
		make "package/$p/check" FIXUP=1 V=s
		cp -f "pure/$p/Makefile" "/logs/$p.Makefile"
	done
	exit 0
fi

echo "=== 编译（并行度 $(nproc)）==="
for p in $PACKAGES; do
	start=$(date +%s)
	# 顶层必须带 -j，OpenWrt 才会给包设置 PKG_JOBS
	if ! make -j"$(nproc)" "package/$p/compile" V=s > "/logs/build-$p.log" 2>&1; then
		echo "编译 $p 失败，日志 /logs/build-$p.log 末尾："
		tail -60 "/logs/build-$p.log"
		exit 1
	fi
	echo "$p 用时 $(( $(date +%s) - start )) 秒"
	grep -E '^门 [0-9] (通过|失败)' "/logs/build-$p.log" || true
done

echo "=== 收集、签名、索引 ==="
dest="/out/$ARCH_PACKAGES"
mkdir -p "$dest" /out/keys
rm -f "$dest"/*.apk "$dest"/packages.adb
for p in $PACKAGES; do
	cp -v bin/packages/"$ARCH_PACKAGES"/pure/"$p"-[0-9]*.apk "$dest"/
done
# OpenWrt 只签索引；这里给单个包也签上，单独下载的 apk 也能校验来源。
# 必须逐个调用：apk 3.0.5 的 adbsign 传多个文件时只签第一个，且返回 0
for f in "$dest"/*.apk; do
	"$APK" adbsign --allow-untrusted --sign-key private-key.pem "$f"
done
(
	cd "$dest"
	"$APK" mkndx --allow-untrusted --sign-key "$SDK/private-key.pem" \
		--output packages.adb ./*.apk
)
cp public-key.pem /out/keys/pure-openwrt-feed.pem
"$APK" --keys-dir /out/keys verify "$dest"/*.apk "$dest"/packages.adb
ls -l "$dest" /out/keys
