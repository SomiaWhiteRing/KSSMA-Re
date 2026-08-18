const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { URLSearchParams } = require("node:url");
const {
  ADMIN_UI_HTML,
  applyAdminFairyUpdate,
  applyAdminPlayerUpdate,
  createAdminState,
} = require("./admin-ui");

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
const GACHA_DATA_PATH = path.join(GAME_DATA_DIR, "gacha.json");
const MAINMENU_DATA_PATH = path.join(GAME_DATA_DIR, "mainmenu.json");
const PLAYER_LEVEL_EXP_TABLE_PATH = path.join(GAME_DATA_DIR, "player-level-exp-table.json");
const DEFAULT_SAVE_DATA_PATH = path.join(PLAYER_DATA_DIR, "default-save.json");
const LOCAL_SAVE_DATA_PATH = path.join(PLAYER_DATA_DIR, "local-save.json");
const WORLDS_DATA_PATH = path.join(SERVER_DATA_DIR, "worlds.json");
const MASTERDATA_ROUTES_DATA_PATH = path.join(SERVER_DATA_DIR, "masterdata-routes.json");
const RUNTIME_CONFIG_DATA_PATH = path.join(SERVER_DATA_DIR, "runtime-config.json");

function sendJson(res, statusCode, value) {
  const body = JSON.stringify(value);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
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
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
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

function getAdminToken() {
  return (process.env.KSSMA_ADMIN_TOKEN || "").trim();
}

function isLoopbackAddress(address) {
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

function isAdminWriteAuthorized(req) {
  const requiredToken = getAdminToken();
  if (!requiredToken) {
    return isLoopbackAddress(req.socket?.remoteAddress || "");
  }
  const suppliedToken = String(req.headers["x-kssma-admin-token"] || "");
  const requiredBytes = Buffer.from(requiredToken, "utf8");
  const suppliedBytes = Buffer.from(suppliedToken, "utf8");
  return suppliedBytes.length === requiredBytes.length
    && suppliedBytes.length > 0
    && crypto.timingSafeEqual(suppliedBytes, requiredBytes);
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
const GAME_GACHA_DATA = readRequiredJsonFile(GACHA_DATA_PATH);
const GAME_MAINMENU_DATA = readRequiredJsonFile(MAINMENU_DATA_PATH);
const GAME_PLAYER_LEVEL_EXP_TABLE = readRequiredJsonFile(PLAYER_LEVEL_EXP_TABLE_PATH);
const DEFAULT_PLAYER_SAVE = readRequiredJsonFile(DEFAULT_SAVE_DATA_PATH);
const DEFAULT_RUNTIME_CONFIG = readRequiredJsonFile(RUNTIME_CONFIG_DATA_PATH);
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

const FACTION_COUNTRY_ID = Object.freeze({
  sword: 1,
  technique: 2,
  magic: 3,
});
const VALID_COUNTRY_IDS = new Set(Object.values(FACTION_COUNTRY_ID));
const EXPLORATION_REGIONS = loadExplorationRegions();
const EXPLORATION_FLOORS = EXPLORATION_REGIONS.flatMap((region) => region.floors);
const EXPLORATION_AREA_XML = createExplorationAreaXml();
let EXPLORATION_FLOOR_XML;
let TOWN_LVUP_STATUS_XML;
let TOWN_POINTSETTING_XML;

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function getPlayerLevelRow(level) {
  const requestedLevel = parseInteger(level, 1);
  const row = (GAME_PLAYER_LEVEL_EXP_TABLE.levels || []).find((candidate) => candidate.level === requestedLevel);
  if (!row) {
    return null;
  }
  const nextExp = parseInteger(row.nextExp, 0);
  if (nextExp <= 0) {
    return null;
  }
  return { ...row, nextExp };
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

function renderUserCardXml(card, indent = "      ") {
  const serialId = Math.max(parseInteger(card?.serialId ?? card?.serial_id, 0), 0);
  const masterCardId = Math.max(parseInteger(card?.masterCardId ?? card?.master_card_id, 0), 0);
  if (!serialId || !masterCardId) {
    return [];
  }
  return [
    `${indent}<user_card>`,
    `${indent}  <serial_id>${serialId}</serial_id>`,
    `${indent}  <master_card_id>${masterCardId}</master_card_id>`,
    `${indent}  <holography>${Math.max(parseInteger(card.holography, 0), 0)}</holography>`,
    `${indent}  <hp>${Math.max(parseInteger(card.hp, 0), 0)}</hp>`,
    `${indent}  <power>${Math.max(parseInteger(card.power, 0), 0)}</power>`,
    `${indent}  <critical>${Math.max(parseInteger(card.critical, 0), 0)}</critical>`,
    `${indent}  <lv>${Math.max(parseInteger(card.level ?? card.lv, 1), 1)}</lv>`,
    `${indent}  <lv_max>${Math.max(parseInteger(card.maxLevel ?? card.lv_max, 1), 1)}</lv_max>`,
    `${indent}  <exp>${Math.max(parseInteger(card.exp, 0), 0)}</exp>`,
    `${indent}  <max_exp>${Math.max(parseInteger(card.maxExp ?? card.max_exp, 0), 0)}</max_exp>`,
    `${indent}  <next_exp>${Math.max(parseInteger(card.nextExp ?? card.next_exp, 0), 0)}</next_exp>`,
    `${indent}  <exp_diff>${Math.max(parseInteger(card.expDiff ?? card.exp_diff, 0), 0)}</exp_diff>`,
    `${indent}  <exp_per>${Math.max(parseInteger(card.expPercent ?? card.exp_per, 0), 0)}</exp_per>`,
    `${indent}  <sale_price>${Math.max(parseInteger(card.salePrice ?? card.sale_price, 0), 0)}</sale_price>`,
    `${indent}  <material_price>${Math.max(parseInteger(card.materialPrice ?? card.material_price, 0), 0)}</material_price>`,
    `${indent}  <evolution_price>${Math.max(parseInteger(card.evolutionPrice ?? card.evolution_price, 0), 0)}</evolution_price>`,
    `${indent}  <plus_limit_count>${Math.max(parseInteger(card.plusLimitCount ?? card.plus_limit_count, 0), 0)}</plus_limit_count>`,
    `${indent}  <limit_over>${Math.max(parseInteger(card.limitOver ?? card.limit_over, 0), 0)}</limit_over>`,
    `${indent}</user_card>`,
  ];
}

function renderLeaderCardXml(card, indent = "      ") {
  const rows = renderUserCardXml(card, indent);
  if (!rows.length) {
    return [];
  }
  return [
    `${indent}<leader_card>`,
    ...rows.slice(1, -1),
    `${indent}</leader_card>`,
  ];
}

function renderOwnerCardListXml(cards = {}, indent = "    ") {
  const instances = Array.isArray(cards.instances) ? cards.instances : [];
  return [
    `${indent}<owner_card_list>`,
    ...instances.flatMap((card) => renderUserCardXml(card, `${indent}  `)),
    `${indent}</owner_card_list>`,
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
  const countryId = getPlayerCountryId(save);
  return [
    `${indent}<your_data>`,
    `${indent}  <name>${escapeXmlText(profile.name || "Arthur")}</name>`,
    `${indent}  <leader_serial_id>${Math.max(parseInteger(profile.leaderSerialId, 0), 0)}</leader_serial_id>`,
    ...renderOwnerCardListXml(cards, `${indent}  `),
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
    `${indent}  <country_id>${countryId}</country_id>`,
    `${indent}  <ex_gauge>${Math.max(parseInteger(resources.super?.current, 0), 0)}</ex_gauge>`,
    `${indent}  <gacha_ticket>${Math.max(parseInteger(items.gachaTicket, 0), 0)}</gacha_ticket>`,
    `${indent}  <deck_rank>${Math.max(parseInteger(cards.deckRank, 0), 0)}</deck_rank>`,
    `${indent}</your_data>`,
  ];
}

function getPlayerCountryId(playerSave) {
  const save = mergeJsonObject(createDefaultPlayerSave(), playerSave || {});
  const profile = save.profile || {};
  const countryId = parseInteger(profile.countryId, FACTION_COUNTRY_ID[profile.faction] || 1);
  return VALID_COUNTRY_IDS.has(countryId) ? countryId : 1;
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
function renderExplorationExploreBodyXml(
  progress = 10,
  rewards = getExplorationStepRewards(EXPLORATION_FLOORS[0]),
  playerSave = null,
  levelResult = null,
  fairyEncounter = null,
  eventType = fairyEncounter ? 1 : 0,
  indent = "    "
) {
  const safeProgress = Math.min(Math.max(parseInteger(progress, 10), 0), 100);
  const gold = Math.max(parseInteger(rewards.gold, 0), 0);
  const getExp = Math.max(parseInteger(rewards.getExp, 0), 0);
  const nextExp = getProfileNextExp(playerSave);
  const lvup = levelResult?.levelUp ? 1 : 0;
  const isLimit = levelResult?.isLimit ? 1 : 0;
  const safeEventType = Math.max(parseInteger(eventType, fairyEncounter ? 1 : 0), 0);
  const fairyRows = fairyEncounter ? [
    `${indent}  <fairy>`,
    `${indent}    <serial_id>${escapeXmlText(fairyEncounter.serialId)}</serial_id>`,
    `${indent}    <master_boss_id>${Math.max(parseInteger(fairyEncounter.masterBossId, 0), 0)}</master_boss_id>`,
    `${indent}    <name>${escapeXmlText(fairyEncounter.name)}</name>`,
    `${indent}    <lv>${Math.max(parseInteger(fairyEncounter.level, 1), 1)}</lv>`,
    `${indent}    <hp>${Math.max(parseInteger(fairyEncounter.currentHp, 1), 0)}</hp>`,
    `${indent}    <hp_max>${Math.max(parseInteger(fairyEncounter.maxHp, 1), 1)}</hp_max>`,
    `${indent}    <time_limit>${Math.max(parseInteger(fairyEncounter.timeLimitSeconds, 60), 0)}</time_limit>`,
    `${indent}    <discoverer_id>${Math.max(parseInteger(fairyEncounter.discovererId, 1), 1)}</discoverer_id>`,
    `${indent}    <rare_flg>${fairyEncounter.rareFlg ? 1 : 0}</rare_flg>`,
    `${indent}    <event_chara_flg>${fairyEncounter.eventCharaFlg ? 1 : 0}</event_chara_flg>`,
    `${indent}  </fairy>`,
  ] : [];

  return [
    `${indent}<explore>`,
    `${indent}  <progress>${safeProgress}</progress>`,
    ...fairyRows,
    `${indent}  <event_type>${safeEventType}</event_type>`,
    `${indent}  <gold>${gold}</gold>`,
    `${indent}  <get_exp>${getExp}</get_exp>`,
    `${indent}  <next_exp>${nextExp}</next_exp>`,
    `${indent}  <lvup>${lvup}</lvup>`,
    `${indent}  <is_limit>${isLimit}</is_limit>`,
    `${indent}  <next_floor>0</next_floor>`,
    `${indent}  <friendship_point>0</friendship_point>`,
    `${indent}  <recover>0</recover>`,
    `${indent}  <encounter>${fairyEncounter ? 1 : 0}</encounter>`,
    `${indent}  <fairy_pose>2</fairy_pose>`,
    `${indent}  <fairy_face>5</fairy_face>`,
    `${indent}</explore>`,
  ];
}

function createExplorationExploreXml(
  progress = 10,
  rewards = getExplorationStepRewards(EXPLORATION_FLOORS[0]),
  playerSave = null,
  levelResult = null,
  fairyEncounter = null
) {
  const yourDataRows = renderYourDataXml(playerSave);

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
    ...yourDataRows,
    "  </header>",
    "  <body>",
    ...renderExplorationExploreBodyXml(progress, rewards, playerSave, levelResult, fairyEncounter),
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

function createTownLvupStatusXml(playerSave = createDefaultPlayerSave()) {
  // ponytail: route 0x5a is a header-only scene entry until the OK/allocation route proves a body schema.
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-town</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>84100</next_scene>",
    "  </header>",
    "  <body></body>",
    "</response>",
  ].join("");
}

TOWN_LVUP_STATUS_XML = createTownLvupStatusXml();

function createTownPointsettingXml(playerSave = createDefaultPlayerSave()) {
  // ponytail: route 0x5b only needs to persist AP/BC allocation and return to town for the current level-up flow.
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-town</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>2100</next_scene>",
    "  </header>",
    "  <body>",
    ...renderMainmenuFields(playerSave),
    "  </body>",
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
const MAINMENU_BY_COUNTRY = MAINMENU_INFORMATION.byCountry || {};

function getMainmenuInformationForPlayer(playerSave = createDefaultPlayerSave()) {
  const countryId = getPlayerCountryId(playerSave);
  const countryInformation = MAINMENU_BY_COUNTRY[String(countryId)] || {};
  const fallbackPose = parseInteger(MAINMENU_INFORMATION.fairyPose, 2);
  const fallbackFace = parseInteger(MAINMENU_INFORMATION.fairyFace, 5);
  return {
    countryId,
    fairyCharacterId: Math.max(parseInteger(countryInformation.fairyCharacterId, MAINMENU_INFORMATION.fairyCharacterId || 0), 0),
    fairyPose: Math.max(parseInteger(countryInformation.fairyPose, fallbackPose), 0),
    fairyFace: Math.max(parseInteger(countryInformation.fairyFace, fallbackFace), 0),
  };
}

function renderMainmenuFields(playerSave = createDefaultPlayerSave(), indent = "    ") {
  const information = getMainmenuInformationForPlayer(playerSave);
  return [
    `${indent}<mainmenu>`,
    `${indent}  <current_bgfile>${MAINMENU_BGFILE}</current_bgfile>`,
    `${indent}  <previous_bgfile>${MAINMENU_PREVIOUS_BGFILE}</previous_bgfile>`,
    `${indent}  <infomation>`,
    `${indent}    <fairy_pose>${information.fairyPose}</fairy_pose>`,
    `${indent}    <fairy_face>${information.fairyFace}</fairy_face>`,
    `${indent}    <message>`,
    `${indent}      <text>${escapeXmlText(requireDataString(MAINMENU_MESSAGE.text, "game.mainmenu.information.message.text"))}</text>`,
    `${indent}      <color>${MAINMENU_MESSAGE.color || "0xFFFFFF"}</color>`,
    `${indent}      <size>${parseInteger(MAINMENU_MESSAGE.size, 20)}</size>`,
    `${indent}    </message>`,
    `${indent}  </infomation>`,
    `${indent}</mainmenu>`,
  ];
}

function createMainmenuUpdateXml(playerSave = createDefaultPlayerSave()) {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-mainmenu</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>2100</next_scene>",
    "  </header>",
    "  <body>",
    ...renderMainmenuFields(playerSave),
    "  </body>",
    "</response>",
  ].join("");
}

function createSceneForwardXml(nextScene, playerSave = createDefaultPlayerSave(), sessionId = "local-mainmenu-route") {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    `    <session_id>${sessionId}</session_id>`,
    ...renderYourDataXml(playerSave),
    `    <next_scene>${Math.max(parseInteger(nextScene, 2100), 0)}</next_scene>`,
    "  </header>",
    "  <body></body>",
    "</response>",
  ].join("");
}

function getFairyBattleDeckCards(playerSave) {
  const instances = Array.isArray(playerSave?.cards?.instances) ? playerSave.cards.instances : [];
  const bySerialId = new Map(instances.map((card) => [parseInteger(card?.serialId, 0), card]));
  const decks = Array.isArray(playerSave?.cards?.decks) ? playerSave.cards.decks : [];
  const activeDeck = decks.find((deck) => deck?.id === playerSave?.cards?.activeDeckId) || decks[0];
  const resolved = (Array.isArray(activeDeck?.cardInstanceIds) ? activeDeck.cardInstanceIds : [])
    .map((serialId) => bySerialId.get(parseInteger(serialId, 0)))
    .filter(Boolean);
  if (resolved.length) {
    return resolved;
  }
  const leader = bySerialId.get(parseInteger(playerSave?.profile?.leaderSerialId, 0));
  return leader ? [leader] : instances.slice(0, 1);
}

function applyFairyRewardExperience(playerSave, gainedExp) {
  const profile = playerSave.profile;
  const beforeLevel = Math.max(parseInteger(profile.level, 1), 1);
  const beforeExp = Math.max(parseInteger(profile.exp, 0), 0);
  const maxLevel = Math.max(parseInteger(profile.maxLevel, beforeLevel), beforeLevel);
  let afterLevel = beforeLevel;
  let afterExp = beforeExp + Math.max(parseInteger(gainedExp, 0), 0);
  let abilityPointsGranted = 0;

  while (afterLevel < maxLevel) {
    const threshold = getPlayerLevelRow(afterLevel)?.nextExp || 0;
    if (!threshold || afterExp < threshold) {
      break;
    }
    afterExp -= threshold;
    afterLevel += 1;
    abilityPointsGranted += getLevelUpPointGrant(afterLevel, playerSave);
  }

  profile.level = afterLevel;
  profile.exp = afterExp;
  profile.nextExp = getPlayerLevelRow(afterLevel)?.nextExp || 0;
  profile.percentage = profile.nextExp ? Math.floor((afterExp * 100) / profile.nextExp) : 100;
  if (abilityPointsGranted > 0) {
    const abilityPoints = playerSave.progression.abilityPoints;
    abilityPoints.unspent = Math.max(parseInteger(abilityPoints.unspent, 0) + abilityPointsGranted, 0);
    abilityPoints.fromLevels = Math.max(parseInteger(abilityPoints.fromLevels, 0) + abilityPointsGranted, 0);
    playerSave.resources.ap.current = Math.max(parseInteger(playerSave.resources.ap.max, 0), 0);
    playerSave.resources.bc.current = Math.max(parseInteger(playerSave.resources.bc.max, 0), 0);
  }
  return { beforeLevel, afterLevel, beforeExp, afterExp, abilityPointsGranted };
}

function createFairyBattleSettlement(playerSave, activeFairy, nowMs = Date.now()) {
  ensureExplorationSaveShape(playerSave);
  const deckCards = getFairyBattleDeckCards(playerSave);
  if (!deckCards.length) {
    throw new Error("fairy battle requires one resolved player deck card");
  }
  // ponytail: the recovered response/path does not yet establish the original BC charge or
  // insufficient-BC failure contract, so this bounded local battle leaves BC unchanged. Upgrade
  // this together with a captured retry/insufficient-BC edge instead of guessing a cost here.
  const playerMaxHp = Math.max(deckCards.reduce((sum, card) => sum + Math.max(parseInteger(card.hp, 0), 0), 0), 1);
  const fairyMaxHp = Math.max(parseInteger(activeFairy.maxHp, 1), 1);
  const fairyInitialHp = Math.min(Math.max(parseInteger(activeFairy.currentHp, fairyMaxHp), 1), fairyMaxHp);
  const fairyAttackPower = Math.max(parseInteger(activeFairy.attackPower, 1), 1);
  const fairyVisualMasterCardId = Math.max(parseInteger(activeFairy.visualMasterCardId, 600), 1);
  let playerHp = playerMaxHp;
  let fairyHp = fairyInitialHp;
  let rounds = 0;
  const actions = [];

  // ponytail: cap one local autoplay response at 200 rounds so extreme admin values cannot create
  // unbounded XML/animation. Replace with recovered multi-attempt raid semantics when available.
  while (playerHp > 0 && fairyHp > 0 && rounds < 200) {
    rounds += 1;
    actions.push({ turn: rounds });
    for (const card of deckCards) {
      const damage = Math.min(Math.max(parseInteger(card.power, 1), 1), fairyHp);
      fairyHp -= damage;
      actions.push({
        actionPlayer: 0,
        attackCard: Math.max(parseInteger(card.masterCardId, 1), 1),
        attackType: 1,
        attackDamage: damage,
      });
      if (fairyHp <= 0) {
        break;
      }
    }
    if (fairyHp <= 0) {
      break;
    }
    const damage = Math.min(fairyAttackPower, playerHp);
    playerHp -= damage;
    actions.push({
      actionPlayer: 1,
      attackCard: fairyVisualMasterCardId,
      attackType: 1,
      attackDamage: damage,
    });
  }

  if (playerHp > 0 && fairyHp > 0) {
    const playerRatio = playerHp / playerMaxHp;
    const fairyRatio = fairyHp / fairyMaxHp;
    if (playerRatio >= fairyRatio) {
      actions.push({ actionPlayer: 0, attackCard: Math.max(parseInteger(deckCards[0].masterCardId, 1), 1), attackType: 1, attackDamage: fairyHp });
      fairyHp = 0;
    } else {
      actions.push({ actionPlayer: 1, attackCard: fairyVisualMasterCardId, attackType: 1, attackDamage: playerHp });
      playerHp = 0;
    }
  }

  const playerWon = fairyHp <= 0;
  const beforeGold = Math.max(parseInteger(playerSave.currencies.gold, 0), 0);
  const rewardGold = playerWon ? Math.max(parseInteger(activeFairy.rewardGold, 0), 0) : 0;
  const rewardExp = playerWon ? Math.max(parseInteger(activeFairy.rewardExp, 0), 0) : 0;
  playerSave.currencies.gold = Math.min(beforeGold + rewardGold, 2147483647);
  const expResult = applyFairyRewardExperience(playerSave, rewardExp);
  playerSave.battle.wins = Math.max(parseInteger(playerSave.battle.wins, 0) + (playerWon ? 1 : 0), 0);
  playerSave.battle.losses = Math.max(parseInteger(playerSave.battle.losses, 0) + (playerWon ? 0 : 1), 0);

  const battledAt = new Date(nowMs).toISOString();
  const resolvedFairy = {
    ...activeFairy,
    currentHp: fairyHp,
    lastBattledAt: battledAt,
    defeatedAt: playerWon ? battledAt : null,
  };
  playerSave.battle.fairy.discovered[String(activeFairy.serialId)] = cloneJson(resolvedFairy);
  playerSave.battle.fairy.active = playerWon ? null : resolvedFairy;
  playerSave.battle.fairy.history.push({
    serialId: String(activeFairy.serialId),
    won: playerWon,
    playerDamage: fairyInitialHp - fairyHp,
    fairyDamage: playerMaxHp - playerHp,
    rewardGold,
    rewardExp,
    battledAt,
  });
  if (playerSave.battle.fairy.history.length > 100) {
    playerSave.battle.fairy.history = playerSave.battle.fairy.history.slice(-100);
  }

  return {
    playerSave,
    fairy: resolvedFairy,
    deckCards,
    actions,
    rounds,
    playerWon,
    // The result scene treats winner as a local-victory flag, not a player_enemy index.
    winner: playerWon ? 1 : 0,
    playerMaxHp,
    playerRemainingHp: playerHp,
    fairyInitialHp,
    fairyRemainingHp: fairyHp,
    fairyAttackPower,
    fairyVisualMasterCardId,
    beforeGold,
    afterGold: playerSave.currencies.gold,
    rewardGold,
    rewardExp,
    ...expResult,
  };
}

function renderFairyBattleCardXml(card, indent) {
  return [
    `${indent}<card_list>`,
    `${indent}  <master_card_id>${Math.max(parseInteger(card.masterCardId, 1), 1)}</master_card_id>`,
    `${indent}  <holography>${Math.max(parseInteger(card.holography, 0), 0)}</holography>`,
    `${indent}  <hp>${Math.max(parseInteger(card.hp, 1), 1)}</hp>`,
    `${indent}  <power>${Math.max(parseInteger(card.power, 1), 1)}</power>`,
    `${indent}  <lv>${Math.max(parseInteger(card.level, 1), 1)}</lv>`,
    `${indent}  <lv_max>${Math.max(parseInteger(card.maxLevel ?? card.level, 1), 1)}</lv_max>`,
    `${indent}</card_list>`,
  ];
}

function renderFairyBattlePlayerXml(player, indent = "      ") {
  const battleType = Math.max(parseInteger(player.type, 2), 0);
  const battleSize = Math.max(parseInteger(player.size, 0), 0);
  return [
    `${indent}<battle_player_list>`,
    `${indent}  <player_enemy>${player.enemy ? 1 : 0}</player_enemy>`,
    `${indent}  <name>${escapeXmlText(player.name)}</name>`,
    `${indent}  <type>${battleType}</type>`,
    `${indent}  <size>${battleSize}</size>`,
    `${indent}  <maxhp>${player.maxHp}</maxhp>`,
    `${indent}  <hp>${player.hp}</hp>`,
    ...player.cards.flatMap((card) => renderFairyBattleCardXml(card, `${indent}  `)),
    `${indent}  <ex>${player.ex}</ex>`,
    `${indent}  <maxex>100</maxex>`,
    `${indent}</battle_player_list>`,
  ];
}

function renderFairyBattleActionXml(action, indent = "      ") {
  if (action.turn) {
    return [`${indent}<battle_action_list><turn>${action.turn}</turn></battle_action_list>`];
  }
  return [
    `${indent}<battle_action_list>`,
    `${indent}  <action_player>${action.actionPlayer}</action_player>`,
    `${indent}  <attack_card>${action.attackCard}</attack_card>`,
    `${indent}  <attack_type>${action.attackType}</attack_type>`,
    `${indent}  <attack_damage>${action.attackDamage}</attack_damage>`,
    `${indent}</battle_action_list>`,
  ];
}

function createExplorationFairyBattleXml(playerSave, settlement) {
  if (!settlement) {
    throw new Error("fairy battle XML requires a settled battle record");
  }
  const leaderSerialId = parseInteger(playerSave.profile?.leaderSerialId, 0);
  const leaderCard = settlement.deckCards.find((card) => parseInteger(card.serialId, 0) === leaderSerialId)
    || settlement.deckCards[0];
  const fairyCard = {
    serialId: parseInteger(settlement.fairy.serialId, 1),
    masterCardId: settlement.fairyVisualMasterCardId,
    holography: 0,
    hp: settlement.fairyInitialHp,
    power: settlement.fairyAttackPower,
    critical: 0,
    level: Math.max(parseInteger(settlement.fairy.level, 1), 1),
    maxLevel: Math.max(parseInteger(settlement.fairy.level, 1), 1),
  };
  const currentFloorKey = String(playerSave.exploration?.currentFloorKey || "");
  const postBattleProgress = Math.min(Math.max(parseInteger(
    playerSave.exploration?.floors?.[currentFloorKey]?.progress,
    0
  ), 0), 100);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-fairy-battle</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>4100</next_scene>",
    "  </header>",
    "  <body>",
    "    <battle_vs_info>",
    "      <player>",
    `        <user_id>${Math.max(parseInteger(settlement.fairy.discovererId, 1), 1)}</user_id>`,
    `        <name>${escapeXmlText(playerSave.profile?.name || "Arthur")}</name>`,
    ...renderUserCardXml(leaderCard, "        "),
    "        <status_friend>2</status_friend><status_yell>0</status_yell>",
    "      </player>",
    "      <player>",
    `        <user_id>${Math.max(parseInteger(settlement.fairy.masterBossId, 1), 1)}</user_id>`,
    `        <name>${escapeXmlText(settlement.fairy.name || "小龙女")}</name>`,
    ...renderUserCardXml(fairyCard, "        "),
    "        <status_friend>2</status_friend><status_yell>0</status_yell>",
    "      </player>",
    "    </battle_vs_info>",
    "    <battle_battle>",
    "      <back_id>4</back_id><bgm_name>bgm_battle1</bgm_name>",
    ...renderFairyBattlePlayerXml({ name: playerSave.profile?.name || "Arthur", enemy: false, type: 2, size: 0, maxHp: settlement.playerMaxHp, hp: settlement.playerMaxHp, cards: settlement.deckCards, ex: Math.max(parseInteger(playerSave.resources?.super?.current, 0), 0) }),
    ...renderFairyBattlePlayerXml({ name: settlement.fairy.name || "小龙女", enemy: true, type: settlement.fairy.masterBossId, size: 0, maxHp: settlement.fairyInitialHp, hp: settlement.fairyInitialHp, cards: [fairyCard], ex: 0 }),
    ...settlement.actions.flatMap((action) => renderFairyBattleActionXml(action)),
    "    </battle_battle>",
    "    <battle_result>",
    "      <event_flag>0</event_flag><event_type>1</event_type>",
    `      <winner>${settlement.winner}</winner>`,
    "      <get_item_parts_event><event_id>0</event_id></get_item_parts_event>",
    `      <before_gold>${settlement.beforeGold}</before_gold><after_gold>${settlement.afterGold}</after_gold>`,
    `      <before_exp>${settlement.beforeExp}</before_exp><after_exp>${settlement.afterExp}</after_exp>`,
    `      <before_level>${settlement.beforeLevel}</before_level><after_level>${settlement.afterLevel}</after_level>`,
    "      <arena_battle_result><before_floor>0</before_floor><before_win>0</before_win><before_require_win>0</before_require_win><after_floor>0</after_floor><after_win>0</after_win><after_require_win>0</after_require_win></arena_battle_result>",
    "      <battle_event_result><battle_point>0</battle_point><bonus_end_time>0</bonus_end_time><bonus_rate>1</bonus_rate><get_point>0</get_point></battle_event_result>",
    "      <result_scene>4420</result_scene>",
    "    </battle_result>",
    // Scene 4420 reuses ExplorationMain. Event 18 is its original area_fairy_dead ->
    // reward_check_com path; no rare_fairy means an ordinary victory stops at settlement/return.
    ...renderExplorationExploreBodyXml(postBattleProgress, { gold: 0, getExp: 0 }, playerSave, null, null, 18),
    "  </body>",
    "</response>",
  ].join("");
}

function createRoundtableEditXml(playerSave = createDefaultPlayerSave()) {
  const save = playerSave && typeof playerSave === "object" ? playerSave : {};
  const cards = save.cards && typeof save.cards === "object" ? save.cards : {};
  const normalizeSerial = (value) => {
    const serial = typeof value === "string" && /^[1-9]\d*$/.test(value) ? Number(value) : value;
    return Number.isSafeInteger(serial) && serial > 0 ? serial : null;
  };
  const ownedSerials = new Set(
    (Array.isArray(cards.instances) ? cards.instances : [])
      .map((card) => normalizeSerial(card?.serialId ?? card?.serial_id))
      .filter((serial) => serial !== null)
  );
  const activeDeck = (Array.isArray(cards.decks) ? cards.decks : [])
    .find((deck) => deck?.id === cards.activeDeckId);
  const activeSlots = Array.isArray(activeDeck?.cardInstanceIds) ? activeDeck.cardInstanceIds : [];
  const deckCards = Array.from({ length: 12 }, (_, index) => {
    const serial = normalizeSerial(activeSlots[index]);
    return serial !== null && ownedSerials.has(serial) ? String(serial) : "empty";
  });
  const requestedLeader = normalizeSerial(save.profile?.leaderSerialId);
  const leaderCard = requestedLeader !== null
    && ownedSerials.has(requestedLeader)
    && deckCards.includes(String(requestedLeader))
    ? String(requestedLeader)
    : deckCards.find((slot) => slot !== "empty") || "";
  // ponytail: the parser proves ex_gauge exists, but no accepted source beyond the zero baseline exists yet.
  const exGauge = 0;

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-round-table</session_id>",
    ...renderYourDataXml(save),
    "    <next_scene>83200</next_scene>",
    "  </header>",
    "  <body>",
    "    <roundtable_edit>",
    `      <ex_gauge>${exGauge}</ex_gauge>`,
    `      <leader_card>${leaderCard}</leader_card>`,
    `      <deck_cards>${deckCards.join(",")}</deck_cards>`,
    "    </roundtable_edit>",
    "  </body>",
    "</response>",
  ].join("");
}

function getGachaSelectPage(pageName = "") {
  const pages = GAME_GACHA_DATA.pages || {};
  const defaultPage = GAME_GACHA_DATA.defaultPage || "main";
  const wanted = (pageName || defaultPage).trim();
  const pageKey = pages[wanted] ? wanted : defaultPage;
  return { pageKey, select: pages[pageKey] || {} };
}

function createGachaSelectSkeletonXml(playerSave = createDefaultPlayerSave(), pageName = "") {
  const { select } = getGachaSelectPage(pageName);
  const contents = Array.isArray(select.contents) ? select.contents : [];
  const scrollHeight = Math.max(parseInteger(select.scrollHeight, 0), 0);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-gacha</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>9100</next_scene>",
    "  </header>",
    "  <body>",
    "    <gacha_select>",
    "      <xml_contents>",
    `        <scroll_height>${scrollHeight}</scroll_height>`,
    ...contents.flatMap((content) => renderGachaSelectContentXml(content, "        ")),
    "      </xml_contents>",
    "    </gacha_select>",
    "  </body>",
    "</response>",
  ].join("");
}

function renderGachaSelectContentXml(content, indent = "        ") {
  const rows = [
    `${indent}<content>`,
    `${indent}  <action_id>${Math.max(parseInteger(content.actionId, 0), 0)}</action_id>`,
  ];
  if (content.imagefile) {
    rows.push(`${indent}  <imagefile>${escapeXmlText(content.imagefile)}</imagefile>`);
  }
  if (content.anmfile) {
    rows.push(`${indent}  <anmfile>${escapeXmlText(content.anmfile)}</anmfile>`);
  }
  if (content.se) {
    rows.push(`${indent}  <se>${escapeXmlText(content.se)}</se>`);
  }
  rows.push(`${indent}  <x>${parseInteger(content.x, 0)}</x>`);
  rows.push(`${indent}  <y>${parseInteger(content.y, 0)}</y>`);
  if (content.message) {
    rows.push(`${indent}  <message>${escapeXmlText(content.message)}</message>`);
  }
  if (content.scaleW !== undefined) {
    rows.push(`${indent}  <scale_w>${escapeXmlText(content.scaleW)}</scale_w>`);
  }
  if (content.scaleH !== undefined) {
    rows.push(`${indent}  <scale_h>${escapeXmlText(content.scaleH)}</scale_h>`);
  }
  if (Array.isArray(content.textMessages) && content.textMessages.length) {
    rows.push(`${indent}  <textdata>`);
    for (const message of content.textMessages) {
      rows.push(`${indent}    <message>`);
      rows.push(`${indent}      <text>${escapeXmlText(message.text || "")}</text>`);
      if (message.color) {
        rows.push(`${indent}      <color>${escapeXmlText(message.color)}</color>`);
      }
      if (message.size !== undefined) {
        rows.push(`${indent}      <size>${Math.max(parseInteger(message.size, 18), 1)}</size>`);
      }
      rows.push(`${indent}    </message>`);
    }
    rows.push(`${indent}  </textdata>`);
  }
  if (content.behavior) {
    rows.push(`${indent}  <behavior>${escapeXmlText(content.behavior)}</behavior>`);
  }
  rows.push(`${indent}</content>`);
  return rows;
}

function createGachaBuyXml(playerSave = createDefaultPlayerSave(), resultCard = null, productId = 1) {
  const buy = GAME_GACHA_DATA.buy || {};
  const drawCard = buy.drawCard || {};
  const fallbackDrawResult = resultCard ? null : addGachaDrawCardToPlayerSave(playerSave, drawCard);
  const responseSave = resultCard ? playerSave : fallbackDrawResult.save;
  const responseCard = resultCard
    ? { ...drawCard, serialId: resultCard.serialId, masterCardId: resultCard.masterCardId }
    : drawCard;
  const completeList = buy.completeList || {};
  const usePaid = parseInteger(productId, 1) === 2;
  const gachaType = usePaid ? parseInteger(buy.paidGachaType, 2) : parseInteger(buy.gachaType, 1);
  const telopMessage = usePaid ? (buy.paidTelopMessage || buy.telopMessage || "") : (buy.telopMessage || "");
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-gacha-buy</session_id>",
    ...renderYourDataXml(responseSave),
    "    <next_scene>9200</next_scene>",
    "  </header>",
    "  <body>",
    "    <gacha_buy>",
    "      <final_result>",
    ...renderGachaExUserCardXml(responseCard, "        "),
    "      </final_result>",
    `      <gacha_type>${Math.max(gachaType, 0)}</gacha_type>`,
    `      <telop_message>${escapeXmlText(telopMessage)}</telop_message>`,
    "      <complete_list>",
    `        <cmpsheet_index>${Math.max(parseInteger(completeList.cmpsheetIndex, 0), 0)}</cmpsheet_index>`,
    `        <is_get>${Math.max(parseInteger(completeList.isGet, 0), 0)}</is_get>`,
    `        <is_new>${Math.max(parseInteger(completeList.isNew, 0), 0)}</is_new>`,
    "      </complete_list>",
    "    </gacha_buy>",
    "  </body>",
    "</response>",
  ].join("");
}

function createPlayerCardFromGachaDraw(drawCard, serialId) {
  const masterCardId = Math.max(parseInteger(drawCard.masterCardId, 0), 0);
  if (!serialId || !masterCardId) {
    return null;
  }
  return {
    serialId: Math.max(parseInteger(serialId, 0), 0),
    masterCardId,
    holography: Math.max(parseInteger(drawCard.holography ?? drawCard.holoFlag, 0), 0),
    hp: Math.max(parseInteger(drawCard.hp, 0), 0),
    power: Math.max(parseInteger(drawCard.power, 0), 0),
    critical: Math.max(parseInteger(drawCard.critical, 0), 0),
    level: Math.max(parseInteger(drawCard.buildLevel, 1), 1),
    maxLevel: Math.max(parseInteger(drawCard.maxLevel, 1), 1),
    exp: Math.max(parseInteger(drawCard.buildExp, 0), 0),
    maxExp: Math.max(parseInteger(drawCard.maxExp, 0), 0),
    nextExp: Math.max(parseInteger(drawCard.nextExp, 0), 0),
    expDiff: Math.max(parseInteger(drawCard.expDiff, 0), 0),
    expPercent: Math.max(parseInteger(drawCard.expPercent, 0), 0),
    salePrice: Math.max(parseInteger(drawCard.salePrice, 0), 0),
    materialPrice: Math.max(parseInteger(drawCard.materialPrice, 0), 0),
    evolutionPrice: Math.max(parseInteger(drawCard.evolutionPrice, 0), 0),
    plusLimitCount: Math.max(parseInteger(drawCard.plusLimitCount, 0), 0),
    limitOver: Math.max(parseInteger(drawCard.limitOver, 0), 0),
  };
}

function getNextPlayerCardSerialId(instances, preferredSerialId = 0) {
  const used = new Set(instances.map((card) => parseInteger(card?.serialId ?? card?.serial_id, 0)).filter((id) => id > 0));
  const preferred = Math.max(parseInteger(preferredSerialId, 0), 0);
  if (preferred && !used.has(preferred)) {
    return preferred;
  }
  return Math.max(0, ...used) + 1;
}

function addGachaDrawCardToPlayerSave(playerSave, drawCard) {
  const save = mergeJsonObject(createDefaultPlayerSave(), playerSave || {});
  const cards = save.cards || {};
  const instances = Array.isArray(cards.instances) ? cards.instances : [];
  const serialId = getNextPlayerCardSerialId(instances, drawCard.serialId);
  const newCard = createPlayerCardFromGachaDraw(drawCard, serialId);
  if (!newCard) {
    return { save, card: null, added: false };
  }
  save.cards = {
    ...cards,
    instances: [...instances, newCard],
    count: instances.length + 1,
  };
  return { save, card: newCard, added: true };
}

function applyGachaBuySettlement(playerSave, params = {}) {
  const save = mergeJsonObject(createDefaultPlayerSave(), playerSave || {});
  const productId = parseInteger(params.product_id, 1);
  const bulk = Math.max(parseInteger(params.bulk, 1), 1);
  const buy = GAME_GACHA_DATA.buy || {};
  const drawCard = buy.drawCard || {};
  const currencies = save.currencies || {};
  const friendshipBefore = Math.max(parseInteger(save.currencies?.friendshipPoint, 0), 0);
  const friendshipCost = Math.max(parseInteger(save.gacha?.friendshipCost, 0), 0) * bulk;
  const useFriendship = productId === 1;
  const mcBefore = Math.max(parseInteger(currencies.mc, 0), 0);
  const paidCostMc = Math.max(parseInteger(save.gacha?.paidCostMc, 0), 0) * bulk;
  const usePaid = productId === 2;
  if (useFriendship && friendshipCost > 0) {
    save.currencies = save.currencies || {};
    save.currencies.friendshipPoint = Math.max(friendshipBefore - friendshipCost, 0);
  }
  if (usePaid && paidCostMc > 0) {
    save.currencies = save.currencies || {};
    save.currencies.mc = Math.max(mcBefore - paidCostMc, 0);
  }
  const drawResult = addGachaDrawCardToPlayerSave(save, drawCard);
  const settledSave = drawResult.save;
  settledSave.gacha = settledSave.gacha || {};
  settledSave.gacha.history = Array.isArray(settledSave.gacha.history) ? settledSave.gacha.history : [];
  if (drawResult.card) {
    settledSave.gacha.history.push({
      productId,
      bulk,
      serialId: drawResult.card.serialId,
      masterCardId: drawResult.card.masterCardId,
    });
  }
  settledSave.stats = settledSave.stats || {};
  settledSave.stats.cardsDrawn = parseInteger(settledSave.stats.cardsDrawn, 0) + (drawResult.card ? 1 : 0);
  return {
    playerSave: settledSave,
    drawCard: drawResult.card,
    friendshipBefore,
    friendshipAfter: Math.max(parseInteger(settledSave.currencies?.friendshipPoint, 0), 0),
    friendshipCost: useFriendship ? friendshipCost : 0,
    mcBefore,
    mcAfter: Math.max(parseInteger(settledSave.currencies?.mc, 0), 0),
    mcCost: usePaid ? paidCostMc : 0,
    productId,
    bulk,
    ownerCardCount: Array.isArray(settledSave.cards?.instances) ? settledSave.cards.instances.length : 0,
    cardsDrawn: parseInteger(settledSave.stats?.cardsDrawn, 0),
  };
}

function renderGachaExUserCardXml(card, indent = "        ") {
  return [
    `${indent}<ex_user_card>`,
    `${indent}  <serial_id>${Math.max(parseInteger(card.serialId, 0), 0)}</serial_id>`,
    `${indent}  <master_card_id>${Math.max(parseInteger(card.masterCardId, 0), 0)}</master_card_id>`,
    `${indent}  <holo_flag>${Math.max(parseInteger(card.holoFlag, 0), 0)}</holo_flag>`,
    `${indent}  <build_exp>${Math.max(parseInteger(card.buildExp, 0), 0)}</build_exp>`,
    `${indent}  <build_lv>${Math.max(parseInteger(card.buildLevel, 1), 1)}</build_lv>`,
    `${indent}  <build_cnt>${Math.max(parseInteger(card.buildCount, 0), 0)}</build_cnt>`,
    `${indent}  <is_new_card>${Math.max(parseInteger(card.isNewCard, 0), 0)}</is_new_card>`,
    `${indent}</ex_user_card>`,
  ];
}

function createMenuRankingSkeletonXml(playerSave = createDefaultPlayerSave()) {
  // ponytail: menu smoke only needs one valid picker tab; real ranking rows can come later.
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-ranking</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>27100</next_scene>",
    "  </header>",
    "  <body>",
    "    <ranking>",
    "      <ranktype_id>1</ranktype_id>",
    "      <exist_top>0</exist_top>",
    "      <exist_bottom>0</exist_bottom>",
    "      <ranking_draw_type>0</ranking_draw_type>",
    "      <ranktype_list>",
    "        <ranktype>",
    "          <tab_id>1</tab_id>",
    "          <title>Total</title>",
    "        </ranktype>",
    "      </ranktype_list>",
    "      <user_list></user_list>",
    "    </ranking>",
    "  </body>",
    "</response>",
  ].join("");
}

