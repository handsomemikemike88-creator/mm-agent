# Build dist\MM-Agent-Setup.exe from MM-Agent.iss with the Inno Setup compiler.
$ErrorActionPreference = 'Stop'
$candidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it: winget install --id JRSoftware.InnoSetup -e --scope user' }

& $iscc /Q "$PSScriptRoot\MM-Agent.iss"
if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)." }
$exe = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\MM-Agent-Setup.exe'
$item = Get-Item $exe
Write-Host ("[OK] Built {0}  ({1:N0} KB)" -f $item.FullName, ($item.Length / 1KB)) -ForegroundColor Green
Write-Host ("SHA256: " + (Get-FileHash $exe -Algorithm SHA256).Hash)
