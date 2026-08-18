# MuMu A12 master-card refresh classifier (2026-08-18)

## Frontier and flow edge

```text
login advertises card_rev=0
-> client skips /connect/app/masterdata/card/update
-> fairybattle returns fairy master_card_id=600
-> VS texture path becomes adv_chara0
-> Android 12 strict JNI aborts
```

This round tests only whether making the server's card revision newer than the packaged `save_version`
causes the original client updater to initialize card master data correctly. Fairy stats, battle XML,
winner semantics, resources, APK/native code, all other master revisions, and emulator display settings are
non-goals.

## Accepted correct path to reuse

- The archived clean-start run with `LOGIN_RESPONSE=sample`, before `save_version` and `master_*` were preloaded,
  observed the original client issuing `/connect/app/masterdata/card/update`, followed by boss, card-category,
  and item updates. Preloading those files then made the client skip the same updater and reach main menu scene
  2100. Evidence is indexed in `docs/reverse-archive/startup-mainmenu-20260624-20260625.md`.
- The current server already maps `/connect/app/masterdata/card/update` to the recovered
  `save/database/master_card` binary and returns it through the accepted AES-128-ECB connect/app transport.
- The A12 packaged `save_version` starts with card revision 231. The normal login currently suppresses every
  advertised revision to zero, so the client has no reason to execute the updater.
- This classifier reuses the complete native version-check/request/callback path. It does not synthesize a scene,
  write a card-table field, add `adv_chara0`, or patch a lookup result. The native request's exact route identifier
  and callback symbol have not yet been named; therefore the switch is diagnostic-only, defaults off, and cannot
  be promoted to the product baseline solely from a request string.

## Wrong-path and correct-path connection

The wrong path enters at login revision suppression. The only changed value is `<card_rev>`: zero becomes 232,
one greater than the packaged revision 231. All `boss_rev`, `item_rev`, `card_category_rev`, `gacha_rev`,
`privilege_rev`, and resource `<revision>` fields remain zero. If the client's native comparison succeeds, it
must choose its own existing card-update request and parser before entering scene 2100.

## Falsifiable hypothesis and observables

Hypothesis: on A12, a master file copied before launch is consumed without populating the live card table, while
the original update callback does populate it. After a single card update, the same fairy `master_card_id=600`
will resolve to a nonzero image ID.

Minimum observables:

1. Login response log records advertised card revision 232.
2. The next startup emits exactly `/connect/app/masterdata/card/update`; no other master/resource updater is
   awakened by the experiment.
3. A user-driven fairy battle does not request `adv_chara0`; the Activity either reaches battle/result or produces
   a new, exact blocker.

The device `save_version` is backed up before the run. If no card-update route appears, or if one update completes
but the battle still requests `adv_chara0`, this hypothesis is rejected. Do not try a second revision-only patch;
restore the version file, record the run, and move to a read-only native card-table initialization differential.

## Result: transport reached, payload contract rejected

- The server advertised only `card_rev=232`; login recorded every other revision at zero.
- The client sent `/connect/app/masterdata/card/update` with decrypted local `revision=231`. The server returned
  the recovered 260,249-byte `database/master_card` payload (260,256 bytes after AES padding), and the client
  remained alive at the main menu with no immediate resource or JNI exception.
- The user then reproduced the same fairy edge. The server received serial `100009`, returned valid
  `master_card_id=600`, enemy `type=30024`, image id 600, and saved a local victory. The client still attempted
  `save/download/image/adv/adv_chara0`, hit `GetObjectClass(null)`, and aborted.
- The external `master_card` was consumed after update and `save_version` retained its original hash; neither is a
  new error. The diagnostic server was restarted with the override absent and now advertises revision zero again.

Artifact: `work/mumu-a12-master-card-refresh-rejected-20260818` (`server.log`, `logcat.txt`).

Subsequent native inspection changes the interpretation: `ResourceDownloader::parseMasterCardTagData` at
`0x003923BD` passes the response bytes to `_TXmlParser::parse`, then `_MasterDataTagParser::parse`, creates `_Card`
objects, and calls the card manager's `updateMasterCardList` callback. The server's binary cache is therefore not a
valid wire payload. The unchanged `save_version` hash corroborates that no master-data revision was accepted.

Conclusion: the version trigger worked, but the current endpoint contract is wrong; the update-callback hypothesis
was not actually tested. Do not try another revision value. Recover the parser-backed card-update XML and rerun the
same revision edge with only the response representation changed.
