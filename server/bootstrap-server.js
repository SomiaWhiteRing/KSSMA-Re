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
const LOGIN_TUTORIAL_XML = readBundledXml("local_forward_tutorial.xml", CHECK_INSPECTION_OK_XML);
const WEB_STUB_HTML = [
  "<!doctype html>",
  '<html lang="zh-CN">',
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width,initial-scale=1">',
  "<title>KSSMA local web stub</title>",
  '<body style="font:18px sans-serif;padding:24px;background:#f5f1e8;color:#241b12">',
  "<h1>Local web stub</h1>",
  "<p>The original service web page is offline. This local stub keeps the client in the reconstructed runtime.</p>",
  '<p><a href="sceneto://2100">Back to game</a></p>',
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
const MASTERDATA_SAMPLES = Object.fromEntries(
  Object.entries(MASTERDATA_ROUTE_FILES).map(([route, relativePath]) => [
    route,
    {
      relativePath,
      bytes: readSampleSaveFile(relativePath),
    },
  ])
);

function getLoginOkXml() {
  // ponytail: default to the safe stub; opt into native scene payloads only when debugging that path.
  const loginResponse = (process.env.LOGIN_RESPONSE || "").trim().toLowerCase();
  if (loginResponse === "tutorial") {
    return LOGIN_TUTORIAL_XML;
  }
  if (loginResponse === "sample") {
    return LOGIN_OK_XML;
  }
  return CHECK_INSPECTION_OK_XML;
}

function getLoginXmlSource(loginXml) {
  if (loginXml === LOGIN_TUTORIAL_XML) {
    return "assets/bundle/local_forward_tutorial.xml";
  }
  if (loginXml === LOGIN_OK_XML) {
    return "assets/bundle/local_battle_player.xml";
  }
  return "minimal";
}

function createServer() {
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
      return sendHtml(res, 200, WEB_STUB_HTML);
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
  getLoginOkXml,
  getLoginXmlSource,
  parseConnectAppBody,
  parsePortList,
  CHECK_INSPECTION_OK_XML,
  LOGIN_TUTORIAL_XML,
  LOGIN_OK_XML,
  MASTERDATA_ROUTE_FILES,
  MASTERDATA_SAMPLES,
  WEB_STUB_HTML,
  readContentFile,
  readSampleSaveFile,
};
