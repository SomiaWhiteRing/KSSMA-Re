const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const SAVE_DOWNLOAD = path.join(
  ROOT,
  "work",
  "million_cn",
  "sdcard_dump",
  "sdcard",
  "Android",
  "data",
  "com.square_enix.million_cn",
  "files",
  "save",
  "download"
);
const OUT_DIR = path.join(ROOT, "work", "exploration-media-preview");
const KEY = Buffer.from("A1dPUcrvur2CRQyl", "utf8");
const PNG_MAGIC = Buffer.from("89504e470d0a1a0a", "hex");

const NAME_PATTERNS = [
  /exp/i,
  /explor/i,
  /map/i,
  /place/i,
  /bg/i,
  /sarch/i,
  /search/i,
  /dungeon/i,
  /field/i,
  /floor/i,
  /area/i,
  /btl/i,
];

function decodeResource(input) {
  const decipher = crypto.createDecipheriv("aes-128-ecb", KEY, null);
  return Buffer.concat([decipher.update(input), decipher.final()]);
}

function pngSize(buffer) {
  assert.equal(buffer.subarray(0, PNG_MAGIC.length).equals(PNG_MAGIC), true);
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

function discoverRestCandidates() {
  const restDir = path.join(SAVE_DOWNLOAD, "rest");
  return fs
    .readdirSync(restDir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => NAME_PATTERNS.some((pattern) => pattern.test(name)))
    .sort((a, b) => a.localeCompare(b, "en"))
    .map((name) => ["rest", name]);
}

function safeDecodePng(source, name) {
  try {
    const encrypted = fs.readFileSync(source);
    const decoded = decodeResource(encrypted);
    if (!decoded.subarray(0, PNG_MAGIC.length).equals(PNG_MAGIC)) {
      return { skipped: true, reason: "not-png" };
    }
    return { encrypted, decoded, size: pngSize(decoded) };
  } catch (error) {
    return { skipped: true, reason: `${error.name}: ${error.message}`, name };
  }
}

function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const knownEncrypted = fs.readFileSync(path.join(SAVE_DOWNLOAD, "pack", "mainbg", "mainbg_an_0_0"));
  const knownDecoded = fs.readFileSync(path.join(ROOT, "work", "decrypted-mainbg", "mainbg_an_0_0.png"));
  const decodedKnown = decodeResource(knownEncrypted);
  assert.equal(decodedKnown.equals(knownDecoded), true, "resource decode self-check failed");

  const candidates = discoverRestCandidates();
  const manifest = [];
  const skipped = [];
  for (const [dir, name] of candidates) {
    const source = path.join(SAVE_DOWNLOAD, dir, name);
    const result = safeDecodePng(source, name);
    if (result.skipped) {
      skipped.push({
        name,
        source: path.relative(ROOT, source).replaceAll("\\", "/"),
        reason: result.reason,
      });
      continue;
    }

    const outFile = path.join(OUT_DIR, `${name}.png`);
    fs.writeFileSync(outFile, result.decoded);
    manifest.push({
      name,
      source: path.relative(ROOT, source).replaceAll("\\", "/"),
      output: path.relative(ROOT, outFile).replaceAll("\\", "/"),
      encryptedBytes: result.encrypted.length,
      pngBytes: result.decoded.length,
      width: result.size.width,
      height: result.size.height,
    });
  }

  fs.writeFileSync(
    path.join(OUT_DIR, "manifest.json"),
    `${JSON.stringify({ generatedAt: new Date().toISOString(), candidates: candidates.length, manifest, skipped }, null, 2)}\n`
  );

  console.log(`decoded=${manifest.length}`);
  console.log(`skipped=${skipped.length}`);
  for (const entry of manifest) {
    console.log(`${entry.name} ${entry.width}x${entry.height} ${entry.output}`);
  }
}

main();
