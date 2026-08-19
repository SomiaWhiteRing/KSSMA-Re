# 扩散性百万亚瑟王重建项目

## 项目启动方式

当前启动流程只在 Windows 上验收。游戏客户端是 2013 年的 ARM 版本，已验证的运行目标是
**Android 4.4.2（API 19）ARMv7 模拟器**。项目脚本将这套环境简称为 `ARM19`，Android
Virtual Device（AVD）名称为 `kssma_arm19`。

全新设备还需要 Node.js、Python 3、JDK（`keytool` 和 `jarsigner`）及
ADB/platform-tools。运行客户端时请使用上述 Android 4.4 ARM 环境。

### 1. 准备原始文件

从 [Internet Archive 的 gacha-archive](https://archive.org/details/gacha-archive) 下载以下两个文件，
将未解压的资源 ZIP 和 APK 放入仓库根目录的 `base` 文件夹：

```text
base/
├─ com.square_enix.million_cn-1.0.0.100.0712.M330.apk
└─ com.square_enix.million_cn-140330.zip
```

校验 SHA-256：

```text
4F6A854C49D1AF59BB5500828D2BDDA0767F4D6A9FCFA8D4D6E46EA9257C58A7  com.square_enix.million_cn-1.0.0.100.0712.M330.apk
D311C8FC3152BE328FA36638F2075F01B95A8AAB2DEA47F918DB3101F18D69F5  com.square_enix.million_cn-140330.zip
```

```powershell
Get-FileHash .\base\com.square_enix.million_cn-1.0.0.100.0712.M330.apk -Algorithm SHA256
Get-FileHash .\base\com.square_enix.million_cn-140330.zip -Algorithm SHA256
```

### 2. 安装 Android 4.4 ARM 模拟器

阅读 [Android SDK License](https://developer.android.com/studio/terms) 后执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\setup-android44-arm.ps1 -AcceptAndroidSdkLicense
```

脚本会直接从 Google 官方 Android 仓库下载固定版本的 classic emulator tools `25.2.5`
和 Android 4.4/API 19 ARMv7 system image revision `5`，校验归档大小、官方 SHA-1、固定
SHA-256 及关键解压文件后，安装到：

```text
%LOCALAPPDATA%\Android\Sdk-classic-arm
```

下载量约 445 MiB，解压后约 1.55 GiB。后续 `configure` 会创建名为 `kssma_arm19` 的
Android 4.4 ARM 虚拟设备、4 GiB SD 卡及必要配置。首次创建和启动会离线生成 1.5 GiB
userdata，ARM 模拟器冷启动可能需要约 4 分钟。

### 3. 首次部署

在仓库根目录执行：

```powershell
python .\work\prepare-assets.py
python .\work\build-client-baseline.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 configure
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-runtime
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-client-baseline
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 preload-full
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-baseline
```

`prepare-assets.py` 会校验两个下载文件并准备客户端所需资源。`build-client-baseline.py`
会生成可安装的客户端；缺少 Android debug keystore 时会通过 JDK 的 `keytool` 创建。
必须先执行 `ensure-client-baseline`，再执行 `preload-full`；顺序调换会导致模拟器空间不足，
客户端无法安装。

脚本使用 `kssma_arm19`、`emulator-5556` / `127.0.0.1:5557`；其他 Android 设备可以保持在线。
请确保 `5556` 和 `5557` 端口可用，否则脚本会停止并输出诊断。

### 4. 日常启动

1. 双击 `start-runtime.cmd`，等待 Android 4.4 ARM 模拟器启动并完成基线检查。
2. 双击 `start-server.cmd`，保持服务器窗口运行。
3. 在模拟器中打开 KSSMA；结束后双击 `stop.cmd` 停止本地服务器。

### 5. 登录

首次进入时选择“继续游戏”，服务器选择 `Local Dev World`，然后使用以下账号登录：

```text
手机号：13800138000
密码：testpass1
```

遇到问题先执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-preflight.ps1
```

## 项目说明

该项目的最终目的是重建已经停服的手游《扩散性百万亚瑟王》，使其能够使用本地搭建的服务器进行游戏。项目的开发和维护由社区志愿者完成，旨在让玩家能够继续享受这款经典游戏。

该项目目前正处于初创阶段，其结构和内容随时且快速的可能发生变化。

如果当前调试已经绕进黑屏、资源、APK 大改等问题，先从 `clean-start.md` 重新
建立主线。启动阶段按下一条服务器请求推进；进入主菜单后的玩法阶段按原始客户端
流程边推进：用户动作、请求/响应、页面状态、截图和下一次点击目标要一起验收。

## 项目结构

- `base/`：《扩散性百万亚瑟王》的基础数据和资源。
- `work/`：从客户端样本拆出的反编译与资源产物。
- `server/`：本地引导/协议验证用的最小服务端。
- `server/data/game/`：临时 JSON 游戏资料，例如主菜单资料、探索 Area/楼层/BGM/背景。
- `server/data/player/`：临时 JSON 玩家资料，例如本地默认探索进度。
- `server/data/server/`：临时 JSON 服务端资料，例如本地世界列表、masterdata 路由映射。

目前这些“数据库”先用 JSON 文件承载。`server/data/player/default-save.json` 是模板，
手动游玩会写入被 git 忽略的 `server/data/player/local-save.json`。flow 验收会改用
artifact 目录里的临时 `player-save.json`，避免自动测试污染真实游玩进度。静态游戏资料
不要重新写死进 `server/bootstrap-server.js`。

`server/data/**/*.json` 是运行数据库，不是考古笔记。里面只放当前采用的唯一游戏基线；
来源、强弱证据、候选值、推断过程和 wiki 链接写进 `work/*-card-*.md`、
`work/recovered-data/` 或 `docs/reverse-archive/`。server 自检会拒绝把这些文档字段重新
混进正式数据。

## 直接游玩

1. 双击 `start-runtime.cmd` 启动 ARM19 模拟器并准备 hosts、显示、存档挂载、音频和客户端基线。
2. 双击 `start-server.cmd` 启动本地服务器，然后在模拟器里打开游戏。
3. 玩完双击 `stop.cmd` 关闭本地服务器；模拟器可以手动关，也可以留着下次更快启动。

`play.cmd` 现在只保留为说明页。不要再把它当作一键启动入口；之前的一键入口把
模拟器、server、登录和验收 flow 绑在一起，遇到已有非 ARM19 设备时会报
`wrong-runtime-only`。

## 本地管理后台

启动 server 后，在服务端电脑浏览器打开：

```text
http://127.0.0.1:50005/admin/
```

首版后台使用接近原作王城界面的本地样式，可以查看运行状态、探索/卡牌摘要，并修改已经被
客户端协议验证过的玩家字段：名称、阵营、等级/经验、AP/BC、金币、MC、友情点、扭蛋券和
持卡上限。账号区可以手动创建登录账号、为每个账号建立独立存档，并切换后台当前编辑的账号；
客户端注册保持关闭，密码仅保存 scrypt 哈希且不会在后台响应或服务端日志中回显。“探索妖精”区可单独
控制启用状态、遭遇概率、等级、最大 HP、攻击力、存活时限、胜利金币/经验奖励、每个奖励位的掉卡概率、
加权掉落卡池、每位贡献者奖励位数和击杀者额外奖励位数；数值在新妖精生成时快照，不会中途改写已在战斗的实例。
“扭蛋产品与卡池”区覆盖友情点单抽、MC 单抽、扭蛋券单抽和 MC 11 连，可分别调整价格与加权卡池。
卡池每行使用 `master_card_id:权重`，后台会显示归一化百分比并拒绝重复、空池或不存在于 480 张恢复主表的卡牌。
价格/卡池保存后新请求立即生效，无需重启服务端；产品 ID、货币类型和抽取张数保持协议固定，不在后台开放重映射。
探索进度、持卡实例及卡组槽位暂时保持只读，避免生成客户端无法消费的不一致存档。状态区会只读显示
当前账号可见的存活妖精数、待领奖励数以及“当前卡组 COST / 当前 BC”。

账号登录响应会签发账号绑定的 `kssma_session` Cookie。静态恢复证明原客户端所有玩法请求共用同一个
Java `DefaultHttpClient` 与 `CookieStore`，因此同一客户端会在后续 `/connect/app/*` 请求中自动回传该
Cookie；服务端按请求解析账号和独立存档，不再依赖来源 IP 或“最近一次登录”的全局账号。两客户端并发
HTTP 自检已经覆盖不同主界面、独立探索/AP 落盘和非法 Cookie 拒绝。未携带 Cookie 的旧调试请求仍保留
最近登录账号兼容；两台真实客户端的最终可见协战验收仍需在后台创建第二账号后执行。

默认只有服务端本机可以写入。从局域网其他设备管理时，启动 server 前设置管理令牌，并在
页面底部输入同一令牌：

```powershell
$env:KSSMA_ADMIN_TOKEN='请换成足够长的随机值'
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 restart
```

然后用服务端的局域网 IP 打开 `http://<服务端IP>:50005/admin/`。不要把 `50005`、`10001`
或后台页面转发到公网。

## Python / conda 环境

日常服务端不依赖 Python；资源准备和布局自检需要 Python/Pillow。建议使用仓库提供的独立
conda 环境，避免污染系统 Python：

```powershell
conda env create -f .\environment.yml
conda run -n KSSMA-Re node .\server\test-bootstrap-server.js
```

环境只使用 `conda-forge`，名称固定为 `KSSMA-Re`。

如果双击入口没有窗口或出现乱码，先在项目目录运行入口自检。它只验证 Windows 能正确解析
`.cmd`，不会启动模拟器：

```cmd
cmd /c start-runtime.cmd self-test
cmd /c start-server.cmd self-test
cmd /c play.cmd self-test
cmd /c stop.cmd self-test
cmd /c install-mumu-a12.cmd self-test
```

当前可体验内容：主菜单、角色点击互动/BGM/语音、主按钮入口、Menu 页入口、底部卡组/好友入口、
探索秘境列表、楼层列表、进入关卡、关卡前进、AP 消耗、进度保存、按顺序开放下一区域、
完成演出、AP 不足页、普通升级与 AP/BC 分配、返回秘境列表，以及友情点/付费单抽、结果页返回与
付费再抽、持卡落盘、友情点/MC 消耗和可见卡组编辑入口。扭蛋服务端现覆盖友情点单抽、MC 单抽、
扭蛋券单抽和 MC 11 连：每类拥有独立价格与加权卡池，11 连会一次性预检货币/持卡空间并原子写入 11 张卡；
友情点与 MC 单抽的既有 ARM19 可见流程保持已验收，新增券抽和 11 连入口/多卡结果仍需客户端 flow 验收。
普通妖精遭遇与原生 VS/战斗/结果演出已验收；
动态伤害、金币/经验结算及原子存档也已由 ARM19 实机 `fairy-battle-smoke` 验收。战斗敌方现按
`master_boss_id` 显示具体妖精贴图，普通妖精死亡后也不会再误播旧的“妖精出现”事件。奖励展示与返回点击
尚未完整验收。妖精战斗现在按当前卡组各卡牌 COST 总和原子扣除 BC，默认卡组实机已验证 `25 -> 15`；
BC 不足会在服务端拒绝且不改写妖精/奖励/胜负，但客户端原有的无 BC 提示入口仍需恢复。罕见妖精、
因子碎片掉落仍未实现。服务端现已实现单账号最多一只存活妖精、失败后继续挂载并抑制新遭遇、
所有实际攻击者的贡献记录、好友顺序协战、击杀后按奖励位独立判定的掉卡概率、加权卡池、击杀额外奖励位，
以及奖励箱的幂等领取。没有命中掉率的奖励位不会创建空奖励；同一贡献者命中的相同卡牌会合并为一条奖励箱通知。
`menu/fairyselect -> exploration/fairy_floor` 和奖励箱 XML 使用已静态闭合的原生 parser 结构；这些好友/领奖
页面还需单独做客户端 flow 可见验收，不能只凭服务端 200 宣布完成。证据见
`work/fairy-battle-bc-card-20260819.md` 和 `work/fairy-shared-raid-account-path-card-20260819.md`。

卡组入口 D1、队长模式 D2 和单卡内存编辑 D4 已验收：`/roundtable/edit move=1` 进入 scene `83200` 的 DeckScene，点击
队长控件会在 server quiet 状态下进入本地 `change_mode_leader_select`；scene `10100` 只是圆桌查看页。
D3 native 路径已闭合：`(127,360)` 进入选卡、`(226,247)` 选择唯一候选、`(1144,360)` 显式返回，
全程停留 scene `83200`；D4 artifact 证明第二槽出现且存档不变，D5 已捕获精确 `C/lr` 请求。显式
`save_deck_card/result=0` 的 D5.5 候选响应未使客户端离开 DeckScene：header 的 `next_scene=83200` 会
push 一个不识别 `save_deck_card` 的新 DeckScene。`next_scene == 0` 到当前 model 的静态交付链现已闭合，
但首个 D5.6 实机回合在登录前因 ARM19 `restart-boot-timeout` 停止，未产生任何玩法 route 或产品证据；
实验响应已撤回，当前仍为 D5 capture-only。修正版 C2 sampler 的 13 项 self-check 通过；单次温启动测得
`tBoot=102.733s`，restart helper 在 `104.449s` 成功，连续健康样本、唯一 ARM19 进程组和两个端口 owner
均一致。因此保留 120 秒等待，不改 runtime；下一轮只恢复一次 D5.6 无 `next_scene` response-only 实验，
不落盘。该唯一重放的精确响应在 165ms 后触发了 `/connect/app/mainmenu`，违反计划要求的三秒 route
quiet；artifact save 仍逐字节不变。实验已撤回，当前保持 D5 capture-only 并冻结 D6。扭蛋失败契约 G1
仍因 generic error model 到可见 dialog scene 的 push 边未闭合；服务端已经在任何写入前拒绝余额不足、
卡位不足和非法产品，但尚不能声称原客户端会显示正确失败弹窗。

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

探索普通行走冒烟：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-walk-smoke
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

## MuMu Android 12 安装

当前 MuMu 12（ADB `127.0.0.1:7555`）已支持独立的一键安装入口。先启动 MuMu 并确认其
ADB 调试端口为 `7555`，然后在仓库根目录双击 `install-mumu-a12.cmd`，或运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 deploy -StartServer -Launch
```

该入口会严格检查 Android 12/API 31-32、32 位 ARM 翻译层和 `10.0.2.2` 宿主网关，随后完成：

- 从干净 base APK 重建唯一客户端 baseline（缺少产物时自动执行，传 `-Rebuild` 可强制重建）；
- 安装 APK、授予旧客户端所需权限，并校验设备端 `librooneyj.so` SHA-256；
- 合并而非覆盖 `/system/etc/hosts`，把 `game.ma.mobimon.com.tw` 和
  `dlc.game-CBT.ma.sdo.com` 指向 `10.0.2.2`；
- 将完整静态资源包安装到应用外部存储，并逐文件校验；已有
  `appdata/save_appdata` 玩家存档不会进入资源包，也不会被删除；
- 在每次控制器启动客户端前停止旧进程，补回并校验会被客户端消费的精确
  `database/master_card` 卡表种子；
- 可选启动双端口本地服务、拉起客户端，并在 10 秒存活检查后保存截图。

第一次准备资源和 APK，或需要明确重建全部安装产物时运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 deploy -Rebuild -StartServer -Launch
```

单项诊断与修复入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 self-check
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 install-client
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 ensure-hosts
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 install-resources
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 repair-master-card
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 launch -StartServer
```

`launch`、`install-client` 和 MuMu flow 都会自动执行卡表补种；`repair-master-card` 用于希望随后由玩家
手动点图标启动的情况，它会先停止游戏并只准备卡表，不会替玩家点击。直接从 MuMu 桌面启动、但没有先走
上述任一入口时，控制器无法介入第三方 Activity 启动，因此不保证补种。

MuMu 也有隔离的兼容性 flow 入口，可复用现有场景做定向调查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 flow -Scenario exploration-walk-smoke -Tag a12-check
```

它不会放宽 ARM19 门禁；会独占本地 server、使用 artifact 内玩家存档，并只读校验 MuMu 保持物理
`1440x2560` / density `360`、没有任何 `wm` override。自动点击仅在主机侧把既有 `1280x720`
逻辑坐标换算为原生横屏 `2560x1440` 坐标；截图同时保留 `.native.png` 原图和供既有判定器使用的
`1280x720` 对照副本。脚本不会修改模拟器分辨率或 density。

hosts 修复会在设备上保留原始备份 `/system/etc/hosts.kssma-re-original`。只有需要撤销旧域名映射时才运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 restore-hosts
```

生成的约 499 MiB TAR、校验表和 manifest 位于 `work\mumu-a12-package\`，均可由脚本重新生成，
无需手工解包或逐文件 `adb push`。MuMu Android 12 曾在临时显示 override 下通过普通探索行走；
该历史结果不能作为原生分辨率验收。原生显示下的路由/点击适配已能进入抽卡和妖精战斗请求，
但 A12 尚不能替代 ARM19。妖精事件的 `adv_chara0` 已由精确 `master_card` 冷启动补种修复，真人验收
能够完成战斗和结算；该补种现已固化到安装、启动与 MuMu flow gate。扭蛋结算的
`thumbnail_chara_0` 需要在新启动基线下重新验收，此前约 269 秒的扭蛋选择页 reward-box 路径崩溃也仍待
复核。完整证据和晋级条件见
`work/mumu-a12-flow-qualification-card-20260818.md`。

## ARM19 运行时

默认自动玩法验收运行时仍是 `kssma_arm19`：Android `4.4.2` / API 19 / `armeabi-v7a`
classic ARM emulator。这是这份 ARM-only 2013 APK 当前证据最完整的目标；不要因为 MuMu
Android 12 已可安装，就放宽或复用 ARM19 的 serial、ABI、坐标和 flow 门禁。

如果不用 `flow` 做玩法验收，手动实机测试前先跑快检：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health
```

快检只检查 `emulator-5556` 并读取 ABI、Android 版本和 boot 状态；它不会截图、
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
