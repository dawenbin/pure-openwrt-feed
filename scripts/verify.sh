#!/usr/bin/env bash
# 验证产物：在临时根目录里用 apk 解析签名索引并安装，确认内核不匹配时装不上。
#
# 用法：scripts/verify.sh --openwrt-version VER [--out DIR] [--work DIR] [--apk PATH]
#                         [--official-key PEM]
#   --openwrt-version  OpenWrt 版本，内核版本与 vermagic 由 scripts/derive.sh 派生
#   --out           build.sh 的产物目录
#   --work          build.sh 的工作目录，默认从中取 SDK 的 apk
#   --apk           apk 可执行文件，给了就不用 --work
#   --official-key  官方签名公钥（文件或目录）。给了才做"连官方源一起装 daed"的完整依赖测试
# 同名环境变量 OPENWRT_VERSION OUT WORK APK OFFICIAL_KEY 亦可。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH=x86_64

OUT="${OUT:-$HOME/build/feed-out}"
WORK="${WORK:-$HOME/build/feed-work}"

while [ $# -gt 0 ]; do
	case "$1" in
		--openwrt-version) OPENWRT_VERSION="$2"; shift 2 ;;
		--out) OUT="$2"; shift 2 ;;
		--work) WORK="$2"; shift 2 ;;
		--apk) APK="$2"; shift 2 ;;
		--official-key) OFFICIAL_KEY="$2"; shift 2 ;;
		*) echo "未知参数: $1"; exit 2 ;;
	esac
done

: "${OPENWRT_VERSION:?需要 --openwrt-version}"
derived="$(bash "$ROOT/scripts/derive.sh" "$OPENWRT_VERSION")"
eval "$derived"
KVER="$KERNEL_VERSION"
OFFICIAL="$BASE_URL"

APK="${APK:-$WORK/sdk/staging_dir/host/bin/apk}"
FEED="$OUT/$ARCH/packages.adb"
FEED_KEY="$(ls "$OUT"/keys/*.pem)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# 伪造的 kernel 包用一次性密钥签，验证不需要碰本源私钥
openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/fake.key" 2>/dev/null
openssl ec -in "$tmp/fake.key" -pubout -out "$tmp/fake.pem" 2>/dev/null
fails=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; fails=$((fails + 1)); }

# 新建一个只信任给定公钥的根目录
newroot() {
	local r="$tmp/$1"; shift
	mkdir -p "$r/etc/apk/keys"
	echo "$ARCH" > "$r/etc/apk/arch"
	for k in "$@"; do cp "$k" "$r/etc/apk/keys/"; done
	"$APK" --root "$r" --usermode add --initdb --no-scripts >/dev/null
	echo "$r"
}
run() { local r="$1"; shift; "$APK" --root "$r" "$@"; }
inst() { local r="$1"; shift; "$APK" --root "$r" --usermode add --no-scripts "$@"; }

# 伪造只有元数据的 kernel 与 libc 包，用于不依赖官方源的版本绑定测试
fake_kernel_repo() {
	local d="$tmp/fake-$1"
	mkdir -p "$d/files"
	"$APK" mkpkg --info "name:kernel" --info "version:$1" --info "arch:$ARCH" 		--info "description:fake" --files "$d/files" --output "$d/kernel-$1.apk" >/dev/null
	"$APK" mkpkg --info "name:libc" --info "version:0-r0" --info "arch:$ARCH" 		--info "description:fake" --files "$d/files" --output "$d/libc-0-r0.apk" >/dev/null
	"$APK" mkndx --allow-untrusted --sign-key "$tmp/fake.key" --output "$d/packages.adb" 		"$d/kernel-$1.apk" "$d/libc-0-r0.apk" >/dev/null
	echo "$d/packages.adb"
}

echo "=== 1 只信任本源公钥：索引可解析，签名有效 ==="
r=$(newroot only-feed "$FEED_KEY")
if run "$r" -X "$FEED" update >/dev/null && run "$r" -X "$FEED" search -v | tee "$tmp/search.txt"; then
	grep -q '^daed-' "$tmp/search.txt" && grep -q '^vmlinux-btf-' "$tmp/search.txt" \
		&& pass "索引含 daed 与 vmlinux-btf" || fail "索引内容不全"
