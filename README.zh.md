# dsh-plugin-chatgpt-crash-fix

> 诊断并修复 Windows 上 ChatGPT / Codex 桌面应用（商店包 `OpenAI.Codex`）**启动后约 1 分钟闪退**的 DSH 插件包：崩溃转储定位 → 微软商店通道检测 → 代理干扰修复，全流程可复现、可回滚。

[English](README.md) · 中文

## 背景：这个插件解决什么问题

很多用户在以下场景遇到 ChatGPT 桌面应用"开了就闪退"：

- 应用窗口能打开、界面正常加载，**约 60–90 秒后整个进程退出**，无系统错误弹窗；
- 应用日志出现 `[windows-store-updater] Checking Windows Store for package updates` 后崩溃；
- 时间点常与**系统更新被断电/中断**、或**启用 Clash 类代理**重合。

**根因链条**（经崩溃转储逐层定位）：

```
Clash 等软件设置系统代理 (127.0.0.1:7897)
  └─ 代理转发微软更新域名失败（直连通、走代理 000）
       └─ Windows Update / 微软商店通道失效 (0x80072EFD)
            └─ 应用内置"商店更新检查器" windows-updater.node 访问冲突崩溃 (0xC0000005)
                 └─ 整个应用闪退
```

**修复思路（两全其美）**：不关代理（OpenAI 流量继续走代理、规避封号风险），只把**微软域名加入代理绕过列表**（直连），商店/更新通道立即恢复，应用更新到新版后不再崩溃。

## 包含内容

| 组件 | 说明 |
| --- | --- |
| `skills/chatgpt-crash-fix/SKILL.md` | **排查手册**：教任意 DSH agent 复现整套诊断→修复→验证流程 |
| `scripts/diagnose-chatgpt-crash.ps1` | 综合诊断：应用状态 + 崩溃转储 + 商店通道 + 代理配置（只读） |
| `scripts/check-store-channel.ps1` | 商店/更新通道检测（只读） |
| `scripts/check-proxy-config.ps1` | 代理与绕过列表检测（只读） |
| `scripts/fix-proxy-bypass.ps1` | 一键修复：备份→添加微软域名绕过→验证（可 `-Restore` 回滚） |
| `lib/index.js` | Cordis 插件：注册 `/chatgpt-crash-fix` 命令 |

## 安装

### 方式一：作为 DSH 插件（推荐）

```bash
# 从 npm（发布后）
dsh plugin add dsh-plugin-chatgpt-crash-fix

# 或从 GitHub
dsh plugin add https://github.com/lammarco86/dsh-plugin-chatgpt-crash-fix
```

安装后重启 DSH，输入 `/chatgpt-crash-fix` 可查看排查入口。

### 方式二：仅取脚本/Skill（不装插件）

```bash
git clone https://github.com/lammarco86/dsh-plugin-chatgpt-crash-fix.git
# 把 skills/chatgpt-crash-fix 放到你的 skill 目录，脚本可直接运行
```

## 使用

```powershell
# 1) 综合诊断（只读）
powershell -ExecutionPolicy Bypass -File scripts\diagnose-chatgpt-crash.ps1

# 2) 若报告"WU 通道失败 + 代理开启 + 无微软绕过"，执行修复
powershell -ExecutionPolicy Bypass -File scripts\fix-proxy-bypass.ps1 -ProxyServer "127.0.0.1:7897"

# 3) 需要回滚时
powershell -ExecutionPolicy Bypass -File scripts\fix-proxy-bypass.ps1 -Restore
```

或让 DSH agent 读取 `skills/chatgpt-crash-fix/SKILL.md`，由 agent 按手册逐步执行（手册含 minidump 解析、zstd 多帧解压等进阶步骤）。

## 已验证效果

- 崩溃转储解析确认故障模块：`...\resources\native\windows-updater.node`（0xC0000005）；
- 添加微软域名绕过列表后：WU 扫描恢复、应用商店更新成功（26.818.2441.0 → 26.818.5229.0）、应用稳定运行、更新检查日志显示 `overallState=NoUpdates`；
- 代理保留：OpenAI 流量仍走 Clash，账号认证正常。

## 免责声明

- 本插件**非 OpenAI 官方出品**，与 Anywhere Labs / DeepSeek 无关，不提供任何安全背书。
- 脚本只修改用户代理设置并自动备份；请先阅读代码再执行。
- 崩溃转储、auth.json、订阅等属个人信息，**请勿**随本仓库发布。

## 上架 / 分发

- 发布到 npm：`npm publish`（需 npm 账号）；
- 提交到 DSH 社区目录（如 1024Store）：按目录提供方的收录规则提交元数据。

## 许可证

[MIT](LICENSE)
