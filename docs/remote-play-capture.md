# Steam Remote Play capture fix (WineForge + ScreenCaptureKit bridge)

Host: `local-heavy`. Game verified with: CONTROL Resonant (Steam AppID `3669870`).

## Symptom

Steam Remote Play into `local-heavy` (from Steam Deck or MacBook Air) shows a
black screen for both desktop streaming and in-game streaming. Disabling
hardware encoding/decoding did not help.

## Root cause

1. Steam on Wine always falls back to
   `Desktop BitBlt RGB + libyuv + scale + libx264`, because
   `CDesktopCaptureDWM: Couldn't find symbol DwmGetDxSharedSurface`
   (see `.../Steam/logs/streaming_log.txt`). There is no DXGI/DWM capture
   path under Wine.
2. `winemac` keeps no GDI desktop backing store, and D3DMetal games render
   to Metal/Cocoa, so that BitBlt captures black. Fingerprints of this
   state: `SessionStats` shows `AvgServerBitrate` ~130-160 Kbit/s for a
   1462x944 stream (solid black compresses to almost nothing),
   `AvgCaptureMS` ~0.4 ms, and `AvgConvertMS` ~6.9 ms.
3. Separate, unfixed: system-audio loopback fails with `0x80004001`. This
   fix is video-only.

## Fix architecture

- Native helper `build/WineCaptureProbe.app` (source
  `tools/steam-capture-probe/WineCaptureProbe.swift`, built with
  `scripts/build-winecaptureprobe.zsh`) captures the macOS main display via
  ScreenCaptureKit and publishes top-down BGRA frames to
  `/private/tmp/wine-sck-probe/latest-frame.wscf`. Status goes to
  `/private/tmp/wine-sck-live.log`.
- Wine patch `WineForge/dlls/winemac.drv/gdi.c` implements winemac
  `pGetImage` to serve that file to GDI `BitBlt` callers (i.e. Steam's
  desktop capture). A missing frame or one older than 1.5 s returns
  `ERROR_NOT_SUPPORTED`, which is what the black screen was.
- `scripts/control-steam.zsh` manages the helper: `start steam` /
  `start all` launch it (`open` on the hardcoded app path), wait up to 20 s
  for `Stream started for display` plus a frame fresher than 5 s, and reuse
  an already-healthy helper without relaunching. `stop all` stops it.
  TCC denial (`-3801` in the live log) is reported explicitly instead of
  streaming black silently.
