# MuMu Android 12 automated-flow qualification card (2026-08-18)

## Bounded round

- Frontier: determine whether the running MuMu Android 12 instance at `127.0.0.1:7555` can replace ARM19 as
  the complete automated gameplay-acceptance runtime.
- Success: reuse the accepted flow plumbing for at least one stateful exploration edge and one gacha settlement/
  owned-card edge, with the normal route, scene, screenshot, save, Activity, logcat, and summary observables.
- Non-goal: do not delete or weaken ARM19 gates, invent placeholder resource zeroes, change product XML/native
  behavior, or promote A12 after startup-only evidence.
- Stop: stop after two runtime adaptations without a new observable, or after a deterministic client fatal proves
  that a representative gameplay edge cannot complete.

## Isolated A12 flow profile

`work/kssma-mumu-a12.ps1` now exposes the shared scenarios through a separate entry:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 flow -Scenario exploration-walk-smoke -Tag qualification-exploration-walk-2
```

The process-local profile keeps the ARM19 controller unchanged. Its runtime gate requires API 31/32, x86_64 plus
the working 32-bit ARM bridge, the exact installed native SHA-256, package/hosts/full-resource health, and both
device-side server health checks. The flow still owns `bootstrap-server.js`, player save, request/event logs,
screenshots, Activity, and logcat.

MuMu's physical portrait surface is `1440x2560` at density 360. The current profile treats that as immutable: it
only reads `wm size`/`wm density`, rejects any `Override size` or `Override density`, and never issues a display
mutation. Existing 1280x720 scenario coordinates are multiplied by two before device input. UIAutomator node
coordinates are already physical and bypass scaling. Each capture retains a 2560x1440 `.native.png` and creates a
1280x720 comparison copy for the existing visual gates.

An earlier qualification attempt temporarily applied `720x1280` / density 240. That override was reset on
2026-08-18, and its exploration pass below is historical compatibility evidence only, not native-display
acceptance. Probe screenshot: `work/kssma-a12-display-probe.png`.

## Experiments

### Exploration attempt 1: valid route chain, then exact fairy resource fatal

Artifact: `work/kssma-flow-exploration-walk-smoke-mumu-a12-qualification-exploration-walk`.

The run reached login and the full first walk request path:

```text
/exploration/area
-> /exploration/floor area_id=0
-> /exploration/get_floor area_id=0 floor_id=2 check=1
-> /exploration/explore area_id=0 floor_id=1
-> /exploration/fairybattle user_id=1 serial_id=100001
```

The adjustable server runtime configuration currently had fairy encounters enabled at 100%, so this supposedly
ordinary exploration scenario inherited a fairy event. The client then requested the nonexistent external resource:

```text
/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save/download/image/adv/adv_chara0
```

Android 12 reported a pending `JResourceLoader.loadFile/loadBitmap` RuntimeException, then strict JNI rejected a
null `GetObjectClass` and aborted the process with `Fatal signal 6 (SIGABRT)`. This is a concrete gameplay/client
data-path fatal, not a route timeout or an unexplained emulator disconnect.

To make ordinary exploration deterministic, the shared flow now gives only the ordinary exploration/progress
scenarios a process-local `KSSMA_FAIRY_ENABLED=0`. `fairy-battle-smoke` retains its explicit enabled/rate/strength
environment, and the special forward-visual scenario is not changed.

### Exploration attempt 2: historical pass under a temporary display override

Artifact: `work/kssma-flow-exploration-walk-smoke-mumu-a12-qualification-exploration-walk-2`.

The unchanged product path passed in 137.536 seconds. Observable route order was:

```text
post_devicetoken -> login -> area -> floor -> get_floor
-> explore -> explore -> area -> floor
```

Both forward actions persisted. The response/save moved from 0 to 10% and then 20%; the final area/floor readback
reported the same 20% progress. Screenshots stayed at 1280x720, the expected Activity remained alive, and final
logcat collection found no fatal. It proved scenario reuse was possible, but it no longer accepts the current
native-display profile.

### Gacha attempt 1: harness-only false failure

Artifact: `work/kssma-flow-gacha-settlement-deck-smoke-mumu-a12-qualification-gacha-settlement`.

This run stopped in 11.730 seconds before launch because the accepted shared flow reads optional ADB result
properties while its new caller still had PowerShell `StrictMode Latest`. The A12 entry now invokes the shared flow
under its original non-strict compatibility mode; the MuMu installer and gates remain strict. This artifact is not
client or A12 gameplay evidence.

### Gacha attempt 2: atomic server settlement, then exact card lookup/resource fatal

Artifact: `work/kssma-flow-gacha-settlement-deck-smoke-mumu-a12-qualification-gacha-settlement-2`.

The rerun reached the expected flow edge:

```text
/gacha/select/getcontents
-> /gacha/buy product_id=1 bulk=1 auto_build=1
```

The server atomically persisted the correct draw: friendship `400 -> 200`, new card serial `2`, master card `9`,
owned-card count `2`, and `cardsDrawn=1`. Immediately after the successful buy response, the client instead tried
to load:

```text
/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save/download/image/card/thumbnail_chara_0
```

`thumbnail_chara_9` is present in both the local resource package and the device payload, while
`thumbnail_chara_0` is absent. Logcat again recorded a pending `JResourceLoader` RuntimeException, strict-JNI null
`GetObjectClass`, and `Fatal signal 6 (SIGABRT)`. Because the response and saved player card both identify master
card 9, the current frontier is why the A12 client-side master/card lookup resolves that draw to zero. Adding a
guessed `thumbnail_chara_0` placeholder would hide the observable and is not an accepted fix.

### Native-display gacha diagnosis: display and consumed-master hypotheses rejected

Artifact: `work/kssma-flow-gacha-settlement-deck-smoke-mumu-a12-native-resolution-master-card`.

The device had only physical `1440x2560` / density 360 and no override. That diagnostic runtime-gate attempt copied
the original 260249-byte `database/master_card`; the request and settlement again contained `masterCardId=9`, but
the client still requested `thumbnail_chara_0` and strict-JNI aborted. At the time the copy was removed because the
run did not change its observable.

Later stopped-process, pre-start restoration produced the decisive fairy differential: the same exact source/hash
removed `adv_chara0`, let the original battle render, and reached the result screen. Therefore the earlier gacha run
rejects only that run's timing/state as a fix for gacha; it does not reject the serialized cache as a process-start
input. The controller now enforces the exact stop -> hash/restore -> verify -> start boundary. Gacha result remains
pending a replay under that accepted launch boundary.

### Native-display fairy battle diagnosis: server victory, client aborts before result

Artifact: `work/kssma-flow-fairy-battle-smoke-mumu-a12-native-resolution-settlement-diagnosis`.

Native coordinate scaling reached the expected route chain through
`/exploration/fairybattle(user_id=1,serial_id=100001)`. The server atomically settled a local-player victory:
`playerWon=true`, the then-current `winner=0`, fairy HP `6000 -> 0`, player HP `5620 -> 4620`, Gold `18 -> 795`,
and EXP `3 -> 7`.
The A12 process requested missing `adv_chara0` and strict-JNI aborted before it could render battle or settlement.
The later timed screenshots show MuMu Store after foreground fallback and are explicitly invalid as gameplay
evidence.

The bundled `local_battle_result.xml` originally suggested that `winner` might identify the winning player index,
but that was only an inference because this A12 run crashed before a result screen. The later user-driven A12 run
did reach the result: a server-confirmed local victory with `winner=0` visibly rendered `YOU LOSE`. That direct UI
observable supersedes this qualification-time inference; the accepted mapping is now `1=local victory` and
`0=local defeat`.

## Conclusion

MuMu Android 12 cannot replace ARM19 as the complete automated gameplay-acceptance runtime yet. It now has a
reproducible native-display flow entry and can navigate the original UI at 2560x1440 without mutating the emulator.
Its earlier complete stateful exploration pass used a temporary override and must be replayed under the native
profile before acceptance. The fairy zero-ID edge is fixed for controller-owned cold starts and has reached normal
battle/settlement in user testing; gacha result and the older delayed reward-box crash remain open.

ARM19 remains the default. Promotion requires, in order:

1. Rerun `fairy-battle-smoke` under the new controller-owned launch seed to turn the accepted human result into a
   full flow artifact.
2. Rerun the drawn `masterCardId=9` result under the same launch boundary; only if it still constructs
   `thumbnail_chara_0` should card-result binding reopen.
3. Rerun `gacha-settlement-deck-smoke` to completion on A12, preferably with the user
   performing the original UI clicks while flow/ADB only observes.
4. Recheck the previously observed approximately 269-second gacha-select/reward-box stability condition.
5. Run a broader representative matrix covering main-menu navigation, exploration state variants, battle/result,
   gacha result/back/settlement, and deck edit/save before changing the default runtime.
