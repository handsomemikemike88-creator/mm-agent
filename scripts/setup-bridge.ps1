# One-time setup: turn on Hermes' OpenAI-compatible API server and point OpenClaw at it.
# Safe to re-run; it backs up both configs first.
param([switch]$SkipModel)   # first-run picks the model itself, from the keys entered
. "$PSScriptRoot\common.ps1"
Update-Path

Write-Host "== $($MM.Name) bridge setup ==" -ForegroundColor Cyan
Backup-File $MM.HermesEnv
Backup-File $MM.HermesConfig

# 1) Hermes brain: local API server, loopback only, guarded by a random bridge key.
$bridgeKey = Get-EnvValue 'API_SERVER_KEY'
# A damaged .env can leave junk glued onto the key; only a clean single token is reused.
if ($bridgeKey -and $bridgeKey -notmatch '^[A-Za-z0-9_-]{16,200}$') {
    Write-Host "[!] The saved bridge key was damaged; making a new one (OpenClaw is re-linked)." -ForegroundColor Yellow
    $bridgeKey = $null
}
$newKey = -not $bridgeKey
if ($newKey) {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $bridgeKey = 'mm-' + ([BitConverter]::ToString($bytes) -replace '-', '').ToLower()
}
Set-EnvValue 'API_SERVER_ENABLED'    'true'
Set-EnvValue 'API_SERVER_HOST'       '127.0.0.1'
Set-EnvValue 'API_SERVER_PORT'       "$($MM.BrainPort)"
Set-EnvValue 'API_SERVER_KEY'        $bridgeKey
Set-EnvValue 'API_SERVER_MODEL_NAME' $MM.BrainModel
Write-Host "[OK] Hermes API server enabled on $($MM.BrainUrl)"

# 2) Default brain model = DeepSeek (switch later with Switch-Model.cmd).
if (-not $SkipModel) { & "$PSScriptRoot\switch-model.ps1" -Provider deepseek -Quiet }

# 3) OpenClaw interface: custom OpenAI-compatible provider -> Hermes.
$onboard = @(
    'onboard', '--non-interactive', '--accept-risk',
    '--mode', 'local', '--flow', 'quickstart',
    '--agent-name', $MM.Name,
    '--auth-choice', 'custom-api-key',
    '--custom-provider-id', $MM.BrainProvider,
    '--custom-base-url', $MM.BrainUrl,
    '--custom-model-id', $MM.BrainModel,
    '--custom-api-key', $bridgeKey,
    '--custom-compatibility', 'openai',
    '--custom-text-input',
    '--gateway-bind', 'loopback',
    '--gateway-auth', 'token',
    '--skip-daemon', '--skip-channels', '--skip-search', '--skip-skills',
    '--skip-health', '--skip-ui', '--suppress-gateway-token-output'
)
$openclaw = Resolve-OpenClaw
if (-not $openclaw) { throw "OpenClaw is not installed. Run 'MM Agent Setup' again." }

function Get-OpenClawValue([string]$Path) {
    $ErrorActionPreference = 'Continue'     # OpenClaw prints harmless warnings on stderr
    "$((& $openclaw config get $Path 2>$null) | Where-Object { "$_".Trim() } | Select-Object -Last 1)".Trim()
}

# Already linked with the same bridge key? Then linking again is not needed. (OpenClaw 2026.10.6+
# answers a repeat link with "Replacement credential saved but inactive" and exit code 1.)
$linked = (Get-OpenClawValue 'agents.defaults.model.primary') -eq "$($MM.BrainProvider)/$($MM.BrainModel)" -and
          (Get-OpenClawValue "models.providers.$($MM.BrainProvider).baseUrl") -eq $MM.BrainUrl
if ($linked -and -not $newKey) {
    Write-Host "[OK] OpenClaw is already linked to Hermes"
} else {
    Write-Host "[..] Linking OpenClaw to Hermes. This takes 1-5 minutes and may print nothing for a while." -ForegroundColor Cyan
    $log = Join-Path $MM.LogDir 'setup-openclaw.log'
    $code = Invoke-WithProgress -Exe $openclaw -Arguments $onboard -Label 'setup-openclaw' -Redact $bridgeKey
    if ($code -ne 0) {
        # A changed key on an existing link is saved "inactive". Activating it tests the brain,
        # which is not running yet, so start.ps1 activates it after the brain is up.
        $pending = Select-String -Path $log -Pattern 'models auth activate (\S+)(?:\s+--agent\s+(\S+))?' | Select-Object -First 1
        if (-not $pending) { throw "Linking OpenClaw failed (exit $code). Log: $log" }
        $id = $pending.Matches[0].Groups[1].Value
        $agent = $pending.Matches[0].Groups[2].Value
        Set-Content (Join-Path $MM.LogDir 'openclaw-pending-signin.txt') "$id $agent".Trim()
        Write-Host "[OK] New Hermes sign-in saved in OpenClaw. It is activated automatically when MM Agent starts." -ForegroundColor Green
    }
}
# Agent answers can be long; the onboarding default of 4096 is too small.
$ErrorActionPreference = 'Continue'     # OpenClaw prints harmless warnings on stderr
& $openclaw config set "models.providers.$($MM.BrainProvider).models[0].maxTokens" 16384 --strict-json 2>$null | Out-Null
# OpenClaw sends no tools to the brain: chat apps get no tools (see below), and when the brain is told
# about tools it cannot use, DeepSeek writes its raw tool-call markup ("<|DSML| calls>") into the reply.
& $openclaw config set "models.providers.$($MM.BrainProvider).models[0].compat.supportsTools" false --strict-json 2>$null | Out-Null

