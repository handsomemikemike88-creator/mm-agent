# Install (or repair) the OpenClaw interface with its official installer, on MM Agent's own Node.js.
# Skips OpenClaw's own setup wizard: MM Agent's settings in ~/.openclaw are kept as they are.
. "$PSScriptRoot\common.ps1"
Write-Host "== Installing OpenClaw for $($MM.Name) ==" -ForegroundColor Cyan

# Make sure the latest Node.js is installed and first on PATH, so the installer uses it
# rather than an older Node in Program Files or Hermes' bundled copy.
& "$PSScriptRoot\install-node.ps1"
Update-Path

$content = (Invoke-WebRequest -UseBasicParsing https://openclaw.ai/install.ps1).Content
# Windows PowerShell 5.1 returns raw bytes for this download; turn them into text.
if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content).TrimStart([char]0xFEFF) }
& ([scriptblock]::Create($content)) -NoOnboard

Update-Path
$cmd = Resolve-OpenClaw
if ($cmd) {
    Write-Host "[OK] OpenClaw ready: $cmd" -ForegroundColor Green
} else {
    Write-Host "[!] OpenClaw installed but its command could not be found. Run 'MM Agent Setup' again;" -ForegroundColor Yellow
    Write-Host "    if it still fails, send a screenshot of: MM Agent Setup  (it prints where Node and OpenClaw are)" -ForegroundColor Yellow
}
