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

先启动本地引导服务。当前 ARM 主线使用 `sample`，它能走到主菜单：

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

## 旧安卓运行时

不要再用本机的 Android 12 模拟器跑这个客户端。
当前已验证的运行时是 `kssma_arm19`：Android `4.4.2` / API 19 / `armeabi-v7a` classic ARM emulator。
这是这份 ARM-only 2013 APK 的最短可用目标，BlueStacks x86/Houdini 崩溃先不要当主线。

仓库里已经附了最短操作脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 configure
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 install -ApkPath .\work\million-cn-animationguard-signed.apk
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 hosts
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-small
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 run
```

说明：

- `preload-small` 只推 `download/rest`、`download/scenario`、`download/pack` 和少量必需文件，用来快速验证启动链；完整资源仍用 `preload-full` 单独处理。
- `preload-small` 也会推已证明需要的小文件：`save_version`、`master_*`、`adv_chara111`、`bgm_common1.ogg`。
- `hosts` 把模拟器里的 `game.ma.mobimon.com.tw` 指向 `10.0.2.2`；`run` 会自动执行一次，服务端需同时监听原服 WebView 端口 `10001`。
- `install` 使用内部安装，绕过 Android 4.4 外置 ASEC 安装不稳定的问题。
- `-gpu on` 是当前默认；`-gpu off` 会产生误导性的 OpenGL ES 噪声。
- BlueStacks 脚本还保留在 `work\bluestacks-nougat32.ps1`，但只作为排查对照，不再是默认运行时。

当前运行时已经能进入主菜单并加载 `adv_chara111` 与 `bgm_common1.ogg`。`_Layout::event(...)` 的 ARM `0x98` 崩溃已通过 `work\build-animation-nullguard.py` 中的最小 native guard 绕过；后续会打开本地 `/connect/web/` 占位页，日志和截图会保存到 `work\android44-arm19-last-run-*`。

已整理的逆向笔记见 `reverse-notes.md`。
