# Paid gacha retry path card (2026-08-09)

## Frontier

Close one already-present product edge without changing protocol data:

```text
paid result page -> retry -> confirmation -> second /connect/app/gacha/buy -> second draw/result
```

## Accepted entry and visible result

- The accepted paid flow reaches `/connect/app/gacha/buy` with decrypted `product_id=2`, `bulk=0`, and `auto_build=0`, receives scene `9200`, and reaches the visible result page.
- `work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-rest-select-paid-2/screenshots/gacha-result-after-touch.png` shows the original top-right `再扭一次` control.
- `layout_gacha_drawresult.xml` declares button `gacha`, command `retry`, at logical `(442,37)` and makes it visible only through `button_visible_cp`.

## Native path

- `_GachaModel::getMap()` at `0x001defdc` exposes `gachaType` from model `+0x44`.
- `_GachaDrawResult::update` at `0x0034e8a0` compares that value at `0x0034e900`; type `1` uses the back-only behavior, while other types use the paid behavior with retry.
- `_GachaDrawResult::Retry::exec(int)` at `0x0034e22c` opens the existing confirmation dialog.
- After confirmation, `_GachaDrawResult::update` at `0x0034e9c4` reuses the held product-content vector and calls `_GachaModel::draw` (`0x001dec94` / `0x001def74`). That path emits the same route id already mapped to `/connect/app/gacha/buy`.
- The existing flow coordinates already map the retry button to device `(1090,95)` and the affirmative dialog button to `(440,418)`.

## Correct-path reuse

The retry action preserves the original product id, bulk flag, auto-build flag, confirmation dialog, draw scene, and result callback. Reusing this full client path is stronger than adding a second select-page button action or manually calling the buy endpoint.

The rejected alternatives for this round are:

- more `gacha_select/xml_contents` layout guessing;
- treating the empty round table as a deck-edit affordance;
- calling `/gacha/buy` directly from the flow without clicking the native retry UI.

## Bounded runtime round

- **Hypothesis:** with an isolated save seeded to `600 MC`, one paid draw leaves `300 MC`; retry confirmation emits a second `/gacha/buy` for product `2`, and settlement leaves `0 MC`, three owned cards, two history entries, and two drawn cards.
- **One variable:** add one flow scenario. No server XML, settlement logic, native library, APK, or resource change.
- **Success:** two ordered `/gacha/buy` responses; the second reports serial `3`, owner count `3`, and `cardsDrawn=2`; a screenshot proves the second result transition; the client remains alive; the player-save assertion passes.
- **Non-goal:** insufficient-funds rejection, unknown products, bulk draws, random pools, deck editing, or save-deck persistence.
- **Stop:** retry emits no route, emits a non-gacha route, the confirmation cannot be reached with the accepted coordinates, or the runtime/server lifecycle consumes 15 minutes before the first core observable.
