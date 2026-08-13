# Gacha Buy Failure Schema Card, 2026-08-10

## Bounded Round

- **Frontier:** `/connect/app/gacha/buy` rejection response -> current pending model -> visible
  dialog -> dismiss -> prior gacha result state.
- **Success:** statically close the response XML, error value, transport, dialog presentation, and
  dismissal/return path before any server rejection is implemented.
- **Non-goal:** no server, test, flow, runtime, APK, native patch, or emulator change; no guessed HTTP
  status, XML field, error code, or scene transition.
- **Stop:** any missing edge between the generic response-error branch and the visible dialog is a hard
  stop for G1 and freezes G2-G4.

The stop condition was reached. The parser and downstream dialog consumer are closed, but the producer
edge that presents the generic business-error dialog is not.

## Evidence Baseline

Static analysis used the current accepted native library:

- Path: `work/librooneyj-gacha-cardget-inner-touch-nullguard.so`
- Size: `4,476,928` bytes
- SHA-256: `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`
- ARM Thumb addresses below are virtual addresses in that ELF; its relevant `.text` and `.rodata`
  virtual addresses equal their file offsets.

No runtime experiment was performed.

## Response Parser

### Document shape

`_TXmlParser::parse(char const*)` at `0x002ec838` parses the response document and searches the document
root's direct children for:

- `<header>` (`0x003da8ac`): its first child is passed to `_HeaderTagParser::parse`; the resulting
  `HeaderTagData` smart pointer is stored at `_TXmlParser+0x08`.
- `<body>` (`0x003dd1d0`): its `FirstChildElement()` is stored at `_TXmlParser+0x0c`.

An empty `<body></body>` therefore produces a null body-model element without making the outer XML parse
fail.

`_TXmlParser::getCode()` at `0x002ec79c` follows
`_TXmlParser+0x08 -> HeaderTagData+0x10 -> ErrorTagData+0x00`; a missing pointer in that chain returns
`0`.

### Header shape and defaults

`_HeaderTagParser::parse(TiXmlElement*)` at `0x00301cec` constructs `HeaderTagData` with
`next_scene=0` at `0x00301d1e`, then recognizes these direct children:

| Header child | Evidence | Destination | Required by generic code-1 branch |
| --- | --- | --- | --- |
| `<error>` | name `0x003ded58`; branch `0x0030213e`; parser call `0x003021a4` | `HeaderTagData+0x10` | Yes |
| `<your_data>` | name `0x003ded6c` | parsed player data | No; parser optional |
| `<session_id>` | name `0x003ded90` | `HeaderTagData+0x04` | No; not consumed by this branch |
| `<next_scene>` | name `0x003ded9c`; text conversion `0x003021e2..0x003021f8`; store `0x003021fc` | `HeaderTagData+0x08` | No; omission retains `0` |

The absence of `your_data` is parser-safe and the generic error path does not require a player-data
mutation. The absence of `next_scene` is also parser-safe and produces the already-proven default `0`.
These are current-client consumption facts, not evidence that the original server always omitted either
field.

### Error shape and defaults

`_ErrorTagParser::parse(TiXmlElement*)` at `0x002f8cd0` allocates a 24-byte `ErrorTagData`. Its
constructor path initializes `code=-1` at `0x002f8cee..0x002f8cf4`, message `"no message"`
(`0x003de2e4`) at `0x002f8cf8`, an empty address string at `+0x0c`, and `link_id=0` at
`0x002f8d06..0x002f8d08`. It iterates direct siblings with `NextSiblingElement()` and recognizes:

| Error child | Name address | Parse/store evidence | Destination |
| --- | --- | --- | --- |
| `<code>` | `0x003de2f0` | `0x002f8d88..0x002f8da4` | integer at `+0x00` |
| `<message>` | `0x003d389c` | branch `0x002f8db6` | string at `+0x04/+0x08` |
| `<address>` | `0x003de2f8` | branch `0x002f8e36` | string at `+0x0c/+0x10` |
| `<link_id>` | `0x003de300` | `0x002f8dfe..0x002f8e1a` | integer at `+0x14` |

