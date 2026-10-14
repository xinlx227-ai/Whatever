param(
    [Parameter(Mandatory = $true)][ValidatePattern('^emulator-[0-9]+$')][string]$Serial,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$LayerName,
    [ValidateRange(5, 120)][int]$DurationSeconds = 30,
    [string]$Adb = 'D:/SDK/platform-tools/adb.exe'
)
$ErrorActionPreference = 'Stop'
$directory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $directory -Force | Out-Null
function Invoke-Adb {
    param([string[]]$Arguments)
    $value = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')`n$value" }
    return ($value -join "`n")
}
$avd = Invoke-Adb @('emu', 'avd', 'name')
if ($avd -notmatch '^Pixel_5_API_35\s') { throw "Expected Pixel_5_API_35; got $avd" }
function Normalize-LayerName {
    param([string]$Value)
    if ($Value -match '^RequestedLayerState\{(.+?)\s+parentId=') { return $Matches[1] }
    return $Value.TrimEnd()
}
$LayerName = Normalize-LayerName $LayerName
if ($LayerName -notmatch 'SurfaceView.*com\.xinlx227\.whatever') { throw 'Select the actual Flutter SurfaceView layer of the benchmark package' }
$layers = Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger', '--list')
$layers | Set-Content -LiteralPath (Join-Path $directory 'layers.txt') -Encoding utf8
if (@($layers -split "`n" | ForEach-Object { Normalize-LayerName $_ } | Where-Object { $_ -eq $LayerName }).Count -ne 1) { throw 'Requested exact layer is missing or ambiguous' }
$quotedLayer = "'" + $LayerName.Replace("'", "'\''") + "'"
Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger', '--latency-clear', $quotedLayer) | Out-Null
Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-clear', '-enable') | Out-Null
$samples = Join-Path $directory 'surface-latency.jsonl'
$rows = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new()
$deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
try {
    do {
        $start = [DateTime]::UtcNow
        $raw = Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger', '--latency', $quotedLayer)
        @{ captureStartUtc = $start.ToString('o'); captureEndUtc = [DateTime]::UtcNow.ToString('o'); layer = $LayerName; raw = $raw } |
            ConvertTo-Json -Compress -Depth 3 | Add-Content -LiteralPath $samples -Encoding utf8
        foreach ($line in $raw -split "`n") {
            if ($line -match '^\s*(\d+)\s+(\d+)\s+(\d+)\s*$') {
                $desired = [int64]$Matches[1]
                $actual = [int64]$Matches[2]
                $ready = [int64]$Matches[3]
                # Zero and INT64_MAX indicate absent or unsignaled records.
                if ($actual -gt 0 -and $actual -lt [int64]::MaxValue -and $seen.Add("$desired/$actual")) {
                    $rows.Add([PSCustomObject]@{ desiredPresentNs = $desired; actualPresentNs = $actual; frameReadyNs = $ready; captureUtc = [DateTime]::UtcNow.ToString('o') })
                }
            }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
} finally {
    Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-dump') |
        Set-Content -LiteralPath (Join-Path $directory 'surface-timestats.txt') -Encoding utf8
    Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-disable') | Out-Null
}
$rows | Sort-Object actualPresentNs | Export-Csv -LiteralPath (Join-Path $directory 'surface-presentations.csv') -NoTypeInformation -Encoding utf8
@{ layer = $LayerName; durationSeconds = $DurationSeconds; validRawPresentationRecords = $rows.Count; latencyAvailable = ($rows.Count -gt 0); acceptance = 'ungraded: establish continuous window coverage and timestamp alignment first' } |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $directory 'surface-summary.json') -Encoding utf8
if ($rows.Count -eq 0) { Write-Warning 'No usable app-surface raw presentation records. Inspect timestats; integer-ms histograms cannot exactly grade 16.67/33.33 ms boundaries.' }
