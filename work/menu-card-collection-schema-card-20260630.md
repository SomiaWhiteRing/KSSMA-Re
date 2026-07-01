Route: `/connect/app/menu/cardcollection`

Frontier: Menu page card collection entry reached the route and response, then crashed while drawing the collection picker/list.

Static anchor: `_CardCollection::initModel(SceneInitializer)` and `_CardCollectionTagParser::parse(TiXmlElement*)` in `librooneyj.so`.

Native owner:

- `_CardCollection::initModel(SceneInitializer)` at `0x0032d18c` scans response body children for `card_collection`.
- After finding `card_collection`, it passes `FirstChildElement()` to `_CardCollectionTagParser::parse(...)` at `0x002f5804`.
- `_CardCollectionModel::init(...)` at `0x001ced90` copies parsed vectors into model offsets `+0x30`, `+0x3c`, and `+0x48`.
- `layout_card_collection.xml` binds `collection_picker` and `card_list_adapter`; `_CardCollection::setupPicker()` and `setupCardTable(int)` consume model vector `+0x30`.

Expected parent:

- `<body><card_collection>...</card_collection></body>`

Confirmed fields:

- `card_library` | comma-separated integer IDs | required for the current smoke | parser string at `0x003ddef4`; copied to model vector `+0x30`; consumed by `setupPicker()` / `setupCardTable(int)`.
- `lvmax_library` | comma-separated integer IDs | optional for current smoke | parser string at `0x003ddf04`; copied only when non-empty to model vector `+0x3c`.
- `holo_library` | comma-separated integer IDs | optional for current smoke | parser string at `0x003ddf14`; copied only when non-empty to model vector `+0x48`.

Model/layout consumers:

- `_CardCollection::setupPicker()` at `0x0032e118` builds the picker from local master card categories, intersects category cards with `CardCollectionModel + 0x30`, then puts data as `collection_picker`.
- `_CardCollection::setupCardTable(int)` at `0x0032e41c` uses the selected category, `CardCollectionModel + 0x30`, and optional `+0x3c/+0x48` to populate `card_list_adapter`.
- The prior runtime crash in `work/kssma-flow-menu-buttons-route-smoke-20260630-234353` was `_PickerAdapter::getItem(int)` from `_Picker::draw`, consistent with an empty picker/list.

Minimal XML candidate:

```xml
<body>
  <card_collection>
    <card_library>22</card_library>
    <lvmax_library></lvmax_library>
    <holo_library></holo_library>
  </card_collection>
</body>
```

Value source:

- `22` is the accepted default owned `masterCardId` in `server/data/player/default-save.json`.
- Future work should derive this from real owned cards as acquisition is implemented.

Rejected shapes:

- Empty `<body></body>` / scene-only response: reached scene `23100` but crashed while drawing card collection.
- Direct `<card_library>` under body without `<card_collection>`: rejected by `_CardCollection::initModel`, which searches for the `card_collection` parent first.

Observable for runtime check:

- `flow -Scenario menu-buttons-route-smoke` should open card collection, capture its screenshot, return to menu, and continue to later menu entries without `SIGSEGV`.

Open questions:

- Complete collection content, completion card presentation, and lvmax/holo acquisition semantics remain outside the menu-entry smoke.
