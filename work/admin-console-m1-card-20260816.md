# Admin console M1 evidence card — 2026-08-16

## Frontier

现有本地 server 没有可视化管理入口；玩家基础字段只能直接编辑 JSON。直接开放整个存档会绕过
持卡、卡组、探索进度和客户端 scene 的跨字段约束。

## Success

- server 提供无需第三方运行时依赖的 `/admin/` 页面；
- 页面可读系统和进度摘要，只写已验证的玩家基础字段；
- 写入经过白名单、值域和跨字段校验，并复用现有原子存档写入；
- 本机默认可写，局域网写入必须配置令牌；
- 原有 server 全量自检继续通过，浏览器实际渲染无横向溢出。

## Non-goal

不修改游戏协议 XML、native、资源、客户端基线或正式玩家数据；不开放探索进度、持卡实例、卡组
槽位和任意 JSON 编辑；不把单活动存档宣称为多用户系统；不尝试探索深层、战斗、妖精或奖励结算。

## Stop

如果需要猜测未恢复的客户端字段契约，或连续两个改动没有产生 API、自检或浏览器 observable，停止
实现并只记录缺失证据。

## Accepted path reused

正确路径是 `readPlayerSave(...) -> validated in-memory copy -> writeJsonFileAtomic(...)`。管理页面只在这一
路径外增加字段白名单和 HTTP 入口，避免另外实现一套存档格式。复杂玩法状态继续由现有 route/flow
路径拥有。

## Hypothesis and changed variable

假设：只开放现有 `default-save.json` 中已由主菜单、探索和扭蛋路径消费的标量字段，就能提供有用的
本地管理能力，同时不扩大协议推测范围。

唯一产品变量是增加独立 admin UI/API 层；玩法 endpoint、XML、native 和数据基线不变。

## Observable and checks

```powershell
node --check .\server\admin-ui.js
node --check .\server\bootstrap-server.js
node --check .\server\test-bootstrap-server.js
& "$env:USERPROFILE\miniconda3\Scripts\conda.exe" run --name KSSMA-Re node .\server\test-bootstrap-server.js
```

自检覆盖 `/admin` 重定向、CSP、状态读取、无令牌拒绝、非法 AP 零写入、合法原子写入、百分比重算、
敏感登录字段不出现在 API，以及全部既有启动/登录/主菜单/扭蛋/卡组/战斗骨架/探索断言。

浏览器以独立临时 server 端口 `50125` 打开 `/admin/`；DOM 包含全部表单、六个状态指标和四个复原
边界。在 `innerWidth=639` 时 `documentElement.scrollWidth=624`、`clientWidth=624`，无横向溢出。
临时检查只执行 GET，没有写入真实或临时玩家存档，检查后已停止 server。

## Observed result

- `bootstrap-server self-check passed`；
- 错误令牌返回 403，非法 AP 返回 400 且存档字节不变；
- 合法更新只改变白名单字段，返回状态不包含登录 ID、密码或管理令牌；
- 页面在桌面/窄窗口均可读，窄窗口自动切换为单栏；
- 独立 conda-forge 环境 `KSSMA-Re` 使用 Python 3.12，并安装 Pillow 供现有布局自检使用。

## Conclusion

M1 可接受为 server-only 管理入口。它解决玩家基础设定与系统状态可视化，不解决玩法协议或多用户
隔离。后续 admin M2 应先做存档快照/恢复、审计和只读诊断；复杂状态写入必须等待各自 flow/native
契约闭合。

## Next frontier

产品主线仍是已记录的扭蛋/卡组共同玩家数据与卡组保存阻塞。探索深层、战斗、妖精和奖励按
`docs/local-revival-roadmap.md` 分成独立流程边推进。
