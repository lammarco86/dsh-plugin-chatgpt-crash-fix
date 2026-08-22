<#
.SYNOPSIS
    检查系统代理配置与 Clash 类代理客户端状态（只读）。
.DESCRIPTION
    读取 HKCU Internet Settings 的代理设置，检测代理端口是否在监听，
    并判断 ProxyOverride 是否已包含微软域名绕过列表。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File check-proxy-config.ps1
#>
[CmdletBinding()]
param(
    [int]$ProxyPort = 7897
)

$k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$p = Get-ItemProperty $k -ErrorAction SilentlyContinue

"=== 代理设置 (HKCU) ==="
"ProxyEnable   : $($p.ProxyEnable)"
"ProxyServer   : $($p.ProxyServer)"
"ProxyOverride : $($p.ProxyOverride)"
"AutoConfigURL : $($p.AutoConfigURL)"

"=== 代理客户端监听检查 (端口 $ProxyPort) ==="
$listen = Get-NetTCPConnection -LocalPort $ProxyPort -State Listen -ErrorAction SilentlyContinue
if ($listen) {
    $proc = Get-Process -Id $listen.OwningProcess -ErrorAction SilentlyContinue
    "正在监听: $($proc.ProcessName) (pid $($listen.OwningProcess))"
} else {
    "端口 $ProxyPort 未监听 —— 代理设置指向的客户端没有运行（死代理，浏览器/商店都会连不上）"
}

"=== 绕过列表评估 ==="
if ($p.ProxyEnable -eq 1) {
    $need = @("*.microsoft.com", "*.windowsupdate.com", "*.delivery.mp.microsoft.com", "*.mp.microsoft.com")
    $missing = $need | Where-Object { $p.ProxyOverride -notmatch [regex]::Escape($_) }
    if ($missing.Count -eq 0) {
        "微软域名绕过: 已完整配置 ✅"
    } else {
        "微软域名绕过: 缺少 -> $($missing -join ', ')"
        "Windows 更新/商店会因此被代理接管；若代理转发微软端点失败则 WU/商店报 0x80072EFD，"
        "并可能导致 ChatGPT 应用的商店更新器崩溃。运行 fix-proxy-bypass.ps1 修复。"
    }
} else {
    "代理未启用 (ProxyEnable=0)，无代理干扰问题。"
}
