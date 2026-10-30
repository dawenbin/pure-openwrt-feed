# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 ImmortalWrt.org
#
# 改编自 immortalwrt/packages net/daed。与上游的差异：
#
#   1 daed 与 dae-wing 上游都已归档。daed v2.1.1 这个 tag 钉的 wing 是 dc503088，这里直接取
#     wing 的最后提交 b089b568（dae-core v2.1.1 与面板流量统计修复），子模块随之取得。
#     patches/ 只有 dae 上游修复 6f2f2aa 的回移：v2.1.1 去掉了 wing 要用的 Marshaller.Bytes。
#     wing 的 GraphQL 相对 dc503088 只增不减，所以前端仍用 v2.1.1 的 web.zip。
#     版本号沿用 2.1.1，靠 PKG_RELEASE 让 apk 从 2.1.1-r1 升级。
#     版本、wing 提交与两处 hash 由 scripts/bump-daed.sh 更新，不手改
#   2 去掉 +kmod-xdp-sockets-diag：官方 OpenWrt x86/64 没有这个 kmod（ImmortalWrt 才有），
#     保留它 apk 会因依赖无法解析而拒绝安装；dae 运行时也不需要它
#   3 加上 vmlinux-btf：dae 的 CO-RE eBPF 必须有内核 BTF，官方内核没有
#     /sys/kernel/btf/vmlinux，只能由本源的 vmlinux-btf 提供。写进 EXTRA_DEPENDS，
#     编 daed 时不必连带重编影子内核
#   4 不拆 daed-geoip / daed-geosite 子包：dae 的 geoip:/geosite: 规则缺 .dat 就拒绝加载配置，
#     直接依赖官方 v2ray-geoip、v2ray-geosite，并把 /usr/share/daed 下的路径链到 /usr/share/v2ray。
#     用 EXTRA_DEPENDS 只写进运行依赖，SDK 不必为此编译 geodata（官方源已有现成包）
#   5 golang-package.mk 用绝对路径：本包作为独立 feed 安装，不在 packages feed 的 net/ 下
#   6 files/：enabled 默认 1，装上即启动
#
# dae 只在两处调用外部命令：netkit 创建失败时回退到 ip(8)（官方内核未开
# CONFIG_NETKIT，实际走 veth，不会执行到），以及 sysdump 诊断命令。qdisc、
# 路由、链路都经 netlink 完成，所以不依赖 ip-full / tc-full / ipset。

include $(TOPDIR)/rules.mk

PKG_NAME:=daed
PKG_VERSION:=2.1.1
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/daeuniverse/dae-wing.git
PKG_SOURCE_VERSION:=b089b568649f03f909477adb6c7db25535a58782
PKG_SOURCE:=daed-wing-$(PKG_SOURCE_VERSION).tar.zst
PKG_MIRROR_HASH:=9e7821ee1f00d0cbe840b61d792bfc9c2c72ed445a6f7fe3e1ab98c4d8b3fde6

PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=dawenbin

PKG_BUILD_DIR=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=golang/host bpf-headers
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/daeuniverse/dae-wing
GO_PKG_LDFLAGS:= \
	-X '$(GO_PKG)/db.AppDescription=$(PKG_NAME) is a integration solution of dae, API and UI.'
GO_PKG_LDFLAGS_X= \
	$(GO_PKG)/db.AppName=$(PKG_NAME) \
	$(GO_PKG)/db.AppVersion=$(PKG_VERSION)
GO_PKG_TAGS:=embedallowed,trace

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/bpf.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

TAR_CMD=$(HOST_TAR) -C $(BUILD_DIR)/ $(TAR_OPTIONS)

define Package/daed/Default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  URL:=https://github.com/daeuniverse/daed
endef

define Package/daed
  $(call Package/daed/Default)
  TITLE:=A Modern Dashboard For dae
  DEPENDS:=$(GO_ARCH_DEPENDS) $(BPF_DEPENDS) \
    +ca-bundle +kmod-sched-core +kmod-sched-bpf +kmod-veth
  EXTRA_DEPENDS:=vmlinux-btf (>=0), v2ray-geoip (>=0), v2ray-geosite (>=0)
endef

define Package/daed/description
  daed is a backend of dae, provides a method to bundle arbitrary
  frontend, dae and geodata into one binary.
endef

define Package/daed/conffiles
/etc/daed/wing.db
/etc/config/daed
endef

WEB_FILE:=$(PKG_NAME)-web-$(PKG_VERSION).zip
define Download/daed-web
	URL:=https://github.com/daeuniverse/daed/releases/download/v$(PKG_VERSION)
	URL_FILE:=web.zip
	FILE:=$(WEB_FILE)
	HASH:=7eb8f42d4860ab7311f87bda2a921bad34a6d54db7edad47466dcb8d9382fea8
endef

define Build/Prepare
	$(call Build/Prepare/Default)

	( \
		mkdir -p $(PKG_BUILD_DIR)/webrender ; \
		unzip -q -d $(PKG_BUILD_DIR)/webrender/ $(DL_DIR)/$(WEB_FILE) ; \
		find $(PKG_BUILD_DIR)/webrender/web -type f -size +4k ! -name "*.gz" ! -name "*.woff"  ! -name "*.woff2" -exec sh -c '\
			gzip -9 -k "{}"; \
			if [ "$$$$(stat -c %s "{}")" -lt "$$$$(stat -c %s "{}.gz")" ]; then \
				rm "{}.gz"; \
			else \
				rm "{}"; \
			fi' \
		";" ; \
	)
endef

DAE_CFLAGS:= \
	-O2 -Wall -Werror \
	-DMAX_MATCH_SET_LEN=1024 \
	-I$(BPF_HEADERS_DIR)/tools/lib \
	-I$(BPF_HEADERS_DIR)/arch/$(BPF_KARCH)/include/asm/mach-generic

ifneq ($(CONFIG_USE_MUSL),)
  TARGET_CFLAGS += -D_LARGEFILE64_SOURCE
endif

define Build/Compile
	( \
		pushd $(PKG_BUILD_DIR) ; \
		export \
		$(GO_GENERAL_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_VARS) ; \
		go generate ./... ; \
		cd dae-core ; \
		export \
		BPF_CLANG="$(CLANG)" \
		BPF_STRIP_FLAG="-strip=$(LLVM_STRIP)" \
		BPF_CFLAGS="$(DAE_CFLAGS)" \
		BPF_TARGET="bpfel,bpfeb" \
		BPF_TRACE_TARGET="$(GO_ARCH)" ; \
		go generate control/control.go ; \
		go generate trace/trace.go ; \
		popd ; \
		$(call GoPackage/Build/Compile) ; \
	)
endef

define Package/daed/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/dae-wing $(1)/usr/bin/daed

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/daed.config $(1)/etc/config/daed

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/daed.init $(1)/etc/init.d/daed

	$(INSTALL_DIR) $(1)/usr/share/daed
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/daed/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/daed/geosite.dat
endef

$(eval $(call Download,daed-web))
$(eval $(call GoBinPackage,daed))
$(eval $(call BuildPackage,daed))
