# Mainmenu Fairy Schema Card

Route:
- `/connect/app/login` seeded `<body><mainmenu>...`
- `/connect/app/mainmenu/update` same minimal `<mainmenu>` body

Frontier:
- Main menu pixie pose/face model values after scene `2100` is visible.

Static anchor:
- XML fields `fairy_pose` and `fairy_face`.

Native owner:
- `_MainMenuTagParser::parse(TiXmlElement*)` at `0x30471c`.
- `_TownModel::init(smart_ptr<_MainMenuTagData>, bool)` at `0x1e8098`.
- `_AnmPixie::setPropertyValues(map<...>)` at `0x2898ac`.
- `_AnmPixie::updateFairyImage(int, int)` at `0x288eac`.

Parser path:
- Existing runtime proof established `<mainmenu>` as the parent for town/mainmenu model fields.
- `layout_mainmenu.xml` binds `<pixie model="town_model">` params `fairy_pose` and `fairy_face`.
- `_AnmPixie::setPropertyValues` looks up `fairy_pose`, then `fairy_face`, then calls `updateFairyImage(pose, face)`.

Expected parent:
- `<body><mainmenu>...</mainmenu></body>`

Confirmed fields:
- `current_bgfile` | string | required for current background | previous mainmenu runtime proof | value source `mainbg_an`
- `previous_bgfile` | string | required for previous background | previous mainmenu runtime proof | value source `mainbg_an`

Candidate fields:
- `fairy_pose` | integer-like | candidate pixie pose input | `layout_mainmenu.xml:21-23`, `mainmenu-parser-annotated.txt:1056-1122` | runtime test value `1`
- `fairy_face` | integer-like | candidate pixie face input | `layout_mainmenu.xml:21-23`, `mainmenu-parser-annotated.txt:1056-1122` | runtime test value `1`

Rejected shapes:
- `<main_menu>` wrapper | runtime experiment did not affect mainmenu visuals.
- direct `<body>` background fields | runtime experiment did not affect mainmenu visuals.

Minimal XML candidates:

```xml
<body>
  <mainmenu>
    <current_bgfile>mainbg_an</current_bgfile>
    <previous_bgfile>mainbg_an</previous_bgfile>
    <fairy_pose>1</fairy_pose>
  </mainmenu>
</body>
```

```xml
<body>
  <mainmenu>
    <current_bgfile>mainbg_an</current_bgfile>
    <previous_bgfile>mainbg_an</previous_bgfile>
    <fairy_face>1</fairy_face>
  </mainmenu>
</body>
```

Observable for later runtime check:
- Artifact prefix under `work/`.
- Server response size proves the single field was served.
- Screenshot of scene `2100` after dismissing `/connect/web/`, compared with baseline clean screenshot.
- Logcat scan for `JResourceLoader`, `getSDPackFile`, `loadTexture`, `face`, `fairy`, `Fatal signal`, `SIGABRT`, `SIGSEGV`.
- Top activity remains `com.test.RooneyJActivity`.

Open questions:
- The numeric value domain for pixie pose/face is not recovered here. Value `1` is only an existence/binding probe.