# Speed: Hermes does the thinking and uses its own tools, so OpenClaw only relays. Without this,
# OpenClaw sends ~47k tokens of its own tool descriptions and workspace files with every message
# (measured: 11.8 s -> 4.7 s per reply together with deepseek-v4-flash and low reasoning).
$slim = @{
    tools  = @{ profile = 'minimal' }
    agents = @{ defaults = @{ contextInjection = 'never'; thinkingDefault = 'off' } }
} | ConvertTo-Json -Depth 6
$slimFile = Join-Path $env:TEMP 'mm-slim.patch.json'
[IO.File]::WriteAllText($slimFile, $slim, (New-Object Text.UTF8Encoding $false))
& $openclaw config patch --file $slimFile 2>$null | Out-Null
Remove-Item $slimFile
$ErrorActionPreference = 'Stop'

# Hermes' "medium" reasoning makes every reply think first; "low" is much quicker for chat.
$effort = ((Get-Content $MM.HermesConfig -ErrorAction SilentlyContinue | Select-String '^\s*reasoning_effort:\s*(\S*)' | Select-Object -First 1).Matches.Groups[1].Value)
if (-not $effort -or $effort -eq 'medium') {
    $ErrorActionPreference = 'Continue'
    & hermes config set agent.reasoning_effort low 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
}
Write-Host "[OK] Fast replies: OpenClaw relays lightly, Hermes reasoning '$(if ($effort -and $effort -ne 'medium') { $effort } else { 'low' })'"

# Safety: everything from chat apps (WhatsApp, Telegram, the chat page) reaches Hermes through its API
# server. Hermes would give those chats its FULL tools (terminal, files, code, browser, memory, search
# across all chats), so anyone who can message the number could make this PC run commands or read
# another client's chat. Chat apps get no Hermes tools; the Hermes dashboard keeps its own tools.
# Only set when the user has not chosen a list themselves.
$hasApiList = Select-String -Path $MM.HermesConfig -Pattern '^\s+api_server:' -Quiet -ErrorAction SilentlyContinue
if (-not $hasApiList) {
    $ErrorActionPreference = 'Continue'
    & hermes config set platform_toolsets.api_server '[]' 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
}
Write-Host "[OK] Chat apps can't use the brain's PC tools (terminal, files, ...)"

# Course info: the mm-course-info plugin adds the course documents (~\.openclaw\workspace\rag\corpus)
# and the customer-service rules to every chat. Read-only, no tools.
$coursePlugin = Join-Path (Split-Path $PSScriptRoot -Parent) 'openclaw-plugin\mm-course-info'
if (Test-Path (Join-Path $coursePlugin 'index.js')) {
    $ErrorActionPreference = 'Continue'
    & $openclaw plugins install --link $coursePlugin --force 2>$null | Out-Null
    $cfgNow = Get-Content (Join-Path $HOME '.openclaw\openclaw.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $allowList = @($cfgNow.plugins.allow | Where-Object { $_ })
    $pluginPatch = @{ plugins = @{ entries = @{ 'mm-course-info' = @{ enabled = $true; hooks = @{ allowConversationAccess = $true; allowPromptInjection = $true } } } } }
    if ($allowList.Count -gt 0 -and $allowList -notcontains 'mm-course-info') { $pluginPatch.plugins.allow = @($allowList + 'mm-course-info') }
    $pluginFile = Join-Path $env:TEMP 'mm-course-plugin.patch.json'
    [IO.File]::WriteAllText($pluginFile, ($pluginPatch | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
    & $openclaw config patch --file $pluginFile 2>$null | Out-Null
    Remove-Item $pluginFile -ErrorAction SilentlyContinue
    $ErrorActionPreference = 'Stop'
    Write-Host "[OK] Course info plugin on (course files: $(Join-Path $HOME '.openclaw\workspace\rag\corpus'))"
}
Write-Host "[OK] OpenClaw now uses '$($MM.BrainProvider)/$($MM.BrainModel)' (Hermes) as its model"
if (-not $SkipModel) { Write-Host "Setup complete. Next: run Enter-API-Keys.cmd, then Start-MM-Agent.cmd" -ForegroundColor Green }
