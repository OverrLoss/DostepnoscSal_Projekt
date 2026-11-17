# server_control.ps1 - Zarzadzanie serwerem SQLite i tunelem Cloudflare (v1.2.0)
param(
    [ValidateSet("start", "stop", "status", "restart")]
    [string]$Action = "start"
)

$ErrorActionPreference = "SilentlyContinue"
$ProjectDir = $PSScriptRoot
if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }

# Dynamiczna konfiguracja tunelu Cloudflare
$LocalCfDir = Join-Path $ProjectDir ".cloudflared"
$LocalCredFile = Join-Path $LocalCfDir "b3ecea77-5b0d-460d-88d6-28e570d05421.json"

if (Test-Path $LocalCredFile) {
    $ConfigFile = Join-Path $LocalCfDir "config.yml"
    $configContent = @"
tunnel: b3ecea77-5b0d-460d-88d6-28e570d05421
credentials-file: $LocalCredFile

ingress:
  - hostname: sale.pwojtaszek.codes
    service: http://127.0.0.1:8081
  - hostname: gra.pwojtaszek.codes
    service: http://localhost:8080
  - hostname: gra.pwojtaszek.5g.in
    service: http://localhost:8080
  - service: http_status:404
"@
    Set-Content -Path $ConfigFile -Value $configContent -Encoding UTF8
} else {
    $ConfigFile = Join-Path $env:USERPROFILE ".cloudflared\config.yml"
}

function Get-CloudflaredPath {
    $paths = @(
        (Join-Path $LocalCfDir "cloudflared.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "cloudflared\cloudflared.exe"),
        (Join-Path $env:ProgramFiles "cloudflared\cloudflared.exe")
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-PythonPid {
    $conn = Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn -and $conn.OwningProcess) { return $conn.OwningProcess }
    return $null
}

function Get-CloudflarePid {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine.Contains("wmt-gra")) {
            return $p.ProcessId
        }
    }
    if ($procs) {
        return ($procs | Select-Object -Last 1).ProcessId
    }
    return $null
}

function Stop-All {
    $py = Get-PythonPid
    if ($py) {
        Stop-Process -Id $py -Force -ErrorAction SilentlyContinue
    }
    $cf = Get-CloudflarePid
    if ($cf) {
        Stop-Process -Id $cf -Force -ErrorAction SilentlyContinue
    }
}

function Start-All {
    # 1. Start Python Server if not running
    $py = Get-PythonPid
    if (-not $py) {
        $serverScript = Join-Path $ProjectDir "server\sync_server.py"
        Start-Process -FilePath "python.exe" -ArgumentList "`"$serverScript`"" -WorkingDirectory $ProjectDir -WindowStyle Hidden
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Milliseconds 300
            $py = Get-PythonPid
            if ($py) { break }
        }
    }

    # 2. Start Cloudflare Tunnel if not running
    $cf = Get-CloudflarePid
    $cfExe = Get-CloudflaredPath

    if (-not $cf) {
        if (-not $cfExe) {
            Write-Host "      [!] Program cloudflared nie jest zainstalowany na tym komputerze." -ForegroundColor Yellow
            Write-Host "          Aby wlaczyc tunel publiczny HTTPS, wpisz w terminalu:" -ForegroundColor Yellow
            Write-Host "          winget install --id Cloudflare.cloudflared" -ForegroundColor White
        } else {
            Start-Process -FilePath $cfExe -ArgumentList "tunnel --config `"$ConfigFile`" run wmt-gra" -WorkingDirectory $ProjectDir -WindowStyle Hidden
            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Milliseconds 400
                $cf = Get-CloudflarePid
                if ($cf) { break }
            }
            Start-Sleep -Seconds 4
        }
    }

    # 3. Pobierz aktualne IP Wi-Fi
    $lanIp = "10.90.250.195"
    try {
        $info = Invoke-RestMethod -Uri "http://127.0.0.1:8081/api/server-info" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($info -and $info.lanIp) { $lanIp = $info.lanIp }
    } catch {}

    [PSCustomObject]@{
        PythonRunning     = ($py -ne $null)
        PythonPid         = $py
        CloudflareRunning = ($cf -ne $null)
        CloudflarePid     = $cf
        LanIp             = $lanIp
        PublicUrl         = "https://sale.pwojtaszek.codes"
        LanUrl            = "http://${lanIp}:8081"
        LocalUrl          = "http://localhost:8081"
    }
}

switch ($Action) {
    "stop" {
        Stop-All
        Write-Host "Zatrzymano serwer i tunel."
    }
    "restart" {
        Stop-All
        Start-Sleep -Seconds 1
        Start-All | Format-List
    }
    "status" {
        $py = Get-PythonPid
        $cf = Get-CloudflarePid
        [PSCustomObject]@{
            PythonRunning     = ($py -ne $null)
            PythonPid         = $py
            CloudflareRunning = ($cf -ne $null)
            CloudflarePid     = $cf
        } | Format-List
    }
    "start" {
        Start-All | Format-List
    }
}
