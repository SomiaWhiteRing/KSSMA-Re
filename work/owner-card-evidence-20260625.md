# Owner-card evidence search, 2026-06-25

Frontier: statically resolve `leader_serial_id=2367` to the owned-card `master_card_id`,
then to the already proven `master_card_id -> face/adv` resource chain.

Hypothesis: one existing bundle sample, server artifact, log/decrypted payload, or 140330 save-dump
file contains an owner-card structure where `serial_id=2367` and `master_card_id` are siblings.

Observable: `node .\work\owner-card-evidence-proof.js` prints a `serial_id=2367 master_card_id=N`
pair, or prints the searched sources and the point where the chain remains open.

## Data Sources

- `work/million_cn/jadx/resources/assets/bundle`
- `work/million_cn/apktool/assets/bundle`
- `work/million_cn/sdcard_dump`
- extracted-equivalent archive coverage from `base/com.square_enix.million_cn-140330.zip`
  via `tar -tf` / `tar -xOf`
- `server/bootstrap-server.js` and `server/test-bootstrap-server.js`
- existing `work/` runtime/server/logcat/decrypted/static artifacts with text-like extensions
- prior proof:
  - `work/master-resource-map-20260625.md`
  - `work/master-resource-map-proof.js`

## Search Method

Script: `work/owner-card-evidence-proof.js`

- Walked candidate static files without starting emulator, server, or touching APK output.
- Parsed XML-ish blocks for sibling `<serial_id>` and `<master_card_id>` under known card block
  shapes: `owner_card`, `user_card`, `leader_card`, `card`, `deck_card`, `battle_card`,
  `battle_user_card`.
- Searched exact `2367`, `leader_serial_id`, `serial_id`, `master_card_id`,
  `owner_card`, `owner_card_list`, `user_card`, and `leader_card` markers.
- Scanned non-audio `sdcard_dump` files for ASCII `2367`, u32-be `2367`, and u32-le `2367`.
- Scanned ZIP index (`6932` entries) and archive database/appdata/text candidates directly with
  `tar`; `work/million_cn/sdcard_dump` is the extracted content coverage for the full save dump.
- Ignored PNG/log numeric false positives unless a textual card payload shape was present.

Coverage from the successful run:

```text
target_serial=2367
source_file_counts:
- apktool bundle: 163
- base zip: 8
- jadx bundle: 163
- sdcard dump: 6388
- server: 2
- work artifacts: 281
zip_entries=6932
zip_interesting_entries=8
```

## Hits

Valid payload hit:

| source | field | value | sibling `master_card_id` |
| --- | --- | ---: | --- |
| `work/million_cn/jadx/resources/assets/bundle/local_battle_player.xml` | `leader_serial_id` | 2367 | none |
| `work/million_cn/apktool/assets/bundle/local_battle_player.xml` | `leader_serial_id` | 2367 | none |

False/non-payload hits:

- `cmn_loading.png` and `cmn_font.png` contain u32-le byte sequences equal to `2367`; these are
  binary image/resource bytes, not owner-card payloads.
- Two logcat files contain ASCII `2367` as Android process ids or unrelated runtime text, not card
  serial evidence.
- `work/master-resource-map-20260625.md` and `work/master-resource-map-proof.js` contain `2367`
  because they document the previous negative proof.

## Serial/Master Pairs Found

No searched source contains:

```text
serial_id=2367 -> master_card_id=N
```

The script did find other sibling serial/master pairs, proving the parser catches the shape when it
exists:

| source | block | serial_id | master_card_id |
| --- | --- | ---: | ---: |
| `local_battle_result.xml` | `user_card` | 13822704 | 9 |
| `local_battle_result.xml` | `user_card` | 7 | 101 |
| `local_users_event_list.xml` | `leader_card` | 1 | 22 |
| `local_users_event_list.xml` | `leader_card` | 6 | 116 |

These are not the logged-in `leader_serial_id=2367`.

## Closure Status

Cannot close:

```text
leader_serial_id=2367 -> master_card_id -> face/adv
```

Reason:

- `leader_serial_id=2367` appears only as `your_data/leader_serial_id` in
  `local_battle_player.xml`.
- That login/main-menu sample has an empty `<body>` and no `owner_card_list`, `user_card`,
  `leader_card`, or `master_card_id`.
- `master_card` is keyed by master id, not owned-card serial id.
- Prior proof already showed `2367` is not a parsed `master_card` id and no parsed `master_card`
  record contains u32 value `2367`.

Therefore `2367` must stay classified as an owned-card serial id only. It is not evidence for
`master_card_id=2367`, `face_2367`, or `adv_chara2367`.

## Next Minimal Proof

Find one static or decrypted payload with an owner-card list for the same login sample, containing:

```xml
<serial_id>2367</serial_id>
<master_card_id>N</master_card_id>
```

Good next static targets are any existing/decrypted responses for routes that naturally return owned
cards or decks: `roundtable/edit`, `roundtable/preview`, `cardselect/savedeckcard`,
`menu/playerinfo`, `menu/cardcollection`, or `card/exchange`.

Once that single pair exists, rerun:

```powershell
node .\work\owner-card-evidence-proof.js
node .\work\master-resource-map-proof.js
```

Then add exactly one closed row:

```text
serial_id=2367 -> master_card_id=N -> face_N/adv_charaN
```
