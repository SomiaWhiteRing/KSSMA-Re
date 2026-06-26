# Pixie layout/command 静态链路分析，2026-06-25

> 2026-06-25 状态更新：主菜单视觉还原已阶段完成。用户找回关服前录像，确认
> 点角色后的同步台词原版就没有底色/对话框背景。本文件只保留 layout/native
> 链路证据，不再代表待修的主菜单视觉问题。

## Frontier

静态重建 mainmenu layout 层里 `pixie`、`stat_fairy`、`main_information`、
`html_viewer` 的初始 `framein`、`popup`、`view_html`、点击 command/action 链路。

边界：未运行模拟器；未修改 server、APK、资源或测试。

## Sources

- `AGENTS.md`
- `readme.md`
- `clean-start.md`
- `reverse-notes.md`
- `work/mainmenu-native-schema-card-20260625.md`
- `work/mainmenu-infomation-schema-card-20260625.md`
- `work/mainmenu-infomation-value-candidates-20260625.md`
- `work/million_cn/apktool/assets/bundle/layout_mainmenu.xml`
- `work/million_cn/apktool/assets/bundle/rule_scene.xml`
- `work/million_cn/apktool/assets/bundle/rule_resource.xml`
- 静态 native 对照：`librooneyj.so` 符号与窄范围反汇编

## Short answer

confirmed: 主菜单进入时的 XML 进场链路是 `framein` 或事件变体 `framein_event`：
`fairy delay_open` 在 `pixie open` 之前，`info` 只是随后被设为 visible。
`info set_data` 不在 `framein` 里，它只出现在独立 `popup` behavior。

confirmed: 点击后正脸不是 `framein` 成功，也不是 `pixie open` 的同一个 action。
layout 里 `pixie` 节点没有 `command` 属性；点击后的变化来自 pixie 组件自己的
selected/touch 分支，或来自 `main_information command="infomation"` 触发的
mainmenu command handler。两者和初始 `pixie open` 不是同一层动作。

candidate: 当前最可能根因不是缺字段，而是把“进场 idle/open 姿态”和“点击/弹出
交互姿态”混在一起看了。layout 暗示初始态可以是背向/侧身；正脸更像点击后的
selected/popup 状态。

## Confirmed

### Scene and resource anchors

confirmed: `rule_scene.xml:43` 把 scene `2100` 定义为 `name="mainmenu"`，
`layout="true"`，BGM 为 `bgm_common1`。

confirmed: `rule_resource.xml:72-78` 的 `scene name="mainmenu"` 只列出
`1000_common_button_.png`、`treasurebox.png`、`button_label.png`。mainmenu
scene 的静态 resource 表没有列出 pixie 变体。`rule_resource.xml:62-67`
列出的 `adv_chara111.png` 在前面的资源段，不是 mainmenu 专属资源段。
这和已有 value card 的结论一致：pixie 变体更可能由 native resource helper
动态解析，而不是 layout 静态声明。

### Layout components

confirmed: `layout_mainmenu.xml:19` 定义隐藏的
`<html_viewer name="html_viewer" visible="false" url="connect/web/"/>`。

confirmed: `layout_mainmenu.xml:21-24` 定义
`<pixie name="pixie" x="-145" y="20" model="town_model">`，只绑定
`fairy_pose` 与 `fairy_face` 两个 model param；该节点没有 `command` 属性。

confirmed: `layout_mainmenu.xml:31` 定义
`<stat_fairy name="fairy" ... visible="false" command="fairy" />`。

confirmed: `layout_mainmenu.xml:35-37` 定义
`<main_information name="info" ... visible="false" command="infomation"
model="navigator_model">`，并绑定 `infoData`。

### Entry behavior order

confirmed: `layout_mainmenu.xml:127-170` 的 `behaviar name="framein"` 顺序是：

1. `layout_mainmenu.xml:128` action `fairy delay_open`
2. `layout_mainmenu.xml:129` action `level open`
3. `layout_mainmenu.xml:130` action `pixie open`
4. `layout_mainmenu.xml:131-143` 打开各按钮/状态/slot/story
5. `layout_mainmenu.xml:146-164` 把多个组件设为 visible，其中 `info` 在
   `151` 和 `164` 被设为 `true`
6. `layout_mainmenu.xml:166` action `viewer open`
7. `layout_mainmenu.xml:168-169` 修正 menu 按钮并 unlock `button_group`

confirmed: `layout_mainmenu.xml:220-263` 的 `framein_event` 是事件按钮版本；
核心顺序同样是 `fairy delay_open` 在 `pixie open` 前，`info` 后续 visible。

confirmed: `info set_data` 不在 `framein` 或 `framein_event` 中。唯一直接
XML 证据是 `layout_mainmenu.xml:318-320`：

```xml
<behaviar name="popup">
    <action target="info" name="set_data" />
</behaviar>
```

confirmed: WebView 的 info action 是另一个 behavior：
`layout_mainmenu.xml:327-330` 的 `view_html` 先把 `html_viewer` visible 设为
`true`，再对 `html_viewer` 调 action `infomation`。

### Data path versus command path

confirmed: server XML 的 `<mainmenu><infomation>...</infomation></mainmenu>`
是数据节点，不是 layout command。已有 schema card 证明 `_MainMenuTagParser`
读取 typo `infomation`，再交给 `_InfomationTagParser`；`fairy_pose` /
`fairy_face` 复制进 `TownModel`，`infoData` 进 `NavigatorModel`。

