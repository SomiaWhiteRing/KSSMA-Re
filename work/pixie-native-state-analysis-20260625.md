# Pixie Native State Analysis, 2026-06-25

Scope: static-only analysis of `_AnmPixie` / main-menu pixie state.
No emulator, server, APK, resource, or test changes were made.

Frontier:
`_AnmPixie` initial `open` / clicked-state native action and image-state
difference.

Static anchor:
`_AnmPixie::action`, `_AnmPixie::setPropertyValues`,
`_AnmPixie::updateFairyImage`, `_AnmPixie::getSelected`.

Observable wanted later:
One pre-tap screenshot under a single value change, compared against the known
`infomation 2/1 + message` pre-tap and post-tap screenshots.

## Confirmed

### Layout ownership

- `layout_mainmenu.xml` creates `<pixie name="pixie" x="-145" y="20"
  model="town_model">` and binds only:
  - `fairy_pose` -> `fairy_pose`
  - `fairy_face` -> `fairy_face`
- `framein` sends `<action target="pixie" name="open"/>`.
- `frameout` sends `<action target="pixie" name="close"/>`.
- `delay_open` in `framein` targets `fairy`, not `pixie`:
  `<action target="fairy" name="delay_open"/>`.
- `popup` targets the information panel, not pixie:
  `<action target="info" name="set_data"/>`.
- `<pixie>` has no `command` attribute in `layout_mainmenu.xml`.

### Function locations

All addresses are Thumb code starts in `librooneyj.so`.

- `_AnmPixie::isStay()` at `0x288dd0`, size `4`.
  It returns `1`.
- `_AnmPixie::task()` at `0x288dd4`, size `78`.
  It increments `this+0x38` as an animation frame counter and clamps it for
  animation state `1` or `2`.
- `_AnmPixie::startAnimation(int)` at `0x288e98`, size `18`.
  It accepts only states `1` and `2`, stores the state at `this+0x34`, and
  resets `this+0x38`.
- `_AnmPixie::updateFairyImage(int pose, int face)` at `0x288eac`, size `488`.
  It selects an internal character id, calls adv-character resource helpers, and
  replaces pixie image slots.
- `_AnmPixie::getSelected(smart_ptr<_MtTouchEvent> const&)` at `0x289094`,
  size `408`.
  It is the pixie touch/click path.
- `_AnmPixie::draw(smart_ptr<IMtGraphics>&)` at `0x28922c`, size `320`.
  It draws state `1` or `2` animations.
- `_AnmPixie` constructor at `0x289494`, size `592`.
  It initializes image holders, animation data, internal character ids, and a
  `_FairyVoiceMap`.
- `_AnmPixie::action(unsigned long)` at `0x2896e4`, size `456`.
  It recognizes only pixie action names `open` and `close`.
- `_AnmPixie::setPropertyValues(map<unsigned long, void*...>&)` at `0x2898ac`,
  size `140`.
  It reads `fairy_pose` and `fairy_face`, then calls `updateFairyImage`.

Related helper:

- `_FairyVoiceMap::getFaceId(int)` at `0x288e24`, size `116`.
  It returns a `PoseFace` pair from a country-specific map.
- `_FairyVoiceMap::createMapCountryA/B/C` at `0x287788`, `0x287638`,
  `0x2874e8`.
- `_FairyVoiceMap` constructor at `0x2878d8`; it chooses one country map from a
  dynamic country selector.

### Model-to-pixie image path

Confirmed parser/model path from the existing schema cards:

```text
<body><mainmenu><infomation>...
-> _MainMenuTagParser::parse
-> _InfomationTagParser::parse
-> MainMenuTagData +0x20 infomation vector
-> _TownModel::init(...)
-> TownModel +0x88 = first infomation fairy_pose
-> TownModel +0x8c = first infomation fairy_face
-> _TownModel::getMap exposes fairy_pose / fairy_face
-> layout_mainmenu.xml pixie params
-> _AnmPixie::setPropertyValues
-> _AnmPixie::updateFairyImage(pose, face)
```

`_AnmPixie::setPropertyValues` evidence:

- `0x2898b6` loads literal `fairy_pose`.
- `0x2898ec` loads `fairy_pose` again and fetches its map value.
- `0x289902` loads literal `fairy_face`.
- `0x28991a` calls `_AnmPixie::updateFairyImage`.
- The call is gated by finding `fairy_pose`; the function then fetches both
  pose and face from the property map.

### `updateFairyImage` resource behavior

`updateFairyImage(pose, face)` is an image/resource selector, not a layout
action.

