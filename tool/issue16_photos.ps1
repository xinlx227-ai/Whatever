param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidateRange(1, 1000)][int]$Count = 1000
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$directory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$random = [Random]::new(16)
$bitmap = [Drawing.Bitmap]::new(4000, 3000)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$font = [Drawing.Font]::new('Arial', 120)
$brush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
$encoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$parameters = [Drawing.Imaging.EncoderParameters]::new(1)
$parameters.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]90)
$manifest = [Collections.Generic.List[object]]::new()
try {
    for ($index = 0; $index -lt $Count; $index++) {
        for ($row = 0; $row -lt 30; $row++) {
            for ($column = 0; $column -lt 40; $column++) {
                $brush.Color = [Drawing.Color]::FromArgb($random.Next(40, 225), $random.Next(40, 225), $random.Next(40, 225))
                $graphics.FillRectangle($brush, $column * 100, $row * 100, 100, 100)
            }
        }
        $brush.Color = [Drawing.Color]::White
        $graphics.DrawString("Issue 16 fixture $index", $font, $brush, 120, 120)
        $name = 'photo-{0:D4}.jpg' -f $index
        $path = Join-Path $directory $name
        $bitmap.Save($path, $encoder, $parameters)
        $manifest.Add(@{ name = $name; width = 4000; height = 3000; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; bytes = (Get-Item -LiteralPath $path).Length })
        if (($index + 1) % 50 -eq 0) { Write-Host "Generated $($index + 1) / $Count distinct JPEG fixtures" }
    }
    $oversized = [Drawing.Bitmap]::new(6000, 6000)
    $extreme = [Drawing.Bitmap]::new(12000, 128)
    try {
        $oversized.Save((Join-Path $directory 'oversized.png'), [Drawing.Imaging.ImageFormat]::Png)
        $extreme.Save((Join-Path $directory 'extreme-ratio.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $oversized.Dispose()
        $extreme.Dispose()
    }
    [IO.File]::WriteAllText((Join-Path $directory 'invalid.jpg'), 'Issue 16 invalid image fixture')
    @{ version = 1; description = 'Distinct synthetic photo-sized texture JPEGs; not natural photographs'; seed = 16; files = $manifest.ToArray() } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $directory 'manifest.json') -Encoding utf8
} finally {
    $parameters.Dispose()
    $brush.Dispose()
    $font.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
