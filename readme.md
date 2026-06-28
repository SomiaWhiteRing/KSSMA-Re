# 扩散性百万亚瑟王重建项目

该项目的最终目的是重建已经停服的手游《扩散性百万亚瑟王》，使其能够使用本地搭建的服务器进行游戏。项目的开发和维护由社区志愿者完成，旨在让玩家能够继续享受这款经典游戏。

该项目目前正处于初创阶段，其结构和内容随时且快速的可能发生变化。

如果当前调试已经绕进黑屏、资源、APK 大改等问题，先从 `clean-start.md` 重新
建立主线。启动阶段按下一条服务器请求推进；进入主菜单后的玩法阶段按原始客户端
流程边推进：用户动作、请求/响应、页面状态、截图和下一次点击目标要一起验收。

## 项目结构

- `base/`：《扩散性百万亚瑟王》的基础数据和资源。
- `work/`：从客户端样本拆出的反编译与资源产物。
- `server/`：本地引导/协议验证用的最小服务端。

## 直接游玩

1. 双击 `start-runtime.cmd` 启动 ARM19 模拟器并准备 hosts、显示、存档挂载、音频、包基线和探索补丁。
2. 双击 `start-server.cmd` 启动本地服务器，然后在模拟器里打开游戏。
3. 玩完双击 `stop.cmd` 关闭本地服务器；模拟器可以手动关，也可以留着下次更快启动。

`play.cmd` 现在只保留为说明页。不要再把它当作一键启动入口；之前的一键入口把
模拟器、server、登录和验收 flow 绑在一起，遇到已有非 ARM19 设备时会报
`wrong-runtime-only`。

如果双击入口没有窗口或出现乱码，先在项目目录运行入口自检。它只验证 Windows 能正确解析
`.cmd`，不会启动模拟器：

```cmd
cmd /c start-runtime.cmd self-test
cmd /c start-server.cmd self-test
cmd /c play.cmd self-test
cmd /c stop.cmd self-test
```

当前可体验内容：主菜单、角色点击互动/BGM/语音、探索秘境列表、楼层列表、进入关卡、
返回秘境列表，以及前两块区域的临时背景。探索深层、战斗、妖精、奖励结算还在开发中。

## 开发验收入口

玩法实机验收默认跑日志化 flow，不再手动启动 server、逐步截图或 OCR。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-smoke
```

`flow` 会独占重启本地 `bootstrap-server.js`、检查 ARM19、必要时修复 ADB、确保唯一
client baseline、自动登录，然后跑主菜单到探索的层级往返冒烟。结果写入
`work\kssma-flow-exploration-smoke-YYYYMMDD-HHMMSS\`，先看 `summary.txt` 或
`summary.json`，再按需看 `requests.jsonl`、`events.jsonl`、`logcat.txt` 和关键截图。

查看可用 flow 场景：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario list
```

只测 flow 日志解析和 notice 判断，不启动模拟器：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario self-check
```

当前 server 实现了客户端前导接口和一小段 native 引导接口：

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

## 手动调试入口

这些命令保留给诊断和人工复核，不是玩法验收默认路径。手动查看、启动或停止 helper server：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 log
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 stop
```

手动启动 server 等价于：

```powershell
$env:CHECK_INSPECTION_KEY='rBwj1MIAivVN222b'
$env:CONNECT_APP_KEY='rBwj1MIAivVN222b'
$env:LOGIN_RESPONSE='sample'
$env:PORTS='50005,10001'
node .\server\bootstrap-server.js
```

只读 preflight 仍可用于人工调试。它不会启动、停止、root、push 或修改模拟器，只检查
server 端口、ARM19 ADB 目标、hosts、显示、音频和几个关键资源文件。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-preflight.ps1
```

## ARM19 运行时

不要再用本机的 Android 12 模拟器跑这个客户端。
当前已验证的运行时是 `kssma_arm19`：Android `4.4.2` / API 19 / `armeabi-v7a` classic ARM emulator。
这是这份 ARM-only 2013 APK 的最短可用目标，BlueStacks x86/Houdini 崩溃先不要当主线。

如果不用 `flow` 做玩法验收，手动实机测试前先跑快检：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health
```

