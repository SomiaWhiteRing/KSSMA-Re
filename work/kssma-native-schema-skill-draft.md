# KSSMA Native Schema Draft

Purpose: make future `/connect/app/` XML work parser-led instead of field-guessing.
This is a KSSMA-specific workflow draft, not an installable Codex skill.

## When To Use

Use this workflow when a KSSMA route stalls because the local server response shape is unknown or suspicious:

- a new `/connect/app/*` route returns `501` or a placeholder XML;
- the client receives a response but does not move to the next route or scene;
- a screen renders with missing model data and logcat has no missing resource path;
- someone is tempted to add XML fields by guessing from names, old server habits, or UI text.

Do not use it for runtime setup, emulator choice, APK rebuilds, resource preloading, audio checks, or known closed issues in `reverse-notes.md`.

## Inputs

Required local evidence:

- `reverse-notes.md` for current frontier, known routes, and failed experiments.
- `server/bootstrap-server.js` for the current minimal response shape.
- `server/test-bootstrap-server.js` for server-only checks after a later implementation change.
- `work/million_cn/apktool/lib/armeabi/librooneyj.so` as the native authority.
- `work/million_cn/jadx/sources/` for Java bootstrap, crypto, WebView, and JNI handoff context.
- `work/million_cn/apktool/assets/bundle/` or `work/million_cn/jadx/resources/assets/bundle/` for bundled XML examples.
- `work/million_cn/sdcard_dump/` and `base/com.square_enix.million_cn-140330.zip` for sample resource/masterdata values.

Useful runtime evidence, when already collected:

- `work/kssma-runtime-*/server.out.log`
- `work/kssma-runtime-*/logcat*.txt`
- screenshots proving the current scene or UI state
- decrypted request parameters printed by `bootstrap-server.js`

## Steps

1. State the frontier.
   Write the route, scene, or parser boundary being investigated. The observable must be one of: next HTTP route, native parser branch, scene id, logcat line, model field assignment, or screenshot tied to a scene transition.

2. Pick one static anchor.
   Start from exactly one of:
   - route string, for example `exploration/floor`;
   - parser symbol, for example `_ExplorationFloorTagParser::parse`;
   - XML field string, for example `current_bgfile`;
   - bundled XML file that the native path already consumes.

3. Locate native ownership.
   Use fast string/symbol reconnaissance first, then decompiler-level work only where needed:
   - find the route string in `librooneyj.so`;
   - find xrefs from that route to the request builder or completion callback;
   - find `*TagParser::parse` symbols or nearby string clusters;
   - find xrefs to field strings and parent node strings.

4. Recover the parser contract.
   For the target parser, record only facts visible in native code:
   - expected parent node name;
   - scalar child names;
   - list wrapper names and item node names;
   - numeric vs string handling;
   - default or error behavior when a node is absent;
   - call path from response parse to model update.

5. Separate required fields from decoration.
   A field is required only when native evidence shows one of:
   - missing node sends control flow to an error/early-return path;
   - the model reads it before the next observable;
   - it selects a resource, scene, route, or list entry needed by the next step.
   Everything else stays `candidate`, not implemented.

6. Cross-check values against existing artifacts.
   Use bundled XML, sample masterdata, and resource filenames for values. They can justify values, not field existence. Example: `mainbg_an` is a value candidate only after native evidence confirms `current_bgfile` under `<mainmenu>`.

7. Produce a schema card before touching code.
   The schema card is the output of this workflow. It must be small enough that a later server patch can change one variable and test one observable.

8. Hand off to normal KSSMA experiment loop.
   If the schema card implies a server response change, apply it in a separate task using the repository loop: frontier, hypothesis, one variable, observable, check, `reverse-notes.md` entry.

## Stop Conditions

Stop the static schema pass when any of these is true:

- The parent node and all fields needed for the next observable are confirmed.
- The route-to-parser path is not found after checking route string, parser symbols, and nearby field strings; record the gap instead of guessing.
- The next unknown is dynamic state, callback timing, request order, or local storage rather than XML shape.
- The next proof requires emulator/logcat/client interaction; hand off to `kssma-re-runtime`.
- Two candidate fields in a row have no native parser evidence. Stop and go back to xrefs.

## Product Format

Create or append a section in a `work/` artifact using this shape:

```text
Route:
Frontier:
Static anchor:
Native owner:
Parser path:
Expected parent:
Confirmed fields:
  - name | type | required? | evidence | value source
List nodes:
  - wrapper -> item | fields | evidence
Rejected shapes:
  - shape | evidence
Minimal XML candidate:
Observable for later runtime check:
Open questions:
```

Evidence lines should include native symbols, string names, addresses when available, and source artifact paths. Keep guessed semantics out of `Confirmed fields`.

## Runtime Skill Handoff

This workflow stops at a schema card. Use `kssma-re-runtime` only after a minimal response patch exists and the next proof needs the ARM19 client.

The handoff should include:

- exact route and hypothesis;
- the single response-shape change to test;
- expected next request, scene id, parser log, or screenshot;
- required server command, normally `work/kssma-server.ps1 start`;
- required runtime command from the skill, normally the smallest driven login or scene check;
- artifact prefix under `work/`;
- what must be appended to `reverse-notes.md` after the run.

Do not ask the runtime skill to discover schema by broad trial. Its job is to validate the one schema hypothesis against the client.

## Bans

- Do not install skills or copy generic reverse-skill scripts into this repo.
- Do not run the emulator as part of this static schema pass.
- Do not modify APK, native patches, resources, or `server/bootstrap-server.js` during schema drafting.
- Do not add XML fields because their names look plausible.
- Do not use bundled/sample XML as proof of a field unless native parser evidence points to the same node.
- Do not reopen excluded frontiers from `reverse-notes.md`.
- Do not switch Android runtime, ABI, emulator, or audio baseline.
- Do not hide uncertainty: mark fields as `confirmed`, `candidate`, or `rejected`.

## Notes From Existing Evidence

- Java owns bootstrap, crypto, and world selection; native owns most `/connect/app/` route schemas.
- `librooneyj.so` string clusters and `*TagParser::parse` symbols are the primary map.
- The `mainmenu` fix is the model example: `<main_menu>` and direct `<body>` fields were rejected by experiment, while native evidence plus runtime proof confirmed `<mainmenu><current_bgfile>...`.
- Exploration work already has confirmed parser fields for area/floor. Future exploration changes should start from the model completion/callback path, not by adding more XML.
