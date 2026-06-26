# pixie 资源和值域静态分析（2026-06-25）

## 范围

本轮只做静态分析：没有运行模拟器，没有启动 server，没有修改 APK、资源、server 或测试。

当前 frontier：`mainmenu/infomation` 的 `fairy_pose=2` / `fairy_face=1` 已经证明能影响 message/点击后 pixie 状态，但没有修复进入 mainmenu 后未点击时的初始背向/侧身画面。

可证伪假设：`fairy_pose` / `fairy_face` 控制 `_AnmPixie` 可加载的 pixie 图像候选；未点击初始正脸不是缺资源或 XML 字段未解析，而是 `_AnmPixie` 的初始 animation/action state 仍停在 frame-in/open 的背向/侧身状态。点击或 infomation 交互触发了另一个 state，才显示正脸资源。

最小 observable（给后续 runtime 用）：在不变更资源和 APK 的前提下，只改变 action/timing 或只改变一个 `fairy_face` 值，观察“初始截图”和“点击/infomation 动作后截图”是否分离。

## 已存在资源矩阵

### adv_chara111 图像资源

save dump 与 base zip 中的 `adv_chara111*` 矩阵一致：

| 文件 | 大小 | 静态含义 |
| --- | ---: | --- |
| `adv_chara111` | 56176 | 基础 pixie/角色图，非 pose-face 三元名 |
| `adv_chara111_2_1` | 41808 | `pose=2, face=1` 有真实文件；当前 runtime 已证明点击后可见正脸 |
| `adv_chara111_2_2` | 20320 | `pose=2` 的 face 变体 |
| `adv_chara111_2_3` | 20320 | `pose=2` 的 face 变体 |
| `adv_chara111_2_4` | 20592 | `pose=2` 的 face 变体 |
| `adv_chara111_2_5` | 20144 | `pose=2` 的 face 变体；native 字符串簇里也出现过 `.png` 形式 |
| `adv_chara111_2_6` | 20096 | `pose=2` 的 face 变体 |
| `adv_chara111_2_7` | 20320 | `pose=2` 的 face 变体 |
| `adv_chara111_2_8` | 20432 | `pose=2` 的 face 变体 |
| `adv_chara111_2_9` | 20432 | `pose=2` 的 face 变体 |
| `adv_chara111_2_10` | 20864 | `pose=2` 的 face 变体 |
| `adv_chara111_2_11` | 20512 | `pose=2` 的 face 变体 |
| `adv_chara111_2_12` | 20144 | `pose=2` 的 face 变体 |

未观察到：

- `adv_chara111_1_1` / `adv_chara111_1_*`
- `adv_chara111_3_*`
- `adv_chara2367*`

结论：`pose=2` 是唯一被 `adv_chara111` 资源矩阵支持的 pose。`face=1..12` 都有文件；`pose=1` 目前只是 parser 默认值，不是资源支持值。

### mainmenu / pixie / animation / rest 资源

save dump 与 base zip 中可见的 mainmenu/pixie 相关资源包括：

| 资源 | 大小 | 静态含义 |
| --- | ---: | --- |
| `save/download/rest/1000_menu` | 48528 | mainmenu rest 包 |
| `rja_1000_main_menu` / `.load` | 272 / 32 | mainmenu animation |
| `rja_1000_main_menu_fairy` / `.load` | 1312 / 32 | mainmenu fairy animation，和 pixie 初始状态最相关 |
| `rja_1000_main_menu_info` / `.load` | 1488 / 64 | infomation/info window animation |
| `rja_1000_main_menu_gacha` / `.load` | 1008 / 32 | gacha 区块 animation |
| `rja_1000_main_menu_level` / `.load` | 384 / 32 | level 区块 animation |
| `rja_1000_main_menu_status_ap` / `.load` | 3008 / 32 | AP/status 区块 animation |
| `rja_mm_pixie` / `.load` | 672 / 48 | pixie 专用 animation；可能决定 idle/open/tap state |
| `rja_dialog_with_fairy` / `.load` | 1904 / 128 | 带 fairy 的 dialog animation |
| `mainbg_an_*` 与 `rja_mainbg_an_*` | 多个 | 背景 animation，已另行证明可修复 mainbg |

