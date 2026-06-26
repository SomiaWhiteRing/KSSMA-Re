# Mainmenu Infomation Schema Card, 2026-06-25

Status update, 2026-06-25: main-menu visual restoration is stage-complete.
This card is retained only as schema evidence for `<mainmenu><infomation>`.
Do not use it to reopen the old tapped-subtitle/dialogue-box bug; pre-shutdown
footage confirmed the tapped subtitle originally has no backing box.

Route:
- `/connect/app/login` seeded `<body><mainmenu>...`
- `/connect/app/mainmenu/update` same `<mainmenu>` body

Frontier:
- Static schema for `<mainmenu><infomation>...</infomation></mainmenu>`.
- Goal is to identify which native fields feed `TownModel` `fairy_pose` /
  `fairy_face`, and which fields feed the main-menu information panel.
- Static only: no emulator, no server start, no APK/server/test change.

Static anchor:
- `_InfomationTagParser::parse(TiXmlElement*)`
  (`_ZN20_InfomationTagParser5parseEP12TiXmlElement`) at symbol `0x302765`,
  Thumb code start `0x302764`, size `740`.
- Parent handoff from `_MainMenuTagParser::parse`:
  `infomation` typo literal at `0x3d951c`; branch around `0x304a38`;
  `FirstChildElement()` at `0x304ac0`; call to `_InfomationTagParser::parse`
  at `0x304acc`; push into `MainMenuTagData +0x20` vector at `0x304afe`.

Native owner:
- `_InfomationTagParser` owns `InfomationTagData`, allocated size `0x24`.
- Constructor/default path in `_InfomationTagParser::parse`:
  `fairy_pose=1`, `fairy_face=1`, `focus=false`, `link=-1`,
  `imagefile` null `String`, and an empty `vector<MessageTagData>` at
  `InfomationTagData +0x18`.
- `_MessageTagParser` owns `MessageTagData`, allocated size `0x14`, with
  default `size=0x14`.

Parser path:
- `<body><mainmenu>` is already the proven parent for `_MainMenuTagParser`.
- `_MainMenuTagParser::parse` treats each `<infomation>` node as one list
  entry. It calls `FirstChildElement()` on that `<infomation>` node and passes
  the first child directly to `_InfomationTagParser::parse`.
- `_InfomationTagParser::parse` scans the passed child and its siblings by
  node name. It does not require or recognize an inner item node.
- `_TownModel::init(MainMenuTagData, bool)` copies
  `MainMenuTagData +0x20` into `TownModel +0xa4`; when the copied vector is
  non-empty, it sends the first `InfomationTagData` to
  `_NavigatorModel::init` and copies first item `+0x00` / `+0x04` into
  `TownModel +0x88` / `+0x8c`.
- `_TownModel::getMap` exposes `TownModel +0x88` as `fairy_pose` and
  `TownModel +0x8c` as `fairy_face`.
- `layout_mainmenu.xml` binds `<main_information model="navigator_model">`
  param `infoData`; `_NavigatorModel::getMap` exposes its stored
  `InfomationTagData` as `infoData`.
- `_AnmInfomation::setPropertyValues` reads `infoData`; action `set_data`
  calls `_AnmInfomation::setInfomationTagData`, which forwards the parsed
  message vector to `_MsgViewer::setMessage`.

Expected parent:
```xml
<body>
  <mainmenu>
    <infomation>
      ...
    </infomation>
  </mainmenu>
</body>
```

Confirmed fields:
- `fairy_pose` | int | required for non-default TownModel pixie pose |
  string `0x3d3fe4`; compare path `0x3027e4`; `toInt(..., 0)` store to
  `InfomationTagData +0x00` at `0x302a16`; first item copied to
  `TownModel +0x88` at `0x1e8136`; exposed as `fairy_pose` at `0x1e9598` |
  value domain not recovered
- `fairy_face` | int | required for non-default TownModel pixie face |
  string `0x3d3ff0`; compare path `0x3027f4`; `toInt(..., 0)` store to
  `InfomationTagData +0x04` at `0x3029f2`; first item copied to
  `TownModel +0x8c` at `0x1e8146`; exposed as `fairy_face` at `0x1e95b0` |
  value domain not recovered
- `focus` | bool | not required for current pixie proof |
  string `0x3e514c`; compare path `0x302804`; `toBool(..., false)` store to
  `InfomationTagData +0x08` at `0x3029ce` | no value source yet
- `link` | int | not required for current pixie proof |
  string `0x3dedb8`; compare path `0x302814`; `toInt(..., 0)` store to
  `InfomationTagData +0x0c` at `0x3029aa` | no value source yet
- `imagefile` | string | candidate info-window image/resource selector |
  string `0x3de268`; compare path `0x302824`; `GetText` copied into
  `InfomationTagData` string at `+0x10` around `0x302940`-`0x30296c`;
  `_AnmInfomation::setInfomationTagData` checks this string before preparing
  message rendering | no value source yet
