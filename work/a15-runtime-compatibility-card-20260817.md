# Android 15 runtime compatibility card (2026-08-17)

## Frontier

Determine whether the user-provided Android 15 emulator at `127.0.0.1:5555` can install and launch
the unique KSSMA-Re client baseline. This round does not change the APK, server URLs, hosts file,
resource mount, or the accepted ARM19 runtime.

## Device fingerprint

The emulator connected through the host ADB server and returned:

```text
serial=127.0.0.1:5555
state=device
release=15
sdk=35
abi=x86_64
abilist=x86_64,arm64-v8a,x86
abilist32=x86
native_bridge=libnb.so
model=HONOR PGT-AN20
boot_completed=1
```

The device had about 100 GiB free under `/data`, and `com.square_enix.million_cn` was not already
installed.

## Client ABI evidence

- Tested APK: `work/client-baseline/KSSMA-Re-client-baseline.apk`.
- Tested SHA-256: `4506D64561F4EFA93952CA068BA596758C27ACD5132221B6E56D9AB67AD31AF7`.
- Its only native library is `lib/armeabi/librooneyj.so`.
- ELF inspection reports `ELFCLASS32`, `EM_ARM`, little endian.

The emulator advertises an ARM64 entry through its native bridge but does not advertise a 32-bit ARM
ABI. The presence of `libnb.so` alone is therefore not evidence that this instance translates
`armeabi` applications.

## Installation observables

Normal installation transferred all 304646358 bytes, then PackageManager rejected the APK:

```text
Failure [INSTALL_FAILED_NO_MATCHING_ABIS:
Failed to extract native libraries, res=-113]
```

A second bounded installation explicitly selected the client ABI:

```powershell
adb -s 127.0.0.1:5555 install --abi armeabi-v7a -r -f `
  .\work\client-baseline\KSSMA-Re-client-baseline.apk
```

It was rejected before package creation:

```text
java.lang.IllegalArgumentException: ABI armeabi-v7a not supported on this device
```

`pm path com.square_enix.million_cn` remained empty after both attempts.

## Conclusion

This Android 15 instance cannot install the current 32-bit ARM client, so it cannot be used for game
or settlement acceptance. No client process, Activity, network request, or game screenshot exists
from this experiment. This is an ABI rejection, not an Android-15 target-SDK rejection and not a
server-address failure.

Do not change `10.0.2.2`, hosts, or server XML to address this result. A replacement emulator must
first expose `armeabi-v7a` or `armeabi` in its usable 32-bit ABI set (natively or through a working
ARM32 translation layer). Only after installation and LogoActivity survival should its host gateway
be tested; the server already emits `http://10.0.2.2:50005/` by default, but a third-party emulator
may use a different host gateway.
