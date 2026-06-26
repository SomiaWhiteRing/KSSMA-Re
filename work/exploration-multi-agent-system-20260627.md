# Exploration Multi-Agent System

Date: 2026-06-27

## Frontier

```text
/connect/app/exploration/area OK
-> /connect/app/exploration/floor OK
-> floor_info_list reaches the scene-side floor_list PickList
-> floor_list is still not visible and the next tap repeats /exploration/floor
```

This round is not a "continue until exploration works" task. It is a bounded
coordination pass whose only job is to produce one safe runtime experiment or
one static reason to avoid that experiment.

## Goal

Build a small multi-agent system that advances exploration reconstruction
without widening the search space.

Success for this coordination round:

- one reviewed runtime handoff for `work/build-exploration-postfloor-state-writer-classifier.py`;
- or one stronger static objection that blocks that handoff;
- plus a written integration note in `reverse-notes.md` after any runtime run.

## Non-Goals

- Do not change `server/bootstrap-server.js` exploration XML in this round.
- Do not add `/connect/app/exploration/*` handlers from route-name guesses.
- Do not run server `floor_info` field sweeps.
- Do not repeat `+0x84`-only visual fixes.
- Do not use Frida as the default probe.
- Do not full-install APK for native-only work.
- Do not reopen main menu visuals, BGM, face, mainbg, or WebView notice issues.

## Agent Roles

| Agent | ID | Role | Output | Hard Boundary |
| --- | --- | --- | --- | --- |
| Averroes | `019f04c8-9fe2-7a03-94c6-fba29c3cabb8` | State-writer probe audit | Coverage/risk report for `build-exploration-postfloor-state-writer-classifier.py` | Read-only static analysis |
| Pasteur | `019f04c8-b515-7721-a441-e631aa59efe2` | Exploration schema/protocol gap audit | Confirm whether XML/header should be changed before the probe | No XML patch, no runtime |
| Dewey | `019f04c8-ca6d-73b0-ae49-c7a362dd4b49` | Floor-row next-route static tracing | Confidence table for route after floor-row click | No server handler guess |
| Faraday | `019f04c8-dfdc-7ef1-965e-3227ab10c8ec` | Runtime one-run handoff | Exact commands, trap map, artifacts, stop conditions | Does not execute runtime |

## Agent Results

### Averroes: Probe Audit

Result: the state-writer classifier is the right next probe, but the first
review found a real blocker: `INIT_WRITE` expected bytes were wrong for stock
`librooneyj.so`.

Fix applied in `work/build-exploration-postfloor-state-writer-classifier.py`:

- `0x00340E8C` expected bytes changed from `b2637354` to the stock bytes
  `f2637354`.
- builder now prints actual `udf` trap PCs, not just cave starts.

Static generator check now passes and writes:

```text
work/librooneyj-exploration-postfloor-state-writer-classifier.so
sha256=D07E21CD70ABC2A5FF24002770FC1A50C540CFB20AB21A7F7E87E3AE129B4F42
```

Trap map from the passing generator:

| Trap PC | UDF | Writer | Meaning |
| --- | --- | --- | --- |
| `0x003e7772` | `0x80` | `0x003413a6` | update area select writes state `3` |
| `0x003e77b2` | `0x82` | `0x0034149a` | state4 selected area-list writes state `0` |
| `0x003e7e72` | `0x84` | `0x00341538` | state2 reset writes state `0` |
| `0x003e7eb2` | `0x86` | `0x003415e2` | focus/end branch writes state `0` |
| `0x003e7ef2` | `0x88` | `0x00342036` | preUpdate state1-to-state4 writes state `4` |
| `0x003e7f32` | `0x8a` | `0x00342050` | preUpdate model-error writes state `0` |
| `0x003e7f72` | `0x8c` | `0x00340e8c` | initModel writes state `1` |

Caveat: `0x00342108` is a gate, not floor-only proof. Runtime artifacts must
show where the trap occurred relative to `/connect/app/exploration/floor`.

### Pasteur: Schema/Protocol Audit

Result: no response header/body field currently has a stronger evidence chain
than the state-writer classifier.

Confirmed:

- `<body><exploration_floor>` with `area_id`, `boss_down`, and
  `floor_info_list/floor_info` is parser-confirmed.
- Parsed data reaches `_ExplorationModel+0x50`, `+0x54`, and `+0x58`.
- The non-empty floor vector reaches the real scene-side `floor_list` PickList.
- `layout_exploration_area.xml` activation is a layout/state issue, not a
  proven response field issue.

Rejected for this round:

- changing `next_scene`;
- adding generic completion fields;
- sweeping `floor_info` values;
- changing XML wrappers.

### Faraday: Runtime Handoff

Result: one-run handoff is usable after the probe script fix above.

Key contract:

- only install `work/librooneyj-exploration-postfloor-state-writer-classifier.so`;
- do not change server XML;
- do not use Frida;
- do not full-install APK;
- stop after the first valid trap or after proving `/exploration/floor` was not
  reached;
- write `reverse-notes.md` before any next fix.

### Dewey: Next-Route Static Trace

Result: floor-row click path is statically useful for the next phase, but it
does not block the state-writer run.

Confirmed floor-row path:

- `layout_exploration_area.xml` binds `floor_list` as a `v_list` using
  `list="floor_list"` and `focus="f_focus"`.
- `_ExplorationArea::update` state-2 branch copies `_ExplorationModel+0x58`,
  bounds-checks the selected row, then calls
  `_ExplorationModel::move(int, smart_ptr<FloorInfoTagData>, bool)` at
  `0x00341426`.
- call shape is `r0=model`, `r1=area_id`, `r2=&selected_floor_info`, `r3=0`.

Route evidence:

- ordinary floor-row `move(...)` sets route id `0x17` before calling
  `Model::connect(int,map)`.
- likely route string is `exploration/explore`, inferred from neighboring route
  ids and route string order, but the route registration table still needs direct
  proof before implementing a handler from this alone.
- request params recovered for the ordinary path: `area_id`, `floor_id`, and
  constant `check=1`.

Next smallest static action after the current frontier: annotate
`_ConnectionControl::init` / route registration helper around
`0x002a81c0..0x002aa598` and helper `0x002a80e4` to directly bind route id
`0x17` to its route string.

## Integration Gate

The main thread may authorize one runtime run only if all are true:

- Averroes reports the probe has static byte checks, cave checks, replay branches,
  and a clear PC/trap map.
- Pasteur does not identify a higher-priority schema/header field with better
  evidence than the state-writer probe.
- Faraday provides a single-run command list with artifact prefix and stop
  conditions.
- The run changes exactly one variable: installed native classifier.

Current gate status: passed for a single state-writer classifier run, after the
builder fix and passing static generation. Dewey is deliberately outside the
gate for this run.

Dewey's route work is for the next phase. It must not cause new server handlers
before floor-list visibility or floor-row click is proven.

## Runtime Run Contract

If the integration gate passes, the runtime task is:

```text
Frontier: identify which post-floor writer changes _ExplorationArea+0x3c.
Hypothesis: after the floor response, one known state writer overwrites or
bypasses state 2 before the next tap can enter floor-row selection.
One variable changed: install only
work/librooneyj-exploration-postfloor-state-writer-classifier.so.
Observable: one controlled SIGILL/SIGTRAP PC mapped to a state writer, with
requests proving /exploration/area then /exploration/floor.
Stop: record the first valid trap or the absence of a trap; do not apply a fix.
```

## Stop Conditions

Stop the whole coordination round if:

- two agents disagree because a prior probe is invalid and needs documentation;
- the next proof requires broad runtime discovery rather than one handoff;
- any agent recommends changing XML without parser/model/layout evidence;
- any agent recommends a product native patch before explaining the state writer.

## After Runtime

Append a short `reverse-notes.md` entry with:

```text
## Exploration post-floor state-writer classifier result

- Frontier:
- Hypothesis:
- Command or patch:
- Static gate:
- Observed result:
- Trap PC map:
- Conclusion:
- Next:
- Do not repeat:
```

Only after that entry exists may the next round decide whether the correct
response is a protocol/schema change, a layout/action state investigation, or
a narrowly scoped diagnostic probe.