Confirmed static behavior:

- It derives the pixie character id internally, not from XML.
- The constructor seeds three character ids:
  - `this+0x3c = 117`
  - `this+0x40 = 120`
  - `this+0x44 = 111`
- `updateFairyImage` indexes those ids using a dynamic selector at
  `0x288efe`-`0x288f08`.
- Existing runtime/resource evidence already made `adv_chara111` the best
  current main-menu pixie id. Static-only proof still leaves the selector
  dynamic, so `111` is high-confidence for this scene, not a new XML field.
- It calls adv-character helpers at:
  - `0x288f0e` -> `rooney::res::getAdvCharaFileName(int, int)`
  - `0x288f62` -> `rooney::res::getAdvCharaImage(int, int)`
  - `0x288fb0` -> `rooney::res::getAdvCharaFileName(int, int, int)`
  - `0x288ffe` -> the paired three-argument image helper path
- For selector value `3`, `0x288ee8`-`0x289084` preserves the incoming pose
  only when `face == 1`; otherwise it forces `pose = 2`.

For the current kept payload, the initial property-bound image update is
therefore expected to be:

```text
pose = 2
face = 1
character id = internally selected; current evidence points to 111
resource candidate = adv_chara111_2_1
```

### `open` / `close` action path

`_AnmPixie::action` evidence:

- `0x2896f8` compares action hash for literal `open`.
- `0x28970a` compares action hash for literal `close`.
- `open` branch at `0x28972a` calls `_AnmPixie::startAnimation(1)`.
- `close` branch at `0x28981c` calls `_AnmPixie::startAnimation(2)`.
- No direct call to `_AnmPixie::updateFairyImage` exists in either branch.
- The `open` branch also contains voice-string setup using literals:
  - `vo_j004c_0`
  - `vo_j004_0`
  - `vo_j004b_0`
  but that is separate from the `fairy_pose` / `fairy_face` image binding.

Answer: initial layout action `open` itself does not call `updateFairyImage`.
The only initial `updateFairyImage` path is the model/property binding path via
`setPropertyValues`.

### Click / touch path

`_AnmPixie::getSelected` is the click/touch handler.

Confirmed static behavior:

- It returns immediately unless `this+0x34 == 1`, so pixie must be in the
  opened/stay animation state.
- It checks touch event state/type and a hit rectangle.
- It gets an interaction id from an internal helper using `this+0x4c`.
- It calls `_FairyVoiceMap::getFaceId(id)` through `this+0x54`.
- It calls `_AnmPixie::updateFairyImage(mapped_pose, mapped_face)` at
  `0x28915e`.
- It plays a voice string chosen from the same `vo_j004...` family.
- It returns selected/handled.

The click path does use `updateFairyImage`, but its pose/face source is
`_FairyVoiceMap`, not `TownModel` `fairy_pose` / `fairy_face`.

Answer: clicked front-face state does not go through a different named pixie
layout action. It goes through the touch handler `getSelected`. It also does
not call `startAnimation`, so the confirmed difference is a different
pose/face image-source path, not a confirmed switch to animation state `2`.

### `fairy_pose` / `fairy_face` role

Confirmed:

- `fairy_pose` / `fairy_face` are model-bound pixie image selectors consumed by
  `_AnmPixie::setPropertyValues`.
- They are valid for initial/property update image selection once they come
  through `<mainmenu><infomation>...`.
- They are not read directly under `<mainmenu>`.
- They are not pixie action names.
- They are not the click/talk selector; click/talk uses `_FairyVoiceMap` and
  then calls the same `updateFairyImage` function with different inputs.

## Candidates

### Most likely root cause

The initial unclicked state and the clicked front-face state are different
native image-selection paths:

```text
initial:
TownModel fairy_pose/fairy_face
-> _AnmPixie::setPropertyValues
-> updateFairyImage(2, 1)
-> open action only starts animation state 1

clicked:
_AnmPixie::getSelected
-> _FairyVoiceMap::getFaceId(interaction id)
-> updateFairyImage(mapped_pose, mapped_face)
-> voice/talk side effect
```

This makes "front face after tap" a click/talk-state effect, not proof that the
initial `open` state is fixed.

### Candidate: `face=1` is a default/non-front expression

For the current main-menu character id evidence (`111`), dumped resources
include `adv_chara111_2_1` through `adv_chara111_2_12`.

Static evidence shows country selector `3` forces `pose=2` for `face != 1`,
while preserving the caller pose for `face == 1`. That makes `face=1` look
special/default. It may be a valid initial image but not the visible
front/talk face seen after tapping.

