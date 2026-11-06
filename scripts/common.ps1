# Shared settings and helpers for MM Agent.
# Hermes Agent = brain (models, memory, tools)  ->  OpenClaw = interface (dashboard, chat apps)

$ErrorActionPreference = 'Stop'

$MM = [ordered]@{
    Name          = 'MM Agent'
    HermesHome    = Join-Path $env:LOCALAPPDATA 'hermes'
    HermesEnv     = Join-Path $env:LOCALAPPDATA 'hermes\.env'
    HermesConfig  = Join-Path $env:LOCALAPPDATA 'hermes\config.yaml'
    BrainPort     = 8642
    InterfacePort = 18789               # OpenClaw gateway + chat dashboard
    DashboardPort = 9119                # Hermes web dashboard
    BrainModel    = 'mm-agent'          # name Hermes reports on /v1/models
    BrainProvider = 'mm-brain'          # provider id inside OpenClaw
    LogDir        = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
    # Provider API keys live outside both programs, encrypted for this Windows user (DPAPI).
    KeysFile      = Join-Path $HOME '.mm-agent\keys.env'
    # MM Agent's own Node.js (latest even major), shared with OpenClaw's installer.
    NodeDir       = Join-Path $env:LOCALAPPDATA 'OpenClaw\deps\portable-node'
}
$MM.BrainUrl = "http://127.0.0.1:$($MM.BrainPort)/v1"

# The four model providers MM Agent supports (Hermes provider id -> key + default model).
$Providers = [ordered]@{
    deepseek  = @{ Label = 'DeepSeek';           KeyVar = 'DEEPSEEK_API_KEY';  Model = 'deepseek-v4-pro' }
    openai    = @{ Label = 'OpenAI';             KeyVar = 'OPENAI_API_KEY';    Model = 'gpt-5.5';          HermesId = 'openai-api' }
    anthropic = @{ Label = 'Anthropic (Claude)'; KeyVar = 'ANTHROPIC_API_KEY'; Model = 'claude-sonnet-5-5' }
    kimi      = @{ Label = 'Kimi (Moonshot)';    KeyVar = 'KIMI_API_KEY';      Model = 'kimi-k2.6';        HermesId = 'kimi-coding' }
}

function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'Machine')
    Use-MMNode
}

# Put MM Agent's Node first for this process, so an older Node elsewhere (Program Files,
# Hermes' bundled copy) never shadows it.
function Use-MMNode {
    if (Test-Path (Join-Path $MM.NodeDir 'node.exe')) {
        $env:Path = "$($MM.NodeDir);" + (($env:Path -split ';' | Where-Object { $_ -and $_ -ine $MM.NodeDir }) -join ';')
    }
}

# Add a folder to the user's saved PATH (and this process) if it is not there yet.
function Add-UserPath([string]$Dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($user -split ';') | Where-Object { $_ -ieq $Dir })) {
        [Environment]::SetEnvironmentVariable('Path', ((@($user -split ';' | Where-Object { $_ }) + $Dir) -join ';'), 'User')
    }
    if (-not (($env:Path -split ';') | Where-Object { $_ -ieq $Dir })) { $env:Path = "$env:Path;$Dir" }
}

# Find openclaw.cmd wherever npm put it and make sure its folder is on the saved PATH.
# (OpenClaw's installer skips saving PATH when the command is only visible in its own window,
# e.g. when it used Hermes' bundled Node.) Returns the full path, or $null.
function Resolve-OpenClaw {
    $found = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $dirs = @($MM.NodeDir, (Join-Path $env:APPDATA 'npm'), (Join-Path $MM.HermesHome 'node'), (Join-Path $HOME '.local\bin'))
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npm) {
        $prefix = (& $npm.Source config get prefix 2>$null | Select-Object -Last 1)
        if ($prefix) { $dirs += $prefix.Trim(); $dirs += (Join-Path $prefix.Trim() 'bin') }
    }
    foreach ($d in $dirs | Select-Object -Unique) {
        if ($d -and (Test-Path (Join-Path $d 'openclaw.cmd'))) {
            Add-UserPath $d
            return (Join-Path $d 'openclaw.cmd')
        }
    }
    return $null
}

# ---- Hermes' .env ----
# A healthy .env is a few KB. Hermes documents a corruption where KEY=VALUE pairs end up glued on
# one line with values repeated (hermes-agent #8908); such a line can grow until reading it runs out
# of memory. Lines are read in chunks, so even a huge file cannot exhaust memory.
$MaxEnvBytes = 1MB
$MaxEnvLine = 8192

