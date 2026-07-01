# Menu Friend List Schema Card, 2026-07-01

Route: `/connect/app/menu/friendlist`

Frontier:
- Main-menu bottom friends button emits `/connect/app/menu/friendlist` with decrypted `move=0`.
- Empty scene skeleton (`<body></body>`, `next_scene=22100`) crashed in `_FriendListScene::updateAnimation()`.
- Minimal `friend_list/user_list/user` data with `next_scene=22100` still crashed while creating scene `22100`.
- Minimal `friend_list/user_list/user` data with `next_scene=17100` is accepted on ARM19.

Static anchor:
- `layout_menu_friend_list.xml`
- `rule_scene.xml`: `17100` is `friend_list_scene` with explicit `layout="friend_list_scene"`.
- `rule_resource.xml`: `friend_list_scene` declares `layout name="friend_list_scene.xml"`.
- `rule_scene.xml`: `22100` is `menu_friend_list` with `layout="true"`.
- `_FriendModel::update(TiXmlElement*)` at `0x001db5c9`
- `_FriendListTagParser::parse(TiXmlElement*)` at `0x002fe4b1`
- `_UserListTagParser::parse(TiXmlElement*)` at `0x00312245`
- `_UserTagParser::parse(TiXmlElement*)` at `0x003110a1`
- bundled sample value source: `local_users_event_list.xml`

Native owner:
- Friend scene owns a `friend_model`; layout binds header `friendNum` / `friendMax` from that model.
- The visible list is a scene `v_list` bound to `friend_list`.

Parser path:
- Friend model update walks response body children and has a dedicated parser for `friend_list`.
- `_FriendListTagParser::parse(...)` owns a `friend_list` data object and descends into nested list/user parser paths.
- `_UserListTagParser::parse(...)` iterates `<user>` children and calls the user parser for each row.

Expected parent:
- `<body><friend_list>...</friend_list></body>`

Confirmed fields:
- `friend_list` | parent | required for page model | native string/parser owner and layout model binding.
- `user_list` | list wrapper | required for visible rows | `_UserListTagParser` symbol and bundled sample shape.
- `user` | list item | required for a non-null row | `_UserTagParser` symbol and bundled sample shape.

List nodes:
- `friend_list -> user_list -> user`
- user row fields taken from `local_users_event_list.xml`: `id`, `name`, `country_id`, `cost`, `results/win/lose`,
  `town_level`, `next_exp`, `leader_card`, `rank`, `friends`, `friend_max`, `last_login`, `ex_gage`,
  `max_card_num`, `status_friend`, `status_yell`, `count_hunting`, `deck_rank`.
- `leader_card` uses the same owner-card field set as already accepted for player header owner cards.

Model/layout consumers:
- `friend_model.friendNum` / `friend_model.friendMax` -> header `<friend_list name="list"...>`.
- `scene.friend_list` -> visible `v_list`.
- `scene.friendsInvitations` -> friend notice button; current minimal runtime candidate keeps this at `0`.

Rejected shapes:
- Empty `<body></body>` scene skeleton: runtime artifact `work/kssma-flow-mainmenu-bottom-buttons-smoke-deck-friends-bottom-final-1`
  proved SIGSEGV after `/connect/app/menu/friendlist`.
- `next_scene=22100` after adding `friend_list/user_list/user`: runtime artifact
  `work/kssma-flow-mainmenu-bottom-buttons-smoke-deck-friends-bottom-final-2` still crashed in
  `_SceneControl::create(int)` with scene id `22100` on the stack.
- `/connect/app/cardselect/savedeckcard` as the bottom card entry: bottom card emits `/connect/app/roundtable/edit`.

Minimal XML candidate:

```xml
<body>
  <friend_list>
    <friends_invitations>0</friends_invitations>
    <user_list>
      <user>...</user>
    </user_list>
  </friend_list>
</body>
```

Accepted target:
- `/connect/app/menu/friendlist` returns `<next_scene>17100</next_scene>` and the minimal `friend_list` body.
- Runtime artifact `work/kssma-flow-mainmenu-bottom-buttons-smoke-deck-friends-bottom-scene17100` passed:
  route `/menu/friendlist` with `move=0`, response `command=friends,nextScene=17100`, friends page screenshot diff
  `91.08`, then `/connect/app/mainmenu` and main-menu screenshot diff `0.26`.

Observable for later runtime check:
- `flow -Scenario mainmenu-bottom-buttons-smoke` should reach `/connect/app/menu/friendlist`, visibly open the friends page,
  then return to main menu without SIGSEGV.

Open questions:
- The full friend application/search/approval routes remain separate frontiers.
- A real friend system should replace the one-row local fallback with `playerSave.friends.list`.
