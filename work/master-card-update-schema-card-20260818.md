# Card master update wire schema (2026-08-18)

## Frontier and flow edge

```text
login card_rev=232 -> /connect/app/masterdata/card/update (client revision 231)
-> card manager contains master ids 9, 22, and 600
-> user taps fairy battle -> VS resolves adv_chara5022 / adv_chara5600
-> battle result scene remains alive
```

This round changes only the representation returned by the card-master update endpoint. Fairy statistics,
fairybattle XML, winner semantics, APK/native code, resources, emulator settings, and the revision trigger are
non-goals. Success requires the client to stop requesting `adv_chara0` and proceed to battle/result. If the XML
update is accepted and persisted but the same null master-card lookup remains, stop rather than scan more XML
fields.

## Accepted native path

- `ResourceDownloader::parseMasterCardTagData` at `0x003923bd` passes the downloaded plaintext to
  `_TXmlParser::parse`, requires the top-level `master_data` node, dispatches `_MasterDataTagParser`, constructs
  `_Card` objects, calls `CCardManager::updateMasterCardList`, serializes the manager, and updates `save_version`.
- `_MasterDataTagParser::parse` recognizes `master_card_data`. `_MasterCardDataTagParser::parse` at `0x00305b31`
  recognizes `update_type`, repeated `card` nodes, and `imagedl_list`; each `card` child is parsed by
  `_CardTagParser::parse` at `0x002f4991`.
- `_BattleVSInfoTagParser::parse` at `0x002f3879` creates the players consumed by
  `_BattleModel::init(BattleVSInfo)` at `0x001ca801`. `_AnmBattleVS::createBattleData` at `0x002560d5` creates a
  `_UserCard` and calls `rooney::res::getAdvCharaImage(UserCard,int)` at `0x0038fcd5`.
- `_UserCard::getImageId` at `0x001f3551` asks `CCardManager` for its `master_card_id`; a missing `_Card` returns
  image id zero. That is the observed `adv_chara0` path.

The accepted wire root is therefore:

```xml
<master_data>
  <master_card_data>
    <update_type>1</update_type>
    <card>...</card>
  </master_card_data>
</master_data>
```

`update_type=1` replaces the in-memory table, so the response must carry the complete recovered 480-record card
baseline rather than a three-card patch that would overwrite the on-device cache with an incomplete table.

## Recovered source and exact records

The source is
`work/million_cn/sdcard_dump/sdcard/Android/data/com.square_enix.million_cn/files/save/database/master_card`,
SHA-256 `7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF`. Its big-endian offset table contains
480 records. The decoder consumes every record to its declared boundary using the native `_Card::serialize`
order: two integers, six strings, sixteen integers, two strings, and thirteen integers.

The current flow-critical records decode without guessing:

| master id | name | max lv | image1 | image2 | character id |
|---:|---|---:|---:|---:|---:|
| 9 | 支援型依缇尔 | 15 | 9 | 5009 | 9 |
| 22 | 特异型恺撒 | 36 | 22 | 5022 | 22 |
| 600 | 特异型小龙女 | 50 | 600 | 5600 | 600 |

All parser field names are present in the accepted native library, including `skill_description`, `grow_type`,
`growth_rate_text`, `distinction`, and `lvmax_power`; the endpoint should render the recovered values rather than
derive image IDs or invent card metadata.

## Wrong-path connection and observable

The current route encrypts and returns the serialized local cache directly. Transport reaches HTTP 200, but the
native callback attempts XML parsing, accepts no cards, leaves `save_version` unchanged, and later resolves the
fairy to image zero. The corrected route keeps the same AES-128-ECB transport and revision request, replacing only
the plaintext payload with the parser-backed XML above.

Minimum verification:

1. Node self-check proves all 480 binary records are consumed exactly and confirms ids 9/22/600.
2. A live login advertises only `card_rev=232`; the client sends one card-update request from revision 231.
3. The response log identifies `master-card XML`, 480 records, and update type 1.
4. After the user taps battle, requests/logcat contain no `adv_chara0` and the activity reaches battle/result or
   yields a different exact blocker.

## Full-payload result and bounded classifier