function createMenuFairySelectSkeletonXml(playerSave = createDefaultPlayerSave()) {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-fairy-select</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>29200</next_scene>",
    "  </header>",
    "  <body>",
    "    <fairy_select>",
    "      <fairy_rewards>0</fairy_rewards>",
    "    </fairy_select>",
    "  </body>",
    "</response>",
  ].join("");
}

function getPlayerOwnedMasterCardIds(playerSave = createDefaultPlayerSave()) {
  const instances = Array.isArray(playerSave.cards?.instances) ? playerSave.cards.instances : [];
  const ids = instances
    .map((card) => parseInteger(card?.masterCardId ?? card?.master_card_id, 0))
    .filter((id) => id > 0);
  const uniqueIds = [...new Set(ids)];
  // ponytail: a blank collection crashes the native picker; seed the accepted starter card until card acquisition is real.
  return uniqueIds.length ? uniqueIds : [22];
}

function createMenuCardCollectionSkeletonXml(playerSave = createDefaultPlayerSave()) {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-card-collection</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>23100</next_scene>",
    "  </header>",
    "  <body>",
    "    <card_collection>",
    `      <card_library>${getPlayerOwnedMasterCardIds(playerSave).join(",")}</card_library>`,
    "      <lvmax_library></lvmax_library>",
    "      <holo_library></holo_library>",
    "    </card_collection>",
    "  </body>",
    "</response>",
  ].join("");
}

