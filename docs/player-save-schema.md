# Player Save Schema

This file documents the temporary JSON player save used by the local bootstrap server.
It is a JSON-backed database shape, not the final storage engine.

## Sources

- Local client sample: `work/million_cn/jadx/resources/assets/bundle/local_battle_player.xml`
  proves `your_data` fields such as `gold`, `cp`, `town_level`, `ap/current`, `ap/max`,
  `ap/interval_time`, `bc/current`, `bc/max`, `max_card_num`, `free_ap_bc_point`,
  `friendship_point`, `country_id`, `ex_gauge`, and `gacha_ticket`.
- Local knowledge base: `work/external-data/normalized/kssma-external.jsonl`.
  The zh-Fandom `新手指南` extraction records AP recovery at 1 per 3 minutes, BC recovery at
  1 per minute, level cap 350, level-up ability points, friendship gacha cost 200 points,
  card cap 350, and friend cap 30.
- Local knowledge base: `work/external-data/normalized/fc2-exploration-regions.json` and
  `work/exploration-fc2-mechanics-card-20260627.md` record exploration AP costs, EXP/Gold,
  required moves, area counts, guardian data, and next-region evidence.
- Client layouts under `work/million_cn/*/assets/bundle/` prove future player-owned surfaces:
  cards/decks, friends, gacha, items, story, fairy/boss battle, factors, and compound state.

## Shape

- `account`: account identity and login metadata.
- `profile`: display name, faction, level, EXP, town level, and greeting.
- `resources`: AP, BC, and SUPER gauges. AP/BC include current, max, base max, regen interval,
  and last regen timestamp.
- `progression`: unspent/allocated AP-BC points and level-up point rules.
- `currencies`: Gold, MC, friendship points, and gacha bonus points.
- `items`: consumables and tickets currently visible in local docs/client samples.
- `cards`: owned card instances, cap, album flags, deck definitions, and protection flags.
- `friends`: friend list, cap, requests, likes, and daily delete counter.
- `gacha`: costs and draw history.
- `exploration`: current region/floor, per-floor moves, per-region unlock/clear/progress,
  per-floor unlock/clear/progress, guardian/factor/item/encounter placeholders.
- `battle`: normal/factor/fairy battle counters and fairy discovery history.
- `stories`: main and side story progress.
- `tutorial`: tutorial completion flags.
- `notifications`: device tokens.
- `server`: session and revision numbers.
- `stats`: aggregate counters useful for future achievements/debugging.

## Current Runtime Use

Only exploration walking currently mutates this save:

- Routes that draw the global player HUD now read `your_data` from the same save:
  `/connect/app/login`, `/connect/app/mainmenu/update`, `/connect/app/mainmenu`,
  `/connect/app/exploration/area`, `/connect/app/exploration/floor`,
  `/connect/app/exploration/get_floor`, and successful `/connect/app/exploration/explore`.
  This keeps level/rank, AP, BC, Gold, max cards, friendship points, country, SUPER gauge,
  and gacha ticket synchronized across main menu and exploration surfaces.
- Exploration stage bodies use `profile.nextExp` for `<next_exp>`. The local save also stores
  accumulated `profile.exp`, but no direct response field for "current total EXP" is wired yet;
  do not invent one until native/schema evidence proves where the client reads it.
- `/connect/app/exploration/explore` increments `exploration.movesByFloor[floorKey]`.
- The same step spends AP from `resources.ap.current` and adds step rewards to
  `profile.exp` and `currencies.gold`.
- The same mutation also updates `exploration.floors[floorKey]`, the containing
  `exploration.regions[regionId]`, `exploration.currentRegionId`,
  `exploration.currentFloorKey`, and `stats.explorationMoves`.
- `/connect/app/exploration/area` now lists only regions unlocked by the player save.
  The area response still carries `prog_area`; no unproven area-lock XML field is emitted.
- `/connect/app/exploration/floor` now lists only unlocked floors in the requested region.
  A later pass can restore locked-but-visible rows if runtime evidence proves the client
  presentation path for `<unlock>0</unlock>`.
- `/connect/app/exploration/explore` refuses locked floors and returns the local AP-shortage
  scene when `resources.ap.current` is below the floor cost; those failure paths do not mutate
  moves, EXP, Gold, or AP.
- Successful `/connect/app/exploration/explore` responses include updated header `your_data`
  after applying AP cost and rewards. The body `<gold>` and `<get_exp>` remain the one-step
  rewards; header `your_data/gold` is the player's total Gold after the step.
- Flow runs use an artifact-local `player-save.json`; manual play uses ignored
  `server/data/player/local-save.json`.

## Open Fields

Many fields are intentionally structural placeholders until their route/schema is recovered.
Do not wire a placeholder into a response just because it exists here. Add response fields only
when the client parser or a successful runtime flow proves the field is needed.