- `message` | nested message entry | required for the main information text path |
  string `0x3d389c`; compare path beginning `0x302840`; `FirstChildElement()`
  at `0x3028d8`; `_MessageTagParser::parse` call at `0x3028e4`; pushed into
  `InfomationTagData +0x18` vector at `0x302914`; consumed by
  `_MsgViewer::setMessage` at `0x288234` | see list node fields

Candidate fields:
- `imagefile` value | string | parser and UI consumer are confirmed, but the
  resource namespace, empty/non-empty behavior, and interaction with message
  rendering are not recovered | missing proof: resource lookup path or a
  bundled/sample value
- `message/color` value | string | `_MessageTagParser` reads it, but color
  format is not recovered | missing proof: `_MsgViewer` color parser value
  examples
- `message/size` value | int | `_MessageTagParser` reads it and defaults to
  `0x14`, but units/domain are not recovered | missing proof: `_MsgViewer`
  layout/value examples

List nodes:
- `mainmenu` -> repeated `infomation` sibling | fields:
  `fairy_pose`, `fairy_face`, `focus`, `link`, `imagefile`, `message` |
  evidence: `_MainMenuTagParser::parse` calls `FirstChildElement()` on each
  `<infomation>` node and pushes one parsed `InfomationTagData` into
  `MainMenuTagData +0x20`.
- `infomation` -> repeated `message` sibling | fields:
  `text`, `color`, `size` | evidence: `_InfomationTagParser::parse` calls
  `FirstChildElement()` on each `<message>` node and pushes one parsed
  `MessageTagData` into `InfomationTagData +0x18`.
- `message` has no confirmed item wrapper. `_MessageTagParser::parse` scans
  its direct children:
  - `text` | string | string `0x3dddf4`; stores to `MessageTagData +0x00`
  - `color` | string | string `0x3dcb8c`; stores to `MessageTagData +0x08`
  - `size` | int | string `0x3dcb94`; stores to `MessageTagData +0x10`

Rejected shapes:
- `<main_menu>` parent | rejected by prior runtime evidence and no matching
  `_MainMenuTagParser` compare.
- Direct `<mainmenu><fairy_pose>` / `<mainmenu><fairy_face>` | not read by
  `_MainMenuTagParser`; prior runtime probes under `<mainmenu>` produced no
  pixie observable.
- `<infomation_list><infomation>...` | no confirmed
  `_MainMenuTagParser` compare for `infomation_list`.
- `<infomation><item>...</item></infomation>` | rejected by parser path:
  `_InfomationTagParser` receives the first child of `<infomation>` and only
  compares that node and its siblings against confirmed field names. It does
  not descend through a generic item node.
- `<message><item>...</item></message>` | rejected by `_MessageTagParser`
  path for the same reason; it scans direct `text` / `color` / `size` children.
- `information` spelling | no evidence for the correctly spelled node in this
  parser path; native literal is the typo `infomation`.

Minimal XML candidate:
- Shape only. Values are intentionally placeholders because the pose/face
  value domain and message style values are not recovered in this static pass.

```xml
<body>
  <mainmenu>
    <current_bgfile>mainbg_an</current_bgfile>
    <previous_bgfile>mainbg_an</previous_bgfile>
    <infomation>
      <fairy_pose>POSE_VALUE</fairy_pose>
      <fairy_face>FACE_VALUE</fairy_face>
      <message>
        <text>TEXT_VALUE</text>
        <color>COLOR_VALUE</color>
        <size>SIZE_VALUE</size>
      </message>
    </infomation>
  </mainmenu>
</body>
```

- Smallest later pixie-only runtime check should add one `<infomation>` entry
  with only `fairy_pose` and `fairy_face`, beside the already proven
  `current_bgfile` / `previous_bgfile` fields.
- Smallest later information-panel check should add one direct `<message>` child with
  direct `text` / `color` / `size` children; do not add an item wrapper.

Observable for later runtime check:
- Server response size proves exactly one `<infomation>` entry was served.
- Scene `2100` still reaches visible main menu and top activity remains
  `com.test.RooneyJActivity`.
- Pixie check: clean screenshot differs in the pixie face/pose region versus
  `work/kssma-runtime-mainmenu-fairy-baseline-clean.png`.
- Information-panel check: triggering layout command `infomation` / behavior
  `popup` shows a main information window whose message text comes from the
  `message/text` value, with no `JResourceLoader`, `getSDPackFile`,
  `loadTexture`, `Fatal signal`, `SIGABRT`, or `SIGSEGV`.
- Log/trace fallback: `_AnmInfomation::setInfomationTagData` reaches
  `_MsgViewer::setMessage` after `infoData` is bound from `NavigatorModel`.

Open questions:
- Exact numeric domain for `fairy_pose` and `fairy_face`.
- Whether default `InfomationTagData` values `1/1` are visually distinct from
  the current baseline once the `<infomation>` node exists.
- Concrete `imagefile` resource namespace and whether non-empty `imagefile`
  suppresses, replaces, or decorates message rendering.
- Valid `message/color` format and `message/size` units.
- Whether multiple `<infomation>` siblings are rotated by `NavigatorModel` or
  only the first one is reachable in the current main-menu layout.
