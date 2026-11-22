# pure-openwrt-feed Agent 协作规范

构建架构、三道一致性门与包清单见 `README.md`；`luci-app-daede` 与上游差异见 `packages/luci-app-daede/UPSTREAM.md`。本文件只记录本仓硬约束。

## 公开仓库安全红线

- 本仓库为**公开仓库**，仅保存打包定义、脚本与构建产物。
- **严禁写入任何私人信息**：禁止出现个人出口 IP、内网网段、订阅/节点名称、凭据、私钥或本机绝对路径。

## 改包与提交硬规则

- **必须递增 `PKG_RELEASE`**：修改 `packages/<pkg>/` 下任何文件内容时，必须递增对应 `Makefile` 中的 `PKG_RELEASE`；否则上游构建流水线会沿用旧 `.apk` 而不重新编译。
- **`UPSTREAM.sha256` 约束**：修改 `packages/luci-app-daede/` 时，严禁改动 `UPSTREAM.sha256` 列出的未改上游文件（构建前会校验 hash）；若确需修改某上游文件，必须同步从 `UPSTREAM.sha256` 移除并在 `UPSTREAM.md` 登记差异原因。
- **`daed` 必留补丁**：`packages/daed/patches/001-dae-core-restore-Marshaller-Bytes.patch` 为编译必需的上游修复回移，不得删除。
- **换行与 Shell 兼容性**：所有脚本、init、Makefile 严格保持 Unix LF 换行（禁止 CRLF）；运行在 OpenWrt 上的脚本必须兼容 BusyBox `ash`（纯 POSIX sh），修改后先做 `sh -n` 语法检查。
- **不自建 CI / 不手推 `gh-pages`**：本仓不放置 GitHub Actions workflow，也不手动修改或推送 `gh-pages` 分支，发布统一由下游构建流水线完成。
- **提交规范**：沿用仓内中文 Conventional Commits 风格，改完并验证后再推送 `main`。
