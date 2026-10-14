param(
    [Parameter(Mandatory = $true)][ValidatePattern('^emulator-[0-9]+$')][string]$Serial,
    [Parameter(Mandatory = $true)][string]$PhotoDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$Adb = 'D:/SDK/platform-tools/adb.exe',
    [string]$Apk = 'build/app/outputs/flutter-apk/app-release.apk',
    [ValidateSet(50, 200, 1000)][int[]]$Pools = @(50, 200, 1000),
    [ValidateSet(0, 50, 100)][int[]]$Photos = @(0, 50, 100),
    [ValidateSet('cards', 'wheel')][string[]]$Modes = @('cards', 'wheel'),
    [ValidateSet('eat', 'cook', 'restaurant')][string]$Scenario = 'eat',
    [ValidateRange(1, 3)][int[]]$Runs = @(1, 2, 3),
    [switch]$SkipRetainedJourneys,
    [switch]$RetainedAllCases,
    [switch]$SkipPhotoPush
)
$ErrorActionPreference = 'Stop'
$package = 'com.xinlx227.whatever'
$remote = "/sdcard/Android/data/$package/files/issue16"
$output = [IO.Path]::GetFullPath($OutputDirectory)
$photosPath = [IO.Path]::GetFullPath($PhotoDirectory)
if (Test-Path -LiteralPath $output) { throw "Output directory already exists: $output. Use a fresh directory; previous completed and failed evidence must be preserved." }
New-Item -ItemType Directory -Path $output | Out-Null
function Invoke-Adb {
    param([string[]]$Arguments)
    $value = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')`n$value" }
    return ($value -join "`n")
}
function Start-Probe {
    Invoke-Adb @('shell', 'am', 'force-stop', $package) | Out-Null
    Invoke-Adb @('shell', 'rm', '-f', "$remote/command.json", "$remote/response.json") | Out-Null
    Invoke-Adb @('shell', 'am', 'start', '-n', "$package/$package.MainActivity") | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $raw = & $Adb -s $Serial shell cat "$remote/response.json" 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $boot = ($raw -join "`n") | ConvertFrom-Json
            $processId = (Invoke-Adb @('shell', 'pidof', $package)).Trim()
            if ($boot.id -eq 'boot' -and $boot.ok -and $boot.release -and "$($boot.pid)" -eq $processId) { return }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    $log = Invoke-Adb @('logcat', '-d', '-t', '150')
    $log | Set-Content -LiteralPath (Join-Path $output 'boot-failure-logcat.txt') -Encoding utf8
    throw 'Release probe did not write a fresh app-owned boot response within 20 seconds. Inspect boot-failure-logcat.txt; configure was not attempted.'
}
$avd = Invoke-Adb @('emu', 'avd', 'name')
if ($avd -notmatch '^Pixel_5_API_35\s') { throw "Expected Pixel_5_API_35; got $avd" }
$metadata = @{
    protocol = 1; serial = $Serial; avd = $avd; startedUtc = [DateTime]::UtcNow.ToString('o')
    sourceSha = (& git rev-parse HEAD); sourceStatus = (& git status --porcelain)
    apkSha256 = (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash
    display = (Invoke-Adb @('shell', 'dumpsys', 'display'))
    compositor = (Invoke-Adb @('shell', 'dumpsys', 'SurfaceFlinger'))
    android = (Invoke-Adb @('shell', 'getprop', 'ro.build.fingerprint'))
    host = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, FreePhysicalMemory, TotalVisibleMemorySize)
    selected = @{ pools = $Pools; photos = $Photos; modes = $Modes; runs = $Runs; scenario = $Scenario; retained = !$SkipRetainedJourneys; retainedAllCases = [bool]$RetainedAllCases }
}
$metadata | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $output 'environment.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $photosPath 'manifest.json') -Destination (Join-Path $output 'fixture-manifest.json')
# The app must create its own external control parent before shell pushes files.
Start-Probe
if (!$SkipPhotoPush -and ($Photos | Where-Object { $_ -gt 0 })) {
    Invoke-Adb @('push', "$photosPath/.", "$remote/photos/") | Out-Null
}
$commandLocal = Join-Path $output 'command.json'
function Send-Command {
    param([hashtable]$Command, [int]$TimeoutSeconds = 45)
    $id = [Guid]::NewGuid().ToString('N')
    $Command.id = $id
    [IO.File]::WriteAllText($commandLocal, ($Command | ConvertTo-Json -Compress -Depth 6), [Text.UTF8Encoding]::new($false))
    # adbd push preserves the app-readable ownership on scoped external files.
    # A shell redirection here creates a shell/root-owned file the app cannot read.
    Invoke-Adb @('push', $commandLocal, "$remote/command.tmp") | Out-Null
    Invoke-Adb @('shell', 'mv', "$remote/command.tmp", "$remote/command.json") | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $raw = & $Adb -s $Serial shell cat "$remote/response.json" 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $response = ($raw -join "`n") | ConvertFrom-Json
            if ($response.id -eq $id) {
                if (!$response.ok) { throw "Probe rejected $($Command.op): $($response.error)" }
                return $response
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Probe timed out waiting for $($Command.op)"
}
function Tap-Target {
    param([string]$Key, [string]$Text, [string]$Feedback, [string]$Label)
    $command = @{ op = 'resolve'; label = $Label }
    if ($Key) { $command.key = $Key } else { $command.text = $Text }
    if ($Feedback) { $command.feedback = $Feedback }
    $point = Send-Command $command
    Invoke-Adb @('shell', 'input', 'tap', "$($point.x)", "$($point.y)") | Out-Null
    return $point
}
function Wait-Idle {
    param([int]$MinimumMilliseconds = 300)
    Start-Sleep -Milliseconds $MinimumMilliseconds
    return (Send-Command @{ op = 'idle' })
}
function Navigate-Tab {
    param([string]$Text, [string]$ReadyKey, [string]$Label)
    if (!$ReadyKey) { throw "Navigation $Text requires an explicit mounted destination target" }
    # Navigation inputs are unarmed diagnostics, never retries of graded input.
    # A controller idle state alone does not prove the destination page mounted.
    Wait-Idle -MinimumMilliseconds 600 | Out-Null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        @{ kind = 'attempt'; label = $Label; destination = $Text; readyKey = $ReadyKey; gradedInput = $false; attempt = $attempt; retry = ($attempt -gt 1); wallUtc = [DateTime]::UtcNow.ToString('o') } |
            ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $navigationPath -Encoding utf8
        $point = Send-Command @{ op = 'resolve'; text = $Text; ensureVisible = $false }
        Invoke-Adb @('shell', 'input', 'tap', "$($point.x)", "$($point.y)") | Out-Null
        $ready = $false
        for ($check = 1; $check -le 3; $check++) {
            Start-Sleep -Milliseconds $(if ($check -eq 1) { 600 } else { 300 })
            $failure = $null
            try {
                Send-Command @{ op = 'resolve'; key = $ReadyKey; ensureVisible = $false } | Out-Null
                $ready = $true
            } catch {
                $failure = $_.Exception.Message
                if ($failure -cne "Probe rejected resolve: Bad state: Target not mounted: $ReadyKey") {
                    @{ kind = 'readiness'; label = $Label; destination = $Text; readyKey = $ReadyKey; gradedInput = $false; attempt = $attempt; retry = ($attempt -gt 1); check = $check; point = $point; ready = $false; error = $failure; wallUtc = [DateTime]::UtcNow.ToString('o') } |
                        ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $navigationPath -Encoding utf8
                    throw
                }
            }
            @{ kind = 'readiness'; label = $Label; destination = $Text; readyKey = $ReadyKey; gradedInput = $false; attempt = $attempt; retry = ($attempt -gt 1); check = $check; point = $point; ready = $ready; error = $failure; wallUtc = [DateTime]::UtcNow.ToString('o') } |
                ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $navigationPath -Encoding utf8
            if ($ready) { return }
        }
    }
    throw "Navigation $Text did not mount $ReadyKey after three explicitly recorded ungraded tap attempts"
}
function Get-Pss {
    $raw = Invoke-Adb @('shell', 'dumpsys', 'meminfo', $package)
    if ($raw -match 'TOTAL PSS:\s+(\d+)') { $pss = [int64]$Matches[1] }
    elseif ($raw -match '(?m)^\s+TOTAL\s+(\d+)') { $pss = [int64]$Matches[1] }
    else { throw 'Android PSS field unavailable' }
    return @{ wallUtc = [DateTime]::UtcNow.ToString('o'); pssKiB = $pss; raw = $raw; pid = (Invoke-Adb @('shell', 'pidof', $package)).Trim() }
}
function Reveal-Card {
    param([string]$Label)
    $point = Tap-Target -Key 'visible-card' -Feedback 'selection' -Label "$Label-select"
    $state = Wait-Idle -MinimumMilliseconds 400
    $expected = [int]($point.key -replace '^candidate-card-', '')
    if ($state.selected -ne $expected) { throw "Overlapping tap selected $($state.selected), expected $expected" }
    Tap-Target -Key $point.key -Feedback 'drawing' -Label "$Label-reveal" | Out-Null
    $state = Wait-Idle -MinimumMilliseconds 1000
    if (@($state.results).Count -ne 1) { throw 'Reveal did not produce exactly one result' }
    return $state
}
function Invoke-Journey {
    param([string]$Mode, [int]$Journey)
    $label = if ($Journey -eq 0) { 'first-entry' } elseif ($Journey -eq 1) { 'repeated' } else { "retained-$($Journey - 1)" }
    $before = Send-Command @{ op = 'state' }
    Send-Command @{ op = 'begin'; label = "$label-entry" } | Out-Null
    Tap-Target -Key 'primary-action' -Feedback $(if ($Mode -eq 'wheel') { 'drawing' } else { '' }) -Label "$label-start" | Out-Null
    $state = Wait-Idle -MinimumMilliseconds $(if ($Mode -eq 'cards') { 2100 } else { 400 })
    Send-Command @{ op = 'end' } | Out-Null
    if ($Mode -eq 'cards') {
        $fan = Send-Command @{ op = 'resolve'; key = 'card-fan-scroll' }
        Send-Command @{ op = 'begin'; label = "$label-browse" } | Out-Null
        $left = $fan.left + [int]($fan.width * .15)
        $right = $fan.left + [int]($fan.width * .85)
        $y = $fan.top + [int]($fan.height * .55)
        for ($gesture = 0; $gesture -lt 3; $gesture++) {
            Invoke-Adb @('shell', 'input', 'swipe', "$right", "$y", "$left", "$y", '650') | Out-Null
            Invoke-Adb @('shell', 'input', 'swipe', "$left", "$y", "$right", "$y", '650') | Out-Null
        }
        $state = Wait-Idle
        if ($state.selected -ne $null -or @($state.results).Count -ne 0 -or $state.hasRound) { throw 'Scrolling unintentionally activated a card' }
        Send-Command @{ op = 'end' } | Out-Null
        Send-Command @{ op = 'begin'; label = "$label-reveal" } | Out-Null
        $state = Reveal-Card -Label $label
        Send-Command @{ op = 'end' } | Out-Null
    }
    $original = @($state.results)[0]
    Tap-Target -Key 'replace-result-0' | Out-Null
    Start-Sleep -Milliseconds 400
    Send-Command @{ op = 'begin'; label = "$label-replace" } | Out-Null
    Tap-Target -Key 'replacement-exclude' -Feedback $(if ($Mode -eq 'wheel') { 'drawing' } else { '' }) -Label "$label-replace" | Out-Null
    $state = Wait-Idle -MinimumMilliseconds $(if ($Mode -eq 'cards') { 1100 } else { 400 })
    if ($Mode -eq 'cards') { $state = Reveal-Card -Label "$label-replacement" }
    if (@($state.results).Count -ne 1 -or @($state.results)[0] -eq $original) { throw 'Replacement did not remove and replace the original stable ID' }
    Send-Command @{ op = 'end' } | Out-Null
    Send-Command @{ op = 'begin'; label = "$label-confirm-history" } | Out-Null
    Tap-Target -Key 'primary-action' -Feedback 'busy' -Label "$label-confirm" | Out-Null
    $state = Wait-Idle
    if ($state.hasRound -or $state.historyCount -ne ($before.historyCount + 1)) { throw 'Confirmation/history count invariant failed' }
    Navigate-Tab -Text '足迹' -ReadyKey $state.latestHistoryKey -Label "$label-history"
    Tap-Target -Key $state.latestHistoryKey | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-Adb @('shell', 'input', 'keyevent', '4') | Out-Null
    Navigate-Tab -Text '决定' -ReadyKey 'primary-action' -Label "$label-decision"
    Send-Command @{ op = 'end' } | Out-Null
    return @{ label = $label; historyCount = $state.historyCount; result = @($state.results); original = $original }
}
foreach ($pool in $Pools) {
    foreach ($photoPercent in $Photos) {
        foreach ($mode in $Modes) {
            foreach ($run in $Runs) {
                $case = "$Scenario-$pool-$photoPercent-$mode-run$run"
                $caseDirectory = Join-Path $output $case
                New-Item -ItemType Directory -Path $caseDirectory | Out-Null
                $navigationPath = Join-Path $caseDirectory 'navigation.jsonl'
                Write-Host "Measuring $case"
                Start-Probe
                $stopFile = Join-Path $caseDirectory 'stop-sampling'
                if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $stopFile }
                $samplesFile = Join-Path $caseDirectory 'pss.jsonl'
                $sampler = Start-Job -ArgumentList $Adb, $Serial, $package, $samplesFile, $stopFile -ScriptBlock {
                    param($adbPath, $deviceSerial, $appPackage, $samplePath, $stopPath)
                    while (!(Test-Path -LiteralPath $stopPath)) {
                        $raw = (& $adbPath -s $deviceSerial shell dumpsys meminfo $appPackage 2>&1) -join "`n"
                        $processId = (& $adbPath -s $deviceSerial shell pidof $appPackage) -join ''
                        $pss = $null
                        if ($raw -match 'TOTAL PSS:\s+(\d+)') { $pss = [int64]$Matches[1] }
                        elseif ($raw -match '(?m)^\s+TOTAL\s+(\d+)') { $pss = [int64]$Matches[1] }
                        @{ wallUtc = [DateTime]::UtcNow.ToString('o'); pssKiB = $pss; pid = $processId.Trim(); raw = $raw } |
                            ConvertTo-Json -Compress -Depth 3 | Add-Content -LiteralPath $samplePath -Encoding utf8
                        Start-Sleep -Seconds 1
                    }
                }
                $journeys = [Collections.Generic.List[object]]::new()
                try {
                    $configured = Send-Command @{ op = 'configure'; pool = $pool; photos = $photoPercent; mode = $mode; scenario = $Scenario } -TimeoutSeconds 120
                    $journeys.Add((Invoke-Journey -Mode $mode -Journey 0))
                    $journeys.Add((Invoke-Journey -Mode $mode -Journey 1))
                    Start-Sleep -Seconds 5
                    $restBaseline = Get-Pss
                    $restFinal = $null
                    if ($run -eq 1 -and !$SkipRetainedJourneys -and ($RetainedAllCases -or ($pool -eq 1000 -and $photoPercent -eq 100))) {
                        for ($journey = 2; $journey -lt 12; $journey++) {
                            $journeys.Add((Invoke-Journey -Mode $mode -Journey $journey))
                        }
                        Start-Sleep -Seconds 5
                        $restFinal = Get-Pss
                    }
                    Send-Command @{ op = 'export' } | Out-Null
                    Invoke-Adb @('pull', "$remote/report.json", (Join-Path $caseDirectory 'frames-input.json')) | Out-Null
                    $result = @{ case = $case; configured = $configured; journeys = $journeys.ToArray(); restingBaseline = $restBaseline; restingFinal = $restFinal; complete = $true }
                    $result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $caseDirectory 'journeys.json') -Encoding utf8
                } catch {
                    @{ case = $case; complete = $false; error = "$_"; journeys = $journeys.ToArray() } |
                        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $caseDirectory 'failure.json') -Encoding utf8
                    throw
                } finally {
                    [IO.File]::WriteAllText($stopFile, 'stop')
                    Wait-Job -Job $sampler -Timeout 10 | Out-Null
                    if ($sampler.State -eq 'Running') { Stop-Job -Job $sampler }
                    Receive-Job -Job $sampler -ErrorAction Continue | Out-Null
                    Remove-Job -Job $sampler
                }
            }
        }
    }
}
