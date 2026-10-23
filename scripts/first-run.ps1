# MM Agent first-run setup: install the brain and interface if missing, link them, ask for API keys.
# -Check only reports what is installed and changes nothing.
param([switch]$Check)
. "$PSScriptRoot\common.ps1"
Update-Path

function Test-Command([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

if (-not $Check -and (Restart-WithoutRedirectionGuard (Join-Path (Split-Path $PSScriptRoot -Parent) 'Run-Setup.cmd'))) { return }

function Show-Where([string]$Name) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { $c.Source } else { 'missing' }
}

Write-Host "== $($MM.Name) setup ==" -ForegroundColor Cyan
$nodeExe = Join-Path $MM.NodeDir 'node.exe'
Write-Host ("Node.js (MM Agent):     {0}" -f $(if (Test-Path $nodeExe) { "$(& $nodeExe -v)  $($MM.NodeDir)" } else { 'missing' }))
Write-Host ("node on PATH:           {0}" -f (Show-Where 'node'))
$hermesProblem = if (Test-Command 'hermes') { Get-HermesRepairReason }
Write-Host ("Brain (Hermes Agent):   {0}{1}" -f (Show-Where 'hermes'), $(if ($hermesProblem) { "  (NEEDS REPAIR: $hermesProblem)" }))
Write-Host ("Interface (OpenClaw):   {0}" -f (Show-Where 'openclaw'))
Write-Host ("Bridge configured:      {0}" -f [bool](Get-EnvValue 'API_SERVER_KEY'))
Write-Host ("RedirectionGuard:       {0}" -f $(if (Test-RedirectionGuard) { 'ON (blocks Hermes Python)' } else { 'off' }))
$saved = @($Providers.Keys | Where-Object { Test-Key $Providers[$_].KeyVar })
Write-Host ("API keys saved:         {0}" -f $(if ($saved) { $saved -join ', ' } else { 'none' }))
if ($Check) { return }

Write-Host "`nThis downloads and installs Node.js, Hermes Agent and OpenClaw (all open source)."
Write-Host "It can take 5-15 minutes. Windows may ask for permission once - click Yes.`n"

# 1. Latest Node.js (installs, updates, or confirms it is current).
& "$PSScriptRoot\install-node.ps1"
Update-Path

# 2. Brain. It must run AND be completely installed (a half-finished update still answers
# `hermes --version` but cannot start the brain). Either is repaired by re-running its installer.
$reason = if (Test-Command 'hermes') { Get-HermesRepairReason } else { 'not installed' }
if ($reason) {
    if (Test-Command 'hermes') {
        Write-Host "[!] Hermes Agent needs repair: $reason" -ForegroundColor Yellow
        Show-HermesDiagnosis
        Write-Host "[..] Repairing Hermes Agent (re-running its installer, about 10 minutes) ..." -ForegroundColor Cyan
    }
    Repair-UvPythonLinks
    & "$PSScriptRoot\install-hermes.ps1"
    Update-Path
    $reason = Get-HermesRepairReason
    if ($reason) {
        Write-Host "[!] Hermes Agent still needs repair: $reason" -ForegroundColor Red
        Show-HermesDiagnosis
        throw 'Hermes Agent is not working. See the lines above, then run MM Agent Setup again.'
    }
    # A brain/dashboard still running from before the repair uses the old, broken setup: stop it
    # so Start launches fresh ones.
    & "$PSScriptRoot\stop.ps1"
    foreach ($port in $MM.BrainPort, $MM.DashboardPort) {
        Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { & taskkill /PID $_.OwningProcess /T /F 2>$null | Out-Null }
    }
}
Write-Host "[OK] Hermes Agent runs" -ForegroundColor Green

# 3. Interface. If OpenClaw is already installed but missing from PATH, this repairs PATH.
$openclaw = Resolve-OpenClaw
if (-not $openclaw) {
    & "$PSScriptRoot\install-openclaw.ps1"
    Update-Path
    $openclaw = Resolve-OpenClaw
    if (-not $openclaw) { throw 'OpenClaw did not install. Run setup again, or see README.md.' }
}
Write-Host "[OK] OpenClaw: $openclaw" -ForegroundColor Green

Write-Host ""
& "$PSScriptRoot\enter-api-keys.ps1"

Write-Host ""
& "$PSScriptRoot\setup-bridge.ps1" -SkipModel

# Default brain = first provider with a saved key.
$first = @($Providers.Keys | Where-Object { Test-Key $Providers[$_].KeyVar }) | Select-Object -First 1
if ($first) {
    & "$PSScriptRoot\switch-model.ps1" -Provider $first
} else {
    Write-Host "[!] No API key entered. Add one later from Start Menu > MM Agent > Enter API Keys." -ForegroundColor Yellow
}

# Optional: connect chat apps now (also available later from the Start Menu).
Write-Host "`nConnect a chat app so you can talk to $($MM.Name) from your phone?" -ForegroundColor Cyan
Write-Host "  1) Telegram   2) WhatsApp   3) Both   Enter) Skip - you can do it later from the Start Menu"
$chat = (Read-Host 'Choice').Trim()
$chatApps = switch ($chat) { '1' { 'telegram' } '2' { 'whatsapp' } '3' { 'telegram', 'whatsapp' } default { @() } }
foreach ($app in $chatApps) {
    Write-Host ""
    # A chat app that fails to connect must not undo the rest of setup.
    try { & "$PSScriptRoot\connect-$app.ps1" }
    catch { Write-Host "[!] $app was not connected: $($_.Exception.Message). Try again later from the Start Menu." -ForegroundColor Yellow }
}

Write-Host "`nSetup complete." -ForegroundColor Green
if ($chatApps) {
    Write-Host "After MM Agent starts, message your bot/number, then approve yourself with Approve Telegram / Approve WhatsApp in the Start Menu." -ForegroundColor Cyan
}
if ($first -and (Read-Host 'Start MM Agent now? (Y/n)') -notmatch '^[nN]') {
    & "$PSScriptRoot\start.ps1"
}
