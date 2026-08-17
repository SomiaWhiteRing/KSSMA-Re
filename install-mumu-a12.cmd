@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if /I "%~1"=="self-test" (
  echo install-mumu-a12.cmd self-test ok
  exit /b 0
)

title KSSMA-Re MuMu Android 12 Installer
echo Preparing and deploying KSSMA-Re to MuMu Android 12 at 127.0.0.1:7555.
echo This preserves mutable game save data, repairs the two legacy host names,
echo installs the complete static resource pack, starts the local server, and launches the client.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\work\kssma-mumu-a12.ps1" deploy -StartServer -Launch
set "KSSMA_EXIT=%ERRORLEVEL%"
echo.
echo Finished with exit code %KSSMA_EXIT%.
echo If this failed, copy this window text before retrying.
echo.
pause
exit /b %KSSMA_EXIT%
