#!/bin/zsh
setopt NO_HUP
ROOT=/Users/tim/Workspace/gptk-steam-emulation
R=$ROOT/build/wineforge-runtime
P=/Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D
G="$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine"
CC=/opt/homebrew/bin/x86_64-w64-mingw32-gcc
FFMPEG=/opt/homebrew/bin/ffmpeg
EXE=/private/tmp/steam-capture-probe.exe
FRAMES=8
FPS=2
OUT=/private/tmp/steam-rp-capture-probe-$(date +%Y%m%d-%H%M%S)

[[ -n "$CAPTURE_FRAMES" ]] && FRAMES=$CAPTURE_FRAMES
[[ -n "$CAPTURE_FPS" ]] && FPS=$CAPTURE_FPS
[[ -n "$CAPTURE_OUTPUT_DIR" ]] && OUT=$CAPTURE_OUTPUT_DIR
"$CC" -O2 -Wall -Wextra -o "$EXE" "$ROOT/tools/steam-capture-probe/steam_capture_probe.c" -lgdi32 -luser32 || exit 1
mkdir -p "$OUT"
print "Built $EXE"
print "The test pattern will briefly cover the host display while frames are captured."
print "Output: $OUT"

arch -x86_64 env \
  PATH="$R/bin:$PATH" \
  WINEPREFIX="$P" WINEARCH=win64 \
  WINESERVER="$R/bin/wineserver" WINELOADER="$R/bin/wine" WINEDLLPATH="$R/lib/wine" \
  DYLD_LIBRARY_PATH="$G/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
  DYLD_FALLBACK_LIBRARY_PATH="$G/lib:$R/lib/wine/x86_64-unix:$R/lib/external:$R/lib" \
  WINE_FREETYPE_PATH="$R/lib/libfreetype.6.dylib" WINE_FONTCONFIG_PATH="$R/lib/libfontconfig.1.dylib" \
  FONTCONFIG_FILE=/opt/homebrew/etc/fonts/fonts.conf FONTCONFIG_PATH=/opt/homebrew/etc/fonts \
  WINEESYNC=0 WINEMSYNC=0 WINEFSYNC=0 WINEDEBUG=+err \
  "$R/bin/wine" "$EXE" "Z:$OUT" "$FRAMES" "$FPS"

mkdir -p "$OUT/decoded"
print "Encoding the good window-DC captures as H.264, then decoding them back to PNG with host FFmpeg..."
"$FFMPEG" -hide_banner -loglevel error -y -framerate "$FPS" \
  -i "$OUT/frame_%04d_window_dc.bmp" \
  -vf "crop=iw:trunc(ih/2)*2" \
  -c:v libx264 -preset ultrafast -tune zerolatency -crf 0 -pix_fmt yuv420p \
  "$OUT/window-pattern.mp4" || exit 1
"$FFMPEG" -hide_banner -loglevel error -y -i "$OUT/window-pattern.mp4" \
  -fps_mode passthrough "$OUT/decoded/frame_%04d.png" || exit 1
print "H.264 round trip complete: $OUT/window-pattern.mp4"
print "Decoded frames: $OUT/decoded"
print "Note: this uses host FFmpeg/libx264 for the cross-check, not Steam's Windows codec DLLs."
