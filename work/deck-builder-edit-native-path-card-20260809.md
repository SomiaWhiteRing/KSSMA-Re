# Deck-builder single-card edit native path card (2026-08-09)

## Round boundary

- Frontier: close the client-local path from the accepted DeckScene to card selection and back.
- Success: identify the entry, candidate index source, exact taps, mutation point, and return state.
- Non-goal: no emulator run, save click, `/cardselect/savedeckcard` response, persistence, or native patch.
- Stop: if any mode jump, button geometry, or candidate mapping remains ambiguous, do not start D4.

All conventions below are closed. D4 may use this path without a native change.

## Accepted entry state

`work/kssma-flow-deck-builder-entry-smoke-deck-builder-entry-1` proves the original path
`main menu -> /roundtable/edit move=1 -> scene 83200` and a visible `_DeckScene`. The accepted screenshot
`screenshots/deck-builder-entry.png` shows the normal 12-slot deck rail and the left `card select` tab. D2 separately
proves that the scene can perform a client-local mode change without a request; D3 does not reuse leader mode.

The D4 fixture must contain owned serials `[1,2]`, active deck `[1]`, and leader `1`. Serial `2` is the only owned
card outside the deck.

## Mode and entry path

- `_DeckLayout` starts with mode `0`. Its raw Thumb case table at `0x002b5950` is `52 29 02 91`; decode raw bytes,
  not GNU objdump's displayed halfwords. It maps mode `0 -> 0x002b59f4` and mode `1 -> 0x002b59a2`.
- Mode 0 runs the clip-37 button stored at wrapper `+148` / child `+152` (`0x002b59f4..0x002b5a34`). A hit returns
  code `5`.
- `_DeckScene::update` maps code `5` at `0x0033cfac` to behavior `slider_right`. `layout_deck_scene.xml` resets the
  slider, invokes `change_mode_card_sel`, runs the slider `right` action, and hides/disables the four right buttons.
- `_DeckLayout::changeMode` maps `change_mode_card_sel` to internal mode `1`; its raw table at `0x002b4b5e` is
  `03 54 87 3e 49`.
- The accepted 1280x720 frame uses logical-to-device `x = 100 + 2.25*x`, `y = 2.25*y`. Decrypted `rja_deck_edit`
  clip 37 is `32x312` and is placed at logical `(-4,4)`; its exact device-center tap is `(127,360)`.

Clicking an empty deck slot is not an entry path. The mode-0 DeckStage branch checks the selected slot, and a null
slot falls through without changing mode. Scene `83100` (`_CardSelectScene`) is also not involved; this edit stays in
scene `83200`.

## Candidate source and tap

- `_DeckCardList::createFromDeck` at `0x002b497c` calls `checkDeck` at `0x002b46ac`, then `sort` at `0x002b4864`.
- `checkDeck` copies the player's owned-card vector and erases each serial already referenced by the active deck.
  With owned `[1,2]` and deck `[1]`, serial `2` is the sole candidate, so it remains index `0` regardless of sort.
- `_DeckCardList::init(0)` builds candidate buttons at scale `0.3`. For index 0 the button is logical
  `x=33.1, y=77.45, w=46, h=65`; its center is about `(56.1,109.95)`.
- The final slider position has no persistent offset. `_ButtonGroup::action(right)` at `0x0038911c` subtracts 480
  from child bases while `_AutoScroller` advances `0 -> 480`; `_ButtonGroup::task` restores the same net positions.
- The candidate's exact device-center tap is therefore `(226,247)`.

On a normal tap, `_DeckCardList` returns code `4`. `_DeckLayout::getSelected` calls
`_DeckCardList::getTappedCard` at `0x002b60be`, then `_DeckStage::setCardAtBlankOnDeck` at `0x002b60c6`.
`setCardAtBlankOnDeck` scans the 12 slots in row-major order; with slot 0 occupied by serial `1`, it writes serial
`2` to slot 1. Its success path rebuilds the card list and combo state at `0x002b60ec..0x002b615c`, but remains in
mode `1`. It does not return to normal deck mode automatically.

## Explicit return path

- Mode 1 runs the clip-38 button stored at wrapper `+140` / child `+144` (`0x002b5b34..0x002b5b74`). A hit returns
  code `6`.
- The constructor queries movie clip 38 at `0x002b702a`, then places it at logical
  `x=480-width, y=(320-height)/2` at `0x002b715e..0x002b7186`.
- Decrypted `rja_deck_edit` clip 38 uses dependency 0 atlas rect `(486,196,32,312)`. Its hit rectangle is logical
  `x=448..480, y=4..316`; the exact device-center tap is `(1144,360)`.
- `_DeckScene::update` maps code `6` at `0x0033cf8e` to `slider_left`. The layout resets, invokes
  `change_mode_deck_edit`, runs `left`, and restores the normal button group. The client remains in scene `83200`.

## D4 observable

The bounded D4 sequence is `(127,360) -> (226,247) -> (1144,360)`. Each action is client-local and must have a
cursor-scoped three-second window with no `/connect/app/*` request and a live RooneyJ activity. Screenshots must show:

1. card-selection mode with the sole serial-2/master-9 candidate;
2. the candidate accepted while still in card-selection mode;
3. normal DeckScene restored, slot 0 unchanged, and slot 1 changed from `empty` to serial 2.

The artifact-local player save must be byte-for-byte unchanged because D4 never taps `decide`. Request capture and
successful `<save_deck_card>` semantics belong to D5.

## Rejected paths

- Do not tap a blank deck slot to enter card mode.
- Do not expect selection to auto-return to normal mode.
- Do not open scene `83100` or resurrect scene `10100` for this edit.
- Do not infer a saved deck from the in-memory slot change.

Reusing this complete native path preserves the client's own filtering, first-empty-slot mutation, mode state, and
visual transition. A local UI/state patch would bypass at least one of those observables and would not establish the
request-free edit edge.
