const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { URLSearchParams } = require("node:url");

const PORT = Number(process.env.PORT || 50005);
const HOST = (process.env.HOST || "0.0.0.0").trim();
const GUEST_HOST = readUrlEnv("GUEST_HOST", "10.0.2.2");

function readUrlEnv(name, fallback) {
  return (process.env[name] || fallback).trim();
}

function parsePortList(input, fallbackPort) {
  const raw = (input || "").trim();
  if (!raw) {
    return [fallbackPort];
  }
  return [...new Set(raw.split(/[,\s]+/).map(Number).filter(Number.isFinite))];
}

const WORLD_URL = readUrlEnv("WORLD_URL", `http://${GUEST_HOST}:${PORT}/connect/app/`);
const TOP_URL = readUrlEnv("TOP_URL", `http://${GUEST_HOST}:${PORT}/`);
const BILLING_URL = readUrlEnv("BILLING_URL", `http://${GUEST_HOST}:${PORT}/billing`);
const LISTEN_PORTS = parsePortList(process.env.PORTS, PORT);
const ADD_USER_KEY = Buffer.from("B1dACcrvur2YULyl", "utf8");
const BUNDLE_DIRS = [
  path.join(__dirname, "..", "work", "million_cn", "jadx", "resources", "assets", "bundle"),
  path.join(__dirname, "..", "work", "million_cn", "apktool", "assets", "bundle"),
];
const CONTENT_DIRS = [
  path.join(__dirname, "..", "work", "million_cn", "jadx", "resources", "assets", "pack"),
  path.join(__dirname, "..", "work", "million_cn", "apktool", "assets", "pack"),
];
const SAMPLE_SAVE_DIRS = [
  path.join(
    __dirname,
    "..",
    "work",
    "million_cn",
    "sdcard_dump",
    "sdcard",
    "Android",
    "data",
    "com.square_enix.million_cn",
    "files",
    "save"
  ),
];
const DATA_ROOT = path.join(__dirname, "data");
const GAME_DATA_DIR = path.join(DATA_ROOT, "game");
const PLAYER_DATA_DIR = path.join(DATA_ROOT, "player");
const SERVER_DATA_DIR = path.join(DATA_ROOT, "server");
const EXPLORATION_DATA_PATH = path.join(GAME_DATA_DIR, "exploration.json");
const MAINMENU_DATA_PATH = path.join(GAME_DATA_DIR, "mainmenu.json");
const DEFAULT_SAVE_DATA_PATH = path.join(PLAYER_DATA_DIR, "default-save.json");
const LOCAL_SAVE_DATA_PATH = path.join(PLAYER_DATA_DIR, "local-save.json");
const WORLDS_DATA_PATH = path.join(SERVER_DATA_DIR, "worlds.json");
const MASTERDATA_ROUTES_DATA_PATH = path.join(SERVER_DATA_DIR, "masterdata-routes.json");

