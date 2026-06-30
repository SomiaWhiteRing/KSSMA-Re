# Player Level EXP Lv10-Lv16 Weak Candidates, 2026-06-30

## Frontier

Find any usable values for player level EXP rows Lv10-Lv16. Source accuracy was relaxed for this
pass, but source strength still has to be labeled.

## Result

No direct public row for player Lv10-Lv16 was found.

Weak bridge candidates:

| level | next EXP |
| ---: | ---: |
| 10 | 1300 |
| 11 | 1400 |
| 12 | 1500 |
| 13 | 1600 |
| 14 | 1700 |
| 15 | 1800 |
| 16 | 1900 |

## Why These Values

The bridge is:

- original mobile atwiki directly confirms Lv17-Lv25 as `2000, 2100, ... 2800`;
- FC2 3DS table directly matches mobile rows at Lv21-Lv26:
  `2400, 2500, 2600, 2700, 2800, 3000`;
- the direct mobile segment Lv17-Lv25 is a plain +100 progression;
- extending that progression backward gives Lv10-Lv16 as `1300..1900`.

This is not a direct wiki/player-summary source. Treat it as low-confidence candidate data.

## Searches Attempted

- Exact Japanese queries for `Lv10=1300` through `Lv16=1900`.
- Japanese queries for `次のLv.までのEXP`, `プレイヤー情報`, and `拡散性ミリオンアーサー`.
- Simplified/Traditional Chinese queries for `等级经验`, `等級經驗`, and `玩家等级`.
- English/Korean queries for `Million Arthur player level experience`.
- atwiki backup/source/edit URL variants through Jina mirror.
- FC2 `?cmd=backup`, `?cmd=source`, and history-looking URL variants.
- Bing RSS result dumps under `work/recovered-data/wide-search/`.

No direct Lv10-Lv16 player EXP row was recovered.

## Outputs

- `work/recovered-data/player-level-exp-lv10-lv16-weak-candidates-20260630.json`
- `work/recovered-data/player-level-exp-lv10-lv16-weak-candidates-20260630.tsv`
- `work/recovered-data/player-level-exp-table-wide-20260630-lv10-lv16-weak-filled.json`
- `work/recovered-data/player-level-exp-table-wide-20260630-lv10-lv16-weak-filled.tsv`

## Product Rule

Do not silently promote these rows to `mobile_exact` or `fc2_3ds_exact`.

If server behavior needs early-level level-up before a direct row is found, use these only under
an explicit weak/candidate policy and make tests assert `sourceRank=weak_inferred_bridge_mobile_fc2`.
