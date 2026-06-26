# 探索功能静态资源路线图

本文档的目的不是一次性修好探索，而是把探索拆成可以并行推进的证据链。
每个 Agent 只负责一个关口，产出可复用的 schema、route、value-domain 或 runtime card。

## 当前结论

当前探索主线已经越过“服务器是否能连通”和“探索按钮是否能请求”的阶段。

已证事实：

- `/connect/app/exploration/area` 已返回 encrypted 200，并能进入 `Local Area` 区域地图。
- `/connect/app/exploration/floor` 已返回 encrypted 200，客户端能解密，且已经自然到达 `_ExplorationArea::createFloorList()` 调用点。
- 当前可见问题是：`createFloorList()` 被调用后没有出现可见 `floor_list`。
- 继续盲改 `<floor_info>` 字段没有意义。下一步必须证明 `createFloorList()` 看到的 floor vector 是空，还是 item 被构造后未显示。

当前 frontier：

```text
exploration/area OK
-> exploration/floor OK
-> _ExplorationArea::createFloorList() reached
-> floor_list not visible
```

## 静态资源拓扑

探索至少分成四个资源层，不应该让一个 Agent 串行吞完整个系统。

| 层级 | 主要资源 | 模型 | 关键控件/行为 | 当前用途 |
| --- | --- | --- | --- | --- |
| 入口/选区 | `layout_exploration_area.xml` | `exploration_model`, `scene` | `area_map`, `area_list`, `floor_list`, `placeview`, behavior `get_floor`, `floor_list_active*` | 选择秘境区域和楼层 |
| 行走主场景 | `layout_exploration_main.xml` | `exp_model`, `battle_model` | `bg_front`, `area_name`, `treasure`, `other_player`, `prize`, `floor_clear`, `forward`, `next_floor` | 进入楼层后探索、前进、奖励、下一层 |
| 普通 boss | `layout_exploration_boss.xml` | `exp_model`, `battle_model` | `exploration_fairy`, `battle`, `bcCheck`, `boss_lose`, `reward` | 楼层 boss/战斗准备/奖励 |
| fairy/rare fairy | `layout_exploration_fairy.xml` | `exp_model`, `fairy_model`, `battle_model` | `fairyHistory`, `rare_fairy_encount`, `fairy_lose`, `levelCheckFairy` | 妖精遭遇、妖精战斗前后 |

关键含义：

- `layout_exploration_area.xml` 只证明“区域/楼层选择”所需字段。
- `layout_exploration_main.xml` 才是探索行走响应的主要消费者。
- boss/fairy 不是 floor list 的前置条件，可以先静态拆 schema，但不要阻塞 floor list 修复。

## 路由图

按证据等级分三类：

| 等级 | route/command | 证据 | 下一步 |
| --- | --- | --- | --- |
| 已实机确认 | `/connect/app/exploration/area` | server log、截图、`EXPLORATION_AREA_XML` | 保持最小实现 |
| 已实机确认 | `/connect/app/exploration/floor` | server log、解密请求 `area_id=0`、到达 `createFloorList()` | 证明 vector/item/visibility |
| 静态强相关 | `command="foward"`, `command="foward2"` -> `exploration/explore` | `layout_exploration_main.xml` + `_ExplorationModel::update` 字符串 `exploration/explore` | 恢复进入楼层后再实机点 |
| 静态强相关 | `command="next_floor"` | `layout_exploration_main.xml` | 确认映射到 `floor`、`get_floor` 或 `explore` |
| 静态强相关 | `command="battle"`, `bcCheck`, `bcCheck2` | boss/fairy layout | 单独做 boss/fairy route mapping |
| 待定位 | `exploration/get_floor` | `reverse-notes.md` route 字符串记录 | 确认触发点：楼层点击还是 floor clear |
| 待定位 | `fairyHistory`, `boss_lose`, `fairy_lose`, `reward_check` | boss/fairy layout command | 做命令到 route 的 native map |

