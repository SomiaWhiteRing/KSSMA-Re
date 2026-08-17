# Gacha request-disconnect server crash card (2026-08-17)

## Bounded round

- Frontier: main-menu gacha tap -> `POST /connect/app/gacha/select/getcontents` -> server remains alive.
- Success: reproduce the reported process exit, isolate the cause, add an automated regression, and keep both
  `50005` and `10001` healthy after the same fault.
- Non-goal: unsupported bulk/11-pull, random pools, completion rewards, or a guessed insufficient-balance dialog.
- Stop: after two ARM19 transport recovery attempts fail without a route or screenshot, record runtime blocking
  evidence and do not continue emulator restarts.

## Evidence

1. A normal POST against the current `server/data/player/local-save.json` returned HTTP 200, encrypted
   `next_scene=9100`, and left the server alive. The save had zero friendship points and zero MC, so the entry
   route and the zero-balance header were not the process-exit trigger.
2. A raw TCP client then sent the same POST with `Content-Length: 4096`, transmitted only `x=`, and closed the
   socket. Before the fix, both listening ports disappeared and stderr recorded:

   ```text
   Error: aborted
     at abortIncoming (node:_http_server:897:17)
   code: 'ECONNRESET'
   Node.js v24.18.0
   ```

3. `http.createServer(async (req, res) => ...)` returned an unobserved Promise. `readBody(req)` rejected on the
   aborted request, Node treated the rejection as uncaught, and the whole process terminated. The failure was
   transport-level; no gacha XML builder or settlement code ran.

## Accepted server fix

- `createServer` now observes every async request Promise and routes failures through `handleRequestFailure`.
- Client disconnects are logged as `request_error` with `code=ECONNRESET` and `disconnected=true`; no response is
  attempted on the dead socket. Other pre-response handler faults receive HTTP 500 without terminating the process.
- `server/test-bootstrap-server.js` reproduces the truncated gacha POST, then requires `/healthz` HTTP 200 and the
  structured disconnect log before continuing through friendship and paid gacha settlements.
- The self-check uses a disabled temporary fairy config instead of depending on the mutable LAN runtime setting;
  enabling fairy encounters in the admin UI no longer makes unrelated self-check exploration requests nondeterministic.

## Verification

- Full self-check passed in the existing environment:

  ```powershell
  & 'C:\Users\jsyzd\miniconda3\Scripts\conda.exe' run -n KSSMA-Re node .\server\test-bootstrap-server.js
  ```

- Manual server verification repeated the truncated POST after the fix, immediately issued a normal gacha-select
  POST, and observed HTTP 200/2784 bytes. The original PID remained alive; ports 50005 and 10001, `/healthz`, and
  the server fingerprint were all healthy; stderr remained empty.

## ARM19 reacceptance

- `flow -Scenario gacha-result-back-smoke -Tag gacha-server-crash-repro-20260817` stopped before login at
  `repair-adb / restart-boot-timeout`; artifact:
  `work/kssma-flow-gacha-result-back-smoke-gacha-server-crash-repro-20260817`.
- A second permitted `repair-adb` also ended at `restart-boot-timeout`. Diagnose showed
  `emulator-5556 offline` while console/ADB ports were open. The same cold boot later completed; `fast-health`
  returned `armeabi-v7a / 4.4.2 / boot_completed=1` without an additional restart.
- The first resumed flow, tag `gacha-server-disconnect-fix-arm19-retest`, stopped before login because the generated
  save resource `download/pack/gacha/gacha_cp_button` was absent. The accepted
  `work/extract-gacha-pack-resources.py` path rebuilt that file and the other original `gacha0_1.pack` resources.
  `environment.yml` now declares the script's existing `pycryptodome` import; it was installed only in the dedicated
  `KSSMA-Re` conda environment from conda-forge.
- `flow -Scenario gacha-result-back-smoke -Tag gacha-server-disconnect-fix-arm19-retest-2` passed on ARM19 in
  149899 ms. Route order was select -> buy `(product_id=1, bulk=1, auto_build=1)` -> select. Screenshots prove the
  original select page, RARE draw, card-detail result, and returned select page; RooneyJ stayed alive and server
  stderr was empty. Artifact:
  `work/kssma-flow-gacha-result-back-smoke-gacha-server-disconnect-fix-arm19-retest-2`.
- The result/back smoke intentionally starts from zero friendship points and therefore exposed the still-open
  insufficient-balance invariant: the current success handler awarded a card while clamping the balance at zero.
  This run accepts presentation/navigation and server survival, not zero-balance settlement semantics.
- `flow -Scenario gacha-settlement-deck-smoke -Tag gacha-funded-settlement-arm19-retest` then passed in 178106 ms
  from 400 friendship points. The response and saved JSON agree on `400 - 200 = 200`, card
  `serialId=2/masterCardId=9`, `cardsDrawn=1`, and one history row. After return, `/roundtable/edit` read owner
  serials `[1,2]` and master IDs `[22,9]`; server stderr and client fatal scan were empty. Artifact:
  `work/kssma-flow-gacha-settlement-deck-smoke-gacha-funded-settlement-arm19-retest`.
- Insufficient balance and invalid product/bulk still require the native producer/visible error contract recorded
  in `work/gacha-buy-failure-schema-card-20260810.md`; do not replace it with guessed XML or HTTP behavior.
