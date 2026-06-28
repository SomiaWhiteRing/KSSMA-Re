@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if /I "%~1"=="self-test" (
  echo start-runtime.cmd self-test ok
  exit /b 0
)

title KSSMA-Re ARM19
echo Starting KSSMA-Re ARM19 emulator.
echo This prepares the emulator, hosts mapping, display, save mount, audio, package baseline, and exploration patch.
echo It does not start the local server.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\work\kssma-runtime.ps1" start-runtime
set "KSSMA_EXIT=%ERRORLEVEL%"
echo.
echo Finished with exit code %KSSMA_EXIT%.
echo If this failed, send this window text to the developer.
echo.
pause
exit /b %KSSMA_EXIT%