confirmed: layout 中 `pixie` 只消费 `town_model.fairy_pose` /
`town_model.fairy_face`（`layout_mainmenu.xml:21-24`）。layout 中
`main_information` 消费 `navigator_model.infoData`
（`layout_mainmenu.xml:35-37`）。这是同一个 `<infomation>` 数据的两个投影，
不是同一个 UI action。

confirmed: native `_AnmPixie::setPropertyValues` 读取 `fairy_pose` /
`fairy_face` 后调用 `_AnmPixie::updateFairyImage(pose, face)`；这解释了
`infomation 2/1` 为什么能成为 pixie 图像输入。

confirmed: native `_AnmInfomation::setPropertyValues` 读取 `infoData`；
`_AnmInfomation::action` 的字符串区包含 `1000_main_menu_info.anm`、
`apperar`、`disappear`、`blur`、`frame_out`、`set_data`，并且
`set_data` 分支调用 `_AnmInfomation::setInfomationTagData`。

## Candidate

### 点击角色区域的链路

candidate: 点击可见角色区域时，至少有两条可能链路需要区分：

1. pixie 组件自身的 touch/select 分支。
   `_AnmPixie::getSelected(...)` 静态反汇编显示它在组件 opened/stay 状态和
   touch end 类事件下做 hit test，随后调用 `_AnmPixie::updateFairyImage`，
   并引用 `vo_j004c_0%d`、`vo_j004b_0%d`、`vo_j004_0%d` 语音资源字符串。
   这能解释“点击后切到正脸/表情”。
2. `main_information command="infomation"` 的 scene command 分支。
   native 符号存在 `_ZN9_MainMenu10Infomation4execEi`；该函数调用
   `_LinkModel::getInstance`、`_LinkModel::linkto(int, LayoutScene*)` 和
   `LayoutScene::trigger(IModel*)`。这说明 `infomation` command 是 scene
   handler 层，不是 `pixie open` action。

candidate: 实际 tap 坐标如果落在 `main_information` hitbox 上，会走
`command="infomation"`；如果落在 pixie hitbox 上，会走 `_AnmPixie::getSelected`。
两者可能同时在视觉上覆盖角色/信息框区域，所以需要 runtime hitbox 验证才能把
点击后正脸唯一归因到其中一条。

### `main_information command="infomation"`、pixie、html_viewer 的关系

candidate: 三处 `infomation` 不是同一个东西：

- server XML typo `<infomation>`：数据。提供 `fairy_pose`、`fairy_face`、
  `message` 等。
- `main_information command="infomation"`：点击 `info` 组件时发出的 scene
  command token。
- `html_viewer action infomation`：`view_html` behavior 中对 WebView 组件的
  action name，URL 基础是 `connect/web/`。

candidate: `_MainMenu::Infomation::exec` 走 `LinkModel::linkto`，而
`layout_mainmenu.xml:327-330` 又有 `view_html`。因此带 `link` 或 held content
时可能进入 Web/link 分支；无 link/default `link=-1` 时更可能只触发本地 popup
或无 Web 跳转。当前静态证据还没有完整证明 `link=-1` 到 `popup` 的分支条件。

## Rejected

rejected: “初始 framein 调用了 `info set_data`”。XML 不支持这个说法；
`framein` 只把 `info` visible 设为 true，`set_data` 只在 `popup`
behavior 中。

rejected: “`pixie command` 是 layout XML 上的 command 属性”。`pixie`
节点 `layout_mainmenu.xml:21-24` 没有 `command` 属性。点击后的 pixie 变化
不能按 XML command 属性解释。

rejected: “点击后出现正脸证明初始态修好了”。已有 runtime 事实说明
`infomation 2/1 + message` 让信息框显示；点击后正脸是预期交互态，不是
初始 framein 态的成功标准。

rejected: “需要继续补 `imagefile`、`banner`、`rewards`、`event_type` 来解释
这次差异”。已有 server/test 与 schema notes 明确当前只保留已证明字段；
这些字段没有新的 layout/native 必要性证据。

## Interpretation

layout 暗示主菜单初始状态不必是正脸弹出态：

- 进场 `framein` 是“打开/显现”链：`fairy delay_open`、`pixie open`、
  各按钮 open、`info visible=true`。
- `popup` 是独立链：只做 `info set_data`。
- `view_html` 是独立链：显示 `html_viewer` 并对它调 `infomation`。
- pixie 点击是组件自身的 selected/touch 链，和 `pixie open` 不是同一个 action。

因此，初始背向/侧身、点击后正脸的差异，目前最像“idle/open 状态 vs
selected/popup 状态”的正常区别，而不是缺某个 mainmenu XML 字段。

仍未完全关闭的问题是：scene 是否应该在进入 mainmenu 后自动触发一次 `popup`
或 `behaviorLink()`。不过当前最新 runtime 已经证明信息框能显示 `Welcome back.`，
所以这不是继续补 XML 字段的理由。

## Closed validation

不再需要为“点角色后缺对话框底色”继续做 runtime hitbox 或 command dispatch
验证。关服前录像已经把这个前提关闭：点角色后的同步台词无底框是原版行为。

## Historical interpretation

这份报告写作时的判断是：当时所谓“视觉差异”不是缺字段或资源，而是把主菜单
初始 `framein` 的 pixie idle/open 姿态和点击后的 selected/popup 姿态混为一个
验收目标。后续关服前录像已确认该判断方向正确：这里没有需要修的台词底框问题。
