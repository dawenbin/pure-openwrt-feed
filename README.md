# pure-openwrt-feed

自建 OpenWrt apk 源，供 [pure-openwrt](https://github.com/dawenbin/pure-openwrt) 使用。

官方 OpenWrt 源里没有这些包，而设备需要它们，所以在这里定义、构建、签名、托管。
包的构建定义、编译宿主镜像和构建脚本都在本仓库。

## 内容

```text
daed-<ver>-r<n>.apk          daed（dae-wing + dae + 内嵌面板）
luci-app-daede-<ver>-r<n>.apk  LuCI 菜单，语言包 luci-i18n-daede-zh-cn
vmlinux-btf-<kver>-r<n>.apk  官方内核配套的 detached BTF
```

`vmlinux-btf` 依赖 `kernel (=<kver>~<vermagic>-r<n>)`，与官方内核一一绑定，
内核不匹配时 apk 拒绝安装。

发布方式：

```text
gh-pages 分支（Pages）  index.html、公钥、x86_64/ 下的 apk 与签名索引
```

`gh-pages` 每次强推成单个提交，不留历史。每个包保留最近 3 个版本，便于回退
（`apk add daed=<版本>`）。

## 使用

源地址：<https://dawenbin.github.io/pure-openwrt-feed/>

```sh
# 信任本源的签名公钥
wget -O /etc/apk/keys/pure-openwrt-feed.pem \
  https://dawenbin.github.io/pure-openwrt-feed/keys/pure-openwrt-feed.pem
# 添加源
echo https://dawenbin.github.io/pure-openwrt-feed/x86_64/packages.adb \
  >> /etc/apk/repositories.d/customfeeds.list

apk update
apk add daed
```

## 构建

```text
packages/daed/          daed 的打包定义（改编自 ImmortalWrt），取 dae-wing `b089b568`
packages/luci-app-daede/ LuCI 菜单，来自 kenzok8/openwrt-daede 的固定提交，差异见 UPSTREAM.md
packages/vmlinux-btf/   影子内核 + BTF 编码 + 三道一致性门
builder/Dockerfile      编译宿主镜像（Debian 12 + pahole 1.32）
scripts/derive.sh       从 OpenWrt 版本号派生 SDK、内核、vermagic 等全部版本信息
scripts/build.sh        入口：下载校验 SDK → 构建镜像 → 编译 → 签名 → 索引
scripts/bump-daed.sh    更新 daed 版本，hash 由 SDK 的 check FIXUP 重算（daed 上游已归档）
scripts/in-container.sh 容器内步骤
scripts/verify.sh       在临时根目录里用 apk 验证产物
```

```sh
# 需要 docker。目录都由参数给出，参数说明见脚本开头
scripts/build.sh --openwrt-version <版本> --cache DIR --work DIR --key-dir DIR --out DIR
scripts/verify.sh --openwrt-version <版本> --work DIR --out DIR --official-key <官方公钥>
# 产物：<out>/x86_64/ 与 <out>/keys/
```

本仓库不放 workflow，也不挂 runner：构建由私有仓库 pure-openwrt 的流水线在自托管
runner 上调用这些脚本完成，本仓库只保存打包定义与发布结果。packages/ 里的版本更新
由流水线推回 main。

编译用官方 OpenWrt x86/64 SDK，版本号不写死，全部由 OpenWrt 版本派生。SDK、官方
kernel-debug 按官方 sha256sums 校验，内核源码按 SDK 里的 hash 校验，OpenWrt 补丁取自
SDK `feeds.conf.default` 钉的完整提交。

`vmlinux-btf` 的构建会在以下任一情况失败：

1. SDK 自带的 `target/linux` 文件与固定提交不一致
2. 影子内核 `.config` 相对官方有调试信息以外的变化
3. 生成的 BTF 与官方 kernel-debug 中任一可比较结构体的大小或成员偏移不同


## 为什么是公开的

这里只有构建定义、二进制包和索引，**不包含任何凭据**。节点、订阅、面板密码都在设备的
`/etc/daed/wing.db` 里；签名私钥只存在于构建环境。

## 来源与许可

| 包 | 上游 | 许可 |
| --- | --- | --- |
| `daed` | [daeuniverse/dae-wing](https://github.com/daeuniverse/dae-wing) `b089b568` 与 [daeuniverse/daed](https://github.com/daeuniverse/daed) v2.1.1 的前端（均已归档），打包定义改编自 [immortalwrt/packages](https://github.com/immortalwrt/packages)（Copyright (C) 2023 ImmortalWrt.org） | AGPL-3.0；打包定义 GPL-2.0 |
| `luci-app-daede` | [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede)，打包定义改编自 ImmortalWrt（Copyright (C) 2023 ImmortalWrt.org） | 仓库 AGPL-3.0，源文件头 Apache-2.0 |
| `vmlinux-btf` | 由 [OpenWrt](https://github.com/openwrt/openwrt) 的内核源码、补丁与配置生成 | GPL-2.0 |
