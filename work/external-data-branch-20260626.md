# External Data Branch

Frontier: build an external evidence pipeline for KSSMA systems and card data without changing the local bootstrap server.

## Sources
- en-fandom: pages=20, images=0, skipped=0, api=https://million-arthur.fandom.com/api.php
- zh-fandom: pages=10, images=16, skipped=20, api=https://kssma.fandom.com/zh/api.php
- atwiki kssma: manual cross-check source only in this phase because direct automation can hit Cloudflare.
- Wayback/CDX: optional future supplement, not required for the current pipeline.

## Entity Counts
| type | count |
| --- | --- |
| card | 20 |
| combo | 20 |
| source_page | 30 |
| skill | 19 |
| fairy_or_boss | 4 |
| system_page | 14 |

## Parsing Status
- structured pages: 30
- text evidence only pages: 0
- conflicts detected: 0
- cards missing image refs: 20

## Card Field Coverage
| field | present | total |
| --- | --- | --- |
| rarity | 20 | 20 |
| cost | 20 | 20 |
| faction | 20 | 20 |
| gender | 20 | 20 |
| lv_max | 20 | 20 |
| skill_name | 20 | 20 |
| illustrator | 20 | 20 |
| image_refs | 0 | 20 |

## System Topic Coverage
| topic | pages | rules | sources |
| --- | --- | --- | --- |
| 主画面 | 1 | BC每1分鐘回復1點; 等級上限是350級; 每次升級獲得3點能力值; 50以上每次升級只有2點; 200點抽一張; 100MC = 100円; 朋友數目上限隨著升級提升，最終上限是30人; AP每3分鐘回復1點 | 新手指南 |
| AP/BC | 1 | BC每1分鐘回復1點; 等級上限是350級; 每次升級獲得3點能力值; 50以上每次升級只有2點; 200點抽一張; 100MC = 100円; 朋友數目上限隨著升級提升，最終上限是30人; AP每3分鐘回復1點 | 新手指南 |
| 探索 | 1 |  | 探索 |
| 战斗 | 1 |  | 戰鬥配牌 |
| 因子战 | 1 |  | 因子戰 |
| 妖精战 | 2 |  | 新版強敵戰, 妖精戰 |
| 合成 | 2 |  | 進化合成, 強化合成 |
| Gacha | 1 | BC每1分鐘回復1點; 等級上限是350級; 每次升級獲得3點能力值; 50以上每次升級只有2點; 200點抽一張; 100MC = 100円; 朋友數目上限隨著升級提升，最終上限是30人; AP每3分鐘回復1點 | 新手指南 |
| 朋友 | 1 | BC每1分鐘回復1點; 等級上限是350級; 每次升級獲得3點能力值; 50以上每次升級只有2點; 200點抽一張; 100MC = 100円; 朋友數目上限隨著升級提升，最終上限是30人; AP每3分鐘回復1點 | 新手指南 |
| 道具 | 1 | BC每1分鐘回復1點; 等級上限是350級; 每次升級獲得3點能力值; 50以上每次升級只有2點; 200點抽一張; 100MC = 100円; 朋友數目上限隨著升級提升，最終上限是30人; AP每3分鐘回復1點 | 新手指南 |
| 剧情 | 2 |  | 支線故事, 主線故事 |
| 活动 | 0 |  |  |

