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
- 不要切回 Android 12、x86、BlueStacks 或 Houdini，除非用户明确要求调查运行时。
- ARM19 默认应开启音频；不要用 `-no-audio` 启动，否则 BGM 和角色语音测试无效。
- 默认从干净 base APK 加最小已知补丁重建，不要从被大改过的 APK 继续叠补丁。
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
- BGM/角色语音的模拟器音频基线；音频只作为运行环境检查项，不属于当前主界面视觉差异 frontier

这些画面问题暂时不作为主线：

- 角色大厅黑屏
- face 图黑
- mainbg 黑

只有当 logcat 明确给出缺失资源路径、纹理加载崩溃或它阻塞下一条请求时，才处理。

## 工作循环

每个非平凡改动必须按这个顺序：

1. 说清当前 frontier。
2. 提出一个可证伪假设。
3. 定义最小 observable。
4. 只改变一个变量。
5. 跑最小检查。
6. 把结果写入 `reverse-notes.md`。

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
