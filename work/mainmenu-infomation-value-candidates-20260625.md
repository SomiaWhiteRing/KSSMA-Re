# Mainmenu Infomation Value Candidates, 2026-06-25

Status update, 2026-06-25: main-menu visual restoration is stage-complete.
The final accepted local baseline uses `fairy_pose=2`, `fairy_face=5`, and the
minimal `message` node. Do not use this candidate list to reopen the old
tapped-subtitle/dialogue-box issue; pre-shutdown footage confirmed no backing
box is expected there.

Static-only follow-up to `work/mainmenu-infomation-schema-card-20260625.md`.

No emulator, server, APK, or test changes were made.

## Frontier

The `<mainmenu><infomation>...</infomation></mainmenu>` node structure is known,
but the safe values for `fairy_pose`, `fairy_face`, and `message` still need
static narrowing before runtime validation.

## Findings

### Message Values

`message/text`, `message/color`, and `message/size` have usable bundled examples:

- `work/million_cn/apktool/assets/bundle/local_gachaselect.xml`
- `work/million_cn/apktool/assets/bundle/local_gachacomp.xml`

Observed formats:

- `color`: RGB hex string such as `0xFFFFFF`, `0xFD7C79`, `0xFF0000`
- `size`: decimal font size such as `12`, `14`, `16`, `18`, `20`
- `_MessageTagParser` default size is `0x14` (`20`)
- `text`: normal XML text; comments in bundled samples document `&#xA;` for newline
  and `&#x20;` for space

Low-risk dialogue message candidate:

```xml
<message>
  <text>Welcome back.</text>
  <color>0xFFFFFF</color>
  <size>20</size>
</message>
```

### Pixie Pose / Face Values

`_AnmPixie::updateFairyImage(pose, face)` does not use `fairy_pose` and
`fairy_face` as direct filenames. It passes them through native resource-name
helpers:

- `rooney::res::getAdvCharaFileName(int, int)` at `0x38fc8d`
- `rooney::res::getAdvCharaImage(int, int)` at `0x38fca1`
- `rooney::res::getAdvCharaFileName(int, int, int)` at `0x38fde1`

Relevant disassembly:

- `work/mainmenu-town-pixie-disasm.txt`, `updateFairyImage` calls at
  `0x288f0e`, `0x288f62`, `0x288fb0`
- `work/native-mainbg-disasm.txt`, helper bodies around `0x38fc8d`,
  `0x38fca1`, `0x38fd9d`, `0x38fde1`

The 3-argument filename helper packs:

```text
resource category: 0x3b
encoded id/value: (chara_id << 16) | (pose << 8) | face
```

The observed dumped resources for the known main-menu pixie character include:

```text
save/download/image/adv/adv_chara111
save/download/image/adv/adv_chara111_2_1
save/download/image/adv/adv_chara111_2_2
...
save/download/image/adv/adv_chara111_2_12
```

No `adv_chara111_1_1` was observed in the dump.

Earlier runtime work had already proven `adv_chara111` is required for the
main-menu path, so `111` is the best currently evidenced pixie/character id for
this screen.

Additional static checks:

- `work/million_cn/apktool/assets/bundle/rule_resource.xml` declares
  `adv_chara111.png` in the player-select scene resources; the mainmenu scene
  itself declares only common UI resources, so the pixie variants appear to be
  resolved dynamically by native resource-name helpers rather than listed in
  `rule_resource.xml`.
- `work/million_cn/apktool/assets/bundle/layout_mainmenu.xml` binds the
  `pixie` component only to `town_model` fields `fairy_pose` and `fairy_face`;
  no layout-side field can directly override the character id.
- The 140330 save dump and ZIP both contain the same backed variant set:
  `adv_chara111` plus `adv_chara111_2_1` through `adv_chara111_2_12`.
  This supports pose `2` with face values `1..12`, and gives no file-backed
  evidence for pose `1`.

## Candidate Ranking

1. Highest-confidence pixie candidate:

```xml
<fairy_pose>2</fairy_pose>
<fairy_face>1</fairy_face>
```

Reason: it matches an existing resource: `adv_chara111_2_1`.

2. Lower-confidence default candidate:

```xml
<fairy_pose>1</fairy_pose>
<fairy_face>1</fairy_face>
```

Reason: `_InfomationTagParser::parse` default path initializes `InfomationTagData`
with `fairy_pose=1` and `fairy_face=1`, but no `adv_chara111_1_1` resource was
observed. This should not be the first runtime trial unless new static evidence
changes the resource id or fallback behavior.

## Minimal Runtime Candidate

If runtime validation is needed later, test one `<infomation>` entry with the
resource-backed `2/1` pair, not direct `<mainmenu><fairy_pose>...`.

```xml
<body>
  <mainmenu>
    <current_bgfile>mainbg_an</current_bgfile>
    <previous_bgfile>mainbg_an</previous_bgfile>
    <infomation>
      <fairy_pose>2</fairy_pose>
      <fairy_face>1</fairy_face>
      <message>
        <text>Welcome back.</text>
        <color>0xFFFFFF</color>
        <size>20</size>
      </message>
    </infomation>
  </mainmenu>
</body>
```

## Remaining Historical Unknowns

- The exact character id used by `_AnmPixie::updateFairyImage` is inferred from
  prior `adv_chara111` runtime evidence, not re-proven in this static pass.
- The exact visual difference between `adv_chara111` and `adv_chara111_2_1`
  was superseded by the later accepted `2/5` runtime baseline.
- Whether `imagefile` should be set for the main-menu information panel remains
  unknown, but it is not needed for the accepted main-menu baseline.
