#!/bin/zsh
# Back up the Whisky bottle WITHOUT game payloads.
#
# Captures everything irreplaceable (registry, windows/, users/saves+configs,
# Steam client + manifests, Whisky metadata) while excluding re-downloadable
# game content. A full bottle is ~130G; the backup is typically 3-5G.
#
# Usage: zsh scripts/backup-bottle.zsh [dest_dir]
#   Produces: <dest_dir>/whisky-bottle-<UUID>-<date>.tar.zst
# Restore with: zsh scripts/restore-bottle.zsh <backup-file>

set -e

UUID="${BOTTLE_UUID:-66589F31-3F31-4D59-AC97-90EE21022A1D}"
BOTTLE="${WINEPREFIX:-/Users/tim/Library/Containers/com.franke.Whisky/Bottles/$UUID}"
DEST="${1:-$HOME/Backups/gptk-steam-emulation}"
STAMP="$(date +%Y%m%d-%H%M)"
OUT="$DEST/whisky-bottle-$UUID-$STAMP.tar.zst"

[[ -d "$BOTTLE" ]] || { print -u2 "Bottle not found: $BOTTLE"; exit 1 }
command -v zstd >/dev/null || { print -u2 "zstd missing (brew install zstd)"; exit 1 }
mkdir -p "$DEST"

# Stop the stack first so registry/logs are stable on disk.
zsh "${0:A:h}/control-steam.zsh" stop all >/dev/null 2>&1 || true

print "Backing up $BOTTLE -> $OUT"
print "(excluding steamapps/common, downloading, shadercache, dumps)"
tar -c \
  --exclude='./drive_c/Program Files (x86)/Steam/steamapps/common' \
  --exclude='./drive_c/Program Files (x86)/Steam/steamapps/downloading' \
  --exclude='./drive_c/Program Files (x86)/Steam/steamapps/shadercache' \
  --exclude='./drive_c/Program Files (x86)/Steam/dumps' \
  -f - -C "$BOTTLE" . | zstd -T0 -19 -o "$OUT"

ls -lh "$OUT"
print "Done. To restore: zsh scripts/restore-bottle.zsh $OUT"
print "Then reinstall game payloads via Steam (manifests are preserved, so"
print "Steam will discover+verify rather than starting fully from scratch)."
