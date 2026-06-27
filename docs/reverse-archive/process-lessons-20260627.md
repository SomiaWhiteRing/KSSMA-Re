# Process Lessons 20260627

Hard-stop process lesson from the failed exploration sprint.

Source: `reverse-notes.md` before compaction, archived in full at `reverse-notes-full-before-compaction-20260627.md`.

<!-- original lines 1284-1294 -->

## Process hard-stop lesson from the failed exploration sprint

- Failure mode: the work drifted from “run static/runtime loop until fixed” into repeated probe construction without a deliverable boundary. Several probes produced invalid or ambiguous evidence, and the findings were not written down before starting the next probe.
- Required correction:
  - Future tasks must be cut into one frontier with one success criterion and one stop condition.
  - A 90-minute work block must end with a committed conclusion in `reverse-notes.md`, even if the conclusion is “probe invalid.”
  - Two consecutive patches without a new route/logcat/native-PC/screenshot/activity observable require a hard stop.
  - A bad probe must be documented as bad before any successor uses its result.
  - Native probes must include byte checks, cave checks, disassembly of replay branches, and trap PC map before `patch-lib`.
- Current safe next action: build and run only `work/build-exploration-postfloor-state-writer-classifier.py`, then stop and record the single writer result.


<!-- original lines 2238-2269 -->

## Project constraint update: gameplay flow edges and known-good path reuse

- Frontier: the old project rules still reflected the startup-chain era and
  could push gameplay work back toward "next request", XML guessing, or one
  local UI flag at a time.
- Hypothesis: the two accepted exploration fixes show a better rule:
  gameplay work should validate an entire flow edge and should prefer reusing a
  proven correct path over locally reconstructing UI state.
- Changed one variable:
  - Updated `AGENTS.md`, `clean-start.md`, and `readme.md` only. No server XML,
    APK, native library, resource, or runtime state was changed.
- New rule substance:
  - Startup can still proceed by next route.
  - Gameplay proceeds by flow edge:
    `user action -> request/response -> client state switch -> visible UI -> next click target/route`.
  - HTTP 200 is not a gameplay success criterion.
  - If an already-accepted correct path can produce the target UI/state/route,
    write a path card and statically recover that complete path before product
    patching.
  - Repeatedly emitting the previous-layer route after a supposed layer switch
    is strong evidence that foreground/click ownership did not change; do not
    keep guessing XML fields in that case.
  - After two failed local UI/state/behavior patches, the next round must use
    known-good path diff/reuse or a read-only classifier, not another local
    behavior/flag patch.
  - Exploration-specific text now explicitly rejects continuing `area_list_sp`,
    `+0x84`, XML-only, and `floor_info` sweeps without new native evidence.
- Conclusion:
  - These rules preserve the useful safety gates while removing the wording that
    made agents overfit to tiny local state fixes. Future exploration work
    should start from the layer/flow-edge question before touching XML, draw
    flags, or behavior names.
