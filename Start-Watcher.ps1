$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cfg = Get-Content -LiteralPath (Join-Path $root 'watch-config.json') -Raw | ConvertFrom-Json
$launcher = Join-Path $root 'scripts\Start-PrivateProcess.ps1'
$watchScript = Join-Path $root 'watch_files.py'
$runtimeFile = Join-Path $root 'watch-processes.json'
if (-not $cfg.account -or $cfg.groups.PSObject.Properties.Count -eq 0) { throw '请先登录并在 watch-config.json 中填写账号和群 ID。' }
$serverUri = [Uri]$cfg.server
if ($serverUri.Host -notin @('127.0.0.1','localhost','::1')) { throw '启动脚本仅支持本机接口。' }
$listen = '127.0.0.1:' + $serverUri.Port
$old = if (Test-Path -LiteralPath $runtimeFile) { Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json } else { $null }
$daemon = Get-CimInstance Win32_Process -Filter "Name = 'wx.exe'" | Where-Object {
    $_.ExecutablePath -eq $cfg.wx -and $_.CommandLine.Contains($cfg.data_dir) -and $_.CommandLine -match '\bserve\b'
}
if (@($daemon).Count -gt 1) { throw '检测到多个接口服务，请先停止重复实例。' }
if ($daemon) { $daemonPid = $daemon.ProcessId } else {
    $daemonPid = & $launcher -Executable $cfg.wx -Arguments ('--data-dir "' + $cfg.data_dir + '" --listen ' + $listen + ' serve')
}
$existingWatcher = if ($old) { Get-CimInstance Win32_Process -Filter "ProcessId = $($old.watcherPid)" } else { $null }
if ($existingWatcher -and $existingWatcher.CommandLine.Contains($watchScript)) {
    $watcherPid = $existingWatcher.ProcessId
} else {
    $watcherPid = & $launcher -Executable (Join-Path $root '.venv\Scripts\python.exe') -Arguments ('"' + $watchScript + '"')
}
@{ daemonPid=$daemonPid; watcherPid=$watcherPid; startedAt=(Get-Date -Format o) } | ConvertTo-Json | Set-Content -LiteralPath $runtimeFile -Encoding utf8
Write-Output '监听进程已启动。实际在线与下载状态请查看 watch.log；扫码会话失效后需重新登录。'