const MENU_HAVE_PARTS_ROWS = [
  [1, 1],
  [2, 1],
  [3, 0],
  [4, 0],
  [5, 1],
  [6, 1],
  [7, 0],
  [8, 1],
  [9, 0],
];

function renderMenuHavePartsRows(indent = "        ") {
  return MENU_HAVE_PARTS_ROWS.flatMap(([partsNum, partsHave]) => [
    `${indent}<parts>`,
    `${indent}  <parts_num>${partsNum}</parts_num>`,
    `${indent}  <parts_have>${partsHave}</parts_have>`,
    `${indent}</parts>`,
  ]);
}

function createMenuHavePartsSkeletonXml(playerSave = createDefaultPlayerSave()) {
  // ponytail: one proven local_battle_area lake is enough to avoid the native no-data modal; real factor progression can replace this later.
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-have-parts</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>31100</next_scene>",
    "  </header>",
    "  <body>",
    "    <have_parts>",
    "      <select_lake_id>2</select_lake_id>",
    "      <leader_card_id>179</leader_card_id>",
    "      <select_parts_num>1</select_parts_num>",
    "      <lake>",
    "        <lake_id>2</lake_id>",
    "        <title>花を愛す者</title>",
    "        <master_card_id>179</master_card_id>",
    "        <complete>0</complete>",
    "        <parts_list>",
    ...renderMenuHavePartsRows("          "),
    "        </parts_list>",
    "      </lake>",
    "    </have_parts>",
    "  </body>",
    "</response>",
  ].join("");
}

