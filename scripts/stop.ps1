# Stop the brain + interface windows that start.ps1 opened.
. "$PSScriptRoot\common.ps1"

$PidFile = Join-Path $MM.LogDir 'pids.txt'
$stopped = 0
if (Test-Path $PidFile) {
    foreach ($id in Get-Content $PidFile) {
        if ($id -and (Get-Process -Id $id -ErrorAction SilentlyContinue)) {
            # /T also ends the hermes / node child processes.
            & taskkill /PID $id /T /F | Out-Null
            $stopped++
        }
    }
    Remove-Item $PidFile
}
Write-Host "Stopped $stopped MM Agent process(es)."