# Return the .env lines, rebuilding the file first if it is corrupted.
function Read-HermesEnvLines {
    if (-not (Test-Path $MM.HermesEnv)) { return @() }
    $result = Read-EnvLinesSafely $MM.HermesEnv
    if ($result.Corrupt) {
        $bad = "$($MM.HermesEnv).mm-corrupt.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Move-Item $MM.HermesEnv $bad     # a rename: instant even for a huge file, nothing is lost
        [IO.File]::WriteAllLines($MM.HermesEnv, [string[]]$result.Lines, (New-Object Text.UTF8Encoding $false))
        Write-Host ("[!] Hermes' settings file (.env) was corrupted ({0:N1} MB). Rebuilt it with its {1} valid line(s);" -f ($result.Bytes / 1MB), $result.Lines.Count) -ForegroundColor Yellow
        Write-Host "    the damaged copy is kept as $bad" -ForegroundColor Yellow
    }
    return $result.Lines
}

# Read a .env file in 64 KB chunks (fast and memory-safe even for a multi-GB file).
# Corrupt = the file was over 1 MB or had damaged lines, so it needs rebuilding.
function Read-EnvLinesSafely([string]$Path) {
    $s = @{
        Bytes   = (Get-Item $Path).Length
        Kept    = New-Object 'System.Collections.Generic.List[string]'
        Line    = New-Object Text.StringBuilder
        TooLong = $false
    }
    $s.Corrupt = $s.Bytes -gt $MaxEnvBytes
    $reader = New-Object IO.StreamReader($Path, [Text.Encoding]::UTF8, $true)
    try {
        $buf = New-Object char[] 65536
        while (($n = $reader.Read($buf, 0, $buf.Length)) -gt 0) {
            $chunk = New-Object string($buf, 0, $n)
            $start = 0
            while ($true) {
                $nl = $chunk.IndexOf("`n", $start)
                $end = if ($nl -ge 0) { $nl } else { $chunk.Length }
                if (-not $s.TooLong) {
                    if ($s.Line.Length + ($end - $start) -gt $MaxEnvLine) { $s.TooLong = $true; [void]$s.Line.Clear() }
                    else { [void]$s.Line.Append($chunk, $start, $end - $start) }
                }
                if ($nl -lt 0) { break }
                Complete-EnvLine $s
                $start = $nl + 1
            }
        }
        if ($s.Line.Length -gt 0 -or $s.TooLong) { Complete-EnvLine $s }
    } finally { $reader.Dispose() }
    return @{ Lines = $s.Kept.ToArray(); Corrupt = $s.Corrupt; Bytes = $s.Bytes }
}

# Decide whether one finished line of a .env file is kept (helper for Read-EnvLinesSafely).
# Only real damage is dropped: over-long lines and lines with NUL bytes. Everything else is kept as is.
function Complete-EnvLine($s) {
    $text = $s.Line.ToString().TrimEnd("`r")
    if ($s.TooLong -or $text.Contains([char]0)) { $s.Corrupt = $true }
    else { $s.Kept.Add($text) }
    [void]$s.Line.Clear()
    $s.TooLong = $false
}

function Get-EnvValue([string]$Name) {
    $line = Read-HermesEnvLines | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -Last 1
    if ($line) { return ($line -split '=', 2)[1].Trim() }
    return $null
}

# Insert or replace NAME=value in Hermes' .env without printing the value.
function Set-EnvValue([string]$Name, [string]$Value) {
    $lines = @(Read-HermesEnvLines)
    $pattern = "^\s*$([regex]::Escape($Name))="
    $found = $false
    $lines = $lines | ForEach-Object {
        if ($_ -match $pattern) { $found = $true; "$Name=$Value" } else { $_ }
    }
    if (-not $found) { $lines = @($lines) + "$Name=$Value" }
    [IO.File]::WriteAllLines($MM.HermesEnv, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
}

# ---- Encrypted key file: NAME=dpapi:<ciphertext>, one per line ----

function Read-KeyLines {
    if (Test-Path $MM.KeysFile) { return @(Get-Content $MM.KeysFile) }
    return @()
}

function Test-Key([string]$Name) {
    return [bool](Read-KeyLines | Where-Object { $_ -match "^$([regex]::Escape($Name))=dpapi:." })
}

# Store a SecureString encrypted; the plain key never touches disk.
function Save-Key([string]$Name, [Security.SecureString]$Secret) {
    $dir = Split-Path $MM.KeysFile -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
        # Only this Windows user may open the folder.
        & icacls $dir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
    }
    $cipher = ConvertFrom-SecureString $Secret
    $lines = @(Read-KeyLines | Where-Object { $_ -notmatch "^$([regex]::Escape($Name))=" }) + "$Name=dpapi:$cipher"
    [IO.File]::WriteAllLines($MM.KeysFile, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
}

# Decrypt all keys into this process's environment, so the Hermes started from here inherits them.
function Import-Keys {
    $count = 0
    foreach ($line in Read-KeyLines) {
        if ($line -match '^([A-Z0-9_]+)=dpapi:(.+)$') {
            $secure = ConvertTo-SecureString $Matches[2]
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { [Environment]::SetEnvironmentVariable($Matches[1], [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr), 'Process') }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $count++
        }
    }
    return $count
}

function Test-Brain {
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($MM.BrainPort)/health" -TimeoutSec 3
        return ($r.status -eq 'ok')
    } catch { return $false }
}

