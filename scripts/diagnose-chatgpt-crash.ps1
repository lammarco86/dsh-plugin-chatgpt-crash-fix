<#
.SYNOPSIS
    综合诊断 ChatGPT/Codex 桌面应用闪退：应用状态、崩溃转储、商店通道、代理配置。
.DESCRIPTION
    输出一份分节报告，覆盖闪退排查所需的全部证据：
    1) 应用安装状态（包版本/注册状态/安装位置）
    2) 最近崩溃转储（Crashpad reports）
    3) 微软商店 / Windows Update 通道实测（WU COM 扫描 + 端点直连）
    4) 系统代理与绕过列表
    全部只读，不修改任何设置。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File diagnose-chatgpt-crash.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Section($title) {
    Write-Host ""
    Write-Host ("=" * 60)
    Write-Host $title
    Write-Host ("=" * 60)
}

Section "1. 应用安装状态"
$pkg = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue
if ($pkg) {
    "包名      : $($pkg.Name)"
    "版本      : $($pkg.Version)"
    "状态      : $($pkg.Status)"
    "安装位置  : $($pkg.InstallLocation)"
} else {
    "未找到 OpenAI.Codex 包（可能未安装或已卸载）"
}

Section "2. 最近崩溃转储 (Crashpad)"
$roots = @(
    "$env:APPDATA\Codex\web\Codex\Crashpad\reports",
    "$env:LOCALAPPDATA\Packages\OpenAI.Codex*\LocalCache\Roaming\Codex\web\Codex\Crashpad\reports"
)
$dumps = @()
foreach ($r in $roots) {
    if (Test-Path $r) {
        $dumps += Get-ChildItem $r -Filter *.dmp -ErrorAction SilentlyContinue
    }
}
if ($dumps.Count -eq 0) {
    "无 .dmp 崩溃转储（可能从未崩溃，或目录尚不存在）"
} else {
    $dumps | Sort-Object LastWriteTime -Descending | Select-Object -First 5 |
        Select-Object LastWriteTime, @{n='MB';e={[Math]::Round($_.Length/1MB,1)}}, FullName |
        Format-Table -AutoSize
    "提示: 崩溃转储为多帧 zstd，逐帧(28 B5 2F FD 魔数)解压后解析 minidump，"
    "故障模块常为 ...\resources\native\windows-updater.node（访问冲突 0xC0000005）"
}

Section "3. 微软商店 / Windows Update 通道"
"服务状态:"
Get-Service wuauserv, bits, DoSvc, InstallService, ClipSVC -ErrorAction SilentlyContinue |
    Select-Object Status, Name | Format-Table -AutoSize
"WU 扫描实测:"
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0")
    "WU scan OK: $($result.Updates.Count) updates"
} catch {
    "WU scan FAILED: $($_.Exception.Message)  (0x80072EFD 通常=代理干扰或网络被墙)"
}
"端点直连 (400=可达, 000=不可达):"
curl.exe -s -o NUL -w "fe3.delivery.mp.microsoft.com => %{http_code}`n" --connect-timeout 10 --max-time 20 "https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx"

Section "4. 系统代理与绕过列表"
$k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$p = Get-ItemProperty $k -ErrorAction SilentlyContinue
"ProxyEnable   : $($p.ProxyEnable)"
"ProxyServer   : $($p.ProxyServer)"
"ProxyOverride : $($p.ProxyOverride)"
"AutoConfigURL : $($p.AutoConfigURL)"
$listen = Get-NetTCPConnection -LocalPort 7897 -State Listen -ErrorAction SilentlyContinue
if ($listen) {
    $proc = Get-Process -Id $listen.OwningProcess -ErrorAction SilentlyContinue
    "代理客户端   : 正在监听 7897 ($($proc.ProcessName))"
} else {
    "代理客户端   : 7897 未监听（代理设置可能是死代理）"
}
$hasMsBypass = ($p.ProxyOverride -match "microsoft")
"微软域名绕过 : $(if ($hasMsBypass) { '已配置' } else { '未配置（若 ProxyEnable=1 且 WU 失败，这就是根因）' })"

Write-Host ""
Write-Host "完成。如需修复：见 skills/chatgpt-crash-fix/SKILL.md 与 fix-proxy-bypass.ps1。"
