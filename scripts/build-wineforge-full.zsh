#!/bin/zsh
# Full WineForge runtime rebuild.
#
# Rebuilds build/wineforge-runtime from the WineForge source tree. Unlike
# scripts/build-wineforge-tls.zsh (TLS repair of an existing build dir only),
# this script performs the complete configure + make + install + external
# runtime sync. It encodes every workaround discovered during the Sep 2026
# macOS 27 rebuild:
#
#  1. Rosetta 2 is mandatory: configure test programs and several build tools
#     are x86_64 binaries. Install with:
#       softwareupdate --install-rosetta --agree-to-license
#     and verify with: arch -x86_64 true && echo ROSETTA_OK
#  2. Xcode license must be accepted: sudo xcodebuild -license
#  3. Apple's /usr/bin/bison is 2.3 (too old); Homebrew bison 3.8 lives at
#     /opt/homebrew/opt/bison/bin and must come first on PATH.
#  4. Out-of-source build: run $SRC/configure from inside $BUILD, not $SRC.
#  5. $GPTK contains spaces ("Game Porting Toolkit.app"), which breaks
#     LDFLAGS word-splitting in configure. Use the build/gptk-wine symlink.
#  6. /opt/homebrew fontconfig is arm64-only and cannot link x86_64. Use the
#     x86_64 libfontconfig/libexpat from GPTK's GStreamer bundle, with
#     Homebrew's headers (headers are arch-independent).
#  7. configure mis-records SONAME_LIBGNUTLS and SONAME_LIBFREETYPE as whole
#     otool output lines; both are repaired to bare dylib names (same repair
#     SUMMARY.md documents for GnuTLS).
#  8. tools/sfnt2fon/sfnt2fon links a bare libfreetype.dylib and runs with
#     $BUILD as CWD, ignoring DYLD_LIBRARY_PATH under Rosetta; symlink the
#     x86_64 freetype into $BUILD.
#  9. The runtime R/lib needs the full freetype/fontconfig dependency closure
#     (@loader_path deps do not consult DYLD_*): libz, libbz2, libpng16,
#     libbrotli x2, exact-name libexpat, libintl.
#
# Usage: zsh scripts/build-wineforge-full.zsh
# Then verify: zsh tools/run-tls-probe-wineforge.zsh  (require HTTPS status: 200)

set -e

ROOT="${0:A:h:h}"
SRC="$ROOT/WineForge"
BUILD="$ROOT/build/wineforge-tls-build"
RUNTIME="$ROOT/build/wineforge-runtime"
GPTK_SRC="$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine"
GNUTLS_HEADERS="$ROOT/toolchain/gnutls-headers/debian-dev/usr/include"
GST="$GPTK_SRC/lib/GStreamer.framework/Versions/1.0"

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ---- preflight -----------------------------------------------------------
[[ -d "$GPTK_SRC/lib" ]] || { print -u2 "Missing GPTK extract: $GPTK_SRC"; exit 1 }
[[ -d "$GNUTLS_HEADERS" ]] || { print -u2 "Missing GnuTLS headers: $GNUTLS_HEADERS"; exit 1 }
clang --version >/dev/null 2>&1 || { print -u2 "clang broken: run sudo xcodebuild -license"; exit 1 }
arch -x86_64 true 2>/dev/null || { print -u2 "Rosetta missing: run softwareupdate --install-rosetta --agree-to-license"; exit 1 }
[[ "$(bison --version | head -1)" == *"3."* ]] || { print -u2 "bison too old on PATH: $(which bison)"; exit 1 }
command -v x86_64-w64-mingw32-gcc >/dev/null || { print -u2 "missing mingw (brew llvm-mingwbrid?)"; exit 1 }
[[ -f "$GST/lib/libfontconfig.1.dylib" ]] || { print -u2 "missing x86_64 fontconfig in GPTK GStreamer bundle"; exit 1 }

mkdir -p "$ROOT/build" "$BUILD"

# Space-free aliases (see note 5).
ln -sfn "$GPTK_SRC" "$ROOT/build/gptk-wine"
ln -sfn "$GST/lib" "$ROOT/build/gst-lib"
GPTK="$ROOT/build/gptk-wine"
GSTLINK="$ROOT/build/gst-lib"

# sfnt2fon looks for bare libfreetype.dylib in $BUILD (see note 8).
ln -sfn "$GPTK/lib/libfreetype.6.dylib" "$BUILD/libfreetype.6.dylib"
ln -sfn "$GPTK/lib/libfreetype.6.dylib" "$BUILD/libfreetype.dylib"

export DYLD_LIBRARY_PATH="$GPTK/lib:$GSTLINK:$RUNTIME/lib:$BUILD"
export DYLD_FALLBACK_LIBRARY_PATH="$GPTK/lib:$GSTLINK:$RUNTIME/lib:$BUILD"