function Test-Port([int]$Port) {
    $client = New-Object Net.Sockets.TcpClient
    try { $client.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $client.Close() }
}

# True when Windows' RedirectionGuard is enforced on this process. It is inherited from the
# program that started us (e.g. an Inno Setup 6.7 installer) and blocks uv's Python junctions.
function Test-RedirectionGuard {
    if (-not ('MMRedirectionTrust' -as [type])) {
        Add-Type @"
using System; using System.Runtime.InteropServices;
public static class MMRedirectionTrust {
  [StructLayout(LayoutKind.Sequential)] public struct POLICY { public uint Flags; }
  [DllImport("kernel32.dll")] static extern bool GetProcessMitigationPolicy(IntPtr h, int policy, ref POLICY p, IntPtr size);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  // 16 = ProcessRedirectionTrustPolicy; bit 0 = EnforceRedirectionTrust
  public static bool Enforced() { var p = new POLICY(); return GetProcessMitigationPolicy(GetCurrentProcess(), 16, ref p, (IntPtr)4) && (p.Flags & 1) != 0; }
}
"@
    }
    try { return [MMRedirectionTrust]::Enforced() } catch { return $false }
}

# If RedirectionGuard is on, reopen $CmdFile in a fresh window started by Explorer (which does
# not have it) and return $true; the caller should then exit.
function Restart-WithoutRedirectionGuard([string]$CmdFile) {
    if (-not (Test-RedirectionGuard)) { return $false }
    Write-Host "[..] This window has Windows' RedirectionGuard switched on, which breaks Hermes' Python." -ForegroundColor Yellow
    Write-Host "     Reopening in a normal window ..." -ForegroundColor Yellow
    Start-Process (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList "`"$CmdFile`""
    return $true
}

# Remove uv's Python "minor version" junctions whose target is gone (astral-sh/uv#19622).
# Only the link is deleted, never an installed Python.
function Repair-UvPythonLinks {
    $dirs = @($env:UV_PYTHON_INSTALL_DIR, (Join-Path $env:APPDATA 'uv\python')) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($d in $dirs) {
        Get-ChildItem $d -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $_.Name -match '^cpython-\d+\.\d+-' } |
            ForEach-Object {
                $target = @($_.Target)[0]
                if (-not $target -or -not (Test-Path -LiteralPath $target)) {
                    [IO.Directory]::Delete($_.FullName, $false)
                    Write-Host "     removed broken uv Python link: $($_.Name)" -ForegroundColor DarkGray
                }
            }
    }
}

# True when the hermes command actually runs (not just exists). A Hermes install can leave
# hermes.exe behind while the Python it launches is missing (cut-short install, or antivirus).
function Test-Hermes {
    $cmd = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    $ErrorActionPreference = 'Continue'
    $out = & $cmd.Source --version 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0 -and $out -match 'Hermes Agent')
}

# Python paths stored in the hermes launcher (uv-style launchers keep them near the end of the .exe).
function Get-HermesLauncherTargets {
    $cmd = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $cmd -or $cmd.Source -notlike '*.exe') { return @() }
    $bytes = [IO.File]::ReadAllBytes($cmd.Source)
    $tail = [Text.Encoding]::UTF8.GetString($bytes, [Math]::Max(0, $bytes.Length - 4096), [Math]::Min(4096, $bytes.Length))
    return @([regex]::Matches($tail, '[A-Za-z]:\\[^\x00"\r\n]{3,260}?\.exe') | Select-Object -ExpandProperty Value -Unique)
}

# Why Hermes needs its installer re-run, or $null when it looks complete and working.
function Get-HermesRepairReason {
    if (-not (Test-Hermes)) { return 'Hermes Agent does not run' }
    if (Test-Path (Join-Path $MM.HermesHome '.hermes-update-in-progress')) { return 'a Hermes Agent update did not finish' }
    $mismatch = Get-HermesPythonMismatch
    if ($mismatch) { return "a Hermes Agent update did not finish ($mismatch)" }
    $said = Test-HermesUpdateFinished
    if ($said) { return "a Hermes Agent update did not finish (Hermes says: $said)" }
    return $null
}

# Newer Hermes finishes an interrupted update at the start of almost every command, but NOT for
# --version/--help (hermes_cli/venv_sync.py, _METADATA_FLAGS). Run a harmless command that does
# go through that step and return Hermes' own failure message, or $null when all is well.
function Test-HermesUpdateFinished {
    $cmd = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    # Finishing a pending update can take minutes, so show progress while it runs.
    $null = Invoke-WithProgress -Exe $cmd.Source -Arguments @('config', 'path') -Label 'hermes-check' -Quiet
    $log = Join-Path $MM.LogDir 'hermes-check.log'
    $hit = Select-String -Path $log -Pattern 'source-update completion failed|source update is unfinished|run `hermes pm repair`|dependency sync left this install out of date' |
        Select-Object -First 1
    if ($hit) { return ($hit.Line.Trim() -replace '^hermes:\s*', '') }
    return $null
}

# Detect a half-finished Hermes update: the program needs a newer Python than its environment
# (venv) has, e.g. "==3.14.*" vs 3.11. `hermes --version` still works then, but starting the
# brain fails with "requested interpreter ... is incompatible". Returns a description, or $null.
function Get-HermesPythonMismatch {
    $agent = Join-Path $MM.HermesHome 'hermes-agent'
    $cfg = Join-Path $agent 'venv\pyvenv.cfg'
    $proj = Join-Path $agent 'pyproject.toml'
    if (-not (Test-Path $cfg) -or -not (Test-Path $proj)) { return $null }
    # Only matters while the hermes launcher still runs that old venv. A finished install of
    # newer Hermes uses its own environment under installs\ and may leave the old venv behind.
    if ((Get-HermesLauncherTargets) -notmatch [regex]::Escape((Join-Path $agent 'venv'))) { return $null }
    $have = (Get-Content $cfg | Select-String '^version(?:_info)?\s*=\s*(\d+)\.(\d+)' | Select-Object -First 1)
    $need = (Get-Content $proj | Select-String '^requires-python\s*=\s*"\s*(==|>=|~=)\s*(\d+)\.(\d+)' | Select-Object -First 1)
    if (-not $have -or -not $need) { return $null }
    $hv = [version]("{0}.{1}" -f $have.Matches[0].Groups[1].Value, $have.Matches[0].Groups[2].Value)
    $op = $need.Matches[0].Groups[1].Value
    $nv = [version]("{0}.{1}" -f $need.Matches[0].Groups[2].Value, $need.Matches[0].Groups[3].Value)
    $ok = if ($op -eq '==') { $hv -eq $nv } else { $hv -ge $nv }
    if ($ok) { return $null }
    return "Hermes needs Python $op$nv but its environment has Python $hv"
}

# Explain why Hermes does not run: which file its launcher needs and whether it exists.
function Show-HermesDiagnosis {
    $cmd = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Host "  hermes command: not found on PATH" -ForegroundColor Yellow; return }
    Write-Host "  hermes command: $($cmd.Source)" -ForegroundColor Yellow
    $ErrorActionPreference = 'Continue'
    # "$_" gives each line's plain text, without PowerShell's "At line:..." error decoration.
    & $cmd.Source --version 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ } |
        Select-Object -First 2 | ForEach-Object { Write-Host "  says: $_" -ForegroundColor Yellow }
    # uv launchers store the Python path they start near the end of the .exe.
    if ($cmd.Source -like '*.exe') {
        foreach ($m in (Get-HermesLauncherTargets)) {
            $ok = Test-Path $m
            Write-Host ("  needs: {0}  -> {1}" -f $m, $(if ($ok) { 'found' } else { 'MISSING' })) -ForegroundColor Yellow
            $cfg = Join-Path (Split-Path (Split-Path $m -Parent) -Parent) 'pyvenv.cfg'
            if ($ok -and (Test-Path $cfg)) {
                $baseDir = ((Get-Content $cfg | Where-Object { $_ -match '^home\s*=' }) -replace '^home\s*=\s*', '').Trim()
                if ($baseDir) { Write-Host ("  base Python folder: {0}  -> {1}" -f $baseDir, $(if (Test-Path (Join-Path $baseDir 'python.exe')) { 'found' } else { 'MISSING' })) -ForegroundColor Yellow }
            }
        }
    }
    $installLog = Join-Path $MM.HermesHome 'logs\install.log'
    if (Test-Path $installLog) { Write-Host "  Hermes install log: $installLog" -ForegroundColor Yellow }
    Write-Host "  If a file is MISSING: open Windows Security > Virus & threat protection > Protection history." -ForegroundColor Yellow
    Write-Host "  Antivirus sometimes quarantines Hermes' Python/uv files by mistake; restore them, then run MM Agent Setup again." -ForegroundColor Yellow
}

# Run a slow command with a "still working" heartbeat, saving its output to logs\<Label>.log.
# Text in -Redact is hidden from the screen and log. Returns the exit code.
function Invoke-WithProgress {
    param([string]$Exe, [string[]]$Arguments, [string]$Label, [int]$TimeoutSec = 900, [string[]]$Redact = @(),
          [switch]$Quiet)   # -Quiet: don't echo the output's last lines (callers that inspect the log)
    New-Item -ItemType Directory -Force $MM.LogDir | Out-Null
    $log = Join-Path $MM.LogDir "$Label.log"
    $errLog = "$log.err"
    $argLine = ($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $p = Start-Process -FilePath $Exe -ArgumentList $argLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $errLog
    $null = $p.Handle   # Windows PowerShell 5.1 only reports ExitCode if the handle was opened
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.WaitForExit(10000)) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
            & taskkill /PID $p.Id /T /F | Out-Null
            Write-Host "[!] Stopped after $TimeoutSec s. Log: $log" -ForegroundColor Yellow
            return 124
        }
        Write-Host ("     ... still working ({0}s) - please wait, do not close this window" -f [int]$sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    }
    $p.WaitForExit()
    # Merge stderr into the log, then hide secrets in both the saved log and the screen.
    $text = (@(Get-Content $log -ErrorAction SilentlyContinue) + @(Get-Content $errLog -ErrorAction SilentlyContinue)) -join "`n"
    foreach ($r in $Redact) { if ($r) { $text = $text.Replace($r, '<hidden>') } }
    [IO.File]::WriteAllText($log, $text)
    Remove-Item $errLog -ErrorAction SilentlyContinue
    if (-not $Quiet) {
        $text -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch 'CLI cleanup timed out' } |
            Select-Object -Last 8 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    }
    return $p.ExitCode
}

