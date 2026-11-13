# Start MM Agent: Hermes brain, OpenClaw interface and Hermes dashboard, then open both web pages.
# -Background: used by the Windows sign-in (Startup) shortcut - starts everything quietly, opens no
# browser pages, and writes its progress to logs\autostart.log. It first runs the daily update
# (update-all.ps1, at most once a day) unless -NoUpdate is given.
param([switch]$Background, [switch]$NoUpdate)
. "$PSScriptRoot\common.ps1"
Update-Path
New-Item -ItemType Directory -Force $MM.LogDir | Out-Null
$PidFile = Join-Path $MM.LogDir 'pids.txt'
if ($Background) {
    if (-not $NoUpdate) {
        Start-Sleep -Seconds 20     # let Windows finish signing in and the network come up
        # Daily update of Node.js, OpenClaw and Hermes (skipped if it already ran today).
        # A failed update never stops MM Agent from starting. Only when the installer's
        # "update automatically" option is on (it adds the daily task).
        if (Get-ScheduledTask -TaskName 'MM Agent Daily Update' -ErrorAction SilentlyContinue) {
            try { & "$PSScriptRoot\update-all.ps1" -NoStart } catch { Write-Host "[!] Update failed: $_" }
        }
        # If the daily task is updating right now, wait for it (it starts MM Agent itself afterwards).
        $lock = Join-Path $MM.LogDir 'update.lock'
        $waited = 0
        while ((Test-Path $lock) -and ((Get-Item $lock).LastWriteTime -gt (Get-Date).AddHours(-2)) -and $waited -lt 2700) {
            Start-Sleep -Seconds 15; $waited += 15
        }
        Update-Path
    }
    Start-Transcript -Path (Join-Path $MM.LogDir 'autostart.log') -Force | Out-Null
}

# Open a minimized window running $Command, logging to logs\<Log>.log.
# -KeepAlive: run it again whenever it stops (e.g. Hermes' dashboard "Restart Gateway" or a Hermes
# update ends it), so the chat never loses its brain. Stop MM Agent closes the window and the loop.
function Start-Part([string]$Title, [string]$Command, [string]$Log, [switch]$KeepAlive) {
    $logFile = "$($MM.LogDir)\$Log.log"
    # Hermes/OpenClaw print normal progress on stderr; Windows PowerShell 5.1 would show each of those
    # lines as a red "NativeCommandError". Turning every line into plain text avoids the false alarm.
    # (ToString() rather than "$_": inner double quotes are stripped on the way into the new window.)
    $plain = "$Command 2>&1 | ForEach-Object { `$_.ToString() }"
    $run = if ($KeepAlive) {
        "Remove-Item '$logFile' -ErrorAction SilentlyContinue; while (`$true) { $plain | Tee-Object -Append -FilePath '$logFile'; " +
        "Write-Host '[$($MM.Name)] $Title stopped - restarting in 10 seconds (close this window to stop it)'; Start-Sleep -Seconds 10 }"
    } else {
        "$plain | Tee-Object -FilePath '$logFile'"
    }
    # Work from the user's home folder, so the AI's file tools never act inside MM Agent's own files.
    $proc = Start-Process powershell -PassThru -WindowStyle Minimized -WorkingDirectory $HOME -ArgumentList @(
        '-NoProfile', '-Command',
        "`$host.UI.RawUI.WindowTitle='$($MM.Name) - $Title'; $run"
    )
    Add-Content $PidFile $proc.Id
    return $proc
}

# Wait for a check to pass, printing progress so the window never looks frozen.
# Stops at once, showing the log, if the part's window has already closed.
function Wait-Ready([scriptblock]$Ready, [string]$What, [int]$TimeoutSec, [string]$Log, $Proc) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $next = 15
    $logPath = Join-Path $MM.LogDir "$Log.log"
    while (-not (& $Ready)) {
        if ($Proc -and $Proc.HasExited) {
            Write-Host "[!] $What stopped while starting. Last lines of ${logPath}:" -ForegroundColor Red
            Get-Content $logPath -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
            throw "$What did not start. See $logPath"
        }
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) { throw "$What did not start. See $logPath" }
        if ($sw.Elapsed.TotalSeconds -ge $next) {
            Write-Host ("     ... {0} still starting ({1}s)" -f $What, [int]$sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
            $next += 15
        }
        Start-Sleep -Seconds 2
    }
}

