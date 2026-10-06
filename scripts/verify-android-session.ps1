param(
    [string]$Adb = 'D:/SDK/platform-tools/adb.exe',
    [string]$Serial = 'emulator-5554',
    [string]$OutputDirectory = 'build/s02-session-evidence'
)

# Requires the test-only integration_test/lifecycle_probe.dart APK already installed.
# Uses real Android events and preserves the production database.
$ErrorActionPreference = 'Stop'
$package = 'com.xinlx227.whatever'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$observations = [System.Collections.Generic.List[object]]::new()

function Invoke-Adb {
    $output = & $Adb -s $Serial @args
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $args ($output)" }
    return $output
}

function Get-Window {
    Invoke-Adb shell uiautomator dump /sdcard/s02-session.xml | Out-Null
    [xml]$window = (Invoke-Adb shell cat /sdcard/s02-session.xml | Out-String)
    return ,$window
}

function Tap-Label([string]$label) {
    $window = Get-Window
    $node = @($window.SelectNodes('//node') | Where-Object {
        $_.'content-desc' -eq $label -and $_.enabled -eq 'true'
    })[0]
    if (!$node) { throw "Visible action missing: $label" }
    $bounds = [regex]::Matches($node.bounds, '\d+') | ForEach-Object { [int]$_.Value }
    Invoke-Adb shell input tap ([int](($bounds[0] + $bounds[2]) / 2)) ([int](($bounds[1] + $bounds[3]) / 2)) | Out-Null
}

function Read-Probe([string]$phase) {
    $window = Get-Window
    $state = [ordered]@{ phase = $phase }
    foreach ($node in $window.SelectNodes('//node')) {
        if ($node.'content-desc' -match '^([a-zA-Z]+): (.*)$') {
            $state[$Matches[1]] = $Matches[2]
        }
    }
    if (!$state.Contains('processId')) { throw "Probe not foreground at $phase" }
    if ($state.controllerError -ne 'none' -or $state.probeError -ne 'none') {
        throw "Probe error: $($state | ConvertTo-Json -Compress)"
    }
    $window.Save((Join-Path (Resolve-Path $OutputDirectory) "$phase.xml"))
    $observations.Add($state)
    $observations | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $OutputDirectory 'observations.json')
    Write-Host ($state | ConvertTo-Json -Compress)
    return $state
}

function Assert-Value($actual, $expected, [string]$description) {
    if ($actual -ne $expected) { throw "$description expected '$expected', got '$actual'" }
}

function Launch-Probe {
    Invoke-Adb shell am start -W -n "$package/.MainActivity" | Out-Null
}

function Assert-Fresh($state, $historyCount) {
    Assert-Value $state.hasRound 'false' 'Fresh round'
    Assert-Value $state.isModeLocked 'false' 'Fresh mode lock'
    Assert-Value $state.sessionExclusions '[]' 'Fresh session exclusions'
    Assert-Value $state.result 'none' 'Fresh result'
    Assert-Value $state.mode 'cards' 'Durable mode'
    Assert-Value $state.excludeYesterday 'true' 'Durable yesterday filter'
    Assert-Value $state.historyCount $historyCount 'Durable history'
    $deviceHour = [int](Invoke-Adb shell date +%H)
    $period = if ($deviceHour -ge 5 -and $deviceHour -lt 11) { 'breakfast' }
        elseif ($deviceHour -ge 11 -and $deviceHour -lt 16) { 'lunch' }
        elseif ($deviceHour -ge 16 -and $deviceHour -lt 21) { 'dinner' }
        else { 'lateNight' }
    Assert-Value $state.period $period 'Fresh local period'
}