结论：资源包里确实有 pixie/mainmenu animation 文件。`adv_chara111_2_1` 的存在只能证明图像可加载，不能证明 frame-in 初始 animation state 会选它作为正面帧。

## 预载与 scene 证据

`rule_resource.xml` 中：

- `player_select` scene id `300` 预载 `adv_chara11.png`、`adv_chara45.png`、`adv_chara81.png`、`adv_chara111.png`、`adv_chara117.png`、`adv_chara120.png`。
- `mainmenu` resource scene id `1000` 只预载 `1000_common_button_.png`、`treasurebox.png`、`button_label.png`。
- mainmenu 预载没有 `adv_chara111.png`，也没有 `adv_chara111_2_1.png` 或其它 face 变体。
- 文件里有注释掉的 `adv_chara111.png` 相关行，但不是 mainmenu 生效 preload。

`rule_scene.xml` 中 mainmenu scene 为 id `2100`、`layout=true`、BGM `bgm_common1`；`rule_resource.xml` 的 mainmenu 资源 id `1000` 更像资源包命名约定，不改变上面的预载结论。

结论：mainmenu 初始 pixie 不依赖 `rule_resource.xml` 预载 `adv_chara111`。它更可能通过 `_AnmPixie::updateFairyImage` 和 `rooney::res::getAdvChara*` 动态解析、加载或绑定资源。

## 命名规则与已知 native 证据

已知 native helper：

- `rooney::res::getAdvCharaFileName(int,int)` at `0x38fc8d`
- `rooney::res::getAdvCharaImage(int,int)` at `0x38fca1`
- `rooney::res::getAdvCharaFileName(int,int,int)` at `0x38fde1`

三参 helper 证据显示会打包 category `0x3b` 和 `(chara_id << 16) | (pose << 8) | face`，并使用 `adv_chara%d_%d_%d` 命名簇。native 字符串也包含：

- `adv_chara%d`
- `adv_chara%d_%d_%d`
- `adv_chara111`
- `adv_chara111.png`
- `adv_chara111_2_5.png`
- `fairy_pose`
- `fairy_face`
- `1000_main_menu_fairy.anm`
- `mm_pixie.anm`

`layout_mainmenu.xml` 中：

- `<pixie name="pixie" ... model="town_model">` 绑定 `fairy_pose` 与 `fairy_face`。
- `framein` / `framein_event` 行为会对 `pixie` 执行 `open` action。
- `main_information` 组件绑定 `infomation` command 和 `navigator_model.infoData`。
- `popup` 行为会对 `info` 执行 `set_data`。

`_AnmPixie::setPropertyValues` 会查找 `fairy_pose`、`fairy_face` 并调用 `_AnmPixie::updateFairyImage(pose, face)`。但 `updateFairyImage` 内部不是简单的一次 `(pose, face) -> 一个纹理` 映射：它同时调用二参/三参 adv helper 和 image 绑定函数，并存在对 pose/face 的分支处理。`_AnmPixie` 还具有 `action(uint32_t)`、`startAnimation(int)`、`getSelected(...)`、`isStay()` 等符号。

结论：字段链路成立，但动画/action 链路也成立。当前现象正好符合“字段已加载资源，初始 action/state 没切到正脸帧；点击后 action/state 切换才显示正脸”的模型。

## 最小候选排序

### 值域候选

1. `infomation/fairy_pose=2, fairy_face=1`
   - 最高优先级。
   - 静态资源存在：`adv_chara111_2_1`。
   - runtime 已观察：message 出现，点击后 pixie 从背向/侧身变为可见正脸。
   - 结论：这是当前最好的基线，但它本身没有证明能控制未点击初始 state。

2. `infomation/fairy_pose=2, fairy_face=5`
   - 第二候选。
   - 静态资源存在：`adv_chara111_2_5`。
   - native 字符串里出现过 `adv_chara111_2_5.png`，比其它 face 变体多一个静态引用信号。
   - 适合作为“face 值确实影响点击后表情，但不影响初始背向/侧身”的最小对照。

