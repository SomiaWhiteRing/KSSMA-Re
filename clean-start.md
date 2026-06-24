# Clean Start

这是项目的新起点。目标不是抹掉已有成果，而是把已有成果当作证据保留，
然后从最小、原始、可验证的启动链重新推进。

## 一句话目标

让原始客户端相信本地服务器就是旧服务器，并按原本流程进入游戏。

## 保留的成果

- 原始 APK 和 140330 资源 dump 保留在 `base/`。
- Android 4.4.2/API19 ARM 是当前可靠运行时。
- 旧域名转本地、双端口 server、AES key、资源预载脚本都是有效成果。
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

不要再把角色大厅、脸图、mainbg 黑屏当作主线，除非当前 run 的 logcat 明确
显示缺失资源路径或纹理加载崩溃。

不要从被大改过的 APK 继续叠补丁。默认从干净 base APK 加最小已知补丁重建。

## 新主线

每次只推进下一条请求。

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

当前验收不要看画面是否完美，只看是否出现下一条请求或下一次场景迁移。

## 第一阶段验收

先把本地 server 启动为最小引导服务：

```powershell
$env:CHECK_INSPECTION_KEY='rBwj1MIAivVN222b'
$env:CONNECT_APP_KEY='rBwj1MIAivVN222b'
$env:LOGIN_RESPONSE='sample'
$env:PORTS='50005,10001'
node .\server\bootstrap-server.js
```

然后运行 ARM19 客户端。第一阶段成功标准：

- server 日志稳定出现 `/check_inspection`
- 随后出现 `/connect/app/notification/post_devicetoken` 或 `/connect/app/login`

如果只出现 `/check_inspection` 后弹网络重试，说明还卡在启动协议，不要处理资源。

## 每轮实验格式

每轮只允许一个假设：

```text
Frontier:
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
Hypothesis: check_inspection 响应缺少客户端必需 header 字段。
One variable changed: 只修改 CHECK_INSPECTION_OK_XML。
Observable: server 是否收到 post_devicetoken 或 login。
Result: 未收到。
Conclusion: 该字段不是推进条件。
Next: 静态追 check_inspection completion path。
```

## AI 任务模板

把下面这段发给新会话：

```text
请按 AGENTS.md 和 clean-start.md 执行。
本轮目标不是修画面，而是推进启动链的下一条请求。

当前只允许处理一个 frontier：
[写当前卡住的请求，例如 /check_inspection 后没有 post_devicetoken/login]

成功标准：
server 日志出现下一条请求，或 logcat/native 证据证明为什么没有下一条请求。

禁止：
- 不许跳过登录/主菜单原始流程
- 不许修 face/mainbg/大厅黑屏
- 不许换模拟器
- 不许大改 APK
- 不许连续试补丁超过 2 次没有新 observable

请先复述 frontier、假设、observable，再动任何文件。
```

