Route: `/connect/app/menu/haveparts`

Frontier: Menu page -> parts list -> return. The empty scene skeleton opened scene `31100` but showed a full-screen no-data overlay, blocking the return button and the next menu entry.

Static anchor: `_HavePartsTagParser::parse` at `0x0030177c`, `_PartsListTagParser::parse` at `0x00308908`, `_PartsTagParser::parse` at `0x003082e4`, and `layout_parts_list.xml`.

Native owner: `/menu/haveparts` uses command `partslist` and scene `31100`. The parser-owned body node is `<have_parts>`.

Parser path:
- `_HavePartsTagParser::parse` scans children of `<have_parts>`.
- Child `<lake>` is parsed by `_LakeTagParser::parse` from the lake node's first child and pushed into the HaveParts lake vector.
- `_PartsListTagParser::parse` scans `<parts_list>` children named `<parts>`.
- `_PartsTagParser::parse` reads each `<parts>` item's scalar fields.

Expected parent:
- `<body><have_parts>...</have_parts></body>`

Confirmed fields:
- `select_lake_id` | integer | required for selected lake state | string `select_lake_id`, store to HavePartsTagData offset `+0`
- `leader_card_id` | integer | required for selected knight/card display | string `leader_card_id`, store to offset `+4`
- `select_parts_num` | integer | required for selected parts focus | string `select_parts_num`, store to offset `+8`

List nodes:
- `have_parts/lake` -> parsed by `_LakeTagParser::parse`; stored in the model's `lakes` vector.
- `lake/parts_list/parts` -> fields `parts_num`, `parts_have`; `_PartsListTagParser::parse` calls `_PartsTagParser::parse` for each `<parts>` child.

Model/layout consumers:
- `_PartsModel::init` copies the three top-level scalars and lake vector.
- `_PartsModel::getMap` exposes `lakes`, `requireWin`, `selectLake`, `selectLakeId`, `leaderCardId`, and `selectPartsNum`.
- `layout_parts_list.xml` binds `card_base` to `selectLake`, `lakes`, `floor`, `win`, and `requireWin`; `parts_list` binds `list=parts_list` and `focus=p_focus`.

Value source:
- `work/million_cn/apktool/assets/bundle/local_battle_area.xml` contains a parser-compatible lake row: `lake_id=2`, `title=花を愛す者`, `master_card_id=179`, `complete=0`, and nine `<parts>` rows with `parts_num=1..9`.
- The local resource dump contains `adv_chara179`, `thumbnail_chara_179`, and `face_179`, so `master_card_id=179` has corresponding client assets.

Rejected shapes:
- Empty `<body></body>` for `/menu/haveparts`: runtime artifact `work/kssma-flow-menu-buttons-tail-smoke-menu-tail-side-menu-return` showed a blocking `无资料可显示` overlay after opening the scene; return and next menu entry were blocked.
- Side-menu return from the blocked overlay: the overlay consumed input and produced no `/connect/app/menu/menulist` route.

Minimal XML candidate:
```xml
<body>
  <have_parts>
    <select_lake_id>2</select_lake_id>
    <leader_card_id>179</leader_card_id>
    <select_parts_num>1</select_parts_num>
    <lake>
      <lake_id>2</lake_id>
      <title>花を愛す者</title>
      <master_card_id>179</master_card_id>
      <complete>0</complete>
      <parts_list>
        <parts><parts_num>1</parts_num><parts_have>1</parts_have></parts>
        ...
        <parts><parts_num>9</parts_num><parts_have>0</parts_have></parts>
      </parts_list>
    </lake>
  </have_parts>
</body>
```

Observable for runtime check:
- `menu-buttons-tail-smoke` opens `/connect/app/menu/haveparts`, screenshot is the parts list rather than the no-data overlay, return emits `/connect/app/menu/menulist`, and the flow continues to later menu entries.

Open questions:
- Real factor ownership and multiple lake progression belong to a later battle/factor subsystem pass.
