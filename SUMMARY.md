# GPTK 4 + WineForge Steam / Planet Coaster 2 checkpoint

This directory records the working configuration reached on 2026-08-29 for
Planet Coaster 2 (Steam AppID `2688950`) on Apple Silicon macOS 26.6.2.

## Working result

The working Steam stack is WineForge's patched x86_64 Wine runtime plus
GPTK 4's D3DMetal and GnuTLS libraries. Steam launches successfully when run
from the user's normal Terminal with the repaired WineForge runtime.

The small `tools/tls_probe.exe` test completes an HTTPS request with status
200 through the repaired WineForge stack. GPTK 4's native Wine also passes
the TLS probe, but native GPTK Wine failed to start this Steam installation
at `COMCTL32.dll` initialization, so it is not the selected Steam runtime.

## Source and toolchain

- `WineForge/` is a clone of `https://github.com/Alien4042x/WineForge.git`.
- Pinned source commit: `59dda45dba2229cce9eb83e6e4e55b408ec37e5e`.
- `patches/wineforge-local-source.patch` contains the four pre-existing
  WineForge source changes used for macOS/Tahoe behavior.
- `toolchain/gptk-extract/` is the extracted GPTK 4 toolkit from the Apple
  Game Porting Toolkit 4 beta 2 evaluation environment.
- `toolchain/gnutls-headers/` contains the GnuTLS headers and source archive
  used to configure the WineForge build.
- Generated Wine builds are intentionally excluded from Git; rebuild them
  with `scripts/build-wineforge-tls.zsh`.

## Source patches

The WineForge source patch changes:

1. `dlls/ntdll/unix/server.c`: tolerate failure of the optional Mach tracing
   server port instead of aborting Wine.
2. `server/mach.c`: disable optional Mach tracing when newer macOS rejects
   its bootstrap registration.
3. `dlls/win32u/freetype.c`: honor `WINE_FREETYPE_PATH` and
   `WINE_FONTCONFIG_PATH` so the runtime can use known compatible libraries.
4. `dlls/win32u/sysparams.c`: provide a deterministic virtual-display
   fallback when macOS display enumeration returns no usable monitor. The
   forced virtual-display environment setting was later removed from the
   launcher because it hid normal GUI windows.

## Schannel/GnuTLS repair

The WineForge configure probe recorded an `otool` description as
`SONAME_LIBGNUTLS`, rather than a filename. That caused `dlopen()` to fail
and produced `no schannel support`.

The repair is applied in `scripts/build-wineforge-tls.zsh` after configure:

```c
#define SONAME_LIBGNUTLS "libgnutls.30.dylib"
```

`secur32` is then rebuilt and installed into the generated runtime. GPTK's
versioned GnuTLS library and dependencies are supplied through
`DYLD_LIBRARY_PATH` and `DYLD_FALLBACK_LIBRARY_PATH`.

The failed intermediate modules are preserved in the original working
runtime as `secur32.gptk-native.so` and `secur32.wineforge-rebuilt.so`; the
checkpoint rebuild script should be preferred for future recovery.

## Runtime scripts

- `scripts/control-planetcoaster2.zsh`: start/stop Steam and the game. It
  supports `start steam`, `start game`, `stop steam`, `stop game`, `start all`,
  and `stop all`. Set `WINE_RUNTIME`, `WINE_EXEC`, `WINE_SERVER`,
  `GPTK_WINE`, or `WINEPREFIX` to override paths.
- `scripts/kill-wine-steam-experiment.zsh`: emergency cleanup for Wine,
  Steam, helpers, `conhost`, and Planet Coaster 2 processes.
- `scripts/build-wineforge-tls.zsh`: configure/build the repaired WineForge
  TLS runtime under `build/`.
- `tools/run-tls-probe-wineforge.zsh`: isolated HTTPS verification.
- `tools/run-tls-probe-native-gptk.zsh`: comparison test for GPTK native Wine.

## Recovery outline

1. Obtain/extract GPTK 4 into `toolchain/gptk-extract/` and restore the
   GnuTLS inputs under `toolchain/gnutls-headers/`.
2. Apply `patches/wineforge-local-source.patch` to the pinned `WineForge/`
   checkout if starting from a fresh clone.
3. Run `scripts/build-wineforge-tls.zsh`.
4. Run `tools/run-tls-probe-wineforge.zsh`; require `HTTPS status: 200`.
5. Set the bottle path in `scripts/control-planetcoaster2.zsh` if the Whisky
   bottle UUID changed.
6. Use the cleanup script before starting a new experiment, then run the
   controller's `start steam` and `start game` commands.

The Steam/Planet Coaster paths are currently tied to Whisky bottle
`66589F31-3F31-4D59-AC97-90EE21022A1D`; update `WINEPREFIX` when restoring on
a new installation.
