#!/bin/zsh
setopt NO_HUP

R='/Users/tim/Documents/Codex/2026-08-28/i-m/work/wineforge-runtime'
Q='/Users/tim/Documents/Codex/2026-08-28/i-m/work/gptk4-tls-probe-prefix'
G='/Users/tim/Documents/Codex/2026-08-28/i-m/work/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine'
EXE='/Users/tim/Documents/Codex/2026-08-28/i-m/work/tls_probe.exe'

if [[ ! -x "$R/bin/wine" || ! -f "$EXE" ]]; then
  print -u2 'WineForge runtime or tls_probe.exe is missing.'
  exit 1
fi

run_wine() {
  arch -x86_64 env \
    PATH="$R/bin:$PATH" \
    WINEPREFIX="$Q" WINEARCH=win64 \
    WINESERVER="$R/bin/wineserver" \
    WINELOADER="$R/bin/wine" \
    WINEDLLPATH="$R/lib/wine" \
    DYLD_LIBRARY_PATH="$G/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
    DYLD_FALLBACK_LIBRARY_PATH="$G/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
    WINE_FREETYPE_PATH="$R/lib/libfreetype.6.dylib" \
    WINE_FONTCONFIG_PATH="$R/lib/libfontconfig.1.dylib" \
    FONTCONFIG_FILE='/opt/homebrew/etc/fonts/fonts.conf' \
    FONTCONFIG_PATH='/opt/homebrew/etc/fonts' \
    WINEESYNC=0 WINEMSYNC=0 WINEFSYNC=0 \
    WINEDEBUG='+err,+secur32,+winhttp' \
    "$R/bin/wine" "$@"
}

print 'Running HTTPS/TLS probe against https://www.cloudflare.com/'
run_wine "$EXE"