function getStarterCardForFriendList(playerSave = createDefaultPlayerSave()) {
  const instances = Array.isArray(playerSave.cards?.instances) ? playerSave.cards.instances : [];
  return instances.find((card) => parseInteger(card?.serialId ?? card?.serial_id, 0) > 0)
    || createDefaultPlayerSave().cards.instances[0];
}

function getMenuFriendRows(playerSave = createDefaultPlayerSave()) {
  const friends = Array.isArray(playerSave.friends?.list) ? playerSave.friends.list : [];
  if (friends.length) {
    return friends;
  }
  const profile = playerSave.profile || {};
  const resources = playerSave.resources || {};
  const cards = playerSave.cards || {};
  // ponytail: a one-row local fallback proves the friend-list scene safely; a real friends system can replace it with saved friends later.
  return [{
    id: 1,
    name: "Local Friend",
    countryId: getPlayerCountryId(playerSave),
    cost: 61,
    win: 0,
    lose: 0,
    townLevel: Math.max(parseInteger(profile.townLevel, 1), 1),
    nextExp: Math.max(parseInteger(profile.nextExp, 0), 0),
    leaderCard: getStarterCardForFriendList(playerSave),
    rank: Math.max(parseInteger(profile.level, 1), 1),
    friends: Math.max(parseInteger(playerSave.friends?.count, 0), 0),
    friendMax: Math.max(parseInteger(playerSave.friends?.max, 30), 0),
    lastLogin: "今日",
    exGauge: Math.max(parseInteger(resources.super?.current, 0), 0),
    maxCardNum: Math.max(parseInteger(cards.max, 0), 0),
    statusFriend: 0,
    statusYell: 1,
    countHunting: 0,
    deckRank: Math.max(parseInteger(cards.deckRank, 0), 0),
  }];
}

