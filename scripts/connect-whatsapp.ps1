# Connect WhatsApp to MM Agent (through the OpenClaw interface): install OpenClaw's WhatsApp
# plugin if needed, apply safe settings, then link by scanning a QR code like WhatsApp Web.
. "$PSScriptRoot\common.ps1"
Update-Path

Write-Host "== $($MM.Name): connect WhatsApp ==" -ForegroundColor Cyan
Write-Host @"
WhatsApp is linked the way WhatsApp Web is: you scan a QR code with your phone.
Tip: a separate WhatsApp number is safer. Linking uses an unofficial WhatsApp Web library,
and WhatsApp may restrict numbers it thinks are automated.

"@
$openclaw = Resolve-OpenClaw
if (-not $openclaw) { throw "OpenClaw is not installed. Run 'MM Agent Setup' first." }
$ErrorActionPreference = 'Continue'     # OpenClaw prints harmless warnings on stderr

# 1) OpenClaw's WhatsApp support is a plugin that is not installed by default. (The status
#    listing can be slow right after a plugin change, so it runs with a time limit.)
$null = Invoke-WithProgress -Exe $openclaw -Arguments @('channels', 'list', '--all') -Label 'channels' -TimeoutSec 180 -Quiet
$status = (Select-String -Path (Join-Path $MM.LogDir 'channels.log') -Pattern '(?i)^\s*-\s*WhatsApp' | Select-Object -First 1).Line
if (-not $status -or $status -match 'not installed') {
    Write-Host "[..] Installing OpenClaw's WhatsApp plugin (1-3 minutes) ..."
    # OpenClaw picks the plugin version that matches its own version.
    $code = Invoke-WithProgress -Exe $openclaw -Arguments @('plugins', 'install', '@openclaw/whatsapp',
        '--accept-capabilities', '--acknowledge-install-policy-warning') -Label 'whatsapp-plugin'
    $log = Join-Path $MM.LogDir 'whatsapp-plugin.log'
    if ($code -ne 0 -and -not (Select-String -Path $log -Pattern 'plugin already exists' -Quiet)) {
        throw "Could not install the WhatsApp plugin. Log: $log"
    }
}
Write-Host "[OK] WhatsApp plugin ready"

# 2) Safe defaults: strangers who message the number get a pairing code that you must approve;
#    in groups the assistant only answers when @mentioned. (Without enabled=true the channel stays off.)
$patch = @{ channels = @{ whatsapp = @{ enabled = $true; dmPolicy = 'pairing'; groups = @{ '*' = @{ requireMention = $true } } } } } |
    ConvertTo-Json -Depth 6
$patchFile = Join-Path $env:TEMP 'mm-whatsapp.patch.json'
[IO.File]::WriteAllText($patchFile, $patch, (New-Object Text.UTF8Encoding $false))
Backup-File (Join-Path $HOME '.openclaw\openclaw.json')
& $openclaw config patch --file $patchFile 2>$null | Out-Null
$code = $LASTEXITCODE
Remove-Item $patchFile
if ($code -ne 0) { throw "Could not save the WhatsApp settings (exit $code)." }

# 3) Link: OpenClaw prints a QR code in this window.
Write-Host @"

On your phone: WhatsApp > Settings (or the 3 dots) > Linked devices > Link a device,
then scan the QR code that appears below. The window may need to be maximised to show it fully.
"@ -ForegroundColor Cyan
& $openclaw channels login --channel whatsapp
if ($LASTEXITCODE -ne 0) { throw "WhatsApp was not linked (exit $LASTEXITCODE). Run Connect-WhatsApp again." }

Write-Host "[OK] WhatsApp linked to $($MM.Name)" -ForegroundColor Green
Write-Host @"

Next:
  1. Start-MM-Agent (if it is already running, Stop and Start it once).
  2. From ANOTHER phone, send any message to the linked WhatsApp number. It replies with a pairing code.
  3. Approve-WhatsApp, and type that code (codes expire after 1 hour).
"@
