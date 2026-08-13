# Gacha Select Resource Ratio Card 2026-07-02

Superseded direction note, 2026-07-06: rest decryption in
`work/gacha-rest-layout-evidence-card-20260706.md` found stronger first-party evidence. The primary page chrome is
`ae_gacha` / `rja_ae_gacha`, while `rja_ae_gacha_slot` is not the select-list layout. Treat the manual fixed-slot
editor below as a diagnostic artifact, not the next product direction.

## Frontier

The gacha select page must use real local/original resources and must respect the local page geometry. Do not generate
or repaint banner images.

## Local Page Geometry

Source: `work/million_cn/apktool/assets/bundle/local_gachaselect.xml`

| Slot | action_id | x | y | local image name | next slot | implied vertical band |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| ticket | 2 | 8 | 8 | `gac_event_0` | 128 | 120 |
| comp sheet | 1 | 8 | 128 | `ae_gacha_compsheet` | 168 | 40 |
| friendship | 1 | 8 | 168 | `gac_free_0` | 288 | 120 |
| paid MC | 2 | 8 | 288 | `gac_cp_0` | scroll end | 342 |

The renderer can scroll; the paid slot is allowed to extend beyond the first visible frame.

Source: `work/million_cn/apktool/assets/bundle/layout_gacha_select.xml`

`layout_gacha_select.xml` is the outer select-box/page layout, not the per-entry image content. Its `xml_viewer`
declares the client logical viewport width as `frame_w=400`. The decoded PNGs in
`work/gacha-image-preview/decoded/` are 2x-sized assets for this page. The editor therefore keeps the XML coordinates
but previews images at an inferred client display scale of `0.5`; export still writes XML coordinates, not scaled
coordinates.

## Real Local Resource Candidates

Source: `work/million_cn/apktool/assets/pack/161/gacha/gacha0_1.pack`, decoded by
`work/extract-gacha-pack-resources.py`.

| Resource | Size | Use |
| --- | ---: | --- |
| `gacha_event_button` | 624x68 | ticket slot; real button-shaped local image |
| `gacha_compsheet` | 504x88 | comp-sheet slot; real local collection button |
| `gacha_free_0` | 784x160 | friendship slot; closest real banner-style friendship asset that does not crowd the next slot |
| `gacha_cp_button` | 624x68 | paid MC slot; real paid button-shaped local image |

Rejected resources:

- `gac_event_0`, `gac_free_0`, `gac_cp_0`, `ae_gacha_compsheet`: generated local aliases from the rejected prototype.
- `gacha_paid_banner`, `gacha_free_blank`: generated/repainted artifacts from rejected experiments.
- `gacha_free_0_1204`: real but visually too busy/crowded in this page region.
- `gacha_cp_2`: real paid banner, but too large and poster-like for the local paid entry slot.
- `gacha_button`, `gacha_free_button`: real but too generic for the current visible entry set.

## Current Product Mapping

`server/data/game/gacha.json` keeps the local slot order and y values:

```text
ticket       -> gacha_event_button @ x=8, y=8
comp sheet   -> gacha_compsheet @ x=8, y=128
friendship   -> gacha_free_0 @ x=8, y=220
paid MC      -> gacha_cp_button @ x=8, y=396
```

The first attempt kept the raw local XML y anchors after swapping in real pack resources. That was wrong: the local
placeholder images are `104/36/104/104` px high, but the current real resources are `68/88/160/68` px high. Keeping
`gacha_compsheet @ y=128`, `gacha_free_0 @ y=168`, and `gacha_cp_button @ y=288` made two hard geometry collisions:

```text
gacha_compsheet overlaps gacha_free_0 by 504x48
gacha_free_0 overlaps gacha_cp_button by 624x40
```

`work/render-gacha-select-layout-html.py --check` now translates the current JSON and bundled XML into an HTML
comparison page and writes `work/gacha-layout-html-check/gacha-select-layout-report.json`. The current accepted layout
uses the same real images but spaces them by actual image height; the check reports `current_overlaps=0`. Browser
verification also loaded the real PNG assets and reported no image overlaps. Screenshot:

```text
work/gacha-layout-html-check/browser-layout-fixed-assets.png
```

After visual review still rejected the page as chaotic, `work/render-gacha-select-layout-html.py --editor` now also
writes a manual editor:

```text
work/gacha-layout-html-check/gacha-select-layout-editor.html
```

The editor renders the XML slot grid on the left and all decoded PNG candidates on the right. Slots and coordinates are
locked to `local_gachaselect.xml`; `layout_gacha_select.xml` supplies only the 400px logical viewer width. A human can
only choose which candidate image fills each fixed slot. Exported `page.contents` forcibly preserve XML x/y coordinates.
This is an offline layout tool only; it does not change product data until a human-approved export is applied.

Browser verification loaded the editor from `file:///`, found 4 XML slots at 400px logical width, inferred preview
scale `0.500`, 6 current placements, 25 candidates, and no legacy free-coordinate reset button. Example displayed
sizes were `gacha_event_button 312x34` from natural `624x68`, `gacha_free_0 392x80` from natural `784x160`, and
`gacha_cp_button 312x34` from natural `624x68`. After replacing the ticket slot image, the export kept image
`x=8,y=8`, ticket text `x=30,y=12`, paid image `x=8,y=288`, and paid text `x=140,y=292`. The strict XML preview still
reports a 4px visual overlap between the currently selected `gacha_compsheet` and `gacha_free_0` candidates, which is a
candidate choice problem for manual selection rather than permission to move the XML slots. Screenshot:

```text
work/gacha-layout-html-check/gacha-select-layout-editor-scaled.png
```

## Runtime Check

Use:

```powershell
node .\server\test-bootstrap-server.js
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-paid-settlement-deck-smoke -Tag gacha-real-pack-ratio-1
```

Accepted runtime artifact:

```text
work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-layout-html-fix-2
```

The previous fully completed flow remains `work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-button-ratio-fix-5`.
After the HTML-derived coordinate fix, `gacha-layout-html-fix-2` reached the same core runtime evidence: opened the
select page, scrolled to the paid slot, reached `/connect/app/gacha/buy product_id=2 bulk=0 auto_build=0`, spent 300 MC,
returned to main menu, and `/connect/app/roundtable/edit move=1` read owner cards `[1,2]` / master cards `[22,9]`. The
outer process timed out while collecting the final deck screenshot, so use the route/events evidence for the coordinate
fix and rerun the flow if a clean summary file is required.
