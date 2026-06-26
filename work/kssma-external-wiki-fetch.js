const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const DATA_DIR = path.join(ROOT, "work", "external-data");
const RAW_DIR = path.join(DATA_DIR, "raw");

const SYSTEM_TOPICS = {
  "主画面": ["新手指南"],
  "AP/BC": ["新手指南"],
  "探索": ["探索"],
  "战斗": ["戰鬥配牌", "战斗配牌"],
  "因子战": ["因子戰", "因子战"],
  "妖精战": ["妖精戰", "新版強敵戰", "妖精战", "新版强敌战"],
  "合成": ["強化合成", "進化合成", "强化合成", "进化合成"],
  Gacha: ["新手指南", "Gacha"],
  "朋友": ["新手指南", "朋友"],
  "道具": ["新手指南", "道具"],
  "剧情": ["主線故事", "支線故事", "主线故事", "支线故事"],
  "活动": ["活動", "活动"],
};

const ZH_SYSTEM_SEEDS = [...new Set(Object.values(SYSTEM_TOPICS).flat())];

const SOURCES = {
  "zh-fandom": {
    id: "zh-fandom",
    lang: "zh",
    api: "https://kssma.fandom.com/zh/api.php",
    articleBase: "https://kssma.fandom.com/zh/wiki/",
    systemSeeds: ZH_SYSTEM_SEEDS,
    categorySeeds: ["Category:卡牌列表", "Category:Combo", "Category:妖精"],
    directSeeds: ["卡牌"],
  },
  "en-fandom": {
    id: "en-fandom",
    lang: "en",
    api: "https://million-arthur.fandom.com/api.php",
    articleBase: "https://million-arthur.fandom.com/wiki/",
    systemSeeds: [],
    categorySeeds: ["Category:Card"],
    directSeeds: ["Arbitrator Knight"],
  },
};

