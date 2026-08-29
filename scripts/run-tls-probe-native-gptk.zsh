#!/bin/zsh
setopt NO_HUP

G='/Users/tim/Documents/Codex/2026-08-28/i-m/work/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine'
Q='/Users/tim/Documents/Codex/2026-08-28/i-m/work/native-gptk4-tls-probe-prefix'
EXE='/Users/tim/Documents/Codex/2026-08-28/i-m/work/tls_probe.exe'

if [[ ! -x "$G/bin/wine64" || ! -f "$EXE" ]]; then
  print -u2 'GPTK 4 wine64 or tls_probe.exe is missing.'
  exit 1
fi

run_wine() {
  arch -x86_64 env \
    PATH="$G/bin:$PATH" \
    WINEPREFIX="$Q" WINEARCH=win64 \
    WINESERVER="$G/bin/wineserver" \
    WINELOADER="$G/bin/wine64" \
    WINEDLLPATH="$G/lib/wine" \
    DYLD_LIBRARY_PATH="$G/lib:$G/lib/wine/x86_64-unix:$G/lib/external" \
    DYLD_FALLBACK_LIBRARY_PATH="$G/lib:$G/lib/wine/x86_64-unix:$G/lib/external" \
    WINEESYNC=0 WINEMSYNC=0 WINEFSYNC=0 \
    WINEDEBUG='+err,+secur32,+winhttp' \
    "$G/bin/wine64" "$@"
}

print "Running HTTPS/TLS probe with GPTK 4 native Wine"
run_wine "$EXE"
