# GPTK 4 + WineForge Steam / Windows games checkpoint

This directory records the working configuration reached on 2026-08-29 for
Planet Coaster 2 (Steam AppID `2688950`) on Apple Silicon macOS 26.6.2,
plus the full-runtime rebuild performed on 2026-09-20 after the host moved
to macOS 27.0 (which deleted the `build/` runtime and broke two Wine
subsystems; both fixes are recorded below and in
`scripts/build-wineforge-full.zsh`).

## Working result

The working Steam stack is WineForge's patched x86_64 Wine runtime plus
GPTK 4's D3DMetal and GnuTLS libraries. Steam launches successfully when run
from the user's normal Terminal with the repaired WineForge runtime. On
2026-09-20 the runtime was rebuilt from scratch on macOS 27.0 and re-verified:
`tools/run-tls-probe-wineforge.zsh` reports `HTTPS status: 200`, Steam shows
windows and rendered text, and the logged-in account was switched in the
Steam UI (bottle previously on `maudcc91`).

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
5. `dlls/winemac.drv/macdrv_main.c` (added 2026-09-20 for macOS 27): remove
   the `SessionGetInfo`/`sessionHasGraphicAccess` gate entirely. On macOS 27
   the call misfires for normal local Aqua launches (it fails outright with
   `status=100022`, or succeeds with e.g. `attrs=0x5020` and no graphic-access
   bit `0x0010`), which unloaded winemac and left `nodrv` behind with no
   windows for any app. A genuinely headless session still fails below in
   `macdrv_start_cocoa_app` with a clear message.

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

## Schannel/freetype SONAME repairs (configure probe bug)

The same `otool`-capture failure hits `SONAME_LIBFREETYPE` when GPTK paths
are in `LDFLAGS` (found 2026-09-20: `config.h` contained a whole otool line,
`"... libfreetype.dylib (compatibility version 27.0.0 ...)"`, as the name).
`dlls/dwrite/freetype.c` ignores `WINE_FREETYPE_PATH` and `dlopen`s that
garbage string, so Steam's Chromium UI lost all text
(`Wine cannot find the FreeType font library.` x N, only in dwrite-loading
processes). Repaired the same way in `scripts/build-wineforge-tls.zsh` and
`scripts/build-wineforge-full.zsh`:

```c
#define SONAME_LIBFREETYPE "libfreetype.6.dylib"
```

A `config.h` define change does NOT trigger recompiles on its own: after
either repair, force-rebuild the dependents (`dlls/secur32`, `dlls/dwrite`,
`dlls/win32u`) before installing.

## Runtime library closure (`R/lib`)

`WINE_FREETYPE_PATH`/`WINE_FONTCONFIG_PATH` point at `R/lib`, so every
`@loader_path`/`@rpath` dependency of those two libraries must also live in
`R/lib` (`@loader_path` does not consult `DYLD_*`). `scripts/build-wineforge-full.zsh`
syncs the full closure: `libfreetype.6` + `libz.1`, `libbz2.1.0`,
`libpng16.16`, `libbrotlidec.1`, `libbrotlicommon.1` (x86_64, from GPTK),
plus `libfontconfig.1`, exact-name `libexpat.1.10.2` (x86_64, from GPTK's
GStreamer bundle), and `libintl.8`. Note `/opt/homebrew` fontconfig is
arm64-only and unusable here; only its headers are used at build time.

The failed intermediate modules are preserved in the original working
runtime as `secur32.gptk-native.so` and `secur32.wineforge-rebuilt.so`; the
checkpoint rebuild script should be preferred for future recovery.

## Runtime scripts

- `scripts/control-planetcoaster2.zsh`: start/stop Steam and either installed
  game. Use `start game pc2` for Planet Coaster 2 (AppID `2688950`) or
  `start game 33` for Clair Obscur: Expedition 33 (AppID `1903340`). Matching
  `stop game pc2` and `stop game 33` commands are also supported; the older
  `start game`/`stop game` forms continue to mean Planet Coaster 2. The script
  also supports `start steam`, `start all`, and `stop all`. Set `WINE_RUNTIME`, `WINE_EXEC`, `WINE_SERVER`,
  `GPTK_WINE`, or `WINEPREFIX` to override paths.
