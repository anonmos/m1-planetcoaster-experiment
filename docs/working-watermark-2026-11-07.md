# Working watermark — 2026-11-07 (pre-upgrade)

Host: Tims-MacBook-Pro.local (SSH profile local-heavy)
Project: ~/Workspace/gptk-steam-emulation (parent remote git@github.com:anonmos/m1-planetcoaster-experiment.git, branch main)
Purpose: frozen record of the working Steam/Wine stack before upgrading WineForge / Homebrew libs. Re-verify with tools/run-tls-probe-wineforge.zsh (require HTTPS status: 200) and scripts/control-steam.zsh start steam.

## Host toolchain

- macOS 27.2 Build 26B123 (sw_vers ProductVersion 27.2)
- Xcode 27.2 Build 27B52
- Rosetta: arch -x86_64 true => ROSETTA_OK
- bison: GNU Bison 3.8.2 at /opt/homebrew/opt/bison/bin (Apple /usr/bin/bison is 2.3, too old)
- mingw: mingw-w64 14.0.0_3 (/opt/homebrew/bin/x86_64-w64-mingw32-gcc)
- Homebrew 7.0.12 (was 6.0.20 before auto-update on 2026-11-07)
- clang: requires sudo xcodebuild -license (preflight in scripts/build-wineforge-full.zsh)

## Homebrew packages (before brew upgrade)

- bison 3.8.2 (keg-only, current)
- fontconfig 2.18.3 (current stable)
- freetype 2.14.3 -> 2.15.0 available (brew outdated)
- brotli 1.2.0 -> 1.2.1 available
- libpng 1.6.58 -> 1.6.59 available
- gettext 1.0

Reproduce: export PATH=/opt/homebrew/bin:/Users/timgrowney/.opencode/v2/bin:/Users/timgrowney/.nvm/versions/node/v26.8.2/bin:/Users/timgrowney/.opencode/bin:/Users/timgrowney/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/Users/timgrowney/.rbenv/bin:/Users/timgrowney/.nvm/versions/node/v18.14.0/bin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/pkg/env/global/bin:/Library/Apple/usr/bin:/usr/local/bin/code:/Users/tim/.flutter/bin:/Applications/Docker.app/Contents/Resources/bin; brew --version; brew list --versions bison fontconfig freetype brotli libpng gettext; brew outdated

## GPTK 4 toolchain

- Installer: Game_Porting_Toolkit_4.0_beta_2.dmg (100M, 2025-08-28)
- SHA-256: 03893ac4fab94ad9ff6aa32e887e2854bbf40fd90796f78a1d9bdbc02526ee5b
- Also present: Evaluation environment for Windows games 4.0 beta 2.dmg (25M, 2025-07-28)
- Extract: toolchain/gptk-extract/Game Porting Toolkit.app/Contents/Resources/wine (bin/wine64, lib/, share/)
- App Info.plist CFBundleShortVersionString 3.0-3 (stale vs installer name, do not use as version)
- D3DMetal.framework version.plist: CFBundleShortVersionString 3.0, SourceVersion 32047000000000, BuildVersion 1
- Bundled libs (x86_64): libbrotlicommon/dec/enc 1.1.0, libbz2 1.0.8, libfreetype.6, libgnutls.30, libpng (dylib), libfontconfig via GStreamer.framework, libexpat, libintl.8

Reproduce: shasum -a 256 ~/Downloads/Game_Porting_Toolkit_4.0_beta_2.dmg; ls toolchain/gptk-extract/Game\ Porting\ Toolkit.app/Contents/Resources/wine/lib | grep -E 'brotli|freetype|gnutls|png|fontconfig|expat'

## GnuTLS

- Version 3.8.13 (latest stable as of 2026-04-29, no upgrade available)
- Archive: toolchain/gnutls-headers/gnutls-3.8.13.tar.xz
- SHA-256: ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e
- Headers used at: toolchain/gnutls-headers/debian-dev/usr/include

Reproduce: shasum -a 256 toolchain/gnutls-headers/gnutls-3.8.13.tar.xz; grep GNUTLS_VERSION toolchain/gnutls-headers/debian-dev/usr/include/gnutls/gnutls.h | head

## WineForge source

