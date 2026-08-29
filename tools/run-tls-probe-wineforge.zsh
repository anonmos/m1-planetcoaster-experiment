#!/bin/zsh
setopt NO_HUP

ROOT="${CHECKPOINT_ROOT:-${0:A:h:h}}"
R="${WINE_RUNTIME:-$ROOT/build/wineforge-runtime}"
Q="${TLS_PROBE_PREFIX:-$ROOT/build/gptk4-tls-probe-prefix}"
G="${GPTK_WINE:-$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine}"
EXE="$ROOT/tools/tls_probe.exe"

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
