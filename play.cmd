@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if /I "%~1"=="self-test" (
  echo play.cmd self-test ok
  exit /b 0
)

title KSSMA-Re
echo KSSMA-Re now uses three simple entries:
echo.
echo 1. start-runtime.cmd  - start the ARM19 emulator
echo 2. start-server.cmd   - start the local server
echo 3. stop.cmd           - stop the local server
echo.
echo After steps 1 and 2, launch or use the game in the ARM19 emulator.
echo.
pause
exit /b 0
