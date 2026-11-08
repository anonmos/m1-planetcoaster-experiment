#!/bin/zsh
# Dead-man's switch for Wine GUI tests (added 2026-11-08 after three storms).
#
# A Wine GUI test that hits nodrv can seed an explorer-respawn fork storm:
# thousands of unreapable exiting Rosetta processes, PID exhaustion in
# minutes. This reaper snapshots the process table, waits 60s, then SIGKILLs
# only Wine/Steam processes that did NOT exist at arm time — so a hung test
# is cleaned up automatically, while everything you already had running is
# untouched (PIDs are allowlisted, not pattern-blasted).
#
# Usage (local Terminal):
#   zsh scripts/reaper-guard.zsh &   # arm (prints baseline + PID)
#   ... run your Wine GUI test, watch for the window ...
#   touch /tmp/reaper.stop           # disarm if the test works
# If the test hangs: do nothing; the reaper fires at 60s and reports counts.
# If ssh itself stops working, fall back to Activity Monitor or reboot
# (see docs/runbook-wine-storm.md).

setopt NO_HUP

SNAP=/tmp/reaper-baseline-pids.txt
FLAG=/tmp/reaper.stop
rm -f "$FLAG"
pgrep -f 'wine|wineserver|Steam|steam|explorer\.exe|conhost' > "$SNAP" 2>/dev/null
echo "reaper armed at $(date): baseline $(wc -l < "$SNAP") matching procs."
echo "Fires in 60s unless disarmed:  touch $FLAG"

for i in {1..12}; do
  sleep 5
  if [[ -f "$FLAG" ]]; then
    print "reaper disarmed by $FLAG; test must have worked. Baseline left at $SNAP."
    rm -f "$FLAG"
    exit 0
  fi
done

print "reaper FIRING at $(date): killing Wine/Steam processes started after arming..."
fired=0
for pat in 'steam\.exe|steamwebhelper|SteamSetup|steamerrorreporter' \
           'services\.exe|explorer\.exe|conhost\.exe|wine-preloader|wine64-preloader|winedbg' \
           'WineCaptureProbe' \
           'wineserver'; do
  # shellcheck disable=SC2046
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    if ! grep -qx "$pid" "$SNAP" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null && fired=$((fired + 1))
    fi
  done
  sleep 1
done
print "reaper done: killed $fired new Wine/Steam processes."
print "process count now: $(ps aux | wc -l) (healthy = low four digits or fewer)"
print "leftovers that never drain are unreapable kernel husks: only a reboot clears those."
