@echo off
setlocal
cd /d "%~dp0"
title KSSMA-Re Stop
echo 正在关闭本地服务器。模拟器可以手动关闭，也可以留着下次更快启动。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\work\kssma-server.ps1" stop
echo.
pause