`address` and `link_id` are not read by the generic type-2 dialog branch. A code and a visible message are
the only parser-proven payload needed by that branch.

### Parser-minimum candidate, not an accepted failure contract

```xml
<response>
  <header>
    <error>
      <code>1</code>
      <message>...</message>
    </error>
  </header>
  <body></body>
</response>
```

This is only the minimum shape the current parser and pending gacha model can consume. It is **not** an
implementable or accepted `/gacha/buy` rejection fixture because the visible-dialog presentation edge is
still missing below.

`ponytail:` this candidate deliberately contains only parser-proven fields; upgrade it only after the
missing dialog-presentation edge is recovered.

## Nonzero Code Domain and Dispatch

`_Main::connect(smart_ptr<_TXmlParser>)` at `0x001c32d8`:

1. Calls `_TXmlParser::parse` at `0x001c359c`.
2. Calls `_TXmlParser::getCode` at `0x001c35b2` and saves the result at `[sp+4]`.
3. Separates code `10000` at `0x001c3704..0x001c370e` (literal `-10000` at `0x001c3874`).
4. Tests zero at `0x001c3afe`; every other nonzero code enters the generic business-error block at
   `0x001c3b04`.

That generic block:

- gets `_DialogModel` at `0x001c3b06` (`_DialogModel::getInstance`, `0x001c2be0`);
- constructs `DialogData` at `0x001c3b2e` (`DialogData::DialogData`, `0x001c21ec`);
- writes dialog `type=2` at `0x001c3b32..0x001c3b36`;
- copies `ErrorTagData.message` into `DialogData.message` at `0x001c3b38..0x001c3b8a`;
- calls `_DialogModel::initDialog(DialogData)` at `0x001c3ba4` (target `0x001d4f7c`);
- separately tests special codes `1040`, `1010`, and `1000` at
  `0x001c3bb0`, `0x001c3bc0`, and `0x001c3bce`.

Code `1` avoids all three special-code branches. The surrounding range path
`0x001c395c..0x001c396c` accepts a nonnegative value no greater than `1010`, then with default
`next_scene=0` and no tutorial task reaches `_ConnectionControl::reset()` at `0x001c3970` and returns
`1` at `0x001c3986`.

`Model::isError()` at `0x001e15b4` returns false only for `0`, `1000`, `1010`, `1020`, and `1030`;
therefore it classifies code `1` as an error. This is executable evidence that `1` belongs to the
client's generic-error value domain. It is not provenance for an original-server `/gacha/buy` code.

## Body Delivery to the Pending Gacha Model

`_Main::main(bool)` calls `_Main::connect` at `0x0018057a`, obtains the parsed code at `0x0018070a`,
and calls `_Main::update` at `0x0018071c`.

On response completion, `LayoutScene::task`:

- invokes the pending model's `setError(code)` virtual slot at `0x001f3e40..0x001f3e48`;
- invokes its `update(bodyElement)` virtual slot at `0x001f3e4a..0x001f3e56`;
- then runs the scene pre-update/reset path.

`GachaModel` does not override `Model::update(TiXmlElement*)`; its vtable resolves this call to the base
no-op at `0x001e15a0`. A null element from `<body></body>` is consequently safe for this generic error
delivery. No `<gacha_buy>`, `<final_result>`, or owner-list update is parser-required on the error branch.

## HTTP and AES Envelope

The accepted local `/connect/app/*` transport in `server/bootstrap-server.js` is reusable without adding
a new protocol path:

- `getConnectAppKey` at line 117 selects the existing connect-app key.
- `parseConnectAppBody` at line 168 iterates form entries; request values are Base64-decoded and decrypted
  by `decryptAes128EcbBase64` at line 154 using AES-128-ECB with automatic padding.
