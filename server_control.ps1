param(
    [ValidateSet('start', 'stop', 'restart', 'status')]
    [string]$Action = 'status'
)

# Lokalny serwer deweloperski. Produkcja działa na Proxmox i nie jest sterowana z tego skryptu.
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerScript = Join-Path $ProjectDir 'server\sync_server.py'

function Get-Python {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-ServerPid {
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*sync_server.py*' } |
        Select-Object -First 1 -ExpandProperty ProcessId
}

function Stop-Server {
    $pidServer = Get-ServerPid
    if ($pidServer) { Stop-Process -Id $pidServer -Force -ErrorAction SilentlyContinue }
}

function Start-Server {
    $python = Get-Python
    if (-not $python) { Write-Host "Brak Pythona w PATH"; return }
    if (Get-ServerPid) { Write-Host "Serwer juz dziala"; return }
    Start-Process -FilePath $python -ArgumentList "`"$ServerScript`"" -WorkingDirectory $ProjectDir -WindowStyle Hidden
    Start-Sleep -Seconds 2
    Write-Host "Serwer wystartowal: http://localhost:8081"
}

switch ($Action) {
    'stop'    { Stop-Server; Write-Host "Zatrzymano lokalny serwer." }
    'start'   { Start-Server }
    'restart' { Stop-Server; Start-Sleep -Seconds 1; Start-Server }
    'status'  {
        $pidServer = Get-ServerPid
        [PSCustomObject]@{
            ServerRunning = ($pidServer -ne $null)
            ServerPid     = $pidServer
            LocalUrl      = 'http://localhost:8081'
        } | Format-List
    }
}
