# Gacha Buy Schema Card, 2026-07-01

> 2026-08-19 supersession: the deterministic single-card implementation below is retained as historical schema
> evidence. Current settlement supports weighted product pools and repeated `ex_user_card` rows for MC 11-draw;
> see `work/fairy-gacha-pool-path-card-20260819.md`. The existing friendship/MC single visible flow remains accepted,
> while ticket/11-draw rendering and the client-visible rejection dialog remain open.

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
- `server/data/game/gacha.json` holds one same-page list with friendship, MC, ticket, and MC 11-draw products, each
  with a fixed currency/draw-count contract and an independently editable weighted pool.
- Friendship uses the captured tuple `product_id=1, bulk=1, auto_build=1`; paid uses
  `product_id=2, bulk=0, auto_build=0`.
- `/connect/app/gacha/buy` preflights product, currency, card capacity, and pool IDs; it then persists exactly the
  configured result count, spends friendship points/MC/tickets, appends one history row per card, increments
  `stats.cardsDrawn`, and returns scene `9200` with every serial repeated in `final_result` and `owner_card_list`.
- ARM19 flow artifacts accept friendship settlement/readback, paid settlement/readback, result-page back, and
  paid retry. Flow assertions now accept any recovered card in the configured product pool.

Current remaining boundaries:
- Ticket single and MC 11-draw require visible client flow acceptance.
- Historical original pool weights are unknown; current weights are an explicit local editable baseline.
- No comp-sheet reward.
- No album completion.

Next frontier:
- Statically recover the `/gacha/buy` failure parser, wire response, visible dialog, and dismiss/return path.
- Server settlement already rejects unknown products, insufficient balances, invalid pools, and insufficient card
  capacity before mutation. Only the correct client-visible error/dialog presentation remains blocked on G1.
