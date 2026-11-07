# Wine fork-storm runbook (local-heavy)

Written 2026-11-07 after the machine wedged *twice* in one day
(~8.5k stuck `explorer.exe`, load 300-900, `fork: Resource temporarily unavailable`).

## Mechanism

1. A Wine GUI process starts with no WindowServer (SSH shells never have one).
2. `winemac` cannot load -> `nodrv` ("no graphics driver"), explorer/desktop dies instantly.
3. Wine's service manager respawns it in a tight loop; each spawn is a Rosetta
   fork that exits stuck (`?E` state, parented to launchd, unkillable).
4. PIDs exhaust in minutes. New forks fail everywhere (`ssh ... exec request
   failed on channel 0`), load explodes, only Activity Monitor/reboot helps.

Triggers hit so far: headless `wineboot --init`, headless `SteamSetup.exe /S`,
fresh-prefix `winecfg`, and any `control-steam.zsh start ...` over SSH.

## Prevention (enforced in scripts)

- `scripts/control-steam.zsh`: `start steam/game/all` refuse over SSH
  (`SSH_CONNECTION`/`SSH_CLIENT` set). `stop ...` stays allowed on purpose:
  stopping only removes processes, so SSH remains a remote kill switch.
- `scripts/create-bottle-fresh.zsh`, `scripts/run-steam-capture-probe.zsh`:
  refuse over SSH for the same reason.
- Headless-safe (no WindowServer needed): `stop` actions,
  `scripts/kill-wine-storm.zsh`, `tools/run-tls-probe-wineforge.zsh`,
  builds (`make`, `xcodebuild`), git/file ops, `otool`/`sample`/`log show`.
- Local-Terminal-only: every `start`, `winecfg`, installers, any game exe.

## Escape hatch

Prefer in this order (each step needs one free PID; act early):

1. `zsh scripts/control-steam.zsh stop all` (graceful).
2. `zsh scripts/kill-wine-storm.zsh` (SIGKILL in dependency order:
   Steam -> services/explorer/conhost/preloaders -> games/launchers ->
   capture helper -> wineserver; clears stale pidfiles; prints counts).
3. If ssh fails with `exec request failed on channel 0`: Activity Monitor
   on the Mac itself (quit `wineserver` first, then the wine/Steam horde).
4. If the horde is unkillable `?E` husks (count stuck ~10k): reboot.
   Post-reboot: verify `ps aux | wc -l` is sane, then rebuild/restart
   deliberately — never auto-start Wine on boot/login.

## Verification after recovery

- `ps aux | wc -l` low four digits or fewer.
- `uptime` load back under ~10 and falling.
- No `wineserver`/`explorer.exe` stragglers: `pgrep -fl wineserver|explorer`.
- Only then: rebuilds/Steam/game restarts, from the local Terminal.
