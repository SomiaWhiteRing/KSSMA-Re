# 探索并行 Agent 协调记录

启动时间：2026-06-26

当前主 frontier：

```text
/connect/app/exploration/area OK
-> /connect/app/exploration/floor OK
-> _ExplorationArea::createFloorList() reached
-> floor_list not visible
```

## 运行规则

- 主线程暂不跑模拟器，不启动/停止 server，不改 APK。
- 子 Agent 本轮只做静态分析或写 card。
- 不允许盲改 XML 字段。
- 不允许重新打开主菜单视觉、BGM、face、mainbg、点角色台词底框问题。
- 任一子 Agent 如果需要 runtime 才能继续，必须写 handoff，不得自己启动 runtime。

## Agent 分工

| Agent | ID | 工作包 | 输出 | 成功条件 |
| --- | --- | --- | --- | --- |
| Mencius | `019f005f-5f75-7df2-948a-410d0c3471aa` | A: Floor List 解堵 | `work/exploration-floorlist-probe-card.md` | 给出区分 `floor_info_list count == 0` 与 `> 0` 的最小 probe |
| Leibniz | `019f005f-7511-7490-b17d-f57826e6d232` | C: Floor parser/model schema | `work/schema-cards/exploration-floor.md`，必要时 `work/value-domain-cards/exploration-floor.md` | 证明 parser/list push/model+0x58 链，或明确静态缺口 |
| Popper | `019f005f-915c-73c2-859b-0772e5b6c588` | D: Command -> Route mapping | `work/exploration-command-route-map.md` | 至少给出 `floor`、`foward`、`next_floor`、`back` 的置信等级 |
| Gibbs | `019f005f-a820-78c1-b839-8554763f0f79` | E: Explore response schema | `work/schema-cards/exploration-explore.md` | 给出最小无分支 `/exploration/explore` 响应草案或 nested parser 缺口 |
| Peirce | `019f005f-bdfd-7f41-ad66-e8c05c0a6cef` | H: Value domain/masterdata | `work/value-domain-cards/exploration-area.md`、`exploration-floor.md`、`exploration-explore.md` | 给出 area/floor/bg/bgm/boss/card/item 值域来源和风险 |

## 集成顺序

1. 先看 Mencius：决定下一次 runtime 是 count probe、item creation probe，还是 parser/init probe。
2. 再看 Leibniz：如果 count 为 0，用 schema card 指定唯一 XML/server 变量。
3. 同步合并 Peirce：只把值域当 value evidence，不当 schema proof。
4. Popper 与 Gibbs 用于 M1 之后，避免 floor list 修好后又卡在下一条 route。
5. 只有当 card 给出 one-variable runtime handoff，才进入 ARM19 实机验证。

## 超时处理

- 5 分钟无产出：继续等待，但不追加新任务。
- 10 分钟无产出：向所有 Agent 要求汇报 `current frontier`、`last observable`、
  `files changed`、`next smallest action`。
- 任一 Agent 汇报需要 runtime：立即停止该 Agent 的扩大探索，只接受 handoff card。
- 任一 Agent 改 server/APK/resource 或开始处理主菜单视觉：中断并关闭。

## 下一次 runtime 进入条件

必须同时满足：

- 有 card 指出唯一变量。
- 有明确 expected observable：count、item creation、route、scene、截图或 logcat 行。
- 有明确 artifact prefix。
- 有反向禁止项：不要重复 `floor id=1/2`，不要重复 state forcing patch，默认不用 Frida。

## 当前不做

- 不修 shop、battle、card、menu 等其它主菜单按钮。
- 不做 boss/fairy runtime。
- 不完整安装 APK。
- 不用 Frida 做默认探针。
- 不把 `id=1`、`id=2` 之类值域猜测再跑一遍。

## 2026-06-26 分流：count probe 前置稳定化

当前阻断：

```text
native count probe 已准备
-> 但 one-shot runtime 在 /connect/web/ notice 处理后可能按 Back 进入退出确认
-> 无法稳定证明 mainmenu
-> 因此不能可靠采集 0x341A34/0x341A36 SIGILL observable
```

| Agent | ID | 工作包 | 写入范围 | 成功条件 |
| --- | --- | --- | --- | --- |
| Curie | `019f0094-a1c5-7901-9857-343d535edb04` | 修 one-shot login/notice/mainmenu harness | `C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1`，必要时追加 `reverse-notes.md` | `-DriveLogin -DismissNoticeWebView` 不把主菜单误处理成退出确认，能产出 mainmenu proof |
| Tesla | `019f0094-b766-7843-8a4b-141ec160b795` | 收窄 runtime control plane 长尾 | `work/kssma-runtime-lib.ps1`、`work/kssma-runtime.ps1`、必要时 `work/android44-arm19.ps1` | fast-health、ensure-runtime、patch-lib post-verify 不再用慢操作或误判健康设备 |
| Lorentz | `019f0094-cd15-7280-a557-86bcdb7742f0` | 设计稳定 count-probe 进入路径 | 默认只写 `work/` handoff/card | 给出精确命令、artifact prefix、预期 observable 和失败分流，不依赖不稳定 notice handler |

### 集成规则

1. Curie 和 Tesla 的写入范围默认不重叠；如果实际冲突，先停下人工合并，不互相覆盖。
2. 不重跑 count probe，直到同时满足：
   - `fast-health` 返回 `ok=true`，serial 为 `127.0.0.1:5583`；
   - stock `librooneyj.so` 已确认，probe install 是单独一步；
   - `run -DriveLogin -DismissNoticeWebView` 或等价脚本能证明 RooneyJActivity 主菜单状态，而不是退出确认；
   - Lorentz 给出 one-variable runtime handoff。
3. 本轮禁止改探索 XML、server exploration 响应、APK 资源或主菜单视觉逻辑。
4. 如果两次 runtime harness 调整没有新 observable，停止继续补丁，回到静态入口设计。

### 本轮硬停止

- 不因 `emulator-5582 offline` 重启模拟器；只看 `127.0.0.1:5583`。
- 不把 `/connect/web/` 当协议失败；它是每日公告路径，只能在可见 WebView notice 时处理。
- 不把退出确认截图当主菜单证明。
- 不重新调查 BGM、face、mainbg、角色台词底框。
