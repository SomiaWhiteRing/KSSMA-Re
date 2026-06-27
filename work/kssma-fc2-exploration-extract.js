const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const RAW_DIR = path.join(ROOT, "work", "external-data", "raw", "fc2-ma3ds", "pages");
const NORMALIZED_DIR = path.join(ROOT, "work", "external-data", "normalized");
const OUT_JSON = path.join(NORMALIZED_DIR, "fc2-exploration-regions.json");
const OUT_REPORT = path.join(ROOT, "work", "exploration-fc2-mechanics-card-20260627.md");

const REGION_TITLES = [
  "人魚の断崖",
  "燐光の湖",
  "錯乱の平原",
  "叡智の草原",
  "猛獣の砂丘",
  "祝福を授ける山",
  "天に至る氷壁",
];

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function decodeEntities(value) {
  return String(value || "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(Number.parseInt(code, 16)));
}

function stripHtml(value) {
  return decodeEntities(
    String(value || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, "")
  )
    .replace(/\r/g, "")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function parseAttr(attrs, name, fallback = 1) {
  const match = String(attrs || "").match(new RegExp(`${name}\\s*=\\s*["']?(\\d+)`, "i"));
  return match ? Number(match[1]) : fallback;
}

function extractRows(html) {
  return [...String(html || "").matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)].map((match) => match[1]);
}

function parseCells(rowHtml) {
  return [...String(rowHtml || "").matchAll(/<(td|th)\b([^>]*)>([\s\S]*?)<\/\1>/gi)].map((match) => ({
    tag: match[1].toLowerCase(),
    attrs: match[2],
    html: match[3],
    text: stripHtml(match[3]),
    rowspan: parseAttr(match[2], "rowspan", 1),
    colspan: parseAttr(match[2], "colspan", 1),
  }));
}

function expandRowspans(rowsHtml, columnCount) {
  const pending = Array(columnCount).fill(null);
  const rows = [];

  for (const rowHtml of rowsHtml) {
    const cells = parseCells(rowHtml);
    const expanded = [];
    let col = 0;
    for (const cell of cells) {
      while (col < columnCount && pending[col]) {
        expanded[col] = pending[col].cell;
        pending[col].rowsLeft -= 1;
        if (pending[col].rowsLeft <= 0) {
          pending[col] = null;
        }
        col += 1;
      }
      for (let offset = 0; offset < cell.colspan && col + offset < columnCount; offset += 1) {
        expanded[col + offset] = cell;
        if (cell.rowspan > 1) {
          pending[col + offset] = { cell, rowsLeft: cell.rowspan - 1 };
        }
      }
      col += cell.colspan;
    }
    while (col < columnCount) {
      if (pending[col]) {
        expanded[col] = pending[col].cell;
        pending[col].rowsLeft -= 1;
        if (pending[col].rowsLeft <= 0) {
          pending[col] = null;
        }
      }
      col += 1;
    }
    rows.push(expanded);
  }

  return rows;
}

function parseCost(text) {
  const match = String(text || "").match(/-?\d+/);
  return match ? Math.abs(Number(match[0])) : null;
}

function parseExpGold(text) {
  const compact = String(text || "").replace(/\s+/g, "");
  const expMatch = compact.match(/(\d+)EXP/);
  const goldMatch = compact.match(/(\d+)～(\d+)Gold/);
  return {
    exp_per_move: expMatch ? Number(expMatch[1]) : null,
    gold_min_per_move: goldMatch ? Number(goldMatch[1]) : null,
    gold_max_per_move: goldMatch ? Number(goldMatch[2]) : null,
  };
}

function parseRequired(text) {
  const match = String(text || "").match(/(\d+)回\((\d+)AP\)/);
  return match
    ? {
        required_moves: Number(match[1]),
        required_total_ap: Number(match[2]),
      }
    : { required_moves: null, required_total_ap: null };
}

function parseRewardSlots(text) {
  return String(text || "")
    .split(/\s*\/\s*/)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function firstTable(html) {
  const match = String(html || "").match(/<table\b[^>]*class=["'][^"']*\btable\b[^"']*["'][^>]*>([\s\S]*?)<\/table>/i);
  return match ? match[1] : "";
}

function parseRegionTable(html) {
  const rows = expandRowspans(extractRows(firstTable(html)), 5);
  const areas = [];
  let boss_area = null;

  for (const row of rows) {
    const texts = row.map((cell) => cell?.text || "");
    if (!texts[0] || /エリア/.test(texts[0])) {
      continue;
    }
    const area = Number.parseInt(texts[0], 10);
    const cost_ap = parseCost(texts[1]);
    if (!Number.isFinite(area)) {
      continue;
    }
    if (/ボスバトル/.test(texts.join(" "))) {
      boss_area = area;
      continue;
    }
    const expGold = parseExpGold(texts[3]);
    const required = parseRequired(texts[4]);
    areas.push({
      area,
      cost_ap,
      reward_slots: parseRewardSlots(texts[2]),
      ...expGold,
      ...required,
      progress_per_move:
        required.required_moves && required.required_moves > 0
          ? Number((100 / required.required_moves).toFixed(6))
          : null,
    });
  }

  return { areas, boss_area };
}

function parseRegionMeta(html) {
  const text = stripHtml(html);
  const totalMatch = text.match(/全エリア踏破必要AP：\s*(\d+)AP/);
  const nextMatch = text.match(/次の秘境：\s*([^\n\r]+)/);
  return {
    total_required_ap: totalMatch ? Number(totalMatch[1]) : null,
    next_region: nextMatch ? nextMatch[1].trim() : "",
  };
}

function parseGuardian(html) {
  const markers = [...String(html || "").matchAll(/秘境守護者\s*ボスバトル/g)];
  const marker = markers.length ? markers[markers.length - 1].index : -1;
  if (marker < 0) {
    return null;
  }
  const sectionHtml = String(html || "").slice(marker);
  const section = sectionHtml.match(/<ul>([\s\S]*?)<\/ul>/i);
  if (!section) {
    return null;
  }
  const text = stripHtml(section[1]);
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const name = lines[0] || "";
  return {
    name,
    hp: Number((text.match(/HP：\s*(\d+)/) || [])[1] || 0) || null,
    exp: Number((text.match(/獲得EXP：\s*(\d+)EXP/) || [])[1] || 0) || null,
    gold: Number((text.match(/獲得Gold：\s*(\d+)Gold/) || [])[1] || 0) || null,
    reward_card: ((text.match(/報酬カード：\s*([^\n(]+)/) || [])[1] || "").trim(),
    holo: /ホロ/.test(text),
  };
}

function sourceUrl(title) {
  return `https://ma3ds.wiki.fc2.com/wiki/${encodeURIComponent(title)}?pc=`;
}

function parseRegion(title, index) {
  const file = path.join(RAW_DIR, `${title}.html`);
  const html = fs.readFileSync(file, "utf8");
  const { areas, boss_area } = parseRegionTable(html);
  return {
    source: "fc2-ma3ds",
    source_url: sourceUrl(title),
    title,
    region_index: index + 1,
    ...parseRegionMeta(html),
    boss_area,
    guardian: parseGuardian(html),
    area_count: areas.length,
    areas,
  };
}

function renderReport(data) {
  const lines = [];
  lines.push("# Exploration FC2 Mechanics Card, 2026-06-27");
  lines.push("");
  lines.push("Scope: external mechanics/value-domain evidence only. Do not merge these values into server responses until native schema and current client route mapping agree.");
  lines.push("");
  lines.push("## Source");
  lines.push("");
  lines.push("- 3DS版 拡散性ミリオンアーサー 攻略Wiki / FC2 pages fetched after JP VPN became available.");
  lines.push("- Raw HTML cache: `work/external-data/raw/fc2-ma3ds/pages/`.");
  lines.push("- Normalized JSON: `work/external-data/normalized/fc2-exploration-regions.json`.");
  lines.push("- Version note: zh-Fandom says the early mobile data had six open regions; FC2 3DS data adds `天に至る氷壁` as a seventh main region. Treat region 7 as cross-version evidence until the local client/master mapping proves it belongs in the current CN baseline.");
  lines.push("");
  lines.push("## Region Summary");
  lines.push("");
  lines.push("| # | region | areas | AP range | total AP | guardian | guardian HP | guardian reward | next |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const region of data.regions) {
    const costs = [...new Set(region.areas.map((area) => area.cost_ap).filter(Number.isFinite))].sort((a, b) => a - b);
    const apRange = costs.length ? `${costs[0]}-${costs[costs.length - 1]}` : "";
    const totalRequiredAp = region.total_required_ap ?? "";
    lines.push(
      `| ${region.region_index} | ${region.title} | ${region.area_count} | ${apRange} | ${totalRequiredAp} | ${region.guardian?.name || ""} | ${region.guardian?.hp || ""} | ${region.guardian?.reward_card || ""} | ${region.next_region} |`
    );
  }
  lines.push("");
  lines.push("## First Region Rows");
  lines.push("");
  lines.push("| area | AP cost | EXP/move | Gold/move | moves to clear | total AP | rewards | progress/move |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const area of data.regions[0].areas) {
    const goldRange =
      area.gold_min_per_move === null || area.gold_max_per_move === null
        ? ""
        : `${area.gold_min_per_move}-${area.gold_max_per_move}`;
    lines.push(
      `| ${area.area} | ${area.cost_ap} | ${area.exp_per_move ?? ""} | ${goldRange} | ${area.required_moves ?? ""} | ${area.required_total_ap ?? ""} | ${area.reward_slots.join(" / ")} | ${area.progress_per_move ?? ""}% |`
    );
  }
  lines.push("");
  lines.push("## Mapping Notes");
  lines.push("");
  lines.push("- `floor_info.cost` matches the AP cost column, not an arbitrary UI label.");
  lines.push("- `/exploration/explore` should eventually return nonzero `gold` and `get_exp` on every normal forward step.");
  lines.push("- `progress` should be derived from a required-move counter per area. The current server's one-percent-per-click behavior is a debug shim, not faithful game logic.");
  lines.push("- `found_item_list` and reward/event branches should be driven by each row's card/factor slots, but branch enum and nested reward payloads still require native/parser evidence.");
  lines.push("- Guardian data is a region-completion gate after the last normal area, not a normal walking-step field.");
  lines.push("- FC2 gives exact Gold ranges for AP 1-4 rows, but several AP 5-6 rows are written as `15EXP/～Gold` or `18EXP/～Gold`; keep EXP as strong evidence and leave those Gold bounds open.");
  lines.push("");
  lines.push("## Evidence Strength");
  lines.push("");
  lines.push("- Strong: first two regions have complete per-area AP, EXP, Gold, required-move, required-total-AP, reward-slot, and next-region data.");
  lines.push("- Strong: first region guardian has HP/EXP/Gold/reward-card data; several later guardian HP/Gold cells are blank on the page and remain open.");
  lines.push("- Medium: later regions still provide AP/EXP/reward slots, but many required-move cells are literal `？` in the source page.");
  lines.push("- Cross-source: zh-Fandom supplies the formula and event categories; FC2 supplies concrete table values. The two agree on EXP = AP x 3 and Gold roughly scaling with AP.");
  lines.push("");
  lines.push("## Current Server Mismatch");
  lines.push("");
  lines.push("- Current `/get_floor.next_floor` increments both `area_id` and `floor_info.id`; FC2 user-facing data says normal progress advances area rows within a region before the guardian. Treat current id movement as client-accepted diagnostics until native/master ID mapping is recovered.");
  lines.push("- Current `/exploration/explore` returns `gold=0` and `get_exp=0`; FC2 and zh-Fandom both say normal walking always yields EXP and Gold.");
  lines.push("- Current background value remains unresolved; FC2 mechanics pages do not identify client resource names for `get_floor.bg`.");
  lines.push("");
  lines.push("## Suggested Next Implementation Frontier");
  lines.push("");
  lines.push("Do not start with battle/fairy/reward branches. The smallest faithful improvement is a no-branch walking table for the first region:");
  lines.push("");
  lines.push("- Keep current accepted hierarchy/native patch unchanged.");
  lines.push("- Add a tiny in-memory exploration state keyed by the request IDs after native/master ID mapping is checked.");
  lines.push("- For normal `/exploration/explore`, return `get_exp = cost_ap * 3`, a deterministic Gold value inside the FC2/Fandom range, and progress derived from `move_count / required_moves`.");
  lines.push("- Only after this is accepted should reward/factor/player/fairy event_type values be recovered from native parser/UI branches.");
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function build() {
  const regions = REGION_TITLES.map(parseRegion);
  return {
    generated_at: new Date().toISOString(),
    source: {
      id: "fc2-ma3ds",
      base_url: "https://ma3ds.wiki.fc2.com/",
    },
    regions,
    summary: {
      region_count: regions.length,
      area_count: regions.reduce((sum, region) => sum + region.area_count, 0),
      known_total_required_ap: regions.reduce((sum, region) => sum + (region.total_required_ap || 0), 0),
      ap_costs: [...new Set(regions.flatMap((region) => region.areas.map((area) => area.cost_ap)))].sort(
        (left, right) => left - right
      ),
    },
  };
}

function runSelfCheck() {
  const rows = expandRowspans(
    extractRows(`
      <tr><th>エリア</th><th>消費<br>AP</th><th>取得カード/因子</th><th>EXP/<br>Gold</th><th>踏破必要探索数</th></tr>
      <tr><td>1</td><td>-1</td><td>A / B</td><td>3EXP<br>16～20Gold</td><td>10回(10AP)</td></tr>
      <tr><td>2</td><td rowspan="2">-2</td><td>C</td><td rowspan="2">6EXP<br>30～40Gold</td><td>11回(22AP)</td></tr>
      <tr><td>3</td><td>D</td><td>12回(24AP)</td></tr>
    `),
    5
  ).map((row) => row.map((cell) => cell?.text || ""));
  assert.equal(rows[2][1], "-2");
  assert.equal(rows[2][3], "6EXP\n30～40Gold");
  assert.deepEqual(parseExpGold("6EXP\n30～40Gold"), {
    exp_per_move: 6,
    gold_min_per_move: 30,
    gold_max_per_move: 40,
  });
  assert.deepEqual(parseExpGold("15EXP\n～Gold"), {
    exp_per_move: 15,
    gold_min_per_move: null,
    gold_max_per_move: null,
  });
  assert.deepEqual(parseRequired("11回(22AP)"), { required_moves: 11, required_total_ap: 22 });
}

function main() {
  runSelfCheck();
  const data = build();
  assert.equal(data.summary.region_count, 7);
  assert.equal(data.regions[0].area_count, 6);
  assert.equal(data.regions[0].areas[0].required_moves, 10);
  assert.equal(data.regions[0].areas[0].gold_min_per_move, 16);
  assert.equal(data.regions[1].total_required_ap, 398);
  assert.equal(data.regions[6].area_count, 25);
  assert.equal(data.regions[6].guardian?.hp, 1500000);
  ensureDir(NORMALIZED_DIR);
  fs.writeFileSync(OUT_JSON, `${JSON.stringify(data, null, 2)}\n`);
  fs.writeFileSync(OUT_REPORT, renderReport(data));
  console.log(`fc2 exploration json=${OUT_JSON}`);
  console.log(`fc2 exploration report=${OUT_REPORT}`);
}

if (require.main === module) {
  main();
}

module.exports = {
  build,
  decodeEntities,
  expandRowspans,
  parseExpGold,
  parseRegionTable,
  parseRequired,
  stripHtml,
};