不要把这张图当成最终协议。它是派工地图：每条边都要有 route card 或 runtime card 补证。

## 里程碑

| M | 目标 | 必须证据 | 可并行准备 |
| --- | --- | --- | --- |
| M0 | 静态资源清单完成 | layout/model/command/behavior 表 | 所有 layout 拆分 |
| M1 | floor list 可见 | 截图 + server requests + `createFloorList()` vector/item 证据 | floor parser/value-domain |
| M2 | 点击楼层进入行走场景 | 下一条 route、decrypted request、`layout_exploration_main.xml` 可见控件 | `ExploreTagParser` schema |
| M3 | 无分支前进一步 | `/exploration/explore` 200 后回到 `stand` 或 `floor_clear_button` | bgName/bgmName/progress/reward 字段域 |
| M4 | 普通奖励事件 | gold/exp/card/parts 至少一种 UI observable | card/parts/userCard schema |
| M5 | floor clear/next floor | `floor_clear` 动画 + `next_floor` route | floor_clear 参数和 eventType 域 |
| M6 | boss 分支 | boss 准备 UI 或 no-BC UI | boss route、bcCheck、battle handoff |
| M7 | fairy 分支 | fairy/rare fairy 准备 UI | fairy_model、fairyHistory、lose/reward |
| M8 | 可循环探索 | area -> floor -> explore -> reward/next -> return 全链路 | 持久化/随机事件策略 |

## 并行工作包

### A. Floor List 解堵

目标：解决当前 blocker。

只回答一个问题：

```text
createFloorList() 看到的 floor_info_list count 是 0，还是 >0？
```

产出：

- `work/exploration-floorlist-probe-card.md`
- 精确 native offset、stock bytes、patched bytes、预期 observable。
- 若 count 为 0，下一步交给 C 包；若 count 大于 0，下一步交给 B 包。

禁止：

- 不改 XML 字段猜值。
- 不改服务器。
- 不换模拟器。

### B. Floor List UI/Item 消费者

目标：如果 vector 非空，找出 item 为什么不可见。

静态任务：

- 继续标注 `_ExplorationArea::createFloorList()`。
- 标出每个 `floor_info` item 被读取的 offset。
- 找出 item type/unlock/progress/cost/boss/found item 对 UI 的分支影响。

产出：

- `work/exploration-floorlist-ui-card.md`
- 字段 -> item 视觉效果 -> 失败 observable 表。

### C. Floor Parser/Model Schema

目标：如果 vector 为空，找出解析或 model init 断点。

静态任务：

- 复核 `_ExplorationFloorTagParser`、`_FloorInfoListTagParser`、`_FloorInfoTagParser`。
- 复核 `_ExplorationModel::init(ExplorationFloorTagData)` 是否把 list 放入 `model+0x58`。
- 区分“字段存在但值域无效”和“字段根本没被 push 进 vector”。

产出：

- `work/schema-cards/exploration-floor.md`
- `work/value-domain-cards/exploration-floor.md`

服务器只允许在这个 card 指出具体字段/值域后改。

### D. Command -> Route Mapping

目标：把 layout 里的 command 映射到真实 HTTP route。

优先级：

1. `floor`
2. `foward`
3. `foward2`
4. `next_floor`
5. `back` / `return_town`
6. `battle`
7. `fairyHistory`
8. `boss_lose` / `fairy_lose` / `reward_check`

产出：

- `work/exploration-command-route-map.md`
- 每条边包含：layout file、command name、native class/function、route 字符串、request 参数来源、置信等级。

### E. Explore Response Schema

目标：提前恢复进入行走主场景后 `/exploration/explore` 的响应结构。

静态入口：

- `_ExploreTagParser::parse`
- `_ExplorationModel::init(ExploreTagData)`
- `layout_exploration_main.xml` 的 `exp_model` 绑定：
  - `bgmName`
  - `bgName`
  - `floorInfo`
  - `areaName`
  - `progress`
  - `userCard`
  - `encounter`
  - `message`
  - `fairy_pose`
  - `fairy_face`
  - `gold`
  - `getExp`
  - `special_item`
  - `bossId`
  - `fairyBossId`
  - `eventType`

