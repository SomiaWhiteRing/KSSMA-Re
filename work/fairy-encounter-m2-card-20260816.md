# Fairy encounter M2 evidence (2026-08-16)

## Hypothesis

If `/exploration/explore` returns the statically recovered `event_type=1` and ordinary
`FairyTagData`, the accepted exploration forward path will enter the original scene 6202 and its
challenge button will emit the original `/exploration/fairybattle` request.

## One changed variable

The existing exploration mutation and `exploration-forward-visual-smoke` scenario were retained.
Only the response event branch was enabled at 100%, with 小龙女 master boss 30024, Lv.18, HP
20000, and 3600-second time limit. No client/native/resource patch was made.

## Checks

- `node --check` passed for `admin-ui.js`, `bootstrap-server.js`, and the server test.
- `conda run -n KSSMA-Re node .\server\test-bootstrap-server.js` passed.
- Browser QA saved and reloaded enabled=true, probability=100, level=18, max HP=20000, and
  time limit=3600. DOM inspection found no horizontal overflow.
- ARM19 first attempt stopped before protocol at `repair-adb`: artifact
  `work/kssma-flow-exploration-forward-visual-smoke-20260816-223714`. No emulator process existed,
  so non-destructive `start-runtime` started the fixed API19 ARM baseline.
- ARM19 accepted artifact:
  `work/kssma-flow-exploration-forward-visual-smoke-20260816-223933`.

## Observed result

- Server response observable: `fairyEncounter=true`, `fairySerialId=100001`,
  `fairyMasterBossId=30024`, `fairyLevel=18`, `fairyMaxHp=20000`.
- Visible UI: `screenshots/after-forward-0200ms.png` shows 小龙女 Lv.18 and HP 20000/20000 on
  the original fairy screen.
- Next route: `/connect/app/exploration/fairybattle`, twice, with decrypted
  `user_id=1`, `serial_id=100001`.
- The endpoint returned 501, producing the visible network retry dialog. The client remained alive;
  there was no server stderr.

## Conclusion and next frontier

The ordinary fairy encounter edge and admin probability/level/HP/time controls are accepted. The
next single frontier is the real `/exploration/fairybattle` response that enters the original battle
scene. Reward settlement must wait for its own result/reward parser closure.
