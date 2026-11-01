param([Parameter(Mandatory)][string]$ImagePath)

# ponytail: S10 landscape pixels; use a UI driver if the device layout changes.
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Bitmap]::FromFile($ImagePath)
try {
    if ($image.Width -ne 2280 -or $image.Height -ne 1080) {
        throw 'Expected a landscape Samsung S10 screenshot'
    }
    $pixel = $image.GetPixel(1140, 850)
    if ($pixel.G -lt 120 -or $pixel.G -lt ($pixel.R * 1.5)) {
        throw 'Spotify login button did not render'
    }
    Write-Output 'Spotify login is visible'
} finally {
    $image.Dispose()
}
