Route:
  /connect/app/exploration/get_floor

Field paths:
  response/body/get_floor/bg -> _GetFloorTagParser::parse -> _ExplorationModel::init(GetFloorTagData) -> exp_model.bgName -> layout_exploration_main.xml exploration_bg.bgName
  response/body/get_floor/bgm -> _GetFloorTagParser::parse -> _ExplorationModel::init(GetFloorTagData) -> exp_model.bgmName -> layout_exploration_main.xml exp_bgm.bgmName -> _ExpBgmComponent::playBgm

Frontier:
  User-visible exploration_main background is wrong after entering a floor, and the stage BGM was missing.
  Current accepted server value for BGM is <bgm>sarch1</bgm>.
  Current server background choice is region-based, not per internal area row.

Schema card:
  work/exploration-get-floor-schema-card-20260627.md

Consumer:
  layout_exploration_main.xml binds <exploration_bg name="bg_front" model="exp_model"> with param bgName=bgName.
  layout_exploration_main.xml binds <exp_bgm name="bgm" model="exp_model"> with param bgmName=bgmName.
  Native _ExpBgmComponent::playBgm prefixes "bgm_" before calling AudioMan::playBgm, so the XML value must be the short suffix.
  Native _AnmExpWalk::setPropertyValues also consumes bgName and can crash while loading an invalid image key.

Value sources checked:
  - work/million_cn/apktool/assets/bundle/layout_exploration_main.xml | confirms bgName is consumed by exploration_bg, not a cosmetic server-only field.
  - work/million_cn/apktool/assets/bundle/rule_resource.xml | scene exploration_main scene_id 3005 preloads exp_sarch.png and exploration.png.
  - work/million_cn/apktool/assets/bundle/rule_resource.xml | scene exploration_area scene_id 3002 preloads exp_map_bg.png and exploration_place.png.
  - work/million_cn/sdcard_dump/.../save/download/rest | contains exp_sarch, exp_map_bg, exploration, and exploration_place resources.
  - work/extract-exploration-media-preview.js | decrypts save/download/rest candidates offline after self-checking against mainbg_an_0_0.
  - work/exploration-media-preview/contact-sheet.png | visual triage sheet for 52 decoded candidate PNGs.

Confirmed values:
  - bgm=sarch1 | static native evidence shows playBgm builds bgm_sarch1, and download/sound/bgm_sarch1.ogg exists.
  - bg=battle_ef_bg15 | decoded PNG is a full sea/coast background; runtime reached exploration_main and screenshot work/kssma-runtime-exploration-media-bg15-main.png shows a proper sea/coast scene instead of UI-sheet fragments.

Candidate values:
  - region background map | current server maps the six outer wiki regions to visually matched decoded backgrounds: 人魚の断崖=battle_ef_bg15, 燐光の湖=battle_ef_bg03, 錯乱の平原=battle_ef_bg12, 叡智の草原=battle_ef_bg08, 猛獣の砂丘=battle_ef_bg17, 祝福を授ける山=battle_ef_bg00. This is content matching from contact-sheet.png, not canonical masterdata proof.
  - battle_ef_bg00..17 | decoded as full scene backgrounds; use only with region/master evidence before treating any one value as official.
  - exp_map_bg | loaded by exploration_area scene 3002 and exists in save dump | missing proof that exploration_main exploration_bg can use it safely from get_floor.bg.
  - exploration_place | loaded by exploration_area scene 3002 and exists in save dump | likely place-view/map art, not proven as bgName.

Rejected values:
  - bg=exp_sarch | safe but visually wrong as a floor background; decoded PNG is an exploration UI atlas, not a stage background.
  - bg=exploration | runtime entered exploration_main but screenshot work/kssma-runtime-exploration-bg-main2.png showed black/UI-sheet fragments, not a valid stage background.
  - bg=bg | runtime sent /connect/app/exploration/get_floor, then crashed. Logcat work/kssma-runtime-exploration-media-bg2-main2-logcat.txt shows _AnmExpWalk::setPropertyValues -> rooney::res::loadImage -> jni_loadTexture.
  - bgm=bgm_sarch1 | rejected by static evidence: _ExpBgmComponent::playBgm adds "bgm_" itself, causing a likely double-prefix lookup and matching the observed missing BGM.

Minimal runtime candidate:
  XML:
    Keep /connect/app/exploration/get_floor <bg> selected by the outer region, not by every internal area row.
    Keep /connect/app/exploration/get_floor <bgm> at sarch1.
  One variable changed:
    Next background round may change a single region's get_floor.bg only after a decoded visual candidate is selected.
  Expected observable:
    exploration_main background changes without changing route sequence or floor hierarchy.
    BGM should use the existing bgm_sarch1.ogg asset through the native bgm_ prefix path.

Open questions:
  - Which master/appdata field maps the outer region/current area request to the original bg value?
  - Which battle_ef_bgXX image officially belongs to each outer region?
  - Does _AnmExpWalk require the same bgName as exploration_bg, or is bgName overloaded for both the walk animation and rear background?
