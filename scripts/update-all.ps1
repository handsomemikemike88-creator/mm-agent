# Update everything MM Agent uses: Node.js, OpenClaw (interface) and Hermes Agent (brain).
# Runs by itself once a day (at Windows sign-in, and from the daily "MM Agent Daily Update" task),
# or any time from Start Menu -> MM Agent -> Update MM Agent.
#
# Why MM Agent does this itself: OpenClaw and Hermes refuse to replace their files while they are
# running (OpenClaw's own "/update" fails with "gateway-stop-unverified"), so the update has to stop
# MM Agent first, update, and start it again. Progress is written to logs\update.log.
#
#   -Force      update even if it already ran today
#   -NoStart    don't start MM Agent afterwards (start.ps1 uses this; it starts everything itself)
#   -Restart    always start MM Agent afterwards (used by the daily task), even if it was not running
param([switch]$Force, [switch]$NoStart, [switch]$Restart)
. "$PSScriptRoot\common.ps1"
Update-Path
New-Item -ItemType Directory -Force $MM.LogDir | Out-Null
$stamp = Join-Path $MM.LogDir 'last-update.txt'
$today = Get-Date -Format 'yyyy-MM-dd'

if (-not $Force -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $today)) {
    Write-Host "[OK] $($MM.Name) was already updated today ($today)."
    return
}

# Only one update at a time (sign-in and the daily task could meet).
$lock = Join-Path $MM.LogDir 'update.lock'
if ((Test-Path $lock) -and ((Get-Item $lock).LastWriteTime -gt (Get-Date).AddHours(-2))) {
    Write-Host "[..] Another update is running; skipping."
    return
}
Set-Content $lock $PID

$transcript = $false
try { Start-Transcript -Path (Join-Path $MM.LogDir 'update.log') -Append | Out-Null; $transcript = $true } catch {}
$ErrorActionPreference = 'Continue'   # one part failing must not stop the others (or the restart)
$failed = @()

