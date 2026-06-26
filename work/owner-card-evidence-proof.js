const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const TARGET_SERIAL = 2367;
const TARGET_TEXT = String(TARGET_SERIAL);
const ZIP_FILE = path.join(ROOT, "base", "com.square_enix.million_cn-140330.zip");
const SELF_FILE = path.resolve(__filename);
const SEARCH_ROOTS = [
  ["jadx bundle", path.join(ROOT, "work", "million_cn", "jadx", "resources", "assets", "bundle")],
  ["apktool bundle", path.join(ROOT, "work", "million_cn", "apktool", "assets", "bundle")],
  ["sdcard dump", path.join(ROOT, "work", "million_cn", "sdcard_dump")],
  ["server", path.join(ROOT, "server")],
];
const WORK_DIR = path.join(ROOT, "work");
const TEXT_EXTENSIONS = new Set([
  ".js",
  ".json",
  ".log",
  ".md",
  ".out",
  ".ps1",
  ".txt",
  ".xml",
]);
const NEEDLES = [
  "2367",
  "<leader_serial_id>",
  "<serial_id>",
  "<master_card_id>",
  "owner_card",
  "owner_card_list",
  "leader_card",
  "user_card",
  "master_card_id",
  "serial_id",
  "leader_serial_id",
];
const MEDIA_PATH_RE = /[\\/](sound|voice)[\\/]|\.ogg$/i;

function relative(file) {
  return path.relative(ROOT, file).replaceAll(path.sep, "/");
}

function* walkFiles(root) {
  if (!fs.existsSync(root)) {
    return;
  }
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    const stat = fs.statSync(current);
    if (stat.isDirectory()) {
      for (const entry of fs.readdirSync(current)) {
        stack.push(path.join(current, entry));
      }
    } else if (stat.isFile()) {
      yield current;
    }
  }
}

function hasAnyNeedle(buffer) {
  return NEEDLES.some((needle) => buffer.includes(Buffer.from(needle, "utf8")));
}

function isTextCandidate(file, buffer) {
  const extension = path.extname(file).toLowerCase();
  if (TEXT_EXTENSIONS.has(extension)) {
    return true;
  }
  if (!hasAnyNeedle(buffer)) {
    return false;
  }
  const sample = buffer.subarray(0, Math.min(buffer.length, 8192));
  let printable = 0;
  for (const byte of sample) {
    if (byte === 9 || byte === 10 || byte === 13 || (byte >= 32 && byte < 127) || byte >= 0x80) {
      printable += 1;
    }
  }
  return sample.length > 0 && printable / sample.length > 0.9;
}

function shouldScanFile(source, file) {
  if (path.resolve(file) === SELF_FILE) {
    return false;
  }
  const extension = path.extname(file).toLowerCase();
  const basename = path.basename(file).toLowerCase();
  const normalized = relative(file).toLowerCase();
  if (source === "work artifacts" && /^owner-card-evidence-.*\.md$/i.test(basename)) {
    return false;
  }
  if (MEDIA_PATH_RE.test(file)) {
    return false;
  }
  if (source === "sdcard dump") {
    return true;
  }
  if (source === "work artifacts" && path.dirname(file) !== WORK_DIR) {
    return false;
  }
  if (TEXT_EXTENSIONS.has(extension)) {
    return true;
  }
  if (basename.startsWith("master_") || basename.includes("save_appdata") || basename === "dtool.txt") {
    return true;
  }
  if (extension === ".bin" || extension === ".dec" || basename.includes("payload")) {
    return true;
  }
  if ((source.includes("bundle") || normalized.includes("/assets/bundle/")) && fs.statSync(file).size <= 5 * 1024 * 1024) {
    return true;
  }
  return false;
}

function lineNumber(text, index) {
  return text.slice(0, index).split(/\r\n|\r|\n/).length;
}

function context(text, index, size = 280) {
  const start = Math.max(0, index - size);
  const end = Math.min(text.length, index + size);
  return text
    .slice(start, end)
    .replace(/\s+/g, " ")
    .trim();
}

function tagValues(xml, tag) {
  // ponytail: fixed local XML samples only; use a real XML parser if this becomes an importer.
  return [...xml.matchAll(new RegExp(`<${tag}>\\s*([^<]*?)\\s*</${tag}>`, "g"))]
    .map((match) => match[1].trim())
    .filter(Boolean);
}

function tagBlocks(xml, tag) {
  return [...xml.matchAll(new RegExp(`<${tag}\\b[^>]*>[\\s\\S]*?</${tag}>`, "g"))].map(
    (match) => match[0]
  );
}

