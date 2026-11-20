# server_control.ps1 - Zarzadzanie serwerem SQLite i tunelem Cloudflare (v1.2.0)
param(
    [ValidateSet("start", "stop", "status", "restart")]
    [string]$Action = "start"
)

$ErrorActionPreference = "SilentlyContinue"
$ProjectDir = $PSScriptRoot
if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }

# Tunel Cloudflare jest jedna usluga Windows (victus, token z C:\ProgramData\cloudflared\token).
# Trasy publiczne (sale/gra/plan) sa ustawione w panelu Cloudflare Zero Trust,
# lokalny config.yml nie jest uzywany. Nie uruchamiamy osobnych tuneli.
$LocalCfDir = Join-Path $ProjectDir ".cloudflared"
$CloudflaredService = "Cloudflared"
$TunnelTokenFile = Join-Path $LocalCfDir "victus.token"

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
    $svc = Get-Service -Name $CloudflaredService -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { return $svc.Status }
    # Na komputerze bez uslugi: tunel uruchomiony z pliku tokenu.
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine.Contains("victus.token")) { return $p.ProcessId }
    }
    return $null
}

function Stop-All {
    $py = Get-PythonPid
    if ($py) {
        Stop-Process -Id $py -Force -ErrorAction SilentlyContinue
    }
    # Nie zatrzymujemy uslugi Cloudflared - obsluga rowniez inne aplikacje.
    # Zatrzymujemy tylko tunel uruchomiony z naszego pliku tokenu.
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine.Contains("victus.token")) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
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

    # 2. Tunel victus: usluga Windows albo plik tokenu z folderu projektu
    $cf = Get-CloudflarePid
    if (-not $cf) {
        $svc = Get-Service -Name $CloudflaredService -ErrorAction SilentlyContinue
        if ($svc) {
            Start-Service -Name $CloudflaredService -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $cf = Get-CloudflarePid
        } else {
            $cfExe = Get-CloudflaredPath
            if ($cfExe -and (Test-Path $TunnelTokenFile)) {
                Start-Process -FilePath $cfExe -ArgumentList "tunnel run --token-file `"$TunnelTokenFile`"" -WorkingDirectory $ProjectDir -WindowStyle Hidden
                for ($i = 0; $i -lt 15; $i++) {
                    Start-Sleep -Milliseconds 400
                    $cf = Get-CloudflarePid
                    if ($cf) { break }
                }
            }
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
        PublicUrl         = "https://sale.pwojtaszek.5g.in"
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
