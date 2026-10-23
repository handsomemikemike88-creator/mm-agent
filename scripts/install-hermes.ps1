# Install (or repair) the Hermes Agent brain with its official installer, skipping its own setup wizard.
$ErrorActionPreference = 'Stop'
Write-Host "== Installing Hermes Agent for MM Agent ==" -ForegroundColor Cyan

$content = (Invoke-WebRequest -UseBasicParsing https://hermes-agent.nousresearch.com/install.ps1).Content
# Windows PowerShell 5.1 can return raw bytes for this download; turn them into text.
if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content).TrimStart([char]0xFEFF) }
& ([scriptblock]::Create($content)) -NonInteractive

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$cmd = Get-Command hermes -ErrorAction SilentlyContinue
if ($cmd) { Write-Host "[OK] Hermes ready: $($cmd.Source)" -ForegroundColor Green }
else { Write-Host "[!] Install finished but 'hermes' is not on PATH yet. Open a new terminal." -ForegroundColor Yellow }
