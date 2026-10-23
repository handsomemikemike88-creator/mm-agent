# Install or update the latest Node.js for MM Agent: a private, per-user copy (no admin rights),
# in the folder OpenClaw's own installer uses. Picks the newest release of the newest
# even-numbered major (odd majors like 27 are short-lived and OpenClaw may not support them yet).
. "$PSScriptRoot\common.ps1"
$ProgressPreference = 'SilentlyContinue'   # PowerShell 5.1's progress bar makes downloads many times slower

Write-Host "== Node.js for $($MM.Name) ==" -ForegroundColor Cyan
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 60
$release = $index |
    Where-Object { ([int]($_.version.TrimStart('v').Split('.')[0]) % 2 -eq 0) -and ($_.files -contains "win-$arch-zip") } |
    Select-Object -First 1
if (-not $release) { throw 'Could not find a Node.js release for this PC.' }
$version = $release.version

$nodeDir = $MM.NodeDir
$nodeExe = Join-Path $nodeDir 'node.exe'
$current = if (Test-Path $nodeExe) { (& $nodeExe -v 2>$null) } else { $null }
if ($current -eq $version) {
    Write-Host "[OK] Node.js $version already installed"
} else {
    if ($current) { Write-Host "[..] Updating Node.js $current -> $version" } else { Write-Host "[..] Installing Node.js $version" }
    $name = "node-$version-win-$arch"
    $tmp = Join-Path $env:TEMP "mm-node-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        $zip = Join-Path $tmp "$name.zip"
        Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/$version/$name.zip" -OutFile $zip -TimeoutSec 600

        # Verify the download against nodejs.org's published checksums.
        $sums = (Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/$version/SHASUMS256.txt" -TimeoutSec 60).Content
        if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }
        $expected = ($sums -split "`n" | Where-Object { $_ -match "\s$([regex]::Escape("$name.zip"))\s*$" } | Select-Object -First 1) -replace '\s.*$', ''
        $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
        if (-not $expected -or $actual -ne $expected.ToUpper()) { throw 'Node.js download failed its checksum. Try again.' }

        # Windows' built-in tar unpacks much faster than Expand-Archive.
        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path $tar) { & $tar -xf $zip -C $tmp }
        if (-not (Test-Path (Join-Path $tmp "$name\node.exe"))) { Expand-Archive -Path $zip -DestinationPath $tmp -Force }
        # A Node update replaces the folder, including OpenClaw installed in it;
        # first-run.ps1 then reinstalls OpenClaw on the new Node.
        if (Test-Path $nodeDir) { Remove-Item $nodeDir -Recurse -Force }
        New-Item -ItemType Directory -Force (Split-Path $nodeDir -Parent) | Out-Null
        Move-Item (Join-Path $tmp $name) $nodeDir
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Add-UserPath $nodeDir
Use-MMNode
Write-Host "[OK] Node.js $(& $nodeExe -v) at $nodeDir" -ForegroundColor Green
