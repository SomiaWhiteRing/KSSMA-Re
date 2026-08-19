# Gacha Buy Original Balance Dialog Path Card (2026-08-19)

## Scope

- Frontier: `/connect/app/gacha/buy` detects an insufficient currency balance, but the accepted compatibility response only redraws gacha select and cannot show the original modal dialog.
- Success: an encrypted HTTP 200 carrying business error code `1` and a balance message shows the stock `dialog_scene` (`90100`) over the current gacha page; dismissing it returns to that same page without another request or a player-save write.
- Non-goal: gacha prices, currency grants, draw pools, result animation, and any special server error codes other than `1`.
- Stop: if this one statically closed response/native path does not produce a visible dialog, stop at the first client observable and do not sweep XML fields or add another UI patch.

## Accepted Correct Paths

### Stock network-error dialog producer

- `_Main::connect` at `0x001c3386` constructs the stock dialog data and calls `_DialogModel::initDialog` at `0x001c33bc`.
- It obtains the current `_SceneControl` through `_Main::getSceneControl` (`0x001c1de4`).
- At `0x001c3424` it calls `_SceneControl::push` (`0x001f6950`) with literal scene id `90100` from `0x001c34d0`.
- `rule_scene.xml` names `90100` `dialog_scene`; `_LayoutScene::showDialog` at `0x001f3d94` uses the same scene push.
- Dismissal is already closed by the stock type-2 dialog consumer and pops back to its underlying scene.

### Stock gacha-page dialog producer

- `_GachaSelect::drawGacha` at `0x00350830` constructs a type-6 dialog from gacha content, initializes `_DialogModel` at `0x00350972`, then invokes the scene's `showDialog` virtual at `0x003509aa`.
- `_GachaDrawResult::Retry::exec` at `0x0034e22c` uses the same `initDialog -> showDialog` pattern.
- These paths prove that the intended gacha behavior is a modal scene over the current page, not a redirect to a newly built gacha page.

## Current Wrong Path

- `_Main::connect` parses `header/error/code` at `0x001c35b2` and `header/error/message` into a type-2 `DialogData`.
- The generic nonzero branch calls `_DialogModel::initDialog` at `0x001c3ba4`, but immediately destroys its local data and returns through `0x001c395c`; it never pushes `90100`.
- A `header/next_scene=90100` server response cannot repair this: only error code `0`/`10000` reaches the next-scene push at `0x001c388c`; generic code `1` branches around it.
- Gacha select/draw/result all inherit the empty `_LayoutScene::preUpdate` at `0x001f3aa4`, so there is no deferred producer after the response is delivered to the model.

## Adopted Path

- Server sends the parser-minimum encrypted response:

```xml
<response>
  <header><error><code>1</code><message>友情点不足</message></error></header>
  <body></body>
</response>
```

- The `message` is server-owned for this branch. The client binary contains the exact local phrase `MC不足` at `0x003e4e70`; `友情点不足` and `扭蛋券不足` use the same concise wording pattern because their original server text is not present in the client resources.
- During candidate testing this response was gated by `KSSMA_GACHA_BUSINESS_ERROR_DIALOG=1`, while the default retained the user-accepted `gacha_select / 9100` fallback. After visible acceptance and native promotion, both the experiment gate and compatibility fallback were removed; code `1` is now the default product path paired with the unique client baseline.
- Native patch point `0x001c3ba8` is after the accepted `DialogModel::initDialog` call. It replays the overwritten stock `DialogData` cleanup, gates on error code `1`, acquires `_Main`'s `_SceneControl`, pushes `90100`, releases the temporary smart pointer, and returns to stock code at `0x001c3bae`.
- This restores one missing edge of an already accepted full path. It does not reconstruct dialog widgets, touch behavior, or dismissal state.

## Patch/Request Map

```text
POST /connect/app/gacha/buy
  -> settlement rejects without writing player save
  -> encrypted header/error/code=1 + message; empty body
  -> _Main::connect parses type-2 DialogData
  -> _DialogModel::initDialog (0x001c3ba4)
  -> native edge 0x001c3ba8 -> cave 0x003e7fa0
  -> _Main::getSceneControl (0x001c1de4)
  -> _SceneControl::push(90100) (0x001f6950)
  -> original dialog visible over gacha select
  -> dismiss -> same gacha select; no new request
```

## Static Acceptance Gates