function extractPairs(text) {
  const pairs = [];
  const blockTags = [
    "owner_card",
    "user_card",
    "leader_card",
    "card",
    "deck_card",
    "battle_card",
    "battle_user_card",
  ];
  for (const tag of blockTags) {
    for (const block of tagBlocks(text, tag)) {
      const serialIds = tagValues(block, "serial_id");
      const masterCardIds = tagValues(block, "master_card_id");
      for (const serialId of serialIds) {
        for (const masterCardId of masterCardIds) {
          pairs.push({ blockTag: tag, serialId, masterCardId });
        }
      }
    }
  }
  return pairs;
}

function classifyText(source, name, text) {
  const hits = [];
  const index = text.indexOf(TARGET_TEXT);
  if (index !== -1) {
    hits.push({
      source,
      name,
      line: lineNumber(text, index),
      kind: "target-number",
      context: context(text, index),
    });
  }
  for (const needle of NEEDLES.filter((value) => value !== TARGET_TEXT)) {
    const found = text.indexOf(needle);
    if (found !== -1) {
      hits.push({
        source,
        name,
        line: lineNumber(text, found),
        kind: `keyword:${needle}`,
        context: context(text, found, 120),
      });
    }
  }

  const pairs = extractPairs(text);
  const targetPairs = pairs.filter((pair) => pair.serialId === TARGET_TEXT);
  const leaderSerials = tagValues(text, "leader_serial_id");
  const masterCardIds = tagValues(text, "master_card_id");
  const serialIds = tagValues(text, "serial_id");
  return {
    hits,
    pairs,
    targetPairs,
    leaderSerials,
    masterCardIds,
    serialIds,
  };
}

function scanFile(source, file) {
  const buffer = fs.readFileSync(file);
  const result = {
    source,
    name: relative(file),
    bytes: buffer.length,
    textScanned: false,
    binaryHits: [],
    ...emptyClassification(),
  };
  if (buffer.includes(Buffer.from(TARGET_TEXT, "ascii"))) {
    result.binaryHits.push("ascii:2367");
  }
  const be = Buffer.alloc(4);
  be.writeUInt32BE(TARGET_SERIAL);
  if (buffer.includes(be)) {
    result.binaryHits.push("u32be:2367");
  }
  const le = Buffer.alloc(4);
  le.writeUInt32LE(TARGET_SERIAL);
  if (buffer.includes(le)) {
    result.binaryHits.push("u32le:2367");
  }
  if (!isTextCandidate(file, buffer)) {
    return result;
  }
  result.textScanned = true;
  Object.assign(result, classifyText(source, relative(file), buffer.toString("utf8")));
  return result;
}

function emptyClassification() {
  return {
    hits: [],
    pairs: [],
    targetPairs: [],
    leaderSerials: [],
    masterCardIds: [],
    serialIds: [],
  };
}

function scanDirectories() {
  const files = [];
  const results = [];
  const seen = new Set();
  for (const [source, root] of SEARCH_ROOTS) {
    for (const file of walkFiles(root)) {
      if (!shouldScanFile(source, file)) {
        continue;
      }
      const real = fs.realpathSync(file);
      if (seen.has(real)) {
        continue;
      }
      seen.add(real);
      files.push({ source, file });
    }
  }
  for (const file of fs.readdirSync(WORK_DIR).map((entry) => path.join(WORK_DIR, entry))) {
    if (!fs.statSync(file).isFile() || !shouldScanFile("work artifacts", file)) {
      continue;
    }
    const real = fs.realpathSync(file);
    if (seen.has(real)) {
      continue;
    }
    seen.add(real);
    files.push({ source: "work artifacts", file });
  }
  for (const entry of files) {
    results.push(scanFile(entry.source, entry.file));
  }
  return { files, results };
}

function tarList(zipFile) {
  try {
    return execFileSync("tar", ["-tf", zipFile], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 })
      .split(/\r?\n/)
      .filter(Boolean);
  } catch (error) {
    return { error: error.message };
  }
}

function tarRead(zipFile, entry) {
  try {
    return execFileSync("tar", ["-xOf", zipFile, entry], { maxBuffer: 64 * 1024 * 1024 });
  } catch {
    return null;
  }
}

