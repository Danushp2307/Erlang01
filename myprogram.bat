@echo off
set "PATH=C:\Program Files\Erlang OTP\bin;%PATH%"

if "%~1"=="" (
    echo Usage:
    echo   Server Mode: .\myprogram.bat ^<LeadingZeros^>   [e.g. .\myprogram.bat 4]
    echo   Worker Mode: .\myprogram.bat ^<ServerIP^>       [e.g. .\myprogram.bat 192.168.0.26]
    exit /b 1
)

cd /d "%~dp0"
if not exist "project1.beam" (
    erlc project1.erl
)

erl -noshell -pa . -s project1 main %*
