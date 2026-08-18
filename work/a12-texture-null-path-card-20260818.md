# A12 battle texture-null path classifier (2026-08-18)

## Bounded round

- Frontier: fairy battle serial 100011 crossed the former missing master-card/`adv_chara0` gate, then A12 ART
  aborted on `GetObjectClass(null)` while entering the battle flow.
- Success: record the exact final texture path and whether it came from `loadTexture` or
  `loadTextureWithRect`, then preserve the crash log as an artifact.
- Non-goal: do not change server XML, card values, battle settlement, resources, native code, emulator
  resolution, or gameplay state.
- Stop: one user-driven reproduction after the logging baseline is installed. Restore the normal baseline before
  any product fix; do not repeat without a new path/exception observable.

## Static path

The accepted native library contains only two direct `JNIEnv::GetObjectClass` calls:

- `jni_loadTexture(char const*, float)` at `0x001b0f6c`, call at `0x001b0fd0` after
  `com/test/TextureLoader.loadTexture(String,float)`.
- `jni_loadTextureWithRect(char const*,int,int,int,int)` at `0x001b112c`, call at `0x001b1192` after
  `com/test/TextureLoader.loadTextureWithRect(String,int,int,int,int)`.

Both native wrappers pass the Java return value directly to `GetObjectClass` without a null check. The A12 abort
therefore proves one Java texture entry point returned null, not that the adjacent MediaPlayer transition failed.

Java bytecode confirms that `TextureLoader.loadTexture(String,float)` stores the path and calls
`JResourceLoader.loadBitmap`; its existing `Debug.log_cjh(path, [])` call is compiled as a no-op. The rect variant
already formats its path and crop rectangle through `Debug.detail`, which is likewise silent in this build.

## Single diagnostic variable

`work/build-client-baseline.py` keeps its default output unchanged. With
`KSSMA_TEXTURE_PATH_DIAGNOSTIC=1`, it verifies the stock `classes.dex` SHA-256
`985D4105968A95EC9DFE9BCC3711597A324A90F472700DF7435CA7D25A2087C6`, changes only two same-signature method
references to the existing `Debug.err(String,Object[])`, and recomputes the DEX SHA-1 and Adler-32 headers:

- file offset 273780: method index `0x07d0` (`Debug.log_cjh`) -> `0x07cc` (`Debug.err`);
- file offset 273902: method index `0x07cb` (`Debug.detail`) -> `0x07cc` (`Debug.err`).

Control flow, registers, instruction widths, APK assets, manifest, and `librooneyj.so` remain unchanged. The
unique baseline manifest records whether this temporary diagnostic is active and pins the resulting DEX hash.

## Result

The one reproduction produced the exact pending exception:

```text
java.lang.RuntimeException: ファイルが開けません:
/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save/download/image/adv/adv_chara0
at JResourceLoader.loadFile -> loadBitmap -> TextureLoader.loadTexture -> GLRenderer.nativeMain
```

It used the ordinary `loadTexture(String,float)` path, not the rect variant. The path proves this is the original
zero image-id consequence of an unresolved card master, not an A12 audio or texture-decoder incompatibility.
Artifact: `work/mumu-a12-texture-null-path-live-20260818/`.
