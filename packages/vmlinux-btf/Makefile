# SPDX-License-Identifier: GPL-2.0-only
#
# 为官方 OpenWrt 内核补一份 detached BTF，供 CO-RE eBPF 程序（dae）使用。
#
# 官方内核没开 CONFIG_DEBUG_INFO_BTF；kernel-debug 里的 vmlinux 又开了
# CONFIG_DEBUG_INFO_REDUCED，三千多个结构体只有声明，不能直接抽 BTF。
# 所以按官方的源码、补丁和 .config 重编一个"影子内核"，唯一的区别是关掉
# DEBUG_INFO_REDUCED 拿到完整 DWARF，再用 pahole 编码。
#
# 构建里有三道门，任何一道不过包就构建失败：
#   1 SDK 自带的 target/linux 文件必须与固定提交逐字一致
#   2 影子内核 .config 相对官方只允许调试信息类选项变化
#   3 生成的 BTF 与官方 kernel-debug 的 DWARF 布局逐结构体一致
#
# 安装路径 /usr/lib/debug/boot/vmlinux-<release> 沿用 kenzok8/vmlinux-btf 与
# QiuSimons/vmlinux-btf 的约定，是 cilium/ebpf 与 libbpf 的标准查找位置之一。

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/version.mk

PKG_NAME:=vmlinux-btf
PKG_VERSION:=$(LINUX_VERSION)
PKG_RELEASE:=1

# 主源码就是官方内核用的那个 tarball，hash 取自 SDK 的 target/linux/generic/kernel-6.12
PKG_SOURCE:=$(LINUX_SOURCE)
PKG_SOURCE_URL:=$(LINUX_SITE)
PKG_HASH:=$(LINUX_KERNEL_HASH)

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=dawenbin
PKG_BUILD_PARALLEL:=1

# 版本信息一律取自正在使用的 SDK，换 SDK 即换版本，这里没有写死的值。
# SDK 只带了 generic 的三个补丁目录，缺 generic/files 与 x86 的 patches/files，
# 所以完整的 target/linux 从 feeds.conf.default 里 base 的固定提交取。
OPENWRT_COMMIT:=$(shell sed -n 's/^src-git --root=package base .*\^\([0-9a-f]\{40\}\)$$/\1/p' $(TOPDIR)/feeds.conf.default)
OPENWRT_RELEASE:=$(VERSION_NUMBER)

# 官方 sha256sums 里的值，由 scripts/build.sh 经 scripts/derive.sh 取得后传入。
# DUMP 是 SDK 扫描包元数据的阶段，不下载，不需要这些值。
ifeq ($(DUMP),)
  ifeq ($(OPENWRT_COMMIT),)
    $(error feeds.conf.default 里没有 base 的固定提交)
  endif
  ifeq ($(KERNEL_DEBUG_SHA256),)
    $(error 需要 KERNEL_DEBUG_SHA256)
  endif
endif

include $(INCLUDE_DIR)/package.mk

define Package/vmlinux-btf
  SECTION:=kernel
  CATEGORY:=Kernel
  TITLE:=Detached BTF for the official kernel
  URL:=https://github.com/dawenbin/pure-openwrt-feed
  # 与 kmod 同样的写法：内核版本或 vermagic 不同，apk 就拒绝安装
  EXTRA_DEPENDS:=kernel (=$(LINUX_VERSION)~$(LINUX_VERMAGIC)-r$(LINUX_RELEASE))
endef

define Package/vmlinux-btf/description
  Detached kernel BTF for CO-RE eBPF programs on kernels built without
  CONFIG_DEBUG_INFO_BTF. Encoded from a rebuild of the exact official kernel
  (same source, patches and .config, full DWARF) and checked against the
  official kernel-debug layout at build time.
endef

define Download/openwrt-target
  URL:=https://github.com/openwrt/openwrt.git
  PROTO:=git
  SOURCE_VERSION:=$(OPENWRT_COMMIT)
  SUBDIR:=openwrt-$(OPENWRT_COMMIT)
  FILE:=openwrt-$(OPENWRT_COMMIT).tar.zst
  SUBMODULES:=skip
  # 只需要这一个提交的树，不拉全部历史的 blob
  OPTS:=--filter=blob:none --no-checkout
  # 归档 hash 无法预先得知，内容由完整提交号钉死，又经门 1 与 SDK 比对，所以不再校验归档
  MIRROR_HASH:=skip
