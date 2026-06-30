# Player Level EXP Table Wide Search Card, 2026-06-30

## Frontier

Before expanding level-up behavior, recover the broadest possible player level EXP table and
separate it from card reinforcement EXP tables.

This pass is data recovery only. It does not change server behavior.

## Outputs

- Wide source-ranked table:
  `work/recovered-data/player-level-exp-table-wide-20260630.json`
- Wide TSV:
  `work/recovered-data/player-level-exp-table-wide-20260630.tsv`
- FC2 comment extraction:
  `work/recovered-data/fc2-3ds-player-level-comment-values-20260630.json`
  and `work/recovered-data/fc2-3ds-player-level-comment-values-20260630.tsv`
- Blocked search captures:
  `work/recovered-data/wide-search/ddg-*.html`
- Rejected card-EXP source cache:
  `work/recovered-data/sea-fandom-experience-table-api.json`

## Sources Checked

### Player Level Sources

- Original mobile atwiki player info:
  `https://w.atwiki.jp/kssma/pages/43.html`
  local mirror: `work/recovered-data/mobile-atwiki-player-info.md`
- 3DS FC2 level page:
  `https://ma3ds.wiki.fc2.com/wiki/%E3%83%AC%E3%83%99%E3%83%AB`
  local mirror: `work/recovered-data/fc2-3ds-player-level-page.html`
- Chinese Fandom beginner guide:
  `https://kssma.fandom.com/zh/wiki/%E6%96%B0%E6%89%8B%E6%8C%87%E5%8D%97`
  local cache: `work/external-data/raw/zh-fandom/pages/110.json`

### Rejected For Player Level

- English Fandom `Experience Table`:
  `https://million-arthur.fandom.com/wiki/Experience_Table`
  local API cache: `work/recovered-data/sea-fandom-experience-table-api.json`
- Chinese Fandom `強化合成`:
  `https://kssma.fandom.com/zh/wiki/%E5%BC%B7%E5%8C%96%E5%90%88%E6%88%90`
  local cache: `work/external-data/raw/zh-fandom/pages/100.json`

Both rejected pages are card reinforcement experience, not player level next-EXP. The Chinese
page explicitly says card level only has a percentage display and its table is based on
`LV 1 -> LV 2 = 100` for cards.

## Search Coverage

Queries attempted across Japanese, Simplified/Traditional Chinese, Korean, and English:

- `"拡散性ミリオンアーサー" "経験値" "プレイヤー"`
- `"拡散性ミリオンアーサー" "次のLv"`
- `"扩散性百万亚瑟王" "等级经验"`
- `"擴散性百萬亞瑟王" "等級" "經驗"`
- `"百万亚瑟王" "玩家等级" "经验"`
- `"확산성 밀리언아서" "레벨" "경험치"`
- `"Million Arthur" "player level" "experience"`

DuckDuckGo returned anomaly pages for these attempts, saved under
`work/recovered-data/wide-search/`. Fandom API search currently returns Cloudflare 403. No
complete original mobile player EXP table was recovered from these searches.

## Evidence Summary

Original mobile atwiki direct rows:

```text
17=2000
18=2100
19=2200
20=2300
21=2400
22=2500
23=2600
24=2700
25=2800
26=3000
```

Original mobile mechanics also confirm:

- Level-up fully recovers AP and BC.
- Level-up grants AP/BC allocation points.
- Up to level 50 gives 3 points; above level 50 gives 2 points.

Chinese Fandom confirms compatible mechanics:

- EXP is gained from exploration, fairy battle, and factor battle.
- Level cap is 350.
- Up to level 50 gives 3 ability points; above level 50 gives 2.
- AP recovers every 3 minutes; BC recovers every 1 minute.

3DS FC2 provides the broadest numeric player-level candidate table to Lv200, but it is not
original mobile proof. It contains direct rows, uncertain rows, holes, and comments.

## Wide Table Strength

`work/recovered-data/player-level-exp-table-wide-20260630.json` contains one candidate row per
level from 1 to 200.

Counts:

```text
mobile_exact: 10
fc2_3ds_exact: 101
fc2_3ds_uncertain: 2
pattern_inferred_from_fc2_comment_supported: 1
pattern_inferred_from_fc2: 78
missing: 8
```

Missing rows:

```text
10, 11, 12, 13, 14, 15, 16, 200
```

Uncertain FC2 table rows:

```text
41, 48
```

FC2 comment evidence recovered:

```text
80 -> 81: 22240以上っぽい
83 -> 84: 22250
84 -> 85: 22250
86 -> 87: 22250
87 -> 91: all 22250
103 -> 104: 23850
110 -> 111: 26650
```

The Lv80 comment is only a lower-bound/uncertain comment. The wide table keeps Lv80 at the
pattern candidate `22250` and records the comment only as support, not as an exact threshold.

## Product-Use Rule

Safe by default for current product code:

```text
mobile_exact
fc2_3ds_exact
```

Not safe by default:

```text
fc2_3ds_uncertain
pattern_inferred_from_fc2_comment_supported
pattern_inferred_from_fc2
missing
```

These weaker rows can be used only in explicitly labeled candidate/test behavior.

## Conclusion

A complete original mobile player level EXP table was not found in this pass. The best available
complete-ish candidate is the FC2 3DS table plus comments and pattern fills, with original mobile
confirmation only for Lv17-Lv26.

For the next level-up implementation, continue using trusted mobile rows for smoke tests. Do not
use card reinforcement EXP tables for player level-up.
