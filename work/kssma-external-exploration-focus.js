const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  DATA_DIR,
  ensureDir,
  extractImageTitles,
  hashText,
  readJson,
  writeJson,
} = require("./kssma-external-wiki-fetch");
const { parseSections, stripMarkup } = require("./kssma-external-wiki-extract");

const ROOT = path.resolve(__dirname, "..");
const RAW_PAGE_DIR = path.join(DATA_DIR, "raw", "zh-fandom", "pages");
const NORMALIZED_DIR = path.join(DATA_DIR, "normalized");
const OUT_JSON = path.join(NORMALIZED_DIR, "exploration-focus.json");
const OUT_REPORT = path.join(ROOT, "work", "exploration-external-system-logic-20260626.md");

function loadPageByTitle(title) {
  if (!fs.existsSync(RAW_PAGE_DIR)) {
    throw new Error(`Missing raw page directory: ${RAW_PAGE_DIR}`);
  }
  for (const file of fs.readdirSync(RAW_PAGE_DIR).filter((entry) => entry.endsWith(".json"))) {
    const page = readJson(path.join(RAW_PAGE_DIR, file));
    if (page.title === title) {
      return page;
    }
  }
  throw new Error(`Missing cached zh-fandom page: ${title}`);
}

function splitRawSections(wikitext) {
  const sections = [];
  let current = null;
  for (const line of String(wikitext || "").split(/\r?\n/)) {
    const heading = line.match(/^(={2,5})\s*(.*?)\s*\1$/);
    if (heading) {
      current = {
        level: heading[1].length,
        title: stripMarkup(heading[2]),
        lines: [],
      };
      sections.push(current);
      continue;
    }
    if (current) {
      current.lines.push(line);
    }
  }
  return sections;
}

function templateName(value) {
  const match = String(value || "").match(/\{\{\s*([^|}]+)(?:\|[^}]*)?\}\}/);
  return match ? stripMarkup(match[1]) : stripMarkup(value);
}

function cleanCell(value) {
  let text = String(value || "").trim();
  text = text.replace(/^rowspan\s*=\s*\d+\s*\|\s*/i, "");
  text = text.replace(/^style\s*=\s*"[^"]*"\s*\|\s*/i, "");
  text = text.replace(/\{\{\s*sqrThumb\s*\|\s*([^|}]+)(?:\|[^}]*)?\}\}/gi, "$1");
  text = text.replace(/\{\{\s*([^|}]+)\s*\|\s*normalImg\s*\}\}/gi, "$1");
  return stripMarkup(text);
}

function parseRowspan(cell) {
  const match = String(cell || "").match(/rowspan\s*=\s*(\d+)/i);
  return match ? Number(match[1]) : 1;
}

function parseNumberCell(cell) {
  const cleaned = cleanCell(cell);
  return /^\d+$/.test(cleaned) ? Number(cleaned) : null;
}

function splitCells(line) {
  const trimmed = String(line || "").trim();
  if (!trimmed.startsWith("|")) {
    return [];
  }
  return trimmed.replace(/^\|+/, "").split("||").map((cell) => cell.trim());
}

function finishFloorRow(row, state) {
  if (!row.length) {
    return null;
  }
  const floor = parseNumberCell(row[0]);
  if (floor === null) {
    return null;
  }

  let cost = null;
  let itemStart = 1;
  const explicitCost = parseNumberCell(row[1]);
  if (explicitCost !== null) {
    cost = explicitCost;
    itemStart = 2;
    const span = parseRowspan(row[1]);
    state.activeCost = cost;
    state.activeCostRows = Math.max(0, span - 1);
  } else if (state.activeCostRows > 0) {
    cost = state.activeCost;
    state.activeCostRows -= 1;
  }

  const items = row.slice(itemStart, itemStart + 3).map(cleanCell);
  while (items.length < 3) {
    items.push("");
  }

  return {
    floor,
    ap_cost: cost,
    item_slots: items.map((item, index) => ({
      slot: index + 1,
      text: item || "無",
      is_factor_fragment: /因子/.test(item),
      is_empty: !item || item === "無",
    })),
  };
}

