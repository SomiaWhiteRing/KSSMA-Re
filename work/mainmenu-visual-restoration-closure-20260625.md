# Mainmenu Visual Restoration Closure, 2026-06-25

## Status

Main-menu visual restoration is stage-complete for the current local baseline.

User recovered pre-shutdown footage and confirmed that tapping the main-menu
character originally showed synchronized subtitle text without a bottom/backing
dialogue box. The earlier "missing tapped dialogue box" premise was wrong.

## Accepted Baseline

- Runtime: Android 4.4.2/API19 ARM `emulator-5582`.
- Server mode: `LOGIN_RESPONSE=sample`, ports `50005,10001`.
- Main background: fixed by `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile>`.
- Initial unclicked character face: fixed by `<infomation><fairy_pose>2</fairy_pose><fairy_face>5</fairy_face>`.
- Main information panel: driven by `<infomation><message><text|color|size>`.
- BGM/voice: environment baseline is enabled.
- Character tap: expression changes and synchronized subtitle text appears; no backing box is expected.

## Removed Wrong Frontier

Do not investigate these as active bugs:

- tapped character subtitle has no bottom/backing dialogue box
- tap text is missing
- another `message`, `focus`, `link`, `imagefile`, `banner`, `rewards`, or `event_type` field is needed to create that backing box
- APK/layout/resource/emulator changes are needed for the tapped subtitle backing box

## Historical Reports Superseded

The following reports were based on the wrong premise and were removed to avoid
misleading future agents:

- `work/mainmenu-dialog-click-static-20260625.md`
- `work/mainmenu-dialog-message-values-20260625.md`
- `work/mainmenu-dialog-runtime-plan-20260625.md`
- `work/mainmenu-pixie-subtitle-box-static-20260625.md`

Schema/value reports that remain in `work/` are evidence cards only. They are
not active tasks to reopen main-menu visual restoration.

## Next Frontier

Return to post-main-menu gameplay/protocol progression. The current useful
frontier is no longer main-menu visuals, but the next route/scene after the
visible main menu, such as exploration request completion and state-machine
transition work.

Only reopen main-menu visuals if a new run produces one of:

- missing-resource logcat line
- texture/native crash
- screenshot regression against the accepted baseline
