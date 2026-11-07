#!/bin/zsh
# Escape hatch for Wine fork storms (formalized 2026-11-07 after two wedges).
#
# Mechanism: a Wine GUI process started with no WindowServer (e.g. over SSH)
# gets nodrv; Wine's service manager respawns explorer.exe in a tight loop and
# Rosetta forks pile up faster than the kernel reaps stuck-exiting processes
# (-> "fork: Resource temporarily unavailable", load 300+, ~10k procs).
#
# Order matters: stop respawners first (Steam + services + explorer), runtime
# (wineserver) last. caffeinate (display sleep holder) is left alone.
#
# Usage: zsh scripts/kill-wine-storm.zsh
#   Works over SSH *while forks still succeed*. If ssh itself fails with
#   "exec request failed on channel 0", only Activity Monitor (quit
#   wineserver first, then the wine/Steam horde) or a reboot can clear it.
#
# After the storm: verify with `ps aux | wc -l` (healthy is low four digits
# at most on this machine), then investigate before restarting anything
# (this script is also what `stop all` cannot do once the table is full).

setopt NO_HUP

stage() {
  local desc="$1"; shift
  print "--- $desc"
  # shellcheck disable=SC2145
  pkill -9 -f "$@" 2>/dev/null || true
  sleep 2
}

print "Wine storm kill-switch: $(date)"
stage "Steam processes (client, helpers, installers)" \
  'steam\.exe|steamwebhelper|SteamSetup|steamerrorreporter'
stage "Wine services + desktop + helpers (respawners)" \
  'services\.exe|explorer\.exe|conhost\.exe|winedbg|wine-preloader|wine64-preloader|winedevice|plugplay|svchost\.exe|rpcss|msiexec'
stage "Game + launcher processes" \
  'PlanetCoaster2\.exe|eldenring\.exe|CONTROLResonant\.exe|SandFall-Win64|Expedition33_Steam|start_protected_game\.exe|conhost\.exe'
stage "Capture helper" \
  'WineCaptureProbe'
stage "Wine servers (runtime last)" \
  'wineserver'

print "--- stale controller pidfiles"
rm -f /private/tmp/planetcoaster2-controller-*-*.pid 2>/dev/null || true

print "--- remaining processes: $(ps aux | wc -l)"
print "--- top names:"
ps -eo comm | sort | uniq -c | sort -rn | head -n 5
print "Done. If the count is still ~10k, reboot: the leftovers are unreapable kernel-exiting husks."
