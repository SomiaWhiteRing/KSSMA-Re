# Gacha System Frontier Card, 2026-07-01

Frontier:
- Main menu already opens the current safe gacha select page through `/connect/app/gacha/select/getcontents`
  and scene `9100`.
- Friendship and paid single-draw success paths, result/back, paid retry, currency spending, card persistence,
  history/stats updates, and roundtable owner-card readback are accepted.
- G1 recovered the parser-minimum error shape and `code=1` generic error-model branch, but stopped because no
  production edge from `_Main::connect` to `LayoutScene::showDialog` or `_SceneControl::push(90100)` was found.
  The candidate response is not implementable. Invalid product, unsupported mode, and insufficient-balance work
  remains frozen rather than guessing a visible rejection contract.

Known accepted state:
- `mainmenu-buttons-route-smoke` proved the main-menu gacha button reaches `/connect/app/gacha/select/getcontents`
  and returns to main menu.
- Current server response follows the original `local_gachaselect.xml` shape: one `gacha_select/xml_contents`
  page, not separate friendship and paid pages.
- `server/data/game/gacha.json` currently provides `gacha_free_0`, `gacha_cp_button`, and a paid explanatory text
  item. It deliberately omits unsupported ticket/comp-sheet purchase behavior.
- `work/extract-gacha-pack-resources.py` decodes the original `gacha0_1.pack` and re-encrypts those real PNG chunks
  into the local save-download pack path. It does not draw, repaint, crop, or generate replacement banner art.
- `work/gacha-select-resource-ratio-card-20260702.md` records the local page geometry, original pack candidate sizes,
  rejected generated aliases, and accepted runtime artifact.
- `flow -Scenario gacha-draw-smoke -Tag gacha-select-button-layout-2` passed on ARM19 with screenshot
  `work/kssma-flow-gacha-draw-smoke-gacha-select-button-layout-2/screenshots/open-gacha-select.png`, proving the
  friendship page renders the banner and bottom draw button, then taps through to
  `/connect/app/gacha/buy product_id=1`.
- The current select page no longer uses generated local aliases or inpainted no-text banners. Bitmap text inside
  original pack images remains unless a cleaner original resource is found.
- `flow -Scenario gacha-draw-smoke -Tag gacha-buy-owner-card-1` passed on ARM19 with artifact
  `work/kssma-flow-gacha-draw-smoke-gacha-buy-owner-card-1`.
- Runtime proved `/connect/app/gacha/buy` uses `product_id=1`, `bulk=1`, `auto_build=1`.
- Runtime paid draw proved the paid button path uses `/connect/app/gacha/buy` with decrypted
  `product_id=2`, `bulk=0`, `auto_build=0`; server normalizes the bulk zero to one paid draw.
- Static scan clarified `_GachaSelect::Cp::exec` opens the CP/shop path, not a separate paid gacha page. The
  accepted direction is now the original same-page list, with paid gacha represented by the `gacha_cp_button` entry.
- Runtime also proved the drawn card must appear in response `your_data.owner_card_list`; otherwise
  `_AnmGachaLakeBall` reaches `_CPlayer::getUserCard(...)` and crashes.

Static anchors:
- `rule_scene.xml`
  - `9100` = `gacha_select`
  - `9200` = `gacha_gettingcard`
  - `9300` = `gacha_gettingresult`
  - `9400` = `gacha_ejected_cards`
  - `9500` = `gacha_comp_sheet`
- `rule_resource.xml`
  - `gacha_select` needs `cmn_bg_01.png`, `ae_gacha.png`, `cmn_header.png`.
  - `gacha_gettingcard` needs `gac_bg.png`, `exp_get.png`, `gac_bg3.png`, `gac_lake01.png`,
    `gac_lake02.png`, and `gacha_drawcard.xml`.
  - `gacha_gettingresult` needs `cmn_bg_00.png`, `ae_gacha.png`, `carddetails.png`, and
    `gacha_drawresult.xml`.
- Bundled samples:
  - `local_gachaselect.xml`
  - `local_gachacomp.xml`
- Local available gacha image candidates:
  - decrypted preview sheet: `work/gacha-image-preview/gacha-pack-sheet.png`
  - decoded manifest: `work/gacha-image-preview/manifest.tsv`
  - `work/million_cn/sdcard_dump/.../save/download/pack/gacha/gacha_banner`
  - `work/million_cn/sdcard_dump/.../save/download/pack/gacha/gacha_free_0`
  - `work/million_cn/sdcard_dump/.../save/download/pack/gacha/gacha_free_button`
  - `work/million_cn/apktool/assets/pack/161/gacha/gacha0_1.pack` also names `gacha_compsheet`,
    `gacha_cp_2`, `gacha_event_button`, `gacha_free_0`, and related `gacha_*` entries.
