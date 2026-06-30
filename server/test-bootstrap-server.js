const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const {
  createServer,
  ADD_USER_KEY,
  CHECK_INSPECTION_OK_XML,
  decryptAes128EcbBase64,
  encryptAes128Ecb,
  encryptAes128EcbBuffer,
  createExplorationAreaXml,
  createExplorationApFailXml,
  createExplorationExploreXml,
  createExplorationFloorXml,
  createExplorationGetFloorXml,
  createExplorationLockedXml,
  createGachaSelectSkeletonXml,
  createLoginMainmenuXml,
  createMainmenuUpdateXml,
  createMainmenuRouteXml,
  createTownLvupStatusXml,
  createTownPointsettingXml,
  EXPLORATION_AREA_XML,
  EXPLORATION_EXPLORE_XML,
  EXPLORATION_FLOOR_XML,
  EXPLORATION_GET_FLOOR_XML,
  TOWN_LVUP_STATUS_XML,
  TOWN_POINTSETTING_XML,
  EXPLORATION_REGIONS,
  EXPLORATION_FLOORS,
  GAME_EXPLORATION_DATA,
  GAME_MAINMENU_DATA,
  GAME_PLAYER_LEVEL_EXP_TABLE,
  DEFAULT_PLAYER_SAVE,
  SERVER_WORLD_DATA,
  MAINMENU_ROUTE_STUBS,
  MAINMENU_UPDATE_XML,
  getMainmenuInformationForPlayer,
  getLoginOkXml,
  getLoginXmlSource,
  LOGIN_OK_XML,
  LOGIN_MAINMENU_XML,
  LOGIN_TUTORIAL_XML,
  MASTERDATA_SAMPLES,
  parseConnectAppBody,
  parsePortList,
  WEB_SCENETO_LOCATION,
  WEB_STUB_HTML,
  readSampleSaveFile,
} = require("./bootstrap-server");

const CONNECT_APP_KEY = "rBwj1MIAivVN222b";
const DATA_META_FIELD_NAMES = new Set([
  "candidateNextExp",
  "caveat",
  "confidence",
  "evidence",
  "fc2MaxStatPoints",
  "fc2NextExp",
  "fc2NextExpUncertain",
  "fetchedVia",
  "mobileNextExp",
  "note",
  "notes",
  "provenance",
  "scope",
  "source",
  "sourceRank",
  "sourceRankMeaning",
  "sources",
  "url",
  "versionNote",
  "weakCandidateEvidence",
]);

function post(port, path, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path,
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Content-Length": Buffer.byteLength(body),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const buffer = Buffer.concat(chunks);
          resolve({
            statusCode: res.statusCode,
            body: buffer.toString("utf8"),
            buffer,
          });
        });
      }
    );
    req.on("error", reject);
    req.end(body);
  });
}

function walkJsonData(value, visit, pathParts = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => walkJsonData(item, visit, pathParts.concat(`[${index}]`)));
    return;
  }
  if (!value || typeof value !== "object") {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    visit(key, pathParts.concat(key));
    walkJsonData(child, visit, pathParts.concat(key));
  }
}

function assertNoDataMetaFields(filePath) {
  const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const offenders = [];
  walkJsonData(data, (key, pathParts) => {
    if (DATA_META_FIELD_NAMES.has(key)) {
      offenders.push(pathParts.join("."));
    }
  });
  assert.deepEqual(offenders, [], `${filePath} contains documentation/provenance fields`);
}

function get(port, path) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path,
        method: "GET",
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const buffer = Buffer.concat(chunks);
          resolve({
            statusCode: res.statusCode,
            headers: res.headers,
            body: buffer.toString("utf8"),
            buffer,
          });
        });
      }
    );
    req.on("error", reject);
    req.end();
  });
}

function encryptPassword(value) {
  const cipher = crypto.createCipheriv("aes-128-ecb", ADD_USER_KEY, null);
  cipher.setAutoPadding(true);
  return Buffer.concat([cipher.update(value, "utf8"), cipher.final()]).toString("base64");
}

function encryptedParam(value) {
  return encodeURIComponent(encryptAes128Ecb(String(value), CONNECT_APP_KEY).toString("base64"));
}

function connectAppBody(values) {
  return Object.entries(values)
    .map(([key, value]) => `${key}=${encryptedParam(value)}`)
    .join("&");
}