endef

# 布局门的参照物：官方同版本内核的 vmlinux（带 REDUCED DWARF）
KERNEL_DEBUG_FILE:=openwrt-$(OPENWRT_RELEASE)-$(BOARD)-$(SUBTARGET)-kernel-debug.tar.zst
define Download/kernel-debug
  URL:=https://downloads.openwrt.org/releases/$(OPENWRT_RELEASE)/targets/$(BOARD)/$(SUBTARGET) \
    https://mirror.sjtu.edu.cn/openwrt/releases/$(OPENWRT_RELEASE)/targets/$(BOARD)/$(SUBTARGET)
  URL_FILE:=kernel-debug.tar.zst
  FILE:=$(KERNEL_DEBUG_FILE)
  HASH:=$(KERNEL_DEBUG_SHA256)
endef

OWRT_DIR:=$(PKG_BUILD_DIR)/openwrt-$(OPENWRT_COMMIT)
OWRT_GENERIC:=$(OWRT_DIR)/target/linux/generic
OWRT_TARGET:=$(OWRT_DIR)/target/linux/$(BOARD)
SHADOW_DIR:=$(PKG_BUILD_DIR)/linux-$(LINUX_VERSION)
REF_VMLINUX:=$(PKG_BUILD_DIR)/official/debug/vmlinux
BTF_OUT:=$(PKG_BUILD_DIR)/vmlinux.btf

# 官方构建机没有 pahole，所以官方 .config 里 PAHOLE_VERSION=0。
# 指向不存在的路径让 Kconfig 算出同样的 0；BTF 由下面单独调用 pahole 编码。
SHADOW_MAKE_FLAGS = \
	$(KERNEL_MAKE_FLAGS) \
	KBUILD_HOSTLDFLAGS="-L$(STAGING_DIR_HOST)/lib -lz" \
	PAHOLE=$(PKG_BUILD_DIR)/no-pahole

# 顶层传了 -jN 时 PKG_JOBS 才有值；否则兜底到 nproc，避免内核单线程编译
KERNEL_JOBS:=$(if $(filter -j%,$(PKG_JOBS)),$(PKG_JOBS),-j$(shell nproc))

# 与 6.12 内核 scripts/Makefile.btf 在 pahole >= 1.26 时的参数一致，
# 只是把 link-vmlinux.sh 里的 -J 换成 --btf_encode_detached
BTF_FEATURES:=encode_force,var,float,enum64,decl_tag,type_tag,optimized_func,consistent_func,decl_tag_kfuncs