function renderMenuFriendRowXml(friend, playerSave = createDefaultPlayerSave(), indent = "        ") {
  const leaderCard = friend.leaderCard || getStarterCardForFriendList(playerSave);
  return [
    `${indent}<user>`,
    `${indent}  <id>${Math.max(parseInteger(friend.id, 0), 0)}</id>`,
    `${indent}  <name>${escapeXmlText(friend.name || "Local Friend")}</name>`,
    `${indent}  <country_id>${VALID_COUNTRY_IDS.has(parseInteger(friend.countryId, 1)) ? parseInteger(friend.countryId, 1) : 1}</country_id>`,
    `${indent}  <cost>${Math.max(parseInteger(friend.cost, 0), 0)}</cost>`,
    `${indent}  <results>`,
    `${indent}    <win>${Math.max(parseInteger(friend.win, 0), 0)}</win>`,
    `${indent}    <lose>${Math.max(parseInteger(friend.lose, 0), 0)}</lose>`,
    `${indent}  </results>`,
    `${indent}  <town_level>${Math.max(parseInteger(friend.townLevel, 1), 1)}</town_level>`,
    `${indent}  <next_exp>${Math.max(parseInteger(friend.nextExp, 0), 0)}</next_exp>`,
    ...renderLeaderCardXml(leaderCard, `${indent}  `),
    `${indent}  <rank>${Math.max(parseInteger(friend.rank, 1), 1)}</rank>`,
    `${indent}  <friends>${Math.max(parseInteger(friend.friends, 0), 0)}</friends>`,
    `${indent}  <friend_max>${Math.max(parseInteger(friend.friendMax, 30), 0)}</friend_max>`,
    `${indent}  <last_login>${escapeXmlText(friend.lastLogin || "今日")}</last_login>`,
    `${indent}  <ex_gage>${Math.max(parseInteger(friend.exGauge, 0), 0)}</ex_gage>`,
    `${indent}  <max_card_num>${Math.max(parseInteger(friend.maxCardNum, 0), 0)}</max_card_num>`,
    `${indent}  <status_friend>${Math.max(parseInteger(friend.statusFriend, 0), 0)}</status_friend>`,
    `${indent}  <status_yell>${Math.max(parseInteger(friend.statusYell, 0), 0)}</status_yell>`,
    `${indent}  <count_hunting>${Math.max(parseInteger(friend.countHunting, 0), 0)}</count_hunting>`,
    `${indent}  <deck_rank>${Math.max(parseInteger(friend.deckRank, 0), 0)}</deck_rank>`,
    `${indent}</user>`,
  ];
}

function createMenuFriendListSkeletonXml(playerSave = createDefaultPlayerSave()) {
  const friendRows = getMenuFriendRows(playerSave);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-friend-list</session_id>",
    ...renderYourDataXml(playerSave),
    "    <next_scene>17100</next_scene>",
    "  </header>",
    "  <body>",
    "    <friend_list>",
    "      <friends_invitations>0</friends_invitations>",
    "      <user_list>",
    ...friendRows.flatMap((friend) => renderMenuFriendRowXml(friend, playerSave, "        ")),
    "      </user_list>",
    "    </friend_list>",
    "  </body>",
    "</response>",
  ].join("");
}

const MAINMENU_UPDATE_XML = createMainmenuUpdateXml();
TOWN_POINTSETTING_XML = createTownPointsettingXml();
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
const LOGIN_MAINMENU_XML = createLoginMainmenuXml();
const MAINMENU_ROUTE_STUBS = {
  "/connect/app/gacha/select/getcontents": { command: "gacha", nextScene: 9100 },
  "/connect/app/gacha/comp_sheet": { command: "gacha_comp_sheet", nextScene: 9500, sample: "local_gachacomp.xml" },
  "/connect/app/gacha/getproductinfo": { command: "gacha_productinfo", nextScene: 8200 },
  "/connect/app/gacha/buy": { command: "gacha_buy", nextScene: 9200 },
  "/connect/app/battle/area": { command: "battle", nextScene: 5100, sample: "local_battle_area.xml" },
  "/connect/app/battle/playerlist": { command: "battle", nextScene: 5200 },
  "/connect/app/battle/battle_userlist": { command: "battle_userlist", nextScene: 5200, sample: "local_users_event_list.xml" },
  "/connect/app/battle/battle_userlist_first": { command: "battle_userlist", nextScene: 5200, sample: "local_users_event_list.xml" },
  "/connect/app/battle/battle_userlist_second": { command: "battle_userlist", nextScene: 5200, sample: "local_users_event_list.xml" },
  "/connect/app/battle/competition_userlist": { command: "battle_userlist", nextScene: 5300, sample: "local_users_event_list.xml" },
  "/connect/app/battle/shooting_userlist": { command: "battle_userlist", nextScene: 5300, sample: "local_users_event_list.xml" },
  "/connect/app/menu/menulist": { command: "menu", nextScene: 20100 },
  "/connect/app/menu/rewardbox": { command: "reward", nextScene: 21100 },
  "/connect/app/menu/get_rewards": { command: "get_rewards", nextScene: 90200 },
  "/connect/app/menu/noticelist": { command: "notice", nextScene: 20100 },
  "/connect/app/menu/other_list": { command: "other_list", nextScene: 20100 },
  "/connect/app/menu/friendlist": { command: "friends", nextScene: 17100 },
  "/connect/app/menu/menu_friend_notification": { command: "friend_notice", nextScene: 22200 },
  "/connect/app/menu/friend_notice": { command: "friend_notice", nextScene: 22200 },
  "/connect/app/menu/friend_appstate": { command: "friend_appstate", nextScene: 29300 },
  "/connect/app/menu/player_search": { command: "friend_search", nextScene: 22300 },
  "/connect/app/menu/cardcollection": { command: "c_collection", nextScene: 23100 },
  "/connect/app/menu/recycle/recycle": { command: "recycle", nextScene: 24100 },
  "/connect/app/menu/recycle/recycle_buy": { command: "recycle_buy", nextScene: 24200 },
  "/connect/app/menu/recycle/recycle_select": { command: "recycle_select", nextScene: 24200 },
  "/connect/app/menu/battlehistory": { command: "b_history", nextScene: 25100 },
  "/connect/app/menu/playerinfo": { command: "p_info", nextScene: 26100 },
  "/connect/app/menu/goodlist": { command: "goodlist", nextScene: 26700 },
  "/connect/app/menu/ranking/ranking_arena": { command: "ranking", nextScene: 27100 },
  "/connect/app/menu/ranking/rankingevent": { command: "ranking", nextScene: 27100 },
  "/connect/app/ranking/ranking": { command: "ranking", nextScene: 27100 },
  "/connect/app/ranking/ranking_next": { command: "ranking_next", nextScene: 27100 },
  "/connect/app/ranking/ranking_previous": { command: "ranking_previous", nextScene: 27100 },
  "/connect/app/menu/gettownevent": { command: "town_event", nextScene: 28100 },
  "/connect/app/menu/towneventlist": { command: "town_event", nextScene: 28100 },
  "/connect/app/menu/fairyselect": { command: "fairy", nextScene: 29200 },
  "/connect/app/menu/fairyrewards": { command: "fairy_rewards", nextScene: 29200 },
  "/connect/app/friend/add_friend": { command: "friend_add", nextScene: 17000 },
  "/connect/app/friend/approve_friend": { command: "friend_approve", nextScene: 17000 },
  "/connect/app/friend/cancel_apply": { command: "friend_cancel_apply", nextScene: 17000 },
  "/connect/app/friend/like_user": { command: "friend_like", nextScene: 17000 },
  "/connect/app/friend/refuse_friend": { command: "friend_refuse", nextScene: 17000 },
  "/connect/app/friend/remove_friend": { command: "friend_remove", nextScene: 17000 },
  "/connect/app/item/havelist": { command: "item", nextScene: 30100 },
  "/connect/app/item/use": { command: "item_use", nextScene: 30200 },
  "/connect/app/item/use_fakecard": { command: "item_use_fakecard", nextScene: 30200 },
  "/connect/app/menu/haveparts": { command: "partslist", nextScene: 31100 },
  "/connect/app/menu/invite_friend": { command: "invide", nextScene: 32100 },
  "/connect/app/menu/chksnd": { command: "option", nextScene: 33000 },
  "/connect/app/story/getoutline": { command: "story", nextScene: 3100 },
  "/connect/app/story/battle": { command: "story_battle", nextScene: 3400 },
  "/connect/app/shop/shop": { command: "shop", nextScene: 8100 },
  "/connect/app/shop/buy": { command: "shop_buy", nextScene: 8200 },
  "/connect/app/shop/use": { command: "shop_use", nextScene: 8100 },
  "/connect/app/menu/productlist": { command: "productlist", nextScene: 8400 },
  "/connect/app/menu/buyproduct": { command: "buyproduct", nextScene: 8400 },
  "/connect/app/trunk/sell": { command: "compound", nextScene: 7500 },
  "/connect/app/compound/evolution/getinfo": { command: "compound_evolution", nextScene: 7100 },
  "/connect/app/compound/buildup/getinfo": { command: "compound_buildup", nextScene: 7300 },
  "/connect/app/compound/evolution/compound": { command: "compound_evolution_commit", nextScene: 7150 },
  "/connect/app/compound/buildup/compound": { command: "compound_buildup_commit", nextScene: 7350 },
  "/connect/app/card/exchange": { command: "card_exchange", nextScene: 7200 },
  "/connect/app/roundtable/edit": { command: "round_table", nextScene: 83200 },
  "/connect/app/cardselect/savedeckcard": { command: "save_deck", nextScene: 83200 },
};
const MASTERDATA_SAMPLES = Object.fromEntries(
  Object.entries(MASTERDATA_ROUTE_FILES).map(([route, relativePath]) => [
    route,
    {
      relativePath,
      bytes: readSampleSaveFile(relativePath),
    },
  ])
);

const MASTER_CARD_UPDATE_ROUTE = "/connect/app/masterdata/card/update";
const MASTER_CARD_SOURCE_SHA256 = "7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF";
const MASTER_CARD_STRING_FIELDS = [
  "name",
  "char_description",
  "skill_kana",
  "skill_name",
  "skill_description",
  "illustrator",
];
const MASTER_CARD_NUMBER_FIELDS = [
  "cost",
  "rarity",
  "extra",
  "eye_y",
  "sale_price",
  "compound_target_id",
  "compound_result_id",
  "base_hp",
  "base_power",
  "max_lv",
  "image1_id",
  "image2_id",
  "character_id",
  "evolution_base_price",
  "data_type",
  "grow_type",
];
const MASTER_CARD_TRAILING_NUMBER_FIELDS = [
  "skill_type",
  "form_id",
  "distinction",
  "card_version",
  "attack_type",
  "lvmax_hp",
  "lvmax_power",
  "base_holo_hp",
  "base_holo_power",
  "lvmax_holo_hp",
  "lvmax_holo_power",
  "max_lv_holo",
  "compound_type",
];
const MASTER_CARD_WIRE_FIELDS = [
  "master_card_id",
  "country_id",
  ...MASTER_CARD_STRING_FIELDS,
  ...MASTER_CARD_NUMBER_FIELDS,
  "grow_name",
  "growth_rate_text",
  ...MASTER_CARD_TRAILING_NUMBER_FIELDS,
];

