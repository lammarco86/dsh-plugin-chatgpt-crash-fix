---
name: chatgpt-crash-fix
description: Diagnose and fix ChatGPT / Codex desktop app (Windows, MSIX package OpenAI.Codex) startup crashes — typically a native Windows Store updater crash (windows-updater.node access violation) ~60-90s after launch, caused by a broken Microsoft Store/WU channel, usually from Clash/system-proxy interference. Use when the app auto-closes shortly after opening, or after an interrupted Windows update.
---

# ChatGPT / Codex 桌面应用闪退排查手册

Windows 上 ChatGPT 桌面应用（商店包名 `OpenAI.Codex`，内含 ChatGPT.exe 与 Codex.exe）启动后约 60–90 秒整应用退出、无系统错误弹窗，是最常见的故障形态之一。**本手册的全部命令都只读/可回滚，修改前一律先备份。**

## 1. 症状确认

- 应用窗口能打开、UI 正常加载，约 1 分钟后整个进程树退出（无 WER 弹窗）。
- 应用日志（stderr）出现 `[windows-store-updater] Checking Windows Store for package updates` 后崩溃。
- 事件日志无 `Application Error`(1000)，崩溃由应用自身 Crashpad 记录。

## 2. 定位崩溃点（决定性证据）

1. 找崩溃转储：`Get-ChildItem "$env:APPDATA\Codex" -Recurse -Filter *.dmp`
   - MSIX 虚拟化路径：`%LOCALAPPDATA%\Packages\OpenAI.Codex_*\LocalCache\Roaming\Codex\web\Codex\Crashpad\reports`
   - 直接 exe 启动时：`%APPDATA%\Codex\web\Codex\Crashpad\reports`
2. 转储是**多帧 zstd**（每帧一段事件流），用 Node ≥22.19 逐帧解压：
   ```js
   const { zstdDecompressSync } = require('node:zlib')
   // 扫描 28 B5 2F FD 魔数分帧，逐帧 zstdDecompressSync，容忍末尾未写完的帧
   ```
3. 用 minidump 解析脚本读异常码与故障模块：
   - `0xC0000005` + 故障模块 `...\resources\native\windows-updater.node` ⇒ 就是"商店更新检查器"崩溃。
   - 模块列表里没有第三方注入（tmmon64.dll 等字符串可能是历史数据，以模块列表为准）。

**结论范式**：崩溃在应用内置"Windows Store 更新检查"原生模块 ⇒ 根因几乎都是**微软商店/更新通道不可用**，而最常见诱因是**系统代理被 Clash 类软件设置、且代理转发微软更新域名失败**。

## 3. 检测微软商店 / Windows Update 通道

```powershell
# 1) 服务状态（异常点：wuauserv 停止、DoSvc 停止）
Get-Service wuauserv, bits, DoSvc, InstallService, ClipSVC

# 2) WU 通道实测（权威）：
try {
  $s = New-Object -ComObject Microsoft.Update.Session
  $r = $s.CreateUpdateSearcher().Search("IsInstalled=0")
  "WU scan OK: $($r.Updates.Count) updates"
} catch { "WU scan FAILED: $($_.Exception.Message)" }   # 0x80072EFD = 连接失败

# 3) 端点直连（区分"被墙"vs"服务损坏"）：
curl.exe -s -o NUL -w "%{http_code}" https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx  # 400 = 可达
```

## 4. 检测代理干扰（最常见根因）

```powershell
$k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
(Get-ItemProperty $k) | Select-Object ProxyEnable, ProxyServer, ProxyOverride
```

- `ProxyEnable=1` 且 `ProxyServer=127.0.0.1:7897`（或类似）＝ Clash 类软件的系统代理。
- **判定**：临时 `Set-ItemProperty $k -Name ProxyEnable -Value 0` → 重测第 3 步 WU 扫描；若恢复 OK，则代理就是元凶（代理软件转发微软更新端点失败，如实测经代理返回 000）。
- 测试后**立即恢复原值**（记下旧值）。

## 5. 修复：微软域名绕过代理（两全方案）

保留代理（OpenAI 流量仍走代理防封号），只让微软域名直连：

