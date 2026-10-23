# Choose which AI provider the Hermes brain uses. OpenClaw needs no change.
param(
    [ValidateSet('deepseek', 'openai', 'anthropic', 'kimi')]
    [string]$Provider,
    [string]$Model,
    [switch]$Quiet
)
. "$PSScriptRoot\common.ps1"
Update-Path

if (-not $Provider) {
    Write-Host "Which AI should $($MM.Name) use?" -ForegroundColor Cyan
    $keys = @($Providers.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $p = $Providers[$keys[$i]]
        $state = if (Test-Key $p.KeyVar) { 'key saved' } else { 'NO KEY' }
        Write-Host ("  {0}) {1,-20} default model: {2,-18} [{3}]" -f ($i + 1), $p.Label, $p.Model, $state)
    }
    $pick = Read-Host 'Number'
    $Provider = $keys[[int]$pick - 1]
    $custom = Read-Host "Model id (Enter = $($Providers[$Provider].Model))"
    if ($custom) { $Model = $custom.Trim() }
}

$p = $Providers[$Provider]
if (-not $Model) { $Model = $p.Model }
$hermesId = if ($p.HermesId) { $p.HermesId } else { $Provider }

function Set-HermesConfig([string]$Key, [string]$Value) {
    $ErrorActionPreference = 'Continue'
    $out = & hermes config set $Key $Value 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $out.Trim() -ForegroundColor Red
        throw "Could not change the Hermes setting '$Key'. Hermes may be broken - run MM Agent Setup to repair it."
    }
}
Set-HermesConfig 'model.provider' $hermesId
Set-HermesConfig 'model.default' $Model
# Clear any old endpoint (e.g. OpenRouter) so the provider's own URL is used.
# (Hermes strips the value, so a single space counts as "not set".)
Set-HermesConfig 'model.base_url' ' '

if (-not $Quiet -or -not (Test-Key $p.KeyVar)) {
    Write-Host "[OK] Brain model: $($p.Label) / $Model"
    if (-not (Test-Key $p.KeyVar)) {
        Write-Host "     No $($p.Label) key saved yet - run Enter-API-Keys.cmd" -ForegroundColor Yellow
    }
}
if (Test-Brain) { Write-Host "     Restart MM Agent (Stop + Start) to apply." -ForegroundColor Yellow }
