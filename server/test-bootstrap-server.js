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
  getLoginOkXml,
  getLoginXmlSource,
  LOGIN_OK_XML,
  LOGIN_TUTORIAL_XML,
  MASTERDATA_SAMPLES,
  parseConnectAppBody,
  parsePortList,
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
  assert.equal(getLoginOkXml(), CHECK_INSPECTION_OK_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "minimal");
  process.env.LOGIN_RESPONSE = "tutorial";
  assert.equal(getLoginOkXml(), LOGIN_TUTORIAL_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "assets/bundle/local_forward_tutorial.xml");
  process.env.LOGIN_RESPONSE = "sample";
  assert.equal(getLoginOkXml(), LOGIN_OK_XML);
  assert.equal(getLoginXmlSource(getLoginOkXml()), "assets/bundle/local_battle_player.xml");
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

    const webStub = await get(port, "/connect/web/?S=session-1");
    assert.equal(webStub.statusCode, 200);
    assert.equal(webStub.body, WEB_STUB_HTML);
    assert.match(webStub.body, /sceneto:\/\/2100/);
    assert.match(webStub.body, /setTimeout/);

    process.stdout.write("bootstrap-server self-check passed\n");
  } finally {
    await new Promise((resolve, reject) => server.close((err) => (err ? reject(err) : resolve())));
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
