#!/bin/zsh
set -e
ROOT="${0:A:h:h}"
SRC="$ROOT/WineForge"
BUILD="$ROOT/build/wineforge-tls-build"
RUNTIME="$ROOT/build/wineforge-runtime"
GPTK="${GPTK_WINE:-$ROOT/toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine}"
GNUTLS_HEADERS="$ROOT/toolchain/gnutls-headers/debian-dev/usr/include"
mkdir -p "$ROOT/build"
if [[ ! -f "$BUILD/Makefile" ]]; then
  cd "$SRC"
  CC='clang -target x86_64-apple-macos15' CXX='clang++ -target x86_64-apple-macos15' \
  CFLAGS="-target x86_64-apple-macos15 -I/opt/homebrew/include/freetype2 -I/opt/homebrew/include -I$GNUTLS_HEADERS" \
  CXXFLAGS="-target x86_64-apple-macos15 -I/opt/homebrew/include/freetype2 -I/opt/homebrew/include -I$GNUTLS_HEADERS" \
  LDFLAGS="-L$GPTK/lib -Wl,-rpath,$GPTK/lib -Wl,-rpath,$RUNTIME/lib" \
  GNUTLS_CFLAGS="-I$GNUTLS_HEADERS" GNUTLS_LIBS="-L$GPTK/lib -lgnutls -L$GPTK/lib -lnettle -L$GPTK/lib -lhogweed" \
  "$SRC/configure" --build=x86_64-apple-darwin --enable-archs=i386,x86_64 --prefix="$RUNTIME" \
    --disable-tests --disable-winedbg --without-alsa --with-coreaudio --without-cups --without-dbus \
    --without-ffmpeg --with-fontconfig --without-gettext --without-gssapi --with-gnutls \
    --without-gstreamer --without-inotify --without-krb5 --with-mingw --without-opengl \
    --without-oss --without-pulse --without-sdl --without-udev --without-usb --without-vulkan \
    --without-wayland --without-x --with-freetype
fi
sed -i.bak 's@^#define SONAME_LIBGNUTLS .*@#define SONAME_LIBGNUTLS "libgnutls.30.dylib"@' "$BUILD/include/config.h"
# 2026-09-20: same otool-capture failure hits freetype when GPTK paths are in
# LDFLAGS (configure records a whole otool line as the SONAME), which breaks
# dwrite text rendering. Repair it the same way.
sed -i.bak 's@^#define SONAME_LIBFREETYPE .*@#define SONAME_LIBFREETYPE "libfreetype.6.dylib"@' "$BUILD/include/config.h"
make -C "$BUILD" -j"$(sysctl -n hw.ncpu)" dlls/secur32/secur32.so
mkdir -p "$RUNTIME/lib/wine/x86_64-unix"
install -m 755 "$BUILD/dlls/secur32/secur32.so" "$RUNTIME/lib/wine/x86_64-unix/secur32.so"
print "Built WineForge TLS runtime: $RUNTIME"
