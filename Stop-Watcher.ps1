$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cfg = Get-Content -LiteralPath (Join-Path $root 'watch-config.json') -Raw | ConvertFrom-Json
$runtime = Get-Content -LiteralPath (Join-Path $root 'watch-processes.json') -Raw | ConvertFrom-Json
foreach ($kind in @('watcher', 'daemon')) {
    $targetPid = if ($kind -eq 'watcher') { $runtime.watcherPid } else { $runtime.daemonPid }
    $targetProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $targetPid"
    if (-not $targetProcess) { continue }
    $valid = if ($kind -eq 'watcher') {
        $targetProcess.Name -eq 'python.exe' -and $targetProcess.CommandLine.Contains((Join-Path $root 'watch_files.py'))
    } else {
        $targetProcess.ExecutablePath -eq $cfg.wx -and $targetProcess.CommandLine.Contains($cfg.data_dir) -and $targetProcess.CommandLine -match '\bserve\b'
    }
    if (-not $valid) { throw '进程身份与记录不符，停止操作已中止。' }
    taskkill /PID $targetPid /T /F
    if ($LASTEXITCODE -ne 0) { throw '停止进程失败。' }
}
Write-Output '监听及本地接口服务已停止。手机微信登录设备记录不会因此自动删除。'
