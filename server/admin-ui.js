"use strict";

const ADMIN_PLAYER_FIELDS = new Set([
  "name",
  "faction",
  "level",
  "exp",
  "nextExp",
  "apCurrent",
  "apMax",
  "bcCurrent",
  "bcMax",
  "gold",
  "mc",
  "friendshipPoint",
  "gachaTicket",
  "cardMax",
]);

const ADMIN_FAIRY_FIELDS = new Set([
  "fairyEnabled",
  "fairyEncounterRate",
  "fairyLevel",
  "fairyMaxHp",
  "fairyAttackPower",
  "fairyRewardGold",
  "fairyRewardExp",
  "fairyRewardDropRate",
  "fairyRewardCardPool",
  "fairyRewardCardsPerContributor",
  "fairyFinisherBonusCards",
  "fairyTimeLimitSeconds",
]);

const ADMIN_GACHA_PRODUCT_FIELDS = new Set(["productId", "cost", "pool"]);

const FACTIONS = new Set(["sword", "technique", "magic"]);
const MAX_COUNTER = 2147483647;

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function requirePlainObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object`);
  }
  return value;
}

function parseIntegerField(value, label, minimum, maximum) {
  const normalized = typeof value === "string" && /^-?\d+$/.test(value.trim())
    ? Number(value.trim())
    : value;
  if (!Number.isSafeInteger(normalized) || normalized < minimum || normalized > maximum) {
    throw new Error(`${label} must be an integer from ${minimum} to ${maximum}`);
  }
  return normalized;
}

function parseBooleanField(value, label) {
  if (typeof value !== "boolean") {
    throw new Error(`${label} must be true or false`);
  }
  return value;
}

function parseCardPoolField(value, label) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 480) {
    throw new Error(`${label} must contain 1 to 480 card rows`);
  }
  const seen = new Set();
  return value.map((row, index) => {
    const entry = requirePlainObject(row, `${label}[${index}]`);
    const unknown = Object.keys(entry).filter((key) => !["masterCardId", "weight"].includes(key));
    if (unknown.length) {
      throw new Error(`${label}[${index}] contains unsupported field: ${unknown.join(", ")}`);
    }
    const masterCardId = parseIntegerField(entry.masterCardId, `${label}[${index}].masterCardId`, 1, MAX_COUNTER);
    const weight = parseIntegerField(entry.weight, `${label}[${index}].weight`, 1, 1000000);
    if (seen.has(masterCardId)) {
      throw new Error(`${label} contains duplicate masterCardId ${masterCardId}`);
    }
    seen.add(masterCardId);
    return { masterCardId, weight };
  });
}

function applyAdminPlayerUpdate(playerSave, input) {
  const patch = requirePlainObject(input, "player update");
  const keys = Object.keys(patch);
  if (!keys.length) {
    throw new Error("player update must contain at least one field");
  }
  const unknown = keys.filter((key) => !ADMIN_PLAYER_FIELDS.has(key));
  if (unknown.length) {
    throw new Error(`unsupported player field: ${unknown.join(", ")}`);
  }

  const save = cloneJson(requirePlainObject(playerSave, "player save"));
  save.profile = save.profile || {};
  save.resources = save.resources || {};
  save.resources.ap = save.resources.ap || {};
  save.resources.bc = save.resources.bc || {};
  save.currencies = save.currencies || {};
  save.items = save.items || {};
  save.cards = save.cards || {};

  if (Object.hasOwn(patch, "name")) {
    if (typeof patch.name !== "string") {
      throw new Error("name must be text");
    }
    const name = patch.name.trim();
    if (!name || [...name].length > 20 || /[\u0000-\u001f\u007f]/.test(name)) {
      throw new Error("name must contain 1 to 20 visible characters");
    }
    save.profile.name = name;
  }

  if (Object.hasOwn(patch, "faction")) {
    if (!FACTIONS.has(patch.faction)) {
      throw new Error("faction must be sword, technique, or magic");
    }
    save.profile.faction = patch.faction;
    delete save.profile.countryId;
  }

  if (Object.hasOwn(patch, "level")) {
    const maxLevel = Math.max(parseIntegerField(save.profile.maxLevel ?? 350, "profile.maxLevel", 1, 9999), 1);
    save.profile.level = parseIntegerField(patch.level, "level", 1, maxLevel);
  }
  if (Object.hasOwn(patch, "exp")) {
    save.profile.exp = parseIntegerField(patch.exp, "exp", 0, MAX_COUNTER);
  }
  if (Object.hasOwn(patch, "nextExp")) {
    save.profile.nextExp = parseIntegerField(patch.nextExp, "nextExp", 0, MAX_COUNTER);
  }

  const apMax = Object.hasOwn(patch, "apMax")
    ? parseIntegerField(patch.apMax, "apMax", 0, 9999)
    : parseIntegerField(save.resources.ap.max ?? 0, "resources.ap.max", 0, 9999);
  const apCurrent = Object.hasOwn(patch, "apCurrent")
    ? parseIntegerField(patch.apCurrent, "apCurrent", 0, 9999)
    : parseIntegerField(save.resources.ap.current ?? 0, "resources.ap.current", 0, 9999);
  if (apCurrent > apMax) {
    throw new Error("apCurrent cannot exceed apMax");
  }
  if (Object.hasOwn(patch, "apMax")) save.resources.ap.max = apMax;
  if (Object.hasOwn(patch, "apCurrent")) save.resources.ap.current = apCurrent;

  const bcMax = Object.hasOwn(patch, "bcMax")
    ? parseIntegerField(patch.bcMax, "bcMax", 0, 9999)
    : parseIntegerField(save.resources.bc.max ?? 0, "resources.bc.max", 0, 9999);
  const bcCurrent = Object.hasOwn(patch, "bcCurrent")
    ? parseIntegerField(patch.bcCurrent, "bcCurrent", 0, 9999)
    : parseIntegerField(save.resources.bc.current ?? 0, "resources.bc.current", 0, 9999);
  if (bcCurrent > bcMax) {
    throw new Error("bcCurrent cannot exceed bcMax");
  }
  if (Object.hasOwn(patch, "bcMax")) save.resources.bc.max = bcMax;
  if (Object.hasOwn(patch, "bcCurrent")) save.resources.bc.current = bcCurrent;

  for (const [field, target] of [
    ["gold", "gold"],
    ["mc", "mc"],
    ["friendshipPoint", "friendshipPoint"],
  ]) {
    if (Object.hasOwn(patch, field)) {
      save.currencies[target] = parseIntegerField(patch[field], field, 0, MAX_COUNTER);
    }
  }

  if (Object.hasOwn(patch, "gachaTicket")) {
    save.items.gachaTicket = parseIntegerField(patch.gachaTicket, "gachaTicket", 0, 999999);
  }
  if (Object.hasOwn(patch, "cardMax")) {
    const ownedCount = Array.isArray(save.cards.instances) ? save.cards.instances.length : 0;
    const cardMax = parseIntegerField(patch.cardMax, "cardMax", 1, 10000);
    if (cardMax < ownedCount) {
      throw new Error(`cardMax cannot be lower than owned card count (${ownedCount})`);
    }
    save.cards.max = cardMax;
  }

  const nextExp = Number.isSafeInteger(save.profile.nextExp) ? save.profile.nextExp : 0;
  const exp = Number.isSafeInteger(save.profile.exp) ? save.profile.exp : 0;
  save.profile.percentage = nextExp > 0 ? Math.min(Math.floor((exp * 100) / nextExp), 100) : 0;
  return save;
}

function applyAdminFairyUpdate(runtimeConfig, input) {
  const patch = requirePlainObject(input, "fairy update");
  const keys = Object.keys(patch);
  if (!keys.length) {
    throw new Error("fairy update must contain at least one field");
  }
  const unknown = keys.filter((key) => !ADMIN_FAIRY_FIELDS.has(key));
  if (unknown.length) {
    throw new Error(`unsupported fairy field: ${unknown.join(", ")}`);
  }

  const config = cloneJson(requirePlainObject(runtimeConfig, "runtime config"));
  config.fairyEncounter = config.fairyEncounter || {};
  const fairy = config.fairyEncounter;

  if (Object.hasOwn(patch, "fairyEnabled")) {
    fairy.enabled = parseBooleanField(patch.fairyEnabled, "fairyEnabled");
  }
  if (Object.hasOwn(patch, "fairyEncounterRate")) {
    fairy.ratePercent = parseIntegerField(patch.fairyEncounterRate, "fairyEncounterRate", 0, 100);
  }
  if (Object.hasOwn(patch, "fairyLevel")) {
    fairy.level = parseIntegerField(patch.fairyLevel, "fairyLevel", 1, 999);
  }
  if (Object.hasOwn(patch, "fairyMaxHp")) {
    fairy.maxHp = parseIntegerField(patch.fairyMaxHp, "fairyMaxHp", 1, MAX_COUNTER);
  }
  if (Object.hasOwn(patch, "fairyAttackPower")) {
    fairy.attackPower = parseIntegerField(patch.fairyAttackPower, "fairyAttackPower", 1, MAX_COUNTER);
  }
  if (Object.hasOwn(patch, "fairyRewardGold")) {
    fairy.rewardGold = parseIntegerField(patch.fairyRewardGold, "fairyRewardGold", 0, MAX_COUNTER);
  }
  if (Object.hasOwn(patch, "fairyRewardExp")) {
    fairy.rewardExp = parseIntegerField(patch.fairyRewardExp, "fairyRewardExp", 0, MAX_COUNTER);
  }
  if (Object.hasOwn(patch, "fairyRewardDropRate")) {
    fairy.rewardDropRatePercent = parseIntegerField(
      patch.fairyRewardDropRate,
      "fairyRewardDropRate",
      0,
      100
    );
  }
  if (Object.hasOwn(patch, "fairyRewardCardPool")) {
    fairy.rewardCardPool = parseCardPoolField(patch.fairyRewardCardPool, "fairyRewardCardPool");
    delete fairy.rewardMasterCardId;
  }
  if (Object.hasOwn(patch, "fairyRewardCardsPerContributor")) {
    fairy.rewardCardsPerContributor = parseIntegerField(
      patch.fairyRewardCardsPerContributor,
      "fairyRewardCardsPerContributor",
      1,
      10
    );
  }
  if (Object.hasOwn(patch, "fairyFinisherBonusCards")) {
    fairy.finisherBonusCards = parseIntegerField(
      patch.fairyFinisherBonusCards,
      "fairyFinisherBonusCards",
      0,
      10
    );
  }
  if (Object.hasOwn(patch, "fairyTimeLimitSeconds")) {
    fairy.timeLimitSeconds = parseIntegerField(
      patch.fairyTimeLimitSeconds,
      "fairyTimeLimitSeconds",
      60,
      86400
    );
  }
  return config;
}

function applyAdminGachaUpdate(gachaConfig, input) {
  const patch = requirePlainObject(input, "gacha update");
  if (Object.keys(patch).length !== 1 || !Object.hasOwn(patch, "products")) {
    throw new Error("gacha update must contain only products");
  }
  if (!Array.isArray(patch.products) || !patch.products.length) {
    throw new Error("gacha products must be a non-empty array");
  }
  const config = cloneJson(requirePlainObject(gachaConfig, "gacha config"));
  if (!Array.isArray(config.products) || !config.products.length) {
    throw new Error("gacha config has no products");
  }
  const byId = new Map(config.products.map((product) => [product.productId, product]));
  const updatedIds = new Set();
  for (const [index, rawProduct] of patch.products.entries()) {
    const productPatch = requirePlainObject(rawProduct, `products[${index}]`);
    const unknown = Object.keys(productPatch).filter((key) => !ADMIN_GACHA_PRODUCT_FIELDS.has(key));
    if (unknown.length) {
      throw new Error(`products[${index}] contains unsupported field: ${unknown.join(", ")}`);
    }
    const productId = parseIntegerField(productPatch.productId, `products[${index}].productId`, 1, MAX_COUNTER);
    const product = byId.get(productId);
    if (!product) {
      throw new Error(`unknown gacha productId ${productId}`);
    }
    if (updatedIds.has(productId)) {
      throw new Error(`duplicate gacha productId ${productId}`);
    }
    updatedIds.add(productId);
    if (Object.hasOwn(productPatch, "cost")) {
      product.cost = parseIntegerField(productPatch.cost, `products[${index}].cost`, 0, MAX_COUNTER);
    }
    if (Object.hasOwn(productPatch, "pool")) {
      product.pool = parseCardPoolField(productPatch.pool, `products[${index}].pool`);
    }
  }
  return config;
}

function createAdminPoolRows(pool) {
  const rows = Array.isArray(pool) ? pool : [];
  const totalWeight = rows.reduce((sum, row) => sum + (Number.isSafeInteger(row?.weight) ? row.weight : 0), 0);
  return rows.map((row) => ({
    masterCardId: row.masterCardId,
    weight: row.weight,
    chancePercent: totalWeight > 0 ? Number(((row.weight * 100) / totalWeight).toFixed(4)) : 0,
  }));
}

function createAdminState(playerSave, system = {}, runtimeConfig = {}, gachaConfig = {}) {
  const save = requirePlainObject(playerSave, "player save");
  const cards = Array.isArray(save.cards?.instances) ? save.cards.instances : [];
  const decks = Array.isArray(save.cards?.decks) ? save.cards.decks : [];
  const regions = Object.values(save.exploration?.regions || {});
  const floors = Object.values(save.exploration?.floors || {});
  const fairy = runtimeConfig.fairyEncounter || {};
  const activeFairy = save.battle?.fairy?.active || null;
  return {
    ok: true,
    system: {
      project: "KSSMA-Re",
      mode: "LAN nostalgia runtime",
      savePath: system.savePath || "player/local-save.json",
      runtimeConfigPath: system.runtimeConfigPath || "server/runtime-config.json",
      listenPorts: Array.isArray(system.listenPorts) ? system.listenPorts : [],
      worldName: system.worldName || "Local Dev World",
      routeCount: Number.isSafeInteger(system.routeCount) ? system.routeCount : 0,
      explorationRegionCount: Number.isSafeInteger(system.explorationRegionCount) ? system.explorationRegionCount : 0,
      adminWritePolicy: system.adminWritePolicy || "loopback-only",
      accounts: Array.isArray(system.accounts) ? system.accounts : [],
      selectedAccountUserId: String(system.selectedAccountUserId || save.account?.userId || "1"),
    },
    player: {
      name: save.profile?.name || "Arthur",
      faction: save.profile?.faction || "sword",
      level: save.profile?.level || 1,
      maxLevel: save.profile?.maxLevel || 350,
      exp: save.profile?.exp || 0,
      nextExp: save.profile?.nextExp || 0,
      apCurrent: save.resources?.ap?.current || 0,
      apMax: save.resources?.ap?.max || 0,
      bcCurrent: save.resources?.bc?.current || 0,
      bcMax: save.resources?.bc?.max || 0,
      gold: save.currencies?.gold || 0,
      mc: save.currencies?.mc || 0,
      friendshipPoint: save.currencies?.friendshipPoint || 0,
      gachaTicket: save.items?.gachaTicket || 0,
      cardMax: save.cards?.max || 0,
    },
    fairy: {
      enabled: fairy.enabled === true,
      encounterRate: Number.isSafeInteger(fairy.ratePercent) ? fairy.ratePercent : 20,
      masterBossId: Number.isSafeInteger(fairy.masterBossId) ? fairy.masterBossId : 30024,
      name: fairy.name || "小龙女",
      level: Number.isSafeInteger(fairy.level) ? fairy.level : 1,
      maxHp: Number.isSafeInteger(fairy.maxHp) ? fairy.maxHp : 9660,
      attackPower: Number.isSafeInteger(fairy.attackPower) ? fairy.attackPower : 1200,
      rewardGold: Number.isSafeInteger(fairy.rewardGold) ? fairy.rewardGold : 300,
      rewardExp: Number.isSafeInteger(fairy.rewardExp) ? fairy.rewardExp : 5,
      rewardDropRate: Number.isSafeInteger(fairy.rewardDropRatePercent) ? fairy.rewardDropRatePercent : 100,
      rewardCardPool: createAdminPoolRows(fairy.rewardCardPool || [
        { masterCardId: Number.isSafeInteger(fairy.rewardMasterCardId) ? fairy.rewardMasterCardId : 600, weight: 1 },
      ]),
      rewardCardsPerContributor: Number.isSafeInteger(fairy.rewardCardsPerContributor) ? fairy.rewardCardsPerContributor : 1,
      finisherBonusCards: Number.isSafeInteger(fairy.finisherBonusCards) ? fairy.finisherBonusCards : 1,
      timeLimitSeconds: Number.isSafeInteger(fairy.timeLimitSeconds) ? fairy.timeLimitSeconds : 7200,
      activeSerialId: activeFairy?.serialId || "",
      activeHp: Number.isSafeInteger(activeFairy?.currentHp) ? activeFairy.currentHp : 0,
    },
    gacha: {
      products: (Array.isArray(gachaConfig.products) ? gachaConfig.products : []).map((product) => ({
        productId: product.productId,
        key: product.key || "",
        name: product.name || `产品 ${product.productId}`,
        currency: product.currency || "",
        currencyLabel: product.currencyLabel || product.currency || "",
        cost: Number.isSafeInteger(product.cost) ? product.cost : 0,
        drawCount: Number.isSafeInteger(product.drawCount) ? product.drawCount : 1,
        pool: createAdminPoolRows(product.pool),
      })),
    },
    progress: {
      ownedCards: cards.length,
      deckCount: decks.length,
      activeDeckId: save.cards?.activeDeckId || "",
      activeDeckCost: Number.isSafeInteger(system.activeDeckCost) ? system.activeDeckCost : null,
      unlockedRegions: regions.filter((region) => region?.unlocked).length,
      clearedRegions: regions.filter((region) => region?.cleared).length,
      knownFloors: floors.length,
      clearedFloors: floors.filter((floor) => floor?.cleared).length,
      currentRegionId: save.exploration?.currentRegionId ?? 0,
      currentFloorKey: save.exploration?.currentFloorKey || "未进入",
      battleWins: save.battle?.wins || 0,
      battleLosses: save.battle?.losses || 0,
      cardsDrawn: save.stats?.cardsDrawn || 0,
      explorationMoves: save.stats?.explorationMoves || 0,
      accountCount: Array.isArray(system.accounts) ? system.accounts.length : 0,
      activeRaidCount: Number.isSafeInteger(system.activeRaidCount) ? system.activeRaidCount : 0,
      pendingFairyRewardCount: Number.isSafeInteger(system.pendingFairyRewardCount) ? system.pendingFairyRewardCount : 0,
    },
    boundaries: [
      { name: "主菜单", status: "accepted", detail: "角色互动、背景、BGM、主入口已验收" },
      { name: "探索", status: "partial", detail: "层级、行走、AP、升级与普通完成已闭合；深层分支待恢复" },
      { name: "扭蛋 / 卡组", status: "partial", detail: "友情点、MC、扭蛋券与MC 11连产品池已配置；新增入口仍需客户端 flow 验收" },
      { name: "战斗 / 妖精 / 奖励", status: "partial", detail: "单账号单存活妖精、好友贡献与奖励箱协议已实现；好友列表到协战及领奖页面仍需客户端 flow 验收" },
    ],
  };
}

const ADMIN_UI_HTML = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>KSSMA-Re 王城管理终端</title>
  <style>
    :root{--ink:#18202a;--night:#111925;--blue:#2b647b;--ice:#77c8d6;--gold:#c8a557;--paper:#f3eddf;--paper2:#ded4bf;--red:#9f4141;--ok:#3a8a73}
    *{box-sizing:border-box}body{margin:0;color:var(--ink);font-family:"Microsoft YaHei","Yu Gothic UI",sans-serif;background:radial-gradient(circle at 20% 0,#244b5a 0,transparent 30%),linear-gradient(135deg,#101723,#22333e 48%,#111823);min-height:100vh}
    body:before{content:"";position:fixed;inset:0;pointer-events:none;opacity:.14;background-image:linear-gradient(30deg,transparent 48%,#fff 49%,transparent 51%),linear-gradient(150deg,transparent 48%,#fff 49%,transparent 51%);background-size:42px 72px}
    .shell{max-width:1180px;margin:auto;padding:26px 18px 54px}.mast{position:relative;overflow:hidden;color:white;border:1px solid #d4bd7a;background:linear-gradient(100deg,#16222d,#286175 60%,#18232e);box-shadow:0 16px 44px #0008,inset 0 0 0 3px #ffffff14;padding:28px 34px 24px;clip-path:polygon(0 0,97% 0,100% 50%,97% 100%,0 100%,2% 50%)}
    .mast:after{content:"MILLION ARTHUR";position:absolute;right:36px;bottom:-8px;font:700 44px Georgia,serif;letter-spacing:.08em;color:#ffffff0d}.kicker{color:#a9e5ec;font-size:12px;letter-spacing:.28em}.mast h1{font:700 clamp(26px,4vw,45px) Georgia,"Microsoft YaHei",serif;letter-spacing:.06em;margin:7px 0 4px;text-shadow:0 2px #000}.mast p{margin:0;color:#d7e7e7}.ribbon{display:inline-flex;align-items:center;gap:8px;margin-top:16px;padding:6px 12px;border:1px solid #d7bd70;background:#0005;color:#ffe3a0;font-size:12px;letter-spacing:.08em}.gem{width:10px;height:10px;background:var(--ice);transform:rotate(45deg);box-shadow:0 0 10px var(--ice)}
    .grid{display:grid;grid-template-columns:1.35fr .65fr;gap:18px;margin-top:18px}.panel{position:relative;background:linear-gradient(145deg,var(--paper),var(--paper2));border:1px solid #e7d9b9;box-shadow:0 11px 30px #0006,inset 0 0 0 3px #ffffff66;padding:20px}.panel:before,.panel:after{content:"";position:absolute;width:13px;height:13px;border:2px solid var(--gold);transform:rotate(45deg)}.panel:before{top:8px;left:8px}.panel:after{right:8px;bottom:8px}.panel h2{font:700 20px Georgia,"Microsoft YaHei",serif;letter-spacing:.05em;margin:0 0 4px}.sub{color:#52606b;font-size:13px;margin-bottom:18px}.form-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:13px}.field{display:flex;flex-direction:column;gap:5px}.field.wide{grid-column:span 2}.field label{font-size:12px;font-weight:700;letter-spacing:.04em;color:#44515c}.field input,.field select,.field textarea{width:100%;border:1px solid #91866e;background:#fffdf7;color:#1c2931;padding:10px 11px;font:inherit;outline:none;box-shadow:inset 0 1px 4px #0002}.field textarea{resize:vertical;min-height:112px;font-family:Consolas,monospace;line-height:1.55}.field input:focus,.field select:focus,.field textarea:focus{border-color:var(--blue);box-shadow:0 0 0 2px #3b829733}.divider{grid-column:1/-1;border:0;border-top:1px solid #ab9b7b;margin:5px 0}.actions{display:flex;align-items:end;gap:12px;grid-column:1/-1;margin-top:8px}.primary{cursor:pointer;border:1px solid #f1d489;color:white;background:linear-gradient(#387b8e,#225466);font-weight:700;letter-spacing:.08em;padding:11px 20px;box-shadow:inset 0 0 0 2px #ffffff24,0 4px 0 #173844}.primary:disabled{filter:grayscale(1);opacity:.6}.notice{min-height:20px;font-size:13px;color:#45545d}.notice.error{color:var(--red)}.notice.ok{color:var(--ok)}
    .stats{display:grid;grid-template-columns:1fr 1fr;gap:9px}.stat{background:#1c2a34;color:#eaf6f6;border-left:3px solid var(--gold);padding:11px}.stat b{display:block;color:#9fdce5;font-size:20px}.stat span{font-size:11px;color:#c4cbcb}.sys{margin-top:14px;border-top:1px solid #aa9e86;padding-top:11px;font-size:12px;line-height:1.8}.sys code{font-family:Consolas,monospace;color:#225466}.account-panel,.fairy-panel,.gacha-panel,.frontiers{grid-column:1/-1}.checkline{flex-direction:row;align-items:center;gap:10px;background:#fff7df;border:1px solid #bcae8d;padding:10px 12px}.checkline input{width:auto;accent-color:var(--blue);transform:scale(1.25)}.fairy-meta{grid-column:1/-1;color:#42515b;font-size:12px;background:#e7ddc8;padding:9px 11px;border-left:3px solid var(--blue)}.gacha-products{display:grid;grid-template-columns:1fr 1fr;gap:13px}.gacha-product{border:1px solid #aa9e86;background:#eee5d2;padding:13px;display:grid;grid-template-columns:1fr 1fr;gap:10px}.gacha-product h3{grid-column:1/-1;margin:0;color:#214b5c;font-size:16px}.gacha-product .pool{grid-column:1/-1}.product-meta{grid-column:1/-1;font-size:11px;color:#52606b}.boundary-list{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.boundary{background:#17232d;color:white;border-top:3px solid #667783;padding:13px;min-height:110px}.boundary.accepted{border-color:#50a98d}.boundary.partial{border-color:#d0a549}.boundary.frontier{border-color:#a55454}.boundary strong{display:block;margin-bottom:7px}.boundary p{font-size:12px;line-height:1.55;color:#cdd7d8;margin:0}.guard{margin-top:13px;padding:10px 12px;background:#fff6d7;border-left:3px solid var(--gold);font-size:12px;line-height:1.6}
    @media(max-width:850px){.grid,.gacha-products{grid-template-columns:1fr}.form-grid{grid-template-columns:1fr 1fr}.boundary-list{grid-template-columns:1fr 1fr}.mast{clip-path:none}.mast:after{display:none}}@media(max-width:520px){.form-grid,.boundary-list,.stats{grid-template-columns:1fr}.field.wide{grid-column:span 1}.actions{align-items:stretch;flex-direction:column}.primary{width:100%}}
  </style>
</head>
<body>
  <main class="shell">
    <header class="mast">
      <div class="kicker">LOCAL ARCHIVE / 王城管制室</div>
      <h1>KSSMA-Re 管理终端</h1>
      <p>扩散性百万亚瑟王 · 局域网怀旧服</p>
      <div class="ribbon"><i class="gem"></i><span id="world-name">LOCAL WORLD</span><span>·</span><span id="policy">读取中</span></div>
    </header>
    <section class="grid">
      <form class="panel account-panel" id="account-form">
        <h2>亚瑟账号管理</h2><div class="sub">客户端注册保持关闭；在这里创建局域网账号，并切换要编辑的独立存档</div>
        <div class="form-grid">
          <div class="field"><label for="account-select">当前编辑账号</label><select id="account-select"></select></div>
          <div class="field"><label for="account-login-id">新账号登录 ID</label><input id="account-login-id" maxlength="64" autocomplete="off" placeholder="例如 arthur02"></div>
          <div class="field"><label for="account-password">新账号密码</label><input id="account-password" type="password" minlength="8" maxlength="72" autocomplete="new-password"></div>
          <div class="field"><label for="account-name">玩家名称</label><input id="account-name" maxlength="20" placeholder="Arthur"></div>
          <div class="field"><label for="account-faction">阵营</label><select id="account-faction"><option value="sword">剑术之城</option><option value="technique">技巧之场</option><option value="magic">魔法之派</option></select></div>
          <div class="field wide"><label for="admin-token">局域网管理令牌（本机默认可留空）</label><input id="admin-token" type="password" autocomplete="off" placeholder="KSSMA_ADMIN_TOKEN"></div>
          <div class="actions"><button class="primary" id="account-create-button" type="submit">创建账号</button><div id="account-notice" class="notice" role="status" aria-live="polite"></div></div>
        </div>
        <div class="guard">账号密码只以 scrypt 哈希保存，不会回显。登录响应会签发账号绑定的本地会话 Cookie；原客户端的 CookieStore 会在后续玩法请求中自动回传，服务端据此按请求隔离账号与存档。未携带 Cookie 的旧调试请求仍按最近登录账号兼容；两台真实客户端的可见协战仍待验收。</div>
      </form>
      <form class="panel" id="player-form">
        <h2>亚瑟档案</h2><div class="sub">仅开放已被现有协议与客户端共同验证的字段</div>
        <div class="form-grid">
          <div class="field wide"><label for="name">玩家名称</label><input id="name" maxlength="20" required></div>
          <div class="field"><label for="faction">阵营</label><select id="faction"><option value="sword">剑术之城</option><option value="technique">技巧之场</option><option value="magic">魔法之派</option></select></div>
          <div class="field"><label for="level">等级</label><input id="level" type="number" min="1" max="350" required></div>
          <div class="field"><label for="exp">当前经验</label><input id="exp" type="number" min="0" required></div>
          <div class="field"><label for="nextExp">升级经验</label><input id="nextExp" type="number" min="0" required></div>
          <hr class="divider">
          <div class="field"><label for="apCurrent">AP 当前</label><input id="apCurrent" type="number" min="0" required></div>
          <div class="field"><label for="apMax">AP 上限</label><input id="apMax" type="number" min="0" required></div>
          <div class="field"><label for="bcCurrent">BC 当前</label><input id="bcCurrent" type="number" min="0" required></div>
          <div class="field"><label for="bcMax">BC 上限</label><input id="bcMax" type="number" min="0" required></div>
          <div class="field"><label for="gold">金币</label><input id="gold" type="number" min="0" required></div>
          <div class="field"><label for="mc">MC</label><input id="mc" type="number" min="0" required></div>
          <div class="field"><label for="friendshipPoint">友情点</label><input id="friendshipPoint" type="number" min="0" required></div>
          <div class="field"><label for="gachaTicket">扭蛋券</label><input id="gachaTicket" type="number" min="0" required></div>
          <div class="field"><label for="cardMax">持卡上限</label><input id="cardMax" type="number" min="1" required></div>
          <div class="actions"><button class="primary" id="save-button" type="submit">保存玩家设定</button><div id="notice" class="notice" role="status" aria-live="polite"></div></div>
        </div>
        <div class="guard">探索进度、持卡实例与卡组槽位在本版保持只读。它们存在跨字段约束，必须等对应 flow / native 契约闭合后再开放编辑。</div>
      </form>
      <aside class="panel">
        <h2>王城状态</h2><div class="sub">当前运行存档的只读摘要</div>
        <div class="stats" id="stats"></div>
        <div class="sys" id="system"></div>
      </aside>
      <form class="panel fairy-panel" id="fairy-form">
        <h2>妖精遭遇管制</h2><div class="sub">控制探索步进中的普通妖精事件；设为 100% 可用于复原验收</div>
        <div class="form-grid">
          <label class="field checkline" for="fairyEnabled"><input id="fairyEnabled" type="checkbox"><span>启用探索妖精遭遇</span></label>
          <div class="field"><label for="fairyEncounterRate">遭遇概率（%）</label><input id="fairyEncounterRate" type="number" min="0" max="100" step="1" required></div>
          <div class="field"><label for="fairyLevel">妖精等级</label><input id="fairyLevel" type="number" min="1" max="999" required></div>
          <div class="field"><label for="fairyMaxHp">妖精最大 HP</label><input id="fairyMaxHp" type="number" min="1" max="2147483647" required></div>
          <div class="field"><label for="fairyAttackPower">妖精攻击力</label><input id="fairyAttackPower" type="number" min="1" max="2147483647" required></div>
          <div class="field"><label for="fairyRewardGold">胜利金币</label><input id="fairyRewardGold" type="number" min="0" max="2147483647" required></div>
          <div class="field"><label for="fairyRewardExp">胜利经验</label><input id="fairyRewardExp" type="number" min="0" max="2147483647" required></div>
          <div class="field"><label for="fairyRewardDropRate">每个奖励位掉卡概率（%）</label><input id="fairyRewardDropRate" type="number" min="0" max="100" required></div>
          <div class="field"><label for="fairyRewardCardsPerContributor">每位贡献者卡牌数</label><input id="fairyRewardCardsPerContributor" type="number" min="1" max="10" required></div>
          <div class="field"><label for="fairyFinisherBonusCards">击杀者额外卡牌数</label><input id="fairyFinisherBonusCards" type="number" min="0" max="10" required></div>
          <div class="field"><label for="fairyTimeLimitSeconds">存活时限（秒）</label><input id="fairyTimeLimitSeconds" type="number" min="60" max="86400" required></div>
          <div class="field wide"><label for="fairyRewardCardPool">掉落卡牌池（每行 master_card_id:权重）</label><textarea id="fairyRewardCardPool" required spellcheck="false"></textarea></div>
          <div class="fairy-meta" id="fairy-meta">正在读取妖精基线…</div>
          <div class="actions"><button class="primary" id="fairy-save-button" type="submit">保存妖精设定</button><div id="fairy-notice" class="notice" role="status" aria-live="polite"></div></div>
        </div>
        <div class="guard">遭遇概率、等级、最大 HP、攻击力和卡牌奖励会快照到新遇到的妖精；已经出现的妖精保持其生成时数值，避免战斗中途被后台改写。只有实际攻击过的账号记为贡献者。</div>
      </form>
      <form class="panel gacha-panel" id="gacha-form">
        <h2>扭蛋产品与卡池</h2><div class="sub">友情点单抽、MC单抽、扭蛋券单抽和MC 11连共用原客户端抽卡/结果路径</div>
        <div class="gacha-products" id="gacha-products"></div>
        <div class="actions"><button class="primary" id="gacha-save-button" type="submit">保存扭蛋设定</button><div id="gacha-notice" class="notice" role="status" aria-live="polite"></div></div>
        <div class="guard">产品 ID、货币类型和抽取张数由已恢复协议固定；后台只开放价格与卡池权重。权重是相对值，例如 70/25/5 会显示为 70%/25%/5%。扭蛋始终出卡，不使用“空掉落”。</div>
      </form>
      <section class="panel frontiers">
        <h2>复原边界</h2><div class="sub">UI 中的状态不是完成宣言；以 flow artifact 和客户端可见迁移为准</div>
        <div class="boundary-list" id="boundaries"></div>
      </section>
    </section>
  </main>
  <script>
    const editable = ["name","faction","level","exp","nextExp","apCurrent","apMax","bcCurrent","bcMax","gold","mc","friendshipPoint","gachaTicket","cardMax"];
    const integerFields = new Set(editable.filter(function (name) { return name !== "name" && name !== "faction"; }));
    const fairyEditable = ["fairyEncounterRate","fairyLevel","fairyMaxHp","fairyAttackPower","fairyRewardGold","fairyRewardExp","fairyRewardDropRate","fairyRewardCardsPerContributor","fairyFinisherBonusCards","fairyTimeLimitSeconds"];
    const notice = document.getElementById("notice");
    const fairyNotice = document.getElementById("fairy-notice");
    const gachaNotice = document.getElementById("gacha-notice");
    const accountNotice = document.getElementById("account-notice");
    const saveButton = document.getElementById("save-button");
    const fairySaveButton = document.getElementById("fairy-save-button");
    const gachaSaveButton = document.getElementById("gacha-save-button");
    const accountCreateButton = document.getElementById("account-create-button");
    function setNotice(message, kind) { notice.textContent = message; notice.className = "notice " + (kind || ""); }
    function setFairyNotice(message, kind) { fairyNotice.textContent = message; fairyNotice.className = "notice " + (kind || ""); }
    function setGachaNotice(message, kind) { gachaNotice.textContent = message; gachaNotice.className = "notice " + (kind || ""); }
    function setAccountNotice(message, kind) { accountNotice.textContent = message; accountNotice.className = "notice " + (kind || ""); }
    function render(state) {
      editable.forEach(function (name) { document.getElementById(name).value = state.player[name]; });
      const accountSelect=document.getElementById("account-select");accountSelect.replaceChildren();
      state.system.accounts.forEach(function(account){const option=document.createElement("option");option.value=account.userId;option.textContent="#"+account.userId+" · "+account.name+" · "+account.loginId+(account.isLastLogin?"（最近登录）":"");accountSelect.append(option);});
      accountSelect.value=state.system.selectedAccountUserId;
      document.getElementById("fairyEnabled").checked = state.fairy.enabled;
      document.getElementById("fairyEncounterRate").value = state.fairy.encounterRate;
      document.getElementById("fairyLevel").value = state.fairy.level;
      document.getElementById("fairyMaxHp").value = state.fairy.maxHp;
      document.getElementById("fairyAttackPower").value = state.fairy.attackPower;
      document.getElementById("fairyRewardGold").value = state.fairy.rewardGold;
      document.getElementById("fairyRewardExp").value = state.fairy.rewardExp;
      document.getElementById("fairyRewardDropRate").value = state.fairy.rewardDropRate;
      document.getElementById("fairyRewardCardPool").value = formatPool(state.fairy.rewardCardPool);
      document.getElementById("fairyRewardCardsPerContributor").value = state.fairy.rewardCardsPerContributor;
      document.getElementById("fairyFinisherBonusCards").value = state.fairy.finisherBonusCards;
      document.getElementById("fairyTimeLimitSeconds").value = state.fairy.timeLimitSeconds;
      document.getElementById("fairy-meta").textContent = "当前设定：" + state.fairy.name + " / master_boss_id " + state.fairy.masterBossId + " · HP " + state.fairy.maxHp + " · ATK " + state.fairy.attackPower + " · 每奖励位 " + state.fairy.rewardDropRate + "% 掉卡 / 池内 " + state.fairy.rewardCardPool.length + " 张 · 基础位 ×" + state.fairy.rewardCardsPerContributor + " / 击杀额外位 ×" + state.fairy.finisherBonusCards + (state.fairy.activeSerialId ? " · 活跃 serial_id " + state.fairy.activeSerialId + " · 剩余 HP " + state.fairy.activeHp : " · 当前无活跃妖精");
      renderGachaProducts(state.gacha.products);
      document.getElementById("world-name").textContent = state.system.worldName;
      document.getElementById("policy").textContent = state.system.adminWritePolicy === "token" ? "令牌写入" : "仅本机写入";
      const rows = [
        [state.progress.ownedCards + " / " + state.player.cardMax, "持有卡牌"],
        [state.progress.unlockedRegions + " / " + state.system.explorationRegionCount, "开放秘境"],
        [state.progress.clearedFloors + " / " + state.progress.knownFloors, "已清楼层"],
        [(state.progress.activeDeckCost === null ? "?" : state.progress.activeDeckCost) + " / " + state.player.bcCurrent, "卡组 COST / 当前 BC"],
        [state.progress.explorationMoves, "探索步数"],
        [state.progress.cardsDrawn, "扭蛋次数"],
        [state.progress.battleWins + " / " + state.progress.battleLosses, "战斗胜负"],
        [state.progress.accountCount, "局域网账号"],
        [state.progress.activeRaidCount, "可见存活妖精"],
        [state.progress.pendingFairyRewardCount, "待领取妖精奖励"]
      ];
      const stats = document.getElementById("stats"); stats.replaceChildren();
      rows.forEach(function (row) { const box=document.createElement("div");box.className="stat";const b=document.createElement("b");b.textContent=row[0];const s=document.createElement("span");s.textContent=row[1];box.append(b,s);stats.append(box); });
      document.getElementById("system").innerHTML = "存档：<code></code><br>运行设定：<code></code><br>端口：<b></b><br>已知玩法 route：<strong></strong><br>当前楼层：<em></em>";
      const sys = document.getElementById("system");const codes=sys.querySelectorAll("code");codes[0].textContent=state.system.savePath;codes[1].textContent=state.system.runtimeConfigPath;sys.querySelector("b").textContent=state.system.listenPorts.join(", ");sys.querySelector("strong").textContent=state.system.routeCount;sys.querySelector("em").textContent=state.progress.currentFloorKey;
      const boundaries=document.getElementById("boundaries");boundaries.replaceChildren();
      state.boundaries.forEach(function (item) { const box=document.createElement("article");box.className="boundary "+item.status;const title=document.createElement("strong");title.textContent=item.name;const detail=document.createElement("p");detail.textContent=item.detail;box.append(title,detail);boundaries.append(box); });
    }
    function formatPool(pool) { return pool.map(function(row){return row.masterCardId + ":" + row.weight + "  # " + row.chancePercent + "%";}).join("\\n"); }
    function parsePool(text, label) {
      const rows=text.split(/\\r?\\n/).map(function(line){return line.replace(/#.*/,"").trim();}).filter(Boolean);
      if(!rows.length)throw new Error(label+"不能为空");
      return rows.map(function(line,index){const match=/^(\\d+)\\s*[:：,]\\s*(\\d+)$/.exec(line);if(!match)throw new Error(label+"第"+(index+1)+"行应为 master_card_id:权重");return {masterCardId:Number(match[1]),weight:Number(match[2])};});
    }
    function renderGachaProducts(products) {
      const root=document.getElementById("gacha-products");root.replaceChildren();
      products.forEach(function(product){const box=document.createElement("section");box.className="gacha-product";box.dataset.productId=product.productId;const title=document.createElement("h3");title.textContent="#"+product.productId+" · "+product.name;const cost=document.createElement("div");cost.className="field";const costLabel=document.createElement("label");costLabel.textContent="价格（"+product.currencyLabel+"）";const costInput=document.createElement("input");costInput.className="gacha-cost";costInput.type="number";costInput.min="0";costInput.required=true;costInput.value=product.cost;cost.append(costLabel,costInput);const meta=document.createElement("div");meta.className="product-meta";meta.textContent="固定抽取 "+product.drawCount+" 张 · 货币字段 "+product.currency;const pool=document.createElement("div");pool.className="field pool";const poolLabel=document.createElement("label");poolLabel.textContent="卡牌池（每行 master_card_id:权重）";const textarea=document.createElement("textarea");textarea.className="gacha-pool";textarea.required=true;textarea.spellcheck=false;textarea.value=formatPool(product.pool);pool.append(poolLabel,textarea);box.append(title,cost,meta,pool);root.append(box);});
    }
    async function load(accountUserId) {
      setNotice("正在读取存档…", "");
      const query=accountUserId?"?account_user_id="+encodeURIComponent(accountUserId):"";
      try { const response=await fetch("/admin/api/state"+query,{cache:"no-store"});const state=await response.json();if(!response.ok)throw new Error(state.error||"读取失败");render(state);setNotice("存档已载入", "ok");setFairyNotice("妖精设定已载入", "ok");setGachaNotice("扭蛋设定已载入", "ok");setAccountNotice("账号列表已载入", "ok"); }
      catch(error){setNotice(error.message,"error");setFairyNotice(error.message,"error");setGachaNotice(error.message,"error");setAccountNotice(error.message,"error");saveButton.disabled=true;fairySaveButton.disabled=true;gachaSaveButton.disabled=true;accountCreateButton.disabled=true;}
    }
    document.getElementById("account-select").addEventListener("change",function(){load(this.value);});
    document.getElementById("account-form").addEventListener("submit", async function (event) {
      event.preventDefault();accountCreateButton.disabled=true;setAccountNotice("正在创建独立存档…","");
      const payload={loginId:document.getElementById("account-login-id").value,password:document.getElementById("account-password").value,name:document.getElementById("account-name").value||"Arthur",faction:document.getElementById("account-faction").value};
      try { const response=await fetch("/admin/api/accounts",{method:"POST",headers:{"Content-Type":"application/json","X-KSSMA-Admin-Token":document.getElementById("admin-token").value},body:JSON.stringify(payload)});const state=await response.json();if(!response.ok)throw new Error(state.error||"创建失败");render(state);document.getElementById("account-password").value="";setAccountNotice("账号与独立存档已创建", "ok");setNotice("新账号存档已载入", "ok"); }
      catch(error){setAccountNotice(error.message,"error");}finally{accountCreateButton.disabled=false;}
    });
    document.getElementById("player-form").addEventListener("submit", async function (event) {
      event.preventDefault();saveButton.disabled=true;setNotice("正在原子写入…","");
      const payload={accountUserId:document.getElementById("account-select").value};editable.forEach(function(name){const value=document.getElementById(name).value;payload[name]=integerFields.has(name)?Number(value):value;});
      try { const response=await fetch("/admin/api/player",{method:"POST",headers:{"Content-Type":"application/json","X-KSSMA-Admin-Token":document.getElementById("admin-token").value},body:JSON.stringify(payload)});const state=await response.json();if(!response.ok)throw new Error(state.error||"保存失败");render(state);setNotice("玩家设定已保存，客户端下一次刷新数据时生效", "ok"); }
      catch(error){setNotice(error.message,"error");}finally{saveButton.disabled=false;}
    });
    document.getElementById("fairy-form").addEventListener("submit", async function (event) {
      event.preventDefault();fairySaveButton.disabled=true;setFairyNotice("正在原子写入…","");
      try { const payload={fairyEnabled:document.getElementById("fairyEnabled").checked};fairyEditable.forEach(function(name){payload[name]=Number(document.getElementById(name).value);});payload.fairyRewardCardPool=parsePool(document.getElementById("fairyRewardCardPool").value,"妖精卡池");const response=await fetch("/admin/api/fairy",{method:"POST",headers:{"Content-Type":"application/json","X-KSSMA-Admin-Token":document.getElementById("admin-token").value},body:JSON.stringify(payload)});const state=await response.json();if(!response.ok)throw new Error(state.error||"保存失败");render(state);setFairyNotice("妖精设定已保存，新探索步进立即生效", "ok"); }
      catch(error){setFairyNotice(error.message,"error");}finally{fairySaveButton.disabled=false;}
    });
    document.getElementById("gacha-form").addEventListener("submit", async function (event) {
      event.preventDefault();gachaSaveButton.disabled=true;setGachaNotice("正在原子写入…","");
      try { const products=Array.from(document.querySelectorAll(".gacha-product")).map(function(box){return {productId:Number(box.dataset.productId),cost:Number(box.querySelector(".gacha-cost").value),pool:parsePool(box.querySelector(".gacha-pool").value,"产品 #"+box.dataset.productId+" 卡池")};});const response=await fetch("/admin/api/gacha",{method:"POST",headers:{"Content-Type":"application/json","X-KSSMA-Admin-Token":document.getElementById("admin-token").value},body:JSON.stringify({products:products})});const state=await response.json();if(!response.ok)throw new Error(state.error||"保存失败");render(state);setGachaNotice("扭蛋价格与卡池已保存，新抽取立即生效", "ok"); }
      catch(error){setGachaNotice(error.message,"error");}finally{gachaSaveButton.disabled=false;}
    });
    load();
  </script>
</body>
</html>`;

module.exports = {
  ADMIN_FAIRY_FIELDS,
  ADMIN_PLAYER_FIELDS,
  ADMIN_UI_HTML,
  applyAdminFairyUpdate,
  applyAdminGachaUpdate,
  applyAdminPlayerUpdate,
  createAdminState,
};
