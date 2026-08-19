# Fairy drop and gacha pool path card (2026-08-19)

## Bounded round

- **Frontier:** `fairy defeat -> contributor reward roll -> reward box` and
  `gacha select product -> gacha/buy -> weighted card result` still use one deterministic card.
- **Success:** the fairy encounter snapshots an overall card-drop percentage and a weighted card pool; every
  contributor/finisher reward slot rolls independently and only successful rolls become idempotent reward-box
  notices. The gacha select exposes every locally supported consumption mode, and every product atomically spends its
  configured currency and draws from its own weighted pool. The admin can edit both systems without restarting Node.
- **Non-goal:** original historical rate claims, holographic-card probability, gacha completion-sheet rewards, and a
  guessed client-visible insufficient-balance/error dialog.
- **Stop:** if a product cannot be expressed by the already accepted four-integer select behavior and the repeated
  `final_result/ex_user_card` parser, keep it server/admin-only and do not patch native code or invent a response.

## Accepted client paths reused

### Fairy reward box

```text
exploration/fairybattle
-> shared raid defeat
-> one reward decision per contributor slot (+ finisher slots)
-> menu/rewardbox
-> menu/get_rewards(notice_id)
-> unique owned-card serials
```

The shared-raid path, type-1 card reward schema, notice ownership, and idempotent claim write are already accepted in
`work/fairy-shared-raid-account-path-card-20260819.md`. This round changes only how the defeated raid creates its
immutable reward rows. Claim and client XML stay on the accepted path.

The encounter is the correct snapshot boundary: strength, lifetime, and current reward card already copy from runtime
configuration into encounter -> raid. `rewardDropRatePercent` and `rewardCardPool` must follow that same path so an
admin edit cannot retroactively change a live raid or reroll an already defeated raid.

### Gacha select and result

```text
gacha/select/getcontents
-> content behavior product_id,bulk,auto_build,link
-> gacha/buy(product_id,bulk,auto_build)
-> repeated final_result/ex_user_card
-> scene 9200 draw/result
```

Two real-client paths close the calling convention:

- friendship behavior `1,1,1,0` emits `product_id=1, bulk=1, auto_build=1`;
- MC behavior `2,0,0,0` emits `product_id=2, bulk=0, auto_build=0`.

The bundled `local_gachaselect.xml` additionally contains the original gold-ticket slot with the same four-integer
behavior but leaves its product ID as a server integration placeholder. Its Japanese text says one gold ticket is
consumed. Assigning local product ID `3` changes only server-owned product data; it does not invent a native enum or
calling convention.

The recovered `FinalResultTagParser` consumes repeated `ex_user_card` rows. Product ID `4` therefore represents the
MC 11-draw product while reusing the same `/gacha/buy` callback and result vector. Historical material corroborates
that tickets are single-draw only and MC supports a 10+1 draw at 3000 MC. This evidence classifies the product modes;
it does not establish original per-card rates.

Historical corroboration used only for product shape/cost, not for rates:

- PlayStation Blog, first discounted 11-draw campaign and normal 3000 MC cost:
  https://blog.ja.playstation.com/?p=7690
- Contemporary Chinese guide, friendship gacha at 200 friendship points:
  https://wap.gamersky.com/gl/Content-314238_2.html
- Contemporary Chinese guide, ticket single-draw versus MC 10+1:
  https://www.duote.com/tech/24/69025.html

## Adopted local product baseline

| product | mode | request behavior | currency | cost | result count |
| ---: | --- | --- | --- | ---: | ---: |
| 1 | friendship single | `1,1,1,0` | friendship points | 200 | 1 |
| 2 | MC single | `2,0,0,0` | MC | 300 | 1 |
| 3 | gold-ticket single | `3,0,0,0` | gacha ticket | 1 | 1 |
| 4 | MC 11 draw | `4,0,0,0` | MC | 3000 | 11 |

All four are entries in one product table. Currency field names, behavior tuples, draw counts, and result gacha types
are fixed protocol data. Admin editing is limited to cost and weighted pool so it cannot silently remap a button to a
different currency or callback.

## Probability contract

- A card pool is a non-empty list of unique recovered `master_card_id` values and positive integer weights.
- Selection uses one cryptographic integer in `[0,totalWeight)`. The admin displays normalized percentages, while
  stored integer weights avoid floating-point drift.
- Fairy `rewardDropRatePercent` is an integer `0..100`. Every base contributor slot and every finisher bonus slot first
  rolls this percentage, then selects one card from the snapshotted weighted pool on success.
- Successful identical fairy rolls for one account are grouped into one reward-box notice. A zero-success contributor
  has no pending notice; no placeholder item is emitted.
- Gacha has no no-drop outcome: every configured draw selects exactly one pool card. The product's draw count controls
  how many `ex_user_card` rows and owned-card serials are committed.

The initial weights are a deliberately local, editable baseline over resource-backed master IDs `9`, `22`, and `600`.
They are not represented as recovered original rates in formal JSON.

## Atomicity and failure boundary

Settlement always mutates a cloned save first. Pool validation, recovered-card validation, currency availability, and
card-capacity checks occur before the real save path is replaced. This prevents partial 11-draw grants. The already
recorded gacha G1 gap still prohibits claiming that an insufficient purchase has a correct visible client dialog;
this round may fail closed server-side but must describe that presentation as unaccepted.

## Minimum observables

- Server self-check fixes deterministic RNG inputs and proves no-drop, weighted selection, finisher grouping,
  idempotent claim, all four product costs, 11 distinct serials, and full rollback on a rejected settlement.
- Admin HTTP self-check edits the fairy and gacha pools in isolated files and proves invalid/unknown card IDs do not
  replace either file.
- The existing gacha layout check must report no overlap after the two additional original-resource buttons.
- Real-client acceptance remains a separate flow edge: select each newly exposed product, observe exact product ID,
  and for product 4 prove all repeated result cards survive scene 9200/result rendering.

## Implemented result

- `server/data/server/runtime-config.json` now stores `rewardDropRatePercent` plus `rewardCardPool`; encounter and raid
  snapshots carry both through defeat so live raids cannot be rerolled by an admin edit.
- `server/data/game/gacha.json` is the sole price/pool source for products 1 through 4. Stale price fields were removed
  from the default player save.
- `/admin/` exposes the fairy rate/pool and four gacha price/pool panels. Pool text uses
  `master_card_id:weight`, displays normalized chance, and the API rejects empty/duplicate/unknown-card pools before
  atomic replacement. Generated inline JavaScript is compiled by the server self-check.
- `/gacha/buy` preflights the full purchase and emits repeated result/owner-card rows. A failed 11-draw never grants a
  prefix of cards or spends currency.
- Existing gacha flow assertions now validate configured-pool membership and cross-check the same dynamic card ID in
  request logs, player save, and roundtable owner-card readback.

Checks:

```text
node .\server\test-bootstrap-server.js
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario self-check -Tag gacha-pool-selfcheck
C:\Users\jsyzd\miniconda3\envs\KSSMA-Re\python.exe work\render-gacha-select-layout-html.py --check
```

All passed. Flow artifact: `work/kssma-flow-self-check-gacha-pool-selfcheck/summary.json`. A local-browser load of
`/admin/` rendered four product panels, loaded every normalized pool, and reported no console errors. No emulator run
was performed in this round; ticket/11-draw visible acceptance remains the next flow edge.
