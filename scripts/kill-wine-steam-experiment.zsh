#!/bin/zsh

PATTERN='(^|/|[[:space:]])wine([[:space:]]|$)|wineboot\.exe|rundll32\.exe.*wine\.inf|com\.franke\.Whisky|/Libraries/Wine/|steam\.exe|steamwebhelper(_real)?\.exe|steamservice\.exe|steamerrorreporter\.exe|PlanetCoaster2\.exe|conhost\.exe|winedevice\.exe|winedbg|wineserver|wine64-preloader|wine-preloader|wine64'

print 'Processes found before cleanup:'
ps -axo pid=,ppid=,comm=,args= 2>/dev/null | grep -Ei "$PATTERN" | grep -v '[g]rep' || print 'None found.'

print '\nSending TERM...'
WINEFORGE_RUNTIME='/Users/tim/Documents/Codex/2026-08-28/i-m/work/wineforge-runtime'
WINEFORGE_PREFIX='/Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D'
GPTK_RUNTIME='/Users/tim/Documents/Codex/2026-08-28/i-m/work/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine'
WHISKY_RUNTIME='/Users/tim/Library/Application Support/com.franke.Whisky/Libraries/Wine'
WHISKY_PREFIX='/Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D'
if [[ -x "$WINEFORGE_RUNTIME/bin/wineserver" ]]; then
  WINEPREFIX="$WINEFORGE_PREFIX" "$WINEFORGE_RUNTIME/bin/wineserver" -k 2>/dev/null || true
fi
if [[ -x "$GPTK_RUNTIME/bin/wineserver" ]]; then
  WINEPREFIX="$WINEFORGE_PREFIX" "$GPTK_RUNTIME/bin/wineserver" -k 2>/dev/null || true
fi
if [[ -x "$WHISKY_RUNTIME/bin/wineserver" ]]; then
  WINEPREFIX="$WHISKY_PREFIX" "$WHISKY_RUNTIME/bin/wineserver" -k 2>/dev/null || true
fi
for name in wine wineboot.exe steam.exe steamwebhelper.exe steamwebhelper_real.exe steamservice.exe steamerrorreporter.exe PlanetCoaster2.exe conhost.exe winedevice.exe winedbg wineserver wine64-preloader wine-preloader wine64; do
  killall -TERM "$name" 2>/dev/null || true
done
for pattern in 'steam\.exe' 'steamwebhelper(_real)?\.exe' 'steamservice\.exe' 'steamerrorreporter\.exe' 'PlanetCoaster2\.exe' 'conhost\.exe' 'winedevice\.exe' 'winedbg' 'wineserver' 'wine(preloader|64-preloader|64)?'; do
  pkill -TERM -f "$pattern" 2>/dev/null || true
done

sleep 3

print 'Sending KILL to anything remaining...'
for name in wine wineboot.exe steam.exe steamwebhelper.exe steamwebhelper_real.exe steamservice.exe steamerrorreporter.exe PlanetCoaster2.exe conhost.exe winedevice.exe winedbg wineserver wine64-preloader wine-preloader wine64; do
  killall -KILL "$name" 2>/dev/null || true
done
for pattern in 'steam\.exe' 'steamwebhelper(_real)?\.exe' 'steamservice\.exe' 'steamerrorreporter\.exe' 'PlanetCoaster2\.exe' 'conhost\.exe' 'winedevice\.exe' 'winedbg' 'wineserver' 'wine(preloader|64-preloader|64)?'; do
  pkill -KILL -f "$pattern" 2>/dev/null || true
done

print '\nProcesses remaining after cleanup:'
ps -axo pid=,ppid=,comm=,args= 2>/dev/null | grep -Ei "$PATTERN" | grep -v '[g]rep' || print 'None found.'
