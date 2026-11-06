$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$config = Join-Path $root 'watch-config.json'
$cfg = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
$listen = '127.0.0.1:' + ([Uri]$cfg.server).Port
$daemon = Get-CimInstance Win32_Process -Filter "Name = 'wx.exe'" | Where-Object { $_.ExecutablePath -eq $cfg.wx -and $_.CommandLine.Contains($cfg.data_dir) -and $_.CommandLine -match '\bserve\b' }
if (-not $daemon) {
    & (Join-Path $root 'scripts\Start-PrivateProcess.ps1') -Executable $cfg.wx -Arguments ('--data-dir "'+$cfg.data_dir+'" --listen '+$listen+' serve') | Out-Null
}
$common = @('--config',$cfg.client_config,'--data-dir',$cfg.data_dir,'--server',$cfg.server,'--json')
for ($attempt=0;$attempt -lt 15;$attempt++) {
    $ready = & $cfg.wx @common status 2>$null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Milliseconds 500
}
if ($LASTEXITCODE -ne 0) { throw '本地接口尚未就绪。' }
if (-not $cfg.account) {
    $created = & $cfg.wx @common accounts create --alias group-files
    if ($LASTEXITCODE -ne 0) { throw '创建本地账号槽失败。' }
    $cfg.account = ($created | ConvertFrom-Json).id
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding utf8
}
Write-Output '请用手机微信扫描程序输出路径中的二维码并确认登录。二维码有时效；过期可重跑此脚本。'
$loginCommon = @($common | Where-Object { $_ -ne '--json' })
& $cfg.wx @loginCommon --account $cfg.account auth login --strategy qr --qr-refresh manual --max-refreshes 0 --timeout 300
if ($LASTEXITCODE -ne 0) { throw '登录未完成，请查看上方错误信息。' }