```powershell
$k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$bypass = "*.microsoft.com;*.windowsupdate.com;*.delivery.mp.microsoft.com;*.mp.microsoft.com;*.windows.com;*.office.com;*.bing.com;<local>"
Set-ItemProperty $k -Name ProxyEnable -Value 1
Set-ItemProperty $k -Name ProxyServer -Value "127.0.0.1:7897"   # 按实际端口
Set-ItemProperty $k -Name ProxyOverride -Value $bypass
# 重测 WU 扫描 ⇒ 应 OK
```

> **⚠️ 该绕过列表会被重置，这是闪退"复发"的头号原因。** Windows 重启、或 Clash 类软件重新设置系统代理时，常把 `ProxyOverride` 重置回默认值（只剩 localhost/内网段），使微软域名重新被代理接管，应用更新器再次崩溃。因此**每次排查/验证前都要先确认 `ProxyOverride` 仍包含微软域名**；已修复过但后续又闪退的，优先怀疑这一项。

持久化建议（避免重启/Clash 重置后复发）：把上述微软域名填进 **Clash 类软件的"系统代理绕过(Bypass)"** 配置（而非只改注册表），让代理客户端每次设代理都自动带上；否则重启后需重新执行本修复。

配套（视情况）：
- `Start-Service wuauserv, DoSvc`（Windows Update 服务被中断的更新停掉时）。
- `wsreset.exe` 重置商店缓存。
- `dism /Online /Cleanup-Image /RestoreHealth` + `sfc /scannow`（排除系统组件损坏，通常不是根因但值得做一次）。

## 6. 更新应用到最新版（商店通道恢复后）

```powershell
# 官方 Web 安装器（产品 ID 9PLM9XGG6VKS）：
#   https://get.microsoft.com/installer/download/9PLM9XGG6VKS
# 或商店/设置里检查更新。旧版闪退通常是该版本 updater 的 bug，新版已修复。
Get-AppxPackage -Name OpenAI.Codex | Select-Object Version, Status
```

## 7. 验证

1. 正常方式启动应用（开始菜单/快捷方式，勿用"直接跑 exe"——会绕过 MSIX 虚拟化）。
2. **先确认代理绕过仍在**（防复发）：`(Get-ItemProperty "HKCU:\...\Internet Settings").ProxyOverride` 应含 `microsoft`/`windowsupdate`；缺少则先重新执行第 5 步修复。
3. 观察 ≥120 秒（超过原崩溃窗口），确认进程存活：
   `Get-Process | Where-Object { $_.ProcessName -match "ChatGPT|Codex" }`
4. 确认日志出现 `windows-store-updater ... overallState=NoUpdates`（检查**完成**而非崩溃）。
5. 确认无新 `.dmp` 生成。

## 8. 安全与合规

- 崩溃转储、`auth.json`、会话数据库、代理订阅等**属于个人信息，严禁随仓库发布**。
- 修改代理设置前必须备份原值（`ProxyEnable/ProxyServer/ProxyOverride`），并提供恢复方法。
- 本流程不审查应用代码安全性，只修复"身份/通道"问题；安装第三方插件前仍需自行判断信任。
- 微软商店不可达时的官方直链（示例，勿写死版本号）：`https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json`（更新清单）、`.../ChatGPT-x64.msix`（商店签名包）。

## 附：常见坑

| 现象 | 原因 |
| --- | --- |
| 修复后又闪退（尤其重启/Clash 重设后） | 代理绕过列表被重置回默认值，微软域名重新被代理接管 → 更新器崩溃；重新执行第 5 步或在 Clash 的 Bypass 配置里持久化 |
| 直接运行 `ChatGPT.exe` 测试 | 绕过 MSIX 虚拟化，数据写到真实 `%APPDATA%\Codex`，与正常启动不一致 |
| 本地 `requirements.toml` 写 `in_app_updates=false` | 个人版不生效，该开关仅对 MDM 托管配置生效 |
| `dsh plugin add` 的恢复边界 | 只快照 profile 的 package.json/lock/workspace 三个文件 |
| 事件日志只有 StoreAgentScanForUpdatesFailure0 | 商店更新扫描失败（常伴随 0x80072EFD），与代理问题同源 |