# ---- configure (out-of-source, under Rosetta) -----------------------------
if [[ ! -f "$BUILD/Makefile" ]]; then
  cd "$BUILD"
  arch -x86_64 env \
    PATH="$PATH" \
    CC='clang -target x86_64-apple-macos15' CXX='clang++ -target x86_64-apple-macos15' \
    CFLAGS="-target x86_64-apple-macos15 -I/opt/homebrew/include/freetype2 -I/opt/homebrew/include -I$GNUTLS_HEADERS" \
    CXXFLAGS="-target x86_64-apple-macos15 -I/opt/homebrew/include/freetype2 -I/opt/homebrew/include -I$GNUTLS_HEADERS" \
    LDFLAGS="-L$GPTK/lib -L$GSTLINK -Wl,-rpath,$GPTK/lib -Wl,-rpath,$RUNTIME/lib" \
    GNUTLS_CFLAGS="-I$GNUTLS_HEADERS" GNUTLS_LIBS="-L$GPTK/lib -lgnutls -L$GPTK/lib -lnettle -L$GPTK/lib -lhogweed" \
    FONTCONFIG_CFLAGS="-I/opt/homebrew/Cellar/fontconfig/2.18.3/include -I/opt/homebrew/opt/freetype/include/freetype2" \
    FONTCONFIG_LIBS="-L$GSTLINK -lfontconfig" \
    FREETYPE_CFLAGS="-I$GPTK/include/freetype2" FREETYPE_LIBS="-L$GPTK/lib -lfreetype" \
    "$SRC/configure" --build=x86_64-apple-darwin --enable-archs=i386,x86_64 --prefix="$RUNTIME" \
      --disable-tests --disable-winedbg --without-alsa --with-coreaudio --without-cups --without-dbus \
      --without-ffmpeg --with-fontconfig --without-gettext --without-gssapi --with-gnutls \
      --without-gstreamer --without-inotify --without-krb5 --with-mingw --without-opengl \
      --without-oss --without-pulse --without-sdl --without-udev --without-usb --without-vulkan \
      --without-wayland --without-x --with-freetype
fi

# ---- SONAME repairs (see note 7) ------------------------------------------
sed -i.bak 's@^#define SONAME_LIBGNUTLS .*@#define SONAME_LIBGNUTLS "libgnutls.30.dylib"@' "$BUILD/include/config.h"
sed -i.bak 's@^#define SONAME_LIBFREETYPE .*@#define SONAME_LIBFREETYPE "libfreetype.6.dylib"@' "$BUILD/include/config.h"
grep -E "SONAME_LIB(GNUTLS|FREETYPE)" "$BUILD/include/config.h"

# ---- build -----------------------------------------------------------------
arch -x86_64 env PATH="$PATH" DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH" \
  DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
  make -C "$BUILD" -j10

# ---- install (retry once: parallel ranlib races can leave truncated .a) ---
if ! arch -x86_64 env PATH="$PATH" DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH" \
  DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
  make -C "$BUILD" -j10 install; then
  print "Install hit a parallel-build artifact; cleaning .delay.a and retrying with -j4..."
  find "$BUILD/dlls" -name '*.delay.a' -delete
  find "$BUILD/dlls" -name '*_syms-*.o' -delete
  arch -x86_64 env PATH="$PATH" DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH" \
    DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
    make -C "$BUILD" -j4 install
fi

# ---- external runtime sync (D3DMetal + freetype/fontconfig closure) --------
mkdir -p "$RUNTIME/lib/external" "$RUNTIME/lib/wine/x86_64-unix"
cp -R "$GPTK/lib/external/D3DMetal.framework" "$RUNTIME/lib/external/"
cp -f "$GPTK/lib/external/libd3dshared.dylib" "$RUNTIME/lib/external/"
cp -a "$GPTK/lib/libfreetype.6.dylib" "$RUNTIME/lib/"
cp -a "$GST/lib/libfontconfig.1.dylib" "$RUNTIME/lib/"
cp -a "$GST/lib/libexpat.1.dylib" "$GST/lib/libexpat.1.10.2.dylib" "$RUNTIME/lib/"
if [[ -f "$GPTK/lib/libintl.8.dylib" ]]; then
  cp -a "$GPTK/lib/libintl.8.dylib" "$RUNTIME/lib/"
else
  cp -a "$GST/lib/libintl.8.dylib" "$RUNTIME/lib/"
fi
for dep in libz.1.dylib libz.1.3.1.dylib libbz2.1.0.dylib libbz2.1.0.8.dylib \
  libpng16.16.dylib libpng16.dylib libbrotlidec.1.dylib libbrotlidec.1.1.0.dylib \
  libbrotlicommon.1.dylib libbrotlicommon.1.1.0.dylib; do
  cp -a "$GPTK/lib/$dep" "$RUNTIME/lib/"
done

# ---- checkpoint secur32 repair ---------------------------------------------
arch -x86_64 env PATH="$PATH" make -C "$BUILD" -j10 dlls/secur32/secur32.so
install -m 755 "$BUILD/dlls/secur32/secur32.so" "$RUNTIME/lib/wine/x86_64-unix/secur32.so"

file "$RUNTIME/bin/wine" "$RUNTIME/bin/wineserver" | sed 's/^/built: /'
file "$RUNTIME/lib/libfontconfig.1.dylib" "$RUNTIME/lib/libfreetype.6.dylib" | sed 's/^/lib: /'
print "Full WineForge runtime ready: $RUNTIME"
print "Verify with: zsh tools/run-tls-probe-wineforge.zsh  (require HTTPS status: 200)"