产出：

- `work/schema-cards/exploration-explore.md`
- 最小“无分支前进”响应草案。

不要等 M1 完成才开始 E 包。E 包是纯静态工作，可以并行。

### F. Reward/Card/Parts 分支

目标：把探索中的奖励 UI 拆出来，不要和普通前进混在一起。

静态入口：

- `card_get command="get_card"`
- `btl_parts_get command="parts_get"`
- `exploration_prize`
- `exploration_compound`
- `lv_max`

产出：

- `work/schema-cards/exploration-reward.md`
- 字段域：gold、exp、userCard、partsOne、autocompCards、lvMaxData。

### G. Boss/Fairy 分支

目标：提前拆 boss/fairy，不阻塞普通探索。

静态入口：

- `layout_exploration_boss.xml`
- `layout_exploration_fairy.xml`
- commands: `battle`, `bcCheck`, `bcCheck2`, `fairyHistory`, `boss_lose`, `fairy_lose`, `levelCheckFairy`

产出：

- `work/schema-cards/exploration-boss.md`
- `work/schema-cards/exploration-fairy.md`
- `work/exploration-boss-fairy-route-map.md`

### H. Value Domain / Masterdata

目标：给字段填什么值，不靠猜。

静态入口：

- bundle/local XML 样本。
- masterdata/resource 样本。
- `dungeon_rev`、area/floor/boss/card/item/resource revision。

产出：

- `work/value-domain-cards/exploration-area.md`
- `work/value-domain-cards/exploration-floor.md`
- `work/value-domain-cards/exploration-explore.md`

原则：

- 本地样本可以提供“像真值”，但不能直接证明当前 route schema。
- 每个 value 都要标注来源：layout consumer、parser field、sample XML、masterdata 或 runtime request。

### I. Runtime Validation

目标：只验证已经有静态证据的假设。

每次实机只允许验证一个变量：

```text
frontier
hypothesis
one changed variable
expected observable
artifact path
```

默认 artifact：

- requests
- activity
- relevant logcat
- screenshot

禁止把连接模拟器、安装 APK、采集全量 logcat 混进探索假设。

## Agent 派工模板

每个子 Agent 接任务时必须收到这样的边界：

```text
Frontier:
Hypothesis:
Allowed files:
Forbidden:
Minimum observable:
Output card:
Stop condition:
```

每个子 Agent 汇报时必须包含：

```text
current frontier:
last observable:
files changed:
new evidence:
dead ends recorded:
next smallest action:
```

如果某个 Agent 连续两次没有新 observable，就停止它，不让它继续堆 XML 或改 APK。

## 第一批建议派工

下一轮不要开“修复探索”这种大任务。开这些小任务：

1. Native probe Agent：只做 A 包，证明 `createFloorList()` vector count。
2. Parser Agent：只做 C 包，补完 floor parser/model schema card。
3. Route Agent：只做 D 包，映射 `floor/foward/next_floor/back`。
4. Explore Schema Agent：只做 E 包，恢复 `/exploration/explore` 的最小无分支响应。
5. Value Agent：只做 H 包，从静态样本挖 area/floor/bg/bgm/boss/card/item 值域。

这五路可以同时开。A 包决定当前卡点怎么修；C/H 包负责不再盲填；D/E 包保证 M1 后不会又卡在下一条 route。

## 完成标准

路线图本身完成，不等于探索修好。探索主线的阶段完成标准是：

- M1：可见 floor list。
- M2：点击 floor 后进入行走主场景。
- M3：点击前进后至少完成一次无分支探索。
- M8：能重复执行 area -> floor -> explore -> reward/next -> return。

任何阶段都不能只用 Node self-check 宣告完成。必须有客户端 observable。
