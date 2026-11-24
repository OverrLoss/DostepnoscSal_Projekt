param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Notes = '',
    [string]$Version = ''
)

# Tworzy Release i uploaduje APK oraz SPA. Nie zawiera danych tunelu ani Cloudflare.
$ErrorActionPreference = 'Stop'
if (-not $Version) { $Version = $Tag -replace '^v', '' }

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Notes) {
    $changelog = Join-Path $root 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $txt = Get-Content -Raw -Encoding UTF8 $changelog
        $pattern = '(?ms)^##\s+' + [regex]::Escape($Version) + '\s*$\r?\n(.*?)(?=^##\s|\z)'
        $m = [regex]::Match($txt, $pattern)
        if ($m.Success) { $Notes = $m.Groups[1].Value.Trim() }
    }
}
if (-not $Notes) { $Notes = "Wersja $Version" }
$apk = Join-Path $root "build\web\DostepnoscSal_v$Version.apk"
if (-not (Test-Path $apk)) { $apk = Join-Path $root 'DostepnoscSal.apk' }
$web = Join-Path $root "web_v$Version.zip"

$cred = ("protocol=https`nhost=github.com`n`n" | git credential fill)
$tok = ($cred | Where-Object { $_ -like 'password=*' }).Substring(9)
$h = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json' }
$body = @{
    tag_name = $Tag
    name = $Tag
    body = if ($Notes) { $Notes } else { "Wersja $Version" }
    draft = $false
    prerelease = $false
} | ConvertTo-Json -Compress

$r = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/repos/OverrLoss/DostepnoscSal_Projekt/releases' `
    -Headers $h -ContentType 'application/json; charset=utf-8' `
    -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
Write-Output ("RELEASE " + $r.tag_name)

$up = $r.upload_url -replace '\{.*$', ''
foreach ($file in @($apk, $web)) {
    if (-not (Test-Path $file)) { Write-Output ("POMINIETO " + (Split-Path $file -Leaf)); continue }
    $name = Split-Path $file -Leaf
    $a = Invoke-RestMethod -Method Post -Uri ($up + '?name=' + $name) -Headers $h `
        -ContentType 'application/octet-stream' -InFile $file -TimeoutSec 300
    Write-Output ("ASSET " + $a.name + " " + $a.size)
}
