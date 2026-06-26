# KSSMA-Re 代理规则

这个仓库是停服手游《扩散性百万亚瑟王》的离线复原项目。把它当作协议考古，
不要当作普通功能开发。

## 开工前必须读

每次修改前，按顺序读取：

1. `readme.md`
2. `clean-start.md`
3. `reverse-notes.md`
4. `server/bootstrap-server.js`
5. `server/test-bootstrap-server.js`

不要重新探索已经记录过的事实。如果笔记过期，用新证据更新笔记。

如果任务涉及启动模拟器、登录测试、采集 logcat、检查 server 请求链，优先使用
个人 skill：`kssma-re-runtime`。

## 固定基线

- 默认只使用 `reverse-notes.md` 记录的 Android 4.4.2/API19 ARM 运行时。
- 运行时控制入口是 `work/kssma-runtime.ps1`；`work/android44-arm19.ps1` 只是旧命令兼容
  shim。不要在两个脚本里维护两套 ADB/serial/hosts/mount 逻辑。
- ARM19 主 serial 固定为 `127.0.0.1:5583`。`emulator-5582` 只作为兼容别名和诊断信息；
  `emulator-5582 offline` 与 `127.0.0.1:5583 device` 并存时不算失败。
- 实机测试前必须先跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health
```

  `fast-health` 只允许做 `adb connect 127.0.0.1:5583` 和三个 `getprop`：
  `ro.product.cpu.abi`、`ro.build.version.release`、`sys.boot_completed`。禁止把 `wm`、
  `dumpsys`、`logcat`、`screencap`、`df` 放进连接健康检查。
- 只有 `fast-health` 明确失败才跑 `repair-adb`；只有 `repair-adb` 也失败并给出
  `restartAllowed=true`，才允许考虑 `restart-runtime`。`restart-runtime` 必须显式带
  `-Force -Reason "..."`，普通 start/connect/repair 不得杀模拟器。
- 不要切回 Android 12、x86、BlueStacks 或 Houdini，除非用户明确要求调查运行时。
- ARM19 默认应开启音频；不要用 `-no-audio` 启动，否则 BGM 和角色语音测试无效。
- 默认从干净 base APK 加最小已知补丁重建，不要从被大改过的 APK 继续叠补丁。
- native-only 改动默认用 `work/kssma-runtime.ps1 patch-lib -ApkPath <apk-or-so>` 直接替换
  已安装包里的 `librooneyj.so`。只有 Java/resources/manifest/签名/包结构变化时才完整
  `install-apk`。
- 完整安装前先跑 `work/kssma-runtime.ps1 clean-install`，并看 `status`/`diagnose` 里的
  `/data` 空间；
  如果 `adb install` 超时，不要立刻重试，先看 helper 对已安装 lib/hash 和 install log 的诊断。
- Frida 不是默认运行时探针；它可能让 ARM19 ADB transport 变成 offline。除非有明确 hook
  假设，否则不要为了“看看”启动 Frida。
- 已知 key：
  - `k1`: `A1dPUcrvur2CRQyl`
  - `k2`: `rBwj1MIAivVN222b`
- 本地 server 通常需要同时监听 `50005` 和 `10001`：

```powershell
$env:CHECK_INSPECTION_KEY='rBwj1MIAivVN222b'
$env:CONNECT_APP_KEY='rBwj1MIAivVN222b'
$env:LOGIN_RESPONSE='sample'
$env:PORTS='50005,10001'
node .\server\bootstrap-server.js
```

## 当前主线

按 `clean-start.md` 执行。项目正在保留已有证据的前提下，重新从原始客户端流程
建立主线。

主菜单视觉还原已阶段完成：当前 `sample` 路径能进入可见主菜单，背景、初始角色
脸图、主菜单信息框、BGM/角色语音、点角色后的表情变化与同步台词都已对照关服前
录像验收。录像确认点角色台词本来就没有底色/对话框背景；不要再把这点当作缺陷。

优先重新打通启动请求链：

```text
world_list.php
-> add_user.php
-> check_inspection
-> connect/app/notification/post_devicetoken
-> connect/app/login
-> masterdata/*/update
-> mainmenu/update
```

如果一次运行只到 `/check_inspection`，随后出现网络重试弹窗，当前 frontier 是
启动协议。不要处理主界面、face、mainbg 或大厅黑屏。

## 已排除或非主线问题

除非有新证据，不要重测这些方向：

- ARM-only APK 运行时目标
- `k1` / `k2`
- 缺少 `save/download/rest`
- 缺少 `adv_chara111`
- 缺少 `bgm_common1.ogg`
- `_Layout::event(...)` 跳到 `0x98`
- 原服 `/connect/web/` 弹窗陷阱
- dirty apktool 资源继承
- BGM/角色语音的模拟器音频基线；音频只作为运行环境检查项
- 主菜单视觉差异；当前背景、初始脸图、信息框、点击表情/台词已经阶段验收

这些画面问题已从主线移除，除非出现新的资源缺失、纹理崩溃或回归截图：

- 角色大厅黑屏
- face 图黑
- mainbg 黑
- 点角色台词缺少底色/对话框背景

只有当 logcat 明确给出缺失资源路径、纹理加载崩溃或它阻塞下一条请求时，才处理。

## 工作循环

每个非平凡改动必须按这个顺序：

1. 说清当前 frontier。
2. 提出一个可证伪假设。
3. 定义最小 observable。
4. 只改变一个变量。
5. 跑最小检查。
6. 把结果写入 `reverse-notes.md`。

## 失败止损硬约束

不要接受“继续直到跑通”作为可执行任务。遇到这种目标，必须先把它切成一个
不超过 90 分钟的可交付回合，并写清：

- Frontier：本轮唯一卡点。
- Success：本轮成功标准。
- Non-goal：本轮明确不碰什么。
- Stop：触发停止的条件。

每个回合必须交付至少一个可审计产物：

- 已验证修复；
- 可复现实验 artifact；
- 写入 `reverse-notes.md` 的结论；
- 明确废弃的假设或坏探针；
- 带最小自检的脚本。

以下情况必须立刻停下并写账，不准继续补丁循环：

- 连续两个补丁没有产生新的 route、logcat、PC、截图状态或 activity observable。
- 任一 native 探针被证明自身有错；必须先写入“坏探针记录”，不得基于它继续推理。
- 单次实机回合超过 20 分钟仍没有核心 observable；先收束 runtime 链路，不继续玩法逻辑。
- ADB/模拟器/server 生命周期消耗超过 15 分钟；本轮改为运行时问题，不继续 APK/server 逻辑。
- 已经得到有效 observable，但还没有写入 `reverse-notes.md`；不得开始下一轮补丁。

native 探针上实机前必须先过静态验收门槛：

- patch 地址原始 bytes 已用脚本 `require(...)` 校验；
- code cave 已校验不覆盖非零字节；
- 反汇编确认所有 replay/branch 回到正确地址；
- trap PC map 写清每个 PC 的含义；
- 明确写出哪些 PC 是有效证据，哪些只是坏探针/时序证据；
- `patch-lib` 后必须校验 installed SHA-256 与 source SHA-256 一致。

如果上述任一项缺失，不得安装到实机。实机 logcat 出现 trap 但 installed hash 不匹配时，
该 run 无效，不能写成产品行为证据。

探索状态机当前额外约束：

- 不要把 `0x00342108` 当成无条件 floor-only 锚点；它属于 `_ExplorationArea::preUpdate`
  的状态流，必须结合请求链、flag gate 或更深的 floor-list/vector 证据使用。
- 不要把 successful-return-only `getSelected` 探针当成“未进入分支”的证明；它只能证明
  已成功选中时的分支，不能证明负返回或未进入。
- 不要继续 server `floor_info` 字段扫值、found_item/cost/boss 猜测、XML-only 修复、
  `+0x84` 单点视觉修复，除非先有新的 native observable 指向这些方向。

好的 observable：

- 下一条 HTTP route
- 解密后的请求或响应
- logcat 行
- native symbol / address / call path
- scene id
- 截图证明 UI 迁移
- top activity 仍然存活

坏的 observable：

- “看起来更好了”
- “也许还缺 XML”
- “换个模拟器试试”
- 没有缺失文件日志却继续扩大资源预载

## 代码规则

- 优先删除或收窄，不要加抽象。
- 没有必要就不要新增依赖。
- 只加当前假设需要的 endpoint、字段或 patch。
- 有意简化必须写 `ponytail:` 注释，并说明上限和升级路径。
- server 响应保持最小，直到客户端证明某个字段必要。
- 至少两个 route 需要同一套真实逻辑时，才考虑抽象。

## 检查

server-only 改动运行：

```powershell
node .\server\test-bootstrap-server.js
```

客户端或运行时改动必须留下一个可复现检查：

- 精确 PowerShell 命令
- 期望请求、日志或截图
- `work/` 下的 artifact 路径

不要因为 Node self-check 通过就宣布客户端行为修好了。目标是客户端证明有进展。

## 笔记纪律

每次有意义实验都往 `reverse-notes.md` 追加简短证据：

- hypothesis
- command 或 patch
- observed result
- conclusion
- next frontier

失败实验也要记录。阻止下一位代理重复弯路就是进展。