- Host software x264 encode stays mandatory (no NVENC/AMF/VideoToolbox
  behind Wine's Windows encoder APIs). Client-side Metal hardware decoding
  works and can stay enabled. `gameoverlayrenderer` remains disabled in the
  controller environment, so desktop capture is the capture path by design.

## Debug logging (disk safety)

All high-volume logging is off by default:

- Wine GDI request logging (`wine-sck-gdi-pgetimage.log`) only with
  `WINE_SCREEN_CAPTURE_DEBUG=1`.
- Single-frame PPM dump + `wine-sck-gdi-pixels.log` only with
  `WINE_SCREEN_CAPTURE_DEBUG_DUMP_DIR` set.
- Helper per-frame/window logging only with `WINE_SCK_DEBUG=1`.
- Always on (tiny): helper errors plus one `Stream started` line per
  launch in `wine-sck-live.log`.

## Permission setup (do this exactly)

`WineCaptureProbe` must be allowed under System Settings → Privacy &
Security → Screen & System Audio Recording. The helper is ad-hoc signed,
so each rebuild produces a new code identity.

- Toggling the existing switch off/on does NOT rebind the grant and leads
  to a repeated consent prompt plus `-3801 "user declined TCC"` in
  `wine-sck-live.log`, i.e. black screen again.
- Correct procedure: select `WineCaptureProbe` in the permission list,
  remove it with the minus button, re-add it with the plus button
  (navigate to `build/WineCaptureProbe.app`), switch it on, then
  relaunch the helper (`stop all` / `start steam`, or `pkill -f
  WineCaptureProbe` + `open` the app).
- Do not rebuild the helper after granting unless prepared to repeat
  this remove/re-add step.

Verify health:

```zsh
tail -n 5 /private/tmp/wine-sck-live.log
ls -lt /private/tmp/wine-sck-probe/latest-frame.wscf
```

Want `Stream started for display ...` with no `-3801`, and a frame file
seconds old. On the next Remote Play session the server bitrate in
`streaming_log.txt` should read in the MBit/s range instead of ~150 Kbit/s.

## Audio fix (same bridge pattern)

Symptom: video streamed, but silence. Host log: `Recording system audio`
→ mix format fine → `couldn't initialize the audio client loopback:
0x80004001` (`E_NOTIMPL`) → `Failed to init system audio recording`.

Cause: Steam opens WASAPI `IAudioClient::Initialize(..., LOOPBACK)` on
the render endpoint. Wine's `mmdevapi` forwards that to
`get_loopback_capture_device` in the backend driver. `winepulse`
implements it (via the PulseAudio monitor source); `winecoreaudio` had no
handler at all, and macOS offers no monitor device anyway.

Fix, mirroring video:

- `WineForge/dlls/winecoreaudio.drv/coreaudio.c`:
  virtual `Wine SCK Loopback` capture device (stereo 48 kHz float32).
  `get_loopback_capture_device` (+ wow64 twin), mix/format/period/latency
  branches, and a unit-less stream whose `capture_resample` hook pumps
  PCM from WSAF snapshots into the normal capture bookkeeping. Empty
  until fed (silence, but `S_OK`). Exported as
  `patches/winecoreaudio-sck-loopback.patch`.
- Helper publishes `audio.wsaf` snapshots (tmp-file + rename): SCK system
  audio → canonical 48 kHz stereo float32 → 0.5 s window every ~100 ms.
  Two gotchas lived here: `SCStreamConfiguration` needs
  `sampleRate = 48000` + `channelCount = 2` set explicitly or SCK
  delivers zero audio buffers; and SCK delivers planar float32
  (`flags 41`), which must be interleaved before writing.
- Fast iteration without Steam: `tools/audio_loopback_probe.c` (+
  `audio_loopback_probe.exe`, `tools/run-audio-loopback-probe.zsh`)
  reproduces Steam's exact init sequence and reports packet/nonsilent/peak
  stats. It printed `0x80004001` before the fix, `0x00000000` after.
- Choppiness root causes found via Steam's `Over 960 sample audio gap`
  log lines: (1) whole snapshots dumped at once made capture position
  jump backward — fixed by metering ingestion to elapsed time;
  (2) starving Steam on missing/stale snapshots — fixed by feeding
  paced silence instead, so quiet scenes and tap stalls stay smooth;
  (3) unconditional per-pump headroom let fast pollers spin on an
  always-full buffer — removed, kept only an empty-buffer recovery kick;
  (4) SCK audio delivery can stall silently while video flows — helper
  watchdog re-attaches the audio output after 5 s of quiet on an
  established tap (visible as `audio tap silent 5s+, re-attaching` in
  the live log).
- The existing Screen Recording grant covers system-audio capture; no new
  permission type. Helper rebuilds still need the remove/re-add dance.

## Troubleshooting

| Observation | Meaning | Action |
|---|---|---|
| `-3801` in live log, stale frame | TCC denied for this binary identity | Remove/re-add app in Screen Recording, relaunch helper |
| Consent dialog loops on every launch | Helper build changed identity (or grant never bound) | Remove/re-add once, stop rebuilding |
| `did not publish a frame in time` | Helper up but no frames | Check permission, check display sleep/lock |
| Bitrate ~150 Kbit/s, black | Serving black/stale frames | Check frame freshness + live log |

## Full rebuild / recovery

The `WineForge/` checkout itself is git-ignored and lives on `local-heavy`
as a primary copy, with two backups: this repo's `patches/` exports, and
the fork at `github.com/anonmos/WineForge`, branch
`gptk4-tahoe-checkpoint` (contains the session-gate removal, Tahoe
patches, and the SCK `pGetImage` commit). Everything
needed to recreate the capture stack is versioned in this repo:

- `patches/wineforge-local-source.patch` — pre-existing macOS/Tahoe
  source fixes (Mach tracing, freetype paths, virtual display,
  `macdrv_main` session-gate removal).
- `patches/winemac-sck-capture.patch` — the SCK bridge: `pGetImage` in
  `dlls/winemac.drv/gdi.c` serving `/private/tmp/wine-sck-probe/`.
  Exported from nested commit `27b59d9` (`git diff bb6da7b 27b59d9`).
  Re-export after any future `gdi.c` change with that same command.
- `tools/steam-capture-probe/WineCaptureProbe.swift` — helper source.
- `scripts/build-winecaptureprobe.zsh` — helper build.
- `scripts/control-steam.zsh` — helper lifecycle.

From scratch on a fresh machine (Rosetta + Xcode license first, see
SUMMARY.md recovery outline):

```zsh
git clone https://github.com/Alien4042x/WineForge.git WineForge
git -C WineForge checkout 59dda45dba2229cce9eb83e6e4e55b408ec37e5e
git -C WineForge apply ../patches/wineforge-local-source.patch
git -C WineForge apply ../patches/winemac-sck-capture.patch
zsh scripts/build-wineforge-full.zsh
zsh scripts/build-winecaptureprobe.zsh
```

Shortcut when the fork is reachable — it already contains all three
layers, so the patch steps are unnecessary:

```zsh
git clone -b gptk4-tahoe-checkpoint git@github.com:anonmos/WineForge.git WineForge
zsh scripts/build-wineforge-full.zsh
zsh scripts/build-winecaptureprobe.zsh
```

Then restore the bottle (`scripts/restore-bottle.zsh` + game installs),
grant Screen Recording via remove/re-add (never just the toggle), and
`start steam`. Shortcut when only `gdi.c` changed and the build tree
still exists: `arch -x86_64 make -C build/wineforge-tls-build -j10`
followed by `make -C build/wineforge-tls-build install` — no full
rebuild, but the helper binary still changes identity, so the
remove/re-add permission step applies to helper rebuilds regardless.