- Source library SHA-256 must be `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`.
- Original bytes at `0x001c3ba8` must be `d9a8fef7d5f8` (`add r0,sp,#0x364; bl 0x001c1d58`).
- Cave `0x003e7fa0..0x003e8050` must be all zero in the accepted source and must not overlap the accepted card-result cave ending before `0x003e7f98`.
- Builder must disassemble both the entry branch and cave return to `0x001c3bae`, and print the request/path map. There is no trap.
- Before client execution, installed and source native-library SHA-256 must match.

The builder passed these gates on 2026-08-19. Candidate SHA-256 is
`36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2`; its disassembly shows
`0x001c3ba8 -> 0x003e7fa0`, the code-1 gate, `push(90100)`, smart-pointer cleanup, and return to
`0x001c3bae`.

## Client Observable

- Request sequence ends in exactly one `/connect/app/gacha/buy` response with `command=gacha_buy_rejected`, `errorCode=1`, and `saved=false`.
- Visible UI is the stock modal containing the currency-specific insufficient text.
- Closing the modal returns to the same gacha select page, emits no follow-up route, and leaves currency/card ownership unchanged.

Client execution is pending because both supported test endpoints were absent at the deployment gate:
`emulator-5556` had no classic-emulator process, and MuMu A12 `127.0.0.1:7555` refused the ADB connection.
No runtime was restarted, wiped, reinstalled, or patched during that failed availability check.

## MuMu A12 Candidate Deployment

After the user started MuMu A12, the 2026-08-19 deployment gate passed Android 12/API 32, the ARM bridge,
unchanged physical `1440x2560/360dpi`, package, hosts, resource sentinels, and both server ports. The installed
library first matched the accepted source exactly (`DEC36585...CD40F`). With the game process stopped, the bounded
candidate replaced only that library; device SHA-256 then matched source
`36A4826B...25B69A2`, while mode `755`, uid/gid `1000:1000`, and SELinux
`u:object_r:apk_data_file:s0` remained unchanged.

The server was restarted with `KSSMA_GACHA_BUSINESS_ERROR_DIALOG=1` as PID `8404`; both ports were healthy and
the fingerprint matched. A live encrypted product-1 probe returned HTTP 200, code `1`, message `友情点不足`, empty
body, no next scene/select/buy model, `saved=false`, and byte-identical live save SHA-256
`6845FBB9...5EACB37`. The controller then seeded the exact master-card cache and launched PID `2902` into resumed
`RooneyJActivity`; the ten-second gate found no fatal. At that candidate checkpoint, visible modal and dismissal
acceptance were the only remaining observables.

## Visible Acceptance And Promotion

- The user triggered the real product-1 request from the original gacha page. Server log recorded cookie account 1,
  `product_id=1`, required `200`, available `0`, HTTP 200, `errorCode=1`, message `友情点不足`, and `saved=false`.
- Visible screenshot `work/gacha-business-error-dialog-visible-a12-20260819.png` shows the stock framed modal over
  the dimmed original gacha page with the exact message. PID `2902` remained resumed in `RooneyJActivity`; logcat
  contained no fatal.
- After the user dismissed it, screenshot `work/gacha-business-error-dialog-dismissed-a12-20260819.png` shows the
  same gacha page. `connect_app_probe` stayed `8 -> 8`, gacha log count stayed `8 -> 8`, and the last request remained
  the original `/gacha/buy`; therefore dismissal is route-quiet.
- Live save SHA-256 stayed `87DA37A...13D52DD`, and `LastWriteTimeUtc` stayed
  `2026-08-19T15:42:03.3895054Z`. The process remained alive and no fatal appeared.
- The user explicitly confirmed both “弹窗已出现，一切正常” and “已关闭，页面正常”.

The candidate was promoted to the unique baseline:

- native: `work/librooneyj-gacha-business-error-dialog.so`, SHA-256
  `36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2`;
- APK: `work/client-baseline/KSSMA-Re-client-baseline.apk`, SHA-256
  `E8723F5438AFC6D39F4E0913159D2EE7B3BC4F097BD2F5A1E48DE31687C2DCC3`;
- server: experiment gate/fallback removed; a fingerprint-clean default restart as PID `29168` returned the same
  encrypted code-1 response with a byte-identical live save.

Final reproducible checks passed: `node server/test-bootstrap-server.js`, the native builder's original-byte/cave/
branch-map gates, Python bytecode compilation, `git diff --check`, and MuMu A12 `status` on `127.0.0.1:7555`.
The latter reported Android 12/API 32 with `libnb.so`, package/hosts/resources healthy, both server ports reachable,
and no warnings. The rebuilt APK's `lib/armeabi/librooneyj.so` hash is the accepted native hash above.