- `encryptAes128EcbBuffer` at line 148 encrypts response XML using the same cipher and padding.
- `sendBinary` at line 105 sends raw ciphertext as `application/octet-stream`.
- `/connect/app/*` dispatch begins at line 2117; `/connect/app/gacha/buy` is handled at line 2423 and
  currently returns `sendBinary(res, 200, encrypted)`.

Any future evidence-backed rejection must reuse HTTP `200`, a full XML document encrypted as raw
AES-128-ECB ciphertext, and `application/octet-stream`. HTTP 4xx, plaintext, an empty body, or empty XML
would be guesses and are prohibited.

## Known Dialog and Retry Paths

The already-accepted paid retry path proves how the *confirmation* dialog is presented:

- `_GachaDrawResult::Retry::exec(int)` at `0x0034e22c` builds a default type-0 yes/no `DialogData`, calls
  `_DialogModel::initDialog` at `0x0034e2aa`, then calls its scene virtual slot `+0x44` at
  `0x0034e2d0..0x0034e2d6`.
- For `_GachaDrawResult`, that slot is `LayoutScene::showDialog()` at `0x001f3d94`.
- `LayoutScene::showDialog()` calls `_SceneControl::push(int)` at `0x001f6950` with literal
  `90100` (`0x00015ff4`, loaded at `0x001f3da0`).
- `_GachaDrawResult::Retry::exec` then sets pending state at draw-result offsets `+0x64=1` and
  `+0x68=0`.
- On confirmation, `_DialogScene::update` uses its type-0/1 case at `0x0033e19c`; the affirmative tap is
  tested at `0x0033e1f4`. `_GachaDrawResult::update` later observes tap `0`, calls
  `_GachaModel::draw` at `0x0034e9c4`, and triggers the request at `0x0034e9cc`.

The downstream type-2 dialog consumer is also closed **if a DialogScene has been pushed**:

- `_DialogModel::initDialog` at `0x001d4f7c` sets the type-2 simple-dialog flag at
  `DialogData+0x28` and resets tap state to `-1`.
- `_DialogScene::update` at `0x0033debc` routes type `2` to `0x0033df0e` and calls
  `_SimpleDialog::isTapped` at `0x0033df34` (target `0x002c3860`).
- A tap calls `_DialogModel::tapEvent(2)` at `0x0033e40a` and invokes `_Scene::end()` through virtual
  slot `+0x30` at `0x0033e414` (target `0x001f4f3c`).
- `_SceneControl::update` at `0x001f6b60` detects the ended top scene around
  `0x001f6bba..0x001f6bbe` and calls `_SceneControl::pop(true)` at `0x001f6bd4` (target
  `0x001f6208`).

Thus a presented type-2 dialog is a visible tap-to-dismiss overlay that pops back to the preceding scene.
This does not prove that the response path presents it.

## Hard Gap

The generic business-error block `0x001c3b04..0x001c3988` initializes `DialogModel`, but contains no call
to either:

- `LayoutScene::showDialog()` at `0x001f3d94`, or
- `_SceneControl::push(90100)` at `0x001f6950`.

The retry confirmation DialogScene calls `_Scene::end()` after the affirmative tap and is then popped by
`_SceneControl`. The current static trace found no proven callback from `Model::isError`, `_Main::update`,
`GachaDrawResult` response pre-update, or response completion that pushes or reactivates scene `90100`
after `_Main::connect` creates the type-2 error data.

The following required G1 observables therefore remain unclosed:

- whether the code-1 `/gacha/buy` response visibly presents the type-2 dialog;
- which scene is beneath that dialog when it is presented;
- whether dismissal returns specifically to `GachaDrawResult`;
- whether dismissal is route-quiet.

## Decision

G1 is **statically blocked at the dialog-presentation edge**. Do not implement the parser-minimum XML as
a rejection response, and do not begin G2, G3, or G4. The next bounded static round must recover the exact
caller that invokes `LayoutScene::showDialog` or `_SceneControl::push(90100)` after generic
`_DialogModel::initDialog`; only a closed producer edge can promote the XML above from parser candidate to
an evidence-backed failure fixture.

