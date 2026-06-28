@echo off
setlocal
cd /d "%~dp0"
title KSSMA-Re Play
echo 扩散性百万亚瑟王本地复原版
echo 1. 请等待脚本自动启动服务器和模拟器。
echo 2. 看到游戏主菜单后，就可以直接体验已完成内容：主菜单、角色互动、探索区域/楼层/关卡。
echo 3. 玩完请运行 stop.cmd 关闭本地服务器。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\work\kssma-runtime.ps1" play
echo.
echo 看到模拟器里的游戏主菜单，就表示已经准备好。
echo 如果没有进入主菜单，请把窗口内容和 work\kssma-flow-play-* 路径发给开发者。
pause
