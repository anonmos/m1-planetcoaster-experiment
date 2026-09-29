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

## Troubleshooting

| Observation | Meaning | Action |
|---|---|---|
| `-3801` in live log, stale frame | TCC denied for this binary identity | Remove/re-add app in Screen Recording, relaunch helper |
| Consent dialog loops on every launch | Helper build changed identity (or grant never bound) | Remove/re-add once, stop rebuilding |
| `did not publish a frame in time` | Helper up but no frames | Check permission, check display sleep/lock |
| Bitrate ~150 Kbit/s, black | Serving black/stale frames | Check frame freshness + live log |
