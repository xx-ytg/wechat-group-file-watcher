param([Parameter(Mandatory)][string]$Name)
$ErrorActionPreference = 'Stop'
$cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'watch-config.json') -Raw | ConvertFrom-Json
& $cfg.wx --config $cfg.client_config --data-dir $cfg.data_dir --server $cfg.server --account $cfg.account --json groups find $Name
if ($LASTEXITCODE -ne 0) { throw '查询群失败，请先检查登录状态。' }