else
	fail "只信任本源公钥时无法读取索引"
fi
"$APK" --keys-dir "$OUT/keys" verify "$OUT/$ARCH"/*.apk >/dev/null \
	&& pass "单个 apk 的签名有效" || fail "apk 签名校验失败"

echo "=== 2 不信任任何公钥：必须拒绝 ==="
r=$(newroot no-key)
if inst "$r" -X "$FEED" vmlinux-btf > "$tmp/nokey.log" 2>&1; then
	fail "未信任公钥却装上了"
elif grep -q 'UNTRUSTED' "$tmp/nokey.log"; then
	pass "未信任公钥时拒绝：$(grep -m1 UNTRUSTED "$tmp/nokey.log")"
else
	fail "失败原因不是签名：$(tail -1 "$tmp/nokey.log")"
fi

echo "=== 3 内核版本匹配：vmlinux-btf 可安装 ==="
r=$(newroot kernel-ok "$FEED_KEY" "$tmp/fake.pem")
good=$(fake_kernel_repo "$KERNEL_PKG_VERSION")
if inst "$r" -X "$good" -X "$FEED" vmlinux-btf >/dev/null \
	&& [ -s "$r/usr/lib/debug/boot/vmlinux-$KVER" ]; then
	pass "kernel=$KERNEL_PKG_VERSION 时安装成功，/usr/lib/debug/boot/vmlinux-$KVER 就位"
else
	fail "内核匹配时安装失败"
fi

echo "=== 4 内核版本不匹配：必须拒绝 ==="
for v in "$KVER~00000000000000000000000000000000-r$KERNEL_RELEASE" \
	"${KVER%.*}.$((${KVER##*.} + 1))~$KERNEL_VERMAGIC-r$KERNEL_RELEASE"; do
	r=$(newroot "kernel-bad-${v%%~*}-${v##*~}" "$FEED_KEY" "$tmp/fake.pem")
	bad=$(fake_kernel_repo "$v")
	inst "$r" -X "$bad" kernel >/dev/null
	if inst "$r" -X "$bad" -X "$FEED" vmlinux-btf > "$tmp/bad.log" 2>&1; then
		fail "kernel=$v 时竟然装上了"
	elif grep -q "kernel-${KVER%.*}\|kernel=" "$tmp/bad.log"; then
		pass "kernel=$v 时拒绝：$(grep -m1 'kernel=' "$tmp/bad.log" | sed 's/^ *//')"
	else
		fail "失败原因不是内核版本：$(tail -3 "$tmp/bad.log")"
	fi
done

if [ -n "${OFFICIAL_KEY:-}" ]; then
	echo "=== 5 连同官方源安装 daed：依赖全部来自官方 + 本源 ==="
	# 可以给单个公钥，也可以给目录（ImageBuilder 的 keys/）
	if [ -d "$OFFICIAL_KEY" ]; then official_keys=("$OFFICIAL_KEY"/*); else official_keys=("$OFFICIAL_KEY"); fi
	r=$(newroot official "$FEED_KEY" "${official_keys[@]}")
	repos=(-X "$OFFICIAL/targets/x86/64/packages/packages.adb"
	       -X "$OFFICIAL/packages/$ARCH/base/packages.adb"
	       -X "$OFFICIAL/targets/x86/64/kmods/$KMOD_DIR/packages.adb"
	       -X "$OFFICIAL/packages/$ARCH/packages/packages.adb"
	       -X "$FEED")
	if inst "$r" "${repos[@]}" kernel daed > "$tmp/official.log" 2>&1; then
		pass "官方内核 + daed 安装成功"
		tail -1 "$tmp/official.log" | sed 's/^/      /'
		[ -x "$r/usr/bin/daed" ] && [ -s "$r/usr/lib/debug/boot/vmlinux-$KVER" ] 			&& pass "daed 与 BTF 文件就位" || fail "文件缺失"
	else
		fail "连同官方源安装 daed 失败"; tail -20 "$tmp/official.log"
	fi
fi

echo "=== 结果：$fails 项失败 ==="
[ "$fails" = 0 ]
