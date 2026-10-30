# openwrt-pkgs

自建 OpenWrt apk 源，供 [pure-openwrt](https://github.com/dawenbin/pure-openwrt) 使用。

官方 OpenWrt 源里没有这两个包，而设备又需要它们，所以自己编、自己签名、自己托管。

## 内容

```text
x86_64/packages.adb                    apk 索引
x86_64/daed-<ver>-r1-x86_64.apk        daed（含 dae-wing 与内嵌面板）
x86_64/vmlinux-btf-<kver>-r1-x86_64.apk 为官方内核配套的 BTF
```

`vmlinux-btf` 的版本号与内核版本一一对应，历史版本全部保留，便于回退。

## 使用

在设备的 `/etc/apk/repositories` 里加一行：

```sh
https://dawenbin.github.io/openwrt-pkgs/x86_64
```

然后：

```sh
apk update
apk upgrade daed
```

## 为什么是公开的

这里只有二进制包和索引，**不包含任何凭据**。节点、订阅、面板密码都在设备的
`/etc/daed/wing.db` 里，不会进入这个仓库。

## 来源与许可

| 包 | 上游 | 许可 |
| --- | --- | --- |
| `daed` | [daeuniverse/daed](https://github.com/daeuniverse/daed) | AGPL-3.0 |
| `vmlinux-btf` | 由 [OpenWrt](https://github.com/openwrt/openwrt) `25.12.6` 的内核调试信息生成 | GPL-2.0 |

两个包都由本项目的 CI 从上述源码/产物构建，未经过第三方重打包。
对应的源码获取地址就是上面表格里的链接。

## 构建

构建脚本与流水线在 [pure-openwrt](https://github.com/dawenbin/pure-openwrt)：

```text
build/daed/            daed 的 apk 打包定义
build/vmlinux-btf/     BTF 的 apk 打包定义
ci/                    构建与发布流水线
```
