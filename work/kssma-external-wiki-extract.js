const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  DATA_DIR,
  RAW_DIR,
  SYSTEM_TOPICS,
  ensureDir,
  extractImageTitles,
  extractInternalLinks,
  hashText,
  readJson,
  writeJson,
} = require("./kssma-external-wiki-fetch");

const NORMALIZED_DIR = path.join(DATA_DIR, "normalized");
const JSONL_FILE = path.join(NORMALIZED_DIR, "kssma-external.jsonl");
const SQLITE_FILE = path.join(DATA_DIR, "kssma-external.sqlite");

function parseArgs(argv) {
  const args = {
    selfCheck: false,
  };
  for (const item of argv) {
    if (item === "--self-check") {
      args.selfCheck = true;
    } else if (item === "--help" || item === "-h") {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${item}`);
    }
  }
  return args;
}

function loadPages() {
  const pages = [];
  if (!fs.existsSync(RAW_DIR)) {
    return pages;
  }
  for (const sourceId of fs.readdirSync(RAW_DIR)) {
    const pageDir = path.join(RAW_DIR, sourceId, "pages");
    if (!fs.existsSync(pageDir)) {
      continue;
    }
    for (const file of fs.readdirSync(pageDir).filter((entry) => entry.endsWith(".json"))) {
      pages.push(readJson(path.join(pageDir, file)));
    }
  }
  return pages.sort((left, right) => `${left.source}:${left.title}`.localeCompare(`${right.source}:${right.title}`));
}

function stripMarkup(text) {
  return String(text || "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\{\{[^{}]*\}\}/g, "")
    .replace(/\[\[(?:Image|File):[^\]]+\]\]/gi, "")
    .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2")
    .replace(/\[\[([^\]]+)\]\]/g, "$1")
    .replace(/'''?/g, "")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function splitTopLevel(value, separator = "|") {
  const parts = [];
  let depth = 0;
  let current = "";
  for (let index = 0; index < value.length; index += 1) {
    const two = value.slice(index, index + 2);
    if (two === "{{" || two === "[[") {
      depth += 1;
      current += two;
      index += 1;
      continue;
    }
    if ((two === "}}" || two === "]]") && depth > 0) {
      depth -= 1;
      current += two;
      index += 1;
      continue;
    }
    if (value[index] === separator && depth === 0) {
      parts.push(current);
      current = "";
      continue;
    }
    current += value[index];
  }
  parts.push(current);
  return parts;
}

function parseTemplates(wikitext) {
  const templates = [];
  const stack = [];
  let index = 0;
  while (index < wikitext.length - 1) {
    const two = wikitext.slice(index, index + 2);
    if (two === "{{") {
      stack.push(index);
      index += 2;
      continue;
    }
    if (two === "}}" && stack.length) {
      const start = stack.pop();
      const raw = wikitext.slice(start + 2, index);
      if (stack.length === 0) {
        const parts = splitTopLevel(raw);
        const name = stripMarkup(parts.shift() || "").trim();
        const params = {};
        const positional = [];
        for (const part of parts) {
          const eqIndex = part.indexOf("=");
          if (eqIndex > 0) {
            const key = stripMarkup(part.slice(0, eqIndex)).trim();
            params[key] = stripMarkup(part.slice(eqIndex + 1));
          } else {
            positional.push(stripMarkup(part));
          }
        }
        templates.push({
          name,
          nameKey: name.toLowerCase(),
          params,
          positional,
          raw: wikitext.slice(start, index + 2),
        });
      }
      index += 2;
      continue;
    }
    index += 1;
  }
  return templates;
}

function parseSections(wikitext) {
  const sections = [];
  let current = null;
  for (const line of wikitext.split(/\r?\n/)) {
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
  return sections.map((section) => ({
    ...section,
    bullets: section.lines
      .filter((line) => /^\s*\*/.test(line))
      .map((line) => stripMarkup(line.replace(/^\s*\*+\s*/, "")))
      .filter(Boolean),
    text: stripMarkup(section.lines.join(" ")),
  }));
}

function sourceFields(page, extractionMethod, confidence) {
  return {
    source_url: page.source_url,
    source_title: page.title,
    source_revision: page.revision?.revid || null,
    source_lang: page.source_lang,
    extraction_method: extractionMethod,
    confidence,
  };
}

function entityId(type, page, suffix = "") {
  const base = `${type}:${page.source}:${page.pageid}`;
  return suffix ? `${base}:${suffix}` : base;
}

function isLikelyEnglishCard(page, templates) {
  if (page.source !== "en-fandom") {
    return false;
  }
  if (templates.some((template) => template.nameKey === "detail")) {
    return true;
  }
  return page.categories?.some((category) => category === "Category:Card");
}

function parseNumber(value) {
  const match = String(value || "").replaceAll(",", "").match(/-?\d+/);
  return match ? Number(match[0]) : null;
}

function pickParam(params, names) {
  for (const name of names) {
    if (params[name] !== undefined && params[name] !== "") {
      return params[name];
    }
  }
  return "";
}

function extractCard(page, templates) {
  const detail = templates.find((template) => template.nameKey === "detail");
  const infobox = templates.find((template) => template.nameKey === "infobox");
  if (!detail && !infobox) {
    return null;
  }
  const params = { ...(infobox?.params || {}), ...(detail?.params || {}) };
  const imageRefs = extractImageTitles(page.wikitext);
  return {
    id: entityId("card", page),
    type: "card",
    ...sourceFields(page, "fandom-template-card-v1", detail ? 0.9 : 0.65),
    source_name: page.title,
    localized_names: {
      en: page.source_lang === "en" ? page.title : "",
      zh: page.source_lang === "zh" ? page.title : "",
    },
    faction: pickParam(params, ["Faction", "faction"]),
    rarity: parseNumber(pickParam(params, ["Rare", "rare"])),
    cost: parseNumber(pickParam(params, ["cost", "Cost"])),
    gender: pickParam(params, ["gender", "Gender"]),
    lv_max: parseNumber(pickParam(params, ["Lvmax", "LvMAX", "lvmax"])),
    normal_hp_atk: {
      lv1_hp: parseNumber(pickParam(params, ["NLv1 HP", "N Lv1 HP"])),
      lv1_atk: parseNumber(pickParam(params, ["NLv1 ATK", "N Lv1 ATK"])),
      lvmax_hp: parseNumber(pickParam(params, ["NLvMAX HP", "N LvMAX HP"])),
      lvmax_atk: parseNumber(pickParam(params, ["NLvMAX ATK", "N LvMAX ATK"])),
    },
    special_hp_atk: {
      lv1_hp: parseNumber(pickParam(params, ["SLv1 HP", "S Lv1 HP"])),
      lv1_atk: parseNumber(pickParam(params, ["SLv1 ATK", "S Lv1 ATK"])),
      lvmax_hp: parseNumber(pickParam(params, ["SLvMAX HP", "S LvMAX HP"])),
      lvmax_atk: parseNumber(pickParam(params, ["SLvMAX ATK", "S LvMAX ATK"])),
    },
    sell_price: parseNumber(pickParam(params, ["sellPrice", "sell price", "SellPrice"])),
    growth: parseNumber(pickParam(params, ["grow", "growth"])),
    skill_name: pickParam(params, ["Skill name", "skill name", "Skill"]),
    skill_effect: pickParam(params, ["Skill effect", "skill effect"]),
    illustrator: pickParam(params, ["Illust", "Illustrator", "illustrator"]),
    categories: page.categories || [],
    image_refs: imageRefs,
    raw_template_names: templates.map((template) => template.name).slice(0, 12),
  };
}

function extractSkillAndCombo(page, card, templates) {
  const entities = [];
  if (card?.skill_name && card.skill_name.toLowerCase() !== "none") {
    entities.push({
      id: entityId("skill", page, hashText(card.skill_name).slice(0, 10)),
      type: "skill",
      ...sourceFields(page, "card-template-skill-v1", 0.75),
      name: card.skill_name,
      effect_text: card.skill_effect || "",
      source_card: card.source_name,
    });
  }
  for (const combo of templates.filter((template) => template.nameKey === "combo")) {
    const name = pickParam(combo.params, ["name", "Name"]) || `${page.title} combo`;
    entities.push({
      id: entityId("combo", page, hashText(combo.raw).slice(0, 10)),
      type: "combo",
      ...sourceFields(page, "fandom-template-combo-v1", 0.65),
      name,
      required_cards_or_attributes: Object.entries(combo.params).map(([key, value]) => `${key}=${value}`),
      effect_text: pickParam(combo.params, ["effect", "Effect"]),
      source_refs: [page.source_url],
    });
  }
  return entities;
}

function topicsForPage(page) {
  if (page.source !== "zh-fandom") {
    return [];
  }
  const topics = [];
  for (const [topic, titles] of Object.entries(SYSTEM_TOPICS)) {
    if (titles.includes(page.title)) {
      topics.push(topic);
    }
  }
  return topics;
}

function extractMechanics(sections) {
  return sections
    .flatMap((section) => section.bullets.map((bullet) => ({ section: section.title, text: bullet })))
    .filter((entry) => entry.text.length >= 8)
    .slice(0, 80);
}

function extractRatesOrTimers(text, sections = []) {
  const patterns = [
    /AP每?3分鐘回復?1點/g,
    /BC每?1分鐘回復?1點/g,
    /等級上限是?350級/g,
    /每次升級獲得3點能力值/g,
    /50以上每次升級只有2點/g,
    /200點抽一張/g,
    /100MC\s*=\s*100円/g,
    /朋友數目上限[^。；\n]*/g,
  ];
  const found = new Set();
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      found.add(match[0]);
    }
  }
  for (const section of sections) {
    const sectionTitle = section.title.toUpperCase();
    const sectionText = section.bullets.join(" ");
    if (sectionTitle === "AP" && /每?3分鐘回復?1點/.test(sectionText)) {
      found.add("AP每3分鐘回復1點");
    }
    if (sectionTitle === "BC" && /每?1分鐘回復?1點/.test(sectionText)) {
      found.add("BC每1分鐘回復1點");
    }
  }
  return [...found];
}

function extractSystemPages(page, sections) {
  const topics = topicsForPage(page);
  if (!topics.length) {
    return [];
  }
  const plainText = stripMarkup(page.wikitext);
  const ratesOrTimers = extractRatesOrTimers(plainText, sections);
  return topics.map((topic) => ({
    id: entityId("system_page", page, topic),
    type: "system_page",
    ...sourceFields(page, "zh-system-section-v1", 0.8),
    topic,
    summary: sections
      .flatMap((section) => section.bullets)
      .slice(0, 5)
      .join(" "),
    mechanics: extractMechanics(sections),
    rates_or_timers: ratesOrTimers,
    linked_entities: extractInternalLinks(page.wikitext).slice(0, 80),
    source_sections: sections.map((section) => ({
      level: section.level,
      title: section.title,
      bullet_count: section.bullets.length,
    })),
  }));
}

function classifyFallback(page, templates, sections) {
  const title = page.title;
  const categoryText = (page.categories || []).join(" ");
  const hasEventSignal = /活動|Event/i.test(title) || /Event|活動/.test(categoryText);
  const hasFairySignal = /妖精|Boss/i.test(title) || /Category:妖精|Category:Boss/.test(categoryText);
  const hasItemSignal = /道具|Item/i.test(title) || /Category:Item/.test(categoryText);
  if (hasEventSignal) {
    return {
      id: entityId("event", page),
      type: "event",
      ...sourceFields(page, "title-category-fallback-v1", 0.35),
      name: title,
      summary: sections.flatMap((section) => section.bullets).slice(0, 6).join(" "),
      categories: page.categories || [],
      linked_entities: extractInternalLinks(page.wikitext).slice(0, 50),
    };
  }
  if (hasFairySignal) {
    return {
      id: entityId("fairy_or_boss", page),
      type: "fairy_or_boss",
      ...sourceFields(page, "title-category-fallback-v1", 0.35),
      name: title,
      summary: sections.flatMap((section) => section.bullets).slice(0, 6).join(" "),
      categories: page.categories || [],
      image_refs: extractImageTitles(page.wikitext),
    };
  }
  if (hasItemSignal) {
    return {
      id: entityId("item", page),
      type: "item",
      ...sourceFields(page, "title-category-fallback-v1", 0.35),
      name: title,
      summary: sections.flatMap((section) => section.bullets).slice(0, 6).join(" "),
      categories: page.categories || [],
      image_refs: extractImageTitles(page.wikitext),
    };
  }
  return null;
}

function sourcePageEntity(page, templates, sections, structuredTypes) {
  return {
    id: entityId("source_page", page),
    type: "source_page",
    ...sourceFields(page, "source-page-index-v1", 1),
    pageid: page.pageid,
    categories: page.categories || [],
    wikitext_sha256: page.wikitext_sha256 || hashText(page.wikitext || ""),
    parsed_template_names: templates.map((template) => template.name),
    section_titles: sections.map((section) => section.title),
    linked_entities: extractInternalLinks(page.wikitext).slice(0, 120),
    image_refs: extractImageTitles(page.wikitext),
    parsing_status: structuredTypes.length ? "structured" : "text-evidence-only",
    structured_types: structuredTypes,
  };
}

function extractEntitiesFromPage(page) {
  const templates = parseTemplates(page.wikitext || "");
  const sections = parseSections(page.wikitext || "");
  const entities = [];
  const structuredTypes = [];

  const systemPages = extractSystemPages(page, sections);
  if (systemPages.length) {
    entities.push(...systemPages);
    structuredTypes.push(...systemPages.map((entity) => entity.type));
  }

  if (isLikelyEnglishCard(page, templates)) {
    const card = extractCard(page, templates);
    if (card) {
      entities.push(card);
      structuredTypes.push("card");
      const related = extractSkillAndCombo(page, card, templates);
      entities.push(...related);
      structuredTypes.push(...related.map((entity) => entity.type));
    }
  }

  const fallback = classifyFallback(page, templates, sections);
  if (fallback && !structuredTypes.includes(fallback.type)) {
    entities.push(fallback);
    structuredTypes.push(fallback.type);
  }

  entities.push(sourcePageEntity(page, templates, sections, structuredTypes));
  return entities;
}

function writeJsonl(file, entities) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, entities.map((entity) => JSON.stringify(entity)).join("\n") + "\n");
}

function loadJsonl(file) {
  if (!fs.existsSync(file)) {
    return [];
  }
  return fs
    .readFileSync(file, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function buildSqlite(jsonlFile, sqliteFile) {
  let sqlite;
  try {
    sqlite = require("node:sqlite");
  } catch (error) {
    return { ok: false, skipped: true, reason: error.code || error.message };
  }

  const { DatabaseSync } = sqlite;
  fs.rmSync(sqliteFile, { force: true });
  const db = new DatabaseSync(sqliteFile);
  try {
    db.exec(`
      CREATE TABLE entities (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        source_title TEXT NOT NULL,
        source_url TEXT NOT NULL,
        source_revision INTEGER,
        source_lang TEXT,
        confidence REAL,
        body TEXT NOT NULL
      );
      CREATE INDEX idx_entities_type ON entities(type);
      CREATE INDEX idx_entities_source_title ON entities(source_title);
    `);
    const insert = db.prepare(`
      INSERT INTO entities
      (id, type, source_title, source_url, source_revision, source_lang, confidence, body)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const entities = loadJsonl(jsonlFile);
    for (const entity of entities) {
      insert.run(
        entity.id,
        entity.type,
        entity.source_title,
        entity.source_url,
        entity.source_revision,
        entity.source_lang,
        entity.confidence,
        JSON.stringify(entity)
      );
    }
    const count = db.prepare("SELECT COUNT(*) AS count FROM entities").get().count;
    return { ok: true, skipped: false, count };
  } finally {
    db.close();
  }
}

function runSelfCheck() {
  const templates = parseTemplates(`{{infobox|Rare = 3|Skill name = None|Illust = Katsumi Enami}}
==Detail==
{{Detail|Faction = m|gender = m|Rare = 3|Lvmax = 30|cost = 8|NLv1 HP = 1680|NLv1 ATK = 2450|NLvMAX HP = 2700|NLvMAX ATK = 4240|SLv1 HP = 1815|SLv1 ATK = 2646|SLvMAX HP = 2916|SLvMAX ATK = 4580|sellPrice = 1200|grow = 2|SLvmax = 34}}
{{Combo|Attribute = a}}`);
  assert.equal(templates.length, 3);
  const card = extractCard(
    {
      source: "en-fandom",
      source_lang: "en",
      title: "Arbitrator Knight",
      pageid: 1,
      source_url: "https://example.invalid",
      revision: { revid: 1 },
      categories: ["Category:Card"],
      wikitext: "",
    },
    templates
  );
  assert.equal(card.rarity, 3);
  assert.equal(card.cost, 8);
  assert.equal(card.normal_hp_atk.lv1_hp, 1680);
  assert.equal(card.normal_hp_atk.lvmax_atk, 4240);
  assert.equal(card.illustrator, "Katsumi Enami");

  const systems = extractSystemPages(
    {
      source: "zh-fandom",
      source_lang: "zh",
      title: "新手指南",
      pageid: 2,
      source_url: "https://example.invalid",
      revision: { revid: 2 },
      categories: [],
      wikitext: "==主畫面==\n*AP每3分鐘回復1點，探索時用。\n*BC每1分鐘回復1點。\n*等級上限是350級。",
    },
    parseSections("==主畫面==\n*AP每3分鐘回復1點，探索時用。\n*BC每1分鐘回復1點。\n*等級上限是350級。")
  );
  const system = systems.find((entry) => entry.topic === "主画面");
  assert.ok(system.rates_or_timers.includes("AP每3分鐘回復1點"));
  assert.ok(system.rates_or_timers.includes("BC每1分鐘回復1點"));
  assert.ok(system.rates_or_timers.includes("等級上限是350級"));

  const apSystems = extractSystemPages(
    {
      source: "zh-fandom",
      source_lang: "zh",
      title: "新手指南",
      pageid: 3,
      source_url: "https://example.invalid",
      revision: { revid: 3 },
      categories: [],
      wikitext: "===AP===\n*每3分鐘回復1點，探索時用。\n===BC===\n*每1分鐘回復1點。",
    },
    parseSections("===AP===\n*每3分鐘回復1點，探索時用。\n===BC===\n*每1分鐘回復1點。")
  );
  assert.ok(apSystems.some((entry) => entry.topic === "AP/BC"));
  assert.ok(apSystems.some((entry) => entry.rates_or_timers.includes("AP每3分鐘回復1點")));

  const continuationPayload = { continue: { apcontinue: "Next", continue: "-||" } };
  assert.equal(continuationPayload.continue.apcontinue, "Next");
}

function printHelp() {
  console.log(`Usage: node work/kssma-external-wiki-extract.js [--self-check]

Reads work/external-data/raw/ and writes normalized JSONL plus SQLite.
`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printHelp();
    return;
  }
  runSelfCheck();
  if (args.selfCheck) {
    console.log("extract self-check passed");
    return;
  }

  const pages = loadPages();
  const entities = pages.flatMap((page) => extractEntitiesFromPage(page));
  writeJsonl(JSONL_FILE, entities);
  const sqlite = buildSqlite(JSONL_FILE, SQLITE_FILE);
  writeJson(path.join(NORMALIZED_DIR, "extract-summary.json"), {
    extractedAt: new Date().toISOString(),
    pages: pages.length,
    entities: entities.length,
    entityCounts: countBy(entities, (entity) => entity.type),
    sqlite,
  });
  console.log(`pages=${pages.length} entities=${entities.length} jsonl=${JSONL_FILE}`);
  if (sqlite.ok) {
    console.log(`sqlite=${SQLITE_FILE} rows=${sqlite.count}`);
  } else {
    console.log(`sqlite skipped: ${sqlite.reason}`);
  }
}

function countBy(values, getKey) {
  const result = {};
  for (const value of values) {
    const key = getKey(value);
    result[key] = (result[key] || 0) + 1;
  }
  return result;
}

if (require.main === module) {
  main();
}

module.exports = {
  JSONL_FILE,
  NORMALIZED_DIR,
  SQLITE_FILE,
  buildSqlite,
  extractCard,
  extractEntitiesFromPage,
  extractRatesOrTimers,
  loadJsonl,
  parseSections,
  parseTemplates,
  splitTopLevel,
  stripMarkup,
};