快检只连接 `127.0.0.1:5583` 并读取 ABI、Android 版本和 boot 状态；它不会截图、
读 logcat、跑 dumpsys、改 hosts 或重启模拟器。正常热状态应在几秒内返回
`ok=true`。如果失败，再跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb
```

`repair-adb` 会区分健康 ARM19、detached ARM19、offline/unauthorized、只剩
Android 12/x86 等情况。只有 `detached-arm19` 会自动温重启 `kssma_arm19`，且不 wipe、
不重装 APK、不重新推资源。

常用诊断命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 configure
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-runtime
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-baseline
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-client-baseline
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 clean-install
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 preload-small
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 launch
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 observe -Observe Requests,Activity,Logcat
```

`run -DriveLogin` 仍存在，但只是 legacy debug plumbing。新玩法验收和新系统测试应新增
`flow` 场景，而不是复制旧登录脚本。场景编写规则见 `docs/flow-scenarios.md`。

说明：

- `preload-small` 只推 `download/rest`、`download/scenario`、`download/pack` 和少量必需文件，用来快速验证启动链；完整资源仍用 `preload-full` 单独处理。
- `preload-small` 也会推已证明需要的小文件：`save_version`、`master_*`、`adv_chara111`、`bgm_common1.ogg`。
- `ensure-baseline` 幂等检查 hosts、mount、display、audio 和 package；只有不符合基线才修复。
- `ensure-client-baseline` 检查唯一客户端 APK 和已安装 `librooneyj.so`。一致时不
  force-stop、不 push；不一致时安装 `work\client-baseline\KSSMA-Re-client-baseline.apk`。
- `ensure-exploration-baseline` 只是兼容别名；新流程使用 `ensure-client-baseline`。
- `launch` 只启动游戏，不隐式重复 hosts/mount；`run` 只执行一次 `ensure-baseline`。
- 如果游戏提示无法连接服务器，先检查 `work\kssma-server.ps1 status`，确认 `50005` 和 `10001` 都在监听。
- native-only 实验必须显式给 `patch-lib -ApkPath <explicit .so>`。脚本不会再自动选择
  `work` 里最新的 `*signed.apk`，因为旧 APK 可能携带错误的 `librooneyj.so`。
- `install-apk` 默认只安装唯一 client baseline；显式传入非 baseline APK 会被拒绝。
  背景、BGM、server XML、玩法协议值域改动不需要完整安装 APK。
- `install-apk` 使用内部安装，绕过 Android 4.4 外置 ASEC 安装不稳定的问题；如果 ADB 客户端超时但设备端安装已完成，helper 会验证已安装 `librooneyj.so` 后给出结论。
- `restart-runtime` 是破坏性命令，必须显式带 `-Force -Reason "..."`。除
  `repair-adb` 的 `detached-arm19` 自动温重启外，普通连接、baseline 或安装命令不会杀
  模拟器进程。
- 不要默认用 Frida 做运行时探针；它容易让 ARM19 ADB transport 掉到 offline。只有有明确 hook 假设时再单独使用，并在回到 ADB 测试前停掉。
- `-gpu on` 是当前默认；`-gpu off` 会产生误导性的 OpenGL ES 噪声。
- 音频是当前运行时基线的一部分；不要用 `-no-audio` 启动 ARM19，否则无法验证 BGM 和角色语音。
- BlueStacks 脚本还保留在 `work\bluestacks-nougat32.ps1`，但只作为排查对照，不再是默认运行时。

当前运行时已经能进入并验收主菜单，加载 `adv_chara111` 与 `bgm_common1.ogg`。`_Layout::event(...)` 的 ARM `0x98` 崩溃已通过 `work\build-animation-nullguard.py` 中的最小 native guard 绕过；后续会打开本地 `/connect/web/` 占位页，按需用 `work\kssma-runtime.ps1 observe -Observe Requests,Activity,Logcat,Screenshot` 采集 artifact。

已整理的逆向笔记见 `reverse-notes.md`。