3. `infomation/fairy_pose=2, fairy_face=2..4/6..12`
   - 都是资源支持的 face 变体。
   - 只适合在确认需要表情枚举时再扫；现在不该扩大测试面。

4. `infomation/fairy_pose=1, fairy_face=1`
   - 低优先级。
   - parser 默认值是 `1/1`，但资源矩阵没有 `adv_chara111_1_1`。
   - 过去 direct mainmenu 字段也已证明无效；不值得为了初始正脸重复测。

### 不值得测的候选

- direct `<mainmenu><fairy_pose>` / `<mainmenu><fairy_face>`
  - 已有 runtime 负证据：direct 字段无效，正确路径是 `<mainmenu><infomation>...`。

- `pose=3` 或其它无资源 pose
  - 没有 `adv_chara111_3_*` 文件；除非 native 新证据证明 pose 不是文件名 pose，否则不测。

- `adv_chara2367*` / 把 `leader_serial_id=2367` 当角色资源 id
  - 已有笔记说明 `leader_serial_id` 不是 `master_card_id`；没有对应资源。

- 增加 `imagefile`、`banner`、`rewards`、`event_type`、`focus`、`link`
  - 当前没有证据说明这些字段参与 `_AnmPixie` 初始正脸。
  - `imagefile` 更像 infomation/info window 内容，不是 pixie 主体资源。

- 修改 `rule_resource.xml` mainmenu preload
  - 点击后能看到正脸，说明关键资源不是彻底缺失。
  - 预载方向容易把“加载时机”误判成“animation state”，目前不值得动。

## 为什么 `2/1` 有 observable 但没修初始正脸

最可能根因：`fairy_pose=2` / `fairy_face=1` 已经通过 `infomation -> TownModel -> layout property -> _AnmPixie::setPropertyValues -> updateFairyImage` 进入 pixie 组件，并能让 `adv_chara111_2_1` 成为可用图像；但 mainmenu frame-in 时，`layout_mainmenu.xml` 会先执行 pixie 的 `open` action，`rja_mm_pixie` / `rja_1000_main_menu_fairy` 选择的是初始背向/侧身 animation state。点击或 infomation 交互后，`_AnmPixie::action` / `startAnimation` / selection state 切到另一个状态，才把已加载的正脸图像显示出来。

也就是说，`2/1` 解决的是“字段链路与资源候选是否成立”，不是“初始 animation state 是否正脸”。这解释了为什么 message 和点击状态有 observable，而未点击初始画面仍不变。

## 下一步 runtime 变量建议（最多 2 个）

1. 只改变 action/timing，不改变 XML 值和资源。
   - 保持 `fairy_pose=2, fairy_face=1`。
   - 记录进入 mainmenu 后未点击截图，再触发一次现有 pixie/infomation 交互并记录截图。
   - 期望：如果初始仍背向/侧身、交互后正脸，则根因继续指向 animation/action state，而不是资源和值域。

2. 只改变一个 face 值：`fairy_face=1 -> 5`，`fairy_pose` 保持 `2`。
   - 选择 `5` 是因为 `adv_chara111_2_5` 有文件，且 native 字符串中出现过 `adv_chara111_2_5.png`。
   - 期望：如果点击后表情/正脸资源变化，而未点击初始仍背向/侧身，则 face 值域成立，但初始问题仍是 action/state；如果未点击初始也变化，才回头收窄 face 对初始 state 的影响。

不要同时改 pose、face、message、preload 或 layout action。一次只改一个变量，否则无法区分“值域错”与“动作状态错”。

## 结论

`fairy_pose=2, fairy_face=1` 是当前最小、资源支持、已被点击后画面证明的基线值。未点击初始正脸没有修复，最可能不是 `adv_chara111_2_1` 缺失，也不是 `rule_resource.xml` 未预载，而是 mainmenu 的 pixie 初始 animation/action state 仍选择背向/侧身。后续应优先验证 action/timing，再用 `2/5` 做一个 face 值对照；不应扩大到换 chara id、补 preload、加 info/banner/reward 字段或扫无资源 pose。