function sendJson(res, statusCode, value) {
  const body = JSON.stringify(value);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function sendText(res, statusCode, value) {
  res.writeHead(statusCode, {
    "Content-Type": "text/plain; charset=utf-8",
    "Content-Length": Buffer.byteLength(value),
  });
  res.end(value);
}

function sendXml(res, statusCode, value) {
  res.writeHead(statusCode, {
    "Content-Type": "text/xml; charset=utf-8",
    "Content-Length": Buffer.byteLength(value),
  });
  res.end(value);
}

function sendHtml(res, statusCode, value) {
  res.writeHead(statusCode, {
    "Content-Type": "text/html; charset=utf-8",
    "Content-Length": Buffer.byteLength(value),
  });
  res.end(value);
}

function sendRedirect(res, location) {
  res.writeHead(302, {
    Location: location,
    "Content-Length": 0,
  });
  res.end();
}

function sendBinary(res, statusCode, value) {
  res.writeHead(statusCode, {
    "Content-Type": "application/octet-stream",
    "Content-Length": value.length,
  });
  res.end(value);
}

function getCheckInspectionKey() {
  return (process.env.CHECK_INSPECTION_KEY || "").trim();
}

function getConnectAppKey() {
  return (process.env.CONNECT_APP_KEY || getCheckInspectionKey()).trim();
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function decryptAddUserPassword(input) {
  try {
    const decipher = crypto.createDecipheriv("aes-128-ecb", ADD_USER_KEY, null);
    decipher.setAutoPadding(true);
    const decoded = Buffer.concat([
      decipher.update(Buffer.from(input, "base64")),
      decipher.final(),
    ]);
    return decoded.toString("utf8");
  } catch {
    return "";
  }
}

function encryptAes128Ecb(value, key) {
  return encryptAes128EcbBuffer(Buffer.from(value, "utf8"), key);
}

function encryptAes128EcbBuffer(value, key) {
  const cipher = crypto.createCipheriv("aes-128-ecb", Buffer.from(key, "utf8"), null);
  cipher.setAutoPadding(true);
  return Buffer.concat([cipher.update(value), cipher.final()]);
}

function decryptAes128EcbBase64(input, key) {
  try {
    const decipher = crypto.createDecipheriv("aes-128-ecb", Buffer.from(key, "utf8"), null);
    decipher.setAutoPadding(true);
    const decoded = Buffer.concat([
      decipher.update(Buffer.from(String(input || "").trim(), "base64")),
      decipher.final(),
    ]);
    return decoded.toString("utf8");
  } catch {
    return "";
  }
}

function parseConnectAppBody(body, key = getConnectAppKey()) {
  const params = new URLSearchParams(body);
  const raw = {};
  const decrypted = {};
  for (const [name, value] of params.entries()) {
    raw[name] = value;
    if (key) {
      decrypted[name] = decryptAes128EcbBase64(value, key);
    }
  }
  return { raw, decrypted };
}

function parseMaybeJson(input) {
  try {
    return JSON.parse(input);
  } catch {
    return null;
  }
}

function readJsonFile(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function readRequiredJsonFile(filePath) {
  const value = readJsonFile(filePath);
  if (!value) {
    throw new Error(`Required JSON data file is missing or invalid: ${filePath}`);
  }
  return value;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function mergeJsonObject(base, override) {
  if (Array.isArray(base)) {
    return Array.isArray(override) ? cloneJson(override) : cloneJson(base);
  }
  if (!isPlainObject(base)) {
    return override === undefined ? base : override;
  }
  const result = cloneJson(base);
  if (!isPlainObject(override)) {
    return result;
  }
  for (const [key, value] of Object.entries(override)) {
    result[key] = key in result ? mergeJsonObject(result[key], value) : cloneJson(value);
  }
  return result;
}

function writeJsonFileAtomic(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp`;
  fs.writeFileSync(tmpPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  fs.renameSync(tmpPath, filePath);
}

function escapeXmlText(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function requireDataString(value, fieldName) {
  if (typeof value !== "string" || !value) {
    throw new Error(`Required data field is missing: ${fieldName}`);
  }
  return value;
}

function logRequest(tag, value) {
  const line = typeof value === "string" ? value : JSON.stringify(value);
  process.stdout.write(`[${new Date().toISOString()}] ${tag} ${line}\n`);
}

function getRequestDetails(req, url, body) {
  return {
    method: req.method,
    host: req.headers.host || "",
    path: url.pathname,
    query: Object.fromEntries(url.searchParams.entries()),
    contentType: req.headers["content-type"] || "",
    contentLength: req.headers["content-length"] || "",
    authorization: req.headers.authorization || "",
    body,
  };
}

const SERVER_WORLD_DATA = readRequiredJsonFile(WORLDS_DATA_PATH);
const MASTERDATA_ROUTE_FILES = readRequiredJsonFile(MASTERDATA_ROUTES_DATA_PATH);
const worldList = (SERVER_WORLD_DATA.worlds || []).map((world) => ({
  ...world,
  url_root: world.url_root || WORLD_URL,
  url_top: world.url_top || TOP_URL,
  url_pr: world.url_pr || BILLING_URL,
}));

const CHECK_INSPECTION_OK_XML = [
  "<response>",
  "    <header>",
  "        <error>",
  "            <code>0</code>",
  "        </error>",
  "    </header>",
  "</response>",
].join("\n");
const POST_DEVICE_TOKEN_OK_XML = CHECK_INSPECTION_OK_XML;
const GAME_EXPLORATION_DATA = readRequiredJsonFile(EXPLORATION_DATA_PATH);
const GAME_MAINMENU_DATA = readRequiredJsonFile(MAINMENU_DATA_PATH);
const DEFAULT_PLAYER_SAVE = readRequiredJsonFile(DEFAULT_SAVE_DATA_PATH);
const DEFAULT_EXPLORATION_BGM = requireDataString(
  GAME_EXPLORATION_DATA.defaultBgm,
  "game.exploration.defaultBgm"
);

function loadExplorationRegions() {
  const regions = GAME_EXPLORATION_DATA.regions || [];
  const goldByCost = GAME_EXPLORATION_DATA.goldByCost || {};

  let nextRouteAreaId = 0;
  let nextFloorId = 2;
  return regions.map((region, regionIndex) => {
    const regionId = Number.isFinite(region.regionId) ? region.regionId : regionIndex;
    const bg = requireDataString(region.bg, `game.exploration.regions[${regionIndex}].bg`);
    const position = region.position || { x: 0, y: 0 };
    const regionBgm = region.bgm || DEFAULT_EXPLORATION_BGM;
    return {
      regionId,
      name: requireDataString(region.name, `game.exploration.regions[${regionIndex}].name`),
      bg,
      bgm: regionBgm,
      position,
      floors: region.floors.map((area, floorIndex) => {
        const cost = parseInteger(area.cost, 1);
        const goldRange = goldByCost[String(cost)] || [cost * 16, cost * 20];
        const floor = {
          regionId,
          regionName: region.name,
          regionBg: bg,
          regionBgm,
          routeAreaId: nextRouteAreaId,
          floorId: nextFloorId,
          floorIndex,
          areaNo: parseInteger(area.areaNo, floorIndex + 1),
          cost,
          requiredMoves: parseInteger(area.requiredMoves, 10 + regionIndex * 5 + floorIndex + 1),
          goldMin: parseInteger(area.goldMin, goldRange[0]),
          goldMax: parseInteger(area.goldMax, goldRange[1]),
        };
        nextRouteAreaId += 1;
        nextFloorId += 1;
        return floor;
      }),
    };
  });
}

const EXPLORATION_REGIONS = loadExplorationRegions();
const EXPLORATION_FLOORS = EXPLORATION_REGIONS.flatMap((region) => region.floors);
const EXPLORATION_AREA_XML = createExplorationAreaXml();
let EXPLORATION_FLOOR_XML;

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function getExplorationRegion(areaId = 0) {
  const requestedAreaId = parseInteger(areaId, 0);
  return EXPLORATION_REGIONS.find((region) => region.regionId === requestedAreaId) || EXPLORATION_REGIONS[0];
}

function getExplorationFloorByFloorId(floorId = 2) {
  const requestedFloorId = parseInteger(floorId, 2);
  return EXPLORATION_FLOORS.find((floor) => floor.floorId === requestedFloorId) || null;
}

function getExplorationFloorByRouteAreaId(areaId = 0) {
  const requestedRouteAreaId = parseInteger(areaId, 0);
  return EXPLORATION_FLOORS.find((floor) => floor.routeAreaId === requestedRouteAreaId) || null;
}

function getExplorationFloor(areaId = 0, floorId = 2) {
  const byFloorId = getExplorationFloorByFloorId(floorId);
  if (byFloorId) {
    return byFloorId;
  }
  const byRouteAreaId = getExplorationFloorByRouteAreaId(areaId);
  if (byRouteAreaId) {
    return byRouteAreaId;
  }
  // ponytail: unknown IDs fall back to the first local row; replace with masterdata mapping when recovered.
  return getExplorationRegion(areaId).floors[0] || EXPLORATION_FLOORS[0];
}

function getExplorationFloorForGetFloorRequest(areaId = 0, floorId = 2) {
  const byRouteAreaId = getExplorationFloorByRouteAreaId(areaId);
  const requestedFloorId = parseInteger(floorId, 2);
  if (byRouteAreaId && byRouteAreaId.areaNo === requestedFloorId) {
    return byRouteAreaId;
  }
  return getExplorationFloor(areaId, floorId);
}

function getExplorationFloorForStageAction(areaId = 0, floorId = 2) {
  const byRouteAreaId = getExplorationFloorByRouteAreaId(areaId);
  if (byRouteAreaId) {
    return byRouteAreaId;
  }
  const byFloorId = getExplorationFloorByFloorId(floorId);
  if (byFloorId) {
    return byFloorId;
  }
  // ponytail: stage actions should normally carry route area_id; keep floor_id fallback for old captures.
  return getExplorationRegion(areaId).floors[0] || EXPLORATION_FLOORS[0];
}

function getNextExplorationFloor(floor) {
  const region = EXPLORATION_REGIONS.find((candidate) => candidate.regionId === floor.regionId);
  return region?.floors[floor.floorIndex + 1] || null;
}

function getExplorationFloorKeyFromIds(areaId = 0, floorId = 2) {
  const floor = getExplorationFloor(areaId, floorId);
  return getExplorationFloorStateKey(floor);
}

function getExplorationFloorStateKey(floor) {
  return `${floor.routeAreaId}:${floor.floorId}`;
}

function clampMoveCount(value, floor) {
  return Math.min(Math.max(parseInteger(value, 0), 0), floor.requiredMoves);
}

function getExplorationProgress(floor, movesDone) {
  return Math.floor((clampMoveCount(movesDone, floor) * 100) / floor.requiredMoves);
}

function getExplorationStepRewards(floor) {
  return {
    getExp: floor.cost * 3,
    // ponytail: deterministic midpoint keeps tests replayable; upgrade to seeded RNG with saved state.
    gold: Math.floor((floor.goldMin + floor.goldMax) / 2),
  };
}

function getExplorationFloorProgressSummary(region, movesByFloor = new Map()) {
  let maxProgress = 0;
  let maxProgressFloorId = 0;
  let maxProgressAreaNo = 0;
  for (const floor of region.floors) {
    const floorKey = getExplorationFloorStateKey(floor);
    const movesDone = movesByFloor instanceof Map ? movesByFloor.get(floorKey) || 0 : 0;
    const progress = getExplorationProgress(floor, movesDone);
    if (progress >= maxProgress) {
      maxProgress = progress;
      maxProgressFloorId = floor.floorId;
      maxProgressAreaNo = floor.areaNo;
    }
  }
  return { maxProgress, maxProgressFloorId, maxProgressAreaNo };
}

function renderFloorInfoXml(floor, progress, indent = "      ", options = {}) {
  const floorInfoId = options.displayAreaNo ? floor.areaNo : floor.floorId;
  const unlocked = options.unlocked === false ? 0 : 1;
  return [
    `${indent}<floor_info>`,
    `${indent}  <id>${floorInfoId}</id>`,
    `${indent}  <type>0</type>`,
    `${indent}  <unlock>${unlocked}</unlock>`,
    `${indent}  <progress>${progress}</progress>`,
    `${indent}  <cost>${floor.cost}</cost>`,
    `${indent}  <boss_id>0</boss_id>`,
    `${indent}  <found_item_list></found_item_list>`,
    `${indent}</floor_info>`,
  ];
}

function getRegionProgress(region, movesByFloor = new Map()) {
  const requiredMoves = region.floors.reduce((sum, floor) => sum + floor.requiredMoves, 0);
  if (!requiredMoves) {
    return 0;
  }
  const doneMoves = region.floors.reduce((sum, floor) => {
    return sum + clampMoveCount(movesByFloor.get(getExplorationFloorStateKey(floor)) || 0, floor);
  }, 0);
  return Math.floor((doneMoves * 100) / requiredMoves);
}

function getFloorMoves(movesByFloor, floor) {
  return movesByFloor instanceof Map ? movesByFloor.get(getExplorationFloorStateKey(floor)) || 0 : 0;
}

function hasExplorationFloorProgress(floor, movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  const key = getExplorationFloorStateKey(floor);
  const floorSave = playerSave.exploration?.floors?.[key] || {};
  return getFloorMoves(movesByFloor, floor) > 0 || parseInteger(floorSave.movesDone, 0) > 0 || parseInteger(floorSave.progress, 0) > 0;
}

function isExplorationFloorComplete(floor, movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  const key = getExplorationFloorStateKey(floor);
  const floorSave = playerSave.exploration?.floors?.[key] || {};
  return !!floorSave.cleared || getExplorationProgress(floor, getFloorMoves(movesByFloor, floor)) >= 100;
}

function isExplorationRegionUnlocked(region, movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  const regionSave = playerSave.exploration?.regions?.[String(region.regionId)] || {};
  if (region.regionId === 0 || regionSave.unlocked) {
    return true;
  }
  if (region.floors.some((floor) => hasExplorationFloorProgress(floor, movesByFloor, playerSave))) {
    return true;
  }
  const previousRegion = EXPLORATION_REGIONS[EXPLORATION_REGIONS.findIndex((candidate) => candidate.regionId === region.regionId) - 1];
  if (!previousRegion) {
    return false;
  }
  const previousSave = playerSave.exploration?.regions?.[String(previousRegion.regionId)] || {};
  return !!previousSave.cleared && !!previousSave.guardianDefeated;
}

function getUnlockedExplorationRegions(movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  return EXPLORATION_REGIONS.filter((region) => isExplorationRegionUnlocked(region, movesByFloor, playerSave));
}

function isExplorationFloorUnlocked(floor, movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  const region = getExplorationRegion(floor.regionId);
  if (!isExplorationRegionUnlocked(region, movesByFloor, playerSave)) {
    return false;
  }
  const floorSave = playerSave.exploration?.floors?.[getExplorationFloorStateKey(floor)] || {};
  if (floor.floorIndex === 0 || floorSave.unlocked || hasExplorationFloorProgress(floor, movesByFloor, playerSave)) {
    return true;
  }
  const previousFloor = region.floors[floor.floorIndex - 1];
  return !!previousFloor && isExplorationFloorComplete(previousFloor, movesByFloor, playerSave);
}

function createExplorationAreaXml(movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  // ponytail: only list unlocked areas until the client's locked-area presentation field is recovered.
  const unlockedRegions = getUnlockedExplorationRegions(movesByFloor, playerSave);
  const yourDataRows = renderYourDataXml(playerSave);
  const areaRows = unlockedRegions.flatMap((region) => [
    "        <area_info>",
    `          <id>${region.regionId}</id>`,
    `          <name>${escapeXmlText(region.name)}</name>`,
    `          <x>${region.position.x}</x>`,
    `          <y>${region.position.y}</y>`,
    "          <area_type>1</area_type>",
    `          <prog_area>${getRegionProgress(region, movesByFloor)}</prog_area>`,
    "          <prog_item>0</prog_item>",
    "        </area_info>",
  ]);

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
    ...yourDataRows,
    "    <next_scene>6100</next_scene>",
    "  </header>",
    "  <body>",
    "    <exploration_area>",
    "      <area_id>0</area_id>",
    "      <locations>0</locations>",
    "      <area_info_list>",
    ...areaRows,
    "      </area_info_list>",
    "    </exploration_area>",
    "  </body>",
    "</response>",
  ].join("");
}

function createExplorationFloorXml(areaId = 0, movesByFloor = new Map(), playerSave = createDefaultPlayerSave()) {
  const region = getExplorationRegion(areaId);
  const regionUnlocked = isExplorationRegionUnlocked(region, movesByFloor, playerSave);
  const yourDataRows = renderYourDataXml(playerSave);
  // ponytail: hide locked rows for now; restore visible <unlock>0 rows once their tap/gray-out behavior is proven.
  const visibleFloors = region.floors.filter((floor) => {
    return regionUnlocked && isExplorationFloorUnlocked(floor, movesByFloor, playerSave);
  });
  const floorRows = visibleFloors.flatMap((floor) => {
    const movesDone = getFloorMoves(movesByFloor, floor);
    return renderFloorInfoXml(floor, getExplorationProgress(floor, movesDone), "        ", {
      unlocked: true,
    });
  });

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
    ...yourDataRows,
    "    <next_scene>6100</next_scene>",
    "  </header>",
    "  <body>",
    "    <exploration_floor>",
    `      <area_id>${region.regionId}</area_id>`,
    "      <boss_down>0</boss_down>",
    "      <floor_info_list>",
    ...floorRows,
    "      </floor_info_list>",
    "    </exploration_floor>",
    "  </body>",
    "</response>",
  ].join("");
}

EXPLORATION_FLOOR_XML = createExplorationFloorXml();

function renderNextFloorXml(floor) {
  if (!floor) {
    return [];
  }
  return [
    "      <next_floor>",
    `        <area_id>${floor.routeAreaId}</area_id>`,
    ...renderFloorInfoXml(floor, 0, "        ", { displayAreaNo: true }),
    "      </next_floor>",
  ];
}

function renderGaugeXml(tagName, gauge = {}, intervalFallback, indent = "      ") {
  const now = Math.floor(Date.now() / 1000);
  const current = Math.max(parseInteger(gauge.current, 0), 0);
  const max = Math.max(parseInteger(gauge.max, current), 0);
  const interval = Math.max(parseInteger(gauge.regenSeconds, intervalFallback), 0);
  const lastUpdate = parseInteger(gauge.lastUpdateTime, now);
  const currentTime = parseInteger(gauge.currentTime, now);
  return [
    `${indent}<${tagName}>`,
    `${indent}  <current>${current}</current>`,
    `${indent}  <max>${max}</max>`,
    `${indent}  <interval_time>${interval}</interval_time>`,
    `${indent}  <last_update_time>${lastUpdate}</last_update_time>`,
    `${indent}  <current_time>${currentTime}</current_time>`,
    `${indent}</${tagName}>`,
  ];
}

function renderYourDataXml(playerSave, indent = "    ") {
  if (!playerSave) {
    return [];
  }
  const save = mergeJsonObject(createDefaultPlayerSave(), playerSave);
  const profile = save.profile || {};
  const resources = save.resources || {};
  const currencies = save.currencies || {};
  const cards = save.cards || {};
  const progression = save.progression || {};
  const abilityPoints = progression.abilityPoints || {};
  const items = save.items || {};
  const factionCountryId = {
    sword: 1,
    technique: 2,
    magic: 3,
  };
  return [
    `${indent}<your_data>`,
    `${indent}  <name>${escapeXmlText(profile.name || "Arthur")}</name>`,
    `${indent}  <leader_serial_id>${Math.max(parseInteger(profile.leaderSerialId, 0), 0)}</leader_serial_id>`,
    `${indent}  <town_level>${Math.max(parseInteger(profile.townLevel, 1), 1)}</town_level>`,
    `${indent}  <percentage>${Math.max(parseInteger(profile.percentage, 0), 0)}</percentage>`,
    `${indent}  <gold>${Math.max(parseInteger(currencies.gold, 0), 0)}</gold>`,
    `${indent}  <cp>${Math.max(parseInteger(currencies.mc, 0), 0)}</cp>`,
    `${indent}  <rank>${Math.max(parseInteger(profile.level, 1), 1)}</rank>`,
    ...renderGaugeXml("ap", resources.ap, 180, `${indent}  `),
    ...renderGaugeXml("bc", resources.bc, 60, `${indent}  `),
    `${indent}  <max_card_num>${Math.max(parseInteger(cards.max, 0), 0)}</max_card_num>`,
    `${indent}  <free_ap_bc_point>${Math.max(parseInteger(abilityPoints.unspent, 0), 0)}</free_ap_bc_point>`,
    `${indent}  <friendship_point>${Math.max(parseInteger(currencies.friendshipPoint, 0), 0)}</friendship_point>`,
    `${indent}  <country_id>${Math.max(parseInteger(profile.countryId, factionCountryId[profile.faction] || 1), 1)}</country_id>`,
    `${indent}  <ex_gauge>${Math.max(parseInteger(resources.super?.current, 0), 0)}</ex_gauge>`,
    `${indent}  <gacha_ticket>${Math.max(parseInteger(items.gachaTicket, 0), 0)}</gacha_ticket>`,
    `${indent}  <deck_rank>${Math.max(parseInteger(cards.deckRank, 0), 0)}</deck_rank>`,
    `${indent}</your_data>`,
  ];
}

function replaceHeaderYourData(xml, playerSave) {
  const yourDataXml = renderYourDataXml(playerSave, "").join("");
  if (!yourDataXml) {
    return xml;
  }
  if (/<your_data>[\s\S]*?<\/your_data>/.test(xml)) {
    return xml.replace(/<your_data>[\s\S]*?<\/your_data>/, yourDataXml);
  }
  return xml.replace("</header>", `${yourDataXml}</header>`);
}

function getProfileNextExp(playerSave) {
  return Math.max(parseInteger(playerSave?.profile?.nextExp, 0), 0);
}

function createExplorationGetFloorXml(areaId = 0, floorId = 2, movesDone = 0, playerSave = null) {
  const currentFloor = getExplorationFloorForGetFloorRequest(areaId, floorId);
  const nextFloor = getNextExplorationFloor(currentFloor);
  const progress = getExplorationProgress(currentFloor, movesDone);
  const yourDataRows = renderYourDataXml(playerSave);
  const nextExp = getProfileNextExp(playerSave);

  return [
  '<?xml version="1.0" encoding="UTF-8"?>',
  "<response>",
  "  <header>",
  "    <error><code>0</code></error>",
  "    <session_id>local-exploration</session_id>",
  ...yourDataRows,
  "    <next_scene>6200</next_scene>",
  "  </header>",
  "  <body>",
  "    <get_floor>",
  `      <area_id>${currentFloor.routeAreaId}</area_id>`,
  `      <bg>${currentFloor.regionBg}</bg>`,
  `      <bgm>${currentFloor.regionBgm}</bgm>`,
  `      <area_name>${escapeXmlText(currentFloor.regionName)}</area_name>`,
  `      <next_exp>${nextExp}</next_exp>`,
  ...renderNextFloorXml(nextFloor),
  ...renderFloorInfoXml(currentFloor, progress, "      ", { displayAreaNo: true }),
  "    </get_floor>",
  "  </body>",
  "</response>",
].join("");
}
const EXPLORATION_GET_FLOOR_XML = createExplorationGetFloorXml();
function createExplorationExploreXml(progress = 10, rewards = getExplorationStepRewards(EXPLORATION_FLOORS[0]), playerSave = null) {
  const safeProgress = Math.min(Math.max(parseInteger(progress, 10), 0), 100);
  const gold = Math.max(parseInteger(rewards.gold, 0), 0);
  const getExp = Math.max(parseInteger(rewards.getExp, 0), 0);
  const yourDataRows = renderYourDataXml(playerSave);
  const nextExp = getProfileNextExp(playerSave);

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
    ...yourDataRows,
    "  </header>",
    "  <body>",
    "    <explore>",
    `      <progress>${safeProgress}</progress>`,
    "      <event_type>0</event_type>",
    `      <gold>${gold}</gold>`,
    `      <get_exp>${getExp}</get_exp>`,
    `      <next_exp>${nextExp}</next_exp>`,
    "      <next_floor>0</next_floor>",
    "      <friendship_point>0</friendship_point>",
    "      <recover>0</recover>",
    "      <encounter>0</encounter>",
    "      <fairy_pose>2</fairy_pose>",
    "      <fairy_face>5</fairy_face>",
    "    </explore>",
    "  </body>",
    "</response>",
  ].join("");
}
const EXPLORATION_EXPLORE_XML = createExplorationExploreXml();

function createExplorationApFailXml() {
  // ponytail: scene 81100 is proven by bundled rule_scene; item-use/buy branches are a later route frontier.
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
    "    <next_scene>81100</next_scene>",
    "  </header>",
    "  <body></body>",
    "</response>",
  ].join("");
}

function createExplorationLockedXml() {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>1</code><message>exploration locked</message></error>",
    "    <session_id>local-exploration</session_id>",
    "  </header>",
    "  <body></body>",
    "</response>",
  ].join("");
}

const MAINMENU_BGFILE = requireDataString(GAME_MAINMENU_DATA.background?.current, "game.mainmenu.background.current");
const MAINMENU_PREVIOUS_BGFILE = GAME_MAINMENU_DATA.background?.previous || MAINMENU_BGFILE;
const MAINMENU_INFORMATION = GAME_MAINMENU_DATA.information || {};
const MAINMENU_MESSAGE = MAINMENU_INFORMATION.message || {};
const MAINMENU_FIELDS = [
  "    <mainmenu>",
  `      <current_bgfile>${MAINMENU_BGFILE}</current_bgfile>`,
  `      <previous_bgfile>${MAINMENU_PREVIOUS_BGFILE}</previous_bgfile>`,
  "      <infomation>",
  `        <fairy_pose>${parseInteger(MAINMENU_INFORMATION.fairyPose, 2)}</fairy_pose>`,
  `        <fairy_face>${parseInteger(MAINMENU_INFORMATION.fairyFace, 5)}</fairy_face>`,
  "        <message>",
  `          <text>${escapeXmlText(requireDataString(MAINMENU_MESSAGE.text, "game.mainmenu.information.message.text"))}</text>`,
  `          <color>${MAINMENU_MESSAGE.color || "0xFFFFFF"}</color>`,
  `          <size>${parseInteger(MAINMENU_MESSAGE.size, 20)}</size>`,
  "        </message>",
  "      </infomation>",
  "    </mainmenu>",
];
const MAINMENU_UPDATE_XML = [
  '<?xml version="1.0" encoding="UTF-8"?>',
  "<response>",
  "  <header>",
  "    <error><code>0</code></error>",
  "    <session_id>local-mainmenu</session_id>",
  "    <next_scene>2100</next_scene>",
  "  </header>",
  "  <body>",
  ...MAINMENU_FIELDS,
  "  </body>",
  "</response>",
].join("");
const LOGIN_TUTORIAL_XML = readBundledXml("local_forward_tutorial.xml", CHECK_INSPECTION_OK_XML);
const WEB_SCENETO_LOCATION = "sceneto://2100";
const WEB_STUB_HTML = [
  "<!doctype html>",
  '<html lang="zh-CN">',
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width,initial-scale=1">',
  "<title>KSSMA local web stub</title>",
  '<body style="font:18px sans-serif;padding:24px;background:#f5f1e8;color:#241b12">',
  "<h1>Local web stub</h1>",
  "<p>The original service web page is offline. This local stub keeps the client in the reconstructed runtime.</p>",
  `<p><a href="${WEB_SCENETO_LOCATION}">Back to game</a></p>`,
  `<script>location.replace("${WEB_SCENETO_LOCATION}");</script>`,
  "</body>",
  "</html>",
].join("");

function readBundledXml(filename, fallback) {
  for (const dir of BUNDLE_DIRS) {
    try {
      return fs.readFileSync(path.join(dir, filename), "utf8").trim();
    } catch {}
  }
  return fallback;
}

function readSampleSaveFile(relativePath) {
  for (const dir of SAMPLE_SAVE_DIRS) {
    try {
      return fs.readFileSync(path.join(dir, relativePath));
    } catch {}
  }
  return null;
}

function readContentFile(relativePath) {
  const safeRelativePath = relativePath.replace(/^\/+/, "");
  if (safeRelativePath.includes("..")) {
    return null;
  }
  for (const dir of CONTENT_DIRS) {
    try {
      return fs.readFileSync(path.join(dir, safeRelativePath));
    } catch {}
  }
  return null;
}

const LOGIN_OK_XML = readBundledXml("local_battle_player.xml", CHECK_INSPECTION_OK_XML);
const LOGIN_MAINMENU_XML = withMainmenuBg(LOGIN_OK_XML);
const MASTERDATA_SAMPLES = Object.fromEntries(
  Object.entries(MASTERDATA_ROUTE_FILES).map(([route, relativePath]) => [
    route,
    {
      relativePath,
      bytes: readSampleSaveFile(relativePath),
    },
  ])
);

function withMainmenuBg(xml) {
  const body = [
    "<body>",
    ...MAINMENU_FIELDS,
    "</body>",
  ].join("");
  // ponytail: login jumps straight to scene 2100, so seed the layout-bound town model fields there too.
  return suppressLoginUpdates(xml.replace(/<body>\s*<\/body>/, body));
}

function suppressLoginUpdates(xml) {
  // ponytail: the 140330 save dump is preloaded; advertising newer revisions only wakes a broken CDN pack updater.
  return xml
    .replace(/<(card_rev|boss_rev|item_rev|card_category_rev|gacha_rev|privilege_rev)>\d+<\/\1>/g, "<$1>0</$1>")
    .replace(/<revision>\d+<\/revision>/g, "<revision>0</revision>");
}

function getLoginOkXml() {
  // ponytail: default to the safe stub; opt into native scene payloads only when debugging that path.
  const loginResponse = (process.env.LOGIN_RESPONSE || "").trim().toLowerCase();
  if (loginResponse === "tutorial") {
    return LOGIN_TUTORIAL_XML;
  }
  if (loginResponse === "sample") {
    return LOGIN_MAINMENU_XML;
  }
  return CHECK_INSPECTION_OK_XML;
}

function getLoginXmlSource(loginXml) {
  if (loginXml === LOGIN_TUTORIAL_XML) {
    return "assets/bundle/local_forward_tutorial.xml";
  }
  if (loginXml === LOGIN_MAINMENU_XML) {
    return "assets/bundle/local_battle_player.xml + mainmenu bg";
  }
  return "minimal";
}

function getExplorationFloorKey(params) {
  const floor = getExplorationFloorForGetFloorRequest(
    params.decrypted.area_id || "0",
    params.decrypted.floor_id || "2"
  );
  return getExplorationFloorStateKey(floor);
}

function getPlayerSavePath() {
  return (process.env.KSSMA_PLAYER_SAVE_PATH || LOCAL_SAVE_DATA_PATH).trim();
}

function createDefaultPlayerSave() {
  return cloneJson(DEFAULT_PLAYER_SAVE);
}

function readPlayerSave(savePath = getPlayerSavePath()) {
  const saved = readJsonFile(savePath);
  if (!saved) {
    return createDefaultPlayerSave();
  }
  return mergeJsonObject(createDefaultPlayerSave(), saved);
}

function createExplorationMovesFromSave(playerSave) {
  return new Map(
    Object.entries(playerSave.exploration?.movesByFloor || {})
      .map(([key, value]) => [key, parseInteger(value, 0)])
  );
}

function ensureExplorationSaveShape(playerSave) {
  playerSave.profile = playerSave.profile || {};
  playerSave.resources = playerSave.resources || {};
  playerSave.resources.ap = playerSave.resources.ap || {};
  playerSave.currencies = playerSave.currencies || {};
  playerSave.exploration = playerSave.exploration || {};
  playerSave.exploration.movesByFloor = playerSave.exploration.movesByFloor || {};
  playerSave.exploration.regions = playerSave.exploration.regions || {};
  playerSave.exploration.floors = playerSave.exploration.floors || {};
  playerSave.stats = playerSave.stats || {};
}

function applyExplorationSeed(moves) {
  const seed = (process.env.KSSMA_EXPLORATION_MOVES_SEED || "").trim();
  if (!seed) {
    return moves;
  }
  const parsedSeed = parseMaybeJson(seed);
  if (!parsedSeed || Array.isArray(parsedSeed) || typeof parsedSeed !== "object") {
    throw new Error("KSSMA_EXPLORATION_MOVES_SEED must be a JSON object");
  }
  const floorsByKey = new Map(EXPLORATION_FLOORS.map((floor) => [getExplorationFloorStateKey(floor), floor]));
  for (const [key, value] of Object.entries(parsedSeed)) {
    const floor = floorsByKey.get(key);
    if (!floor) {
      throw new Error(`Unknown exploration seed floor key: ${key}`);
    }
    const movesDone = Math.trunc(Number(value));
    if (!Number.isFinite(movesDone)) {
      throw new Error(`Invalid exploration seed move count for ${key}: ${value}`);
    }
    moves.set(key, Math.max(moves.get(key) || 0, clampMoveCount(movesDone, floor)));
  }
  return moves;
}

function saveExplorationMoves(playerSave, savePath, moves) {
  ensureExplorationSaveShape(playerSave);
  playerSave.exploration.movesByFloor = Object.fromEntries(moves);
  writeJsonFileAtomic(savePath, playerSave);
}

function updateExplorationSaveAfterMove(playerSave, floor, moves) {
  ensureExplorationSaveShape(playerSave);
  const floorKey = getExplorationFloorStateKey(floor);
  const region = EXPLORATION_REGIONS.find((candidate) => candidate.regionId === floor.regionId);
  const movesDone = moves.get(floorKey) || 0;
  const progress = getExplorationProgress(floor, movesDone);
  const floorSave = playerSave.exploration.floors[floorKey] || {};
  const rewards = getExplorationStepRewards(floor);

  playerSave.resources.ap.current = Math.max(parseInteger(playerSave.resources.ap.current, 0) - floor.cost, 0);
  playerSave.profile.exp = Math.max(parseInteger(playerSave.profile.exp, 0) + rewards.getExp, 0);
  playerSave.currencies.gold = Math.max(parseInteger(playerSave.currencies.gold, 0) + rewards.gold, 0);

  playerSave.exploration.currentRegionId = floor.regionId;
  playerSave.exploration.currentFloorKey = floorKey;
  playerSave.exploration.floors[floorKey] = {
    ...floorSave,
    regionId: floor.regionId,
    floorId: floor.floorId,
    routeAreaId: floor.routeAreaId,
    areaNo: floor.areaNo,
    unlocked: true,
    cleared: progress >= 100,
    movesDone,
    requiredMoves: floor.requiredMoves,
    progress,
    lastExploredAt: new Date().toISOString(),
  };

  if (region) {
    const regionProgress = getRegionProgress(region, moves);
    const regionSave = playerSave.exploration.regions[String(region.regionId)] || {};
    playerSave.exploration.regions[String(region.regionId)] = {
      ...regionSave,
      unlocked: true,
      cleared: region.floors.every((candidate) => {
        const key = getExplorationFloorStateKey(candidate);
        return getExplorationProgress(candidate, moves.get(key) || 0) >= 100;
      }),
      progress: regionProgress,
      guardianDefeated: !!regionSave.guardianDefeated,
    };
  }

  const nextFloor = getNextExplorationFloor(floor);
  if (nextFloor && progress >= 100) {
    const nextKey = getExplorationFloorStateKey(nextFloor);
    const nextFloorSave = playerSave.exploration.floors[nextKey] || {};
    playerSave.exploration.floors[nextKey] = {
      ...nextFloorSave,
      regionId: nextFloor.regionId,
      floorId: nextFloor.floorId,
      routeAreaId: nextFloor.routeAreaId,
      areaNo: nextFloor.areaNo,
      unlocked: true,
      cleared: !!nextFloorSave.cleared,
      movesDone: parseInteger(nextFloorSave.movesDone, 0),
      requiredMoves: nextFloor.requiredMoves,
      progress: parseInteger(nextFloorSave.progress, 0),
    };
  }

  playerSave.stats.explorationMoves = parseInteger(playerSave.stats.explorationMoves, 0) + 1;
  if (progress >= 100 && !floorSave.cleared) {
    playerSave.stats.explorationClears = parseInteger(playerSave.stats.explorationClears, 0) + 1;
  }
}

function unlockExplorationProgressFromMoves(playerSave, moves) {
  ensureExplorationSaveShape(playerSave);
  for (const region of EXPLORATION_REGIONS) {
    const regionKey = String(region.regionId);
    const regionSave = playerSave.exploration.regions[regionKey] || {};
    const regionUnlocked = isExplorationRegionUnlocked(region, moves, playerSave);
    if (regionUnlocked || regionSave.unlocked !== undefined) {
      playerSave.exploration.regions[regionKey] = {
        ...regionSave,
        unlocked: regionUnlocked,
        cleared: !!regionSave.cleared || region.floors.every((floor) => isExplorationFloorComplete(floor, moves, playerSave)),
        progress: getRegionProgress(region, moves),
        guardianDefeated: !!regionSave.guardianDefeated,
      };
    }
    for (const floor of region.floors) {
      const floorKey = getExplorationFloorStateKey(floor);
      const movesDone = getFloorMoves(moves, floor);
      const floorSave = playerSave.exploration.floors[floorKey] || {};
      if (!movesDone && floorSave.unlocked === undefined) {
        continue;
      }
      const progress = getExplorationProgress(floor, movesDone);
      playerSave.exploration.floors[floorKey] = {
        ...floorSave,
        regionId: floor.regionId,
        floorId: floor.floorId,
        routeAreaId: floor.routeAreaId,
        areaNo: floor.areaNo,
        unlocked: isExplorationFloorUnlocked(floor, moves, playerSave),
        cleared: !!floorSave.cleared || progress >= 100,
        movesDone,
        requiredMoves: floor.requiredMoves,
        progress,
      };
    }
  }
}

function getLogSafePath(filePath) {
  const relative = path.relative(__dirname, filePath);
  if (relative && !relative.startsWith("..") && !path.isAbsolute(relative)) {
    return relative.replace(/\\/g, "/");
  }
  return path.basename(filePath);
}

function loadExplorationMovesForRequest(savePath) {
  const playerSave = readPlayerSave(savePath);
  const moves = applyExplorationSeed(createExplorationMovesFromSave(playerSave));
  unlockExplorationProgressFromMoves(playerSave, moves);
  return { playerSave, moves };
}

function createServer() {
  const playerSavePath = getPlayerSavePath();
  if ((process.env.KSSMA_EXPLORATION_MOVES_SEED || "").trim()) {
    const seededMoves = applyExplorationSeed(createExplorationMovesFromSave(readPlayerSave(playerSavePath)));
    logRequest("exploration_seed", {
      source: "KSSMA_EXPLORATION_MOVES_SEED",
      movesByFloor: Object.fromEntries(seededMoves),
    });
  }
  logRequest("player_save", {
    path: getLogSafePath(playerSavePath),
    source: fs.existsSync(playerSavePath) ? "file" : "default",
  });
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);

    if (req.method === "GET" && url.pathname === "/healthz") {
      return sendJson(res, 200, { ok: true, world: worldList[0] });
    }

    if (req.method === "GET" && url.pathname.startsWith("/connect/web/")) {
      logRequest("connect_web_stub", {
        path: url.pathname,
        query: Object.fromEntries(url.searchParams.entries()),
      });
      // ponytail: these offline service pages are just modal WebViews; redirect through the client's existing close path.
      return sendRedirect(res, WEB_SCENETO_LOCATION);
    }

    if (req.method === "GET" && url.pathname.startsWith("/contents/")) {
      const relativePath = url.pathname.slice("/contents/".length);
      const content = readContentFile(relativePath);
      if (!content) {
        logRequest("contents_miss", { path: url.pathname, relativePath });
        return sendText(res, 404, "content not found\n");
      }
      logRequest("contents_hit", {
        path: url.pathname,
        relativePath,
        bytes: content.length,
      });
      return sendBinary(res, 200, content);
    }

    if (req.method === "POST" && url.pathname === "/world_list.php") {
      const body = await readBody(req);
      logRequest("world_list", { body });
      return sendJson(res, 200, worldList);
    }

    if (req.method === "POST" && url.pathname === "/add_user.php") {
      const body = await readBody(req);
      const params = new URLSearchParams(body);
      const dataStr = params.get("data_str") || "";
      const payload = parseMaybeJson(dataStr) || {};
      const decryptedPassword = payload.password
        ? decryptAddUserPassword(payload.password)
        : "";

      logRequest("add_user", {
        raw: body,
        payload,
        decryptedPassword,
      });

      return sendJson(res, 200, {
        code: 1,
        world_id: payload.world_id || 1,
        user_id: payload.user_id || "",
        // ponytail: only enough fields for the client bootstrap; add more if the next screen proves it needs them.
      });
    }

    if (url.pathname === "/check_inspection") {
      const body = req.method === "POST" ? await readBody(req) : "";
      const checkInspectionKey = getCheckInspectionKey();
      logRequest("check_inspection", getRequestDetails(req, url, body));
      if (checkInspectionKey) {
        const encrypted = encryptAes128Ecb(CHECK_INSPECTION_OK_XML, checkInspectionKey);
        logRequest("check_inspection_response", {
          mode: "aes-128-ecb",
          key: checkInspectionKey,
          bytes: encrypted.length,
        });
        sendBinary(res, 200, encrypted);
        return;
      }
      // ponytail: start with the smallest success XML shape shared by bundled local responses; add fields only if the next request proves they're required.
      return sendXml(res, 200, CHECK_INSPECTION_OK_XML);
    }

    if (url.pathname.startsWith("/connect/app/")) {
      const body = req.method === "POST" ? await readBody(req) : "";
      const connectAppKey = getConnectAppKey();
      const params = parseConnectAppBody(body, connectAppKey);
      logRequest("connect_app_probe", {
        ...getRequestDetails(req, url, body),
        rawParams: params.raw,
        decryptedParams: params.decrypted,
      });

      if (!connectAppKey) {
        return sendText(res, 500, "connect/app key missing\n");
      }

      if (req.method === "POST" && url.pathname === "/connect/app/notification/post_devicetoken") {
        const encrypted = encryptAes128Ecb(POST_DEVICE_TOKEN_OK_XML, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/login") {
        // ponytail: keep the login sample that gets furthest into native bootstrap; add the real payload only when the next blocker proves we need it.
        const playerSave = readPlayerSave(playerSavePath);
        const baseLoginXml = getLoginOkXml();
        const loginXml = replaceHeaderYourData(baseLoginXml, playerSave);
        const encrypted = encryptAes128Ecb(loginXml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: getLoginXmlSource(baseLoginXml),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/mainmenu/update") {
        // ponytail: one known-good mainbg is enough to un-black the town background; real rotation can wait for event data.
        const playerSave = readPlayerSave(playerSavePath);
        const xml = replaceHeaderYourData(MAINMENU_UPDATE_XML, playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal mainmenu update",
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/mainmenu") {
        // ponytail: the exploration return path only needs the same mainmenu payload as update; split behavior later if evidence demands it.
        const playerSave = readPlayerSave(playerSavePath);
        const xml = replaceHeaderYourData(MAINMENU_UPDATE_XML, playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal mainmenu",
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/area") {
        const { playerSave, moves } = loadExplorationMovesForRequest(playerSavePath);
        const unlockedRegions = getUnlockedExplorationRegions(moves, playerSave);
        const xml = createExplorationAreaXml(moves, playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "save-gated exploration area list",
          areaCount: unlockedRegions.length,
          unlockedRegionIds: unlockedRegions.map((region) => region.regionId),
          regionProgress: Object.fromEntries(unlockedRegions.map((region) => [region.regionId, getRegionProgress(region, moves)])),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/floor") {
        const { playerSave, moves } = loadExplorationMovesForRequest(playerSavePath);
        const region = getExplorationRegion(params.decrypted.area_id);
        const progressSummary = getExplorationFloorProgressSummary(region, moves);
        const regionUnlocked = isExplorationRegionUnlocked(region, moves, playerSave);
        const unlockedFloorIds = region.floors
          .filter((floor) => isExplorationFloorUnlocked(floor, moves, playerSave))
          .map((floor) => floor.floorId);
        const xml = regionUnlocked
          ? createExplorationFloorXml(params.decrypted.area_id, moves, playerSave)
          : createExplorationLockedXml();
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: regionUnlocked ? "save-gated exploration floor list" : "locked exploration floor list",
          regionId: region.regionId,
          unlocked: regionUnlocked,
          unlockedFloorIds,
          floorCount: region.floors.length,
          maxProgress: progressSummary.maxProgress,
          maxProgressFloorId: progressSummary.maxProgressFloorId,
          maxProgressAreaNo: progressSummary.maxProgressAreaNo,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/get_floor") {
        // ponytail: one no-branch floor entry is enough to test exploration_main; real event routing comes after the next route proves it.
        const { playerSave, moves } = loadExplorationMovesForRequest(playerSavePath);
        const floorKey = getExplorationFloorKey(params);
        const floor = getExplorationFloorForGetFloorRequest(params.decrypted.area_id, params.decrypted.floor_id);
        const floorUnlocked = isExplorationFloorUnlocked(floor, moves, playerSave);
        const nextFloor = getNextExplorationFloor(floor);
        const movesDone = moves.get(floorKey) || 0;
        const progress = getExplorationProgress(floor, movesDone);
        const xml = floorUnlocked
          ? createExplorationGetFloorXml(params.decrypted.area_id, params.decrypted.floor_id, movesDone, playerSave)
          : createExplorationLockedXml();
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: floorUnlocked ? "minimal exploration get_floor" : "locked exploration get_floor",
          floorKey,
          regionId: floor.regionId,
          floorId: floor.floorId,
          areaNo: floor.areaNo,
          unlocked: floorUnlocked,
          cost: floor.cost,
          requiredMoves: floor.requiredMoves,
          bg: floor.regionBg,
          bgm: floor.regionBgm,
          gold: getExplorationStepRewards(floor).gold,
          getExp: getExplorationStepRewards(floor).getExp,
          movesDone,
          progress,
          hasNextFloor: !!nextFloor,
          nextFloorKey: nextFloor ? getExplorationFloorStateKey(nextFloor) : "",
          nextFloorId: nextFloor ? nextFloor.floorId : 0,
          nextAreaNo: nextFloor ? nextFloor.areaNo : 0,
          nextRouteAreaId: nextFloor ? nextFloor.routeAreaId : 0,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/explore") {
        // ponytail: keep this as the no-branch walking candidate; battle/fairy/reward routes stay separate frontiers.
        const { playerSave, moves } = loadExplorationMovesForRequest(playerSavePath);
        const floor = getExplorationFloorForStageAction(params.decrypted.area_id, params.decrypted.floor_id);
        const floorKey = getExplorationFloorStateKey(floor);
        const currentAp = parseInteger(playerSave.resources?.ap?.current, 0);
        if (!isExplorationFloorUnlocked(floor, moves, playerSave)) {
          const encrypted = encryptAes128Ecb(createExplorationLockedXml(), connectAppKey);
          logRequest("connect_app_response", {
            path: url.pathname,
            mode: "aes-128-ecb",
            key: connectAppKey,
            bytes: encrypted.length,
            source: "locked exploration explore",
            floorKey,
            regionId: floor.regionId,
            floorId: floor.floorId,
            areaNo: floor.areaNo,
            cost: floor.cost,
            currentAp,
            saved: false,
            savePath: getLogSafePath(playerSavePath),
          });
          sendBinary(res, 200, encrypted);
          return;
        }
        if (currentAp < floor.cost) {
          const encrypted = encryptAes128Ecb(createExplorationApFailXml(), connectAppKey);
          logRequest("connect_app_response", {
            path: url.pathname,
            mode: "aes-128-ecb",
            key: connectAppKey,
            bytes: encrypted.length,
            source: "exploration ap fail",
            floorKey,
            regionId: floor.regionId,
            floorId: floor.floorId,
            areaNo: floor.areaNo,
            cost: floor.cost,
            currentAp,
            nextScene: 81100,
            saved: false,
            savePath: getLogSafePath(playerSavePath),
          });
          sendBinary(res, 200, encrypted);
          return;
        }
        const movesDone = clampMoveCount((moves.get(floorKey) || 0) + 1, floor);
        moves.set(floorKey, movesDone);
        updateExplorationSaveAfterMove(playerSave, floor, moves);
        saveExplorationMoves(playerSave, playerSavePath, moves);
        const progress = getExplorationProgress(floor, movesDone);
        const rewards = getExplorationStepRewards(floor);
        const encrypted = encryptAes128Ecb(createExplorationExploreXml(progress, rewards, playerSave), connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal exploration explore",
          floorKey,
          regionId: floor.regionId,
          floorId: floor.floorId,
          areaNo: floor.areaNo,
          cost: floor.cost,
          currentAp,
          remainingAp: parseInteger(playerSave.resources?.ap?.current, 0),
          requiredMoves: floor.requiredMoves,
          movesDone,
          progress,
          gold: rewards.gold,
          getExp: rewards.getExp,
          saved: true,
          savePath: getLogSafePath(playerSavePath),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      const masterdataSample = MASTERDATA_SAMPLES[url.pathname];
      if (req.method === "POST" && masterdataSample) {
        if (!masterdataSample.bytes) {
          logRequest("connect_app_response_miss", {
            path: url.pathname,
            source: masterdataSample.relativePath,
          });
          return sendText(res, 500, "masterdata sample missing\n");
        }
        const encrypted = encryptAes128EcbBuffer(masterdataSample.bytes, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: masterdataSample.relativePath,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      return sendText(res, 501, "connect/app not implemented yet\n");
    }

    const body = req.method === "POST" ? await readBody(req) : "";
    logRequest("miss", getRequestDetails(req, url, body));
    return sendText(res, 404, "not found\n");
  });

  server.on("connection", (socket) => {
    logRequest("tcp_connect", {
      remoteAddress: socket.remoteAddress,
      remotePort: socket.remotePort,
    });
  });

  return server;
}

if (require.main === module) {
  for (const listenPort of LISTEN_PORTS) {
    const server = createServer();
    server.listen(listenPort, HOST, () => {
      process.stdout.write(
        `bootstrap server listening on http://${HOST}:${listenPort}\n` +
          `world_url=${WORLD_URL}\n` +
          `top_url=${TOP_URL}\n` +
          `billing_url=${BILLING_URL}\n`
      );
    });
  }
}

