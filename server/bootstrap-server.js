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
const MASTERDATA_ROUTE_FILES = {
  "/connect/app/masterdata/card/update": "database/master_card",
  "/connect/app/masterdata/card_category/update": "database/master_cardcategory",
  "/connect/app/masterdata/boss/update": "database/master_boss",
  "/connect/app/masterdata/item/update": "database/master_item",
  "/connect/app/masterdata/scol/update": "database/master_scol",
  "/connect/app/masterdata/combo/update": "database/master_combo",
};

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

const worldList = [
  {
    name: "Local Dev World",
    member_count: 1,
    world_status: 1,
    url_root: WORLD_URL,
    url_top: TOP_URL,
    world_id: 1,
    url_pr: BILLING_URL,
    billing_flag: 0,
  },
];

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
const EXPLORATION_REGION_BACKGROUNDS = [
  "adv_bg14",
  "adv_bg11",
  "adv_bg12",
  "adv_bg15",
  "adv_bg37",
  "adv_bg42",
];
const EXPLORATION_REGION_POSITIONS = [
  { x: 150, y: 510 },
  { x: 310, y: 420 },
  { x: 480, y: 355 },
  { x: 635, y: 285 },
  { x: 780, y: 420 },
  { x: 885, y: 220 },
];
const EXPLORATION_FOCUS_DATA_PATH = path.join(
  __dirname,
  "..",
  "work",
  "external-data",
  "normalized",
  "exploration-focus.json"
);
const EXPLORATION_FC2_DATA_PATH = path.join(
  __dirname,
  "..",
  "work",
  "external-data",
  "normalized",
  "fc2-exploration-regions.json"
);

