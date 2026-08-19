# MuMu A12 launch-time master-card seed path (2026-08-19)

## Bounded round

- Frontier: a MuMu A12 process start can consume and remove `save/database/master_card`; a later cold start then
  builds card lookups without the recovered table and fairy battle resolves `master_card_id=600` to
  `adv_chara0`.
- Success: every controller-owned client start stops the process, restores the exact recovered table when it is
  missing or different, verifies the device SHA-256, and only then starts the original Activity. The same rule must
  cover `install-client`, `launch`, and the isolated A12 flow runtime gate.
- Non-goal: do not change card-update XML, server revisions, battle XML, client/native code, display settings, BC,
  drops, rare fairies, or multiplayer behavior.
- Stop: stop after two controller changes without a new seed hash, route, logcat, Activity, or visible battle
  observable.

## Accepted correct path

The recovered source is:

```text
work/million_cn/sdcard_dump/sdcard/Android/data/com.square_enix.million_cn/files/save/database/master_card
bytes=260249
sha256=7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF
```

Its accepted device destination is:

```text
/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save/database/master_card
```

The original resource/bootstrap path can consume this serialized 480-card cache before the main menu and remove the
external file on some startup/update paths. The exact preload function symbol is not named, so this round does not
patch or reimplement that native path. It only restores the already accepted input before process start and lets
the original client execute its complete loader/card-manager path.

The decisive user-driven differential was:

```text
missing consumed cache -> fairy master_card_id=600 -> adv_chara0 -> strict-JNI abort
exact cache restored before process start -> battle renders and reaches the result screen
```

Fairy serial `100013` then proved that the client had crossed the texture-null blocker: the local victory reached
the visible result screen. A subsequent server-only winner mapping correction (`winner=1`) was accepted by the
user as normal battle and settlement. This is stronger than the earlier diagnostic flow that copied a card file
but still produced `thumbnail_chara0`; that earlier run did not establish the same stopped-process/pre-start
boundary and cannot reject the later exact-path result.

## Wrong-path connection

`install-resources` extracts the correct file, but the client intentionally removes it after loading. Existing
`install-client`, `launch`, and `Invoke-MumuFlowRuntimeGate` did not restore it at their final stopped-process
boundary. A manual icon start or a later controller start could therefore enter the original loader without its
one-shot input.

The controller fix belongs immediately between `am force-stop` and `am start`:

```text
controller entry
-> am force-stop com.square_enix.million_cn
-> hash exact device target
-> push only when missing/different
-> verify SHA-256
-> original LogoActivity / original flow launch
```

`status` must continue to use persistent sentinels such as `database/master_boss`; the consumed card seed is an
audited launch precondition, not a persistent resource-health sentinel.

## Observable and upgrade boundary

The minimum reproducible observable is a controller JSON stage/event containing the exact expected and device
SHA-256 before the Activity starts. A user-driven battle after that cold start must avoid `adv_chara0` and reach
battle/result, or produce a new exact blocker.

This makes controller-owned starts repeatable. Launching the app directly from the MuMu home screen without first
using the controller remains outside this fix; making arbitrary third-party Activity starts self-seed would require
a separately reviewed client/bootstrap change.

## Result

- `build-mumu-a12-resource-pack.py` emitted schema 2 while retaining the accepted TAR SHA-256
  `FF60551898A285A355ECEC0E4C38624BA9999A6A19A6CB668CF8C7C9E66519CF` and checksum-list SHA-256
  `71E8B7DB5820CD9811F04BFF191B699798B0EB5011834B8C2A5C8605DDB09AF5`.
- `kssma-mumu-a12.ps1 self-check` passed nine checks and printed the exact seed hash.
- An exact device-side fault injection moved the hash-verified target to
  `master_card.before-kssma-launch-seed-selfcheck-20260819`. The normal
  `kssma-mumu-a12.ps1 launch -StartServer` then observed the missing target, pushed 260,249 bytes, verified
  `7B121D...B3A56BDF`, and reported `restored=true` before Activity start.
- PID 3012 survived in `RooneyJActivity`; `work/kssma-mumu-a12-last-launch.png` visibly shows the normal main menu.
  The launch log contained no `adv_chara0`, `thumbnail_chara_0`, fatal signal, `SIGABRT`, or `SIGSEGV`.
- The temporary backup was deleted after both target and backup hashes matched. The accepted target remains present.

Conclusion: the controller-owned installation/start/flow boundary is fixed and reproducible. A gameplay flow
artifact is still desirable, but the user has already accepted the same exact-preload battle and the corrected
settlement screen. The next product frontier can move to BC once this runtime baseline is not bypassed.
