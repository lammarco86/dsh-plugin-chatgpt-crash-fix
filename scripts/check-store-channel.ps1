<#
.SYNOPSIS
    检测微软商店 / Windows Update 通道是否可用（只读）。
.DESCRIPTION
    检查相关服务状态，实测 WU COM 扫描，并直连更新端点。
    WU 扫描返回 0x80072EFD 而端点直连可达 ⇒ 通常是系统代理干扰。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File check-store-channel.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

"=== 相关服务 ==="
Get-Service wuauserv, bits, DoSvc, InstallService, ClipSVC -ErrorAction SilentlyContinue |
    Select-Object Status, Name | Format-Table -AutoSize

"=== WU COM 扫描实测 ==="
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0")
    "OK: 找到 $($result.Updates.Count) 个更新"
} catch {
    "FAILED: $($_.Exception.Message)"
    "若为 0x80072EFD(无法连接)，下一步:"
    "  1) 检查代理: HKCU\...\Internet Settings 的 ProxyEnable/ProxyServer"
    "  2) 临时 ProxyEnable=0 重测本脚本，若恢复 OK ⇒ 代理干扰确认"
}

"=== 更新端点直连（400=可达）==="
foreach ($u in @(
    "https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx",
    "https://displaycatalog.mp.microsoft.com/v7.0/ping"
)) {
    $code = curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 10 --max-time 20 $u 2>$null
    "$u => $code"
}
