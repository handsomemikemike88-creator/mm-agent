# Add (or -Remove) the Windows Task Scheduler task "MM Agent Daily Update".
# It runs update-all.ps1 every day at 04:00 for PCs that stay switched on, then starts MM Agent
# again. (PCs that are restarted get the same update at sign-in, from start.ps1 -Background.)
# A per-user task: no administrator rights needed; it runs only while this user is signed in.
param([switch]$Remove, [string]$At = '04:00')
. "$PSScriptRoot\common.ps1"
$name = 'MM Agent Daily Update'

Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
if ($Remove) { Write-Host "[OK] Removed the task '$name'"; return }

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script = Join-Path $PSScriptRoot 'update-all.ps1'
$action = New-ScheduledTaskAction -Execute $ps -WorkingDirectory (Split-Path $PSScriptRoot -Parent) `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Restart"
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description 'Updates Node.js, OpenClaw and Hermes Agent for MM Agent, then starts MM Agent again.' -ErrorAction Stop | Out-Null
Write-Host "[OK] '$name' runs every day at $At" -ForegroundColor Green
