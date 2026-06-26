const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const BUNDLE_DIR = path.join(ROOT, "work", "million_cn", "jadx", "resources", "assets", "bundle");
const PACK_CARD_DIR = path.join(ROOT, "work", "million_cn", "jadx", "resources", "assets", "pack", "148", "card");
const SAVE_DIR = path.join(
  ROOT,
  "work",
  "million_cn",
  "sdcard_dump",
  "sdcard",
  "Android",
  "data",
  "com.square_enix.million_cn",
  "files",
  "save"
);
const MASTER_CARD = path.join(SAVE_DIR, "database", "master_card");
const FACE_DIR = path.join(SAVE_DIR, "download", "image", "face");
const ADV_DIR = path.join(SAVE_DIR, "download", "image", "adv");

function readBundle(name) {
  return fs.readFileSync(path.join(BUNDLE_DIR, name), "utf8");
}

function tagValues(xml, tag) {
  // ponytail: regex is enough for these fixed bundle samples; use an XML parser if this becomes a general tool.
  return [...xml.matchAll(new RegExp(`<${tag}>\\s*([^<]*?)\\s*</${tag}>`, "g"))]
    .map((match) => match[1].trim())
    .filter(Boolean);
}

function tagBlocks(xml, tag) {
  return [...xml.matchAll(new RegExp(`<${tag}>[\\s\\S]*?</${tag}>`, "g"))].map(
    (match) => match[0]
  );
}

function readString(buffer, pos, end) {
  const length = buffer.readUInt32BE(pos);
  if (length > end - pos - 4) {
    throw new Error(`bad string length ${length} at ${pos}`);
  }
  return {
    value: buffer.slice(pos + 4, pos + 4 + length).toString("utf8"),
    next: pos + 4 + length,
    length,
  };
}

function parseMasterCard(file) {
  const buffer = fs.readFileSync(file);
  const count = buffer.readUInt32BE(0);
  const offsets = Array.from({ length: count }, (_, index) => buffer.readUInt32BE(4 + index * 4));
  assert.equal(offsets[0], 4 + count * 4);

  function parseRecord(index) {
    const start = offsets[index];
    const end = index + 1 < count ? offsets[index + 1] : buffer.length;
    const u32 = [];
    const strings = [];
    let pos = start;

    function readU32() {
      const value = buffer.readUInt32BE(pos);
      u32.push({ pos: pos - start, value });
      pos += 4;
      return value;
    }

    function readPrefixedString() {
      const result = readString(buffer, pos, end);
      strings.push({ pos: pos - start, value: result.value });
      pos = result.next;
      return result.value;
    }

    readU32();
    readU32();
    for (let i = 0; i < 6; i += 1) {
      readPrefixedString();
    }

    let guard = 0;
    while (pos < end && guard < 200) {
      guard += 1;
      const maybeLength = buffer.readUInt32BE(pos);
      const remaining = end - pos - 4;
      const bytes = maybeLength <= remaining ? buffer.slice(pos + 4, pos + 4 + maybeLength) : null;
      const plausibleString = bytes && maybeLength < 1000 && !bytes.includes(0);
      if (plausibleString) {
        readPrefixedString();
      } else {
        readU32();
      }
    }

    assert.equal(pos, end);
    return {
      index: index + 1,
      start,
      end,
      masterId: u32[0].value,
      name: strings[0]?.value || "",
      u32Values: u32.map((entry) => entry.value),
    };
  }

  const records = offsets.map((_, index) => parseRecord(index));
  return {
    count,
    records,
    byMasterId: new Map(records.map((record) => [record.masterId, record])),
  };
}

function fileStatus(file) {
  try {
    return { exists: true, bytes: fs.statSync(file).size };
  } catch {
    return { exists: false, bytes: 0 };
  }
}

function packHasAlias(packFile, alias) {
  try {
    return fs.readFileSync(packFile).includes(Buffer.from(alias, "ascii"));
  } catch {
    return false;
  }
}

