param([Parameter(Mandatory = $true)][string]$Directory)
$ErrorActionPreference = 'Stop'
$directoryPath = [IO.Path]::GetFullPath($Directory)
$rows = [Collections.Generic.List[object]]::new()
$cases = [Collections.Generic.List[object]]::new()
$inputRows = [Collections.Generic.List[object]]::new()
function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)
    if ($Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    return $sorted[[Math]::Max(0, [Math]::Ceiling($sorted.Count * $Percentile) - 1)]
}
foreach ($file in Get-ChildItem -LiteralPath $directoryPath -Filter 'frames-input.json' -Recurse -File) {
    $report = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $journeysPath = Join-Path $file.DirectoryName 'journeys.json'
    if (!(Test-Path -LiteralPath $journeysPath)) { throw "Missing completed journey evidence for $($file.DirectoryName)" }
    $journeys = Get-Content -LiteralPath $journeysPath -Raw | ConvertFrom-Json
    foreach ($window in $report.windows) {
        $frames = @($report.frames | Where-Object { $_.vsyncWallUs -ge $window.startWallUs -and $_.vsyncWallUs -lt $window.endWallUs })
        foreach ($metric in @('buildUs', 'rasterUs', 'totalSpanUs')) {
            $values = [double[]]@($frames | ForEach-Object { $_.$metric })
            $one = @($values | Where-Object { $_ -le (1000000.0 / 60) }).Count
            $two = @($values | Where-Object { $_ -le (2000000.0 / 60) }).Count
            $rows.Add([PSCustomObject]@{
                case = $journeys.case; window = $window.label; metric = $metric; frames = $values.Count
                withinOnePercent = $(if ($values.Count) { 100.0 * $one / $values.Count } else { $null })
                withinTwoPercent = $(if ($values.Count) { 100.0 * $two / $values.Count } else { $null })
                p95Us = (Get-Percentile -Values $values -Percentile .95)
                p99Us = (Get-Percentile -Values $values -Percentile .99)
                maxUs = $(if ($values.Count) { ($values | Measure-Object -Maximum).Maximum } else { $null })
                primaryRenderedMetric = ($metric -eq 'totalSpanUs')
                renderedWithinBudget = $(if ($metric -eq 'totalSpanUs' -and $values.Count -gt 0) { (100.0 * $one / $values.Count) -ge 95 -and (100.0 * $two / $values.Count) -ge 99 } else { $null })
            })
        }
    }
    $joined = @($report.inputs | Where-Object { $_.deliveryToRasterUs -ne $null -and $_.deliveryToRasterUs -ge 0 })
    $eligible = @($report.inputs)
    $platformJoined = @($report.inputs | Where-Object { $_.inputClockValid -eq $true -and $_.platformEventToRasterUs -ne $null -and $_.platformEventToRasterUs -ge 0 })
    $invalidClocks = @($report.inputs | Where-Object { $_.rasterFinishWallUs -ne $null -and $_.inputClockValid -ne $true })
    foreach ($input in $eligible) {
        $phase = if ($input.label -match '^(first-entry|repeated|retained-[0-9]+)') { $Matches[1] } else { 'unspecified' }
        $inputRows.Add([PSCustomObject]@{
            case = $journeys.case; phase = $phase; action = $input.label; kind = $input.kind
            platformTimestampUs = $input.platformTimestampUs; deliveredWallUs = $input.deliveredWallUs
            platformEventToRasterUs = $input.platformEventToRasterUs; platformToDartDeliveryUs = $input.platformToDartDeliveryUs
            deliveryToStateUs = $input.deliveryToStateUs; deliveryToRasterUs = $input.deliveryToRasterUs
            inputClockValid = $input.inputClockValid; firstCandidateFrame = $input.firstFeedbackFrameNumber
            matchedFrame = $input.matchedFeedbackFrameNumber; candidateFrames = @($input.candidateFrames).Count
            platformWithin100ms = $(if ($input.inputClockValid -eq $true -and $input.platformEventToRasterUs -ne $null) { $input.platformEventToRasterUs -le 100000 } else { $null })
        })
    }
    $samplesPath = Join-Path $file.DirectoryName 'pss.jsonl'
    $samples = @(Get-Content -LiteralPath $samplesPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    $restingSamples = @($journeys.restingBaseline, $journeys.restingFinal | Where-Object { $_ -ne $null })
    $allMemorySamples = @($samples) + @($restingSamples)
    $missingSamples = @($allMemorySamples | Where-Object { $_.pssKiB -eq $null }).Count
    $pids = @($allMemorySamples | ForEach-Object { $_.pid } | Sort-Object -Unique)
    $memoryValid = $samples.Count -gt 0 -and $journeys.restingBaseline -ne $null -and $missingSamples -eq 0 -and $pids.Count -eq 1 -and $pids[0] -eq "$($report.pid)"
    $peak = if ($allMemorySamples.Count) { [double](($allMemorySamples | Measure-Object -Property pssKiB -Maximum).Maximum) / 1024 } else { $null }
    $delta = if ($journeys.restingFinal.pssKiB -ne $null -and $journeys.restingBaseline.pssKiB -ne $null) { ($journeys.restingFinal.pssKiB - $journeys.restingBaseline.pssKiB) / 1024.0 } else { $null }
    $retainedValid = $memoryValid -and @($journeys.journeys).Count -eq 12 -and $journeys.restingFinal -ne $null -and $journeys.restingBaseline.pid -eq "$($report.pid)" -and $journeys.restingFinal.pid -eq "$($report.pid)"
    $cases.Add([PSCustomObject]@{
        case = $journeys.case; release = $report.release; journeyCount = @($journeys.journeys).Count
        feedbackArmedCount = $eligible.Count; feedbackJoinedCount = $joined.Count; feedbackMissingCount = ($eligible.Count - $joined.Count)
        feedbackP95Us = (Get-Percentile -Values ([double[]]@($joined | ForEach-Object { $_.deliveryToRasterUs })) -Percentile .95)
        feedbackWithin100msPercentOfArmed = $(if ($eligible.Count) { 100.0 * @($joined | Where-Object { $_.deliveryToRasterUs -le 100000 }).Count / $eligible.Count } else { $null })
        platformFeedbackJoinedCount = $platformJoined.Count; platformFeedbackMissingCount = ($eligible.Count - $platformJoined.Count); platformFeedbackClockInvalidCount = $invalidClocks.Count
        platformFeedbackP95Us = (Get-Percentile -Values ([double[]]@($platformJoined | ForEach-Object { $_.platformEventToRasterUs })) -Percentile .95)
        platformFeedbackWithin100msPercentOfArmed = $(if ($eligible.Count) { 100.0 * @($platformJoined | Where-Object { $_.platformEventToRasterUs -le 100000 }).Count / $eligible.Count } else { $null })
        inputMethod = 'Primary Android event timestamp to raster finish; millisecond event precision; physical sampling and compositor scanout excluded; legacy delivery metrics diagnostic'
        memorySamples = $samples.Count; restingMemorySamples = $restingSamples.Count; memoryMissingSamples = $missingSamples; processIds = ($pids -join ','); memoryValid = $memoryValid
        sampledPeakPssMiB = $peak; sampledPeakWithin512MiB = $(if ($memoryValid) { $peak -le 512 } else { $null })
        retainedDeltaMiB = $delta; retainedValid = $retainedValid; retainedWithin50MiB = $(if ($retainedValid) { $delta -le 50 } else { $null })
        compositorAcceptance = 'unverified; inspect app surface presentation evidence separately'
    })
}
$rows | Export-Csv -LiteralPath (Join-Path $directoryPath 'engine-windows.csv') -NoTypeInformation -Encoding utf8
$cases | Export-Csv -LiteralPath (Join-Path $directoryPath 'cases.csv') -NoTypeInformation -Encoding utf8
$inputRows | Export-Csv -LiteralPath (Join-Path $directoryPath 'input-feedback.csv') -NoTypeInformation -Encoding utf8
@{ protocol = 1; metricScope = 'Primary totalSpan rendered-frame budgets; primary Android event-to-raster feedback; sampled Android PSS; compositor separate'; cases = $cases.ToArray(); windows = $rows.ToArray(); inputs = $inputRows.ToArray() } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $directoryPath 'summary.json') -Encoding utf8
Write-Host "Summarized $($cases.Count) completed release cases. Compositor acceptance remains separate."
