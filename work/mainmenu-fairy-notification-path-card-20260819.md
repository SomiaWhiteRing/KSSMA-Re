# Main-menu Fairy Notification Path Card, 2026-08-19

## Frontier

`login/mainmenu refresh -> top-left fairy status -> tap -> /connect/app/menu/fairyselect`

The server already keeps shared fairy raids and can render the fairy selection
response, but it did not publish the state which makes the original main-menu
entry visible.

## Accepted client path

- `assets/bundle/layout_mainmenu.xml` declares `stat_fairy name="fairy" ...
  visible="false" command="fairy"` and the accepted `framein` behaviors open it.
- `_AnmStatusFairyAppearance::action(unsigned long)` at `0x0025fe9d` and
  `_AnmStatusFairyAppearance::task()` at `0x0025ff95` read
  `_CPlayer::isFairyAppearance()` through the player vtable.
- `_MainMenu::Fairy::exec(int)` at `0x003546c9` calls
  `_TownModel::fairy()` at `0x001e7a55`.
- `_TownModel::fairy()` reuses `_FairyModel::selection()` at `0x001d8bb1`.
  The accepted server route for this command is
  `/connect/app/menu/fairyselect`, whose next scene is `29200`.

## XML and player-state path

- `_YourDataTagParser::parse(TiXmlElement*)` at `0x00312d5d` contains the
  `fairy_appearance` literal. Its matching branch at `0x00313170` stores the
  parsed integer into `_YourDataTagData +0x38` at `0x00313486`.
- `_CPlayer::updatePlayerData()` at `0x001f0611` reads
  `_YourDataTagData +0x38` at `0x001f0ef4`, normalizes a non-zero value to a
  boolean, and stores it at `_CPlayer +0x84` at `0x001f0efe`.
- `_CPlayer::isFairyAppearance()` at `0x001ee42d` reads the same byte at
  `_CPlayer +0x84`.

Therefore the required response field is:

```xml
<header>
  <your_data>
    <fairy_appearance>1</fairy_appearance>
  </your_data>
</header>
```

`1` means at least one unexpired active fairy is visible to the current LAN
account, whether discovered by that account or another enabled account. `0`
means no visible live fairy.

## Reward-box sibling path

`_MainMenuTagParser::parse` at `0x0030471d` separately parses
`<mainmenu><rewards>` into `_MainMenuTagData +0x10`; `_TownModel::init` copies
it to `+0x30`, and `_TownModel::getMap` exposes `rewards`. The layout has an
independent `main_reward name="reward_box" command="reward"` component, whose
accepted route is `/connect/app/menu/rewardbox`.

This field is the count of pending reward notices for the current account. It
must not be folded into `fairy_appearance`: a defeated raid no longer counts as
a live fairy, while its unclaimed contributor reward must keep the reward box
available.

`event_type` is deliberately unchanged. Its parser is known, but no direct UI
semantics have been closed for this flow.

## Current wrong server path

- `renderYourDataXml` omitted `fairy_appearance`.
- `renderMainmenuFields` omitted `rewards`.
- Login and both main-menu refresh handlers did not read the shared raid
  registry before creating their XML.

Consequently, `/connect/app/menu/fairyselect` could return live shared raids
when called directly, but the original client had no main-menu state telling it
to expose the entry.

## Product patch boundary

Compute one per-account notification snapshot from the shared raid registry:

- `fairy_appearance = visible active raid count > 0`
- `rewards = pending contributor reward count`

Pass that snapshot into the existing login/main-menu serializers. Reusing the
original parser, player flag, layout component, command, and selection route is
more reliable than forcing a layout visibility flag or adding a new client
event.

## Minimum observable

Server self-check must prove all four states:

1. neither live raid nor reward -> `fairy_appearance=0`, `rewards=0`;
2. own live raid -> `fairy_appearance=1`;
3. friend's live raid -> `fairy_appearance=1`;
4. defeated raid with an unclaimed contribution reward ->
   `fairy_appearance=0`, `rewards>0`.

Client acceptance is the main-menu screenshot showing the original top-left
fairy status followed by a tap which emits `/connect/app/menu/fairyselect`.