$lockWasDisabled = (Invoke-Adb shell locksettings get-disabled | Out-String).Trim()
Invoke-Adb shell locksettings set-disabled false | Out-Null
try {
    Launch-Probe
    Tap-Label 'Reset preferences'
    $initial = Read-Probe 'initial'
    Assert-Value $initial.mode 'wheel' 'Reset mode'
    Assert-Value $initial.excludeYesterday 'false' 'Reset yesterday filter'
    Tap-Label 'Prepare session'
    $prepared = Read-Probe 'prepared'
    Assert-Value $prepared.hasRound 'true' 'Prepared round'
    Assert-Value $prepared.sessionExclusions '[soy-milk]' 'Prepared exclusions'

    Invoke-Adb shell input keyevent KEYCODE_HOME | Out-Null
    Launch-Probe
    $returned = Read-Probe 'home-return'
    foreach ($key in @('processId', 'result', 'period', 'sessionExclusions', 'hasRound')) {
        Assert-Value $returned[$key] $prepared[$key] "Home preserves $key"
    }

    Invoke-Adb shell input keyevent KEYCODE_SLEEP | Out-Null
    Start-Sleep -Seconds 6
    Invoke-Adb shell dumpsys power | Set-Content -Encoding utf8 (Join-Path $OutputDirectory 'screen-off-power.txt')
    $lockPolicy = Invoke-Adb shell dumpsys window policy | Out-String
    $lockPolicy | Set-Content -Encoding utf8 (Join-Path $OutputDirectory 'screen-off-policy.txt')
    if ($lockPolicy -notmatch '(?m)^\s+showing=true') { throw 'Keyguard did not lock' }
    Invoke-Adb shell input keyevent KEYCODE_WAKEUP | Out-Null
    Invoke-Adb shell wm dismiss-keyguard | Out-Null
    $unlocked = Read-Probe 'lock-return'
    foreach ($key in @('processId', 'result', 'period', 'sessionExclusions', 'hasRound')) {
        Assert-Value $unlocked[$key] $prepared[$key] "Lock preserves $key"
    }

    Tap-Label 'Abandon'
    $abandoned = Read-Probe 'abandoned'
    Assert-Value $abandoned.hasRound 'false' 'Abandoned round'
    Assert-Value $abandoned.isModeLocked 'false' 'Abandoned mode lock'
    Assert-Value $abandoned.sessionExclusions '[soy-milk]' 'Abandon preserves exclusions'

    # With no started round, Back goes home without destroying the live session.
    Invoke-Adb shell input keyevent KEYCODE_BACK | Out-Null
    Start-Sleep -Milliseconds 500
    $activities = Invoke-Adb shell dumpsys activity activities | Out-String
    if ($activities -match 'mResumedActivity:.*com\.xinlx227\.whatever') {
        throw 'Root Back did not return home'
    }
    Launch-Probe
    $back = Read-Probe 'back-return'
    Assert-Value $back.processId $prepared.processId 'Back preserves process'
    Assert-Value $back.sessionExclusions '[soy-milk]' 'Back preserves exclusions'
    Assert-Value $back.period 'lateNight' 'Back preserves manual period'

    Tap-Label 'New round'
    Tap-Label 'Confirm'
    $confirmed = Read-Probe 'confirmed'
    Assert-Value $confirmed.historyCount ([string]([int]$initial.historyCount + 1)) 'Explicit confirmation'
    Assert-Value $confirmed.sessionExclusions '[soy-milk]' 'Confirmation preserves exclusions'
    Tap-Label 'New round'
    Invoke-Adb shell am force-stop $package | Out-Null
    $stopped = Invoke-Adb shell 'pidof com.xinlx227.whatever || true'
    Assert-Value ($stopped | Out-String).Trim() '' 'Force stop terminates process'
    Launch-Probe
    $fresh = Read-Probe 'force-stop-return'
    Assert-Fresh $fresh $confirmed.historyCount
    if ($fresh.processId -eq $prepared.processId) { throw 'Force stop reused process' }

    Tap-Label 'Prepare session'
    $beforeKill = Read-Probe 'before-kill'
    Invoke-Adb shell input keyevent KEYCODE_HOME | Out-Null
    Start-Sleep -Milliseconds 700
    # am kill may decline to kill a recently visible process. SIGKILL under the
    # debuggable app's own UID proves termination without force-stop semantics.
    Invoke-Adb shell run-as $package kill -9 $beforeKill.processId | Out-Null
    Start-Sleep -Milliseconds 700
    $killed = Invoke-Adb shell 'pidof com.xinlx227.whatever || true'
    Assert-Value ($killed | Out-String).Trim() '' 'Background kill terminates process'
    Launch-Probe
    $afterKill = Read-Probe 'background-kill-return'
    Assert-Fresh $afterKill $confirmed.historyCount
    if ($afterKill.processId -eq $beforeKill.processId) { throw 'Background kill reused process' }

    Tap-Label 'Prepare session'
    $beforeRemoval = Read-Probe 'before-recents-removal'
    Invoke-Adb shell input keyevent KEYCODE_APP_SWITCH | Out-Null
    Start-Sleep -Milliseconds 700
    # Quickstep can move the card while entering overview. Re-read its bounds before
    # each bounded attempt, and only ever swipe the explicitly identified app task.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $recents = Get-Window
        $recents.Save((Join-Path (Resolve-Path $OutputDirectory) "recents-$attempt.xml"))
        $task = @($recents.SelectNodes('//node') | Where-Object {
            $_.'resource-id' -eq 'com.android.launcher3:id/task' -and $_.'content-desc' -eq '这一餐'
        })[0]
        if (!$task) { throw 'Expected app task not found in AOSP recents; no swipe performed' }
        $bounds = [regex]::Matches($task.bounds, '\d+') | ForEach-Object { [int]$_.Value }
        $x = [int](($bounds[0] + $bounds[2]) / 2)
        $y = [int]($bounds[3] - ($bounds[3] - $bounds[1]) * 0.2)
        Write-Host "Recents swipe $attempt from ${x},$y (task $($task.bounds))"
        Invoke-Adb shell input swipe $x $y $x 250 250 | Out-Null
        Start-Sleep -Seconds 1
        $tasks = Invoke-Adb shell dumpsys activity recents | Out-String
        if ($tasks -notmatch 'Recent #\d+:.*com\.xinlx227\.whatever') { break }
    }
    if ($tasks -match 'Recent #\d+:.*com\.xinlx227\.whatever') { throw 'App task still exists after swipe' }
    Launch-Probe
    $afterRemoval = Read-Probe 'recents-removal-return'
    Assert-Fresh $afterRemoval $confirmed.historyCount
    Write-Host 'PASS: real Home, lock, Back, force stop, background kill, and recents removal.'
} finally {
    Invoke-Adb shell input keyevent KEYCODE_WAKEUP | Out-Null
    Invoke-Adb shell wm dismiss-keyguard | Out-Null
    Invoke-Adb shell locksettings set-disabled $lockWasDisabled | Out-Null
}
