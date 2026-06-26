# KSSMA native schema hardening, 2026-06-25

## Recommendation

Recommended landing place:

`C:\Users\旻\.codex\skills\kssma-re-native-schema\SKILL.md`

Do not put the full workflow in `AGENTS.md`, `readme.md`, or
`HUMAN-ROADMAP.local.md`.

Reason:

- `AGENTS.md` is always loaded before every edit. The native schema workflow is only needed when
  `/connect/app/` XML shape is unknown, so putting the full procedure there would tax unrelated
  runtime, server, and documentation work.
- `readme.md` is for project overview and shortest human operation. Parser-led native schema work
  is too narrow and too agent-procedural for it.
- `HUMAN-ROADMAP.local.md` is for human project strategy. It can mention the existence of a schema
  skill later, but should not become an agent runbook.
- `kssma-re-runtime` must stay focused on ARM19/server/logcat/screenshot validation. Expanding it
  into static native schema recovery would blur the stop condition and reopen runtime/audio scope.
- A separate local skill gives the right trigger behavior: load it only when an agent is about to
  infer XML schema, inspect `librooneyj.so`, or patch a `/connect/app/` response shape.

Minimal change now:

- Keep this report in `work/`.
- Do not install the skill yet.
- After the main thread approves, create only
  `C:\Users\旻\.codex\skills\kssma-re-native-schema\SKILL.md` from the draft below.
- Optional later, after the skill exists, add a one-line pointer to `AGENTS.md`:

```markdown
如果任务涉及 `/connect/app/` XML schema、native `*TagParser` 字段、或有人准备猜响应字段，优先使用个人 skill：`kssma-re-native-schema`；它只做静态 schema pass，需要 ARM19 验证时再交给 `kssma-re-runtime`。
```

That optional pointer is not required for the current task. The smallest durable landing is the
local skill.

## Complete SKILL.md draft

Save this as:

`C:\Users\旻\.codex\skills\kssma-re-native-schema\SKILL.md`

Do not add scripts, references, or generic reverse-engineering helpers for v1. The reusable asset is
the workflow and output format, not code.