- Layouts:
  - `layout_gacha_select.xml` uses an `xml_viewer` bound to `xmlcontents_model.contents`.
  - `layout_gacha_drawcard.xml`
  - `layout_gacha_drawresult.xml`
  - `layout_gacha_ejected_cards.xml`
  - `layout_gacha_comp_sheet.xml`

Current candidate route map:
- `/connect/app/gacha/select/getcontents` -> select page, scene `9100`.
- `/connect/app/gacha/comp_sheet` -> comp sheet page, scene `9500`, sample-backed by `local_gachacomp.xml`.
- `/connect/app/gacha/getproductinfo` -> currently a scene skeleton, likely product/detail confirmation frontier.
- `/connect/app/gacha/buy` -> minimal accepted draw animation response, scene `9200`; schema card:
  `work/gacha-buy-schema-card-20260701.md`.

Shared data prerequisites:
- Player save already has:
  - `items.gachaTicket`
  - `currencies.mc`
  - `currencies.friendshipPoint`
  - `gacha.friendshipCost`
  - `gacha.paidCostMc`
  - `gacha.history`
  - `cards.instances`
- Gacha cannot become real until draw results can add an owned card instance with a unique `serialId`
  and valid `masterCardId`.
- Card master data currently comes from masterdata samples; a clean game card database should be introduced before
  making draw pools large or random.

Accepted first implementation round:
- Restored one safe visible draw option in `gacha_select` without missing-image resources.
- Replaced the temporary text-only select page with a minimal image-backed page using `gacha_free_0` as the banner
  and `gacha_free_button` as the clickable draw button.
- Added `flow -Scenario gacha-draw-smoke`.
- Captured `/connect/app/gacha/buy` and passed the first draw response without a native crash.

Accepted settlement rounds:
- `gacha-settlement-deck-smoke -Tag gacha-localstyle-friendship-4` proves the local-style same-page select renders
  and the friendship entry reaches `/gacha/buy product_id=1` with settlement.
- `gacha-paid-settlement-deck-smoke -Tag gacha-localstyle-clean-paid-1` proves the same-page paid MC entry opens
  the native confirmation dialog, reaches `/gacha/buy product_id=2 bulk=0 auto_build=0`, spends 300 MC, persists
  card `serialId=2/masterCardId=9`, returns to main menu, and `/roundtable/edit move=1` reads the new card.
- `gacha-paid-settlement-deck-smoke -Tag gacha-button-ratio-fix-5` keeps the same functional proof while replacing
  the rejected generated and poster-sized page assets with original button/banner resources matched to the local
  page roles.
- `work/render-gacha-select-layout-html.py --check` is the local visual geometry gate for this page. It translates the
  current gacha JSON and bundled `local_gachaselect.xml` into HTML, copies the real PNG assets into the check artifact,
  and fails if current image entries overlap, overflow, or reference missing assets. `gacha-layout-html-fix-2` fixed
  the previous hard collisions (`gacha_compsheet` over `gacha_free_0`, and `gacha_free_0` over `gacha_cp_button`) by
  moving friendship to `y=220` and paid MC to `y=396`.

Current static stop:
- `work/gacha-buy-failure-schema-card-20260810.md` closes response/header/error parsing, code-1 model dispatch,
  transport, and type-2 dialog dismissal once that scene exists. It does not close the producer that actually pushes
  the dialog scene after the generic response error.
- G2/G3/G4 remain frozen. Do not change server XML until a static caller closes that exact presentation edge and
  proves the prior gacha result scene and dismissal behavior.

Non-goals for the first round:
- No random pool.
- No 11-pull.
- No comp-sheet reward.
- No card album completion.

Accepted success for the first round:
- Request order and screenshot prove:
  `main menu -> /gacha/select/getcontents -> gacha_select visible -> tap draw -> /gacha/buy -> draw scene alive`.

Do not repeat:
- Do not split friendship and paid gacha into separate server-selected pages again unless new native evidence
  proves the original client had such a page switch. The accepted baseline is a single original-style select list.
- Do not use `gacha_banner` as a draw button or select-page banner. It is a 784x553 pool image and previously
  rendered oversized/overlapping on ARM19.
- Do not treat `gacha_free_0` as a button. It is the 784x160 friendship gacha banner.
- Do not keep bundled `local_gachaselect.xml` y coordinates blindly after swapping resource names. First run
  `python .\work\render-gacha-select-layout-html.py --check`; the old raw-anchor mapping had measurable image overlaps.
- Do not switch the accepted select page back to text-only or to `gacha_free_button`/`gacha_button` pseudo-buttons
  unless a new runtime resource regression proves the original-style `gac_*`/`ae_*` resources unavailable.
- Do not treat HTTP 200 on `/gacha/buy` as success without draw animation/result screenshot or next route.
- Do not implement the parser-minimum code-1 XML from the G1 card; it is explicitly a non-accepted candidate.
