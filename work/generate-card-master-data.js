const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const SOURCE = path.join(
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
  "database",
  "master_card"
);
const OUTPUT = path.join(ROOT, "server", "data", "game", "card-master.json");
const SOURCE_SHA256 = "7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF";
const RECORD_COUNT = 480;

function extractCards(buffer) {
  assert.equal(
    crypto.createHash("sha256").update(buffer).digest("hex").toUpperCase(),
    SOURCE_SHA256,
    "master_card source SHA-256 changed"
  );

  const count = buffer.readUInt32BE(0);
  assert.equal(count, RECORD_COUNT);
  const offsets = Array.from({ length: count }, (_, index) => buffer.readUInt32BE(4 + index * 4));
  assert.equal(offsets[0], 4 + count * 4);
  assert.ok(offsets.every((offset, index) => index === 0 || offset > offsets[index - 1]));
  assert.ok(offsets.at(-1) < buffer.length);

  const cards = offsets.map((start, index) => {
    const end = index + 1 < count ? offsets[index + 1] : buffer.length;
    let position = start;

    function readU32() {
      assert.ok(position + 4 <= end, `record ${index + 1} integer exceeds boundary`);
      const value = buffer.readUInt32BE(position);
      position += 4;
      return value;
    }

    function skipString() {
      const length = readU32();
      assert.ok(position + length <= end, `record ${index + 1} string exceeds boundary`);
      position += length;
    }

    // ponytail: decode only deck-validation fields, but consume every serialized field so schema drift fails closed.
    const masterCardId = readU32();
    readU32(); // countryId
    for (let field = 0; field < 6; field += 1) {
      skipString();
    }

    const cost = readU32();
    for (let field = 0; field < 11; field += 1) {
      readU32();
    }
    const characterId = readU32();
    for (let field = 0; field < 3; field += 1) {
      readU32();
    }
    skipString(); // growName
    skipString(); // growthRateText
    for (let field = 0; field < 13; field += 1) {
      readU32();
    }

    assert.equal(position, end, `record ${index + 1} was not consumed exactly`);
    return { masterCardId, characterId, cost };
  });

  for (const card of cards) {
    assert.ok(Number.isSafeInteger(card.masterCardId) && card.masterCardId > 0);
    assert.ok(Number.isSafeInteger(card.characterId) && card.characterId > 0);
    assert.ok(Number.isSafeInteger(card.cost) && card.cost > 0);
  }
  assert.equal(new Set(cards.map((card) => card.masterCardId)).size, RECORD_COUNT);
  assert.equal(new Set(cards.map((card) => card.characterId)).size, RECORD_COUNT);
  assert.ok(cards.every((card) => card.characterId === card.masterCardId));
  assert.deepEqual(cards.find((card) => card.masterCardId === 9), {
    masterCardId: 9,
    characterId: 9,
    cost: 3,
  });
  assert.deepEqual(cards.find((card) => card.masterCardId === 22), {
    masterCardId: 22,
    characterId: 22,
    cost: 10,
  });
  return cards;
}

function main() {
  const mode = process.argv[2];
  assert.ok(mode === "--write" || mode === "--check", "usage: node work/generate-card-master-data.js --write|--check");
  const cards = extractCards(fs.readFileSync(SOURCE));
  const output = `${JSON.stringify({ schemaVersion: 1, cards }, null, 2)}\n`;

  if (mode === "--write") {
    fs.writeFileSync(OUTPUT, output, "utf8");
  } else {
    assert.equal(fs.readFileSync(OUTPUT, "utf8"), output, "checked-in card master differs from generated data");
  }

  console.log(JSON.stringify({
    ok: true,
    mode: mode.slice(2),
    sourceSha256: SOURCE_SHA256,
    records: cards.length,
    characterIdsUnique: true,
    characterIdEqualsMasterCardId: true,
    minCost: Math.min(...cards.map((card) => card.cost)),
    maxCost: Math.max(...cards.map((card) => card.cost)),
  }));
}

main();