function readJsonFile(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function getFc2AreaByTitleAndNo(fc2Data, title, areaNo) {
  const region = fc2Data?.regions?.find((candidate) => candidate.title === title);
  return region?.areas?.find((area) => area.area === areaNo) || null;
}

function inferRequiredMoves(regionIndex, areaNo, fc2Area) {
  if (Number.isFinite(fc2Area?.required_moves)) {
    return fc2Area.required_moves;
  }
  // ponytail: later wiki rows have unknown clear counts; replace with master/client values when recovered.
  return 10 + regionIndex * 5 + areaNo;
}

function createFallbackExplorationRegions() {
  const rows = [
    { areaNo: 1, cost: 1, requiredMoves: 10, goldMin: 16, goldMax: 20 },
    { areaNo: 2, cost: 2, requiredMoves: 11, goldMin: 30, goldMax: 40 },
    { areaNo: 3, cost: 2, requiredMoves: 12, goldMin: 30, goldMax: 40 },
    { areaNo: 4, cost: 2, requiredMoves: 15, goldMin: 30, goldMax: 40 },
    { areaNo: 5, cost: 3, requiredMoves: 16, goldMin: 50, goldMax: 60 },
    { areaNo: 6, cost: 3, requiredMoves: 20, goldMin: 50, goldMax: 60 },
  ];
  return [
    {
      regionId: 0,
      name: "人魚の断崖",
      bg: EXPLORATION_REGION_BACKGROUNDS[0],
      position: EXPLORATION_REGION_POSITIONS[0],
      floors: rows.map((row, index) => ({
        ...row,
        regionId: 0,
        regionName: "人魚の断崖",
        regionBg: EXPLORATION_REGION_BACKGROUNDS[0],
        routeAreaId: index,
        floorId: index + 2,
        floorIndex: index,
        goldMin: row.goldMin,
        goldMax: row.goldMax,
      })),
    },
  ];
}

function loadExplorationRegions() {
  const focusData = readJsonFile(EXPLORATION_FOCUS_DATA_PATH);
  const fc2Data = readJsonFile(EXPLORATION_FC2_DATA_PATH);
  const regions = focusData?.structured_regions?.slice(0, 6);
  if (!regions?.length) {
    return createFallbackExplorationRegions();
  }

  let nextRouteAreaId = 0;
  let nextFloorId = 2;
  return regions.map((region, regionIndex) => {
    const regionId = region.region_index - 1;
    const bg = EXPLORATION_REGION_BACKGROUNDS[regionIndex] || EXPLORATION_REGION_BACKGROUNDS[0];
    const position = EXPLORATION_REGION_POSITIONS[regionIndex] || { x: 0, y: 0 };
    return {
      regionId,
      name: region.name,
      bg,
      position,
      floors: region.floors.map((area, floorIndex) => {
        const cost = parseInteger(area.ap_cost, 1);
        const fc2Area = getFc2AreaByTitleAndNo(fc2Data, region.name, area.floor);
        const floor = {
          regionId,
          regionName: region.name,
          regionBg: bg,
          routeAreaId: nextRouteAreaId,
          floorId: nextFloorId,
          floorIndex,
          areaNo: area.floor,
          cost,
          requiredMoves: inferRequiredMoves(regionIndex, area.floor, fc2Area),
          goldMin: Number.isFinite(fc2Area?.gold_min_per_move) ? fc2Area.gold_min_per_move : cost * 16,
          goldMax: Number.isFinite(fc2Area?.gold_max_per_move) ? fc2Area.gold_max_per_move : cost * 20,
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

function getExplorationFloor(areaId = 0, floorId = 2) {
  const requestedFloorId = parseInteger(floorId, 2);
  const byFloorId = EXPLORATION_FLOORS.find((floor) => floor.floorId === requestedFloorId);
  if (byFloorId) {
    return byFloorId;
  }

  const requestedRouteAreaId = parseInteger(areaId, 0);
  const byRouteAreaId = EXPLORATION_FLOORS.find((floor) => floor.routeAreaId === requestedRouteAreaId);
  if (byRouteAreaId) {
    return byRouteAreaId;
  }

  // ponytail: unknown IDs fall back to the first local row; replace with masterdata mapping when recovered.
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

function renderFloorInfoXml(floor, progress, indent = "      ") {
  return [
    `${indent}<floor_info>`,
    `${indent}  <id>${floor.floorId}</id>`,
    `${indent}  <type>0</type>`,
    `${indent}  <unlock>1</unlock>`,
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

function createExplorationAreaXml(movesByFloor = new Map()) {
  const areaRows = EXPLORATION_REGIONS.flatMap((region) => [
    "        <area_info>",
    `          <id>${region.regionId}</id>`,
    `          <name>${region.name}</name>`,
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

function createExplorationFloorXml(areaId = 0, movesByFloor = new Map()) {
  const region = getExplorationRegion(areaId);
  const floorRows = region.floors.flatMap((floor) => {
    const floorKey = getExplorationFloorStateKey(floor);
    const movesDone = movesByFloor instanceof Map ? movesByFloor.get(floorKey) || 0 : 0;
    return renderFloorInfoXml(floor, getExplorationProgress(floor, movesDone), "        ");
  });

  // ponytail: v1 unlocks all normal rows from the cached wiki table; add lock gating when progression is save-backed.
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
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
    ...renderFloorInfoXml(floor, 0, "        "),
    "      </next_floor>",
  ];
}

function createExplorationGetFloorXml(areaId = 0, floorId = 2, movesDone = 0) {
  const currentFloor = getExplorationFloor(areaId, floorId);
  const nextFloor = getNextExplorationFloor(currentFloor);
  const progress = getExplorationProgress(currentFloor, movesDone);

  return [
  '<?xml version="1.0" encoding="UTF-8"?>',
  "<response>",
  "  <header>",
  "    <error><code>0</code></error>",
  "    <session_id>local-exploration</session_id>",
  "    <next_scene>6200</next_scene>",
  "  </header>",
  "  <body>",
  "    <get_floor>",
  `      <area_id>${currentFloor.routeAreaId}</area_id>`,
  `      <bg>${currentFloor.regionBg}</bg>`,
  "      <bgm>sarch1</bgm>",
  `      <area_name>${currentFloor.regionName}</area_name>`,
  "      <next_exp>0</next_exp>",
  ...renderNextFloorXml(nextFloor),
  ...renderFloorInfoXml(currentFloor, progress),
  "    </get_floor>",
  "  </body>",
  "</response>",
].join("");
}
const EXPLORATION_GET_FLOOR_XML = createExplorationGetFloorXml();
function createExplorationExploreXml(progress = 10, rewards = getExplorationStepRewards(EXPLORATION_FLOORS[0])) {
  const safeProgress = Math.min(Math.max(parseInteger(progress, 10), 0), 100);
  const gold = Math.max(parseInteger(rewards.gold, 0), 0);
  const getExp = Math.max(parseInteger(rewards.getExp, 0), 0);

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<response>",
    "  <header>",
    "    <error><code>0</code></error>",
    "    <session_id>local-exploration</session_id>",
    "    <next_scene>6200</next_scene>",
    "  </header>",
    "  <body>",
    "    <explore>",
    `      <progress>${safeProgress}</progress>`,
    "      <event_type>0</event_type>",
    `      <gold>${gold}</gold>`,
    `      <get_exp>${getExp}</get_exp>`,
    "      <next_exp>0</next_exp>",
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
// ponytail: getCurrentMainBg only appends the day/night suffix; the saved base name already includes mainbg_.
const MAINMENU_BGFILE = "mainbg_an";
const MAINMENU_FIELDS = [
  "    <mainmenu>",
  `      <current_bgfile>${MAINMENU_BGFILE}</current_bgfile>`,
  `      <previous_bgfile>${MAINMENU_BGFILE}</previous_bgfile>`,
  "      <infomation>",
  "        <fairy_pose>2</fairy_pose>",
  "        <fairy_face>5</fairy_face>",
  "        <message>",
  "          <text>Welcome back.</text>",
  "          <color>0xFFFFFF</color>",
  "          <size>20</size>",
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
  return getExplorationFloorKeyFromIds(params.decrypted.area_id || "0", params.decrypted.floor_id || "2");
}

function createServer() {
  // ponytail: in-memory per-process progress is enough for one reconstruction run; replace with a save-backed model when persistence matters.
  const explorationMovesByFloor = new Map();
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
        const loginXml = getLoginOkXml();
        const encrypted = encryptAes128Ecb(loginXml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: getLoginXmlSource(loginXml),
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/mainmenu/update") {
        // ponytail: one known-good mainbg is enough to un-black the town background; real rotation can wait for event data.
        const encrypted = encryptAes128Ecb(MAINMENU_UPDATE_XML, connectAppKey);
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
        const encrypted = encryptAes128Ecb(MAINMENU_UPDATE_XML, connectAppKey);
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
        // ponytail: process-local area progress is enough for one reconstruction run; persist after hierarchy is stable.
        const xml = createExplorationAreaXml(explorationMovesByFloor);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "wiki exploration area list",
          areaCount: EXPLORATION_REGIONS.length,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/floor") {
        // ponytail: floor-list progress is process-local; save-backed persistence comes after return/list progress is accepted.
        const xml = createExplorationFloorXml(params.decrypted.area_id, explorationMovesByFloor);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "wiki exploration floor list",
          regionId: parseInteger(params.decrypted.area_id, 0),
          floorCount: getExplorationRegion(params.decrypted.area_id).floors.length,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/get_floor") {
        // ponytail: one no-branch floor entry is enough to test exploration_main; real event routing comes after the next route proves it.
        const floorKey = getExplorationFloorKey(params);
        const floor = getExplorationFloor(params.decrypted.area_id, params.decrypted.floor_id);
        const movesDone = explorationMovesByFloor.get(floorKey) || 0;
        const xml = createExplorationGetFloorXml(params.decrypted.area_id, params.decrypted.floor_id, movesDone);
        const encrypted = encryptAes128Ecb(xml, connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal exploration get_floor",
          floorKey,
          regionId: floor.regionId,
          floorId: floor.floorId,
          bg: floor.regionBg,
          movesDone,
        });
        sendBinary(res, 200, encrypted);
        return;
      }

      if (req.method === "POST" && url.pathname === "/connect/app/exploration/explore") {
        // ponytail: keep this as the no-branch walking candidate; battle/fairy/reward routes stay separate frontiers.
        const floor = getExplorationFloor(params.decrypted.area_id, params.decrypted.floor_id);
        const floorKey = getExplorationFloorKey(params);
        const movesDone = clampMoveCount((explorationMovesByFloor.get(floorKey) || 0) + 1, floor);
        explorationMovesByFloor.set(floorKey, movesDone);
        const progress = getExplorationProgress(floor, movesDone);
        const rewards = getExplorationStepRewards(floor);
        const encrypted = encryptAes128Ecb(createExplorationExploreXml(progress, rewards), connectAppKey);
        logRequest("connect_app_response", {
          path: url.pathname,
          mode: "aes-128-ecb",
          key: connectAppKey,
          bytes: encrypted.length,
          source: "minimal exploration explore",
          floorKey,
          movesDone,
          progress,
          gold: rewards.gold,
          getExp: rewards.getExp,
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
  createExplorationExploreXml,
  createExplorationFloorXml,
  createExplorationGetFloorXml,
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
