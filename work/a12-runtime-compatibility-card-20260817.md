# Android 12 runtime compatibility card (2026-08-17)

## Bounded round

- Frontier: determine whether the user-provided Android 12 emulator at `127.0.0.1:7555` can run the
  unique KSSMA-Re client through login, visible main menu, and one gameplay navigation edge.
- Success: the installed client stays alive in `RooneyJActivity`, reaches the local server through the
  emulator gateway, renders the main menu, and a main-menu tap produces both a route and visible UI migration.
- Non-goal: do not replace ARM19 as the default runtime, change the APK/native library, change gameplay XML,
  or generalize the existing ARM19 flow controller in this round.
- Stop: stop on an ABI/install rejection, a repeatable native-translation crash, or two attempts without a new
  Activity, route, fatal log, or screenshot observable.

## Device fingerprint

```text
serial=127.0.0.1:7555
release=12
sdk=32
abi=x86_64
abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi
abilist32=x86,armeabi-v7a,armeabi
native_bridge=libnb.so
boot_completed=1
guest_ip=10.0.2.15
guest_route=10.0.2.0/24 dev wlan0
SELinux=permissive
```

MuMu's launch telemetry identified version `12.5.1.5004`, native bridge name `libhoudini.so`,
`NB_64BIT=false`, and `RunningArchitecture=armeabi`. PackageManager installed the client with
`primaryCpuAbi=armeabi`; the client is version 1.0.0, versionCode 100, minSdk 8, targetSdk 8.

## Installation and gateway

- Installed only `work/client-baseline/KSSMA-Re-client-baseline.apk`.
- Tested APK SHA-256:
  `4506D64561F4EFA93952CA068BA596758C27ACD5132221B6E56D9AB67AD31AF7`.
- Normal `adb install` succeeded; no ABI override or APK repack was needed.
- `10.0.2.2` is the correct host gateway for this emulator. The guest reached both local server ports
  `50005` and `10001`.
- The server already emitted `world_url=http://10.0.2.2:50005/connect/app/` and
  `top_url=http://10.0.2.2:50005/`; no server configuration or source change was required.

The legacy client still connects to two original host names. After `adb root`, the device hosts file was
backed up as `/system/etc/hosts.kssma-re-backup-20260817` and the following mappings were installed:

```text
10.0.2.2 game.ma.mobimon.com.tw
10.0.2.2 dlc.game-CBT.ma.sdo.com
```

The host-side candidate is `work/kssma-a12-launch-20260817/hosts.kssma-re`. The change is recoverable:

```powershell
adb -s 127.0.0.1:7555 root
adb -s 127.0.0.1:7555 shell cp /system/etc/hosts.kssma-re-backup-20260817 /system/etc/hosts
adb -s 127.0.0.1:7555 unroot
```

## Flow observables

The first launch displayed Android 12's legacy-app permission review, then reached Mode Select. With the
hosts mapping installed, Continue produced `/world_list.php` and displayed `Local Dev World`. Selecting it
reached `LoginActivity`; accepting the client's original resource confirmation then produced:

```text
/check_inspection
-> /connect/app/notification/post_devicetoken
-> /connect/app/login
-> /connect/web/
```

The first native start aborted on the exact missing external-resource path:

```text
/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save/download/rest/treasurebox
```

This was not a Houdini or Android 12 crash. Reusing the already accepted small resource baseline
(`rest`, `scenario`, `pack`, startup master files, `adv_chara111`, and `bgm_common1.ogg`; 2,123 source files,
about 66.5 MiB) removed the failure without changing APK/native/server behavior. A cold relaunch returned to
`RooneyJActivity`, repeated the login chain, rendered the main menu within five seconds, and stayed alive
through the 5/10/15-second captures with no fatal exception.

The final main-menu interaction tapped Gacha and produced:

```text
/connect/app/gacha/select/getcontents
```

The response selected scene 9100, and the client visibly migrated to the Chinese general-gacha page while
the same `RooneyJActivity` process remained alive through the six-second capture.

A later stability check found that this process did not remain healthy indefinitely. About 269 seconds after the
gacha-select page opened, PID 4227 received `SIGSEGV` at null in the
`vector<smart_ptr<RewardBoxTagData>>` copy constructor (`librooneyj.so` PC `0x003657c6`, caller
`0x0040b03c`). There was no accompanying missing-resource message. Android restarted the task as a new process,
the login/web path ran again, and the client returned to a visible main menu. This is a real delayed stability
frontier; this round cannot attribute it specifically to Houdini because reward-box/client state is also in the
native path. It must be compared against ARM19 using the same idle-on-select-page condition before any fix.

Evidence is under
`work/kssma-a12-launch-20260817/`, especially:

- `world-2s.png`: local world rendered from the server response.
- `after-world-2s.png`: stable login screen.
- `preloaded-native-5s.png`: visible main menu.
- `preloaded-native-10s.png`: main-menu greeting overlay.
- `preloaded-native-15s.png`: main menu still alive.
- `mainmenu-gacha-6s.png`: visible gacha page after the route.
- `delayed-gacha-crash.txt`: delayed SIGSEGV PC/backtrace and attribution limit.
- `current-after-gacha.png`: automatic recovery to a visible main menu under the new process.
- `preloaded-native-logcat.txt`: native bridge/Activity evidence and no fatal crash after preload.

## Conclusion

This Android 12/MuMu instance is compatible with the current 32-bit ARM client through installation, login,
main-menu rendering, and immediate page navigation. It is materially more useful than the rejected Android 15
instance because it exposes and actually translates 32-bit `armeabi` code. `10.0.2.2` is confirmed, not merely
assumed. The delayed reward-box-path SIGSEGV prevents treating it as a fully accepted gameplay runtime today.

This round does not promote Android 12 to the default automated acceptance runtime. The existing
`work/kssma-runtime.ps1` gates, baseline checks, coordinate system, resource preload, and flow scenarios are still
ARM19-specific. Before promotion, add an explicit alternate-runtime profile instead of weakening those ARM19 guards,
then reproduce or reject the delayed gacha-select crash on ARM19 and run at least one complete existing gameplay
scenario with normalized 2560x1440 coordinates and an isolated artifact bundle.

## Installation automation follow-up

The alternate runtime now has an isolated, hash-verified installer without changing any ARM19 gate. See
`work/mumu-a12-deployment-card-20260817.md` for the accepted one-command deployment, full resource-pack contents,
hosts recovery behavior, real-device result, and remaining boundary.
