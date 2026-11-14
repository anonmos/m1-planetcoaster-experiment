#!/bin/zsh
# Reinstall the steamwebhelper flag shim after a Steam client update.
#
# What/why: steam.exe does NOT forward most -cef-* flags to steamwebhelper.exe,
# and stock multi-process CEF paints black under Wine (cross-process present is
# lost). The working setup (Aug 2026, client 1785799196) ran the helper with
# "--disable-gpu --single-process" first on its command line. The Nov-12 update
# to 1794424036 replaced that shim with a stock binary and the black window
# returned. This script rebuilds tools/steamwebhelper-shim.c with mingw and
# installs it AS steamwebhelper.exe, moving Valve's binary to
# steamwebhelper_real.exe. Re-run after every Steam client self-update
# (bootstrap replaces steamwebhelper.exe; symptom is the black window again).
set -euo pipefail
ROOT="${CHECKPOINT_ROOT:-${0:A:h:h}}"
P="${WINEPREFIX:-/Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D}"
CEF="$P/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
HELPER="$CEF/steamwebhelper.exe"
REAL="$CEF/steamwebhelper_real.exe"
SHIM_SRC="$ROOT/tools/steamwebhelper-shim.c"
SHIM_BIN="$ROOT/build/steamwebhelper-shim.exe"

if [[ ! -f "$HELPER" ]]; then
  print -u2 "steamwebhelper.exe not found at $HELPER"
  exit 1
fi

# Never touch a running Steam: file swaps under a live client corrupt it.
# NOTE: use pgrep with a bracket pattern — a naive `ps | grep steamwebhelper`
# matches the grep process itself (its argv contains the pattern text) and
# refuses even with nothing running (seen 2026-11-14 after a reboot).
if pgrep -qf '[s]team\.exe|[s]teamwebhelper'; then
  print -u2 'Steam processes are running. Run this first:'
  print -u2 '  zsh scripts/control-steam.zsh stop all'
  exit 1
fi

print 'Building shim...'
mkdir -p "$ROOT/build"
# --no-insert-timestamp keeps the build deterministic (the PE timestamp would
# otherwise differ every build and defeat the already-installed check below).
x86_64-w64-mingw32-gcc -mwindows -O2 -Wl,--no-insert-timestamp -o "$SHIM_BIN" "$SHIM_SRC"

# Preserve Valve's binary. The installed shim is zero-padded to the genuine
# size, so compare the installed first-N bytes against the fresh build
# (plain `cmp` of padded vs unpadded always "differs" at the padding).
SHIM_SZ="$(stat -f%z "$SHIM_BIN")"
if head -c "$SHIM_SZ" "$HELPER" 2>/dev/null | cmp -s - "$SHIM_BIN"; then
  print 'Shim already installed; genuine binary untouched.'
else
  TS="$(date +%Y%m%d-%H%M%S)"
  cp -p "$HELPER" "$CEF/steamwebhelper.stock-$TS.exe"
  mv -f "$HELPER" "$REAL"
  print "Saved current Valve binary (and replaced any stale _real)."
  cp -f "$SHIM_BIN" "$HELPER"
  # Size-match the genuine binary: Steam's bootstrap has been observed to
  # restore a replaced helper (exit 42); keep the shim byte-identical in size.
  SZ="$(stat -f%z "$REAL")"
  truncate -s "$SZ" "$HELPER"
  print "Installed shim ($SZ bytes, size-matched to genuine binary)."
fi
print 'Next (local Terminal): zsh scripts/control-steam.zsh start steam'