Write-Host "== Starting $($MM.Name) ==" -ForegroundColor Cyan
if (Restart-WithoutRedirectionGuard (Join-Path (Split-Path $PSScriptRoot -Parent) 'Start-MM-Agent.cmd')) { return }

# Keys are decrypted into this process only; the windows started below inherit them.
$n = Import-Keys
if ($n -eq 0) { Write-Host "[!] No API keys saved - run Enter-API-Keys.cmd" -ForegroundColor Yellow }
else { Write-Host "[OK] Loaded $n encrypted API key(s)" }

# MM Agent starts and watches Hermes and OpenClaw itself. Their own autostarts (OpenClaw's
# "OpenClaw Gateway" login item, e.g. after 'openclaw gateway install' or 'openclaw doctor --fix',
# and Hermes' "Hermes_Gateway" task, added by some Hermes updates) start a second copy that takes
# the port, after which MM Agent's copy restarts in a loop and the two keep replacing each other.
# Turn those off (moved/disabled, not deleted) and stop a copy they already started.
function Disable-OtherAutostarts {
    $parked = Join-Path $MM.LogDir 'disabled-autostarts'
    $startup = [Environment]::GetFolderPath('Startup')
    Get-ChildItem $startup -Filter 'OpenClaw Gateway*' -ErrorAction SilentlyContinue | ForEach-Object {
        New-Item -ItemType Directory -Force $parked | Out-Null
        Move-Item $_.FullName (Join-Path $parked $_.Name) -Force
        Write-Host "[OK] Turned off OpenClaw's own autostart ($($_.Name)); MM Agent starts OpenClaw"
    }
    foreach ($task in 'OpenClaw Gateway', 'Hermes_Gateway') {
        $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        if ($t -and $t.State -ne 'Disabled') {
            $t | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            Write-Host "[OK] Turned off the task '$task'; MM Agent starts it instead"
        }
    }
    $foreign = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'gateway .*--task-supervisor|service-child-windows-job-anchor' }
    if ($foreign) {
        $foreign | ForEach-Object { & taskkill /PID $_.ProcessId /T /F 2>&1 | Out-Null }
        Write-Host "[OK] Stopped a second OpenClaw started outside MM Agent"
        Start-Sleep -Seconds 3
    }
}
try { Disable-OtherAutostarts } catch { Write-Host "[!] Could not check other autostarts: $_" -ForegroundColor Yellow }

if (Test-Brain) {
    Write-Host "[OK] Brain (Hermes) already running"
} else {
    $reason = Get-HermesRepairReason
    if ($reason) {
        Write-Host "[!] Hermes Agent (the brain) needs repair: $reason" -ForegroundColor Red
        Show-HermesDiagnosis
        throw "Run 'MM Agent Setup' from the Start Menu to repair Hermes Agent."
    }
    Write-Host "[..] Starting brain (Hermes) ..."
    # --replace: take over from a leftover gateway (e.g. from an earlier, failed start).
    $p = Start-Part 'Brain (Hermes)' 'hermes gateway run --replace' 'brain' -KeepAlive
    Wait-Ready { Test-Brain } 'Brain' 300 'brain' $p
    Write-Host "[OK] Brain ready"
}

# Brain healer: clears conversations Hermes blocked after a restart mid-reply ("unknown_execution").
$healerRunning = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'brain-healer\.ps1' }
if (-not $healerRunning) {
    Start-Part 'Brain healer' "powershell -NoProfile -ExecutionPolicy Bypass -File '$PSScriptRoot\brain-healer.ps1'" 'brain-healer' | Out-Null
    Write-Host "[OK] Brain healer running"
}

# A sign-in that setup saved "inactive" (bridge key changed) can only be activated while the
# brain is running, so do it now, before OpenClaw starts.
$pendingFile = Join-Path $MM.LogDir 'openclaw-pending-signin.txt'
if (Test-Path $pendingFile) {
    $id, $agent = (Get-Content $pendingFile -Raw).Trim() -split '\s+'
    $activate = @('models', 'auth', 'activate', $id) + $(if ($agent) { @('--agent', $agent) })
    Write-Host "[..] Activating the new Hermes sign-in in OpenClaw ..."
    if ((Invoke-WithProgress -Exe (Resolve-OpenClaw) -Arguments $activate -Label 'activate-signin') -eq 0) {
        Remove-Item $pendingFile
        Write-Host "[OK] Sign-in activated"
        if (Test-Port $MM.InterfacePort) { Write-Host "[!] OpenClaw was already running: Stop and Start MM Agent to use the new sign-in." -ForegroundColor Yellow }
    } else {
        Write-Host "[!] Could not activate the sign-in. Log: $(Join-Path $MM.LogDir 'activate-signin.log')" -ForegroundColor Yellow
    }
}