Missing proof:

- Which exact `_FairyVoiceMap` id was chosen in the tapped screenshot.
- Which `adv_chara111_2_N` file visually corresponds to the tapped front face.

### Candidate: draw/layer state hides or emphasizes different image slots

`updateFairyImage` updates image holders, while `draw` chooses animation state
`1` or `2` and clips/draws with the current frame counter. The clicked path
does not statically prove a state switch, but it does update the image slots
while already in state `1`.

Missing proof:

- A runtime/native trace showing which image slot and frame are drawn before
  and after click.

## Rejected

- Rejected: treating "tap shows front face" as a fix for the initial main-menu
  state. The tap path is a different native input path.
- Rejected: `delay_open` as a pixie action in main menu. Layout sends
  `delay_open` to `fairy`, not `pixie`, and `_AnmPixie::action` has no
  `delay_open` branch.
- Rejected: `open` directly calls `updateFairyImage`. It calls
  `startAnimation(1)` and voice setup only.
- Rejected: `close` directly calls `updateFairyImage`. It calls
  `startAnimation(2)` only.
- Rejected: a named pixie `click` / `talk` action branch in
  `_AnmPixie::action`. Static action dispatch recognizes `open` and `close`;
  click/talk behavior is in `getSelected`.
- Rejected: direct `<mainmenu><fairy_pose>` /
  `<mainmenu><fairy_face>` as the parser shape. Existing schema/runtime
  evidence rejects it; the fields must come through `<infomation>`.
- Rejected: resource-missing explanations for the current frontier without new
  log evidence. Prior notes already exclude missing `adv_chara111`,
  `bgm_common1.ogg`, `save/download/rest`, and the old `_Layout::event(0x98)`
  path as current causes.

## Direct Answers

### Where are the functions and how do they call each other?

```text
MainMenuPixieTemplate::create          0x2da5a0
  -> _AnmPixie::constructor            0x289494

layout framein pixie/open
  -> _AnmPixie::action                 0x2896e4
  -> _AnmPixie::startAnimation(1)      0x288e98
  -> _AnmPixie::task/draw              0x288dd4 / 0x28922c

layout frameout pixie/close
  -> _AnmPixie::action                 0x2896e4
  -> _AnmPixie::startAnimation(2)      0x288e98

model property binding
  -> _AnmPixie::setPropertyValues      0x2898ac
  -> _AnmPixie::updateFairyImage       0x288eac

pixie tap/click
  -> _AnmPixie::getSelected            0x289094
  -> _FairyVoiceMap::getFaceId         0x288e24
  -> _AnmPixie::updateFairyImage       0x288eac
  -> voice string path                 vo_j004...
```

### Does initial layout action `open` call `updateFairyImage`?

No. `open` calls `startAnimation(1)`.

The initial image update, if the model property map is applied, comes from
`setPropertyValues`. With the current kept `infomation 2/1 + message` payload,
that path uses `pose=2` and `face=1`; the internally selected character id is
best evidenced as `111` for the current main-menu pixie.

### Does clicked/front state use a different action or animation state?

Confirmed different path: yes, it uses `getSelected`, not layout action
`open`.

Confirmed different animation state: not proven. `getSelected` requires
state `1` and does not call `startAnimation`, so static evidence points to the
same opened animation state with a different pose/face image source.

### Are `fairy_pose` / `fairy_face` initial selectors or only action-specific?

They are initial/property-bound image selectors. They are consumed by
`setPropertyValues`, not by `open`.

They do not drive the click/talk path directly. The click/talk path uses
`_FairyVoiceMap` to select a possibly different `PoseFace` pair and then calls
`updateFairyImage` again.

## Minimal Runtime Hypothesis

Hypothesis:
The unclicked state is not front-facing because `fairy_face=1` is a
default/non-front initial expression, while tapping chooses another face through
`_FairyVoiceMap`.

One variable:
Keep the proven payload shape and message, keep `fairy_pose=2`, and change only:

```xml
<fairy_face>1</fairy_face>
```

to:

```xml
<fairy_face>2</fairy_face>
```

Expected observable:

- Judge only the pre-tap main-menu screenshot.
- If pre-tap pixie changes to the same front-facing class of image, the next
  frontier is value-domain mapping for `fairy_face`.
- If pre-tap remains back/side while post-tap still changes to front, the next
  frontier is confirmed as click-time `_FairyVoiceMap` / image-state behavior,
  not more XML shape work.

Do not count post-tap front face as success for the initial state.
