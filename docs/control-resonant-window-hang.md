# CONTROL Resonant window hang — diagnosis and fix (2026-11-08)

## Symptom

After the WineForge 0.6.0.3 → 0.6.0.8 / Wine 11.16 → 11.21 upgrade,
CONTROL Resonant (AppID 3669870, Remedy Northlight) never opens its window.
The game process stays alive at ~0% CPU indefinitely. Two stable failure
modes were observed across boots:

- **hang-mode**: renderer thread stuck inside `CreateWindowExW`, everything
  else parked. Deterministic once reached.
- **exit-mode**: main thread parks at the scheduler gate right after
  registering `AppWindowClass`; the renderer thread is never spawned.

## Hang site (verified 6x, hang-mode)

```
win32u (+0x13464)                         = NtUserGetClassInfoEx+0x14
  (PE win32u.dll base 0x180000000: 0x180013450+0x14, verified by disassembly)
user32 WIN_CreateWindowEx+0x98            = call *NtUserGetClassInfoEx return
  (verified: 0x1800581a0+0x98 = 0x180058238, the import call site)
CONTROLResonant.exe+0x3fbcd4              = game return address
  args: ex=0x40000, class=atom 0xC053, title "CONTROL Resonant",
  style=0x90000000 (WS_POPUP|WS_VISIBLE), 0,33,1728,1117
```

RIP-stable across 10-minute-spaced captures, 0.0% CPU on every thread
(`ps -M`), wineserver healthy and serving other clients throughout.

## Dead ends (each killed by evidence)

- **Atom mechanism**: probe registering + creating via atom 0xC053 with
  identical args succeeds instantly. The game/probe even drew the same atom.
- **Seqlock livelock**: `get_shared_class` always pairs acquire→success in
  2 trace lines; spinning would burn a core (0% observed).
- **Server-side block**: `server/window.c:get_desktop_window` handler is
  straight-line code; wineserver sampled healthy mid-hang.
- **user_lock holder**: exhaustive backtrace scans across 5 captures show no
  game thread inside user32; zero `SuspendThread`/`TerminateThread` in
  556 MB of relay log.
- **Overlay hooks**: `gameoverlayrenderer` never loads in the game process.
- **Network/Steam wait**: zero sockets in the stalled process.
- **Power state**: display awake throughout; caffeinate hold changed nothing.
- **WindowMode**: engine-flipped `2→1` at 13:33 (not by us); mode 0/2 boots
  behave the same. `renderer.ini` geometry (1728x1117) matches the hung call.
- **`RegisterClassW` err=123**: our own missing `lpszClassName`, not a bug.

## Root cause

`tools/cr_repro_giN.exe` reproduces the hang deterministically: the ONLY
difference vs the working variants is linking the game's real icon 101
(PNG-compressed 256px frames + BMP frames).

First GUI call in the process → `get_desktop_window` →
`macdrv_SetDesktopWindow` → `pthread_once(set_app_icon)` →
`create_app_icon_images` → `KeUserDispatchCallback(macdrv_app_icon)`,
which enumerates `RT_GROUP_ICON` 101 and `CreateIconFromResourceEx`s each
frame. The returned `entries[]` come back corrupt
(`{icon:0, 32x16842810}` — a 2.1 GB phantom DIB), the 48px frame fails with
`Error retrieving icon frame 0`, and the worker thread wedges right after
its desktop query — the same pre-`desktop step done` stall as the game,
same backtrace, same silence.

Icon matrix (all in `tools/`, rebuildable): every single frame alone OK,
BMP-only subsets OK, PNG pairs OK — only the full multi-frame set with
PNGs hangs. The corruption needs the full group parse.

## Fix (WineForge, committed)

Commit `26292f90` (`winemac: harden app-icon scan`):

- `dlls/winemac.drv/dllmain.c`: zero `entries[64]` so skipped frames are
  deterministic instead of stack garbage.
- `dlls/winemac.drv/image.c` (`create_app_icon_images`): skip null-handle
  entries instead of feeding them downstream.
- `dlls/winemac.drv/image.c` (`create_cgimage_from_icon`): reject insane
  dimensions (≤0 or >512) instead of attempting multi-GB DIB allocations.

Diagnostic scaffolding kept in history: `ccc35ba3`, `ed1c9bd1`
(per-line TRACE through `NtUserGetClassInfoEx`/`get_desktop_window`;
zero cost with channels off).

Rebuilt `build/wineforge-runtime` in place (backup at
`build/wineforge-runtime.bak-20261108`; TLS probe still 200).

## Verification

- `tools/cr_repro_giN.exe` (hung 5/5 pre-fix): creates its window
  post-fix. Matrix exes (`cr_1f*.exe`, `cr_2m*.exe`, `cr_m3/m4.exe`) available.
- Game boot post-fix: `docs/hang-evidence/cr-BOOT-SUCCESS-20261108.log`
  shows the 1728x1117 top-level window (`0x101d6`) created, receiving mouse
  input (`TrackMouseEvent`, hittest) and presenting client surfaces —
  first successful boot.

## Reproducer usage

```zsh
# needs: same prefix env as scripts/control-steam.zsh run_wine
./build/wineforge-runtime/bin/wine ./tools/cr_repro_giN.exe
# exit 0 + "SUCCESS"  -> window path healthy
# exit 2 + "HANG ..." -> window creation wedged (watch 20s/90s watchdog)
```

`tools/cr_repro.c` is the source of truth (self-diagnosing, ~20s watchdog);
`tools/reg_probe.c` maps RegisterClass W/Ex behavior; `tools/resume.exe`
resumes a thread by TID; icon fixtures `game101.ico` (poisonous),
`gameBMP.ico`, `one_*.ico`, `multi_*.ico` + `mkicons*.py` generators.

## Open items

- hang-vs-exit bimodality trigger (why some boots never spawn the renderer
  thread) is unexplained; exit-mode stalls are scheduler-idle, not Wine wedge.
- The exact wait primitive inside/after `set_app_icon` was never isolated
  (host-level, invisible to Wine tooling); hardening removes the corrupt
  input that leads there.
- Consider upstreaming the winemac hardening + a `+class` hang capture if
  any regression appears.
