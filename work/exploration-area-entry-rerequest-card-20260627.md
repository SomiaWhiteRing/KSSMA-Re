Route: `/connect/app/exploration/area`
Frontier: floor-list return should reuse the known-good main-menu -> area-list request path.
Static anchor: `_ExplorationModel::area()` at `librooneyj.so+0x001d63c0`.
Native owner: `_ExplorationModel`.

Parser/request path:
- `_ExplorationModel::area()` constructs an empty `std::map<String,String>` on the stack.
- `0x001d63de..0x001d63e4` sets `r0=this`, `r1=0x14`, `r2=&emptyParams`, then calls `Model::connect(int,map)` at `0x001e16e4`.
- Native route string table contains `exploration/area` at `0x003d98b4`.
- Existing runtime evidence maps route id `0x14` to `POST /connect/app/exploration/area?cyt=1`, showing `Local Area`.

Request parameters:
- Empty map. No request keys are inserted by `_ExplorationModel::area()`.

Callback/model behavior:
- After `Model::connect(0x14, emptyParams)`, `_ExplorationModel::area()` writes `1` to `_ExplorationModel+0x2c` and calls `Model::setSync(true)`.
- `_ExplorationModel::update(TiXmlElement)` already parses the area response and calls `_ExplorationModel::init(smart_ptr<_ExplorationAreaTagData>)`; prior runtime evidence shows this produces the working `Local Area` entry path.

Return-path reuse candidate:
- Floor-list return path currently branches through `_ExplorationArea::update` at `0x00341538`.
- Product patch should replace the local-only return rebuild at this point with:
  - clear the floor-list latch,
  - load the current `_ExplorationModel*` from `_ExplorationArea+0x5c`,
  - call `_ExplorationModel::area()`,
  - call `LayoutScene::trigger(model)` at `0x001f3eb4`,
  - leave `_ExplorationArea+0x3c` in area-wait mode (`1`) while the response comes back.

Rejected shapes:
- `area_list_sp` behavior-only hooks are already rejected by runtime evidence.
- `createAreaList()` vector-only rebuild is already rejected by runtime evidence.
- Do not use `0x001f4200` or `0x000c6b81`; both were recorded as bad anchors.

Minimal runtime candidate:
- Builder: `python .\work\build-exploration-area-return-rerequest.py`
- Output: `work/librooneyj-exploration-area-return-rerequest.so`
- Expected observable: after floor-list return, server receives another `/connect/app/exploration/area`, then screenshot shows non-empty `Local Area`.

Open questions:
- If the re-request appears but the screenshot remains empty, the next frontier is the area-response completion path after a return-triggered request, not the return button itself.