function resourceProof(master, masterId) {
  const record = master.byMasterId.get(masterId);
  if (!record) {
    return null;
  }
  const recordNumbers = new Set(record.u32Values);
  const imageIds = [masterId, masterId + 5000].filter((id) => recordNumbers.has(id));
  const packFile = path.join(PACK_CARD_DIR, `card${masterId}_0.pack`);
  return {
    masterId,
    recordIndex: record.index,
    imageIds,
    pack: fileStatus(packFile),
    resources: imageIds.map((imageId) => ({
      imageId,
      face: fileStatus(path.join(FACE_DIR, `face_${imageId}`)),
      adv: fileStatus(path.join(ADV_DIR, `adv_chara${imageId}`)),
      packFaceAlias: packHasAlias(packFile, `face_${imageId}`),
      packAdvAlias: packHasAlias(packFile, `adv_chara${imageId}`),
    })),
  };
}

function collectPairs(file, blockName) {
  const xml = readBundle(file);
  return tagBlocks(xml, blockName)
    .map((block) => ({
      serialId: tagValues(block, "serial_id")[0] || "",
      masterCardId: Number(tagValues(block, "master_card_id")[0] || 0),
    }))
    .filter((entry) => entry.masterCardId);
}

function main() {
  const master = parseMasterCard(MASTER_CARD);
  const localBattlePlayer = readBundle("local_battle_player.xml");
  const leaderSerials = tagValues(localBattlePlayer, "leader_serial_id");
  const battleResultPairs = collectPairs("local_battle_result.xml", "user_card");
  const eventLeaderPairs = collectPairs("local_users_event_list.xml", "leader_card");
  const battleAreaIds = tagValues(readBundle("local_battle_area.xml"), "master_card_id").map(Number);
  const directIds = [...new Set([...battleResultPairs, ...eventLeaderPairs].map((entry) => entry.masterCardId))];
  const proofIds = [9, 101, 22, 116, 179, 30].filter((id) => directIds.includes(id) || battleAreaIds.includes(id));
  const proofs = proofIds.map((id) => resourceProof(master, id)).filter(Boolean);
  const recordsContainingLeaderSerial = master.records
    .filter((record) => record.u32Values.includes(Number(leaderSerials[0])))
    .map((record) => record.masterId);

  assert.deepEqual(leaderSerials, ["2367"]);
  assert.equal(master.byMasterId.has(2367), false);
  assert.deepEqual(recordsContainingLeaderSerial, []);
  assert.ok(proofs.length >= 2);
  for (const proof of proofs.slice(0, 2)) {
    assert.ok(proof.pack.exists);
    assert.ok(proof.resources.length >= 2);
    for (const resource of proof.resources) {
      assert.ok(resource.face.exists);
      assert.ok(resource.adv.exists);
      assert.equal(resource.packFaceAlias, true);
      assert.equal(resource.packAdvAlias, true);
    }
  }

  console.log(`# master/resource map proof`);
  console.log(`master_card_records=${master.count}`);
  console.log(`local_battle_player.leader_serial_id=${leaderSerials.join(",")}`);
  console.log(`leader_serial_id_as_master_id=${master.byMasterId.has(Number(leaderSerials[0]))}`);
  console.log(`master_records_containing_leader_serial=${recordsContainingLeaderSerial.join(",") || "none"}`);
  console.log("");
  console.log(`sample direct serial/master pairs:`);
  for (const entry of battleResultPairs.slice(0, 2)) {
    console.log(`- local_battle_result user_card serial_id=${entry.serialId} master_card_id=${entry.masterCardId}`);
  }
  for (const entry of eventLeaderPairs.slice(0, 3)) {
    console.log(`- local_users_event_list leader_card serial_id=${entry.serialId} master_card_id=${entry.masterCardId}`);
  }
  console.log("");
  console.log(`resource checks:`);
  for (const proof of proofs) {
    console.log(`- master_card_id=${proof.masterId} record_index=${proof.recordIndex} pack=${proof.pack.exists ? proof.pack.bytes : "missing"}`);
    for (const resource of proof.resources) {
      console.log(
        `  image_id=${resource.imageId} face=${resource.face.exists ? resource.face.bytes : "missing"} ` +
          `adv=${resource.adv.exists ? resource.adv.bytes : "missing"} ` +
          `pack_aliases=${resource.packFaceAlias && resource.packAdvAlias}`
      );
    }
  }
}

main();
