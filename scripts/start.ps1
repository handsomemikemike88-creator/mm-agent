# Start MM Agent: Hermes brain, OpenClaw interface and Hermes dashboard, then open both web pages.
. "$PSScriptRoot\common.ps1"
Update-Path
New-Item -ItemType Directory -Force $MM.LogDir | Out-Null
$PidFile = Join-Path $MM.LogDir 'pids.txt'

# Open a minimized window running $Command, logging to logs\<Log>.log.
function Start-Part([string]$Title, [string]$Command, [string]$Log) {
    # Work from the user's home folder, so the AI's file tools never act inside MM Agent's own files.
    $proc = Start-Process powershell -PassThru -WindowStyle Minimized -WorkingDirectory $HOME -ArgumentList @(
        '-NoProfile', '-Command',
        "`$host.UI.RawUI.WindowTitle='$($MM.Name) - $Title'; $Command *>&1 | Tee-Object -FilePath '$($MM.LogDir)\$Log.log'"
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
    $p = Start-Part 'Brain (Hermes)' 'hermes gateway run --replace' 'brain'
    Wait-Ready { Test-Brain } 'Brain' 300 'brain' $p
    Write-Host "[OK] Brain ready"
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
    $p = Start-Part 'Interface (OpenClaw)' 'openclaw gateway run' 'interface'
    try {
        Wait-Ready { Test-Port $MM.InterfacePort } 'Interface' 300 'interface' $p
    } catch {
        # OpenClaw updated itself and asks for a database upgrade: do it once, then start again.
        $log = Join-Path $MM.LogDir 'interface.log'
        if (-not (Select-String -Path $log -Pattern 'openclaw doctor --fix' -Quiet -ErrorAction SilentlyContinue)) { throw }
        Write-Host "[..] OpenClaw was updated and must upgrade its database first." -ForegroundColor Cyan
        Write-Host "     Running OpenClaw's repair (openclaw doctor --fix). This can take 5-15 minutes; leave this window open." -ForegroundColor Cyan
        $code = Repair-OpenClawState
        if ($code -ne 0) { throw "OpenClaw's repair failed (exit $code). Log: $(Join-Path $MM.LogDir 'openclaw-doctor.log')" }
        Write-Host "[OK] OpenClaw repaired. Starting the interface again ..."
        $p = Start-Part 'Interface (OpenClaw)' 'openclaw gateway run' 'interface'
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
