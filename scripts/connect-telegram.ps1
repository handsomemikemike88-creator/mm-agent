# Connect a Telegram bot to MM Agent (through the OpenClaw interface).
# The token is typed hidden, checked with Telegram, and saved to a private file.
. "$PSScriptRoot\common.ps1"
Update-Path

Write-Host "== $($MM.Name): connect Telegram ==" -ForegroundColor Cyan
Write-Host @"
1. In Telegram, open a chat with @BotFather (check the handle is exactly @BotFather).
2. Send /newbot, choose a display name, then a username ending in 'bot'.
3. BotFather replies with a token like 123456789:AA...  Copy it.

"@

$secure = Read-Host -AsSecureString 'Paste the bot token'
$token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)).Trim()
if ($token -notmatch '^\d{5,}:[A-Za-z0-9_-]{30,}$') { throw 'That does not look like a Telegram bot token.' }

try {
    $me = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/getMe" -TimeoutSec 15
} catch { throw 'Telegram rejected the token. Copy it again from @BotFather.' }
$botName = $me.result.username
Write-Host "[OK] Token valid for @$botName" -ForegroundColor Green

# Private token file, readable only by this Windows user.
$secretDir = Join-Path $HOME '.openclaw\secrets'
New-Item -ItemType Directory -Force $secretDir | Out-Null
$tokenFile = Join-Path $secretDir 'telegram-bot-token.txt'
[IO.File]::WriteAllText($tokenFile, $token, (New-Object Text.UTF8Encoding $false))
& icacls $tokenFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
$token = $null

# Pairing = strangers who message the bot get a code; only approved people can use MM Agent.
# In groups the bot only answers when @mentioned.
$patch = @{
    channels = @{
        telegram = @{
            enabled   = $true
            tokenFile = ($tokenFile -replace '\\', '/')
            dmPolicy  = 'pairing'
            groups    = @{ '*' = @{ requireMention = $true } }
        }
    }
} | ConvertTo-Json -Depth 6
$patchFile = Join-Path $env:TEMP 'mm-telegram.patch.json'
[IO.File]::WriteAllText($patchFile, $patch, (New-Object Text.UTF8Encoding $false))

Backup-File (Join-Path $HOME '.openclaw\openclaw.json')
$ErrorActionPreference = 'Continue'     # OpenClaw prints harmless warnings on stderr
& openclaw config patch --file $patchFile 2>$null | Out-Host
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Remove-Item $patchFile
if ($code -ne 0) { throw "Could not save the Telegram settings (exit $code)." }

Write-Host "[OK] Telegram connected to $($MM.Name)" -ForegroundColor Green
Write-Host @"

Next:
  1. Start-MM-Agent.cmd   (if it is already running, the change applies automatically)
  2. In Telegram, open https://t.me/$botName and send it any message.
     It replies with a pairing code.
  3. Approve-Telegram.cmd  and type that code (codes expire after 1 hour).
"@
