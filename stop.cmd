@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if /I "%~1"=="self-test" (
  echo stop.cmd self-test ok
  exit /b 0
)

title KSSMA-Re Stop
echo Stopping KSSMA-Re local server.
echo The emulator can be closed manually or left open for a faster next start.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\work\kssma-server.ps1" stop
set "KSSMA_EXIT=%ERRORLEVEL%"
echo.
echo Finished with exit code %KSSMA_EXIT%.
echo.
pause
exit /b %KSSMA_EXIT%
