# Type your provider API keys. Input is hidden; each key is saved encrypted (Windows DPAPI)
# in a private file outside Hermes and OpenClaw. Only your Windows account on this PC can decrypt it.
. "$PSScriptRoot\common.ps1"

Write-Host "== $($MM.Name): enter API keys ==" -ForegroundColor Cyan
Write-Host "Paste a key and press Enter. Press Enter on an empty line to keep the current value.`n"

foreach ($id in $Providers.Keys) {
    $p = $Providers[$id]
    $state = if (Test-Key $p.KeyVar) { 'saved' } else { 'empty' }
    $secure = Read-Host -AsSecureString ("{0} key [{1}]" -f $p.Label, $state)
    if ($secure.Length -gt 0) {
        Save-Key $p.KeyVar $secure
        Write-Host "   saved (encrypted)" -ForegroundColor Green
    }
    $secure.Dispose()
}

Write-Host "`nDone. Encrypted keys: $($MM.KeysFile)"
if (Test-Brain) { Write-Host "Restart MM Agent (Stop + Start) to use the new keys." -ForegroundColor Yellow }