try {
    Write-Host "== Updating $($MM.Name) ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) ==" -ForegroundColor Cyan
    if (Restart-WithoutRedirectionGuard (Join-Path (Split-Path $PSScriptRoot -Parent) 'Update-MM-Agent.cmd')) { return }

    # 1. Stop MM Agent: both programs lock their own files while running.
    $wasRunning = (Test-Brain) -or (Test-Port $MM.InterfacePort) -or (Test-Port $MM.DashboardPort)
    if ($wasRunning) {
        Write-Host "[..] Stopping $($MM.Name) for the update ..."
        & "$PSScriptRoot\stop.ps1"
        Start-Sleep -Seconds 5
        # Anything still holding MM Agent's ports was started some other way: end it too.
        foreach ($port in $MM.BrainPort, $MM.InterfacePort, $MM.DashboardPort) {
            Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty OwningProcess -Unique |
                ForEach-Object { & taskkill /PID $_ /T /F 2>$null | Out-Null }
        }
        Start-Sleep -Seconds 2
    }

    # 2. Node.js. A new Node replaces its folder, and OpenClaw lives inside it, so reinstall OpenClaw then.
    $nodeExe = Join-Path $MM.NodeDir 'node.exe'
    $nodeBefore = if (Test-Path $nodeExe) { & $nodeExe -v 2>$null } else { $null }
    try { & "$PSScriptRoot\install-node.ps1" } catch { Write-Host "[!] Node.js update failed: $_" -ForegroundColor Yellow; $failed += 'Node.js' }
    Update-Path
    $nodeAfter = if (Test-Path $nodeExe) { & $nodeExe -v 2>$null } else { $null }

    # 3. OpenClaw.
    $oc = Resolve-OpenClaw
    if ($nodeBefore -ne $nodeAfter -or -not $oc) {
        Write-Host "[..] Reinstalling OpenClaw on Node.js $nodeAfter ..."
        try { & "$PSScriptRoot\install-openclaw.ps1" } catch { Write-Host "[!] OpenClaw install failed: $_" -ForegroundColor Yellow; $failed += 'OpenClaw' }
    } else {
        $have = ((& $oc --version 2>$null) -join ' ') -replace '^.*?(\d{4}\.\d+\.\d+\S*).*$', '$1'
        $latest = ((& npm view openclaw version 2>$null) | Select-Object -Last 1)
        if ($latest) { $latest = $latest.Trim() }
        if (-not $latest) {
            Write-Host "[!] Could not ask npm for the newest OpenClaw (no internet?)" -ForegroundColor Yellow; $failed += 'OpenClaw'
        } elseif ($have -eq $latest) {
            Write-Host "[OK] OpenClaw $have is the newest version"
        } else {
            # Straight to npm: OpenClaw's own updater ('openclaw update') spends ~8 minutes on safety checks and
            # then fails on most Windows PCs (SQLite backup worker / C:\ permissions), keeping chats down longer.
            # The gateway migrates its data itself on the next start.
            Write-Host "[..] Updating OpenClaw $have -> $latest (npm) ..."
            $npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
            $code = Invoke-WithProgress -Exe $npm -Arguments @('install', '-g', "openclaw@$latest") -Label 'openclaw-npm-update' -TimeoutSec 1800
            $now = ((& $oc --version 2>$null) -join ' ') -replace '^.*?(\d{4}\.\d+\.\d+\S*).*$', '$1'
            if ($now -ne $latest) {
                Write-Host "[..] npm did not finish (exit $code); trying OpenClaw's own updater ..."
                $code = Invoke-WithProgress -Exe $oc -Arguments @('update', '--yes', '--no-restart') -Label 'openclaw-update' -TimeoutSec 1800
                $now = ((& $oc --version 2>$null) -join ' ') -replace '^.*?(\d{4}\.\d+\.\d+\S*).*$', '$1'
            }
            if ($now -eq $latest) { Write-Host "[OK] OpenClaw updated to $now" -ForegroundColor Green }
            else { Write-Host "[!] OpenClaw is still $now (wanted $latest). Log: $(Join-Path $MM.LogDir 'openclaw-update.log')" -ForegroundColor Yellow; $failed += 'OpenClaw' }
        }
    }

    # 4. Hermes Agent.
    $check = (& hermes update --check 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    if ($check -match '(?i)update available|behind') {
        $before = ((& hermes --version 2>$null) | Select-Object -First 1)
        Write-Host "[..] Updating Hermes Agent ($before) ..."
        $hermes = (Get-Command hermes -ErrorAction SilentlyContinue).Source
        $code = Invoke-WithProgress -Exe $hermes -Arguments @('update', '--yes') -Label 'hermes-update' -TimeoutSec 1800
        $reason = Get-HermesRepairReason
        if ($reason) {
            # A half-finished Hermes update leaves the brain unable to start: repair it with the official installer.
            Write-Host "[..] Hermes update did not finish cleanly ($reason); repairing ..." -ForegroundColor Yellow
            try { & "$PSScriptRoot\install-hermes.ps1" } catch { Write-Host "[!] Hermes repair failed: $_" -ForegroundColor Yellow }
            Update-Path
            $reason = Get-HermesRepairReason
        }
        if ($reason) { Write-Host "[!] Hermes Agent needs repair: $reason" -ForegroundColor Red; $failed += 'Hermes Agent' }
        else { Write-Host "[OK] Hermes Agent updated: $((& hermes --version 2>$null) | Select-Object -First 1)" -ForegroundColor Green }
    } elseif ($check -match '(?i)up to date|already|no newer release|checkout is newer') {
        Write-Host "[OK] Hermes Agent is the newest version"
    } else {
        Write-Host "[!] Could not check for a Hermes update:" -ForegroundColor Yellow
        $check -split "`n" | Select-Object -Last 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        $failed += 'Hermes Agent'
    }

    # Mark today as done only when everything worked, so a failed part is tried again at the next start.
    if ($failed.Count -eq 0) { Set-Content $stamp $today; Write-Host "[OK] Everything is up to date." -ForegroundColor Green }
    else { Write-Host "[!] Not updated: $($failed -join ', '). It will be tried again at the next start." -ForegroundColor Yellow }
} finally {
    Remove-Item $lock -ErrorAction SilentlyContinue
    if ($transcript) { Stop-Transcript | Out-Null }
}

# 5. Start MM Agent again (quietly, without browser pages).
if (-not $NoStart -and ($wasRunning -or $Restart)) {
    Write-Host "[..] Starting $($MM.Name) again ..."
    & "$PSScriptRoot\start.ps1" -Background -NoUpdate
}
