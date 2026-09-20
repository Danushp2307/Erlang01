# ===================================================================
# COP5615 Project 1 - Runner Script (PowerShell)
# Usage:
#    .\myprogram.ps1 4               (Start Server with K=4)
#    .\myprogram.ps1 192.168.0.26    (Start Worker pointing to Server IP)
# ===================================================================

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Target
)

# Ensure Erlang OTP is in PATH
$erlPath = "C:\Program Files\Erlang OTP\bin"
if (Test-Path $erlPath) {
    if ($env:PATH -notlike "*$erlPath*") {
        $env:PATH = "$erlPath;$env:PATH"
    }
}

# Detect local IP
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1).IPAddress
if (-not $localIP) { $localIP = "127.0.0.1" }

$scriptDir = $PSScriptRoot

# Compile if needed
if (-not (Test-Path "$scriptDir\project1.beam")) {
    & erlc "$scriptDir\project1.erl"
}

if ($Target -match '^\d+$') {
    Write-Host "[Starting Main Server Node on $localIP with K=$Target...]" -ForegroundColor Green
    & erl -name "server@$localIP" -setcookie cop5615_cookie -noshell -pa "$scriptDir" -s project1 main $Target
} else {
    $randId = Get-Random -Minimum 10000 -Maximum 99999
    Write-Host "[Starting Worker Node connecting to server at $Target...]" -ForegroundColor Cyan
    & erl -name "worker_$randId@$localIP" -setcookie cop5615_cookie -noshell -pa "$scriptDir" -s project1 main $Target
}
