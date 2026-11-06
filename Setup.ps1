$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not [Environment]::Is64BitOperatingSystem) { throw '需要 64 位 Windows。' }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw '此安装脚本固定使用 Windows x64 二进制。' }
$runtime = Join-Path $root 'runtime'
$data = Join-Path $runtime 'data'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
foreach ($path in @($runtime,$data,(Join-Path $data 'login-receipts'),(Join-Path $data 'login'))) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '运行目录不能是链接。' }
    $acl = Get-Acl -LiteralPath $path; $acl.SetOwner($sid); Set-Acl -LiteralPath $path -AclObject $acl
}
$binary = Join-Path $runtime 'wx.exe'
$expected = '29bfc4e5e45fa90ddadaa54eaa3f9d33b5d5a2d83803011468f40dc15c245abe'
if (-not (Test-Path -LiteralPath $binary)) {
    Invoke-WebRequest -Uri 'https://github.com/thisnick/agent-wechat/releases/download/v1.5.1/wx-v1.5.1-win32-x64.exe' -OutFile $binary
}
if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLower() -ne $expected) { throw '接口程序 SHA-256 校验失败，未运行。' }
if (-not (Test-Path -LiteralPath (Join-Path $root '.venv\Scripts\python.exe'))) {
    py -3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)'
    if ($LASTEXITCODE -ne 0) { throw '需要 Python 3.11 或更新版本。' }
    py -3 -m venv (Join-Path $root '.venv')
    if ($LASTEXITCODE -ne 0) { throw '创建虚拟环境失败。' }
}
$client = Join-Path $data 'client.toml'
if (-not (Test-Path -LiteralPath $client)) { [IO.File]::WriteAllText($client,"schemaVersion = 1`n") }
$fileAcl = [Security.AccessControl.FileSecurity]::new()
$fileAcl.SetOwner($sid); $fileAcl.SetAccessRuleProtection($true,$false)
$fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','Allow'))
$fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-18'),'FullControl','Allow'))
Set-Acl -LiteralPath $client -AclObject $fileAcl
$config = Join-Path $root 'watch-config.json'
if (-not (Test-Path -LiteralPath $config)) {
    @{server='http://127.0.0.1:18766';account='';data_dir=$data;client_config=$client;wx=$binary;output=(Join-Path $root 'downloads');groups=@{}} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding utf8
}
Write-Output '安装完成。请运行 Login.ps1，然后添加群 ID。'
