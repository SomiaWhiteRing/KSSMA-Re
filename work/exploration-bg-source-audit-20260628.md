Route:
`/connect/app/exploration/get_floor`

Frontier:
Recover the value domain for per-area walking background images. User-provided
screenshots show `人魚の断崖 エリア1/2` using `adv_bg14`, while `人魚の断崖
エリア3` uses `adv_bg26`; the current server still maps one background per
outer region.

Static anchor:
`bg` -> `GetFloorTagData.bgName` -> `layout_exploration_main.xml`
`<exploration_bg><param name="bgName" value="bgName" />`

Local sources checked:
- `rg -a` over repo text/binaries for `adv_bg14`, `adv_bg26`,
  `adv_bg_fog14`, `adv_bg_fog26`, `人魚の断崖`, `dungeon_rev`,
  `master_dungeon`, `exploration_bg`, `bgName`.
- `work/million_cn/apktool/assets/bundle/rule_resource_route.xml`
- `work/million_cn/apktool/assets/bundle/rule_resource.xml`
- `work/million_cn/apktool/assets/bundle/local_battle_player.xml`
- `work/million_cn/apktool/assets/bundle/layout_exploration_main.xml`
- `work/million_cn/sdcard_dump/.../save/database/*`
- `work/background-candidates/adv-bg.tsv`

Confirmed local facts:
- `layout_exploration_main.xml` binds the walking background component to the
  model field `bgName`.
- Native strings include `bgName`, `adv_bg%d`, `adv_bg_fog%d`, and resource pack
  patterns `advbg%d_%d.pack`, proving these are intended resource names.
- `rule_resource_route.xml` maps prefix `adv` to `save/download/image/adv/`.
- `local_battle_player.xml` advertises `resource_rev filename=advbg` and
  `dungeon_rev area_id=0..6`, implying original service had dungeon/exploration
  update data not present in the current local save database.
- `adv_bg14` is present in `assets/pack/148/advbg/advbg0_1.pack` and the
  decoded dump as `save/download/image/adv/adv_bg14`, 960x640.
- `adv_bg26` is present in `assets/pack/148/advbg/advbg0_3.pack` and the
  decoded dump as `save/download/image/adv/adv_bg26`, 960x640.
- `adv_bg_fog14` and `adv_bg_fog26` also exist as 960x640 variants.

Rejected or missing local evidence:
- No local text/binary reference was found that maps `人魚の断崖 エリアN` to
  `adv_bg14`, `adv_bg26`, or any other concrete `adv_bg*` value.
- Current `save/database` only contains `master_boss`, `master_card`,
  `master_cardcategory`, `master_combo`, `master_item`, and `master_scol`; there
  is no recovered `master_dungeon` / exploration master table in the local dump.
- `rule_resource.xml` only contains generic scene resource dependencies such as
  `exp_sarch.png` and occasional fixed `adv_bg6.png`; it is not an area
  background map.
- Existing wiki-derived `File:area1.jpg` through `File:area6.jpg` refs are outer
  area/list/map art, not proven walking backgrounds.

Network sources checked:
- atwiki `探索攻略` lists exploration mechanics and per-area AP/EXP/Gold/drop
  rows for `人魚の断崖`, but no background image/resource mapping.
- FC2 3DS wiki cached locally gives per-area mechanics; no background mapping.
- Fandom `探索` cached locally gives the six-region mobile/CN table and
  `File:areaN.jpg` outer images; no walking background mapping.
- Google/web search for `人魚の断崖 エリア1/エリア3 adv_bg/背景` found mechanics
  tables and screenshots, but no authoritative area-to-resource table.

Current accepted external visual evidence:
- User screenshot: `人魚の断崖 エリア1` visually matches `adv_bg14`.
- User screenshot: `人魚の断崖 エリア3` visually matches `adv_bg26`.

Conclusion:
No authoritative local or network area-to-background table was recovered in this
pass. The most likely missing canonical source is original dungeon/exploration
update data referenced by `dungeon_rev`, but that data is not present in the
current dump. The practical path is a manual per-area background override table,
with each override carrying a screenshot/source note and confidence.

Minimal runtime candidate:
- Keep schema unchanged; continue sending `<bg>` under `/get_floor`.
- Change only the value selection from one background per outer region to
  per-floor/per-area override.
- Seed known overrides first:
  - `人魚の断崖` area 1 -> `adv_bg14`
  - `人魚の断崖` area 2 -> `adv_bg14`
  - `人魚の断崖` area 3 -> `adv_bg26`
- Expected observable: entering those areas renders the screenshot-matched
  beach/cliff backgrounds without route or hierarchy changes.

Open questions:
- Whether `adv_bg_fog*` variants are used by weather/time/event states or by a
  later client scene transition.
- Whether the missing `dungeon_rev` route can be reconstructed from native route
  generation strongly enough to fetch or emulate a canonical dungeon master
  payload later.
