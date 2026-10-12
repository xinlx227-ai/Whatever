param(
    [string]$KeyFile = 'D:\project\mimo_api.txt'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$secretDirectory = Join-Path $repoRoot 'build'
[System.IO.Directory]::CreateDirectory($secretDirectory) | Out-Null
$defineFile = Join-Path $secretDirectory ('mimo-defines-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $apiKey = [System.IO.File]::ReadAllText($KeyFile).Trim()
    if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '\s') {
        throw 'The credential file must contain one non-empty API key.'
    }
    $defines = @{ MIMO_API_KEY = $apiKey } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($defineFile, $defines, [System.Text.UTF8Encoding]::new($false))
    Push-Location $repoRoot
    try {
        & flutter build apk --release "--dart-define-from-file=$defineFile"
        if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
    } finally {
        Pop-Location
    }
} finally {
    $apiKey = $null
    $defines = $null
    if (Test-Path -LiteralPath $defineFile) {
        Remove-Item -LiteralPath $defineFile -Force
    }
}