- `scripts/kill-wine-steam-experiment.zsh`: emergency cleanup for Wine,
  Steam, helpers, `conhost`, and Planet Coaster 2 processes. Points at the
  current `build/wineforge-runtime` (fixed 2026-09-20; it previously
  referenced a deleted August work path, which silently disabled its
  `wineserver -k` step).
- `scripts/build-wineforge-tls.zsh`: configure/build the repaired WineForge
  TLS runtime under `build/`. Now applies both SONAME repairs (GnuTLS +
  freetype). Note it is still a repair-only script: it does not `make
  install`, sync external libs, or handle the macOS build-environment
  quirks below.
- `scripts/build-wineforge-full.zsh` (added 2026-09-20): canonical full
  rebuild — preflight (Xcode license, Rosetta, bison ≥ 3, mingw),
  out-of-source configure under Rosetta, both SONAME repairs, full
  `make -j10` + `make install` (with one automatic retry over parallel
  `ranlib` races), D3DMetal + freetype/fontconfig closure sync, and the
  `secur32` repair. This is the script to run after any macOS/Xcode update
  or `build/` loss.
- `scripts/control-planetcoaster2.zsh`: also fixed 2026-09-20 — `find_pids`
  now matches Wine-spawned children by their `C:\...` argv paths (they carry
  no trace of the macOS bottle path, so `stop` previously missed all
  helpers/service), and `stop all` ends with a catch-all sweep
  (`services/plugplay/svchost/explorer/rpcss` included) because
  `wineserver -k` cannot kill orphans of an already-dead server.
- `tools/run-tls-probe-wineforge.zsh`: isolated HTTPS verification.
- `tools/run-tls-probe-native-gptk.zsh`: comparison test for GPTK native Wine.

## Recovery outline

1. Accept the Xcode license (`sudo xcodebuild -license`) and install Rosetta
   (`softwareupdate --install-rosetta --agree-to-license`; verify with
   `arch -x86_64 true`). Both are hard requirements: git/clang refuse to run
   without the former, and x86_64 configure tests plus all Wine processes
   need the latter.
2. Obtain/extract GPTK 4 into `toolchain/gptk-extract/` and restore the
   GnuTLS inputs under `toolchain/gnutls-headers/`. Homebrew `bison` ≥ 3
   must precede `/usr/bin` on PATH (`/opt/homebrew/opt/bison/bin`); the
   script handles this itself.
3. Apply `patches/wineforge-local-source.patch` to the pinned `WineForge/`
   checkout if starting from a fresh clone.
4. Run `scripts/build-wineforge-full.zsh` (full rebuild; prefer over
   `build-wineforge-tls.zsh`, which is repair-only).
5. Run `tools/run-tls-probe-wineforge.zsh`; require `HTTPS status: 200`.
6. Set the bottle path in `scripts/control-planetcoaster2.zsh` if the Whisky
   bottle UUID changed.
7. Use the cleanup script before starting a new experiment, then run the
   controller's `start steam` and `start game` commands. Steam must be
   started from the user's normal Terminal (agent/background shells have no
   WindowServer access).

The working Steam and Planet Coaster 2 installation used for this checkpoint
resides in Whisky bottle `66589F31-3F31-4D59-AC97-90EE21022A1D`. This is a path
reference, not a claim that the installations were inherited from the earlier
setup: Steam and Planet Coaster 2 were reinstalled/initialized in this bottle
as part of the WineForge experiment. The checkpoint does not contain the Steam
or game files. When restoring on another installation, create or use the new
bottle, install Steam and Planet Coaster 2 there, and set `WINEPREFIX` to that
bottle's path.
