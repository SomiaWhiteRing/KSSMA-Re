const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { DATA_DIR, RAW_DIR, SYSTEM_TOPICS, ensureDir, readJson } = require("./kssma-external-wiki-fetch");
const { JSONL_FILE, loadJsonl } = require("./kssma-external-wiki-extract");

function parseArgs(argv) {
  const args = {};
  for (const item of argv) {
    if (item === "--help" || item === "-h") {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${item}`);
    }
  }
  return args;
}

function todayStamp() {
  const date = new Date();
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("");
}

function countBy(values, getKey) {
  const result = {};
  for (const value of values) {
    const key = getKey(value);
    result[key] = (result[key] || 0) + 1;
  }
  return result;
}

function groupBy(values, getKey) {
  const result = new Map();
  for (const value of values) {
    const key = getKey(value);
    if (!result.has(key)) {
      result.set(key, []);
    }
    result.get(key).push(value);
  }
  return result;
}

function loadManifests() {
  if (!fs.existsSync(RAW_DIR)) {
    return [];
  }
  return fs
    .readdirSync(RAW_DIR)
    .map((sourceId) => path.join(RAW_DIR, sourceId, "manifest.json"))
    .filter((file) => fs.existsSync(file))
    .map(readJson);
}

function cardFieldCoverage(cards) {
  const fields = [
    ["rarity", (card) => card.rarity !== null],
    ["cost", (card) => card.cost !== null],
    ["faction", (card) => Boolean(card.faction)],
    ["gender", (card) => Boolean(card.gender)],
    ["lv_max", (card) => card.lv_max !== null],
    ["skill_name", (card) => Boolean(card.skill_name)],
    ["illustrator", (card) => Boolean(card.illustrator)],
    ["image_refs", (card) => card.image_refs?.length > 0],
  ];
  return fields.map(([field, test]) => ({
    field,
    present: cards.filter(test).length,
    total: cards.length,
  }));
}

function findDuplicateCards(cards) {
  return [...groupBy(cards, (card) => card.source_name.toLowerCase()).entries()]
    .filter(([, values]) => values.length > 1)
    .map(([name, values]) => ({ name, count: values.length, sources: values.map((card) => card.source_title) }));
}

function findConflicts(cards) {
  const grouped = groupBy(cards, (card) => card.source_name.toLowerCase());
  const conflicts = [];
  for (const [name, values] of grouped.entries()) {
    if (values.length < 2) {
      continue;
    }
    for (const field of ["rarity", "cost", "faction"]) {
      const seen = new Set(values.map((card) => card[field]).filter((value) => value !== "" && value !== null));
      if (seen.size > 1) {
        conflicts.push({ name, field, values: [...seen] });
      }
    }
  }
  return conflicts;
}

function systemCoverage(systemPages) {
  const byTopic = groupBy(systemPages, (page) => page.topic);
  return Object.keys(SYSTEM_TOPICS).map((topic) => {
    const pages = byTopic.get(topic) || [];
    return {
      topic,
      pages: pages.length,
      rates_or_timers: [...new Set(pages.flatMap((page) => page.rates_or_timers || []))],
      source_titles: pages.map((page) => page.source_title),
    };
  });
}

function localMasterCandidateNotes(cards) {
  const candidates = cards
    .filter((card) => card.rarity !== null && card.cost !== null && card.normal_hp_atk?.lv1_hp !== null)
    .slice(0, 20)
    .map((card) => ({
      name: card.source_name,
      rarity: card.rarity,
      cost: card.cost,
      hp: card.normal_hp_atk.lv1_hp,
      atk: card.normal_hp_atk.lv1_atk,
      source: card.source_url,
    }));
  return candidates;
}

function markdownTable(rows, columns) {
  const header = `| ${columns.map((column) => column.label).join(" | ")} |`;
  const divider = `| ${columns.map(() => "---").join(" | ")} |`;
  const body = rows.map((row) => `| ${columns.map((column) => String(column.value(row) ?? "").replaceAll("|", "\\|")).join(" | ")} |`);
  return [header, divider, ...body].join("\n");
}

function buildReport(entities, manifests) {
  const sourcePages = entities.filter((entity) => entity.type === "source_page");
  const cards = entities.filter((entity) => entity.type === "card");
  const systemPages = entities.filter((entity) => entity.type === "system_page");
  const entityCounts = countBy(entities, (entity) => entity.type);
  const structured = sourcePages.filter((page) => page.parsing_status === "structured");
  const textOnly = sourcePages.filter((page) => page.parsing_status === "text-evidence-only");
  const cardsMissingImages = cards.filter((card) => !card.image_refs?.length);
  const coverage = cardFieldCoverage(cards);
  const duplicates = findDuplicateCards(cards);
  const conflicts = findConflicts(cards);
  const systems = systemCoverage(systemPages);
  const candidates = localMasterCandidateNotes(cards);
  const reportPath = path.join(path.dirname(__dirname), "work", `external-data-branch-${todayStamp()}.md`);

  const lines = [];
  lines.push("# External Data Branch");
  lines.push("");
  lines.push("Frontier: build an external evidence pipeline for KSSMA systems and card data without changing the local bootstrap server.");
  lines.push("");
  lines.push("## Sources");
  for (const manifest of manifests) {
    lines.push(`- ${manifest.source.id}: pages=${manifest.pages.length}, images=${manifest.images.length}, skipped=${manifest.skipped.length}, api=${manifest.source.api}`);
  }
  lines.push("- atwiki kssma: manual cross-check source only in this phase because direct automation can hit Cloudflare.");
  lines.push("- Wayback/CDX: optional future supplement, not required for the current pipeline.");
  lines.push("");
  lines.push("## Entity Counts");
  lines.push(markdownTable(
    Object.entries(entityCounts).map(([type, count]) => ({ type, count })),
    [
      { label: "type", value: (row) => row.type },
      { label: "count", value: (row) => row.count },
    ]
  ));
  lines.push("");
  lines.push("## Parsing Status");
  lines.push(`- structured pages: ${structured.length}`);
  lines.push(`- text evidence only pages: ${textOnly.length}`);
  lines.push(`- conflicts detected: ${conflicts.length}`);
  lines.push(`- cards missing image refs: ${cardsMissingImages.length}`);
  lines.push("");
  lines.push("## Card Field Coverage");
  lines.push(markdownTable(coverage, [
    { label: "field", value: (row) => row.field },
    { label: "present", value: (row) => row.present },
    { label: "total", value: (row) => row.total },
  ]));
  lines.push("");
  lines.push("## System Topic Coverage");
  lines.push(markdownTable(systems, [
    { label: "topic", value: (row) => row.topic },
    { label: "pages", value: (row) => row.pages },
    { label: "rules", value: (row) => row.rates_or_timers.join("; ") },
    { label: "sources", value: (row) => row.source_titles.join(", ") },
  ]));
  lines.push("");
  lines.push("## Structured Examples");
  for (const card of cards.slice(0, 8)) {
    lines.push(`- card: ${card.source_name} rarity=${card.rarity ?? ""} cost=${card.cost ?? ""} skill=${card.skill_name || ""} source=${card.source_url}`);
  }
  for (const system of systemPages.slice(0, 5)) {
    lines.push(`- system: ${system.topic} rules=${(system.rates_or_timers || []).join("; ")} source=${system.source_url}`);
  }
  lines.push("");
  lines.push("## Manual Review");
  if (conflicts.length) {
    lines.push("Conflicts:");
    for (const conflict of conflicts.slice(0, 20)) {
      lines.push(`- ${conflict.name}: ${conflict.field} => ${conflict.values.join(", ")}`);
    }
  } else {
    lines.push("- No duplicate-card field conflicts detected in the current sample.");
  }
  if (duplicates.length) {
    lines.push("Duplicates:");
    for (const duplicate of duplicates.slice(0, 20)) {
      lines.push(`- ${duplicate.name}: ${duplicate.count} pages`);
    }
  }
  lines.push("");
  lines.push("## Local Masterdata Candidate Notes");
  lines.push("These are candidates for later matching against local masterdata, not merged server data.");
  lines.push(markdownTable(candidates, [
    { label: "name", value: (row) => row.name },
    { label: "rarity", value: (row) => row.rarity },
    { label: "cost", value: (row) => row.cost },
    { label: "lv1 hp", value: (row) => row.hp },
    { label: "lv1 atk", value: (row) => row.atk },
  ]));
  lines.push("");
  lines.push("## Commands");
  lines.push("```powershell");
  lines.push("node .\\work\\kssma-external-wiki-fetch.js --source zh-fandom --limit 20");
  lines.push("node .\\work\\kssma-external-wiki-fetch.js --source en-fandom --limit 20");
  lines.push("node .\\work\\kssma-external-wiki-extract.js");
  lines.push("node .\\work\\kssma-external-wiki-report.js");
  lines.push("```");
  lines.push("");
  lines.push("## Conclusion");
  lines.push("External wiki data is now a reproducible evidence source. Keep it separate from native schema proof and bootstrap-server responses until a route-specific handoff names one field/value to test.");
  lines.push("");

  return {
    markdown: lines.join("\n"),
    reportPath,
    summary: {
      generatedAt: new Date().toISOString(),
      reportPath,
      entityCounts,
      structuredPages: structured.length,
      textEvidenceOnlyPages: textOnly.length,
      conflicts: conflicts.length,
      cardsMissingImages: cardsMissingImages.length,
      systemCoverage: systems,
    },
  };
}

function runSelfCheck() {
  const entities = [
    {
      type: "source_page",
      parsing_status: "structured",
      source_title: "A",
    },
    {
      type: "card",
      source_name: "A",
      source_title: "A",
      source_url: "u",
      rarity: 3,
      cost: 8,
      faction: "m",
      gender: "m",
      lv_max: 30,
      skill_name: "None",
      illustrator: "X",
      image_refs: ["File:a.png"],
      normal_hp_atk: { lv1_hp: 1, lv1_atk: 2 },
    },
    {
      type: "system_page",
      topic: "AP/BC",
      source_title: "新手指南",
      source_url: "u",
      rates_or_timers: ["AP每3分鐘回復1點"],
    },
  ];
  const report = buildReport(entities, [
    { source: { id: "test", api: "https://example.invalid" }, pages: [1], images: [], skipped: [] },
  ]);
  assert.match(report.markdown, /Card Field Coverage/);
  assert.match(report.markdown, /AP每3分鐘回復1點/);
}

function printHelp() {
  console.log(`Usage: node work/kssma-external-wiki-report.js

Reads normalized JSONL and writes work/external-data-branch-YYYYMMDD.md.
`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printHelp();
    return;
  }
  runSelfCheck();
  const entities = loadJsonl(JSONL_FILE);
  const manifests = loadManifests();
  const report = buildReport(entities, manifests);
  fs.writeFileSync(report.reportPath, report.markdown);
  ensureDir(DATA_DIR);
  fs.writeFileSync(path.join(DATA_DIR, "report-summary.json"), `${JSON.stringify(report.summary, null, 2)}\n`);
  console.log(`report=${report.reportPath}`);
  console.log(`entities=${entities.length} structured=${report.summary.structuredPages} text_only=${report.summary.textEvidenceOnlyPages}`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildReport,
  cardFieldCoverage,
  findConflicts,
  systemCoverage,
};