The 480-record XML was returned in full and the Activity reached the main menu, but the client neither changed
`save_version` nor produced an external `master_card`. A subsequent user-driven battle repeated `adv_chara0` and
the strict-JNI abort. This rejects HTTP 200 and XML well-formedness as acceptance evidence; it does not identify
whether the callback received a truncated/failed body or rejected one of the 480 parsed records.

The next classifier changes only card count/response size. It keeps the same root, field set, update type 1,
revision 232, encryption, and exact recovered record values, but selects the three current flow-critical cards
9/22/600 through diagnostic env `KSSMA_CARD_UPDATE_IDS=9,22,600`. The product default remains the complete 480-card
response. A changed `save_version`, serialized table, or nonzero battle image is a positive callback observable;
the same unchanged files plus `adv_chara0` rejects payload size/card-count as the blocker and ends this XML branch.

## Bounded classifier result

The diagnostic response contained exactly ids 9/22/600 and was 5,568 encrypted bytes. During the same client
process, user-driven fairy battle serial 100011 no longer logged `adv_chara0`, `thumbnail_chara_0`, a missing-file
path, `JResourceLoader`, or its pending `RuntimeException`. Although `save_version` remained byte-identical and no
external `database/master_card` appeared, the disappearance of the exact downstream missing-master observable is
positive evidence that the bounded XML initialized the current in-memory card table.

The process instead aborted at 21:59:12 while switching into battle: MediaPlayer reset and a new NuPlayer source
started, then ART reported `JNI DETECTED ERROR: java_object == null` for `GetObjectClass` from
`GLRenderer.nativeMain`. The fairybattle request arrived after that abort and the server later settled victory;
therefore it does not prove a visible client result scene. The card XML/count branch has produced a new observable
and is frozen while the next frontier is the battle-transition audio/JNI bridge. Product default remains the full
480-card response; the three-card selector is diagnostic only.

### Superseding exact-path capture

The temporary DEX path logger on the next bounded login/reproduction supersedes the absence-based inference above.
Fairy serial 100012 again aborted with a pending `RuntimeException` for the exact path
`save/download/image/adv/adv_chara0`, through `JResourceLoader.loadFile -> loadBitmap ->
TextureLoader.loadTexture -> GetObjectClass(null)`. The same process requested revision 231, received the 5,568-byte
three-card response, and still resolved image zero. Therefore the earlier lack of a printed path was incomplete
log evidence, not proof of in-memory card-manager acceptance. The media transition is not the root cause.

Both the full and bounded XML responses are now rejected as client-accepted updates: neither persisted a version or
card table, and the bounded response demonstrably leaves the battle lookup unresolved. Do not create a fake
`adv_chara0`; the next frontier is the exact parser/callback acceptance condition before
`CCardManager::updateMasterCardList` and `save_version`.

## Corrected persistence evidence and preload classifier

The A12 deployment card predates this experiment and records that the client deliberately removes the externally
preloaded `database/master_card` after loading it. Native inspection agrees that
`CCardManager::deserializeMasterCardList` reads the exact `ResourceManagerEx::getMasterCardPath()` cache, while the
update callback calls `clearMasterCardList`, `updateMasterCardList`, and `serializeMasterCardList` in that order.
Consequently, absence of the external file is not an XML-rejection observable and must not be used as one. The
unchanged `save_version` is also insufficient on its own because the callback receives the updater's `RequestData`;
the exact revision commit source is not yet closed.

Deeper static recovery closes the XML child path without another field scan. `_MasterCardDataTagParser::parse`
compares direct children against `card`, `update_type`, and `imagedl_list`; for each `card` it calls
`FirstChildElement()` and passes the first field directly to `_CardTagParser::parse`. The first two card comparisons
resolve exactly to `master_card_id` and `country_id`, and the remaining emitted field names are the parser's own
native strings. There is no additional `card_list` wrapper or response/body envelope in this callback.

The next one-variable live classifier therefore restores the already accepted serialized cache before process
start and removes the diagnostic revision override. Source and device SHA-256 are both
`7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF`; the normal server again advertises card
revision zero. If the same user-driven fairy edge no longer resolves `adv_chara0`, the blocker is A12 process restart
without a rebuilt transient master table, and the product fix belongs in the A12 launch/runtime baseline. If the
exact path remains, the XML/preload branch stops and the next frontier is `battle_vs_info`/`battle_battle` user-card
binding. No fake image zero, resource reinstall, or further XML tag variation is authorized by this classifier.
