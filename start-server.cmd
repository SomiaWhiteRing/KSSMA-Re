@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if /I "%~1"=="self-test" (
  echo start-server.cmd self-test ok
  exit /b 0
)

title KSSMA-Re Server
echo Starting KSSMA-Re local server.
echo Keep this server running while playing.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\work\kssma-server.ps1" start
set "KSSMA_EXIT=%ERRORLEVEL%"
echo.
echo Finished with exit code %KSSMA_EXIT%.
echo If the game cannot connect, send this window text and work\kssma-server.out.log.
echo.
pause
exit /b %KSSMA_EXIT%
