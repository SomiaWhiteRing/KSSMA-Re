# `/connect/app/roundtable/edit` native schema/path card (2026-08-09)

## Frontier

At recovery time, the historical accepted flow reached `/connect/app/roundtable/edit?move=1` and scene `10100`, but that generic scene-forward response left the round table empty. The previous working assumption was that tapping the empty table should enter deck editing; D1 later deprecated that assumption by entering `_DeckScene` directly through scene `83200`.

## Static chain

- `_RoundTableScene::initModel(SceneInitializer)` at `0x0036f8fc` matches the direct body child `roundtable_edit` (string at `0x003e15f8`), passes its first child to `_RoundTableEditTagParser::parse`, then initializes `_CircleTableModel`. Its other accepted parent is `save_deck_card` (string at `0x003d3a70`).
- `_RoundTableEditTagParser::parse(TiXmlElement*)` at `0x0030ded8` walks direct siblings and accepts exactly:
  - `ex_gauge` (string at `0x003dfb30`) -> integer at tag data `+0x00`; absent/empty remains `0`.
  - `leader_card` (string at `0x003dd348`) -> `String` at `+0x04`; absent/empty remains an empty string.
  - `deck_cards` (string at `0x003ddf6c`) -> comma-split `vector<String>` at `+0x0c`; absent/empty remains an empty vector.
- `_CircleTableModel::init(smart_ptr<_RoundTableEditTagData>)` at `0x001d10c0` copies:
  - tag `+0x0c` to model `+0x4c`, then calls `_CircleTableModel::createDeck` at `0x001d0ffc`;
  - tag `+0x04` to model `+0x60`.
- `_CircleTableModel::getMap()` at `0x001d1ac0` exposes model `+0x4c` as `deckCards` and model `+0x60` as `leader`. It also exposes `lockCards`, `totalHp`, `totalAtk`, `totalCost`, `leader_sel`, `result`, and `errorMessage`.
- `layout_roundtable.xml` binds the `main` `ae_deck` control to `deckCards`; there is no edit/select button in that layout.
- `_RoundTableScene::update` at `0x0036fb6c` handles only `back` and `main`. A positive `main` selection is bounds-checked against model `+0x4c`, resolves that owned-card serial, and opens card detail. With an empty vector it returns without a route or scene transition.

## Entry and save path

- `_TownModel::card(bool)` at `0x001e7b0c` calls `_CircleTableModel::edit()` at `0x001d1984`.
- `edit()` builds `move=1` (string at `0x003d357c`) and calls `Model::connect(72, ...)`; route id `72` maps to `roundtable/edit` at `0x003d9b54`.
- `_DeckScene::initModel` at `0x0033c6c8` and `_CardSelectScene::initModel` at `0x003333d4` both accept `roundtable_edit`, pass its first child through the same parser, and initialize `_CircleTableModel`.
- The closed deck-editor entry is therefore `/roundtable/edit -> <roundtable_edit> -> scene 83200 (_DeckScene)`. The current server's scene `10100` selects `_RoundTableScene` instead and cannot expose editing.
- `_DeckScene::ConnectSave::exec` at `0x0033c52c` calls `_CircleTableModel::save()` at `0x001d159c`, which sends `C=<12-slot comma list>` and `lr=<leader serial>` through connect id `74`; id `74` maps to `cardselect/savedeckcard` at `0x003d9b78`.
- The save response parent is `save_deck_card`. `_SaveDeckCardTagParser::parse` at `0x0030e0ac` consumes `result` (integer), `error_message` (string), `leader_card` (string), and comma-separated `deck_cards`. Save response construction and persistence remain a separate frontier.

## Value-domain boundary

`deck_cards` is a 12-slot comma-separated list. Each slot is an owned-card serial string or the literal `empty` (string at `0x003d3ba4`). Those entries populate the `deckCards` model; `createDeck`, `calcStatus`, and card-detail selection all consume this representation.

`leader_card` is one owned-card serial string and maps to `leader`. The clean runtime sources already exist: `cards.activeDeckId`, the matching `cards.decks[].cardInstanceIds`, and `profile.leaderSerialId`. Missing deck slots are padded to 12 with `empty`. `ex_gauge` is parsed, but this init path does not prove a stronger value source than the current zero baseline.

## Falsified hypothesis

`empty round table -> tap main -> card/deck selection scene` is false for the accepted client. The only `main` branch requires an existing `deckCards` entry and opens card detail. Adding a blind tap or local UI/state patch cannot prove a deck-edit path.

## Minimal schema candidate (not runtime-approved)

```xml
<roundtable_edit>
  <ex_gauge>0</ex_gauge>
  <leader_card>1</leader_card>
  <deck_cards>1,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty</deck_cards>
</roundtable_edit>
```

This candidate uses the current active deck and leader as its only value source. With scene `83200` it is sufficient to test the first visible/editable frame; it must not be presented as a save-path fix.

## Runtime closure and next frontier

- D1 proved scene `83200` needs no additional direct child beyond the parser's three accepted fields for the first visible/editable frame. Artifact: `work/kssma-flow-deck-builder-entry-smoke-deck-builder-entry-1`.
- D2 proved leader `(1090,270)` invokes local `change_mode_leader_select`, disables the right button group, leaves the deck rail active, emits no `/connect/app/*` route for three seconds, and keeps the client alive. Artifact: `work/kssma-flow-deck-builder-leader-mode-smoke-deck-builder-leader-mode-2`.
- Save validation, response behavior, and persistence. The request keys are known, but they are deliberately outside the entry-only round.

The next bounded round is D3 static-only recovery of the card-selection entry, selected-index source, exact tap coordinates, and return-to-DeckScene state. It must stop before an emulator trial if the calling convention remains incomplete, and it must not implement `/cardselect/savedeckcard` or persistence.
