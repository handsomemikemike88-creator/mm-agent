# Approve a person who messaged MM Agent on Telegram or WhatsApp.
param([ValidateSet('telegram', 'whatsapp')][string]$Channel = 'telegram')
. "$PSScriptRoot\common.ps1"
Update-Path

if (-not (Test-Port $MM.InterfacePort)) { throw 'MM Agent is not running. Start it with Start MM Agent first.' }
$openclaw = Resolve-OpenClaw

$ErrorActionPreference = 'Continue'     # OpenClaw prints harmless warnings on stderr
Write-Host "== Pending $Channel requests ==" -ForegroundColor Cyan
& $openclaw pairing list $Channel 2>$null | Out-Host

$code = (Read-Host 'Pairing code to approve (Enter = cancel)').Trim()
if ($code) {
    & $openclaw pairing approve $Channel $code 2>$null | Out-Host
    if ($LASTEXITCODE -eq 0) { Write-Host "[OK] Approved. Send another message to chat with $($MM.Name)." -ForegroundColor Green }
}