# 复刻 include/quilt.mk 的 Kernel/Patch/Default：先复制 files，再按
# backport → pending → hack → 平台 的顺序打补丁
define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)/official

	$(TAR) -C $(PKG_BUILD_DIR) -xf $(DL_DIR)/openwrt-$(OPENWRT_COMMIT).tar.zst

	# 门 1：SDK 里有的 target/linux 文件，必须与固定提交逐字一致
	cd $(TOPDIR)/target/linux && find generic $(BOARD) -type f | LC_ALL=C sort > $(PKG_BUILD_DIR)/sdk-files.txt
	while read -r f; do \
		cmp -s "$(TOPDIR)/target/linux/$$$$f" "$(OWRT_DIR)/target/linux/$$$$f" || \
			{ echo "SDK 与 $(OPENWRT_COMMIT) 不一致: target/linux/$$$$f"; exit 1; }; \
	done < $(PKG_BUILD_DIR)/sdk-files.txt
	echo "门 1 通过：SDK 的 $$$$(wc -l < $(PKG_BUILD_DIR)/sdk-files.txt) 个 target/linux 文件与提交一致"

	$(TAR) -C $(PKG_BUILD_DIR) -xf $(DL_DIR)/$(LINUX_SOURCE)
	if [ -d $(OWRT_GENERIC)/patches-$(KERNEL_PATCHVER) ]; then \
		echo "generic/patches-$(KERNEL_PATCHVER) 不应存在"; exit 1; \
	fi
	for d in $(OWRT_GENERIC)/files $(OWRT_GENERIC)/files-$(KERNEL_PATCHVER) \
		 $(OWRT_TARGET)/files $(OWRT_TARGET)/files-$(KERNEL_PATCHVER); do \
		[ ! -d "$$$$d" ] || $(CP) "$$$$d/." $(SHADOW_DIR)/; \
	done
	find $(SHADOW_DIR)/ -name \*.rej -or -name \*.orig | $(XARGS) rm -f
	$(call PatchDir/Default,$(SHADOW_DIR),$(OWRT_GENERIC)/backport-$(KERNEL_PATCHVER),generic-backport/)
	$(call PatchDir/Default,$(SHADOW_DIR),$(OWRT_GENERIC)/pending-$(KERNEL_PATCHVER),generic/)
	$(call PatchDir/Default,$(SHADOW_DIR),$(OWRT_GENERIC)/hack-$(KERNEL_PATCHVER),generic-hack/)
	$(call PatchDir/Default,$(SHADOW_DIR),$(OWRT_TARGET)/patches-$(KERNEL_PATCHVER),platform/)

	zstd -dc $(DL_DIR)/$(KERNEL_DEBUG_FILE) | \
		$(TAR) -C $(PKG_BUILD_DIR)/official -x --wildcards '*debug/vmlinux'
	test -s $(REF_VMLINUX)
endef

# 门 2：只关 DEBUG_INFO_REDUCED，olddefconfig 后除调试信息类选项外不许有任何变化
define Build/Configure
	$(CP) $(LINUX_DIR)/.config $(SHADOW_DIR)/.config.official
	$(CP) $(LINUX_DIR)/.config $(SHADOW_DIR)/.config
	$(SHADOW_DIR)/scripts/config --file $(SHADOW_DIR)/.config --disable DEBUG_INFO_REDUCED
	$(MAKE) -C $(SHADOW_DIR) $(SHADOW_MAKE_FLAGS) olddefconfig
	python3 $(CURDIR)/scripts/kconfig-gate.py $(SHADOW_DIR)/.config.official $(SHADOW_DIR)/.config
endef

define Build/Compile
	$(MAKE) -C $(SHADOW_DIR) $(SHADOW_MAKE_FLAGS) $(KERNEL_JOBS) vmlinux

	grep -qF -- '--btf_features=$(BTF_FEATURES)' $(SHADOW_DIR)/scripts/Makefile.btf
	grep -qF -- '--lang_exclude=rust' $(SHADOW_DIR)/scripts/Makefile.btf
	test "$$$$(pahole --numeric_version)" -ge 126
	pahole -j --btf_features=$(BTF_FEATURES) --lang_exclude=rust \
		--btf_encode_detached=$(BTF_OUT) $(SHADOW_DIR)/vmlinux

	# 门 3：两边都有完整定义的 struct/union，大小与成员偏移必须一致
	pahole -F dwarf --suppress_aligned_attribute $(REF_VMLINUX) > $(PKG_BUILD_DIR)/layout-official.txt
	pahole -F btf --suppress_aligned_attribute $(BTF_OUT) > $(PKG_BUILD_DIR)/layout-btf.txt
	python3 $(CURDIR)/scripts/layout-gate.py \
		$(PKG_BUILD_DIR)/layout-official.txt $(PKG_BUILD_DIR)/layout-btf.txt
endef

define Build/Clean
	rm -rf $(PKG_BUILD_DIR)
endef

# 包与内核一一绑定，uname -r 必然等于 LINUX_VERSION，直接装成目标文件名，
# 不需要 postinst 再做软链
define Package/vmlinux-btf/install
	$(INSTALL_DIR) $(1)/usr/lib/debug/boot
	$(INSTALL_DATA) $(BTF_OUT) $(1)/usr/lib/debug/boot/vmlinux-$(LINUX_VERSION)
endef

$(eval $(call Download,openwrt-target))
$(eval $(call Download,kernel-debug))
$(eval $(call BuildPackage,vmlinux-btf))
