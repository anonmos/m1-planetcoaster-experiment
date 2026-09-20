#!/bin/zsh
# Create a fresh Steam bottle from zero (no Whisky UI needed).
#
# Produces a win64 Wine prefix with Steam silently installed, usable with
# scripts/control-steam.zsh via WINEPREFIX. Verified 2026-09-20 against a
# throwaway prefix (Steam reached the login window; no login performed).
#
# Usage: zsh scripts/create-bottle-fresh.zsh [prefix-path]
#   Default prefix: ~/Bottles/steam-fresh
#
# Afterwards:
#   1. WINEPREFIX=<prefix> zsh scripts/control-steam.zsh start steam
#   2. Log in via the Steam UI (credentials + Steam Guard; interactive).
#   3. Install the games via Steam (AppIDs: 2688950, 1903340, 1245620).
#   4. Re-apply prefix-local tweaks (see SUMMARY.md, Elden Ring section).

set -e

ROOT="${0:A:h:h}"
R="${WINE_RUNTIME:-$ROOT/build/wineforge-runtime}"
WINE_EXEC="${WINE_EXEC:-$R/bin/wine}"
WINE_SERVER="${WINE_SERVER:-$R/bin/wineserver}"
GPTK="${GPTK_WINE:-$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine}"
P="${1:-$HOME/Bottles/steam-fresh}"
INSTALLER="${STEAM_SETUP_EXE:-/private/tmp/SteamSetup.exe}"
STEAM_URL="${STEAM_SETUP_URL:-https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe}"

[[ -x "$WINE_EXEC" && -x "$WINE_SERVER" ]] || { print -u2 "WineForge runtime missing: $R (run build-wineforge-full.zsh first)"; exit 1 }
[[ -d "$GPTK/lib" ]] || { print -u2 "GPTK extract missing: $GPTK"; exit 1 }
if [[ -e "$P" ]]; then
  print -u2 "Prefix path exists: $P (pass another path or move it aside)"
  exit 1
fi

run_wine() {
  arch -x86_64 env \
    PATH="$R/bin:$PATH" \
    WINEPREFIX="$P" WINEARCH=win64 \
    WINESERVER="$WINE_SERVER" \
    WINELOADER="$WINE_EXEC" \
    WINEDLLPATH="$R/lib/wine" \
    DYLD_LIBRARY_PATH="$GPTK/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
    DYLD_FALLBACK_LIBRARY_PATH="$GPTK/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
    WINE_FREETYPE_PATH="$R/lib/libfreetype.6.dylib" \
    WINE_FONTCONFIG_PATH="$R/lib/libfontconfig.1.dylib" \
    FONTCONFIG_FILE='/opt/homebrew/etc/fonts/fonts.conf' \
    FONTCONFIG_PATH='/opt/homebrew/etc/fonts' \
    WINEESYNC=0 WINEMSYNC=0 WINEFSYNC=0 \
    WINEDEBUG="${WINE_DEBUG_MODE:--err}" \
    "$WINE_EXEC" "$@"
}

print "==> Initializing prefix: $P"
mkdir -p "$P"
run_wine wineboot --init

if [[ ! -f "$INSTALLER" ]]; then
  print "==> Downloading Steam installer"
  curl -L --fail -o "$INSTALLER" "$STEAM_URL"
fi
ls -lh "$INSTALLER"

print "==> Silent-installing Steam (/S) — takes several minutes"
run_wine "$INSTALLER" /S

STEAM="$P/drive_c/Program Files (x86)/Steam/steam.exe"
[[ -f "$STEAM" ]] || { print -u2 "Steam install did not produce $STEAM"; exit 1 }

print "==> Fresh bottle ready: $P"
print "Start it with: WINEPREFIX=\"$P\" zsh scripts/control-steam.zsh start steam"
