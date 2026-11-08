# Keeps chats from getting stuck after the brain restarts.
# If Hermes restarts in the middle of a reply (daily update, crash, MM Agent's auto-restart), that
# reply is lost and Hermes blocks the whole conversation with "unknown_execution"; WhatsApp/Telegram
# then only get "OpenClaw couldn't finish this reply". Every minute this checks Hermes' database
# (read-only) for such lost turns and acknowledges them with Hermes' own command
# `hermes sessions discard <session> --yes`, so the conversation works again. The lost message is
# not re-sent; the client simply asks again. Started by start.ps1; stopped by Stop MM Agent.
. "$PSScriptRoot\common.ps1"
Update-Path
$ErrorActionPreference = 'Continue'
$node = Join-Path $MM.NodeDir 'node.exe'
$finder = Join-Path $PSScriptRoot 'hermes-unknown.mjs'
$db = Join-Path $MM.HermesHome 'state.db'
Write-Host "[$($MM.Name)] Brain healer: checking for stuck conversations every 60 seconds."
while ($true) {
    if ((Test-Path $node) -and (Test-Brain)) {
        $ids = & $node $finder $db 2>$null | Where-Object { $_ -match '^[\w.:-]+$' }
        foreach ($id in $ids) {
            $out = & hermes sessions discard $id --yes 2>&1 | ForEach-Object { $_.ToString() }
            Write-Host ("{0}  cleared lost turn in {1}: {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $id, ($out -join ' '))
        }
    }
    Start-Sleep -Seconds 60
}
