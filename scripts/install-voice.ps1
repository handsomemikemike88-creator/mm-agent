# Voice messages for MM Agent (WhatsApp / Telegram):
#   hear  - voice notes are turned into text on this PC with whisper.cpp (free, private, any language)
#   speak - when a client sends a voice note, the answer also comes back as a voice note
#           (Microsoft's free voices: Cantonese, Mandarin, English, ... picked from the reply's language)
# Installs into %LOCALAPPDATA%\MM Agent Voice (no admin rights), then sets OpenClaw up to use it.
#   -Reply inbound|always|off   when to answer with voice (default: inbound = only after a voice note)
param([ValidateSet('inbound', 'always', 'off')][string]$Reply = 'inbound', [switch]$SkipConfig)
. "$PSScriptRoot\common.ps1"
Update-Path
$ProgressPreference = 'SilentlyContinue'
$VoiceDir = Join-Path $env:LOCALAPPDATA 'MM Agent Voice'
New-Item -ItemType Directory -Force $VoiceDir | Out-Null
Write-Host "== Voice messages for $($MM.Name) ==" -ForegroundColor Cyan

function Get-Download([string]$Url, [string]$Out, [string]$Sha256, [string]$What) {
    if ((Test-Path $Out) -and $Sha256 -and ((Get-FileHash $Out -Algorithm SHA256).Hash -eq $Sha256.ToUpper())) {
        Write-Host "[OK] $What already downloaded"; return
    }
    Write-Host "[..] Downloading $What ..."
    $tmp = "$Out.part"
    $job = Start-Job { param($u, $o) $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $o -TimeoutSec 3600 } -ArgumentList $Url, $tmp
    while ($job.State -eq 'Running') {
        Start-Sleep -Seconds 10
        if (Test-Path $tmp) { Write-Host ("     ... {0:N0} MB" -f ((Get-Item $tmp).Length / 1MB)) -ForegroundColor DarkGray }
    }
    Receive-Job $job -ErrorAction Stop | Out-Null; Remove-Job $job
    if ($Sha256 -and (Get-FileHash $tmp -Algorithm SHA256).Hash -ne $Sha256.ToUpper()) {
        Remove-Item $tmp -Force; throw "$What failed its checksum. Try again."
    }
    Move-Item $tmp $Out -Force
    Write-Host "[OK] $What downloaded"
}