if (Test-Port $MM.InterfacePort) {
    Write-Host "[OK] Interface (OpenClaw) already running"
} else {
    Write-Host "[..] Starting interface (OpenClaw) ..."
    # -KeepAlive: if OpenClaw stops (crash, or something ends it), it is started again within seconds,
    # so WhatsApp/Telegram never stay without an answer.
    $p = Start-Part 'Interface (OpenClaw)' 'openclaw gateway run' 'interface' -KeepAlive
    try {
        Wait-Ready { Test-Port $MM.InterfacePort } 'Interface' 300 'interface' $p
    } catch {
        # OpenClaw updated itself and asks for a database upgrade: do it once, then start again.
        $log = Join-Path $MM.LogDir 'interface.log'
        if (-not (Select-String -Path $log -Pattern 'openclaw doctor --fix' -Quiet -ErrorAction SilentlyContinue)) { throw }
        & taskkill /PID $p.Id /T /F 2>$null | Out-Null    # stop the restart loop while the database is upgraded
        Write-Host "[..] OpenClaw was updated and must upgrade its database first." -ForegroundColor Cyan
        Write-Host "     Running OpenClaw's repair (openclaw doctor --fix). This can take 5-15 minutes; leave this window open." -ForegroundColor Cyan
        $code = Repair-OpenClawState
        if ($code -ne 0) { throw "OpenClaw's repair failed (exit $code). Log: $(Join-Path $MM.LogDir 'openclaw-doctor.log')" }
        Write-Host "[OK] OpenClaw repaired. Starting the interface again ..."
        $p = Start-Part 'Interface (OpenClaw)' 'openclaw gateway run' 'interface' -KeepAlive
        Wait-Ready { Test-Port $MM.InterfacePort } 'Interface' 300 'interface' $p
    }
    Write-Host "[OK] Interface ready"
}

$dashUrl = "http://127.0.0.1:$($MM.DashboardPort)/"
$dashProc = $null
if (Test-Port $MM.DashboardPort) {
    Write-Host "[OK] Hermes dashboard already running"
} else {
    Write-Host "[..] Starting Hermes dashboard (the first start builds its web pages: a few minutes) ..."
    $dashProc = Start-Part 'Hermes dashboard' "hermes dashboard --no-open --port $($MM.DashboardPort)" 'hermes-dashboard'
}

if ($Background) {
    # Started at Windows sign-in: everything runs, but no browser pages pop up.
    Write-Host "[OK] $($MM.Name) started in the background. Chat: http://127.0.0.1:$($MM.InterfacePort)/"
    Stop-Transcript | Out-Null
    return
}

Write-Host "[..] Opening the OpenClaw chat page ..."
$ErrorActionPreference = 'Continue'     # OpenClaw prints harmless warnings on stderr
& openclaw dashboard 2>$null | Where-Object { $_ -match 'Dashboard URL|Opened' } | ForEach-Object { Write-Host "     $_" }
$ErrorActionPreference = 'Stop'

# The Hermes dashboard is an extra: if it cannot start, the chat still works, so only warn.
try {
    if (-not (Test-Port $MM.DashboardPort)) { Wait-Ready { Test-Port $MM.DashboardPort } 'Hermes dashboard' 600 'hermes-dashboard' $dashProc }
    Start-Process $dashUrl
    Write-Host "[OK] Hermes dashboard: $dashUrl"
} catch {
    Write-Host "[!] The Hermes dashboard could not start; the OpenClaw chat still works." -ForegroundColor Yellow
    Write-Host "    Run 'MM Agent Setup' from the Start Menu to repair Hermes, then start again." -ForegroundColor Yellow
    $dashUrl = '(not running)'
}

Write-Host ""
Write-Host "$($MM.Name) is running:" -ForegroundColor Green
Write-Host "  Chat (OpenClaw):         http://127.0.0.1:$($MM.InterfacePort)/"
Write-Host "  Brain panel (Hermes):    $dashUrl"
Write-Host "  (127.0.0.1:$($MM.BrainPort) is the brain's internal API for OpenClaw, not a web page.)"
Write-Host "Close everything with Stop-MM-Agent.cmd"
