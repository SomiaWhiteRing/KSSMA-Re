# Mainmenu Button Route Card, 2026-06-30

Route frontier:
- Main menu and menu overlay buttons should no longer fall through to `/connect/app` 501.
- This card records only entry/back route skeletons, not full subsystem gameplay.

Static anchors:
- `work/million_cn/apktool/assets/bundle/layout_mainmenu.xml`
- `work/million_cn/apktool/assets/bundle/layout_menu.xml`
- `work/million_cn/apktool/assets/bundle/rule_scene.xml`
- `work/million_cn/apktool/lib/armeabi/librooneyj.so` route fragments
- bundled local XML samples:
- `local_gachaselect.xml`
- `local_gachacomp.xml`
- `local_battle_area.xml`

Confirmed main buttons:
- `gacha` -> `gacha/select/getcontents` -> scene `9100` (`gacha_select`), currently a safe minimal
  `<gacha_select><xml_contents><scroll_height>0</scroll_height></xml_contents></gacha_select>` skeleton.
  `local_gachaselect.xml` is not accepted for the entry smoke because it references missing local gacha images
  such as `gac_event_0`.
- `exploration` -> `exploration/area` -> scene `6100`, already implemented.
- `battle` -> `battle/area` -> scene `5100` (`battle_area`), body from `local_battle_area.xml`.
- `compound` main-menu button -> `card/exchange` with `mode=1` -> scene `7200` (`强化合成`) in runtime
  `mainmenu-buttons-route-smoke`; other compound/trunk routes remain skeleton second-level paths.
- `shop` -> `shop/shop` -> scene `8100` (`shop_item_scene`) skeleton.
- `menu` -> `menu/menulist` -> scene `20100` (`menu_select`) skeleton.
- `reward_box` -> `menu/rewardbox` -> scene `21100` (`menu_reward_box`) skeleton.
- status buttons:
  - card/friends/fairy routes are represented by menu/friend/fairy skeleton paths.
  - AP/BC did not expose an independent static `/connect/app` path from `layout_mainmenu.xml`; AP shortage and CP
    purchase screens remain represented by known scene routes `81100` and `8400` when reached through item/shop flow.

Confirmed menu overlay buttons:
- `p_info` -> `menu/playerinfo` -> scene `26100`.
- `story` -> `story/getoutline` -> scene `3100`.
- `town_event` -> `menu/gettownevent` or `menu/towneventlist` -> scene `28100`.
- `fairy` -> `menu/fairyselect` -> scene `29200`.
- `b_history` -> `menu/battlehistory` -> scene `25100`.
- `ranking` -> `menu/ranking/ranking_arena`, `menu/ranking/rankingevent`, or `ranking/ranking*` -> scene `27100`.
- `option` -> `menu/chksnd` -> scene `33000`.
- `item` -> `item/havelist` -> scene `30100`.
- `c_collection` -> `menu/cardcollection` -> scene `23100`.
- `partslist` -> `menu/haveparts` -> scene `31100`.
- `invide` -> `menu/invite_friend` -> scene `32100`.
- `help`, `update_history`, and `sqex_apply` are WebView paths under `/connect/web/*`; current web stub returns `sceneto://2100`.

Confirmed second-level paths covered as skeletons:
- `menu/productlist`, `menu/buyproduct` -> CP shop scene `8400`.
- `friend/add_friend`, `friend/approve_friend`, `friend/cancel_apply`, `friend/like_user`,
  `friend/refuse_friend`, `friend/remove_friend` -> friend scene `17000`.
- `item/use`, `item/use_fakecard` -> item-use-end scene `30200`.
- `cardselect/savedeckcard` -> deck scene `83200`.
- `gacha/getproductinfo`, `gacha/buy`, `shop/buy`, `shop/use`, `story/battle`, compound commit routes,
  battle user-list routes, recycle buy/select, reward get, notice/other list routes are present as explicit route
  skeletons or sample-backed bodies.

Return route:
- Current proven return-to-town route remains `/connect/app/mainmenu`, returning the accepted `<mainmenu>` body and `next_scene=2100`.
- Player-info back returns to `/connect/app/menu/menulist` first, not directly to town. Use that as the explicit
  menu-overlay back route in flow tests.
- Layout back buttons are often client-side `back` commands, but if they ask server for town, the server path is already covered by `/connect/app/mainmenu`.

Implementation:
- `server/bootstrap-server.js` now has `MAINMENU_ROUTE_STUBS` and `createMainmenuRouteXml(...)`.
- Sample-backed routes preserve bundled sample bodies and replace/supply `<your_data>` from the active player save.
- Skeleton routes contain header, current `<your_data>`, target `<next_scene>`, and an empty `<body>`,
  except `gacha/select/getcontents`, which needs the minimal `gacha_select/xml_contents` shell because
  an empty body crashed in `_XmlContentViewer::setPropertyValues`.
- `gacha/select/getcontents` deliberately avoids `local_gachaselect.xml` for now; the first runtime smoke
  with that sample crashed on missing `/save/download/image/gacha/gac_event_0`, so full gacha select content
  is a later resource/schema frontier.

Rejected/limited:
- This does not implement gacha buying, battle matching, card collection contents, item use, shop buying, reward claiming, ranking pages, friends, fairy rewards, story chapters, or compound flows.
- Empty-body skeletons are only to remove the 501/network-error wall and establish a route frontier. If a page opens blank or cannot return, the next round must recover that page's parser/body schema.

Server check:
- `server/test-bootstrap-server.js` covers representative routes:
  - `/connect/app/gacha/select/getcontents`
  - `/connect/app/battle/area`
  - `/connect/app/battle/battle_userlist`
  - `/connect/app/menu/menulist`
  - `/connect/app/menu/playerinfo`
  - `/connect/app/shop/shop`
  - `/connect/app/menu/productlist`
  - `/connect/app/friend/like_user`

Runtime observable for next round:
- `mainmenu-buttons-route-smoke` taps main menu/menu overlay buttons, waits for first routes, screenshots entered
  pages, and verifies return routes. Runtime artifact `work/kssma-flow-mainmenu-buttons-route-smoke-20260630-211416`
  passed for gacha, battle, compound/card exchange, shop, menu list, and player info.
