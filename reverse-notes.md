# KSSMA-Re Current Reverse Notes

This file is the startup index, not the full experiment log. The full pre-compaction
notes are archived at
`docs/reverse-archive/reverse-notes-full-before-compaction-20260627.md`.

## Current Baseline

- Source APK: `base/com.square_enix.million_cn-1.0.0.100.0712.M330.apk`.
- Resource dump: `base/com.square_enix.million_cn-140330.zip`.
- Decompiled output and working assets: `work/million_cn/`.
- Runtime target: Android `4.4.2` / API 19 / `armeabi-v7a` classic ARM emulator.
- Runtime control entry: `work/kssma-runtime.ps1`; `work/android44-arm19.ps1` is only a legacy shim.
- Primary serial is `127.0.0.1:5583`; the healthy fallback alias commonly used by helper commands is `emulator-5582`.
- Known keys:
  - `k1`: `A1dPUcrvur2CRQyl`
  - `k2`: `rBwj1MIAivVN222b`
- Server normally runs on both `50005` and `10001` through:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start`.
- Server self-check:
  `node .\server\test-bootstrap-server.js`.

## Flow Discipline

- Startup can still be advanced by next route.
- Gameplay must be advanced by flow edge:
  `user action -> request/response -> client state switch -> visible UI -> next click target/route`.
- HTTP 200 is not a gameplay success criterion.
- If an already-accepted correct path can produce the target UI/state/route,
  write a path card and statically recover that complete path before product patching.
- Repeating the previous-layer route after a supposed layer switch is strong evidence that foreground/click ownership did not change.
- After two failed local UI/state/behavior product patches, the next round must use known-good path diff/reuse or a read-only classifier.

## Accepted Startup And Main Menu

- Original Java flow can reach:
  `world_list.php -> check_inspection -> post_devicetoken -> connect/app/login`.
- Full save preload/mount fixed the old `save/download/rest/treasurebox` crash.
- `/connect/web/` notice handling is not a failure by itself; only interact with it when screenshot/UI proves an active notice is blocking play.
- Main menu visual restoration is accepted:
  - background uses `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile>`;
  - initial character face/pose and information box are accepted;
  - BGM/voice runtime baseline is accepted;
  - user footage confirmed tapped character subtitles originally had no backing dialogue box.
- Do not reopen main menu black background, face black, BGM, voice, or tapped dialogue-box work without a new resource-miss log, native texture crash, or regression screenshot.

Archive: `docs/reverse-archive/startup-mainmenu-20260624-20260625.md`.

## Accepted Runtime Control

- Use ARM19 only unless the user explicitly asks to investigate another runtime.
- Always run `fast-health` before real-device work.
- Only run `repair-adb` after `fast-health` explicitly fails.
- Only consider `restart-runtime -Force -Reason "..."` after repair also fails and reports `restartAllowed=true`.
- Native-only changes should use `patch-lib -ApkPath <apk-or-so>` and must verify installed/source SHA-256 equality.
- Frida is not a default probe because it can destabilize ARM19 ADB.

Archive: `docs/reverse-archive/runtime-control-arm19-20260625-20260627.md`.

## Accepted Exploration State

The accepted hierarchy is:

```text
main menu -> area list -> floor list -> floor/exploration main
```

Current accepted flow evidence:

- Main menu exploration button emits `/connect/app/exploration/area` and shows non-empty `Local Area`.
- Tapping `Local Area` emits `/connect/app/exploration/floor` with decrypted `area_id=0` and shows floor row `区域 1`.
- Tapping floor row emits `/connect/app/exploration/get_floor` with decrypted `area_id=0`, `floor_id=2`, `check=1`, and enters `exploration_main`.
- Tapping forward emits `/connect/app/exploration/explore` with decrypted `area_id=0`, `floor_id=2`, `auto_build=1`, and progress advances.
- Returning to main menu uses `/connect/app/mainmenu` and shows the accepted main menu.
- Floor-list return now re-requests `/connect/app/exploration/area`; the accepted route order is:
  `/exploration/area -> /exploration/floor -> /exploration/area -> /exploration/floor`.

Accepted native patches/builders:

- Sticky floor-list mode accepted the floor-list switch after floor data exists.
  Archive details: `docs/reverse-archive/exploration-floorlist-deadends-20260625-20260627.md`.
- Area/floor descent and floor-list return re-request accepted:
  - builder: `work/build-exploration-area-return-rerequest.py`
  - path card: `work/exploration-area-entry-rerequest-card-20260627.md`
  - output: `work/librooneyj-exploration-area-return-rerequest.so`
  - SHA-256: `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`
  - key artifacts:
    `work/kssma-runtime-exploration-area-return-rerequest-area-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-floor-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-return-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-refloor-*`.

Accepted server handlers:

- `/connect/app/exploration/area`
- `/connect/app/exploration/floor`
- `/connect/app/exploration/get_floor`
- `/connect/app/exploration/explore`
- `/connect/app/mainmenu`

Schema/value cards:

- `work/exploration-get-floor-schema-card-20260627.md`
- `work/exploration-explore-schema-card-20260627.md`
- `work/exploration-area-entry-rerequest-card-20260627.md`
- `work/exploration-bg-value-card-20260627.md`

Archives:

- `docs/reverse-archive/exploration-floorlist-deadends-20260625-20260627.md`
- `docs/reverse-archive/exploration-minloop-and-schema-20260627.md`
- `docs/reverse-archive/exploration-return-deadends-and-rerequest-20260627.md`

## Do Not Repeat

- Do not continue server `floor_info` field/value sweeps for floor-list visibility.
- Do not continue XML-only floor-list fixes without new native parser/consumer evidence.
- Do not use `0x00342108` as an unconditional floor-only anchor.
- Do not use successful-return-only `getSelected` probes as proof that a branch was not entered.
- Do not continue `+0x84` single-point visual fixes for the accepted floor-list blocker.
- Do not continue local `area_list_sp`, remake, draw-flag, state-only, or behavior-only return fixes for the accepted floor-list return blocker.
- Do not use `0x001f4200` as a layout behavior event function or `0x000c6b81` as `area_list_sp`.
- Do not merge the exploration background problem into hierarchy or route fixes.
- Do not treat APN permission warnings from `CheckNetWork` as a gameplay blocker.
- Do not treat `/connect/web/` alone as failure.

## Current Frontiers

- Exploration background value-domain:
  - Current server value is `<bg>exp_sarch</bg>`.
  - This is resource-backed but not accepted as visually correct.
  - Keep it separate from hierarchy/route work.
- Further exploration depth:
  - Repeated `explore`, event, battle, fairy, boss, reward, and floor-clear routes are not implemented as complete gameplay.
  - Add fields/routes only after a new route, screenshot, decrypted request, or native parser observable demands it.
- Other main-menu buttons:
  - Several routes are known from button triage, but only implement them one frontier at a time.

## Archive Index

- Full old log:
  `docs/reverse-archive/reverse-notes-full-before-compaction-20260627.md`
- Startup/login/main menu:
  `docs/reverse-archive/startup-mainmenu-20260624-20260625.md`
- ARM19 runtime control:
  `docs/reverse-archive/runtime-control-arm19-20260625-20260627.md`
- Exploration floor-list dead ends and accepted sticky floor-list mode:
  `docs/reverse-archive/exploration-floorlist-deadends-20260625-20260627.md`
- Exploration `get_floor` / `explore` schema and minimal loop:
  `docs/reverse-archive/exploration-minloop-and-schema-20260627.md`
- Exploration hierarchy return dead ends and accepted re-request fix:
  `docs/reverse-archive/exploration-return-deadends-and-rerequest-20260627.md`
- Process lessons:
  `docs/reverse-archive/process-lessons-20260627.md`

## Compaction Note

This file was compacted on 2026-06-27 from 2269 lines / 236228 bytes into a startup index.
Do not paste old archive material back into this file. Add new detailed experiments to a topic
archive when they are no longer current, and keep this file focused on accepted facts, active
frontiers, and hard "do not repeat" constraints.
