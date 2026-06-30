# Player owner card bootstrap card

## Frontier

`exploration-levelup-smoke` reached `/connect/app/town/lvup_status`, but the client
crashed before the AP/BC allocation request.

Runtime artifact:

```text
work/kssma-flow-exploration-levelup-smoke-levelup-pointsetting-runtime-2
```

Crash evidence:

```text
SIGSEGV at _UserCard::isCardNull()+5
_CPlayer::getUserCard(String)+64
_CardManager::getCardEyeImage(smart_ptr<_UserCard>)+20
_AnmAeLvUpStatus::_AnmAeLvUpStatus()+476
```

The level-up allocation/status page tries to draw the player's current leader card. The
local player save had `leader_serial_id=0` and an empty owned-card list, so the card lookup
returned a null card.

## Native parser evidence

- `_HeaderTagParser::parse` parses `<your_data>` into the shared header player data.
- `_YourDataTagParser::parse` stores parsed `owner_card_list` at `_YourDataTagData + 0x74`.
- `_OwnerCardListTagParser::parse` iterates `<user_card>` children and calls
  `_UserCardTagParser::parse(...)` for each card.
- `_CPlayer::updatePlayerData()` reads `header -> your_data -> owner_card_list`, creates
  `_UserCard` objects, and installs them into the global player/card manager state.
- `_CPlayer::createUserCardList(...)` maps cards by `serial_id`; therefore
  `<leader_serial_id>` must match one owned `<user_card><serial_id>`.

This is a shared player-data path, not a level-up-specific body field.

## Adopted local baseline

Use the bundled leader-card sample shape from:

```text
work/million_cn/jadx/resources/assets/bundle/local_users_event_list.xml
```

Baseline card:

```text
serial_id=1
master_card_id=22
lv=36
lv_max=36
hp=5620
power=4340
```

`master_card_id=22` is already present in local master/resource samples, and the same sample
uses it as a `leader_card`.

## Product change

- `server/data/player/default-save.json` and `server/data/player/local-save.json` now contain
  one owned card instance with `serialId=1`, `masterCardId=22`.
- `profile.leaderSerialId=1`.
- `server/bootstrap-server.js` renders:

```xml
<your_data>
  <leader_serial_id>1</leader_serial_id>
  <owner_card_list>
    <user_card>
      <serial_id>1</serial_id>
      <master_card_id>22</master_card_id>
      ...
    </user_card>
  </owner_card_list>
</your_data>
```

## Checks

Low-cost checks:

```powershell
node .\server\test-bootstrap-server.js
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario self-check -Tag levelup-owner-card-selfcheck
```

Runtime target:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-levelup-smoke -Tag levelup-owner-card-runtime
```

Runtime `work/kssma-flow-exploration-levelup-smoke-levelup-owner-card-runtime` confirmed
the crash is gone and the allocation page is visible. A later run confirmed OK emits:

```text
/connect/app/town/pointsetting ap=3 bc=0
```

Success is `/connect/app/town/pointsetting` after `/town/lvup_status`, with no
`_UserCard::isCardNull` crash.