# After OpenClaw updates itself, its databases may need a one-time upgrade: the gateway then stops
# with "... uses schema version N; ... run openclaw doctor --fix". Back up the databases (3 newest
# backups kept) and run OpenClaw's own safe repair. Returns doctor's exit code.
function Repair-OpenClawState {
    $root = Join-Path $HOME '.openclaw'
    $backups = Join-Path $root 'backups'
    $dest = Join-Path $backups "mm-before-doctor-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Force $dest | Out-Null
    Get-ChildItem (Join-Path $root 'agents') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $db = Join-Path $_.FullName 'agent'
        if (Test-Path $db) {
            $to = New-Item -ItemType Directory -Force (Join-Path $dest $_.Name)
            Copy-Item (Join-Path $db 'openclaw-agent.sqlite*') $to -ErrorAction SilentlyContinue
        }
    }
    Copy-Item (Join-Path $root 'state\openclaw.sqlite*') $dest -ErrorAction SilentlyContinue
    Get-ChildItem $backups -Directory -Filter 'mm-before-doctor-*' | Sort-Object Name -Descending |
        Select-Object -Skip 3 | Remove-Item -Recurse -Force
    Write-Host "     databases backed up to $dest" -ForegroundColor DarkGray
    return (Invoke-WithProgress -Exe (Resolve-OpenClaw) -Arguments @('doctor', '--fix', '--non-interactive') `
        -Label 'openclaw-doctor' -TimeoutSec 1800 -Quiet)
}

# Keep a dated copy of a settings file (only the 5 newest are kept). Files over 1 MB are not
# copied: a settings file that big is damaged, and Read-HermesEnvLines keeps that copy itself.
function Backup-File([string]$Path) {
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -gt $MaxEnvBytes) { return }
    Copy-Item $Path "$Path.mm-backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Get-ChildItem (Split-Path $Path -Parent) -Filter "$(Split-Path $Path -Leaf).mm-backup.*" -Force |
        Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Force
}