- Remote origin https://github.com/Alien4042x/WineForge.git, fork git@github.com:anonmos/WineForge.git
- Local branch: gptk4-tahoe-checkpoint, HEAD c4d0f94824d42688e6e742ce955cfe21edc7840c (winecoreaudio: drop cushion top-up)
- Base in HEAD: 59dda45dba2229cce9eb83e6e4e55b408ec37e5e (Wine 11.16, tag 0.6.0.3, 2026-08-22)
- git describe: 0.6.0.3-11-gc4d0f948
- Local-only stack on top of 59dda45: 40a8a7b GPTK4 Tahoe compat, bb6da7b drop SessionGetInfo gate (macOS 27 fix), 27b59d9 SCK capture, bdd6081 loopback + 7x timer/pacing commits (see git log --all --graph)
- origin/main at doc time: 9a445e947d0d7cad140f31c77cb94fb2057a4882 (0.6.0.8, Wine 11.21, 2026-10-31) — NOT yet merged locally
- Tags fetched 2026-11-07: 0.6.0.0 through 0.6.0.8
- NOTE: toolchain/MANIFEST.md claims commit 40a8a7b — stale, actual base is 59dda45 (see SUMMARY.md)

Reproduce: git -C WineForge rev-parse HEAD; git -C WineForge log --oneline -12; git -C WineForge rev-parse origin/main; git -C WineForge tag --sort=-creatordate | head

## Parent repo

- HEAD 399c9ac241d169ddcc980d0d23cbebc83819bd81 (Probe: 10s WAV dump mode)
- Branch main, remote origin git@github.com:anonmos/m1-planetcoaster-experiment.git
- Dirty at doc time: ?? scripts/control-steam.zsh.bak-20260928-cef-flags, ?? tools/sleep_probe.c
- Patches SHAs: winecoreaudio-sck-loopback 1a9dab84..., wineforge-local-source 0fdc9a7a..., winemac-sck-capture 4be470af... (shasum -a 256 patches/*)

## Built runtime

- Path: build/wineforge-runtime, built via scripts/build-wineforge-full.zsh (Sep 2026, macOS 27 rebuild)
- wine --version: wine-11.16 (WineForge 0.6.0.3)
- R/lib SHAs (shasum -a 256 build/wineforge-runtime/lib/*.dylib):
  - libbrotlicommon.1.1.0 996f893ffd37...
  - libbrotlidec.1.1.0 0ed8b9b60311...
  - libbz2.1.0.8 759af61a3bc6...
  - libexpat.1.10.2 0ac136949a04...
  - libfontconfig.1 7c76768c5430...
  - libfreetype.6 1fca8221d23c...
  - libintl.8 440aa1e11f76...
  - libpng16.16 4ebcf2e317c3...
  - libz.1.3.1 457b5e33cd60...
- otool example: libfreetype.6 compat 27.0.0 current 27.2.0, deps @loader_path/libz.1, libbz2.1.0, libpng16.16, libbrotlidec.1
- external/: D3DMetal.framework + libd3dshared.dylib + wine/{x86_64-windows,x86_64-unix,i386-windows}/{dxgi,d3d10,d3d10core,d3d11,d3d12,nvapi64,nvngx*} with x86_64-unix/*.so as ../../libd3dshared.dylib symlinks (must not dangle)

Reproduce: ./build/wineforge-runtime/bin/wine --version; shasum -a 256 build/wineforge-runtime/lib/*.dylib; otool -L build/wineforge-runtime/lib/libfreetype.6.dylib; ls -R build/wineforge-runtime/lib/external | head -n 40

## Bottle

- Whisky bottle UUID 66589F31-3F31-4D59-AC97-90EE21022A1D at /Users/tim/Library/Containers/com.franke.Whisky/Bottles/66589F31-3F31-4D59-AC97-90EE21022A1D (246G, win64, Windows build 22000)
- Steam + VC++2022 + Wine Mono, games: Planet Coaster 2 AppID 2688950, Clair Obscur 1903340, Elden Ring 1245620 (offline EAC bypass, steam_appid.txt + BORDERLESS GraphicsConfig.xml prefix-local)
- Backup: scripts/backup-bottle.zsh / restore-bottle.zsh (excludes steamapps/common)

## Verification (must pass before/after upgrade)

- zsh tools/run-tls-probe-wineforge.zsh => HTTPS status: 200
- zsh scripts/control-steam.zsh start steam (from normal Terminal, not agent ssh — needs WindowServer)
- Steam shows windows + rendered text, login as current user

## Known upgrades pending (do NOT apply yet)

- WineForge 0.6.0.4 (Wine 11.17) through 0.6.0.8 (Wine 11.21) — needs port of local SCK/loopback + Tahoe gate patches
- Homebrew freetype 2.15.0, brotli 1.2.1, libpng 1.6.59 — needs R/lib re-sync + full rebuild