function extractFloorRows(lines) {
  const floors = [];
  let inFloorTable = false;
  let row = [];
  let state = { activeCost: null, activeCostRows: 0 };

  function closeRow() {
    const parsed = finishFloorRow(row, state);
    if (parsed) {
      floors.push(parsed);
    }
    row = [];
  }

  for (const line of lines) {
    if (/!區域!!消費AP!!道具1!!道具2!!道具3/.test(line)) {
      inFloorTable = true;
      row = [];
      state = { activeCost: null, activeCostRows: 0 };
      continue;
    }
    if (!inFloorTable) {
      continue;
    }
    if (/^\|\}/.test(line)) {
      closeRow();
      inFloorTable = false;
      continue;
    }
    if (/^\|-/.test(line)) {
      closeRow();
      continue;
    }
    row.push(...splitCells(line));
  }
  closeRow();
  return floors;
}

function extractAreaMeta(lines) {
  const joined = lines.join("\n");
  const metaLine = lines.find((line) => /\[\[(?:Image|File):/i.test(line) && /\|\|/.test(line)) || "";
  const parts = splitCells(metaLine);
  const imageMatch = metaLine.match(/\[\[(?:Image|File):([^\]|]+)/i);
  return {
    image_ref: imageMatch ? `File:${imageMatch[1].trim()}` : "",
    factor_name: templateName(parts[1] || ""),
    guardian_name: templateName(parts[2] || ""),
    raw_image_refs: extractImageTitles(joined),
  };
}

function extractExplorationAreas(page) {
  const sections = splitRawSections(page.wikitext);
  const areaSections = sections.filter((section) => section.level === 3);
  return areaSections.map((section, index) => {
    const meta = extractAreaMeta(section.lines);
    const floors = extractFloorRows(section.lines).map((floor) => ({
      ...floor,
      region_index: index + 1,
      region_name: section.title,
    }));
    return {
      region_index: index + 1,
      name: section.title,
      ...meta,
      floor_count: floors.length,
      ap_costs: [...new Set(floors.map((floor) => floor.ap_cost).filter((value) => value !== null))],
      floors,
    };
  });
}

function bulletSection(page, title) {
  const section = parseSections(page.wikitext).find((entry) => entry.title === title);
  return section ? section.bullets : [];
}

function buildSource(page) {
  return {
    title: page.title,
    pageid: page.pageid,
    source_url: page.source_url,
    revision: page.revision?.revid || null,
    revision_timestamp: page.revision?.timestamp || null,
    wikitext_sha256: page.wikitext_sha256 || hashText(page.wikitext || ""),
  };
}

function buildFocus() {
  const exploration = loadPageByTitle("探索");
  const beginner = loadPageByTitle("新手指南");
  const areas = extractExplorationAreas(exploration);
  const allFloors = areas.flatMap((area) => area.floors);

  return {
    generated_at: new Date().toISOString(),
    frontier:
      "exploration/floor returns 200 and createFloorList builds a non-empty scene vector, but floor_list is still not visible.",
    sources: {
      exploration: buildSource(exploration),
      beginner: buildSource(beginner),
    },
    mechanics: {
      basic: bulletSection(exploration, "基本"),
      guardian: bulletSection(exploration, "秘境守護者"),
      regions: bulletSection(exploration, "探索地域"),
      beginner_exploration: bulletSection(beginner, "探索"),
      ap: bulletSection(beginner, "AP"),
      bc: bulletSection(beginner, "BC"),
      deck: bulletSection(beginner, "編輯牌組"),
      friendship_gacha: bulletSection(beginner, "友情點數抽獎"),
    },
    structured_regions: areas,
    summary: {
      region_count: areas.length,
      floor_count: allFloors.length,
      ap_costs: [...new Set(allFloors.map((floor) => floor.ap_cost).filter((value) => value !== null))].sort(
        (left, right) => left - right
      ),
      factor_fragment_floor_count: allFloors.filter((floor) =>
        floor.item_slots.some((slot) => slot.is_factor_fragment)
      ).length,
      image_refs: areas.map((area) => area.image_ref).filter(Boolean),
    },
  };
}

function apRange(values) {
  if (!values.length) {
    return "";
  }
  return values.length === 1 ? String(values[0]) : `${values[0]}-${values[values.length - 1]}`;
}

function renderSource(source) {
  return `${source.title} pageid=${source.pageid}, revid=${source.revision}, timestamp=${source.revision_timestamp}, sha256=${source.wikitext_sha256}`;
}

function renderReport(focus) {
  const lines = [];
  lines.push("# Exploration External System Logic");
  lines.push("");
  lines.push(`Generated: ${focus.generated_at}`);
  lines.push("");
  lines.push("## Frontier");
  lines.push("");
  lines.push(focus.frontier);
  lines.push("");
  lines.push("This card is external evidence only. It names original-game mechanics and value-domain candidates; it does not authorize changing `server/bootstrap-server.js` without native/schema proof.");
  lines.push("");
  lines.push("## Sources");
  lines.push("");
  lines.push(`- ${renderSource(focus.sources.exploration)}`);
  lines.push(`  - ${focus.sources.exploration.source_url}`);
  lines.push(`- ${renderSource(focus.sources.beginner)}`);
  lines.push(`  - ${focus.sources.beginner.source_url}`);
  lines.push("");
  lines.push("## System Logic Extracted");
  lines.push("");
  lines.push("- Exploration is the main early source of Gold and EXP.");
  lines.push("- The user-facing progression is region -> area/floor -> walking progress -> 100% -> next area/floor.");
  lines.push("- Each move consumes AP; the zh wiki gives EXP as AP cost times 3 and Gold as AP cost times 20 times a random 0.8-1.0 multiplier.");
  lines.push("- Each move also rolls one side event: AP recovery, BC recovery, fairy encounter during fairy events, card reward, factor fragment, other-player encounter, or no extra event.");
  lines.push("- Region completion is separate from a normal floor row: all areas/floors plus the guardian must be cleared before the next region opens.");
  lines.push("- Beginner guide cross-check: AP recovers 1 every 3 minutes; BC recovers 1 every 1 minute; card inventory cap 350 can block exploration and gacha.");
  lines.push("");
  lines.push("## Structured Region Data");
  lines.push("");
  lines.push("| # | region | image | guardian | factor | floors | AP costs | factor floors |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const area of focus.structured_regions) {
    const factorFloors = area.floors.filter((floor) => floor.item_slots.some((slot) => slot.is_factor_fragment)).length;
    lines.push(
      `| ${area.region_index} | ${area.name} | ${area.image_ref} | ${area.guardian_name} | ${area.factor_name} | ${area.floor_count} | ${apRange(area.ap_costs)} | ${factorFloors} |`
    );
  }
  lines.push("");
  lines.push(`Full structured data is written to \`${path.relative(ROOT, OUT_JSON).replaceAll("\\", "/")}\`.`);
  lines.push("");
  lines.push("## First Region Floor Rows");
  lines.push("");
  lines.push("| region | floor | AP | item1 | item2 | item3 |");
  lines.push("| --- | --- | --- | --- | --- | --- |");
  for (const floor of focus.structured_regions[0]?.floors || []) {
    lines.push(
      `| ${floor.region_name} | ${floor.floor} | ${floor.ap_cost} | ${floor.item_slots[0].text} | ${floor.item_slots[1].text} | ${floor.item_slots[2].text} |`
    );
  }
  lines.push("");
  lines.push("## Mapping To Current Blocker");
  lines.push("");
  lines.push("| External fact | Local protocol implication | Server action now |");
  lines.push("| --- | --- | --- |");
  lines.push("| Wiki has 6 regions and per-region area/floor tables | `/exploration/area` should eventually expose multiple regions/locations, but the current one-area baseline is a diagnostic stub | Do not expand area list until floor_list renders |");
  lines.push("| Each area/floor has an AP consumption value | `floor_info.cost` is an AP-cost value-domain candidate; current `cost=1` matches the first listed floor | Do not sweep costs; the visible row is missing even with a non-empty scene vector |");
  lines.push("| Each area/floor has three item/factor slots, with slot 1 most common and slot 3 least common | `found_item_list` likely drives row reward icons or later reward pools | Do not fake found items for visibility; native evidence says empty found items still continue row construction |");
  lines.push("| Progress reaches 100% before the next area/floor | `progress` belongs to walking/floor progress, not to the existence of a selectable row | Keep `progress=0` as a valid unopened/current-floor state until a consumer proves otherwise |");
  lines.push("| Guardians gate region completion | `boss_id`/guardian data is later boss/clear logic | Do not use boss data to debug the missing floor_list row |");
  lines.push("");
  lines.push("## Next Smallest Observable");
  lines.push("");
  lines.push("The external data points away from schema/value guessing and toward the later UI consumer:");
  lines.push("");
  lines.push("- Instrument `_PickList::setPropertyValues` to prove whether this component receives a `list` property whose value is `floor_list`.");
  lines.push("- Instrument `_PickList::setRecords` to prove whether it is called with the scene `floor_list` vector pointer and positive count.");
  lines.push("- Only if `setRecords` receives positive records but draws nothing should the next branch inspect `_AnmExplorationList` item fields such as type/unlock/progress/cost visuals.");
  lines.push("");
  lines.push("## Do Not Repeat");
  lines.push("");
  lines.push("- No `floor_info/id` sweep; id 1 was already tested and failed.");
  lines.push("- No empty-vector/parser chase; runtime proved `_ExplorationModel+0x58` count is greater than 0.");
  lines.push("- No post-data `floor_list_active2`, update-all, or direct `updateProperty(floor_list)` retry without a new PickList observable.");
  lines.push("- No server merge from wiki values before native parser/schema and runtime observables agree.");
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function runSelfCheck() {
  const lines = [
    "!區域!!消費AP!!道具1!!道具2!!道具3",
    "|-",
    "|1||1",
    "||{{sqrThumb|A}}",
    "||{{sqrThumb|B}}",
    "||無",
    "|-",
    "|2",
    "|rowspan=2|2",
    "||{{sqrThumb|C}}",
    "||因子碎片",
    "||無",
    "|-",
    "|3",
    "||{{sqrThumb|D}}",
    "||因子碎片",
    "||無",
    "|}",
  ];
  const rows = extractFloorRows(lines);
  assert.equal(rows.length, 3);
  assert.deepEqual(rows.map((row) => row.ap_cost), [1, 2, 2]);
  assert.equal(rows[1].item_slots[1].is_factor_fragment, true);
  assert.equal(cleanCell("{{sqrThumb|第二型マロース}}"), "第二型マロース");
}

function main() {
  runSelfCheck();
  const focus = buildFocus();
  assert.equal(focus.summary.region_count, 6);
  assert.equal(focus.summary.floor_count, 70);
  assert.deepEqual(
    focus.structured_regions.map((area) => area.floor_count),
    [6, 9, 10, 10, 15, 20]
  );
  assert.deepEqual(focus.summary.ap_costs, [1, 2, 3, 4, 5, 6]);
  ensureDir(NORMALIZED_DIR);
  writeJson(OUT_JSON, focus);
  fs.writeFileSync(OUT_REPORT, renderReport(focus));
  console.log(`exploration focus json=${OUT_JSON}`);
  console.log(`exploration focus report=${OUT_REPORT}`);
}

if (require.main === module) {
  main();
}

module.exports = {
  OUT_JSON,
  OUT_REPORT,
  buildFocus,
  cleanCell,
  extractExplorationAreas,
  extractFloorRows,
};