module.exports = {
  ADD_USER_KEY,
  createServer,
  decryptAddUserPassword,
  decryptAes128EcbBase64,
  encryptAes128Ecb,
  encryptAes128EcbBuffer,
  createExplorationAreaXml,
  createExplorationApFailXml,
  createExplorationExploreXml,
  createExplorationFloorXml,
  createExplorationGetFloorXml,
  createExplorationLockedXml,
  getLoginOkXml,
  getLoginXmlSource,
  parseConnectAppBody,
  parsePortList,
  CHECK_INSPECTION_OK_XML,
  EXPLORATION_AREA_XML,
  EXPLORATION_FLOOR_XML,
  EXPLORATION_GET_FLOOR_XML,
  EXPLORATION_EXPLORE_XML,
  EXPLORATION_REGIONS,
  EXPLORATION_FLOORS,
  GAME_EXPLORATION_DATA,
  GAME_MAINMENU_DATA,
  DEFAULT_PLAYER_SAVE,
  SERVER_WORLD_DATA,
  MAINMENU_UPDATE_XML,
  LOGIN_TUTORIAL_XML,
  LOGIN_OK_XML,
  LOGIN_MAINMENU_XML,
  MASTERDATA_ROUTE_FILES,
  MASTERDATA_SAMPLES,
  WEB_SCENETO_LOCATION,
  WEB_STUB_HTML,
  readContentFile,
  readSampleSaveFile,
};
