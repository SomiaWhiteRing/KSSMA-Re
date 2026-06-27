Route:
  /connect/app/exploration/get_floor

Field path:
  response/body/get_floor/bg -> _GetFloorTagParser::parse -> _ExplorationModel::init(GetFloorTagData) -> exp_model.bgName -> layout_exploration_main.xml exploration_bg.bgName

Frontier:
  User-visible exploration_main background is wrong after entering a floor. The current server value is <bg>exp_sarch</bg>.

Schema card:
  work/exploration-get-floor-schema-card-20260627.md

Consumer:
  layout_exploration_main.xml binds <exploration_bg name="bg_front" model="exp_model"> with param bgName=bgName.

Value sources checked:
  - work/million_cn/apktool/assets/bundle/layout_exploration_main.xml | confirms bgName is consumed by exploration_bg, not a cosmetic server-only field.
  - work/million_cn/apktool/assets/bundle/rule_resource.xml | scene exploration_main scene_id 3005 preloads exp_sarch.png and exploration.png.
  - work/million_cn/apktool/assets/bundle/rule_resource.xml | scene exploration_area scene_id 3002 preloads exp_map_bg.png and exploration_place.png.
  - work/million_cn/sdcard_dump/.../save/download/rest | contains exp_sarch, exp_map_bg, exploration, and exploration_place resources.

Confirmed values:
  - None yet. exp_sarch is confirmed only as an available exploration_main resource, not as the correct stage background for this local floor.

Candidate values:
  - exp_sarch | currently loaded by scene 3005 and accepted by runtime | missing original-area value proof; user report says the visible result is wrong.
  - exp_map_bg | loaded by exploration_area scene 3002 and exists in save dump | missing proof that exploration_main exploration_bg can use it safely from get_floor.bg.
  - exploration_place | loaded by exploration_area scene 3002 and exists in save dump | likely place-view/map art, not proven as bgName.

Rejected values:
  - None yet. No runtime one-field background check has been run for this frontier.

Minimal runtime candidate:
  XML:
    Change only /connect/app/exploration/get_floor <bg> after a stronger value source is found.
  One variable changed:
    get_floor.bg only.
  Expected observable:
    exploration_main background changes without changing route sequence or floor hierarchy.

Open questions:
  - Which master/appdata field maps area_id=0/floor_id=2 to the original bg value?
  - Does exploration_bg dynamically load any save/download/rest resource by name, or only resources predeclared for scene 3005?
  - Is exp_sarch a generic exploration effect/search layer while another place resource should sit behind it?
