# Mainmenu Native Schema Card, 2026-06-25

Source: Noether subagent report for `/connect/app/mainmenu/update`.

This card records the static native-schema result so future agents do not need to
recover it from chat history.

## Route

`/connect/app/mainmenu/update`

## Frontier

Historical note: this schema card was written before the main-menu visual pass
was closed. The old "character dialogue incomplete" premise is obsolete:
pre-shutdown footage confirms the tapped main-menu subtitle originally had no
bottom/backing dialogue box, and the current `fairy_pose=2` / `fairy_face=5`
baseline is accepted for the initial face.

Static frontier for schema reuse remains:

`_MainMenuTagParser::parse -> MainMenuTagData -> _TownModel::init -> layout/component consumers`

No emulator, server, APK, or test changes were part of this schema pass.

## Static Anchor

`librooneyj.so::_ZN18_MainMenuTagParser5parseEP12TiXmlElement` at `0x30471d`

Primary references:

- `work/mainmenu-parser-annotated.txt`
- `work/town-mainmenu-disasm.txt`
- `work/mainmenu-components-annotated.txt`

## Native Owner

`MainMenuTagData`, size `0x2c`

## Parser Path

Runtime evidence confirms `<body><mainmenu>` reaches the main-menu model.
`_MainMenuTagParser::parse` iterates only the child nodes of the element passed
to it. The consumer is `_TownModel::init(smart_ptr<MainMenuTagData>, bool)` at
`0x1e8099`; `_TownModel::getMap` then exposes values to layout/component code.

## Expected Parent

```xml
<body>
  <mainmenu>
    ...
  </mainmenu>
</body>
```

`<main_menu>` is rejected by runtime evidence and has no matching parser compare
in `_MainMenuTagParser::parse`.

## Confirmed Fields

| Field | Type | Required? | Evidence | Value source |
| --- | --- | --- | --- | --- |
| `current_bgfile` | String | Required for background baseline | compare at `0x304834` -> branch `0x3049ca`; stores `String` at `MainMenuTagData +0x00`; `_TownModel` copies to `+0x38/+0x3c`; exposed as `currentBgfile` to `_AnmBackground` | resource background basename; `mainbg_an` proven |
| `previous_bgfile` | String | Required for background baseline | compare at `0x304844` -> branch `0x304988`; stores `String` at `MainMenuTagData +0x08`; `_TownModel` copies to `+0x40/+0x44`; exposed as `previousBgfile` to `_AnmBackground` | resource background basename; `mainbg_an` proven |
| `banner` | nested `XmlContentsTagData` | Not required for current face proof | literal `banner` at `0x3d5cfc`; branch `0x30488c` calls `_XmlContentsTagParser::parse` at `0x3123a8`; stores smart pointer at `MainMenuTagData +0x18/+0x1c`; `_TownModel` passes it to `_XmlContentsModel::init` | unknown; recover `XmlContentsTagParser` before use |
| `infomation` | list entry via `InfomationTagData` | Candidate for face/dialogue | typo literal `infomation` at `0x3d951c`; branch `0x304a38` calls `_InfomationTagParser::parse` at `0x302764`; pushes vector at `MainMenuTagData +0x20`; `_TownModel` copies vector to `+0xa4` and derives `fairy_pose` / `fairy_face` from first item into `+0x88/+0x8c` | unknown; recover `InfomationTagParser` before use |
| `rewards` | int | Not required yet | compare points to literal `rewards` at `0x3d4a6c`; branch `0x304964` reads `GetText` / `toInt`; stores `MainMenuTagData +0x10`; `_TownModel` stores `+0x30` and `getMap` exposes `rewards` | unknown |
| `event_type` | int | Not required yet | literal `event_type` at `0x3ddaa0`; branch `0x30492c` reads `GetText` / `toInt`; stores `MainMenuTagData +0x14`; `_TownModel` stores `+0x98`; direct UI consumer not found | unknown |

## List Nodes

| Wrapper | Item | Fields | Evidence |
| --- | --- | --- | --- |
| `banner` | first child element | Owned by `_XmlContentsTagParser::parse` | `0x3048e2` `FirstChildElement`, `0x3048f0` parse call |
| `infomation` | first child element | Owned by `_InfomationTagParser::parse` | `0x304ac0` `FirstChildElement`, `0x304acc` parse call, `0x304afe` push into `MainMenuTagData +0x20` vector |

## Rejected Shapes

- `<main_menu>` wrapper: runtime rejected; no `_MainMenuTagParser` compare evidence.
- Direct `<fairy_pose>` / `<fairy_face>` under `<mainmenu>`: not read by
  `_MainMenuTagParser`; these are `TownModel` properties derived from
  `InfomationTagData`.
- `bgAnmType` under `<mainmenu>`: not read by this parser; `_TownModel` computes
  or stores it separately.
- `login_bonus` / `town_event_list` under this parser: separate parser/model
  paths, not `_MainMenuTagParser` fields.

## Minimal XML Candidate

```xml
<body>
  <mainmenu>
    <current_bgfile>mainbg_an</current_bgfile>
    <previous_bgfile>mainbg_an</previous_bgfile>
  </mainmenu>
</body>
```

No `infomation` XML candidate yet. The inner item node and fields are still
unrecovered, so adding it now would be guessing.

## Observable For Later Runtime Check

After `_InfomationTagParser::parse` is mapped, change exactly one response shape:
add one minimal `<infomation>` entry. Expected observable is a `TownModel`-visible
`fairy_pose` / `fairy_face` effect, proven by pixie face/dialogue screenshot or
equivalent native/log evidence.

## Open Questions

- Exact child node name and field schema inside `<infomation>`.
- Which `InfomationTagData` offsets map to `fairy_pose` and `fairy_face` beyond
  observed first two ints.
- Exact `banner` / `XmlContentsTagParser` shape, if banner or dialogue content
  becomes required.
- Consumer semantics of `MainMenuTagData +0x14` / `_TownModel +0x98`
  `event_type`.