function scanZip() {
  const listed = tarList(ZIP_FILE);
  if (!Array.isArray(listed)) {
    return { error: listed.error, entries: 0, results: [] };
  }
  const interestingEntries = listed.filter((entry) => {
    const lower = entry.toLowerCase();
    return (
      lower.includes("/database/master_") ||
      lower.includes("/appdata/save_appdata") ||
      lower.includes("/appdata/save_version") ||
      lower.includes("bundle") ||
      lower.endsWith(".xml") ||
      lower.endsWith(".json") ||
      lower.endsWith(".txt") ||
      lower.endsWith(".log")
    );
  });
  const results = [];
  for (const entry of interestingEntries) {
    const buffer = tarRead(ZIP_FILE, entry);
    if (!buffer) {
      continue;
    }
    const result = {
      source: "base zip",
      name: `base/com.square_enix.million_cn-140330.zip!/${entry}`,
      bytes: buffer.length,
      textScanned: false,
      binaryHits: [],
      ...emptyClassification(),
    };
    if (buffer.includes(Buffer.from(TARGET_TEXT, "ascii"))) {
      result.binaryHits.push("ascii:2367");
    }
    const be = Buffer.alloc(4);
    be.writeUInt32BE(TARGET_SERIAL);
    if (buffer.includes(be)) {
      result.binaryHits.push("u32be:2367");
    }
    const le = Buffer.alloc(4);
    le.writeUInt32LE(TARGET_SERIAL);
    if (buffer.includes(le)) {
      result.binaryHits.push("u32le:2367");
    }
    if (hasAnyNeedle(buffer)) {
      result.textScanned = true;
      Object.assign(result, classifyText(result.source, result.name, buffer.toString("utf8")));
    }
    results.push(result);
  }
  return { entries: listed.length, interestingEntries: interestingEntries.length, results };
}

function summarize(results) {
  const withTarget = results.filter(
    (result) => result.hits.some((hit) => hit.kind === "target-number") || result.binaryHits.length
  );
  const targetPairs = results.flatMap((result) =>
    result.targetPairs.map((pair) => ({ source: result.source, name: result.name, ...pair }))
  );
  const allPairs = results.flatMap((result) =>
    result.pairs.map((pair) => ({ source: result.source, name: result.name, ...pair }))
  );
  const leader2367 = results.filter((result) => result.leaderSerials.includes(TARGET_TEXT));
  return { withTarget, targetPairs, allPairs, leader2367 };
}

function main() {
  const directoryScan = scanDirectories();
  const zipScan = scanZip();
  const allResults = [...directoryScan.results, ...zipScan.results];
  const summary = summarize(allResults);

  assert.ok(directoryScan.files.length > 0);
  assert.ok(allResults.some((result) => result.leaderSerials.includes(TARGET_TEXT)));

  const sourceCounts = new Map();
  for (const result of allResults) {
    sourceCounts.set(result.source, (sourceCounts.get(result.source) || 0) + 1);
  }

  console.log("# owner-card evidence proof");
  console.log(`target_serial=${TARGET_SERIAL}`);
  console.log("source_file_counts:");
  for (const [source, count] of [...sourceCounts.entries()].sort()) {
    console.log(`- ${source}: ${count}`);
  }
  console.log(`zip_entries=${zipScan.entries || 0}`);
  console.log(`zip_interesting_entries=${zipScan.interestingEntries || 0}`);
  if (zipScan.error) {
    console.log(`zip_error=${zipScan.error}`);
  }
  console.log("");

  console.log("target 2367 hits:");
  for (const result of summary.withTarget) {
    const leader = result.leaderSerials.includes(TARGET_TEXT) ? " leader_serial_id=2367" : "";
    const pair = result.targetPairs.length ? " target_pair=true" : "";
    const binary = result.binaryHits.length ? ` binary=${result.binaryHits.join(",")}` : "";
    console.log(`- ${result.name} [${result.source}]${leader}${pair}${binary}`);
    for (const hit of result.hits.filter((entry) => entry.kind === "target-number").slice(0, 2)) {
      console.log(`  line ${hit.line}: ${hit.context}`);
    }
  }
  console.log("");

  console.log("serial/master pairs with serial_id=2367:");
  if (summary.targetPairs.length === 0) {
    console.log("- none");
  } else {
    for (const pair of summary.targetPairs) {
      console.log(`- ${pair.name}: ${pair.blockTag} serial_id=${pair.serialId} master_card_id=${pair.masterCardId}`);
    }
  }
  console.log("");

  console.log("sample serial/master pairs found elsewhere:");
  for (const pair of summary.allPairs.slice(0, 20)) {
    console.log(`- ${pair.name}: ${pair.blockTag} serial_id=${pair.serialId} master_card_id=${pair.masterCardId}`);
  }
}

main();
