<#
.SYNOPSIS
    修复"代理干扰微软商店/更新通道"：为微软域名添加代理绕过列表（可回滚）。
.DESCRIPTION
    现象：Clash 类软件设置了系统代理（127.0.0.1:xxxx），Windows Update /
    微软商店的更新通道经代理转发失败（0x80072EFD），进而导致 ChatGPT/Codex
    桌面应用的商店更新器（windows-updater.node）崩溃闪退。

    本脚本：
      * 先备份当前 ProxyEnable/ProxyServer/ProxyOverride 到 -BackupPath；
      * 把微软域名加入 ProxyOverride（保留原有绕过项）；
      * 提供 -Restore 一键恢复备份。
    仅修改用户代理设置，不动 Clash 本身 —— OpenAI 等流量仍走代理（防封号），
    微软域名直连（通道可用），两全其美。

.PARAMETER ProxyServer
    代理地址，默认 127.0.0.1:7897（Clash 常见端口，按你的客户端实际端口改）。
.PARAMETER BackupPath
    备份文件路径，默认 $env:USERPROFILE\Desktop\proxy-backup.json。
.PARAMETER Restore
    恢复模式：从 BackupPath 恢复原代理设置并退出。
.PARAMETER Apply
    执行修复（默认行为）。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File fix-proxy-bypass.ps1 -ProxyServer "127.0.0.1:7897"
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File fix-proxy-bypass.ps1 -Restore
#>
[CmdletBinding()]
param(
    [string]$ProxyServer = "127.0.0.1:7897",
    [string]$BackupPath = (Join-Path $env:USERPROFILE "Desktop\proxy-backup.json"),
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$bypass = "*.microsoft.com;*.windowsupdate.com;*.delivery.mp.microsoft.com;*.mp.microsoft.com;*.windows.com;*.office.com;*.bing.com;<local>"

function Read-Proxy {
    $p = Get-ItemProperty $key
    [pscustomobject]@{
        ProxyEnable   = $p.ProxyEnable
        ProxyServer   = $p.ProxyServer
        ProxyOverride = $p.ProxyOverride
        AutoConfigURL = $p.AutoConfigURL
    }
}

function Save-Backup($state, $path) {
    $state | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
    "已备份代理设置 -> $path"
}

if ($Restore) {
    if (-not (Test-Path $BackupPath)) { throw "备份文件不存在: $BackupPath" }
    $bak = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
    Set-ItemProperty $key -Name ProxyEnable -Value $bak.ProxyEnable
    Set-ItemProperty $key -Name ProxyServer -Value $bak.ProxyServer
    if ($null -ne $bak.ProxyOverride) { Set-ItemProperty $key -Name ProxyOverride -Value $bak.ProxyOverride }
    if ($null -ne $bak.AutoConfigURL) { Set-ItemProperty $key -Name AutoConfigURL -Value $bak.AutoConfigURL }
    "已从备份恢复代理设置:"
    Read-Proxy | Format-List
    exit 0
}

$current = Read-Proxy
"当前设置:"
$current | Format-List

Save-Backup $current $BackupPath

# 合并绕过列表（保留已有项，去重）
$existing = @()
if ($current.ProxyOverride) {
    $existing = $current.ProxyOverride -split ';' | Where-Object { $_.Trim() -ne '' }
}
$merged = ($existing + ($bypass -split ';')) | Where-Object { $_.Trim() -ne '' } | Select-Object -Unique
$mergedList = ($merged -join ';')

Set-ItemProperty $key -Name ProxyEnable -Value 1
Set-ItemProperty $key -Name ProxyServer -Value $ProxyServer
Set-ItemProperty $key -Name ProxyOverride -Value $mergedList

"修复后设置:"
Read-Proxy | Format-List

"=== 验证 Windows Update 通道 ==="
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $result = $session.CreateUpdateSearcher().Search("IsInstalled=0")
    "WU scan OK: $($result.Updates.Count) updates"
} catch {
    "WU scan FAILED: $($_.Exception.Message) —— 若仍失败，检查代理客户端是否在运行、端口是否正确。"
}

"提示: 恢复方法 -> powershell -File $PSCommandPath -Restore -BackupPath $BackupPath"