```markdown
---
name: kssma-re-native-schema
description: Static native-schema recovery workflow for the KSSMA-Re repository. Use when working in KSSMA-Re and a `/connect/app/*` XML response shape is unknown, suspicious, returns 501, stalls a scene/request, or someone is tempted to guess fields. Covers parser-led inspection of `librooneyj.so`, bundled XML, master/resource samples, and schema-card handoff. Do not use for emulator control, APK rebuilds, runtime setup, resource preloading, audio checks, or broad runtime triage; use `kssma-re-runtime` for ARM19 validation after one schema hypothesis exists.
---

# KSSMA-Re Native Schema

Use this skill to recover KSSMA `/connect/app/` response schemas from native evidence before
changing server XML. The output is a schema card, not a patch.

## Required repo context

Read these first in the repository:

1. `AGENTS.md`
2. `readme.md`
3. `clean-start.md`
4. `reverse-notes.md`
5. `server/bootstrap-server.js`
6. `server/test-bootstrap-server.js`

Then read any existing route-specific `work/*schema-card*.md` relevant to the current frontier.

## Boundaries

Do not run the emulator.
Do not start or stop the runtime server.
Do not edit APK, native patches, resources, `server/bootstrap-server.js`, or tests during the
schema pass.
Do not copy generic reverse-engineering scripts into the repo.
Do not add XML fields because names look plausible.
Do not reopen closed runtime, audio, face/mainbg, or resource issues from `reverse-notes.md`.

Stop the schema pass and hand off when proof requires ARM19, logcat, screenshots, callback timing,
or current client state.

## Workflow

State the current frontier before inspecting:

```text
Frontier:
Static anchor:
Observable wanted later:
```

Use exactly one static anchor:

- route string, for example `exploration/floor`;
- parser symbol, for example `_ExplorationFloorTagParser::parse`;
- XML field string, for example `current_bgfile`;
- bundled XML file that the native path already consumes.

Locate native ownership:

- find the route string in `work/million_cn/apktool/lib/armeabi/librooneyj.so`;
- find xrefs from the route to the request builder or completion path;
- find nearby `*TagParser::parse` symbols and field-string clusters;
- find xrefs to parent node strings, child field strings, and list wrapper strings;
- use decompiler-level work only for the narrow owner path.

Recover only parser facts visible in native code:

- expected parent node;
- scalar child names;
- list wrapper names and item node names;
- numeric/string handling when visible;
- missing-node behavior when visible;
- call path from response parse to model update or scene transition.

Classify fields:

- `confirmed`: native parser evidence shows the node/field is read.
- `required`: native evidence shows it gates the next observable, model value, resource, scene,
  route, or list entry needed now.
- `candidate`: value source exists, but native requirement or value domain is not proven.
- `rejected`: native evidence or prior runtime evidence proves the shape is wrong.

Use sample artifacts only for values, not field existence:

- `work/million_cn/apktool/assets/bundle/`
- `work/million_cn/jadx/resources/assets/bundle/`
- `work/million_cn/sdcard_dump/`
- `base/com.square_enix.million_cn-140330.zip`

Example: `mainbg_an` is a valid value candidate only after native evidence confirms
`current_bgfile` under `<mainmenu>`.

## Required output

Write or append a small schema card under `work/`, using this exact shape:

```text
Route:
Frontier:
Static anchor:
Native owner:
Parser path:
Expected parent:
Confirmed fields:
  - name | type | required? | evidence | value source
Candidate fields:
  - name | type | evidence | value source | missing proof
List nodes:
  - wrapper -> item | fields | evidence
Rejected shapes:
  - shape | evidence
Minimal XML candidate:
Observable for later runtime check:
Open questions:
```

Evidence lines should name concrete symbols, strings, addresses when available, and source paths.
Keep guessed semantics out of `Confirmed fields`.

## Stop conditions

Stop when one of these holds:

- parent node and fields needed for the next observable are confirmed;
- route-to-parser ownership is not found after checking route string, parser symbols, and nearby
  field strings;
- the next unknown is dynamic state, callback timing, request order, or local storage;
- the next proof needs emulator/logcat/screenshot/client interaction;
- two candidate fields in a row have no native parser evidence.

When stopped by a gap, record the gap in the schema card instead of guessing.

## Handoff to kssma-re-runtime

This skill stops before runtime validation. Use `kssma-re-runtime` only after the schema card
supports one minimal response-shape change.

The handoff must include:

- exact route and frontier;
- one response-shape change to test;
- expected next request, scene id, parser/log line, or screenshot;
- server command, usually `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start`;
- runtime command from `kssma-re-runtime`, normally the smallest `kssma_runtime_check.ps1` command
  for the current scene;
- artifact prefix under `work/`;
- the `reverse-notes.md` entry to append after the run.

Do not ask the runtime skill to discover schema by broad trial. Its job is to validate one schema
hypothesis against the ARM19 client.

## Known local examples

- Main menu background proof: `<body><mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile></mainmenu></body>` fixed the black main-menu background path. `<main_menu>` and direct `<body>` fields were rejected by runtime evidence.
- Exploration area/floor fields already have parser evidence in `reverse-notes.md`. Future
  exploration work should inspect model completion/callback state before adding XML fields.
- `leader_serial_id` is not a `master_card_id`. Use an owner-card payload with both `serial_id`
  and `master_card_id` before mapping face/adv resources.
```

## How this pairs with kssma-re-runtime

`kssma-re-native-schema` and `kssma-re-runtime` should form a two-step gate:

1. Native schema skill: static proof only. It inspects native parser ownership and writes a schema
   card. No emulator, no server edit, no APK edit.
2. Runtime skill: validation only. It applies or tests one minimal server response change, drives
   the existing ARM19 flow, captures server/logcat/screenshot artifacts, and appends
   `reverse-notes.md`.

The schema skill should hand the runtime skill a single falsifiable experiment. Bad handoff:

```text
Try fields until the exploration screen works.
```

Good handoff:

```text
Route: /connect/app/mainmenu/update
Hypothesis: native MainMenuTagParser reads pixie face from <body><mainmenu><fairy_face>.
One variable: add only <fairy_face>1</fairy_face> beside existing proven bg fields.
Observable: scene 2100 screenshot changes pixie expression and no JResourceLoader/native crash appears.
Runtime: use kssma-re-runtime with -DriveLogin -DismissNoticeWebView.
Artifacts: work/kssma-runtime-mainmenu-fairy-face-*
```

If the runtime result produces new native/logcat evidence, update `reverse-notes.md` and, if useful,
the route-specific schema card. Do not move runtime findings back into the native schema skill unless
they are durable examples like rejected node shapes.

## Shortest future-agent instruction

After the skill is installed, use:

```text
请按 AGENTS.md 执行，并使用 $kssma-re-native-schema。
只做静态 schema pass，不运行模拟器、不改 APK/server。
当前 frontier: [route or scene].
输出一个 work/*schema-card*.md；如果需要 ARM19 验证，只写给 $kssma-re-runtime 的单一假设和 observable。
```

Before the skill is installed, use:

```text
请按 AGENTS.md 执行。临时按 work/kssma-native-schema-hardening-20260625.md 里的 SKILL.md 草案做静态 native schema pass。
禁止运行模拟器、改 APK/server、猜 XML 字段。输出 work/*schema-card*.md 和给 kssma-re-runtime 的单一验证假设。
```

