# MuMu Android 12 deployment card (2026-08-17)

## Round boundary

- Frontier: turn the already proven MuMu Android 12 startup candidate into a reproducible installation path.
- Success: one command rebuilds/verifies artifacts as needed, installs the client and static resources, repairs both
  legacy host names, reaches both server ports from the guest, launches the client, and leaves auditable hashes.
- Non-goal: promote A12 to the default gameplay-flow runtime or fix the delayed gacha-select crash.
- Stop: stop on a runtime lifecycle delay over 15 minutes or two installer changes without a new observable.

## Accepted implementation

- Entry point: `install-mumu-a12.cmd`.
- PowerShell controller: `work/kssma-mumu-a12.ps1`.
- Deterministic resource builder: `work/build-mumu-a12-resource-pack.py`.
- Target: MuMu Android 12/API 32 at `127.0.0.1:7555`; guest host gateway `10.0.2.2`.
- Runtime gate: boot complete, Android 12/API 31-32, `armeabi`/`armeabi-v7a` in 32-bit ABI list, and a nonempty
  native-bridge property. PackageManager must select `primaryCpuAbi=armeabi` after install.
- Hosts: merge only `game.ma.mobimon.com.tw` and `dlc.game-CBT.ma.sdo.com`; preserve unrelated aliases; keep
  `/system/etc/hosts.kssma-re-original`; verify both names by device-side resolution. `restore-hosts` is explicit.
- Resources: package `appdata/save_version`, all `database`, and all `download`; exclude mutable
  `appdata/save_appdata`. Upload one TAR, extract into the package external save directory, then run full
  device-side `sha256sum -c`. Remote installer temporaries are removed by exact paths.
- Python: the dedicated `KSSMA-Re` conda environment is required. The documented creation command uses only
  `--override-channels -c conda-forge`, so accepting Anaconda default-channel ToS is not required.

## Built artifacts

The accepted prepare chain was:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 prepare
```

It produced:

- client APK SHA-256: `D22ED62A8C39210FBC22B91FB224FB33F603AF4CF9927B9014098AAF9398429B`;
- accepted `librooneyj.so` SHA-256: `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`;
- static files: 6,901;
- static payload: 517,599,894 bytes;
- TAR size: 522,864,640 bytes;
- TAR SHA-256: `FF60551898A285A355ECEC0E4C38624BA9999A6A19A6CB668CF8C7C9E66519CF`;
- checksum-list SHA-256: `71E8B7DB5820CD9811F04BFF191B699798B0EB5011834B8C2A5C8605DDB09AF5`.

Rebuilding after changing only the persistent sentinel retained the same TAR hash, confirming deterministic payload
construction. The generated TAR/checksum/manifest live under ignored `work/mumu-a12-package/` and are reproducible.

## Real-device replay

Accepted command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 deploy -StartServer -Launch
```

Observed result after making final package/hosts/resources and guest health values mandatory postconditions: exit 0 /
`ok=true` in 67.882 seconds. APK installation and legacy permissions passed; the installed native hash exactly matched
the accepted source. Hosts installation was idempotent (`changed=false`) and both legacy names resolved to
`10.0.2.2`. All 6,901 resources passed device-side hashing. Device-side HTTP health requests passed on ports 50005
and 10001. PID 6701 survived the ten-second launch gate, top resumed activity was
`com.square_enix.million_cn/com.test.RooneyJActivity`, no fatal signal appeared, and
`work/kssma-mumu-a12-last-launch.png` visibly showed the main menu.

The first complete replay had already installed the APK, repaired hosts, and hashed all resources successfully but
failed while collecting final launch evidence: local variable `$pid` collided with PowerShell's read-only `$PID`.
This was an installer-script defect, not client/runtime evidence; it was changed to `$gamePid` before the accepted
replay.

Two status probes were also rejected before acceptance. `database/master_card` is deliberately removed by the client
after loading, so it was replaced with persistent `database/master_boss`. MuMu's bundled `nc` lacks `-z`, so both
port checks now use device-side `curl` against `/healthz`. Do not revive either rejected probe.

This does not mean `master_card` is irrelevant. The later fairy-battle differential proved it is a one-shot
process-start input rather than a persistent health sentinel. The schema-2 resource manifest now pins the exact
260,249-byte source and SHA-256 `7B121D...B3A56BDF`. `install-client`, `launch`, and the isolated A12 flow gate stop
the client, restore the file only when missing/different, verify the device hash, and only then allow the original
Activity to start. `repair-master-card` exposes the same stopped-process preparation for a subsequent manual icon
launch; an icon launch without first using a controller entry remains outside the guarantee.

The 2026-08-19 missing-file fault injection moved the verified device file to an exact temporary backup and ran the
normal `launch -StartServer` command. Its JSON reported `restored=true`,
`reason=seeded-consumed-or-missing-file`, and the exact post-push hash before starting the Activity. PID 3012 stayed
in `RooneyJActivity`, the launch screenshot showed the normal main menu, and logcat contained no `adv_chara0`,
`thumbnail_chara_0`, `SIGABRT`, or `SIGSEGV`. The backup was removed only after both copies matched; the normal
device target remains present with the accepted hash. The resource TAR and checksum-list hashes remained
`FF6055...19CF` and `71E8...AF5`, respectively.

## Boundary

This accepts installation, resource completeness, old-domain recovery, server reachability, repeatable card-master
initialization for controller-owned cold starts, and immediate launch to the main menu on the current MuMu Android
12 instance. It does not yet accept long-running gameplay: the separately recorded gacha-select page can still hit
the reward-box-path null `SIGSEGV` after roughly 269 seconds, and gacha result must be replayed on the new launch
baseline. ARM19 remains the default automated gameplay acceptance runtime.
