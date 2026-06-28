# Exploration zh Area Names Card

Route:
`/connect/app/exploration/area`, `/connect/app/exploration/get_floor`

Frontier:
Area display names should come from the Chinese wiki source, not from an
agent-made translation. Keep this separate from walking background selection.

Primary source:

- Local cached zh-Fandom `探索` page:
  - Path: `work/external-data/raw/zh-fandom/pages/117.json`
  - URL: `https://kssma.fandom.com/zh/wiki/%E6%8E%A2%E7%B4%A2`
  - pageid `117`, revid `7930`, timestamp `2013-08-25T08:56:49Z`
  - wikitext sha256:
    `3387abf36af377515a9d191405035480ca69076efed1f663f1d5fd85c5c607a1`
  - Result: the page's prose/table labels are Chinese, but the six exploration
    area headings themselves are mixed Japanese strings.

Extracted area headings from zh-Fandom:

| index | zh-Fandom heading | image ref | floor count |
| --- | --- | --- | --- |
| 1 | 人魚の断崖 | File:area1.jpg | 6 |
| 2 | 燐光の湖 | File:area2.jpg | 9 |
| 3 | 錯乱の平原 | File:area3.jpg | 10 |
| 4 | 叡智の草原 | File:area4.jpg | 10 |
| 5 | 猛獣の砂丘 | File:area5.jpg | 15 |
| 6 | 祝福を授ける山 | File:area6.jpg | 20 |

Local normalized source:

- `work/external-data/normalized/exploration-focus.json` already extracts these
  exact six headings and the 70 floor rows from the cached zh-Fandom page.

Secondary sources checked:

- `work/external-data/raw/nonwiki-exploration/4399-exploration.html`
- `work/external-data/raw/nonwiki-exploration/962-exploration.html`

These Chinese article caches discuss exploration mechanics but do not provide a
usable six-area name table in the locally cached text. They are not accepted as
name sources for this patch.

Rejected assumption:

- Do not display agent-translated names such as `人鱼断崖`, `磷光之湖`,
  `错乱平原`, `睿智草原`, `猛兽沙丘`, or `传授祝福的山` unless a new source
  proves those exact strings were used by the CN client or a stronger Chinese
  wiki source.

Implementation rule:

- Use the zh-Fandom headings as both `sourceName` and visible display name for
  now.
- Keep the join key for FC2 mechanics on the same heading.
- Do not infer walking background ids from area names. Background remains a
  separate per-area override table sourced from screenshots/resource matching.

Observable for later runtime check:

- Area list shows the six zh-Fandom headings above.
- Entering the first area shows `人魚の断崖 区域1`/client-localized area suffix
  according to the existing layout behavior.

Open questions:

- Whether the original Simplified CN server used fully translated secret-area
  names is still unproven in the current local/web cache set.
