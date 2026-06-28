# Flow Scenario Guide

`work/kssma-runtime.ps1 flow` is the default gameplay acceptance harness. A flow
scenario should start from the main menu and reuse the shared runtime plumbing
instead of copying login, server, ADB, or artifact code.

## User Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario list
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario self-check
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-walk-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-forward-visual-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-floor-clear-smoke
```

## Scenario Contract

- `list` and `self-check` must not touch ARM19 or the local server.
- Runtime gameplay scenarios own the local `bootstrap-server.js` process.
- Runtime gameplay scenarios call the shared runtime gate and login-to-main-menu stage before gameplay taps.
- Runtime gameplay scenarios use an artifact-local player save. The default exploration smoke
  starts like a new player: only `人魚の断崖` and its first unlocked floor are visible.
- Deep exploration scenarios may use `KSSMA_EXPLORATION_MOVES_SEED`, but the seed is only an
  initial minimum; it must not overwrite higher progress saved during the same run.
- A gameplay step waits for a route, decrypted params, or response metadata; screenshots are milestone/failure evidence, not the pass condition.
- Failures must use a stable class such as `runtime-not-ready`, `server-start-failed`, `login-failed`, `route-timeout`, `route-param-mismatch`, `tap-no-effect`, `native-baseline-mismatch`, `client-crash`, or `resource-miss`.
- Every run writes `summary.json`, `summary.txt`, `events.jsonl`, `requests.jsonl`, `server.out.log`, `server.err.log`, `logcat.txt`, `activity.txt`, and key screenshots.

## Adding A Scenario

1. Add one scenario entry to `Get-FlowScenarioCatalog`.
2. Add one `Invoke-Flow<FeatureName>` function that starts after main menu.
3. Dispatch it from `Invoke-Flow` after `Start-FlowServer`, `Invoke-FlowRuntimeGate`, and `Invoke-FlowLaunchAndLogin`.
4. Use `Invoke-FlowTapThenWaitProbe`, `Wait-FlowServerEvent`, `Wait-FlowServerQuiet`, and `Capture-FlowScreenshot` instead of ad hoc ADB loops.
5. Add or update the smallest self-check that proves new log parsing or matching behavior.

Do not create a separate login driver for gacha, shop, exploration depth, or any
other gameplay system.
