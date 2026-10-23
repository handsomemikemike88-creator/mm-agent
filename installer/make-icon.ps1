# Build installer\mmagent.ico from installer\mmagent-source.jpg.
# Large sizes show the whole artwork (with "MMAGENT"); small sizes show a close-up of the rooster,
# where text would be unreadable. Entries are stored as PNG (supported since Windows Vista).
param([string]$PreviewDir)   # optional: also save each size as a PNG for checking
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$src = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'mmagent-source.jpg'))
$bg = $src.GetPixel(2, 2)                         # dark background colour of the artwork
$closeUp = New-Object Drawing.Rectangle 72, 4, 164, 164   # rooster head and fists, no text

function New-IconImage([int]$Size, [bool]$Full) {
    $bmp = New-Object Drawing.Bitmap $Size, $Size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($Full) {
        # Fit the whole wide picture, centred, on its own background colour.
        $g.Clear($bg)
        $h = [int]($Size * $src.Height / $src.Width)
        $g.DrawImage($src, (New-Object Drawing.Rectangle 0, (($Size - $h) / 2), $Size, $h))
    } else {
        $g.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $Size, $Size), $closeUp, [Drawing.GraphicsUnit]::Pixel)
    }
    $g.Dispose()
    return $bmp
}

$sizes = 256, 128, 64, 48, 32, 24, 16
$pngs = foreach ($s in $sizes) {
    $bmp = New-IconImage $s ($s -ge 128)
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    if ($PreviewDir) { $bmp.Save((Join-Path $PreviewDir "icon-$s.png"), [Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
    , $ms.ToArray()
}
$src.Dispose()

# ICO file: 6-byte header, one 16-byte directory entry per image, then the PNG data.
$out = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $out
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $w.Write([byte]($s % 256)); $w.Write([byte]($s % 256))   # 256 is written as 0
    $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Flush()
$ico = Join-Path $PSScriptRoot 'mmagent.ico'
[IO.File]::WriteAllBytes($ico, $out.ToArray())
"[OK] $ico  ($([int]($out.Length / 1KB)) KB, sizes: $($sizes -join ', '))"
