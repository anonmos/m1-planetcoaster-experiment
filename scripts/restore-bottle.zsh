#!/bin/zsh
# Restore a Whisky bottle from a backup-bottle.zsh archive.
#
# Usage: zsh scripts/restore-bottle.zsh <backup-file.tar.zst> [bottles-dir]
#
# Extracts to <bottles-dir>/<UUID>/ (Whisky picks the directory up on next
# launch; no import step needed). Game payloads excluded from the backup must
# be reinstalled via Steam afterwards. Set WINEPREFIX (or accept the default
# in scripts/control-steam.zsh) to point at the restored bottle if its path
# differs.

set -e

[[ $# -ge 1 ]] || { print -u2 "Usage: restore-bottle.zsh <backup-file.tar.zst> [bottles-dir]"; exit 1 }
BACKUP="$1"
BOTTLES_DIR="${2:-/Users/tim/Library/Containers/com.franke.Whisky/Bottles}"

[[ -f "$BACKUP" ]] || { print -u2 "Backup not found: $BACKUP"; exit 1 }
command -v zstd >/dev/null || { print -u2 "zstd missing (brew install zstd)"; exit 1 }

# UUID is encoded in the filename: whisky-bottle-<UUID>-<stamp>.tar.zst
BASE="${BACKUP:t}"
UUID="$(print "$BASE" | sed -E 's/^whisky-bottle-([0-9A-F-]{36})-.*/\1/')"
[[ "$UUID" != "$BASE" ]] || { print -u2 "Cannot parse bottle UUID from filename: $BASE"; exit 1 }

DEST="$BOTTLES_DIR/$UUID"
if [[ -e "$DEST" ]]; then
  print -u2 "Destination exists: $DEST"
  print -u2 "Move it aside first, or restore elsewhere and set WINEPREFIX."
  exit 1
fi

mkdir -p "$DEST"
print "Extracting $BACKUP -> $DEST"
zstd -d -c "$BACKUP" | tar -x -C "$DEST"

print "Restored. Next:"
print "  1. Launch Whisky once so it registers the bottle (or skip; the"
print "     controller scripts only need the directory + WINEPREFIX)."
print "  2. zsh scripts/control-steam.zsh start steam, log in, and install"
print "     game payloads (Steam keeps the preserved manifests)."
print "  3. Re-apply prefix-local tweaks if missing: ELDEN RING/Game/"
print "     steam_appid.txt ('1245620') and borderless GraphicsConfig.xml"
print "     (see SUMMARY.md, Elden Ring section)."