function assertPlayerHeader(xml, expected) {
  if (expected.leaderSerialId !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<leader_serial_id>${expected.leaderSerialId}</leader_serial_id>`));
  }
  if (expected.ownerCardSerialId !== undefined) {
    assert.match(xml, new RegExp(`<owner_card_list>[\\s\\S]*<serial_id>${expected.ownerCardSerialId}</serial_id>`));
  }
  if (expected.ownerCardMasterCardId !== undefined) {
    assert.match(xml, new RegExp(`<owner_card_list>[\\s\\S]*<master_card_id>${expected.ownerCardMasterCardId}</master_card_id>`));
  }
  if (expected.apCurrent !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<ap>[\\s\\S]*<current>${expected.apCurrent}</current>`));
  }
  if (expected.apMax !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<ap>[\\s\\S]*<max>${expected.apMax}</max>`));
  }
  if (expected.bcCurrent !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<bc>[\\s\\S]*<current>${expected.bcCurrent}</current>`));
  }
  if (expected.bcMax !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<bc>[\\s\\S]*<max>${expected.bcMax}</max>`));
  }
  if (expected.gold !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<gold>${expected.gold}</gold>`));
  }
  if (expected.rank !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<rank>${expected.rank}</rank>`));
  }
  if (expected.percentage !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<percentage>${expected.percentage}</percentage>`));
  }
  if (expected.maxCardNum !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<max_card_num>${expected.maxCardNum}</max_card_num>`));
  }
  if (expected.friendshipPoint !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<friendship_point>${expected.friendshipPoint}</friendship_point>`));
  }
  if (expected.countryId !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<country_id>${expected.countryId}</country_id>`));
  }
  if (expected.nextExp !== undefined) {
    assert.match(xml, new RegExp(`<next_exp>${expected.nextExp}</next_exp>`));
  }
  if (expected.freeApBcPoint !== undefined) {
    assert.match(xml, new RegExp(`<your_data>[\\s\\S]*<free_ap_bc_point>${expected.freeApBcPoint}</free_ap_bc_point>`));
  }
}

function assertMainmenuInformation(xml, expected) {
  assert.match(xml, /<mainmenu>/);
  assert.match(xml, /<current_bgfile>mainbg_an<\/current_bgfile>/);
  assert.match(xml, /<previous_bgfile>mainbg_an<\/previous_bgfile>/);
  assert.match(xml, /<infomation>/);
  assert.match(xml, new RegExp(`<fairy_pose>${expected.fairyPose}</fairy_pose>`));
  assert.match(xml, new RegExp(`<fairy_face>${expected.fairyFace}</fairy_face>`));
  assert.match(xml, /<text>Welcome back\.<\/text>/);
  assert.match(xml, /<color>0xFFFFFF<\/color>/);
  assert.match(xml, /<size>20<\/size>/);
  assert.doesNotMatch(xml, /<currentBgfile>/);
  assert.doesNotMatch(xml, /<imagefile>/);
  assert.doesNotMatch(xml, /<focus>/);
  assert.doesNotMatch(xml, /<link>/);
  assert.doesNotMatch(xml, /<banner>/);
  assert.doesNotMatch(xml, /<rewards>/);
  assert.doesNotMatch(xml, /<event_type>/);
}

function saveWithFaction(faction) {
  const save = JSON.parse(JSON.stringify(DEFAULT_PLAYER_SAVE));
  save.profile.faction = faction;
  delete save.profile.countryId;
  return save;
}

async function main() {
  const previousPlayerSavePath = process.env.KSSMA_PLAYER_SAVE_PATH;
  const previousLoginResponse = process.env.LOGIN_RESPONSE;
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "kssma-player-save-"));
  const tempPlayerSavePath = path.join(tempDir, "player-save.json");

  for (const relativePath of [
    "server/data/game/exploration.json",
    "server/data/game/mainmenu.json",
    "server/data/game/player-level-exp-table.json",
    "server/data/player/default-save.json",
    "server/data/server/masterdata-routes.json",
    "server/data/server/worlds.json",
  ]) {
    assertNoDataMetaFields(path.join(__dirname, "..", relativePath));
  }

  assert.deepEqual(parsePortList("", 50005), [50005]);
  assert.deepEqual(parsePortList("50005,10001 50005", 50005), [50005, 10001]);
  assert.equal(
    encryptAes128Ecb(CHECK_INSPECTION_OK_XML, "A1dPUcrvur2CRQyl").length % 16,
    0
  );
  assert.equal(decryptAes128EcbBase64("ySboruTbjYskjVUIf7U3Ew==", "rBwj1MIAivVN222b"), "13800138000");
  assert.equal(decryptAes128EcbBase64("8qAl04QoOI2mCN0/MwrBKg==", "rBwj1MIAivVN222b"), "testpass1");
  assert.equal(SERVER_WORLD_DATA.worlds[0].name, "Local Dev World");
  assert.equal(GAME_MAINMENU_DATA.information.message.text, "Welcome back.");
  assert.equal(GAME_EXPLORATION_DATA.defaultBgm, "sarch1");
  assert.equal(GAME_EXPLORATION_DATA.regions.length, 6);
  assert.equal(DEFAULT_PLAYER_SAVE.schemaVersion, 2);
  assert.equal(DEFAULT_PLAYER_SAVE.resources.ap.current, 25);
  assert.equal(DEFAULT_PLAYER_SAVE.resources.ap.max, 25);
  assert.equal(DEFAULT_PLAYER_SAVE.resources.ap.regenSeconds, 180);
  assert.equal(DEFAULT_PLAYER_SAVE.resources.bc.current, 25);
  assert.equal(DEFAULT_PLAYER_SAVE.resources.bc.max, 25);
  assert.equal(DEFAULT_PLAYER_SAVE.resources.bc.regenSeconds, 60);
  assert.equal(DEFAULT_PLAYER_SAVE.profile.leaderSerialId, 1);
  assert.equal(DEFAULT_PLAYER_SAVE.cards.count, 1);
  assert.equal(DEFAULT_PLAYER_SAVE.cards.max, 350);
  assert.equal(DEFAULT_PLAYER_SAVE.cards.instances[0].serialId, 1);
  assert.equal(DEFAULT_PLAYER_SAVE.cards.instances[0].masterCardId, 22);
  assert.deepEqual(DEFAULT_PLAYER_SAVE.cards.decks[0].cardInstanceIds, [1]);
  assert.equal(DEFAULT_PLAYER_SAVE.friends.count, 0);
  assert.equal(DEFAULT_PLAYER_SAVE.friends.max, 30);
  assert.equal(DEFAULT_PLAYER_SAVE.gacha.friendshipCost, 200);
  assert.equal(DEFAULT_PLAYER_SAVE.currencies.friendshipPoint, 0);
  assert.equal(DEFAULT_PLAYER_SAVE.exploration.regions["0"].unlocked, true);
  assert.equal(DEFAULT_PLAYER_SAVE.exploration.regions["1"].unlocked, false);
  assert.deepEqual(DEFAULT_PLAYER_SAVE.exploration.movesByFloor, {});
  const level17Row = GAME_PLAYER_LEVEL_EXP_TABLE.levels.find((row) => row.level === 17);
  const level18Row = GAME_PLAYER_LEVEL_EXP_TABLE.levels.find((row) => row.level === 18);
  const level10Row = GAME_PLAYER_LEVEL_EXP_TABLE.levels.find((row) => row.level === 10);
  assert.equal(level17Row.nextExp, 2000);
  assert.equal(level18Row.nextExp, 2100);
  assert.equal(level10Row.nextExp, 1300);
  for (const row of GAME_PLAYER_LEVEL_EXP_TABLE.levels) {
    for (const key of Object.keys(row)) {
      assert.ok(["friendMax", "level", "nextExp", "statPointsOnLevelUp"].includes(key), `unexpected level table key: ${key}`);
    }
  }
  assert.match(EXPLORATION_AREA_XML, /<next_scene>6100<\/next_scene>/);
  assert.match(EXPLORATION_AREA_XML, /<exploration_area>/);
  assert.match(EXPLORATION_AREA_XML, /<your_data>[\s\S]*<ap>[\s\S]*<current>25<\/current>/);
  assert.match(EXPLORATION_AREA_XML, /<prog_area>0<\/prog_area>/);
  assert.equal([...EXPLORATION_AREA_XML.matchAll(/<area_info>/g)].length, 1);
  assert.equal(EXPLORATION_REGIONS.length, 6);
  assert.equal(EXPLORATION_FLOORS.length, 70);
  assert.deepEqual(EXPLORATION_REGIONS.map((region) => region.floors.length), [6, 9, 10, 10, 15, 20]);
  assert.match(EXPLORATION_AREA_XML, /<name>人魚の断崖<\/name>/);
  for (const name of ["燐光の湖", "錯乱の平原", "叡智の草原", "猛獣の砂丘", "祝福を授ける山"]) {
    assert.doesNotMatch(EXPLORATION_AREA_XML, new RegExp(`<name>${name}</name>`));
  }
  assert.doesNotMatch(EXPLORATION_AREA_XML, /Local Area/);
  assert.match(EXPLORATION_FLOOR_XML, /<exploration_floor>/);
  assert.match(EXPLORATION_FLOOR_XML, /<your_data>[\s\S]*<ap>[\s\S]*<current>25<\/current>/);
  assert.match(EXPLORATION_FLOOR_XML, /<id>2<\/id>/);
  assert.doesNotMatch(EXPLORATION_FLOOR_XML, /<id>7<\/id>/);
  assert.match(EXPLORATION_FLOOR_XML, /<unlock>1<\/unlock>/);
  assert.match(EXPLORATION_FLOOR_XML, /<boss_down>0<\/boss_down>/);
  assert.equal([...EXPLORATION_FLOOR_XML.matchAll(/<floor_info>/g)].length, 1);
  assert.equal([...createExplorationFloorXml(1).matchAll(/<floor_info>/g)].length, 0);
  const region1UnlockedSave = JSON.parse(JSON.stringify(DEFAULT_PLAYER_SAVE));
  region1UnlockedSave.exploration.regions["1"].unlocked = true;
  assert.equal([...createExplorationAreaXml(new Map(), region1UnlockedSave).matchAll(/<area_info>/g)].length, 2);
  assert.match(createExplorationAreaXml(new Map(), region1UnlockedSave), /<name>燐光の湖<\/name>/);
  assert.equal([...createExplorationFloorXml(1, new Map(), region1UnlockedSave).matchAll(/<floor_info>/g)].length, 1);
  assert.match(createExplorationFloorXml(1, new Map(), region1UnlockedSave), /<id>8<\/id>/);
  assert.match(createExplorationFloorXml(0, new Map([["0:2", 2]])), /<id>2<\/id>[\s\S]*?<progress>20<\/progress>/);
  assert.doesNotMatch(createExplorationFloorXml(0, new Map([["0:2", 2]])), /<id>3<\/id>/);
  assert.match(createExplorationFloorXml(0, new Map([["0:2", 10]])), /<id>3<\/id>[\s\S]*?<unlock>1<\/unlock>/);
  assert.match(createExplorationFloorXml(0, new Map([["1:3", 1]])), /<id>3<\/id>[\s\S]*?<progress>9<\/progress>/);
  assert.match(createExplorationFloorXml(0, new Map([["1:3", 1]])), /<id>3<\/id>[\s\S]*?<cost>2<\/cost>/);
  assert.match(createExplorationAreaXml(new Map([["0:2", 2]])), /<name>人魚の断崖<\/name>[\s\S]*?<prog_area>2<\/prog_area>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<next_scene>6200<\/next_scene>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<get_floor>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<area_id>0<\/area_id>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<bg>adv_bg14<\/bg>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<bgm>sarch1<\/bgm>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<area_name>人魚の断崖<\/area_name>/);
  for (const [name, bg] of [
    ["人魚の断崖", "adv_bg14"],
    ["燐光の湖", "adv_bg11"],
    ["錯乱の平原", "adv_bg12"],
    ["叡智の草原", "adv_bg15"],
    ["猛獣の砂丘", "adv_bg37"],
    ["祝福を授ける山", "adv_bg42"],
  ]) {
    const region = EXPLORATION_REGIONS.find((candidate) => candidate.name === name);
    assert.equal(region?.bg, bg);
  }
  assert.match(EXPLORATION_GET_FLOOR_XML, /<next_floor>\s*<area_id>1<\/area_id>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<next_floor>[\s\S]*<floor_info>\s*<id>2<\/id>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<floor_info>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<\/next_floor>\s*<floor_info>\s*<id>1<\/id>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<\/next_floor>[\s\S]*<progress>0<\/progress>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<\/next_floor>[\s\S]*<cost>1<\/cost>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<get_floor>\s*<area_id>1<\/area_id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<next_floor>\s*<area_id>2<\/area_id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<\/next_floor>\s*<floor_info>\s*<id>2<\/id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<next_floor>[\s\S]*<floor_info>\s*<id>3<\/id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<\/next_floor>[\s\S]*<progress>0<\/progress>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<\/next_floor>[\s\S]*<cost>2<\/cost>/);
  assert.match(createExplorationGetFloorXml(1, 3, 1), /<\/next_floor>[\s\S]*<progress>9<\/progress>/);
  assert.match(createExplorationGetFloorXml(5, 7), /<get_floor>\s*<area_id>5<\/area_id>/);
  assert.match(createExplorationGetFloorXml(5, 7), /<floor_info>\s*<id>6<\/id>/);
  assert.doesNotMatch(createExplorationGetFloorXml(5, 7), /<next_floor>/);
  assert.match(createExplorationGetFloorXml(1, 8), /<get_floor>\s*<area_id>6<\/area_id>/);
  assert.match(createExplorationGetFloorXml(1, 8), /<area_name>燐光の湖<\/area_name>/);
  assert.match(createExplorationGetFloorXml(1, 8), /<bg>adv_bg11<\/bg>/);
  assert.match(createExplorationGetFloorXml(4, 37), /<area_name>猛獣の砂丘<\/area_name>/);
  assert.match(createExplorationGetFloorXml(4, 37), /<bg>adv_bg37<\/bg>/);
  assert.match(createExplorationGetFloorXml(5, 52), /<area_name>祝福を授ける山<\/area_name>/);
  assert.match(createExplorationGetFloorXml(5, 52), /<bg>adv_bg42<\/bg>/);
  assert.doesNotMatch(EXPLORATION_EXPLORE_XML, /<next_scene>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<explore>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<progress>10<\/progress>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<gold>18<\/gold>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<get_exp>3<\/get_exp>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<lvup>0<\/lvup>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<is_limit>0<\/is_limit>/);
  assert.match(createExplorationExploreXml(9, { gold: 35, getExp: 6 }), /<progress>9<\/progress>/);
  assert.match(createExplorationExploreXml(9, { gold: 35, getExp: 6 }), /<gold>35<\/gold>/);
  assert.match(createExplorationExploreXml(9, { gold: 35, getExp: 6 }), /<get_exp>6<\/get_exp>/);
  assert.match(
    createExplorationExploreXml(10, { gold: 18, getExp: 3 }, { profile: { level: 18, nextExp: 2100 } }, { levelUp: true, isLimit: false }),
    /<lvup>1<\/lvup>[\s\S]*<is_limit>0<\/is_limit>/
  );
  assert.match(createExplorationExploreXml(99), /<next_floor>0<\/next_floor>/);
  assert.match(createExplorationExploreXml(100), /<progress>100<\/progress>/);
  assert.match(createExplorationExploreXml(100), /<next_floor>0<\/next_floor>/);
  assert.match(
    createExplorationExploreXml(10, { gold: 18, getExp: 3 }, { resources: { ap: { current: 24 } } }),
    /<your_data>[\s\S]*<ap>[\s\S]*<current>24<\/current>/
  );
  assert.match(
    createExplorationGetFloorXml(0, 2, 0, { profile: { nextExp: 123 }, resources: { ap: { current: 24 } } }),
    /<your_data>[\s\S]*<ap>[\s\S]*<current>24<\/current>/
  );
  assert.match(createExplorationGetFloorXml(0, 2, 0, { profile: { nextExp: 123 } }), /<next_exp>123<\/next_exp>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<event_type>0<\/event_type>/);
  assert.doesNotMatch(EXPLORATION_EXPLORE_XML, /<get_exp>0<\/get_exp>/);
  assert.match(TOWN_LVUP_STATUS_XML, /<next_scene>84100<\/next_scene>/);
  assert.match(TOWN_LVUP_STATUS_XML, /<body><\/body>/);
  assert.match(TOWN_LVUP_STATUS_XML, /<your_data>[\s\S]*<free_ap_bc_point>0<\/free_ap_bc_point>/);
  assertPlayerHeader(TOWN_LVUP_STATUS_XML, {
    leaderSerialId: 1,
    ownerCardSerialId: 1,
    ownerCardMasterCardId: 22,
  });
  assert.match(TOWN_POINTSETTING_XML, /<next_scene>2100<\/next_scene>/);
  assert.match(TOWN_POINTSETTING_XML, /<mainmenu>/);
  assertMainmenuInformation(TOWN_POINTSETTING_XML, { fairyPose: 1, fairyFace: 4 });
  assertPlayerHeader(
    createTownLvupStatusXml({
      profile: { level: 18, exp: 0, nextExp: 2100, percentage: 0 },
      resources: { ap: { current: 25, max: 25 }, bc: { current: 25, max: 25 } },
      progression: { abilityPoints: { unspent: 3 } },
    }),
    {
      apCurrent: 25,
      apMax: 25,
      bcCurrent: 25,
      bcMax: 25,
      rank: 18,
      percentage: 0,
      freeApBcPoint: 3,
    }
  );
  assertPlayerHeader(
    createTownPointsettingXml({
      profile: { level: 18, exp: 0, nextExp: 2100, percentage: 0 },
      resources: { ap: { current: 28, max: 28 }, bc: { current: 25, max: 25 } },
      progression: { abilityPoints: { unspent: 0 } },
    }),
    {
      apCurrent: 28,
      apMax: 28,
      bcCurrent: 25,
      bcMax: 25,
      rank: 18,
      percentage: 0,
      freeApBcPoint: 0,
    }
  );
  assertMainmenuInformation(MAINMENU_UPDATE_XML, { fairyPose: 1, fairyFace: 4 });
  for (const [faction, countryId, fairyCharacterId, fairyPose, fairyFace] of [
    ["sword", 1, 117, 1, 4],
    ["technique", 2, 120, 1, 8],
    ["magic", 3, 111, 2, 4],
  ]) {
    const save = saveWithFaction(faction);
    assert.deepEqual(getMainmenuInformationForPlayer(save), {
      countryId,
      fairyCharacterId,
      fairyPose,
      fairyFace,
    });
    const updateXml = createMainmenuUpdateXml(save);
    assertPlayerHeader(updateXml, { countryId });
    assertMainmenuInformation(updateXml, { fairyPose, fairyFace });
    const loginSampleXml = createLoginMainmenuXml(save);
    assertPlayerHeader(loginSampleXml, { countryId });
    assertMainmenuInformation(loginSampleXml, { fairyPose, fairyFace });
    assert.ok(readSampleSaveFile(`download/image/adv/adv_chara${fairyCharacterId}`)?.length > 0);
    assert.ok(readSampleSaveFile(`download/image/adv/adv_chara${fairyCharacterId}_${fairyPose}_${fairyFace}`)?.length > 0);
  }
  assert.deepEqual(getMainmenuInformationForPlayer({ profile: { countryId: 99 } }), {
    countryId: 1,
    fairyCharacterId: 117,
    fairyPose: 1,
    fairyFace: 4,
  });
  assert.equal(getLoginOkXml(), CHECK_INSPECTION_OK_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "minimal");
  process.env.LOGIN_RESPONSE = "tutorial";
  assert.equal(getLoginOkXml(), LOGIN_TUTORIAL_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "assets/bundle/local_forward_tutorial.xml");
  process.env.LOGIN_RESPONSE = "sample";
  const loginOkSampleXml = getLoginOkXml();
  assert.equal(getLoginXmlSource(loginOkSampleXml), "assets/bundle/local_battle_player.xml + mainmenu bg");
  assertPlayerHeader(loginOkSampleXml, { countryId: 1 });
  assertMainmenuInformation(loginOkSampleXml, { fairyPose: 1, fairyFace: 4 });
  assert.doesNotMatch(loginOkSampleXml, /<card_rev>[1-9]/);
  assert.doesNotMatch(loginOkSampleXml, /<resource_rev>[\s\S]*?<revision>[1-9]/);
  assert.equal(MAINMENU_ROUTE_STUBS["/connect/app/gacha/select/getcontents"].nextScene, 9100);
  assert.match(createMainmenuRouteXml("/connect/app/gacha/select/getcontents", DEFAULT_PLAYER_SAVE), /<next_scene>9100<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/gacha/select/getcontents", DEFAULT_PLAYER_SAVE), /<gacha_select>[\s\S]*<xml_contents>[\s\S]*<scroll_height>0<\/scroll_height>/);
  assert.doesNotMatch(createGachaSelectSkeletonXml(DEFAULT_PLAYER_SAVE), /gac_event_0|gac_free_0|gac_cp_0|<imagefile>/);
  assertPlayerHeader(createMainmenuRouteXml("/connect/app/gacha/select/getcontents", DEFAULT_PLAYER_SAVE), {
    apCurrent: DEFAULT_PLAYER_SAVE.resources.ap.current,
    apMax: DEFAULT_PLAYER_SAVE.resources.ap.max,
    bcCurrent: DEFAULT_PLAYER_SAVE.resources.bc.current,
    bcMax: DEFAULT_PLAYER_SAVE.resources.bc.max,
  });
  assert.match(createMainmenuRouteXml("/connect/app/battle/area", DEFAULT_PLAYER_SAVE), /<competition_parts>/);
  assert.match(createMainmenuRouteXml("/connect/app/battle/area", DEFAULT_PLAYER_SAVE), /<next_scene>\s*5100\s*<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/menu/menulist", DEFAULT_PLAYER_SAVE), /<next_scene>20100<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/menu/playerinfo", DEFAULT_PLAYER_SAVE), /<next_scene>26100<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/shop/shop", DEFAULT_PLAYER_SAVE), /<next_scene>8100<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/menu/productlist", DEFAULT_PLAYER_SAVE), /<next_scene>8400<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/item/use", DEFAULT_PLAYER_SAVE), /<next_scene>30200<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/friend/like_user", DEFAULT_PLAYER_SAVE), /<next_scene>17000<\/next_scene>/);
  assert.match(createMainmenuRouteXml("/connect/app/battle/battle_userlist", DEFAULT_PLAYER_SAVE), /<battle_userlist>/);
  assert.match(createMainmenuRouteXml("/connect/app/cardselect/savedeckcard", DEFAULT_PLAYER_SAVE), /<next_scene>83200<\/next_scene>/);
  assert.equal(createMainmenuRouteXml("/connect/app/not/a/mainmenu/route", DEFAULT_PLAYER_SAVE), null);
  delete process.env.LOGIN_RESPONSE;
  assert.deepEqual(
    parseConnectAppBody(
      "login_id=ySboruTbjYskjVUIf7U3Ew%3D%3D%0A&password=8qAl04QoOI2mCN0%2FMwrBKg%3D%3D%0A",
      "rBwj1MIAivVN222b"
    ).decrypted,
    { login_id: "13800138000", password: "testpass1" }
  );
  assert.ok(MASTERDATA_SAMPLES["/connect/app/masterdata/card/update"].bytes?.length > 0);
  assert.equal(
    encryptAes128EcbBuffer(
      MASTERDATA_SAMPLES["/connect/app/masterdata/card/update"].bytes,
      "rBwj1MIAivVN222b"
    ).length % 16,
    0
  );

  process.env.CHECK_INSPECTION_KEY = CONNECT_APP_KEY;
  process.env.CONNECT_APP_KEY = CONNECT_APP_KEY;
  process.env.KSSMA_PLAYER_SAVE_PATH = tempPlayerSavePath;
  process.env.LOGIN_RESPONSE = "sample";
  delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
  const syncedSave = JSON.parse(JSON.stringify(DEFAULT_PLAYER_SAVE));
  syncedSave.profile.level = 10;
  syncedSave.profile.faction = "technique";
  syncedSave.profile.percentage = 44;
  syncedSave.profile.nextExp = 321;
  syncedSave.resources.ap.current = 19;
  syncedSave.resources.ap.max = 31;
  syncedSave.resources.bc.current = 12;
  syncedSave.resources.bc.max = 33;
  syncedSave.currencies.gold = 4567;
  syncedSave.currencies.friendshipPoint = 88;
  syncedSave.cards.max = 222;
  fs.writeFileSync(tempPlayerSavePath, JSON.stringify(syncedSave), "utf8");
  const serverLogs = [];
  const originalWrite = process.stdout.write;
  process.stdout.write = function writeServerCapture(chunk, encoding, callback) {
    serverLogs.push(String(chunk));
    return originalWrite.call(process.stdout, chunk, encoding, callback);
  };
  const server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;

  try {
    const worldList = await post(port, "/world_list.php", "data_str=%7B%7D");
    assert.equal(worldList.statusCode, 200);
    const worlds = JSON.parse(worldList.body);
    assert.equal(worlds[0].world_id, 1);
    assert.equal(
      worlds[0].url_root,
      process.env.WORLD_URL || "http://10.0.2.2:50005/connect/app/"
    );

    const payload = {
      world_id: 1,
      device_id: "device-1",
      game_id: "1",
      user_id: "13800138000",
      password: encryptPassword("secret"),
    };
    const addUser = await post(
      port,
      "/add_user.php",
      `data_str=${encodeURIComponent(JSON.stringify(payload))}`
    );
    assert.equal(addUser.statusCode, 200);
    const addUserJson = JSON.parse(addUser.body);
    assert.equal(addUserJson.code, 1);
    assert.equal(addUserJson.user_id, "13800138000");

    const postDeviceToken = await post(
      port,
      "/connect/app/notification/post_devicetoken?cyt=1",
      "S=tAS5lPt7ftw8HlSUflkJFA%3D%3D%0A&login_id=zoRXD3LE%2F0ZO5aHAmQ0E9Q%3D%3D%0A"
    );
    assert.equal(postDeviceToken.statusCode, 200);
    assert.deepEqual(
      encryptAes128Ecb(CHECK_INSPECTION_OK_XML, "rBwj1MIAivVN222b"),
      postDeviceToken.buffer
    );

    const login = await post(
      port,
      "/connect/app/login?cyt=1",
      "login_id=ySboruTbjYskjVUIf7U3Ew%3D%3D%0A&password=8qAl04QoOI2mCN0%2FMwrBKg%3D%3D%0A"
    );
    assert.equal(login.statusCode, 200);
    const loginDecoded = decryptAes128EcbBase64(login.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(loginDecoded, /<mainmenu>/);
    assertPlayerHeader(loginDecoded, {
      countryId: 2,
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4567,
      rank: 10,
      percentage: 44,
      maxCardNum: 222,
      friendshipPoint: 88,
    });
    assertMainmenuInformation(loginDecoded, { fairyPose: 1, fairyFace: 8 });
    const loginResponseLog = serverLogs.find((line) => line.includes('"path":"/connect/app/login"') && line.includes("connect_app_response"));
    assert.match(loginResponseLog, /"mainmenu":\{"countryId":2,"fairyCharacterId":120,"fairyPose":1,"fairyFace":8\}/);
    assert.doesNotMatch(loginDecoded, /<ap>[\s\S]*<current>27<\/current>/);

    const mainmenuUpdate = await post(
      port,
      "/connect/app/mainmenu/update?cyt=1",
      ""
    );
    assert.equal(mainmenuUpdate.statusCode, 200);
    const mainmenuUpdateDecoded = decryptAes128EcbBase64(
      mainmenuUpdate.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(mainmenuUpdateDecoded, /<mainmenu>/);
    assertPlayerHeader(mainmenuUpdateDecoded, {
      countryId: 2,
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4567,
      rank: 10,
      percentage: 44,
      maxCardNum: 222,
      friendshipPoint: 88,
    });
    assertMainmenuInformation(mainmenuUpdateDecoded, { fairyPose: 1, fairyFace: 8 });
    const mainmenuUpdateResponseLog = serverLogs.find((line) => line.includes('"path":"/connect/app/mainmenu/update"') && line.includes("connect_app_response"));
    assert.match(mainmenuUpdateResponseLog, /"mainmenu":\{"countryId":2,"fairyCharacterId":120,"fairyPose":1,"fairyFace":8\}/);

    const mainmenu = await post(port, "/connect/app/mainmenu?cyt=1", "");
    assert.equal(mainmenu.statusCode, 200);
    const mainmenuDecoded = decryptAes128EcbBase64(
      mainmenu.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(mainmenuDecoded, /<mainmenu>/);
    assertPlayerHeader(mainmenuDecoded, {
      countryId: 2,
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4567,
      rank: 10,
      percentage: 44,
      maxCardNum: 222,
      friendshipPoint: 88,
    });
    assertMainmenuInformation(mainmenuDecoded, { fairyPose: 1, fairyFace: 8 });
    const mainmenuResponseLog = serverLogs.find((line) => line.includes('"path":"/connect/app/mainmenu"') && line.includes("connect_app_response"));
    assert.match(mainmenuResponseLog, /"mainmenu":\{"countryId":2,"fairyCharacterId":120,"fairyPose":1,"fairyFace":8\}/);

    const gachaSelect = await post(port, "/connect/app/gacha/select/getcontents?cyt=1", "");
    assert.equal(gachaSelect.statusCode, 200);
    const gachaSelectDecoded = decryptAes128EcbBase64(gachaSelect.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(gachaSelectDecoded, /<next_scene>9100<\/next_scene>/);
    assert.match(gachaSelectDecoded, /<gacha_select>[\s\S]*<xml_contents>[\s\S]*<scroll_height>0<\/scroll_height>/);
    assert.doesNotMatch(gachaSelectDecoded, /gac_event_0|gac_free_0|gac_cp_0|<imagefile>/);
    assertPlayerHeader(gachaSelectDecoded, {
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      rank: 10,
    });
    const gachaResponseLog = serverLogs.find((line) => line.includes('"path":"/connect/app/gacha/select/getcontents"') && line.includes("connect_app_response"));
    assert.match(gachaResponseLog, /"command":"gacha"/);
    assert.match(gachaResponseLog, /"nextScene":9100/);

    const battleArea = await post(port, "/connect/app/battle/area?cyt=1", "");
    assert.equal(battleArea.statusCode, 200);
    const battleAreaDecoded = decryptAes128EcbBase64(battleArea.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(battleAreaDecoded, /<next_scene>\s*5100\s*<\/next_scene>/);
    assert.match(battleAreaDecoded, /<competition_parts>/);
    assertPlayerHeader(battleAreaDecoded, { apCurrent: 19, bcCurrent: 12, rank: 10 });

    const menuList = await post(port, "/connect/app/menu/menulist?cyt=1", "");
    assert.equal(menuList.statusCode, 200);
    const menuListDecoded = decryptAes128EcbBase64(menuList.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(menuListDecoded, /<next_scene>20100<\/next_scene>/);
    assert.match(menuListDecoded, /<body><\/body>/);
    assertPlayerHeader(menuListDecoded, { apCurrent: 19, bcCurrent: 12, rank: 10 });

    const playerInfo = await post(port, "/connect/app/menu/playerinfo?cyt=1", "");
    assert.equal(playerInfo.statusCode, 200);
    const playerInfoDecoded = decryptAes128EcbBase64(playerInfo.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(playerInfoDecoded, /<next_scene>26100<\/next_scene>/);

    const shop = await post(port, "/connect/app/shop/shop?cyt=1", "");
    assert.equal(shop.statusCode, 200);
    const shopDecoded = decryptAes128EcbBase64(shop.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(shopDecoded, /<next_scene>8100<\/next_scene>/);

    const productList = await post(port, "/connect/app/menu/productlist?cyt=1", "");
    assert.equal(productList.statusCode, 200);
    const productListDecoded = decryptAes128EcbBase64(productList.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(productListDecoded, /<next_scene>8400<\/next_scene>/);

    const friendLike = await post(port, "/connect/app/friend/like_user?cyt=1", "");
    assert.equal(friendLike.statusCode, 200);
    const friendLikeDecoded = decryptAes128EcbBase64(friendLike.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(friendLikeDecoded, /<next_scene>17000<\/next_scene>/);

    const battleUserlist = await post(port, "/connect/app/battle/battle_userlist?cyt=1", "");
    assert.equal(battleUserlist.statusCode, 200);
    const battleUserlistDecoded = decryptAes128EcbBase64(battleUserlist.buffer.toString("base64"), "rBwj1MIAivVN222b");
    assert.match(battleUserlistDecoded, /<battle_userlist>/);

    const explorationArea = await post(
      port,
      "/connect/app/exploration/area?cyt=1",
      ""
    );
    assert.equal(explorationArea.statusCode, 200);
    const explorationAreaDecoded = decryptAes128EcbBase64(
      explorationArea.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(explorationAreaDecoded, /<exploration_area>/);
    assertPlayerHeader(explorationAreaDecoded, {
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4567,
      rank: 10,
      percentage: 44,
      maxCardNum: 222,
      friendshipPoint: 88,
    });
    assert.match(explorationAreaDecoded, /<area_info>/);
    assert.doesNotMatch(explorationAreaDecoded, /<floor_info_list>/);
    assert.doesNotMatch(explorationAreaDecoded, /<floor_info>/);

    const explorationFloor = await post(
      port,
      "/connect/app/exploration/floor?cyt=1",
      "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A"
    );
    assert.equal(explorationFloor.statusCode, 200);
    const explorationFloorDecoded = decryptAes128EcbBase64(
      explorationFloor.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(explorationFloorDecoded, /<exploration_floor>/);
    assertPlayerHeader(explorationFloorDecoded, {
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4567,
      rank: 10,
      percentage: 44,
      maxCardNum: 222,
      friendshipPoint: 88,
    });

    const explorationGetFloor = await post(
      port,
      "/connect/app/exploration/get_floor?cyt=1",
      "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&check=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A"
    );
    assert.equal(explorationGetFloor.statusCode, 200);
    const explorationGetFloorDecoded = decryptAes128EcbBase64(
      explorationGetFloor.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(explorationGetFloorDecoded, /<get_floor>/);
    assertPlayerHeader(explorationGetFloorDecoded, {
      apCurrent: 19,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4567,
      rank: 10,
      percentage: 44,
      maxCardNum: 222,
      friendshipPoint: 88,
      nextExp: 321,
    });

    const capturedLogs = [];
    process.stdout.write = function writeCapture(chunk, encoding, callback) {
      capturedLogs.push(String(chunk));
      if (typeof callback === "function") {
        callback();
      }
      return true;
    };
    try {
      const logServer = createServer();
      await new Promise((resolve) => logServer.listen(0, "127.0.0.1", resolve));
      const logPort = logServer.address().port;
      try {
        await post(
          logPort,
          "/connect/app/exploration/get_floor?cyt=1",
          "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&check=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A"
        );
      } finally {
        await new Promise((resolve, reject) => logServer.close((err) => (err ? reject(err) : resolve())));
      }
    } finally {
      process.stdout.write = originalWrite;
    }
    const getFloorResponseLog = capturedLogs
      .join("")
      .split(/\r?\n/)
      .find((line) => line.includes("connect_app_response") && line.includes("/connect/app/exploration/get_floor"));
    assert.ok(getFloorResponseLog);
    assert.match(getFloorResponseLog, /"regionId":0/);
    assert.match(getFloorResponseLog, /"floorId":2/);
    assert.match(getFloorResponseLog, /"areaNo":1/);
    assert.match(getFloorResponseLog, /"cost":1/);
    assert.match(getFloorResponseLog, /"requiredMoves":10/);
    assert.match(getFloorResponseLog, /"bg":"adv_bg14"/);
    assert.match(getFloorResponseLog, /"bgm":"sarch1"/);
    assert.match(getFloorResponseLog, /"gold":18/);
    assert.match(getFloorResponseLog, /"getExp":3/);
    assert.match(getFloorResponseLog, /"progress":0/);
    assert.match(getFloorResponseLog, /"hasNextFloor":true/);
    assert.match(getFloorResponseLog, /"nextFloorId":3/);
    assert.match(getFloorResponseLog, /"nextAreaNo":2/);
    assert.match(getFloorResponseLog, /"nextRouteAreaId":1/);

    const lockedNextFloor = await post(
      port,
      "/connect/app/exploration/get_floor?cyt=1",
      "area_id=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&check=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=3sJ7qONwz5JawDpnsoUDJQ%3D%3D%0A"
    );
    assert.equal(lockedNextFloor.statusCode, 200);
    const lockedNextFloorDecoded = decryptAes128EcbBase64(
      lockedNextFloor.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.equal(lockedNextFloorDecoded, createExplorationLockedXml());

    const explorationExplore = await post(
      port,
      "/connect/app/exploration/explore?cyt=1",
      "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A"
    );
    assert.equal(explorationExplore.statusCode, 200);
    const explorationExploreDecoded = decryptAes128EcbBase64(
      explorationExplore.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(explorationExploreDecoded, /<progress>10<\/progress>/);
    assert.match(explorationExploreDecoded, /<gold>18<\/gold>/);
    assert.match(explorationExploreDecoded, /<get_exp>3<\/get_exp>/);
    assertPlayerHeader(explorationExploreDecoded, {
      apCurrent: 18,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4585,
      rank: 10,
      percentage: 0,
      maxCardNum: 222,
      friendshipPoint: 88,
      nextExp: 1300,
    });
    const saveAfterExplore = JSON.parse(fs.readFileSync(tempPlayerSavePath, "utf8"));
    assert.equal(saveAfterExplore.resources.ap.current, 18);
    assert.equal(saveAfterExplore.profile.exp, 3);
    assert.equal(saveAfterExplore.profile.nextExp, 1300);
    assert.equal(saveAfterExplore.profile.percentage, 0);
    assert.equal(saveAfterExplore.currencies.gold, 4585);
    assert.equal(saveAfterExplore.exploration.movesByFloor["0:2"], 1);
    assert.equal(saveAfterExplore.exploration.currentRegionId, 0);
    assert.equal(saveAfterExplore.exploration.currentFloorKey, "0:2");
    assert.equal(saveAfterExplore.exploration.floors["0:2"].movesDone, 1);
    assert.equal(saveAfterExplore.exploration.floors["0:2"].progress, 10);
    assert.equal(saveAfterExplore.exploration.floors["0:2"].unlocked, true);
    assert.equal(saveAfterExplore.exploration.floors["0:2"].cleared, false);
    assert.equal(saveAfterExplore.exploration.regions["0"].progress, 1);
    assert.equal(saveAfterExplore.exploration.regions["0"].unlocked, true);
    assert.equal(saveAfterExplore.stats.explorationMoves, 1);

    const explorationExploreAgain = await post(
      port,
      "/connect/app/exploration/explore?cyt=1",
      "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A"
    );
    assert.equal(explorationExploreAgain.statusCode, 200);
    const explorationExploreAgainDecoded = decryptAes128EcbBase64(
      explorationExploreAgain.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(explorationExploreAgainDecoded, /<progress>20<\/progress>/);
    assert.match(explorationExploreAgainDecoded, /<gold>18<\/gold>/);
    assert.match(explorationExploreAgainDecoded, /<get_exp>3<\/get_exp>/);
    assertPlayerHeader(explorationExploreAgainDecoded, {
      apCurrent: 17,
      apMax: 31,
      bcCurrent: 12,
      bcMax: 33,
      gold: 4603,
      rank: 10,
      percentage: 0,
      maxCardNum: 222,
      friendshipPoint: 88,
      nextExp: 1300,
    });
    const saveAfterExploreAgain = JSON.parse(fs.readFileSync(tempPlayerSavePath, "utf8"));
    assert.equal(saveAfterExploreAgain.resources.ap.current, 17);
    assert.equal(saveAfterExploreAgain.profile.exp, 6);
    assert.equal(saveAfterExploreAgain.profile.nextExp, 1300);
    assert.equal(saveAfterExploreAgain.profile.percentage, 0);
    assert.equal(saveAfterExploreAgain.currencies.gold, 4603);
    assert.equal(saveAfterExploreAgain.exploration.movesByFloor["0:2"], 2);
    assert.equal(saveAfterExploreAgain.exploration.floors["0:2"].movesDone, 2);
    assert.equal(saveAfterExploreAgain.exploration.floors["0:2"].progress, 20);
    assert.equal(saveAfterExploreAgain.stats.explorationMoves, 2);

    const explorationFloorAfterTwoMoves = await post(
      port,
      "/connect/app/exploration/floor?cyt=1",
      "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A"
    );
    assert.equal(explorationFloorAfterTwoMoves.statusCode, 200);
    const explorationFloorAfterTwoMovesDecoded = decryptAes128EcbBase64(
      explorationFloorAfterTwoMoves.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(
      explorationFloorAfterTwoMovesDecoded,
      /<floor_info>\s*<id>2<\/id>[\s\S]*?<progress>20<\/progress>/
    );
    assert.doesNotMatch(
      explorationFloorAfterTwoMovesDecoded,
      /<floor_info>\s*<id>3<\/id>[\s\S]*?<progress>0<\/progress>/
    );

    const capturedProgressLogs = [];
    process.stdout.write = function writeProgressCapture(chunk, encoding, callback) {
      capturedProgressLogs.push(String(chunk));
      if (typeof callback === "function") {
        callback();
      }
      return true;
    };
    try {
      const progressLogServer = createServer();
      await new Promise((resolve) => progressLogServer.listen(0, "127.0.0.1", resolve));
    const progressLogPort = progressLogServer.address().port;
      try {
        await post(
          progressLogPort,
          "/connect/app/exploration/explore?cyt=1",
          "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A"
        );
        await post(
          progressLogPort,
          "/connect/app/exploration/floor?cyt=1",
          "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A"
        );
      } finally {
        await new Promise((resolve, reject) => progressLogServer.close((err) => (err ? reject(err) : resolve())));
      }
    } finally {
      process.stdout.write = originalWrite;
    }
    const floorProgressLog = capturedProgressLogs
      .join("")
      .split(/\r?\n/)
      .find((line) => line.includes("connect_app_response") && line.includes("/connect/app/exploration/floor"));
    assert.ok(floorProgressLog);
    assert.match(floorProgressLog, /"maxProgress":30/);
    assert.match(floorProgressLog, /"maxProgressFloorId":2/);
    const saveAfterProgressLogServer = JSON.parse(fs.readFileSync(tempPlayerSavePath, "utf8"));
    assert.equal(saveAfterProgressLogServer.resources.ap.current, 16);
    assert.equal(saveAfterProgressLogServer.profile.exp, 9);
    assert.equal(saveAfterProgressLogServer.currencies.gold, 4621);
    assert.equal(saveAfterProgressLogServer.exploration.movesByFloor["0:2"], 3);
    assert.equal(saveAfterProgressLogServer.exploration.floors["0:2"].progress, 30);
    assert.equal(saveAfterProgressLogServer.stats.explorationMoves, 3);

    const previousMigrationSavePath = process.env.KSSMA_PLAYER_SAVE_PATH;
    const migrationSavePath = path.join(tempDir, "old-player-save.json");
    fs.writeFileSync(
      migrationSavePath,
      JSON.stringify({ exploration: { movesByFloor: { "0:2": 2 } } }),
      "utf8"
    );
    process.env.KSSMA_PLAYER_SAVE_PATH = migrationSavePath;
    const migrationServer = createServer();
    await new Promise((resolve) => migrationServer.listen(0, "127.0.0.1", resolve));
    const migrationPort = migrationServer.address().port;
    try {
      const migratedFloor = await post(
        migrationPort,
        "/connect/app/exploration/floor?cyt=1",
        "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A"
      );
      assert.equal(migratedFloor.statusCode, 200);
      const migratedFloorDecoded = decryptAes128EcbBase64(
        migratedFloor.buffer.toString("base64"),
        "rBwj1MIAivVN222b"
      );
      assert.match(migratedFloorDecoded, /<floor_info>\s*<id>2<\/id>[\s\S]*?<progress>20<\/progress>/);
      const migratedExplore = await post(
        migrationPort,
        "/connect/app/exploration/explore?cyt=1",
        "area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A"
      );
      assert.equal(migratedExplore.statusCode, 200);
      const migratedSave = JSON.parse(fs.readFileSync(migrationSavePath, "utf8"));
      assert.equal(migratedSave.schemaVersion, 2);
      assert.equal(migratedSave.resources.ap.current, 24);
      assert.equal(migratedSave.resources.ap.max, 25);
      assert.equal(migratedSave.profile.exp, 3);
      assert.equal(migratedSave.currencies.gold, 18);
      assert.equal(migratedSave.cards.max, 350);
      assert.equal(migratedSave.friends.max, 30);
      assert.equal(migratedSave.exploration.movesByFloor["0:2"], 3);
      assert.equal(migratedSave.exploration.floors["0:2"].progress, 30);
    } finally {
      await new Promise((resolve, reject) => migrationServer.close((err) => (err ? reject(err) : resolve())));
      process.env.KSSMA_PLAYER_SAVE_PATH = previousMigrationSavePath;
    }

    const lockedSecondAreaGetFloor = await post(
      port,
      "/connect/app/exploration/get_floor?cyt=1",
      "area_id=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&check=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=3sJ7qONwz5JawDpnsoUDJQ%3D%3D%0A"
    );
    assert.equal(lockedSecondAreaGetFloor.statusCode, 200);
    const lockedSecondAreaGetFloorDecoded = decryptAes128EcbBase64(
      lockedSecondAreaGetFloor.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.equal(lockedSecondAreaGetFloorDecoded, createExplorationLockedXml());

    const lockedSecondAreaExplore = await post(
      port,
      "/connect/app/exploration/explore?cyt=1",
      "area_id=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=3sJ7qONwz5JawDpnsoUDJQ%3D%3D%0A"
    );
    assert.equal(lockedSecondAreaExplore.statusCode, 200);
    const lockedSecondAreaExploreDecoded = decryptAes128EcbBase64(
      lockedSecondAreaExplore.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.equal(lockedSecondAreaExploreDecoded, createExplorationLockedXml());
    const saveAfterLockedSecondArea = JSON.parse(fs.readFileSync(tempPlayerSavePath, "utf8"));
    assert.equal(saveAfterLockedSecondArea.exploration.movesByFloor["1:3"], undefined);
    assert.equal(saveAfterLockedSecondArea.resources.ap.current, 16);

    const previousUnlockSeed = process.env.KSSMA_EXPLORATION_MOVES_SEED;
    const unlockSavePath = path.join(tempDir, "unlock-player-save.json");
    process.env.KSSMA_PLAYER_SAVE_PATH = unlockSavePath;
    process.env.KSSMA_EXPLORATION_MOVES_SEED = '{"0:2":9}';
    const unlockServer = createServer();
    await new Promise((resolve) => unlockServer.listen(0, "127.0.0.1", resolve));
    const unlockPort = unlockServer.address().port;
    try {
      const unlockExplore = await post(
        unlockPort,
        "/connect/app/exploration/explore?cyt=1",
        connectAppBody({ area_id: 0, auto_build: 1, floor_id: 1 })
      );
      assert.equal(unlockExplore.statusCode, 200);
      const unlockExploreDecoded = decryptAes128EcbBase64(unlockExplore.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.match(unlockExploreDecoded, /<progress>100<\/progress>/);
      assert.match(unlockExploreDecoded, /<gold>18<\/gold>/);
      assert.match(unlockExploreDecoded, /<get_exp>3<\/get_exp>/);
      assert.match(unlockExploreDecoded, /<your_data>[\s\S]*<ap>[\s\S]*<current>24<\/current>/);
      const unlockFloor = await post(
        unlockPort,
        "/connect/app/exploration/floor?cyt=1",
        connectAppBody({ area_id: 0 })
      );
      assert.equal(unlockFloor.statusCode, 200);
      const unlockFloorDecoded = decryptAes128EcbBase64(unlockFloor.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.match(unlockFloorDecoded, /<floor_info>\s*<id>2<\/id>[\s\S]*?<progress>100<\/progress>/);
      assert.match(unlockFloorDecoded, /<floor_info>\s*<id>3<\/id>[\s\S]*?<progress>0<\/progress>/);
      const unlockSave = JSON.parse(fs.readFileSync(unlockSavePath, "utf8"));
      assert.equal(unlockSave.resources.ap.current, 24);
      assert.equal(unlockSave.exploration.floors["0:2"].cleared, true);
      assert.equal(unlockSave.exploration.floors["1:3"].unlocked, true);
    } finally {
      await new Promise((resolve, reject) => unlockServer.close((err) => (err ? reject(err) : resolve())));
      if (previousUnlockSeed === undefined) {
        delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
      } else {
        process.env.KSSMA_EXPLORATION_MOVES_SEED = previousUnlockSeed;
      }
      process.env.KSSMA_PLAYER_SAVE_PATH = tempPlayerSavePath;
    }

    const previousApSeed = process.env.KSSMA_EXPLORATION_MOVES_SEED;
    const lowApSavePath = path.join(tempDir, "low-ap-player-save.json");
    fs.writeFileSync(lowApSavePath, JSON.stringify({ resources: { ap: { current: 0 } } }), "utf8");
    process.env.KSSMA_PLAYER_SAVE_PATH = lowApSavePath;
    delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
    const lowApServer = createServer();
    await new Promise((resolve) => lowApServer.listen(0, "127.0.0.1", resolve));
    const lowApPort = lowApServer.address().port;
    try {
      const lowApExplore = await post(
        lowApPort,
        "/connect/app/exploration/explore?cyt=1",
        connectAppBody({ area_id: 0, auto_build: 1, floor_id: 1 })
      );
      assert.equal(lowApExplore.statusCode, 200);
      const lowApExploreDecoded = decryptAes128EcbBase64(lowApExplore.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.equal(lowApExploreDecoded, createExplorationApFailXml());
      const lowApSave = JSON.parse(fs.readFileSync(lowApSavePath, "utf8"));
      assert.equal(lowApSave.resources.ap.current, 0);
      assert.equal(lowApSave.exploration, undefined);
    } finally {
      await new Promise((resolve, reject) => lowApServer.close((err) => (err ? reject(err) : resolve())));
      if (previousApSeed === undefined) {
        delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
      } else {
        process.env.KSSMA_EXPLORATION_MOVES_SEED = previousApSeed;
      }
      process.env.KSSMA_PLAYER_SAVE_PATH = tempPlayerSavePath;
    }

    const levelUpSavePath = path.join(tempDir, "levelup-player-save.json");
    const levelUpSave = JSON.parse(JSON.stringify(DEFAULT_PLAYER_SAVE));
    levelUpSave.profile.level = 17;
    levelUpSave.profile.exp = 1997;
    levelUpSave.profile.nextExp = 2000;
    levelUpSave.profile.percentage = 99;
    levelUpSave.resources.ap.current = 1;
    levelUpSave.resources.ap.max = 25;
    levelUpSave.resources.bc.current = 7;
    levelUpSave.resources.bc.max = 25;
    levelUpSave.progression.abilityPoints.unspent = 0;
    levelUpSave.progression.abilityPoints.fromLevels = 0;
    fs.writeFileSync(levelUpSavePath, JSON.stringify(levelUpSave), "utf8");
    process.env.KSSMA_PLAYER_SAVE_PATH = levelUpSavePath;
    delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
    const levelUpServer = createServer();
    await new Promise((resolve) => levelUpServer.listen(0, "127.0.0.1", resolve));
    const levelUpPort = levelUpServer.address().port;
    try {
      const levelUpExplore = await post(
        levelUpPort,
        "/connect/app/exploration/explore?cyt=1",
        connectAppBody({ area_id: 0, auto_build: 1, floor_id: 1 })
      );
      assert.equal(levelUpExplore.statusCode, 200);
      const levelUpExploreDecoded = decryptAes128EcbBase64(levelUpExplore.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.match(levelUpExploreDecoded, /<progress>10<\/progress>/);
      assert.match(levelUpExploreDecoded, /<gold>18<\/gold>/);
      assert.match(levelUpExploreDecoded, /<get_exp>3<\/get_exp>/);
      assert.match(levelUpExploreDecoded, /<lvup>1<\/lvup>/);
      assert.match(levelUpExploreDecoded, /<is_limit>0<\/is_limit>/);
      assertPlayerHeader(levelUpExploreDecoded, {
        apCurrent: 25,
        apMax: 25,
        bcCurrent: 25,
        bcMax: 25,
        gold: 18,
        rank: 18,
        percentage: 0,
        freeApBcPoint: 3,
      });
      const saveAfterLevelUp = JSON.parse(fs.readFileSync(levelUpSavePath, "utf8"));
      assert.equal(saveAfterLevelUp.profile.level, 18);
      assert.equal(saveAfterLevelUp.profile.exp, 0);
      assert.equal(saveAfterLevelUp.profile.nextExp, 2100);
      assert.equal(saveAfterLevelUp.profile.percentage, 0);
      assert.equal(saveAfterLevelUp.resources.ap.current, 25);
      assert.equal(saveAfterLevelUp.resources.bc.current, 25);
      assert.equal(saveAfterLevelUp.progression.abilityPoints.unspent, 3);
      assert.equal(saveAfterLevelUp.progression.abilityPoints.fromLevels, 3);
      assert.equal(saveAfterLevelUp.currencies.gold, 18);
      assert.equal(saveAfterLevelUp.exploration.movesByFloor["0:2"], 1);

      const townLvupStatus = await post(
        levelUpPort,
        "/connect/app/town/lvup_status?cyt=1",
        ""
      );
      assert.equal(townLvupStatus.statusCode, 200);
      const townLvupStatusDecoded = decryptAes128EcbBase64(townLvupStatus.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.match(townLvupStatusDecoded, /<next_scene>84100<\/next_scene>/);
      assert.match(townLvupStatusDecoded, /<body><\/body>/);
      assertPlayerHeader(townLvupStatusDecoded, {
        apCurrent: 25,
        apMax: 25,
        bcCurrent: 25,
        bcMax: 25,
        gold: 18,
        rank: 18,
        percentage: 0,
        freeApBcPoint: 3,
      });

      const townPointsetting = await post(
        levelUpPort,
        "/connect/app/town/pointsetting?cyt=1",
        connectAppBody({ ap: 3, bc: 0 })
      );
      assert.equal(townPointsetting.statusCode, 200);
      const townPointsettingDecoded = decryptAes128EcbBase64(townPointsetting.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.match(townPointsettingDecoded, /<next_scene>2100<\/next_scene>/);
      assert.match(townPointsettingDecoded, /<mainmenu>/);
      assertPlayerHeader(townPointsettingDecoded, {
        apCurrent: 28,
        apMax: 28,
        bcCurrent: 25,
        bcMax: 25,
        gold: 18,
        rank: 18,
        percentage: 0,
        freeApBcPoint: 0,
      });
      const saveAfterPointsetting = JSON.parse(fs.readFileSync(levelUpSavePath, "utf8"));
      assert.equal(saveAfterPointsetting.resources.ap.current, 28);
      assert.equal(saveAfterPointsetting.resources.ap.max, 28);
      assert.equal(saveAfterPointsetting.resources.bc.current, 25);
      assert.equal(saveAfterPointsetting.resources.bc.max, 25);
      assert.equal(saveAfterPointsetting.progression.abilityPoints.unspent, 0);
      assert.equal(saveAfterPointsetting.progression.abilityPoints.apAllocated, 3);
      assert.equal(saveAfterPointsetting.progression.abilityPoints.bcAllocated, 0);
    } finally {
      await new Promise((resolve, reject) => levelUpServer.close((err) => (err ? reject(err) : resolve())));
      process.env.KSSMA_PLAYER_SAVE_PATH = tempPlayerSavePath;
    }

    const weakLevelUpSavePath = path.join(tempDir, "weak-levelup-player-save.json");
    const weakLevelUpSave = JSON.parse(JSON.stringify(DEFAULT_PLAYER_SAVE));
    weakLevelUpSave.profile.level = 16;
    weakLevelUpSave.profile.exp = 1897;
    weakLevelUpSave.profile.nextExp = 1900;
    weakLevelUpSave.profile.percentage = 99;
    weakLevelUpSave.resources.ap.current = 1;
    weakLevelUpSave.resources.ap.max = 25;
    weakLevelUpSave.resources.bc.current = 7;
    weakLevelUpSave.resources.bc.max = 25;
    weakLevelUpSave.progression.abilityPoints.unspent = 0;
    weakLevelUpSave.progression.abilityPoints.fromLevels = 0;
    fs.writeFileSync(weakLevelUpSavePath, JSON.stringify(weakLevelUpSave), "utf8");
    process.env.KSSMA_PLAYER_SAVE_PATH = weakLevelUpSavePath;
    delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
    const weakLevelUpServer = createServer();
    await new Promise((resolve) => weakLevelUpServer.listen(0, "127.0.0.1", resolve));
    const weakLevelUpPort = weakLevelUpServer.address().port;
    try {
      const weakLevelUpExplore = await post(
        weakLevelUpPort,
        "/connect/app/exploration/explore?cyt=1",
        connectAppBody({ area_id: 0, auto_build: 1, floor_id: 1 })
      );
      assert.equal(weakLevelUpExplore.statusCode, 200);
      const weakLevelUpExploreDecoded = decryptAes128EcbBase64(weakLevelUpExplore.buffer.toString("base64"), CONNECT_APP_KEY);
      assert.match(weakLevelUpExploreDecoded, /<lvup>1<\/lvup>/);
      assertPlayerHeader(weakLevelUpExploreDecoded, {
        apCurrent: 25,
        apMax: 25,
        bcCurrent: 25,
        bcMax: 25,
        rank: 17,
        percentage: 0,
        nextExp: 2000,
        freeApBcPoint: 3,
      });
      const saveAfterWeakLevelUp = JSON.parse(fs.readFileSync(weakLevelUpSavePath, "utf8"));
      assert.equal(saveAfterWeakLevelUp.profile.level, 17);
      assert.equal(saveAfterWeakLevelUp.profile.exp, 0);
      assert.equal(saveAfterWeakLevelUp.profile.nextExp, 2000);
    } finally {
      await new Promise((resolve, reject) => weakLevelUpServer.close((err) => (err ? reject(err) : resolve())));
      process.env.KSSMA_PLAYER_SAVE_PATH = tempPlayerSavePath;
    }

    const previousSeed = process.env.KSSMA_EXPLORATION_MOVES_SEED;
    const seededSavePath = path.join(tempDir, "seeded-player-save.json");
    process.env.KSSMA_PLAYER_SAVE_PATH = seededSavePath;
    process.env.KSSMA_EXPLORATION_MOVES_SEED = '{"4:6":15}';
    const seededServer = createServer();
    await new Promise((resolve) => seededServer.listen(0, "127.0.0.1", resolve));
    const seededPort = seededServer.address().port;
    try {
      const seededGetFloor = await post(
        seededPort,
        "/connect/app/exploration/get_floor?cyt=1",
        connectAppBody({ area_id: 0, check: 1, floor_id: 6 })
      );
      assert.equal(seededGetFloor.statusCode, 200);
      const seededGetFloorDecoded = decryptAes128EcbBase64(
        seededGetFloor.buffer.toString("base64"),
        CONNECT_APP_KEY
      );
      assert.match(seededGetFloorDecoded, /<get_floor>\s*<area_id>4<\/area_id>/);
      assert.match(seededGetFloorDecoded, /<next_floor>\s*<area_id>5<\/area_id>/);
      assert.match(seededGetFloorDecoded, /<next_floor>[\s\S]*<floor_info>\s*<id>6<\/id>/);
      assert.match(seededGetFloorDecoded, /<\/next_floor>\s*<floor_info>\s*<id>5<\/id>/);
      assert.match(seededGetFloorDecoded, /<\/next_floor>[\s\S]*<progress>93<\/progress>/);

      const seededExplore = await post(
        seededPort,
        "/connect/app/exploration/explore?cyt=1",
        connectAppBody({ area_id: 4, auto_build: 1, floor_id: 5 })
      );
      assert.equal(seededExplore.statusCode, 200);
      const seededExploreDecoded = decryptAes128EcbBase64(
        seededExplore.buffer.toString("base64"),
        CONNECT_APP_KEY
      );
      assert.match(seededExploreDecoded, /<progress>100<\/progress>/);
      assert.match(seededExploreDecoded, /<gold>55<\/gold>/);
      assert.match(seededExploreDecoded, /<get_exp>9<\/get_exp>/);
      assert.match(seededExploreDecoded, /<your_data>[\s\S]*<ap>[\s\S]*<current>22<\/current>/);

      const seededNextFloor = await post(
        seededPort,
        "/connect/app/exploration/get_floor?cyt=1",
        connectAppBody({ area_id: 5, check: 1, floor_id: 6 })
      );
      assert.equal(seededNextFloor.statusCode, 200);
      const seededNextFloorDecoded = decryptAes128EcbBase64(
        seededNextFloor.buffer.toString("base64"),
        CONNECT_APP_KEY
      );
      assert.match(seededNextFloorDecoded, /<get_floor>\s*<area_id>5<\/area_id>/);
      assert.doesNotMatch(seededNextFloorDecoded, /<next_floor>/);
      assert.match(seededNextFloorDecoded, /<floor_info>\s*<id>6<\/id>[\s\S]*?<progress>0<\/progress>/);
    } finally {
      await new Promise((resolve, reject) => seededServer.close((err) => (err ? reject(err) : resolve())));
      if (previousSeed === undefined) {
        delete process.env.KSSMA_EXPLORATION_MOVES_SEED;
      } else {
        process.env.KSSMA_EXPLORATION_MOVES_SEED = previousSeed;
      }
      process.env.KSSMA_PLAYER_SAVE_PATH = tempPlayerSavePath;
    }

    const webStub = await get(port, "/connect/web/?S=session-1");
    assert.equal(webStub.statusCode, 302);
    assert.equal(webStub.headers.location, WEB_SCENETO_LOCATION);
    assert.equal(webStub.body, "");
    assert.match(WEB_STUB_HTML, /sceneto:\/\/2100/);

    process.stdout.write("bootstrap-server self-check passed\n");
  } finally {
    process.stdout.write = originalWrite;
    await new Promise((resolve, reject) => server.close((err) => (err ? reject(err) : resolve())));
    if (previousPlayerSavePath === undefined) {
      delete process.env.KSSMA_PLAYER_SAVE_PATH;
    } else {
      process.env.KSSMA_PLAYER_SAVE_PATH = previousPlayerSavePath;
    }
    if (previousLoginResponse === undefined) {
      delete process.env.LOGIN_RESPONSE;
    } else {
      process.env.LOGIN_RESPONSE = previousLoginResponse;
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
