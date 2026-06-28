# Clean Start

这是项目的新起点。目标不是抹掉已有成果，而是把已有成果当作证据保留，
然后沿原始客户端流程推进。启动阶段按请求链推进；进入主菜单后的玩法阶段按
“流程边”推进，不再把所有问题都压成下一条 HTTP 请求。

## 一句话目标

让原始客户端相信本地服务器就是旧服务器，并按原本流程进入游戏。

## 保留的成果

- 原始 APK 和 140330 资源 dump 保留在 `base/`。
- 唯一可安装客户端基线是 `work/client-baseline/KSSMA-Re-client-baseline.apk`，manifest 是
  `work/client-baseline/client-baseline.json`。普通流程不要安装旧 APK。
- Android 4.4.2/API19 ARM 是当前可靠运行时。
- 旧域名转本地、双端口 server、AES key、资源预载脚本都是有效成果。
- `work/kssma-runtime.ps1 flow` 是玩法实机验收的默认入口；它负责 server、runtime gate、
  baseline、登录、route 等待、关键截图和 artifact。
- 主菜单视觉还原已阶段完成：背景、初始角色脸图、信息框、BGM/角色语音、点角色
  表情变化与同步台词已对照关服前录像验收；点角色台词原版就没有底色/对话框背景。
- 已知 key：
  - `k1`: `A1dPUcrvur2CRQyl`
  - `k2`: `rBwj1MIAivVN222b`
- `server/bootstrap-server.js` 是协议验证用的最小 server。
- `reverse-notes.md` 是证据账本，不是待办列表。

## 冻结的弯路

不要继续删除或跳过这些原始流程：

- 进入游戏
- 登录
- `/check_inspection`
- `/connect/app/login`
- 主菜单 scene

不要再把角色大厅、脸图、mainbg 黑屏、点角色台词底框当作主线，除非当前 run 的
logcat 明确显示缺失资源路径、纹理加载崩溃，或截图证明相对当前基线发生回归。

不要从被大改过的 APK 继续叠补丁。默认从干净 base APK 加最小已知补丁重建唯一
client baseline；旧 APK 只能作为归档证据，不是运行入口。

## 新主线

启动阶段每次只推进下一条请求。

```text
world_list.php
-> add_user.php
-> check_inspection
-> connect/app/notification/post_devicetoken
-> connect/app/login
-> masterdata/*/update
-> mainmenu/update
-> 主菜单可见
-> 一个玩法入口
-> 一个完整玩法闭环
```

主菜单画面已完成第一轮验收。玩法阶段的推进单位改为一条流程边：

```text
用户动作 -> 请求/响应 -> 客户端状态切换 -> 可见 UI 迁移 -> 下一次点击目标/下一条 route
```

HTTP 200 不是玩法成功标准。只有当请求顺序、截图/scene、下一次点击目标一起证明
客户端站到了正确层级，才算该流程边打通。

## 默认验收

玩法验收默认跑一个 flow 场景，而不是手动启动 server、逐步截图或 OCR：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-smoke
```

成功或失败都先看本次 artifact 的 `summary.json`、`events.jsonl` 和 `requests.jsonl`。
截图只作为关键里程碑和失败复核，不再作为每一步的主判断。

新增玩法系统时，先新增或扩展 flow scenario，复用已存在的 server 管理、runtime gate、
登录到主菜单、route wait 和 artifact 收集。不要为每个系统复制一套登录/ADB/server 脚本。

启动链低层调试仍可手动启动 `bootstrap-server.js`，但那是 debug 路径，不是玩法验收默认路径。

## 每轮实验格式

每轮只允许一个假设：

```text
Frontier:
Known-good path:
Hypothesis:
One variable changed:
Observable:
Result:
Conclusion:
Next:
```

例子：

```text
Frontier: /check_inspection 后没有下一条请求。
Known-good path: 无；这是启动链第一段。
Hypothesis: check_inspection 响应缺少客户端必需 header 字段。
One variable changed: 只修改 CHECK_INSPECTION_OK_XML。
Observable: server 是否收到 post_devicetoken 或 login。
Result: 未收到。
Conclusion: 该字段不是推进条件。
Next: 静态追 check_inspection completion path。
```

玩法阶段例子：

```text
Frontier: 秘境列表选择区域 0 后没有进入楼层列表。
Known-good path: 楼层数据已到且楼层列表 UI 曾被正确激活；下一次点击不应重复 /floor。
Hypothesis: 客户端仍站在秘境列表层级，不是 floor XML 字段缺失。
One variable changed: 只复用已验收的楼层列表激活路径。
Observable: /area -> /floor 后 flow 截图显示楼层列表；再点楼层发 /get_floor 而不是重复 /floor。
Result: ...
Conclusion: ...
Next: ...
```

如果存在已验收正确路径能产生目标画面、状态或下一条 route，先写 path card，静态恢复
入口函数、route id、参数来源和回调/scene 路径，再考虑复用完整路径。不要先手搓一个
behavior、flag、列表字段或绘制标志。

## AI 任务模板

把下面这段发给新会话：

```text
请按 AGENTS.md 和 clean-start.md 执行。
本轮目标不是凑画面，而是推进一个原始客户端流程边。
默认使用 `work/kssma-runtime.ps1 flow -Scenario <场景名>` 验收；如果没有现成场景，
本轮优先新增一个复用登录到主菜单阶段的 flow scenario。

当前只允许处理一个 frontier：
[写当前卡住的流程边，例如“秘境列表 -> 楼层列表”或“楼层列表 -> 返回秘境列表”]

已验收正确路径：
[如果有，写出能产生目标 UI/route 的正确路径；如果没有，写“无”]

成功标准：
请求顺序、截图/scene、下一次点击目标或 native/logcat 证据证明该流程边推进。

禁止：
- 不许跳过登录/主菜单原始流程
- 不许重新修已验收的 face/mainbg/大厅黑屏/点角色台词底框，除非有新的缺失资源、
  崩溃或回归截图证据
- 不许把 HTTP 200 当成玩法完成
- 不许在存在正确路径可复用时，优先猜 XML 字段、behavior、flag、列表内部状态或绘制标志
- 不许换模拟器
- 不许大改 APK
- 不许连续试补丁超过 2 次没有新 observable

请先复述 frontier、已验收正确路径、假设、observable，再动任何文件。
```