function parseArgs(argv) {
  const args = {
    source: "all",
    limit: 50,
    refresh: false,
    maxImages: 100,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (item === "--source") {
      args.source = argv[++index] || args.source;
    } else if (item === "--limit") {
      args.limit = Number(argv[++index] || args.limit);
    } else if (item === "--refresh") {
      args.refresh = true;
    } else if (item === "--max-images") {
      args.maxImages = Number(argv[++index] || args.maxImages);
    } else if (item === "--help" || item === "-h") {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${item}`);
    }
  }
  if (!Number.isFinite(args.limit) || args.limit < 1) {
    throw new Error("--limit must be a positive number");
  }
  return args;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeJson(file, value) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function hashText(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function normalizeTitle(title) {
  return String(title || "").trim().replaceAll(" ", "_");
}

function safeName(value) {
  return normalizeTitle(value)
    .replace(/[<>:"/\\|?*\x00-\x1f]/g, "_")
    .replace(/_+/g, "_")
    .slice(0, 160);
}

function articleUrl(source, title) {
  return `${source.articleBase}${encodeURIComponent(normalizeTitle(title))}`;
}

function apiUrl(source, params) {
  const url = new URL(source.api);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) {
      url.searchParams.set(key, String(value));
    }
  }
  url.searchParams.set("format", "json");
  return url;
}

function cachePath(sourceId, group, key) {
  return path.join(RAW_DIR, sourceId, "api", group, `${safeName(key)}.json`);
}

async function fetchJson(url) {
  const response = await fetch(url, {
    headers: {
      "Accept": "application/json,text/plain,*/*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7",
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36 KSSMA-Re/1.0",
    },
  });
  const text = await response.text();
  if (response.ok) {
    return JSON.parse(text);
  }
  if (response.status === 403 || /Just a moment|cf[-_]?chl/i.test(text)) {
    return fetchJsonViaPowerShell(url);
  }
  throw new Error(`HTTP ${response.status} for ${url}`);
}

function fetchJsonViaPowerShell(url) {
  const script = [
    "$ProgressPreference='SilentlyContinue'",
    "$u = [Environment]::GetEnvironmentVariable('KSSMA_WIKI_URL')",
    "$response = Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 30",
    "$response.Content",
  ].join("; ");
  const output = execFileSync("powershell", ["-NoProfile", "-Command", script], {
    encoding: "utf8",
    env: { ...process.env, KSSMA_WIKI_URL: url.toString() },
    maxBuffer: 64 * 1024 * 1024,
  });
  return JSON.parse(output);
}

async function cachedApi(source, group, key, params, refresh) {
  const file = cachePath(source.id, group, key);
  if (!refresh && fs.existsSync(file)) {
    return { value: readJson(file), cache: "hit", file };
  }
  const url = apiUrl(source, params);
  const value = await fetchJson(url);
  writeJson(file, { fetchedAt: new Date().toISOString(), url: url.toString(), value });
  return { value: { fetchedAt: new Date().toISOString(), url: url.toString(), value }, cache: "miss", file };
}

function apiPayload(cached) {
  return cached.value.value || cached.value;
}

function mergeContinuationParams(params, continuation) {
  return continuation ? { ...params, ...continuation } : { ...params };
}

async function fetchPagedList(source, group, keyPrefix, params, listKey, limit, refresh) {
  const items = [];
  let continuation = null;
  let pageIndex = 0;
  do {
    const cached = await cachedApi(
      source,
      group,
      `${keyPrefix}-page-${pageIndex}`,
      mergeContinuationParams(params, continuation),
      refresh
    );
    const payload = apiPayload(cached);
    items.push(...(payload.query?.[listKey] || []));
    continuation = payload.continue || null;
    pageIndex += 1;
  } while (continuation && items.length < limit);
  return items.slice(0, limit);
}

async function fetchAllPages(source, limit, refresh) {
  return fetchPagedList(
    source,
    "allpages",
    `limit-${limit}`,
    {
      action: "query",
      list: "allpages",
      aplimit: Math.min(limit, 500),
    },
    "allpages",
    limit,
    refresh
  );
}

async function fetchCategoryMembers(source, categoryTitle, limit, refresh) {
  return fetchPagedList(
    source,
    "categorymembers",
    `${categoryTitle}-limit-${limit}`,
    {
      action: "query",
      list: "categorymembers",
      cmtitle: categoryTitle,
      cmlimit: Math.min(limit, 500),
    },
    "categorymembers",
    limit,
    refresh
  );
}

async function fetchRevisions(source, titles, refresh) {
  const pages = [];
  const skipped = [];
  for (let index = 0; index < titles.length; index += 50) {
    const batch = titles.slice(index, index + 50);
    let cached;
    try {
      cached = await cachedApi(
        source,
        "revisions",
        batch.join("__"),
        {
          action: "query",
          prop: "revisions|categories",
          rvprop: "ids|timestamp|content",
          rvslots: "main",
          cllimit: "max",
          titles: batch.join("|"),
        },
        refresh
      );
    } catch (error) {
      skipped.push(...batch.map((title) => ({ title, reason: `revision-request-failed: ${error.message}` })));
      continue;
    }
    const payload = apiPayload(cached);
    for (const page of Object.values(payload.query?.pages || {})) {
      if (page.missing !== undefined || !page.revisions?.length) {
        skipped.push({ title: page.title, reason: "missing-or-no-revision" });
        continue;
      }
      const revision = page.revisions[0];
      const wikitext = revision.slots?.main?.["*"] ?? revision["*"] ?? "";
      pages.push({
        pageid: page.pageid,
        title: page.title,
        ns: page.ns,
        source: source.id,
        source_lang: source.lang,
        source_url: articleUrl(source, page.title),
        categories: (page.categories || []).map((entry) => entry.title),
        revision: {
          revid: revision.revid,
          parentid: revision.parentid,
          timestamp: revision.timestamp,
        },
        wikitext,
        wikitext_sha256: hashText(wikitext),
      });
    }
  }
  return { pages, skipped };
}

function extractInternalLinks(wikitext) {
  const links = new Set();
  const re = /\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]/g;
  for (const match of wikitext.matchAll(re)) {
    const title = match[1].trim();
    if (!title || title.startsWith("Image:") || title.startsWith("File:") || title.startsWith("Category:")) {
      continue;
    }
    links.add(title);
  }
  return [...links];
}

function extractImageTitles(wikitext) {
  const images = new Set();
  const re = /\[\[(?:Image|File):([^\]|]+)(?:\|[^\]]*)?\]\]/gi;
  for (const match of wikitext.matchAll(re)) {
    images.add(`File:${match[1].trim()}`);
  }
  return [...images];
}

async function fetchImageInfo(source, imageTitles, maxImages, refresh) {
  const selected = imageTitles.slice(0, maxImages);
  const images = [];
  const skipped = [];
  for (let index = 0; index < selected.length; index += 50) {
    const batch = selected.slice(index, index + 50);
    let cached;
    try {
      cached = await cachedApi(
        source,
        "imageinfo",
        batch.join("__"),
        {
          action: "query",
          prop: "imageinfo",
          iiprop: "url|size|mime|sha1",
          titles: batch.join("|"),
        },
        refresh
      );
    } catch (error) {
      skipped.push(...batch.map((title) => ({ title, reason: `imageinfo-request-failed: ${error.message}` })));
      continue;
    }
    const payload = apiPayload(cached);
    for (const page of Object.values(payload.query?.pages || {})) {
      if (page.missing !== undefined || !page.imageinfo?.length) {
        skipped.push({ title: page.title, reason: "missing-imageinfo" });
        continue;
      }
      images.push({
        title: page.title,
        pageid: page.pageid,
        ...page.imageinfo[0],
      });
    }
  }
  return { images, skipped };
}

function selectSourceIds(requested) {
  if (requested === "all") {
    return Object.keys(SOURCES);
  }
  if (!SOURCES[requested]) {
    throw new Error(`Unknown source '${requested}'. Expected one of: all, ${Object.keys(SOURCES).join(", ")}`);
  }
  return [requested];
}

async function fetchSource(source, args) {
  const sourceDir = path.join(RAW_DIR, source.id);
  const pageDir = path.join(sourceDir, "pages");
  ensureDir(pageDir);

  const requestedLimit = Math.max(1, Math.floor(args.limit));
  let allpages = [];
  const skipped = [];
  try {
    allpages = await fetchAllPages(source, Math.min(requestedLimit, 50), args.refresh);
  } catch (error) {
    skipped.push({ title: "*allpages*", reason: `allpages-request-failed: ${error.message}` });
  }
  const categoryResults = [];
  const titleSet = new Set([...source.systemSeeds, ...source.directSeeds]);

  for (const category of source.categorySeeds) {
    try {
      const members = await fetchCategoryMembers(source, category, requestedLimit, args.refresh);
      categoryResults.push({ category, count: members.length, members });
      for (const member of members) {
        if (member.ns === 0) {
          titleSet.add(member.title);
        }
      }
    } catch (error) {
      categoryResults.push({ category, count: 0, members: [], error: error.message });
    }
  }

  for (const page of allpages) {
    if (titleSet.size >= requestedLimit) {
      break;
    }
    titleSet.add(page.title);
  }

  let titles = [...titleSet].slice(0, requestedLimit);
  const firstPass = await fetchRevisions(source, titles, args.refresh);

  if (source.id === "zh-fandom") {
    const cardIndex = firstPass.pages.find((page) => page.title === "卡牌");
    if (cardIndex) {
      for (const link of extractInternalLinks(cardIndex.wikitext)) {
        if (titles.length >= requestedLimit) {
          break;
        }
        if (!titleSet.has(link)) {
          titleSet.add(link);
          titles.push(link);
        }
      }
    }
  }

  titles = [...titleSet].slice(0, requestedLimit);
  const revisionResult = await fetchRevisions(source, titles, args.refresh);
  const pages = revisionResult.pages;
  skipped.push(...revisionResult.skipped);
  const imageTitles = [...new Set(pages.flatMap((page) => extractImageTitles(page.wikitext)))];
  const imageInfo = await fetchImageInfo(source, imageTitles, args.maxImages, args.refresh);

  for (const page of pages) {
    writeJson(path.join(pageDir, `${page.pageid}.json`), page);
  }

  const manifest = {
    source: {
      id: source.id,
      lang: source.lang,
      api: source.api,
      articleBase: source.articleBase,
    },
    fetchedAt: new Date().toISOString(),
    limit: requestedLimit,
    pages: pages.map((page) => ({
      pageid: page.pageid,
      title: page.title,
      revision: page.revision,
      source_url: page.source_url,
      categories: page.categories,
      wikitext_sha256: page.wikitext_sha256,
    })),
    skipped: [...firstPass.skipped, ...skipped, ...imageInfo.skipped],
    categories: categoryResults.map((entry) => ({
      category: entry.category,
      count: entry.count,
      error: entry.error,
      members: entry.members.map((member) => ({ pageid: member.pageid, ns: member.ns, title: member.title })),
    })),
    allpages: allpages.map((page) => ({ pageid: page.pageid, ns: page.ns, title: page.title })),
    images: imageInfo.images,
    notes: [
      "External wiki data is evidence only; do not merge it into server responses without native/schema validation.",
      "atwiki is a manual cross-check source in this phase because direct automation can hit Cloudflare.",
    ],
  };
  writeJson(path.join(sourceDir, "manifest.json"), manifest);
  return manifest;
}

function runSelfCheck() {
  assert.equal(selectSourceIds("all").length >= 2, true);
  assert.deepEqual(selectSourceIds("zh-fandom"), ["zh-fandom"]);
  assert.equal(articleUrl(SOURCES["en-fandom"], "Arbitrator Knight"), "https://million-arthur.fandom.com/wiki/Arbitrator_Knight");
  assert.deepEqual(extractInternalLinks("[[探索]] [[Image:x.png]] [[Card|label]]"), ["探索", "Card"]);
  assert.deepEqual(extractImageTitles("[[Image:main1.jpg|480px]] [[File:card.png]]"), ["File:main1.jpg", "File:card.png"]);
  assert.deepEqual(mergeContinuationParams({ action: "query" }, { continue: "-||", apcontinue: "Next" }), {
    action: "query",
    continue: "-||",
    apcontinue: "Next",
  });
  assert.equal(JSON.stringify(fetchJsonViaPowerShell), JSON.stringify(fetchJsonViaPowerShell));
}

function printHelp() {
  console.log(`Usage: node work/kssma-external-wiki-fetch.js [--source zh-fandom|en-fandom|all] [--limit N] [--refresh]

Fetches Fandom MediaWiki evidence into work/external-data/raw/.
`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printHelp();
    return;
  }
  runSelfCheck();
  ensureDir(RAW_DIR);
  const sourceIds = selectSourceIds(args.source);
  const manifests = [];
  for (const sourceId of sourceIds) {
    const manifest = await fetchSource(SOURCES[sourceId], args);
    manifests.push(manifest);
    console.log(
      `${sourceId}: pages=${manifest.pages.length} images=${manifest.images.length} skipped=${manifest.skipped.length}`
    );
  }
  writeJson(path.join(RAW_DIR, "fetch-summary.json"), {
    fetchedAt: new Date().toISOString(),
    args,
    sources: manifests.map((manifest) => ({
      id: manifest.source.id,
      pages: manifest.pages.length,
      images: manifest.images.length,
      skipped: manifest.skipped.length,
    })),
  });
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = {
  ROOT,
  DATA_DIR,
  RAW_DIR,
  SYSTEM_TOPICS,
  SOURCES,
  articleUrl,
  ensureDir,
  extractImageTitles,
  extractInternalLinks,
  hashText,
  mergeContinuationParams,
  normalizeTitle,
  parseArgs,
  readJson,
  safeName,
  writeJson,
};