function parseSerializedMasterCards(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 8) {
    throw new Error("master_card sample is missing or too short");
  }
  const sourceSha256 = crypto.createHash("sha256").update(buffer).digest("hex").toUpperCase();
  if (sourceSha256 !== MASTER_CARD_SOURCE_SHA256) {
    throw new Error(`master_card source SHA-256 changed: ${sourceSha256}`);
  }

  const count = buffer.readUInt32BE(0);
  if (count !== 480 || 4 + count * 4 > buffer.length) {
    throw new Error(`unexpected master_card record count: ${count}`);
  }
  const offsets = Array.from({ length: count }, (_, index) => buffer.readUInt32BE(4 + index * 4));
  if (offsets[0] !== 4 + count * 4 || offsets.some((offset, index) => (
    offset >= buffer.length || (index > 0 && offset <= offsets[index - 1])
  ))) {
    throw new Error("invalid master_card record offsets");
  }

  const cards = offsets.map((start, index) => {
    const end = index + 1 < count ? offsets[index + 1] : buffer.length;
    let position = start;
    const card = {};

    function readU32() {
      if (position + 4 > end) {
        throw new Error(`master_card record ${index + 1} integer exceeds its boundary`);
      }
      const value = buffer.readUInt32BE(position);
      position += 4;
      return value;
    }

    function readString() {
      const length = readU32();
      if (position + length > end) {
        throw new Error(`master_card record ${index + 1} string exceeds its boundary`);
      }
      const value = buffer.subarray(position, position + length).toString("utf8");
      position += length;
      return value;
    }

    card.master_card_id = readU32();
    card.country_id = readU32();
    for (const field of MASTER_CARD_STRING_FIELDS) {
      card[field] = readString();
    }
    for (const field of MASTER_CARD_NUMBER_FIELDS) {
      card[field] = readU32();
    }
    card.grow_name = readString();
    card.growth_rate_text = readString();
    for (const field of MASTER_CARD_TRAILING_NUMBER_FIELDS) {
      card[field] = readU32();
    }
    if (position !== end) {
      throw new Error(`master_card record ${index + 1} was not consumed exactly`);
    }
    return card;
  });

  if (new Set(cards.map((card) => card.master_card_id)).size !== cards.length) {
    throw new Error("master_card ids are not unique");
  }
  return cards;
}

function createMasterCardUpdateXml(buffer, selectedMasterCardIds = []) {
  const allCards = parseSerializedMasterCards(buffer);
  const selectedIds = [...new Set(selectedMasterCardIds.map(Number).filter((value) => Number.isSafeInteger(value) && value > 0))];
  const selectedSet = new Set(selectedIds);
  const cards = selectedIds.length > 0
    ? allCards.filter((card) => selectedSet.has(card.master_card_id))
    : allCards;
  if (cards.length !== (selectedIds.length || allCards.length)) {
    const foundIds = new Set(cards.map((card) => card.master_card_id));
    throw new Error(`unknown master_card ids requested: ${selectedIds.filter((id) => !foundIds.has(id)).join(",")}`);
  }
  const lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<master_data>",
    "  <master_card_data>",
    "    <update_type>1</update_type>",
  ];
  for (const card of cards) {
    lines.push("    <card>");
    for (const field of MASTER_CARD_WIRE_FIELDS) {
      lines.push(`      <${field}>${escapeXmlText(card[field])}</${field}>`);
    }
    lines.push("    </card>");
  }
  lines.push("  </master_card_data>", "</master_data>");
  return {
    xml: lines.join("\n"),
    cards,
    sourceRecordCount: allCards.length,
    selectedMasterCardIds: selectedIds,
    sourceSha256: MASTER_CARD_SOURCE_SHA256,
    updateType: 1,
  };
}

const MASTER_CARD_UPDATE = MASTERDATA_SAMPLES[MASTER_CARD_UPDATE_ROUTE]?.bytes
  ? createMasterCardUpdateXml(MASTERDATA_SAMPLES[MASTER_CARD_UPDATE_ROUTE].bytes)
  : null;

function getConfiguredMasterCardUpdate() {
  const raw = (process.env.KSSMA_CARD_UPDATE_IDS || "").trim();
  if (!raw) {
    return MASTER_CARD_UPDATE;
  }
  if (!/^\d+(?:,\d+)*$/.test(raw)) {
    throw new Error("KSSMA_CARD_UPDATE_IDS must be a comma-separated list of positive integers");
  }
  // ponytail: diagnostic-only bounded payload for distinguishing callback parsing from full-payload rejection.
  // The default product response remains the complete recovered 480-card update.
  return createMasterCardUpdateXml(
    MASTERDATA_SAMPLES[MASTER_CARD_UPDATE_ROUTE]?.bytes,
    raw.split(",").map(Number)
  );
}

function withMainmenuBg(xml, playerSave = createDefaultPlayerSave()) {
  const body = [
    "<body>",
    ...renderMainmenuFields(playerSave),
    "</body>",
  ].join("");
  // ponytail: login jumps straight to scene 2100, so seed the layout-bound town model fields there too.
  return suppressLoginUpdates(xml.replace(/<body>\s*<\/body>/, body));
}

function createLoginMainmenuXml(playerSave = createDefaultPlayerSave()) {
  return replaceHeaderYourData(withMainmenuBg(LOGIN_OK_XML, playerSave), playerSave);
}

function suppressLoginUpdates(xml) {
  // ponytail: the 140330 save dump is preloaded; advertising newer revisions only wakes a broken CDN pack updater.
  const suppressed = xml
    .replace(/<(card_rev|boss_rev|item_rev|card_category_rev|gacha_rev|privilege_rev)>\d+<\/\1>/g, "<$1>0</$1>")
    .replace(/<revision>\d+<\/revision>/g, "<revision>0</revision>");
  const cardRevision = getAdvertisedCardRevision();
  return cardRevision > 0
    ? suppressed.replace(/<card_rev>0<\/card_rev>/, `<card_rev>${cardRevision}</card_rev>`)
    : suppressed;
}

function getAdvertisedCardRevision() {
  // ponytail: diagnostic-only escape hatch for replaying the original card-master updater on A12.
  // It defaults off; promote it only after the native update callback is identified and accepted.
  const raw = (process.env.KSSMA_CARD_REVISION_OVERRIDE || "").trim();
  if (!/^\d+$/.test(raw)) {
    return 0;
  }
  const revision = Number(raw);
  return Number.isSafeInteger(revision) && revision > 0 && revision <= 0x7fffffff ? revision : 0;
}

function getLoginOkXml(playerSave = createDefaultPlayerSave()) {
  // ponytail: default to the safe stub; opt into native scene payloads only when debugging that path.
  const loginResponse = (process.env.LOGIN_RESPONSE || "").trim().toLowerCase();
  if (loginResponse === "tutorial") {
    return LOGIN_TUTORIAL_XML;
  }
  if (loginResponse === "sample") {
    return createLoginMainmenuXml(playerSave);
  }
  return CHECK_INSPECTION_OK_XML;
}

function getLoginXmlSource(loginXml) {
  if (loginXml === LOGIN_TUTORIAL_XML) {
    return "assets/bundle/local_forward_tutorial.xml";
  }
  if (loginXml === LOGIN_MAINMENU_XML || /<mainmenu>/.test(loginXml)) {
    return "assets/bundle/local_battle_player.xml + mainmenu bg";
  }
  return "minimal";
}

function createMainmenuRouteXml(routePath, playerSave = createDefaultPlayerSave()) {
  const route = MAINMENU_ROUTE_STUBS[routePath];
  if (!route) {
    return null;
  }
  if (route.command === "gacha") {
    return createGachaSelectSkeletonXml(playerSave);
  }
  if (route.command === "gacha_buy") {
    return createGachaBuyXml(playerSave);
  }
  if (route.command === "ranking" || route.command === "ranking_next") {
    return createMenuRankingSkeletonXml(playerSave);
  }
  if (route.command === "fairy") {
    return createMenuFairySelectSkeletonXml(playerSave);
  }
  if (route.command === "c_collection") {
    return createMenuCardCollectionSkeletonXml(playerSave);
  }
  if (route.command === "partslist") {
    return createMenuHavePartsSkeletonXml(playerSave);
  }
  if (route.command === "friends") {
    return createMenuFriendListSkeletonXml(playerSave);
  }
  if (route.command === "round_table") {
    return createRoundtableEditXml(playerSave);
  }
  if (route.sample) {
    const fallback = createSceneForwardXml(route.nextScene, playerSave, `local-${route.command}`);
    return replaceHeaderYourData(suppressLoginUpdates(readBundledXml(route.sample, fallback)), playerSave);
  }
  // ponytail: these are route skeletons for page entry/back testing; page-specific lists come after a flow proves the next frontier.
  return createSceneForwardXml(route.nextScene, playerSave, `local-${route.command}`);
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

function getRuntimeConfigPath() {
  return (process.env.KSSMA_RUNTIME_CONFIG_PATH || RUNTIME_CONFIG_DATA_PATH).trim();
}

function readRuntimeConfig(configPath = getRuntimeConfigPath()) {
  const saved = readJsonFile(configPath);
  return mergeJsonObject(DEFAULT_RUNTIME_CONFIG, saved || {});
}

function readBooleanOverride(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === "") {
    return fallback;
  }
  return /^(1|true|yes|on)$/i.test(raw.trim());
}

function getFairyEncounterSettings(runtimeConfig = readRuntimeConfig()) {
  const defaults = DEFAULT_RUNTIME_CONFIG.fairyEncounter;
  const saved = runtimeConfig.fairyEncounter || {};
  const ratePercent = Math.min(Math.max(parseInteger(
    process.env.KSSMA_FAIRY_ENCOUNTER_RATE ?? saved.ratePercent,
    defaults.ratePercent
  ), 0), 100);
  return {
    enabled: readBooleanOverride("KSSMA_FAIRY_ENABLED", saved.enabled === true),
    ratePercent,
    masterBossId: Math.max(parseInteger(saved.masterBossId, defaults.masterBossId), 1),
    name: typeof saved.name === "string" && saved.name ? saved.name : defaults.name,
    level: Math.min(Math.max(parseInteger(process.env.KSSMA_FAIRY_LEVEL ?? saved.level, defaults.level), 1), 999),
    maxHp: Math.min(Math.max(parseInteger(process.env.KSSMA_FAIRY_MAX_HP ?? saved.maxHp, defaults.maxHp), 1), 2147483647),
    visualMasterCardId: Math.max(parseInteger(saved.visualMasterCardId, defaults.visualMasterCardId), 1),
    attackPower: Math.min(Math.max(parseInteger(
      process.env.KSSMA_FAIRY_ATTACK_POWER ?? saved.attackPower,
      defaults.attackPower
    ), 1), 2147483647),
    rewardGold: Math.min(Math.max(parseInteger(
      process.env.KSSMA_FAIRY_REWARD_GOLD ?? saved.rewardGold,
      defaults.rewardGold
    ), 0), 2147483647),
    rewardExp: Math.min(Math.max(parseInteger(
      process.env.KSSMA_FAIRY_REWARD_EXP ?? saved.rewardExp,
      defaults.rewardExp
    ), 0), 2147483647),
    timeLimitSeconds: Math.min(Math.max(parseInteger(
      process.env.KSSMA_FAIRY_TIME_LIMIT_SECONDS ?? saved.timeLimitSeconds,
      defaults.timeLimitSeconds
    ), 60), 86400),
  };
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
  playerSave.resources.bc = playerSave.resources.bc || {};
  playerSave.progression = playerSave.progression || {};
  playerSave.progression.abilityPoints = playerSave.progression.abilityPoints || {};
  playerSave.currencies = playerSave.currencies || {};
  playerSave.exploration = playerSave.exploration || {};
  playerSave.exploration.movesByFloor = playerSave.exploration.movesByFloor || {};
  playerSave.exploration.regions = playerSave.exploration.regions || {};
  playerSave.exploration.floors = playerSave.exploration.floors || {};
  playerSave.exploration.encounters = playerSave.exploration.encounters || [];
  playerSave.battle = playerSave.battle || {};
  playerSave.battle.fairy = playerSave.battle.fairy || {};
  playerSave.battle.fairy.discovered = playerSave.battle.fairy.discovered || {};
  playerSave.battle.fairy.history = playerSave.battle.fairy.history || [];
  playerSave.stats = playerSave.stats || {};
}

function hasLiveFairyEncounter(playerSave, nowMs = Date.now()) {
  const active = playerSave.battle?.fairy?.active;
  if (!active || parseInteger(active.currentHp, 0) <= 0) {
    return false;
  }
  const expiresAt = Date.parse(active.expiresAt || "");
  return !Number.isFinite(expiresAt) || expiresAt > nowMs;
}

function shouldCreateFairyEncounter(playerSave, settings) {
  if (!settings.enabled || hasLiveFairyEncounter(playerSave)) {
    return false;
  }
  if (settings.ratePercent <= 0) {
    return false;
  }
  if (settings.ratePercent >= 100) {
    return true;
  }
  return crypto.randomInt(100) < settings.ratePercent;
}

