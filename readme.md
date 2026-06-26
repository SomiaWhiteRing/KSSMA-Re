# 扩散性百万亚瑟王重建项目

该项目的最终目的是重建已经停服的手游《扩散性百万亚瑟王》，使其能够使用本地搭建的服务器进行游戏。项目的开发和维护由社区志愿者完成，旨在让玩家能够继续享受这款经典游戏。

该项目目前正处于初创阶段，其结构和内容随时且快速的可能发生变化。

如果当前调试已经绕进黑屏、资源、APK 大改等问题，先从 `clean-start.md` 重新
建立主线。这个项目的短期目标是稳定推进客户端的下一条服务器请求，而不是一次性
修完整个画面。

## 项目结构

- `base/`：《扩散性百万亚瑟王》的基础数据和资源。
- `work/`：从客户端样本拆出的反编译与资源产物。
- `server/`：本地引导/协议验证用的最小服务端。

## 当前可用的最短流程

先启动本地引导服务。当前 ARM 主线使用 `sample`，它能走到主菜单；主菜单背景、
初始角色脸图、信息框、BGM/角色语音、点角色表情变化与同步台词已完成第一轮验收。
关服前录像确认点角色台词本来就没有底色/对话框背景。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start
```

查看状态、日志或停止服务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 log
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 stop
```

手动启动等价于：

```powershell
$env:CHECK_INSPECTION_KEY='rBwj1MIAivVN222b'
$env:CONNECT_APP_KEY='rBwj1MIAivVN222b'
$env:LOGIN_RESPONSE='sample'
$env:PORTS='50005,10001'
node .\server\bootstrap-server.js
```

它目前实现了客户端前导接口和一小段 native 引导接口：

- `POST /world_list.php`
- `POST /add_user.php`
- `POST /check_inspection`
- `POST /connect/app/notification/post_devicetoken`
- `POST /connect/app/login`
- `POST /connect/app/masterdata/*/update`
- `GET /connect/web/*`
- `GET /contents/*`

用途是先顶住世界选择、入场注册、密钥加密和资源入口，把请求打印出来，再继续补 `/connect/app/` 协议。`LOGIN_RESPONSE` 不设置时只返回最小成功 XML；`sample` 是当前最远路径；`tutorial` 会进入教程 scene 100，但会在教程资源路径上更早崩溃，暂时不是主线。
服务端默认把客户端回调地址写成 `http://10.0.2.2:50005/`，这是 Android 模拟器访问宿主机的地址；如果换真机或不同虚拟化网络，再用 `GUEST_HOST` 或 `WORLD_URL`/`TOP_URL` 覆盖。

开始人工测试前，可以跑只读 preflight：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-preflight.ps1
```

它不会启动、停止、root、push 或修改模拟器，只检查 server 端口、ARM19 ADB 目标、
hosts、显示、音频和几个关键资源文件，并给出下一条该执行的修复命令。

## 旧安卓运行时

不要再用本机的 Android 12 模拟器跑这个客户端。
当前已验证的运行时是 `kssma_arm19`：Android `4.4.2` / API 19 / `armeabi-v7a` classic ARM emulator。
这是这份 ARM-only 2013 APK 的最短可用目标，BlueStacks x86/Houdini 崩溃先不要当主线。

仓库里已经附了运行时控制脚本。实机测试前先跑快检：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health
```

快检只连接 `127.0.0.1:5583` 并读取 ABI、Android 版本和 boot 状态；它不会截图、
读 logcat、跑 dumpsys、改 hosts 或重启模拟器。正常热状态应在约 1 秒内返回
`ok=true`。如果失败，再跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb
```

常用命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 configure
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-runtime
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-baseline
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 patch-lib -ApkPath .\work\million-cn-animationguard-signed.apk
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 clean-install
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 install-apk -ApkPath .\work\million-cn-animationguard-signed.apk
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 preload-small
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 launch
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 observe -Observe Requests,Activity,Logcat
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 run -DriveLogin -Observe Requests,Activity,Logcat
```

说明：

- `preload-small` 只推 `download/rest`、`download/scenario`、`download/pack` 和少量必需文件，用来快速验证启动链；完整资源仍用 `preload-full` 单独处理。
- `preload-small` 也会推已证明需要的小文件：`save_version`、`master_*`、`adv_chara111`、`bgm_common1.ogg`。
- `ensure-baseline` 幂等检查 hosts、mount、display、audio 和 package；只有不符合基线才修复。
- `launch` 只启动游戏，不隐式重复 hosts/mount；`run` 只执行一次 `ensure-baseline`。
- 如果游戏提示无法连接服务器，先检查 `work\kssma-server.ps1 status`，确认 `50005` 和 `10001` 都在监听。
- native-only 实验默认用 `patch-lib`，它只替换已安装包里的 `librooneyj.so`，避免每次推 304MB APK。
- 只有 Java、resources、manifest、签名或包结构变化时才用完整 `install-apk`；安装前先跑 `clean-install` 清理 Android 4.4 遗留的临时安装文件。
- `install-apk` 使用内部安装，绕过 Android 4.4 外置 ASEC 安装不稳定的问题；如果 ADB 客户端超时但设备端安装已完成，helper 会验证已安装 `librooneyj.so` 后给出结论。
- `restart-runtime` 是破坏性命令，必须显式带 `-Force -Reason "..."`。普通连接、修复、
  baseline 或安装命令不会杀模拟器进程。
- 不要默认用 Frida 做运行时探针；它容易让 ARM19 ADB transport 掉到 offline。只有有明确 hook 假设时再单独使用，并在回到 ADB 测试前停掉。
- `-gpu on` 是当前默认；`-gpu off` 会产生误导性的 OpenGL ES 噪声。
- 音频是当前运行时基线的一部分；不要用 `-no-audio` 启动 ARM19，否则无法验证 BGM 和角色语音。
- BlueStacks 脚本还保留在 `work\bluestacks-nougat32.ps1`，但只作为排查对照，不再是默认运行时。

当前运行时已经能进入并验收主菜单，加载 `adv_chara111` 与 `bgm_common1.ogg`。`_Layout::event(...)` 的 ARM `0x98` 崩溃已通过 `work\build-animation-nullguard.py` 中的最小 native guard 绕过；后续会打开本地 `/connect/web/` 占位页，按需用 `work\kssma-runtime.ps1 observe -Observe Requests,Activity,Logcat,Screenshot` 采集 artifact。

已整理的逆向笔记见 `reverse-notes.md`。
