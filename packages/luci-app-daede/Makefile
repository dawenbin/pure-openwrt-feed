# SPDX-License-Identifier: Apache-2.0
#
# 来自 kenzok8/openwrt-daede 的 luci-app-daede，钉住的提交和改动见 UPSTREAM.md。
# 上游仓库是 AGPL-3.0，源文件头写 Apache-2.0，两份信息都保留。

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-daede
PKG_VERSION:=1.15
PKG_RELEASE:=1
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

PKG_LICENSE:=AGPL-3.0-only Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=dawenbin

LUCI_TITLE:=LuCI support for daed
LUCI_PKGARCH:=all
LUCI_URL:=https://github.com/kenzok8/openwrt-daede
# 只写进运行依赖：SDK 不必为此编译这些包。curl 给 update-geo.sh 用。
LUCI_EXTRA_DEPENDS:=luci-base (>=0), daed (>=0), curl (>=0)

define Package/luci-app-daede/conffiles
/etc/config/daede
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