## Structured Examples
- card: Arbitrator Knight rarity=3 cost=8 skill=None source=https://million-arthur.fandom.com/wiki/Arbitrator_Knight
- card: Arousal - Sisilala Overdrive rarity=6 cost=11 skill=Inferno Dance source=https://million-arthur.fandom.com/wiki/Arousal_-_Sisilala_Overdrive
- card: Arthur - Blade Protector rarity=3 cost=7 skill=Righteous Sword source=https://million-arthur.fandom.com/wiki/Arthur_-_Blade_Protector
- card: Arthur - Blade Protector (SR+) rarity=6 cost=7 skill=Righteous Sword source=https://million-arthur.fandom.com/wiki/Arthur_-_Blade_Protector_(SR%2B)
- card: Arthur - Sorcery King rarity=3 cost=7 skill=Strategic Dream source=https://million-arthur.fandom.com/wiki/Arthur_-_Sorcery_King
- card: Arthur - Sorcery King (SR+) rarity=6 cost=7 skill=Strategic Dream source=https://million-arthur.fandom.com/wiki/Arthur_-_Sorcery_King_(SR%2B)
- card: Arthur - Techno Smith rarity=3 cost=7 skill=Counter Assault source=https://million-arthur.fandom.com/wiki/Arthur_-_Techno_Smith
- card: Arthur - Techno Smith (SR+) rarity=6 cost=7 skill=Counter Assault source=https://million-arthur.fandom.com/wiki/Arthur_-_Techno_Smith_(SR%2B)
- system: 合成 rules= source=https://kssma.fandom.com/zh/wiki/%E9%80%B2%E5%8C%96%E5%90%88%E6%88%90
- system: 合成 rules= source=https://kssma.fandom.com/zh/wiki/%E5%BC%B7%E5%8C%96%E5%90%88%E6%88%90
- system: 探索 rules= source=https://kssma.fandom.com/zh/wiki/%E6%8E%A2%E7%B4%A2
- system: 妖精战 rules= source=https://kssma.fandom.com/zh/wiki/%E6%96%B0%E7%89%88%E5%BC%B7%E6%95%B5%E6%88%B0
- system: 主画面 rules=BC每1分鐘回復1點; 等級上限是350級; 每次升級獲得3點能力值; 50以上每次升級只有2點; 200點抽一張; 100MC = 100円; 朋友數目上限隨著升級提升，最終上限是30人; AP每3分鐘回復1點 source=https://kssma.fandom.com/zh/wiki/%E6%96%B0%E6%89%8B%E6%8C%87%E5%8D%97

## Manual Review
- No duplicate-card field conflicts detected in the current sample.

## Local Masterdata Candidate Notes
These are candidates for later matching against local masterdata, not merged server data.
| name | rarity | cost | lv1 hp | lv1 atk |
| --- | --- | --- | --- | --- |
| Arbitrator Knight | 3 | 8 | 1680 | 2450 |
| Arousal - Sisilala Overdrive | 6 | 11 | 1930 | 1200 |
| Arthur - Blade Protector | 3 | 7 | 1960 | 1520 |
| Arthur - Blade Protector (SR+) | 6 | 7 | 7400 | 5700 |
| Arthur - Sorcery King | 3 | 7 | 1960 | 1520 |
| Arthur - Sorcery King (SR+) | 6 | 7 | 7400 | 5700 |
| Arthur - Techno Smith | 3 | 7 | 1960 | 1520 |
| Arthur - Techno Smith (SR+) | 6 | 7 | 7300 | 5600 |
| Arts - Eternal Flame | 7 | 31 | 4440 | 4440 |
| Arts - Kinon | 6 | 22 | 5200 | 9500 |
| Arts - Lami | 6 | 25 | 2150 | 2680 |
| Arts - Leone | 7 | 20 | 3620 | 4150 |
| Arts - Martisha | 6 | 22 | 8400 | 7200 |
| Arts - Siqi | 7 | 23 | 7200 | 2500 |
| Arts - XiaoLongNu | 7 | 21 | 4320 | 5870 |
| Arts - YangGuo | 7 | 14 | 2350 | 3350 |
| Arts - Yuuka | 7 | 41 | 2350 | 5020 |
| AWC - Alessandra | 6 | 22 | 8000 | 6800 |
| AWC - Luka | 6 | 20 | 6800 | 8000 |
| AWC - Oliver | 6 | 23 | 8000 | 9000 |

## Commands
```powershell
node .\work\kssma-external-wiki-fetch.js --source zh-fandom --limit 20
node .\work\kssma-external-wiki-fetch.js --source en-fandom --limit 20
node .\work\kssma-external-wiki-extract.js
node .\work\kssma-external-wiki-report.js
```

## Conclusion
External wiki data is now a reproducible evidence source. Keep it separate from native schema proof and bootstrap-server responses until a route-specific handoff names one field/value to test.
