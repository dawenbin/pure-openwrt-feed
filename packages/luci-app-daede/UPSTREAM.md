# 上游

来源：<https://github.com/kenzok8/openwrt-daede> 的 `luci-app-daede/`，提交 `57659f63d341b5ce71ca30ba378f4a4d8e5ce779`。

`UPSTREAM.sha256` 记录未改动文件在该提交的 hash，`scripts/build.sh` 构建前校验。

## 与上游的差异

只保留 daed 后端，不带 dae。

| 去掉 | 原因 |
| --- | --- |
| 软件包在线更新（`update-pkg.sh`、`pkg-info.sh`、`refresh-index.sh`、页面） | 防止把本源的 daed 换成第三方 fork |
| dae 后端（`dae.js`、`gen-dae-config.sh`、`config-defaults.sh`、`proxy-check.sh`） | 只用 daed |
| 设置表单、订阅定时（`daed.js`、`daed-sub-*.sh`） | 会把面板账号明文写进 `/etc/config/daed`；daed 自带订阅定时 |
| 启停开关、停止按钮 | 会写 `daed.config.enabled`；失败关闭下停 daed 等于断网 |
| `po/zh-cn`、自带 lmo | 按 LuCI 规范由 `luci.mk` 生成 `luci-i18n-daede-zh-cn` |

| 改动 | 内容 |
| --- | --- |
| `update-geo.sh` | 默认源改 v2fly；替换前校验结构与分类，内容没变不重启，用 restart 而非 reload，重启后没绑定就回滚 |
| `geo-cron.sh` | 定时按 UTC 换算到北京时间 04:17（上游写的是 UTC 04:17，等于北京时间中午重启 daed） |
| `etc/config/daede` | 默认开启每周更新，数据源 v2fly |
| `90-luci-app-daede-init` | 只写 cron 条目，不动 daed 与其他包 |
| `config-backup.sh` | 只管 daed |
| `daede-graphql` | 请求体上限 1 MiB |
| `converter.js` | 只导入 daed，默认分组名改为 `node` |
| `updates.js` | BTF 按 `vmlinux-<版本>` 查找；不提供删除 netns |
| ACL | 按实际用到的收窄，对 `uci daed` 只读 |
| `Makefile` | `LUCI_MINIFY_JS:=0`：jsmin 会截断 `converter.js` 字符类里带 `/` 的正则 |