function createFairyEncounter(playerSave, settings, floor, nowMs = Date.now()) {
  ensureExplorationSaveShape(playerSave);
  const fairySave = playerSave.battle.fairy;
  const serialNumber = Math.max(parseInteger(fairySave.nextSerialId, 100001), 1);
  const discoveredAt = new Date(nowMs).toISOString();
  const encounter = {
    serialId: String(serialNumber),
    masterBossId: settings.masterBossId,
    name: settings.name,
    level: settings.level,
    currentHp: settings.maxHp,
    maxHp: settings.maxHp,
    visualMasterCardId: settings.visualMasterCardId,
    attackPower: settings.attackPower,
    rewardGold: settings.rewardGold,
    rewardExp: settings.rewardExp,
    timeLimitSeconds: settings.timeLimitSeconds,
    discovererId: Math.max(parseInteger(playerSave.account?.userId, 1), 1),
    rareFlg: 0,
    eventCharaFlg: 0,
    discoveredAt,
    expiresAt: new Date(nowMs + settings.timeLimitSeconds * 1000).toISOString(),
  };

  fairySave.nextSerialId = serialNumber + 1;
  fairySave.active = encounter;
  fairySave.discovered[encounter.serialId] = cloneJson(encounter);
  playerSave.exploration.encounters.push({
    type: "fairy",
    serialId: encounter.serialId,
    floorKey: getExplorationFloorStateKey(floor),
    discoveredAt,
  });
  return encounter;
}

function getLevelUpPointGrant(newLevel, playerSave) {
  const rules = playerSave.progression?.levelUpRules || {};
  const pointsUntilLevel50 = Math.max(parseInteger(rules.pointsUntilLevel50, 3), 0);
  const pointsAfterLevel50 = Math.max(parseInteger(rules.pointsAfterLevel50, 2), 0);
  return newLevel >= 50 ? pointsAfterLevel50 : pointsUntilLevel50;
}

function applyTownPointsetting(playerSave, params = {}) {
  ensureExplorationSaveShape(playerSave);
  const abilityPoints = playerSave.progression.abilityPoints;
  const available = Math.max(parseInteger(abilityPoints.unspent, 0), 0);
  const requestedAp = Math.max(parseInteger(params.inc_ap ?? params.ap ?? 0, 0), 0);
  const requestedBc = Math.max(parseInteger(params.inc_bc ?? params.bc ?? 0, 0), 0);
  const totalRequested = requestedAp + requestedBc;
  const totalAllocated = Math.min(totalRequested, available);
  const apAllocated = Math.min(requestedAp, totalAllocated);
  const bcAllocated = Math.min(requestedBc, totalAllocated - apAllocated);

  playerSave.resources.ap.max = Math.max(parseInteger(playerSave.resources.ap.max, 0) + apAllocated, 0);
  playerSave.resources.ap.current = Math.max(parseInteger(playerSave.resources.ap.current, 0) + apAllocated, 0);
  playerSave.resources.bc.max = Math.max(parseInteger(playerSave.resources.bc.max, 0) + bcAllocated, 0);
  playerSave.resources.bc.current = Math.max(parseInteger(playerSave.resources.bc.current, 0) + bcAllocated, 0);
  abilityPoints.unspent = Math.max(available - apAllocated - bcAllocated, 0);
  abilityPoints.apAllocated = Math.max(parseInteger(abilityPoints.apAllocated, 0) + apAllocated, 0);
  abilityPoints.bcAllocated = Math.max(parseInteger(abilityPoints.bcAllocated, 0) + bcAllocated, 0);

  return {
    requestedAp,
    requestedBc,
    apAllocated,
    bcAllocated,
    remainingAbilityPoints: abilityPoints.unspent,
  };
}

