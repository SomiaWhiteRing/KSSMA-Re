# Gacha Buy Schema Card, 2026-07-01

Frontier:
- Accepted success path: `main menu -> gacha_select -> /gacha/buy -> draw -> result -> back/retry`.
- Open trust-boundary path: recover one native-supported rejection response before rejecting invalid product,
  unsupported mode tuples, or insufficient balance.

Runtime evidence:
- `work/kssma-flow-gacha-draw-smoke-gacha-draw-dynamic-3` captured `/connect/app/gacha/buy`
  with `product_id=1`, `bulk=1`, `auto_build=1`.
- Empty scene-forward response crashed in `_AnmGachaAutoCompound::setPropertyValues`.
- Adding only `<final_result><ex_user_card>...` changed the crash to
  `_AnmGachaLakeBall::setPropertyValues`, with stack evidence through `_CPlayer::getUserCard(...)`.
- Adding the same drawn card to response `<your_data><owner_card_list>` passed runtime:
  `work/kssma-flow-gacha-draw-smoke-gacha-buy-owner-card-1`.

Static evidence:
- Scene `9200` is `gacha_gettingcard`; `9300` is `gacha_gettingresult`.
- `layout_gacha_drawcard.xml` binds model `gacha` fields including `finalResult`,
  `compounds`, `completeList`, `completeFull`, and `complate`.
- Native parser symbols include `_GachaBuyTagParser::parse`, `_FinalResultTagParser::parse`,
  `_ExUserCardTagParser::parse`, and `_CompleteListTagParser::parse`.
- `_FinalResultTagParser` consumes `ex_user_card` children.
- `CompleteListTagParser` consumes `cmpsheet_index`, `is_get`, and `is_new`.

Accepted minimal XML shape:

```xml
<gacha_buy>
  <final_result>
    <ex_user_card>
      <serial_id>2</serial_id>
      <master_card_id>9</master_card_id>
      <holo_flag>0</holo_flag>
      <build_exp>0</build_exp>
      <build_lv>1</build_lv>
      <build_cnt>0</build_cnt>
      <is_new_card>1</is_new_card>
    </ex_user_card>
  </final_result>
  <gacha_type>1</gacha_type>
  <telop_message>友情ポイントガチャ</telop_message>
  <complete_list>
    <cmpsheet_index>0</cmpsheet_index>
    <is_get>0</is_get>
    <is_new>0</is_new>
  </complete_list>
</gacha_buy>
```

Required header coupling:
- The drawn card serial must also appear in `<your_data><owner_card_list>`.
- Without this, the draw animation can look up the result card by serial and crash.

Current implementation:
- `server/data/game/gacha.json` holds the accepted same-page friendship and paid entries plus one deterministic
  draw-card baseline.
- Friendship uses the captured tuple `product_id=1, bulk=1, auto_build=1`; paid uses
  `product_id=2, bulk=0, auto_build=0`.
- `/connect/app/gacha/buy` persists one owned card, spends friendship points or MC, appends history, increments
  `stats.cardsDrawn`, and returns scene `9200` with the same serial in `final_result` and `owner_card_list`.
- ARM19 flow artifacts accept friendship settlement/readback, paid settlement/readback, result-page back, and
  paid retry. The success path is deterministic and single-card only.

Non-goals:
- No random pool.
- No 11-pull.
- No comp-sheet reward.
- No album completion.

Next frontier:
- Statically recover the `/gacha/buy` failure parser, wire response, visible dialog, and dismiss/return path.
- Only after that card exists, reject unknown products, tuples other than friendship `(1,1,1)` and paid
  `(2,0,0)`, and insufficient balances before any mutation or write.
