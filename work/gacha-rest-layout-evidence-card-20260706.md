# Gacha Rest Layout Evidence Card 2026-07-06

## Frontier

The current gacha select page is visually wrong. The next step is not manual fitting. Use the still-encrypted
`save/download/rest/ae_gacha*` and `rja_ae_gacha*` files as first-party evidence.

## Decryption Result

Tool:

```powershell
python .\work\decrypt-gacha-rest-evidence.py
```

Output directory:

```text
work/gacha-rest-decrypt/
```

All tested gacha rest files decrypt with `k1 = A1dPUcrvur2CRQyl`; `k2` is not the resource key for these files.

| File | Result | Evidence output |
| --- | --- | --- |
| `ae_gacha` | PNG `1024x1024` | `work/gacha-rest-decrypt/ae_gacha.png` |
| `ae_gacha02` | PNG `1024x256` | `work/gacha-rest-decrypt/ae_gacha02.png` |
| `rja_ae_gacha.load` | dependency table: `ae_gacha.png`, `cmn_bg_01.png`, `ae_gacha02.png` | `work/gacha-rest-decrypt/rja_ae_gacha_load.load.txt` |
| `rja_ae_gacha` | `.AE` animation, 29 top-level records, 27 sprite atlas rects | `work/gacha-rest-decrypt/rja_ae_gacha.records.json` |
| `rja_ae_gacha_slot.load` | dependency table: `1000_common_button_.png` | `work/gacha-rest-decrypt/rja_ae_gacha_slot_load.load.txt` |
| `rja_ae_gacha_slot` | `.AE` animation, 4 top-level records, 2 button atlas rects | `work/gacha-rest-decrypt/rja_ae_gacha_slot.records.json` |
| `11_gacha_banner` | PNG `784x553` | `work/gacha-rest-decrypt/11_gacha_banner.png` |
| `11_gacha_banner_event` | PNG `784x553` | `work/gacha-rest-decrypt/11_gacha_banner_event.png` |
| `rja_1000_main_menu_gacha` | `.AE` animation, 6 records, 2 button atlas rects | `work/gacha-rest-decrypt/rja_1000_main_menu_gacha.records.json` |
| `rja_gac_gauge` | `.AE` animation, 47 records, 37 sprite atlas rects | `work/gacha-rest-decrypt/rja_gac_gauge.records.json` |

Preview sheets:

```text
work/gacha-rest-decrypt/rja_ae_gacha_sprites_sheet.png
work/gacha-rest-decrypt/rja_ae_gacha_slot_sprites_sheet.png
work/gacha-rest-decrypt/rja_1000_main_menu_gacha_sprites_sheet.png
```

## Static Layout Evidence

`rule_resource.xml` says scene `gacha_select` loads only:

```text
cmn_bg_01.png
ae_gacha.png
cmn_header.png
```

`layout_gacha_select.xml` says the visible select list is:

```text
xml_viewer name=viewer y=50 frame_w=400 bar=true
gacha name=main x=0 y=0 mc=11
```

So the page has two layers:

- `gacha main`: original gacha chrome/status animation using `ae_gacha.anm` / `rja_ae_gacha`.
- `xml_viewer`: server-provided `gacha_select/xml_contents` list, starting at screen y=50.

`local_gachaselect.xml` remains the best bundled sample for the server-provided list. It uses:

```text
gac_event_0 @ x=8, y=8
ae_gacha_compsheet @ x=8, y=128
gac_free_0 @ x=8, y=168
gac_cp_0 @ x=8, y=288
```

Those `y` values are relative to the `xml_viewer`, not the entire screen. The `xml_viewer` itself starts at `y=50`.

## Interpretation

`rja_ae_gacha` proves the original page chrome and atlas fragments. It does not by itself replace
`gacha_select/xml_contents`; the scrolling product list is still data-driven by the server response.

The parsed `.AE` tail quads are atlas source rectangles, not screen rectangles. Examples:

```text
ae_gacha.png 0,56 376x96
ae_gacha.png 0,152 376x96
ae_gacha.png 0,0 480x56
cmn_bg_01.png 0,0 480x320
```

`rja_ae_gacha_slot` is not the gacha select list layout. Native strings associate `ae_gacha_slot.anm` with
`AnmMainGachaSlot`, and its dependency is only `1000_common_button_.png`; it appears to be a small main-menu/button
slot animation.

Current dump contains `pack/gacha/gacha_banner*` and `rest/11_gacha_banner*`, but it does not contain
`gac_event_0`, `gac_free_0`, `gac_cp_0`, or `ae_gacha_compsheet` as original rest/pack files. Those names appear in
the bundled `local_gachaselect.xml` sample and in old generated artifacts, not as first-party files in the current dump.

## Conclusion

This evidence invalidates the recent "manually fit decoded pack buttons into fixed XML slots" direction as the primary
route. The first-party page chrome is `ae_gacha`/`rja_ae_gacha`; the product list still needs a server XML hypothesis,
but it should be built around the original `xml_viewer` layer and real downloaded product/banner assets, not around
hand-positioned replacement buttons.

## Runtime Trial 2026-07-06

Implemented a narrow trial that keeps the server XML list to two original-resource entries:

```text
friendship -> gacha_free_0 @ x=8, y=8
paid MC    -> gacha_cp_button @ x=8, y=112
```

The gacha flow now syncs the scene-owned rest resources before entering the page:

```text
download/rest/ae_gacha
download/rest/ae_gacha02
download/rest/rja_ae_gacha
download/rest/rja_ae_gacha.load
```

Checks:

```powershell
node .\server\test-bootstrap-server.js
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-draw-smoke -Tag gacha-rest-select-trial-2
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-paid-settlement-deck-smoke -Tag gacha-rest-select-paid-2
```

Accepted artifact:

```text
work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-rest-select-paid-2
```

Observed:

- `open-gacha-select.png` shows the restored `ae_gacha` page chrome, the real friendship banner, and the MC button.
- `gacha-paid-confirm.png` shows the Chinese confirmation dialog.
- Paid route reached `/connect/app/gacha/buy` with decrypted `product_id=2`, then returned to gacha select, main menu,
  and `/connect/app/roundtable/edit` saw owner cards `[1,2]`.

This trial does not prove separate friendship/paid pages. It only establishes a cleaner runnable same-page baseline while
the page-switch/category route remains unrecovered.

Next safe implementation step:

1. Keep `layout_gacha_select.xml` geometry: `xml_viewer y=50 frame_w=400`.
2. Stop treating `rja_ae_gacha_slot` as the select-page list layout.
3. Build a new gacha select candidate using real first-party resources:
   - `ae_gacha` chrome is scene-owned, not an XML content image.
   - product/banner candidates are `11_gacha_banner`, `11_gacha_banner_event`, `pack/gacha/gacha_banner`, and
     `pack/gacha/gacha_banner_event`.
4. Recover or prove the server-side `gacha_select/xml_contents` shape before changing `server/data/game/gacha.json`.