function applyExplorationExperience(playerSave, gainedExp) {
  const profile = playerSave.profile;
  const beforeLevel = Math.max(parseInteger(profile.level, 1), 1);
  const maxLevel = Math.max(parseInteger(profile.maxLevel, beforeLevel), beforeLevel);
  const beforeExp = Math.max(parseInteger(profile.exp, 0), 0);
  const gained = Math.max(parseInteger(gainedExp, 0), 0);
  const currentRow = getPlayerLevelRow(beforeLevel);
  const currentThreshold = currentRow?.nextExp || 0;
  const afterExp = beforeExp + gained;

  profile.exp = afterExp;
  if (beforeLevel >= maxLevel) {
    profile.percentage = 100;
    return {
      levelUp: false,
      isLimit: true,
      beforeLevel,
      afterLevel: beforeLevel,
      beforeExp,
      afterExp,
      nextExp: Math.max(parseInteger(profile.nextExp, 0), 0),
      abilityPointsGranted: 0,
    };
  }

  if (!currentThreshold || afterExp < currentThreshold) {
    profile.nextExp = currentThreshold || Math.max(parseInteger(profile.nextExp, 0), 0);
    profile.percentage = currentThreshold ? Math.floor((afterExp * 100) / currentThreshold) : Math.max(parseInteger(profile.percentage, 0), 0);
    return {
      levelUp: false,
      isLimit: false,
      beforeLevel,
      afterLevel: beforeLevel,
      beforeExp,
      afterExp,
      nextExp: profile.nextExp,
      abilityPointsGranted: 0,
    };
  }

  // ponytail: one exploration step is tiny; add a multi-level loop only after a full trusted table exists.
  const afterLevel = beforeLevel + 1;
  const carryExp = afterExp - currentThreshold;
  const nextRow = getPlayerLevelRow(afterLevel);
  const nextThreshold = nextRow?.nextExp || 0;
  const isLimit = afterLevel >= maxLevel;
  const abilityPoints = playerSave.progression.abilityPoints;
  const granted = getLevelUpPointGrant(afterLevel, playerSave);

  profile.level = afterLevel;
  profile.exp = carryExp;
  profile.nextExp = nextThreshold;
  profile.percentage = nextThreshold ? Math.floor((carryExp * 100) / nextThreshold) : 0;
  playerSave.resources.ap.current = Math.max(parseInteger(playerSave.resources.ap.max, playerSave.resources.ap.current), 0);
  playerSave.resources.bc.current = Math.max(parseInteger(playerSave.resources.bc.max, playerSave.resources.bc.current), 0);
  abilityPoints.unspent = Math.max(parseInteger(abilityPoints.unspent, 0) + granted, 0);
  abilityPoints.fromLevels = Math.max(parseInteger(abilityPoints.fromLevels, 0) + granted, 0);

  return {
    levelUp: true,
    isLimit,
    beforeLevel,
    afterLevel,
    beforeExp,
    afterExp: carryExp,
    nextExp: nextThreshold,
    abilityPointsGranted: granted,
  };
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
  const levelResult = applyExplorationExperience(playerSave, rewards.getExp);
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
  return levelResult;
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

function getAdminState(playerSavePath, runtimeConfigPath = getRuntimeConfigPath()) {
  const runtimeConfig = readRuntimeConfig(runtimeConfigPath);
  runtimeConfig.fairyEncounter = getFairyEncounterSettings(runtimeConfig);
  return createAdminState(readPlayerSave(playerSavePath), {
    savePath: getLogSafePath(playerSavePath),
    runtimeConfigPath: getLogSafePath(runtimeConfigPath),
    listenPorts: LISTEN_PORTS,
    worldName: worldList[0]?.name || "Local Dev World",
    routeCount: Object.keys(MAINMENU_ROUTE_STUBS).length,
    explorationRegionCount: EXPLORATION_REGIONS.length,
    adminWritePolicy: getAdminToken() ? "token" : "loopback-only",
  }, runtimeConfig);
}

function handleRequestFailure(req, res, error) {
  const disconnected = req.aborted === true
    || res.destroyed === true
    || error?.code === "ECONNRESET";
  logRequest("request_error", {
    method: req.method || "",
    path: String(req.url || "").split("?", 1)[0],
    code: error?.code || "",
    message: error?.message || String(error),
    disconnected,
  });
  if (disconnected || res.writableEnded) {
    return;
  }
  if (!res.headersSent) {
    sendText(res, 500, "internal server error\n");
    return;
  }
  res.end();
}

function createServer() {
  const playerSavePath = getPlayerSavePath();
  const runtimeConfigPath = getRuntimeConfigPath();
  const masterCardUpdate = getConfiguredMasterCardUpdate();
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
  logRequest("runtime_config", {
    path: getLogSafePath(runtimeConfigPath),
    source: fs.existsSync(runtimeConfigPath) ? "file" : "default",
  });
  logRequest("login_revision_config", {
    advertisedCardRevision: getAdvertisedCardRevision(),
    masterCardUpdateRecordCount: masterCardUpdate?.cards.length || 0,
    selectedMasterCardIds: masterCardUpdate?.selectedMasterCardIds || [],
  });
  const server = http.createServer((req, res) => {
    void (async () => {
    const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);

    if (req.method === "GET" && url.pathname === "/admin") {
      return sendRedirect(res, "/admin/");
    }

    if (req.method === "GET" && url.pathname === "/admin/") {
      return sendHtml(res, 200, ADMIN_UI_HTML);
    }

    if (req.method === "GET" && url.pathname === "/admin/api/state") {
      return sendJson(res, 200, getAdminState(playerSavePath, runtimeConfigPath));
    }

    if (req.method === "POST" && ["/admin/api/player", "/admin/api/fairy"].includes(url.pathname)) {
      if (!isAdminWriteAuthorized(req)) {
        logRequest("admin_write_denied", {
          remoteAddress: req.socket?.remoteAddress || "",
          policy: getAdminToken() ? "token" : "loopback-only",
        });
        return sendJson(res, 403, {
          ok: false,
          error: getAdminToken()
            ? "管理令牌不正确"
            : "未设置 KSSMA_ADMIN_TOKEN 时，只允许在服务端本机修改",
        });
      }
      if (!String(req.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
        return sendJson(res, 415, { ok: false, error: "Content-Type must be application/json" });
      }
      const body = await readBody(req);
      if (Buffer.byteLength(body, "utf8") > 65536) {
        return sendJson(res, 413, { ok: false, error: "admin update is too large" });
      }
      const update = parseMaybeJson(body);
      if (!update) {
        return sendJson(res, 400, { ok: false, error: "admin update must be valid JSON" });
      }
      try {
        const isFairyUpdate = url.pathname === "/admin/api/fairy";
        const targetPath = isFairyUpdate ? runtimeConfigPath : playerSavePath;
        const updated = isFairyUpdate
          ? applyAdminFairyUpdate(readRuntimeConfig(runtimeConfigPath), update)
          : applyAdminPlayerUpdate(readPlayerSave(playerSavePath), update);
        writeJsonFileAtomic(targetPath, updated);
        logRequest(isFairyUpdate ? "admin_fairy_update" : "admin_player_update", {
          fields: Object.keys(update),
          remoteAddress: req.socket?.remoteAddress || "",
          savePath: getLogSafePath(targetPath),
          saved: true,
        });
        return sendJson(res, 200, getAdminState(playerSavePath, runtimeConfigPath));
      } catch (error) {
        return sendJson(res, 400, { ok: false, error: error.message });
      }
    }

    if (req.method === "GET" && url.pathname === "/healthz") {
      return sendJson(res, 200, { ok: true, world: worldList[0], admin: "/admin/" });
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
        const loginXml = getLoginOkXml(playerSave);
        const encrypted = encryptAes128Ecb(loginXml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: getLoginXmlSource(loginXml),
          advertisedCardRevision: getAdvertisedCardRevision(),
          mainmenu: getMainmenuInformationForPlayer(playerSave),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/mainmenu/update") {
        // ponytail: one known-good mainbg is enough to un-black the town background; real rotation can wait for event data.
        const playerSave = readPlayerSave(playerSavePath);
        const xml = createMainmenuUpdateXml(playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal mainmenu update",
          mainmenu: getMainmenuInformationForPlayer(playerSave),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/mainmenu") {
        // ponytail: the exploration return path only needs the same mainmenu payload as update; split behavior later if evidence demands it.
        const playerSave = readPlayerSave(playerSavePath);
        const xml = createMainmenuUpdateXml(playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal mainmenu",
          mainmenu: getMainmenuInformationForPlayer(playerSave),
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
        // ponytail: ordinary and ordinary-fairy are the only accepted event branches here; rare fairy and battle results stay separate frontiers.
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
        const levelResult = updateExplorationSaveAfterMove(playerSave, floor, moves);
        const progress = getExplorationProgress(floor, movesDone);
        const rewards = getExplorationStepRewards(floor);
        const fairySettings = getFairyEncounterSettings();
        const fairyEncounter = !levelResult?.levelUp
          && progress < 100
          && shouldCreateFairyEncounter(playerSave, fairySettings)
          ? createFairyEncounter(playerSave, fairySettings, floor)
          : null;
        saveExplorationMoves(playerSave, playerSavePath, moves);
        const encrypted = encryptAes128Ecb(
          createExplorationExploreXml(progress, rewards, playerSave, levelResult, fairyEncounter),
          connectAppKey
        );
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
          levelUp: !!levelResult?.levelUp,
          isLimit: !!levelResult?.isLimit,
          beforeLevel: levelResult?.beforeLevel || parseInteger(playerSave.profile?.level, 1),
          level: parseInteger(playerSave.profile?.level, 1),
          profileExp: parseInteger(playerSave.profile?.exp, 0),
          nextExp: parseInteger(playerSave.profile?.nextExp, 0),
          abilityPoints: parseInteger(playerSave.progression?.abilityPoints?.unspent, 0),
          abilityPointsGranted: levelResult?.abilityPointsGranted || 0,
          fairyEncounter: !!fairyEncounter,
          fairyEncounterRate: fairySettings.ratePercent,
          fairySerialId: fairyEncounter?.serialId || "",
          fairyMasterBossId: fairyEncounter?.masterBossId || 0,
          fairyLevel: fairyEncounter?.level || 0,
          fairyMaxHp: fairyEncounter?.maxHp || 0,
          saved: true,
          savePath: getLogSafePath(playerSavePath),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/fairybattle") {
        const playerSave = readPlayerSave(playerSavePath);
        const activeFairy = playerSave.battle?.fairy?.active || null;
        const requestedSerialId = String(params.decrypted.serial_id || "");
        const requestedUserId = parseInteger(params.decrypted.user_id, 0);
        const encounterMatches = hasLiveFairyEncounter(playerSave)
          && requestedSerialId === String(activeFairy.serialId || "")
          && requestedUserId === parseInteger(activeFairy.discovererId, 0);
        if (!encounterMatches) {
          logRequest("connect_app_response", {
            path: url.pathname,
            status: 409,
            source: "fairy battle encounter mismatch",
            requestedSerialId,
            requestedUserId,
            activeSerialId: activeFairy?.serialId || "",
            activeDiscovererId: parseInteger(activeFairy?.discovererId, 0),
          });
          return sendText(res, 409, "fairy battle encounter mismatch\n");
        }
        const settlement = createFairyBattleSettlement(playerSave, activeFairy);
        const xml = createExplorationFairyBattleXml(settlement.playerSave, settlement);
        writeJsonFileAtomic(playerSavePath, settlement.playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "local fairy battle settlement",
          nextScene: 4100,
          battleScene: 4301,
          resultScene: 4420,
          explorationEventType: 18,
          requestedSerialId,
          fairyMasterBossId: parseInteger(activeFairy.masterBossId, 0),
          enemyBattleType: parseInteger(activeFairy.masterBossId, 0),
          enemyBossImageId: settlement.fairyVisualMasterCardId,
          fairyLevel: parseInteger(activeFairy.level, 0),
          fairyInitialHp: settlement.fairyInitialHp,
          fairyCurrentHp: settlement.fairyRemainingHp,
          fairyMaxHp: parseInteger(activeFairy.maxHp, 0),
          fairyAttackPower: settlement.fairyAttackPower,
          playerMaxHp: settlement.playerMaxHp,
          playerRemainingHp: settlement.playerRemainingHp,
          playerWon: settlement.playerWon,
          winner: settlement.winner,
          rounds: settlement.rounds,
          playerDamage: settlement.fairyInitialHp - settlement.fairyRemainingHp,
          fairyDamage: settlement.playerMaxHp - settlement.playerRemainingHp,
          goldBefore: settlement.beforeGold,
          goldReward: settlement.rewardGold,
          goldAfter: settlement.afterGold,
          expBefore: settlement.beforeExp,
          expReward: settlement.rewardExp,
          expAfter: settlement.afterExp,
          levelBefore: settlement.beforeLevel,
          levelAfter: settlement.afterLevel,
          saved: true,
          savePath: getLogSafePath(playerSavePath),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/town/lvup_status") {
        const playerSave = readPlayerSave(playerSavePath);
        const xml = createTownLvupStatusXml(playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal town lvup status",
          nextScene: 84100,
          level: parseInteger(playerSave.profile?.level, 1),
          profileExp: parseInteger(playerSave.profile?.exp, 0),
          nextExp: parseInteger(playerSave.profile?.nextExp, 0),
          apCurrent: parseInteger(playerSave.resources?.ap?.current, 0),
          apMax: parseInteger(playerSave.resources?.ap?.max, 0),
          bcCurrent: parseInteger(playerSave.resources?.bc?.current, 0),
          bcMax: parseInteger(playerSave.resources?.bc?.max, 0),
          abilityPoints: parseInteger(playerSave.progression?.abilityPoints?.unspent, 0),
          savePath: getLogSafePath(playerSavePath),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/town/pointsetting") {
        const playerSave = readPlayerSave(playerSavePath);
        const allocation = applyTownPointsetting(playerSave, params.decrypted);
        writeJsonFileAtomic(playerSavePath, playerSave);
        const xml = createTownPointsettingXml(playerSave);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal town pointsetting",
          nextScene: 2100,
          ...allocation,
          apCurrent: parseInteger(playerSave.resources?.ap?.current, 0),
          apMax: parseInteger(playerSave.resources?.ap?.max, 0),
          bcCurrent: parseInteger(playerSave.resources?.bc?.current, 0),
          bcMax: parseInteger(playerSave.resources?.bc?.max, 0),
          abilityPoints: parseInteger(playerSave.progression?.abilityPoints?.unspent, 0),
          saved: true,
          savePath: getLogSafePath(playerSavePath),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/gacha/buy") {
        const settlement = applyGachaBuySettlement(readPlayerSave(playerSavePath), params.decrypted);
        writeJsonFileAtomic(playerSavePath, settlement.playerSave);
        const xml = createGachaBuyXml(settlement.playerSave, settlement.drawCard, settlement.productId);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "gacha buy settlement",
          command: "gacha_buy",
          nextScene: 9200,
          productId: settlement.productId,
          bulk: settlement.bulk,
          friendshipBefore: settlement.friendshipBefore,
          friendshipCost: settlement.friendshipCost,
          friendshipAfter: settlement.friendshipAfter,
          mcBefore: settlement.mcBefore,
          mcCost: settlement.mcCost,
          mcAfter: settlement.mcAfter,
          drawnSerialId: settlement.drawCard ? settlement.drawCard.serialId : 0,
          drawnMasterCardId: settlement.drawCard ? settlement.drawCard.masterCardId : 0,
          ownerCardCount: settlement.ownerCardCount,
          cardsDrawn: settlement.cardsDrawn,
          saved: true,
          savePath: getLogSafePath(playerSavePath),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      const routePlayerSave = req.method === "POST" ? readPlayerSave(playerSavePath) : null;
      const mainmenuRouteXml = routePlayerSave ? createMainmenuRouteXml(url.pathname, routePlayerSave) : null;
      if (mainmenuRouteXml) {
        const route = MAINMENU_ROUTE_STUBS[url.pathname];
        const ownedCards = Array.isArray(routePlayerSave.cards?.instances) ? routePlayerSave.cards.instances : [];
        const gachaPage = route.command === "gacha" ? getGachaSelectPage().pageKey : undefined;
        const encrypted = encryptAes128Ecb(mainmenuRouteXml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: route.sample ? `assets/bundle/${route.sample}` : "mainmenu route skeleton",
          command: route.command,
          nextScene: route.nextScene,
          ...(gachaPage ? { gachaPage } : {}),
          ownerCardCount: ownedCards.length,
          ownerCardSerialIds: ownedCards.map((card) => parseInteger(card?.serialId ?? card?.serial_id, 0)).filter((id) => id > 0),
          ownerCardMasterCardIds: ownedCards.map((card) => parseInteger(card?.masterCardId ?? card?.master_card_id, 0)).filter((id) => id > 0),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === MASTER_CARD_UPDATE_ROUTE) {
        if (!masterCardUpdate) {
          logRequest("connect_app_response_miss", {
            path: url.pathname,
            source: MASTERDATA_SAMPLES[url.pathname]?.relativePath || "database/master_card",
          });
          return sendText(res, 500, "masterdata sample missing\n");
        }
        const encrypted = encryptAes128Ecb(masterCardUpdate.xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "recovered master-card XML",
          sourceSha256: masterCardUpdate.sourceSha256,
          sourceRecordCount: masterCardUpdate.sourceRecordCount,
          recordCount: masterCardUpdate.cards.length,
          selectedMasterCardIds: masterCardUpdate.selectedMasterCardIds,
          updateType: masterCardUpdate.updateType,
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

      logRequest("connect_app_response", {
        path: url.pathname,
        status: 501,
        source: "connect/app not implemented yet",
      });
      return sendText(res, 501, "connect/app not implemented yet\n");
    }

    const body = req.method === "POST" ? await readBody(req) : "";
    logRequest("miss", getRequestDetails(req, url, body));
      return sendText(res, 404, "not found\n");
    })().catch((error) => handleRequestFailure(req, res, error));
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
  ADMIN_UI_HTML,
  applyAdminFairyUpdate,
  applyAdminPlayerUpdate,
  createFairyBattleSettlement,
  createFairyEncounter,
  createAdminState,
  createServer,
  decryptAddUserPassword,
  decryptAes128EcbBase64,
  encryptAes128Ecb,
  encryptAes128EcbBuffer,
  createExplorationAreaXml,
  createExplorationApFailXml,
  createExplorationExploreXml,
  createExplorationFairyBattleXml,
  createExplorationFloorXml,
  createExplorationGetFloorXml,
  createExplorationLockedXml,
  createGachaBuyXml,
  createGachaSelectSkeletonXml,
  createMasterCardUpdateXml,
  createMenuCardCollectionSkeletonXml,
  createMenuFairySelectSkeletonXml,
  createMenuFriendListSkeletonXml,
  createMenuHavePartsSkeletonXml,
  createMenuRankingSkeletonXml,
  createRoundtableEditXml,
  createMainmenuUpdateXml,
  createMainmenuRouteXml,
  createLoginMainmenuXml,
  createTownLvupStatusXml,
  createTownPointsettingXml,
  getMainmenuInformationForPlayer,
  getAdvertisedCardRevision,
  getLoginOkXml,
  getLoginXmlSource,
  getFairyEncounterSettings,
  getConfiguredMasterCardUpdate,
  hasLiveFairyEncounter,
  parseConnectAppBody,
  parsePortList,
  CHECK_INSPECTION_OK_XML,
  EXPLORATION_AREA_XML,
  EXPLORATION_FLOOR_XML,
  EXPLORATION_GET_FLOOR_XML,
  EXPLORATION_EXPLORE_XML,
  TOWN_LVUP_STATUS_XML,
  TOWN_POINTSETTING_XML,
  EXPLORATION_REGIONS,
  EXPLORATION_FLOORS,
  GAME_EXPLORATION_DATA,
  GAME_MAINMENU_DATA,
  GAME_PLAYER_LEVEL_EXP_TABLE,
  DEFAULT_PLAYER_SAVE,
  DEFAULT_RUNTIME_CONFIG,
  SERVER_WORLD_DATA,
  MAINMENU_ROUTE_STUBS,
  MAINMENU_UPDATE_XML,
  LOGIN_TUTORIAL_XML,
  LOGIN_OK_XML,
  LOGIN_MAINMENU_XML,
  MASTERDATA_ROUTE_FILES,
  MASTERDATA_SAMPLES,
  MASTER_CARD_UPDATE,
  MASTER_CARD_UPDATE_ROUTE,
  MASTER_CARD_SOURCE_SHA256,
  parseSerializedMasterCards,
  WEB_SCENETO_LOCATION,
  WEB_STUB_HTML,
  readContentFile,
  readSampleSaveFile,
};