# 1. ffmpeg (converts voice notes for whisper, and voice replies into WhatsApp voice notes).
#    OpenClaw only runs ffmpeg from "C:\Program Files\ffmpeg\bin" (a folder normal programs can't change,
#    so nothing can swap in a fake ffmpeg). Putting it there needs administrator rights once: Windows asks.
$ffmpeg = Join-Path $env:ProgramFiles 'ffmpeg\bin\ffmpeg.exe'
if (-not (Test-Path $ffmpeg)) {
    $stage = Join-Path $env:TEMP "mm-ffmpeg-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force $stage | Out-Null
    try {
        $zip = Join-Path $stage 'ffmpeg.zip'
        $sha = ((Invoke-WebRequest -UseBasicParsing 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256').Content |
                ForEach-Object { if ($_ -is [byte[]]) { [Text.Encoding]::ASCII.GetString($_) } else { $_ } }).Trim().Split()[0]
        Get-Download 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $zip $sha 'ffmpeg (~100 MB, official gyan.dev build)'
        & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $zip -C $stage
        $bin = Get-ChildItem $stage -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1 | ForEach-Object DirectoryName
        if (-not $bin) { throw 'ffmpeg.exe not found in the download.' }
        Write-Host "[..] Windows will now ask for permission to put ffmpeg in 'C:\Program Files\ffmpeg' - click Yes." -ForegroundColor Cyan
        $dest = Join-Path $env:ProgramFiles 'ffmpeg\bin'
        $copy = "New-Item -ItemType Directory -Force '$dest' | Out-Null; Copy-Item '$bin\ffmpeg.exe','$bin\ffprobe.exe' '$dest' -Force"
        try {
            $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $copy)
        } catch { throw "Permission was not given, so voice replies can't be sent on WhatsApp. Run Voice Messages again and click Yes." }
        if (-not (Test-Path $ffmpeg)) { throw "ffmpeg could not be copied to $dest (exit $($p.ExitCode))." }
    } finally {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "[OK] ffmpeg: $ffmpeg"

# 2. whisper.cpp (speech-to-text program), newest official Windows build.
#    With an NVIDIA graphics card the CUDA build is used: a voice note takes ~1 second instead of 10-60.
$smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
$gpuName = if ($smi) { (& $smi.Source --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1) } else { $null }
$gpu = [bool]$gpuName
$pattern = if ($gpu) { '^whisper-(bin-win-cuda|cublas)-12[.\d]*-(bin-)?x64\.zip$' } else { '^whisper-bin-x64\.zip$' }
$variant = if ($gpu) { 'cuda' } else { 'cpu' }
Write-Host ("[..] Speech recognition will run on: " + $(if ($gpu) { "the graphics card ($gpuName)" } else { 'the processor (no NVIDIA graphics card found)' }))
$whisperDir = Join-Path $VoiceDir 'whisper'
$whisper = Get-ChildItem $whisperDir -Recurse -Filter 'whisper-cli.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
$releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/ggml-org/whisper.cpp/releases?per_page=15' -Headers @{ 'User-Agent' = 'MM-Agent' } -TimeoutSec 60
$asset = $releases | ForEach-Object { $r = $_; $_.assets | Where-Object { $_.name -match $pattern } | ForEach-Object { [pscustomobject]@{ Tag = "$($r.tag_name) $variant"; Url = $_.browser_download_url; Digest = $_.digest; Size = $_.size } } } | Select-Object -First 1
if (-not $asset) { if (-not $whisper) { throw 'Could not find a whisper.cpp download.' } }
$stampFile = Join-Path $whisperDir 'version.txt'
if ($asset -and (-not $whisper -or -not (Test-Path $stampFile) -or (Get-Content $stampFile -Raw).Trim() -ne $asset.Tag)) {
    $zip = Join-Path $VoiceDir 'whisper.zip'
    $sha = if ($asset.Digest) { $asset.Digest -replace '^sha256:', '' } else { $null }
    Get-Download $asset.Url $zip $sha ("whisper.cpp {0} ({1:N0} MB)" -f $asset.Tag, ($asset.Size / 1MB))
    if (Test-Path $whisperDir) { Remove-Item $whisperDir -Recurse -Force }
    New-Item -ItemType Directory -Force $whisperDir | Out-Null
    & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $zip -C $whisperDir
    Remove-Item $zip -Force
    Set-Content $stampFile $asset.Tag
    $whisper = Get-ChildItem $whisperDir -Recurse -Filter 'whisper-cli.exe' | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $whisper) { throw 'whisper-cli.exe not found after install.' }
Write-Host "[OK] whisper.cpp: $whisper"

# 3. Whisper model: large-v3-turbo (quantized, ~575 MB) - good with Cantonese, Mandarin and English.
$modelName = 'ggml-large-v3-turbo-q5_0.bin'
$model = Join-Path $VoiceDir "models\$modelName"
New-Item -ItemType Directory -Force (Split-Path $model) | Out-Null
$modelSha = ((Invoke-RestMethod -Uri 'https://huggingface.co/api/models/ggerganov/whisper.cpp/tree/main' -TimeoutSec 60) |
             Where-Object path -eq $modelName | Select-Object -First 1).lfs.oid
Get-Download "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$modelName" $model $modelSha 'speech model (575 MB)'

# Warm up once: the graphics card build compiles itself for this card on its first run (~30 s),
# which should not happen while a client waits for an answer.
# (Both programs print progress on stderr, which Windows PowerShell would turn into a stopping error.)
$warm = Join-Path $env:TEMP 'mm-voice-warmup.wav'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'anullsrc=r=16000:cl=mono' -t 2 -c:a pcm_s16le $warm 2>&1 | Out-Null
if (Test-Path $warm) {
    Write-Host "[..] Testing speech recognition once (the first run can take up to a minute) ..."
    & $whisper -m $model -f $warm -l en -nt -np 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "[OK] Speech recognition works" }
    else { Write-Host "[!] Speech recognition test failed (exit $LASTEXITCODE)" -ForegroundColor Yellow }
    Remove-Item $warm -ErrorAction SilentlyContinue
}
$ErrorActionPreference = $eap

# 4. Edge voices for the replies (small npm package, kept outside OpenClaw so its updates can't remove it).
$ttsDir = Join-Path $VoiceDir 'tts'
New-Item -ItemType Directory -Force $ttsDir | Out-Null
$npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
$code = Invoke-WithProgress -Exe $npm -Arguments @('install', '--prefix', $ttsDir, '--no-audit', '--no-fund', 'node-edge-tts@1') -Label 'voice-npm' -Quiet
$edge = Join-Path $ttsDir 'node_modules\node-edge-tts\dist\edge-tts.js'
if (-not (Test-Path $edge)) { throw "Voice package did not install (exit $code). Log: $(Join-Path $MM.LogDir 'voice-npm.log')" }
Write-Host "[OK] Voices: Microsoft Edge (Cantonese, Mandarin, English, ...)"

# Paths for voice-stt.mjs / voice-tts.mjs.
$cfgFile = Join-Path $VoiceDir 'voice.json'
# Keep choices the user edited in voice.json (e.g. "chinese": "mandarin"); refresh the paths.
$old = if (Test-Path $cfgFile) { try { Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } } else { $null }
$json = [ordered]@{ ffmpeg = $ffmpeg; whisper = $whisper; gpu = $gpu; model = $model; edgeTts = $edge
                    language = $(if ($old.language) { $old.language } else { 'auto' })
                    chinese  = $(if ($old.chinese) { $old.chinese } else { 'cantonese' }) } | ConvertTo-Json
[IO.File]::WriteAllText($cfgFile, $json, (New-Object Text.UTF8Encoding $false))   # no BOM: Node's JSON.parse rejects it
if ($SkipConfig) { return }

# 5. Tell OpenClaw to use them.
$node = Join-Path $MM.NodeDir 'node.exe'
$patch = [ordered]@{
    tools = @{ media = @{
        audio  = @{ enabled = $true }
        models = @(@{ type = 'cli'; command = $node; args = @((Join-Path $PSScriptRoot 'voice-stt.mjs'), '{{AttachmentPath}}');
                      timeoutSeconds = 120; capabilities = @('audio') })
    } }
    tts = @{
        auto = $Reply
        provider = 'tts-local-cli'
        providers = @{ 'tts-local-cli' = @{ command = $node; args = @((Join-Path $PSScriptRoot 'voice-tts.mjs'), '{{OutputPath}}', '{{Text}}');
                                            # MP3: OpenClaw turns it into the voice note itself (it always re-encodes).
                                            outputFormat = 'mp3'; timeoutMs = 90000 } }
    }
}
$patchFile = Join-Path $env:TEMP 'mm-voice.patch.json'
$patch | ConvertTo-Json -Depth 10 | Set-Content $patchFile -Encoding utf8
Backup-File (Join-Path $HOME '.openclaw\openclaw.json')
$oc = Resolve-OpenClaw
$ErrorActionPreference = 'Continue'
$out = & $oc config patch --file $patchFile 2>&1 | ForEach-Object { $_.ToString() } | Where-Object { $_ -notmatch 'CLI cleanup' }
$ok = $LASTEXITCODE -eq 0
Remove-Item $patchFile -ErrorAction SilentlyContinue
$out | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
if (-not $ok) { throw 'OpenClaw did not accept the voice settings.' }
Write-Host "[OK] Voice messages are on. Voice replies: $Reply" -ForegroundColor Green
