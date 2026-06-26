# Master/resource static proof, 2026-06-25

Frontier: face/character dialog resource mapping, static only.

Hypothesis: an existing sample `leader_serial_id` or `master_card_id` can be linked to `master_card`,
then to concrete `face_*` / `adv_chara*` resources already present in the 140330 save dump.

Observable: `node .\work\master-resource-map-proof.js` prints a closed id/resource chain or the exact
point where the chain breaks.

## Data sources

- Login/main-menu sample:
  `work/million_cn/jadx/resources/assets/bundle/local_battle_player.xml`
- Other bundle samples with explicit card ownership pairs:
  `work/million_cn/jadx/resources/assets/bundle/local_battle_result.xml`
  `work/million_cn/jadx/resources/assets/bundle/local_users_event_list.xml`
  `work/million_cn/jadx/resources/assets/bundle/local_battle_area.xml`
- Master table:
  `work/million_cn/sdcard_dump/sdcard/Android/data/com.square_enix.million_cn/files/save/database/master_card`
- Resource routes:
  `work/million_cn/jadx/resources/assets/bundle/rule_resource_route.xml`
- Card packs:
  `work/million_cn/jadx/resources/assets/pack/148/card/card*_0.pack`
- Runtime resource files:
  `work/million_cn/sdcard_dump/sdcard/Android/data/com.square_enix.million_cn/files/save/download/image/face/`
  `work/million_cn/sdcard_dump/sdcard/Android/data/com.square_enix.million_cn/files/save/download/image/adv/`

## Parsing method

- `local_battle_player.xml` was parsed for `<leader_serial_id>`.
- Bundle battle/user samples were parsed for local `<serial_id>` + `<master_card_id>` pairs.
- `master_card` is not XML. Its first big-endian u32 is the record count (`480`), followed by a
  big-endian offset table. Each record starts with u32 fields, then length-prefixed UTF-8 strings.
- The proof script only parses enough of each record to extract the internal `masterId`, name, and
  numeric fields. It does not claim full master schema coverage.
- `rule_resource_route.xml` maps `face` to `save/download/image/face/` and `adv` to
  `save/download/image/adv/`.
- Card packs were checked for ASCII aliases such as `face_9` and `adv_chara9`; save dump files were
  checked by exact filename.

## Found mappings

`local_battle_player.xml`:

- `leader_serial_id=2367`
- No `<master_card_id>` or owner-card list is present in that sample.
- `2367` is not a `master_card` id in the parsed table.
- No parsed `master_card` record contains u32 value `2367`.

Explicit bundle sample chains that do close:

| source | serial evidence | master_card_id | master_card record | resource ids proven | resource files |
| --- | --- | ---: | --- | --- | --- |
| `local_battle_result.xml` | `serial_id=13822704` | 9 | id 9, `支援型依缇尔` | 9, 5009 | `face_9`, `adv_chara9`, `face_5009`, `adv_chara5009` |
| `local_battle_result.xml` | `serial_id=7` | 101 | id 101, `支援型克莱尔` | 101, 5101 | `face_101`, `adv_chara101`, `face_5101`, `adv_chara5101` |
| `local_users_event_list.xml` | `leader_card serial_id=1` | 22 | id 22 | 22, 5022 | `face_22`, `adv_chara22`, `face_5022`, `adv_chara5022` |
| `local_battle_area.xml` | battle area card list | 179 | id 179 | 179, 5179 | `face_179`, `adv_chara179`, `face_5179`, `adv_chara5179` |
| `local_battle_area.xml` | battle area card list | 30 | id 30 | 30, 5030 | `face_30`, `adv_chara30`, `face_5030`, `adv_chara5030` |

Resource proof details from the script:

```text
master_card_id=9   pack=504660 bytes, image_id=9/5009, all face/adv files exist, pack aliases true
master_card_id=101 pack=539116 bytes, image_id=101/5101, all face/adv files exist, pack aliases true
master_card_id=22  pack=571512 bytes, image_id=22/5022, all face/adv files exist, pack aliases true
master_card_id=179 pack=379916 bytes, image_id=179/5179, all face/adv files exist, pack aliases true
master_card_id=30  pack=610760 bytes, image_id=30/5030, all face/adv files exist, pack aliases true
```

## Confidence

- High: `master_card_id -> master_card record -> card{master_id}_0.pack -> face/adv aliases -> save dump files`
  is a valid static chain for samples that already contain `master_card_id`.
- Medium-high: `master_card` numeric fields include both base image id and +5000 holography/variant image id.
  This is supported by repeated records and matching pack aliases, but the full field names are not decoded.
- Low/blocked: `local_battle_player.xml leader_serial_id=2367 -> master_card_id` is not proven. That value is a
  user-card serial id, not a master id, and this sample does not include the owner card list needed to resolve it.

## Failure points

- The current login sample has only `your_data/leader_serial_id=2367`; it does not carry
  `owner_card_list`, `user_card`, `leader_card`, or `master_card_id`.
- `master_card` is a master table keyed by master id, not by user-card serial id.
- The existing parsed data does not contain a `2367 -> master_card_id` mapping.
- Therefore, using `leader_serial_id=2367` alone to choose `face_2367` or `adv_chara2367` would be a bad inference.

## Next minimal proof

Find or capture one static payload that contains the logged-in user's owner card list, preferably with
`serial_id=2367` and its sibling `master_card_id`. Candidate route/schema names already visible in native strings
and bundle samples: `owner_card_list`, `user_card`, `leader_card`, `serial_id`, `master_card_id`.

Once that one pair exists, rerun the same proof shape:

```powershell
node .\work\master-resource-map-proof.js
```

Then add exactly one `serial_id=2367 -> master_card_id=N -> face_N/adv_charaN` row to this report.
