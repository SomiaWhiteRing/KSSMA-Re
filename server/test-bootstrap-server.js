const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const http = require("node:http");
const {
  createServer,
  ADD_USER_KEY,
  CHECK_INSPECTION_OK_XML,
  decryptAes128EcbBase64,
  encryptAes128Ecb,
  encryptAes128EcbBuffer,
  createExplorationAreaXml,
  createExplorationExploreXml,
  createExplorationFloorXml,
  createExplorationGetFloorXml,
  EXPLORATION_AREA_XML,
  EXPLORATION_EXPLORE_XML,
  EXPLORATION_FLOOR_XML,
  EXPLORATION_GET_FLOOR_XML,
  EXPLORATION_REGIONS,
  EXPLORATION_FLOORS,
  MAINMENU_UPDATE_XML,
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
} = require("./bootstrap-server");

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

async function main() {
  assert.deepEqual(parsePortList("", 50005), [50005]);
  assert.deepEqual(parsePortList("50005,10001 50005", 50005), [50005, 10001]);
  assert.equal(
    encryptAes128Ecb(CHECK_INSPECTION_OK_XML, "A1dPUcrvur2CRQyl").length % 16,
    0
  );
  assert.equal(decryptAes128EcbBase64("ySboruTbjYskjVUIf7U3Ew==", "rBwj1MIAivVN222b"), "13800138000");
  assert.equal(decryptAes128EcbBase64("8qAl04QoOI2mCN0/MwrBKg==", "rBwj1MIAivVN222b"), "testpass1");
  assert.match(EXPLORATION_AREA_XML, /<next_scene>6100<\/next_scene>/);
  assert.match(EXPLORATION_AREA_XML, /<exploration_area>/);
  assert.match(EXPLORATION_AREA_XML, /<prog_area>0<\/prog_area>/);
  assert.equal([...EXPLORATION_AREA_XML.matchAll(/<area_info>/g)].length, 6);
  assert.equal(EXPLORATION_REGIONS.length, 6);
  assert.equal(EXPLORATION_FLOORS.length, 70);
  assert.deepEqual(EXPLORATION_REGIONS.map((region) => region.floors.length), [6, 9, 10, 10, 15, 20]);
  for (const name of ["人魚の断崖", "燐光の湖", "錯乱の平原", "叡智の草原", "猛獣の砂丘", "祝福を授ける山"]) {
    assert.match(EXPLORATION_AREA_XML, new RegExp(`<name>${name}</name>`));
  }
  assert.doesNotMatch(EXPLORATION_AREA_XML, /Local Area/);
  assert.match(EXPLORATION_FLOOR_XML, /<exploration_floor>/);
  assert.match(EXPLORATION_FLOOR_XML, /<id>2<\/id>/);
  assert.match(EXPLORATION_FLOOR_XML, /<id>7<\/id>/);
  assert.match(EXPLORATION_FLOOR_XML, /<unlock>1<\/unlock>/);
  assert.match(EXPLORATION_FLOOR_XML, /<boss_down>0<\/boss_down>/);
  assert.equal([...EXPLORATION_FLOOR_XML.matchAll(/<floor_info>/g)].length, 6);
  assert.equal([...createExplorationFloorXml(1).matchAll(/<floor_info>/g)].length, 9);
  assert.match(createExplorationFloorXml(1), /<id>8<\/id>/);
  assert.match(createExplorationFloorXml(1), /<id>16<\/id>/);
  assert.match(createExplorationFloorXml(0, new Map([["0:2", 2]])), /<id>2<\/id>[\s\S]*?<progress>20<\/progress>/);
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
  assert.match(EXPLORATION_GET_FLOOR_XML, /<next_floor>[\s\S]*<floor_info>\s*<id>3<\/id>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<floor_info>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<\/next_floor>\s*<floor_info>\s*<id>2<\/id>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<\/next_floor>[\s\S]*<progress>0<\/progress>/);
  assert.match(EXPLORATION_GET_FLOOR_XML, /<\/next_floor>[\s\S]*<cost>1<\/cost>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<get_floor>\s*<area_id>1<\/area_id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<next_floor>\s*<area_id>2<\/area_id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<\/next_floor>\s*<floor_info>\s*<id>3<\/id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<next_floor>[\s\S]*<floor_info>\s*<id>4<\/id>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<\/next_floor>[\s\S]*<progress>0<\/progress>/);
  assert.match(createExplorationGetFloorXml(1, 3), /<\/next_floor>[\s\S]*<cost>2<\/cost>/);
  assert.match(createExplorationGetFloorXml(1, 3, 1), /<\/next_floor>[\s\S]*<progress>9<\/progress>/);
  assert.match(createExplorationGetFloorXml(5, 7), /<get_floor>\s*<area_id>5<\/area_id>/);
  assert.doesNotMatch(createExplorationGetFloorXml(5, 7), /<next_floor>/);
  assert.match(createExplorationGetFloorXml(1, 8), /<get_floor>\s*<area_id>6<\/area_id>/);
  assert.match(createExplorationGetFloorXml(1, 8), /<area_name>燐光の湖<\/area_name>/);
  assert.match(createExplorationGetFloorXml(1, 8), /<bg>adv_bg11<\/bg>/);
  assert.match(createExplorationGetFloorXml(4, 37), /<area_name>猛獣の砂丘<\/area_name>/);
  assert.match(createExplorationGetFloorXml(4, 37), /<bg>adv_bg37<\/bg>/);
  assert.match(createExplorationGetFloorXml(5, 52), /<area_name>祝福を授ける山<\/area_name>/);
  assert.match(createExplorationGetFloorXml(5, 52), /<bg>adv_bg42<\/bg>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<next_scene>6200<\/next_scene>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<explore>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<progress>10<\/progress>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<gold>18<\/gold>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<get_exp>3<\/get_exp>/);
  assert.match(createExplorationExploreXml(9, { gold: 35, getExp: 6 }), /<progress>9<\/progress>/);
  assert.match(createExplorationExploreXml(9, { gold: 35, getExp: 6 }), /<gold>35<\/gold>/);
  assert.match(createExplorationExploreXml(9, { gold: 35, getExp: 6 }), /<get_exp>6<\/get_exp>/);
  assert.match(createExplorationExploreXml(99), /<next_floor>0<\/next_floor>/);
  assert.match(createExplorationExploreXml(100), /<progress>100<\/progress>/);
  assert.match(createExplorationExploreXml(100), /<next_floor>0<\/next_floor>/);
  assert.match(EXPLORATION_EXPLORE_XML, /<event_type>0<\/event_type>/);
  assert.doesNotMatch(EXPLORATION_EXPLORE_XML, /<get_exp>0<\/get_exp>/);
  assert.match(MAINMENU_UPDATE_XML, /<mainmenu>/);
  assert.match(MAINMENU_UPDATE_XML, /<current_bgfile>mainbg_an<\/current_bgfile>/);
  assert.match(MAINMENU_UPDATE_XML, /<previous_bgfile>mainbg_an<\/previous_bgfile>/);
  assert.match(MAINMENU_UPDATE_XML, /<infomation>/);
  assert.match(MAINMENU_UPDATE_XML, /<fairy_pose>2<\/fairy_pose>/);
  assert.match(MAINMENU_UPDATE_XML, /<fairy_face>5<\/fairy_face>/);
  assert.match(MAINMENU_UPDATE_XML, /<text>Welcome back\.<\/text>/);
  assert.match(MAINMENU_UPDATE_XML, /<color>0xFFFFFF<\/color>/);
  assert.match(MAINMENU_UPDATE_XML, /<size>20<\/size>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<currentBgfile>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<imagefile>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<focus>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<link>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<banner>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<rewards>/);
  assert.doesNotMatch(MAINMENU_UPDATE_XML, /<event_type>/);
  assert.equal(getLoginOkXml(), CHECK_INSPECTION_OK_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "minimal");
  process.env.LOGIN_RESPONSE = "tutorial";
  assert.equal(getLoginOkXml(), LOGIN_TUTORIAL_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "assets/bundle/local_forward_tutorial.xml");
  process.env.LOGIN_RESPONSE = "sample";
  assert.equal(getLoginOkXml(), LOGIN_MAINMENU_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "assets/bundle/local_battle_player.xml + mainmenu bg");
  assert.match(getLoginOkXml(), /<mainmenu>/);
  assert.match(getLoginOkXml(), /<current_bgfile>mainbg_an<\/current_bgfile>/);
  assert.match(getLoginOkXml(), /<previous_bgfile>mainbg_an<\/previous_bgfile>/);
  assert.match(getLoginOkXml(), /<infomation>/);
  assert.match(getLoginOkXml(), /<fairy_pose>2<\/fairy_pose>/);
  assert.match(getLoginOkXml(), /<fairy_face>5<\/fairy_face>/);
  assert.match(getLoginOkXml(), /<text>Welcome back\.<\/text>/);
  assert.match(getLoginOkXml(), /<color>0xFFFFFF<\/color>/);
  assert.match(getLoginOkXml(), /<size>20<\/size>/);
  assert.doesNotMatch(getLoginOkXml(), /<currentBgfile>/);
  assert.doesNotMatch(getLoginOkXml(), /<imagefile>/);
  assert.doesNotMatch(getLoginOkXml(), /<focus>/);
  assert.doesNotMatch(getLoginOkXml(), /<link>/);
  assert.doesNotMatch(getLoginOkXml(), /<banner>/);
  assert.doesNotMatch(getLoginOkXml(), /<rewards>/);
  assert.doesNotMatch(getLoginOkXml(), /<event_type>/);
  assert.doesNotMatch(getLoginOkXml(), /<card_rev>[1-9]/);
  assert.doesNotMatch(getLoginOkXml(), /<resource_rev>[\s\S]*?<revision>[1-9]/);
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

  const server = createServer();
  process.env.CHECK_INSPECTION_KEY = "rBwj1MIAivVN222b";
  process.env.CONNECT_APP_KEY = "rBwj1MIAivVN222b";
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
    assert.equal(loginDecoded, CHECK_INSPECTION_OK_XML);

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
    assert.equal(mainmenuUpdateDecoded, MAINMENU_UPDATE_XML);

    const mainmenu = await post(port, "/connect/app/mainmenu?cyt=1", "");
    assert.equal(mainmenu.statusCode, 200);
    const mainmenuDecoded = decryptAes128EcbBase64(
      mainmenu.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.equal(mainmenuDecoded, MAINMENU_UPDATE_XML);

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
    assert.equal(explorationAreaDecoded, EXPLORATION_AREA_XML);
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
    assert.equal(explorationFloorDecoded, EXPLORATION_FLOOR_XML);

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
    assert.equal(explorationGetFloorDecoded, EXPLORATION_GET_FLOOR_XML);

    const capturedLogs = [];
    const originalWrite = process.stdout.write;
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
    assert.match(getFloorResponseLog, /"bg":"adv_bg14"/);

    const explorationGetNextFloor = await post(
      port,
      "/connect/app/exploration/get_floor?cyt=1",
      "area_id=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&check=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=3sJ7qONwz5JawDpnsoUDJQ%3D%3D%0A"
    );
    assert.equal(explorationGetNextFloor.statusCode, 200);
    const explorationGetNextFloorDecoded = decryptAes128EcbBase64(
      explorationGetNextFloor.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.equal(explorationGetNextFloorDecoded, createExplorationGetFloorXml(1, 3));

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
    assert.equal(explorationExploreDecoded, EXPLORATION_EXPLORE_XML);
    assert.match(explorationExploreDecoded, /<progress>10<\/progress>/);
    assert.match(explorationExploreDecoded, /<gold>18<\/gold>/);
    assert.match(explorationExploreDecoded, /<get_exp>3<\/get_exp>/);

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
    assert.equal(explorationExploreAgainDecoded, createExplorationExploreXml(20, { gold: 18, getExp: 3 }));

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
    assert.match(
      explorationFloorAfterTwoMovesDecoded,
      /<floor_info>\s*<id>3<\/id>[\s\S]*?<progress>0<\/progress>/
    );

    const secondAreaGetFloor = await post(
      port,
      "/connect/app/exploration/get_floor?cyt=1",
      "area_id=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&check=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=3sJ7qONwz5JawDpnsoUDJQ%3D%3D%0A"
    );
    assert.equal(secondAreaGetFloor.statusCode, 200);
    const secondAreaGetFloorDecoded = decryptAes128EcbBase64(
      secondAreaGetFloor.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.match(secondAreaGetFloorDecoded, /<get_floor>\s*<area_id>1<\/area_id>/);
    assert.match(secondAreaGetFloorDecoded, /<\/next_floor>\s*<floor_info>\s*<id>3<\/id>/);
    assert.match(secondAreaGetFloorDecoded, /<\/next_floor>[\s\S]*<progress>0<\/progress>/);
    assert.match(secondAreaGetFloorDecoded, /<\/next_floor>[\s\S]*<cost>2<\/cost>/);

    const secondAreaExplore = await post(
      port,
      "/connect/app/exploration/explore?cyt=1",
      "area_id=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=3sJ7qONwz5JawDpnsoUDJQ%3D%3D%0A"
    );
    assert.equal(secondAreaExplore.statusCode, 200);
    const secondAreaExploreDecoded = decryptAes128EcbBase64(
      secondAreaExplore.buffer.toString("base64"),
      "rBwj1MIAivVN222b"
    );
    assert.equal(secondAreaExploreDecoded, createExplorationExploreXml(9, { gold: 35, getExp: 6 }));

    const webStub = await get(port, "/connect/web/?S=session-1");
    assert.equal(webStub.statusCode, 302);
    assert.equal(webStub.headers.location, WEB_SCENETO_LOCATION);
    assert.equal(webStub.body, "");
    assert.match(WEB_STUB_HTML, /sceneto:\/\/2100/);

    process.stdout.write("bootstrap-server self-check passed\n");
  } finally {
    await new Promise((resolve, reject) => server.close((err) => (err ? reject(err) : resolve())));
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
