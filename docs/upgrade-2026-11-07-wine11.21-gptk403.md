# Upgrade 2026-11-07 — Wine 11.21 / GPTK 4.0 beta 3

Base: watermark-2026-11-07 (24dd1c2, WineForge 0.6.0.3 / Wine 11.16 / D3DMetal 3.0)

## Changes

- Homebrew: freetype 2.14.3->2.15.0, brotli 1.2.0->1.2.1, libpng 1.6.58->1.6.59 (plus 13 dependents)
- GPTK: D3DMetal 3.0/32047000000000 Build 1 -> 4.0b3/33040000000000 Build 2, wine DLLs d3d10/d3d11/d3d12/d3d12core/dxgi/nvapi64/nvngx updated from Evaluation environment for Windows games 4.0 beta 3.dmg (SHA 9550b8e5...). System libs (freetype/gnutls/etc.) kept from beta 2 (beta 3 eval ships D3DMetal-only).
- WineForge: gptk4-tahoe-checkpoint (59dda45, 0.6.0.3) -> gptk4-beta3-wine11.21 (9a445e9 origin/main 0.6.0.8 + a830478d Tahoe compat + 27254917 SessionGetInfo gate removal + f4319ad0 SCK capture). Loopback audio chain (bdd6081 + 6 follow-ups) conflicts on 11.21 coreaudio.c — parked, see watermark for SHAs.
- scripts/build-wineforge-full.zsh: added d3d12core to D3DMetal sync loop (beta 3 new Agility DLL, was missing from runtime).
- Rebuilt via scripts/build-wineforge-full.zsh + SONAME re-repair (configure overwrote config.h on 11.21; re-applied libgnutls.30.dylib / libfreetype.6.dylib + rebuilt secur32/dwrite/win32u + install).

## Tests (headless, 2026-11-07)

- ./build/wineforge-runtime/bin/wine --version => wine-11.21 (WineForge 0.6.0.8)
- zsh tools/run-tls-probe-wineforge.zsh => TLS probe succeeded; HTTPS status: 200
- D3DMetal runtime => 4.0b3, external/wine x86_64-unix *.so all resolve (file = Mach-O x86_64, not broken), d3d12core.dll/.so present
- R/lib closure unchanged (GPTK beta-2 x86_64 libs): brotli 1.1.0, bz2 1.0.8, expat 1.10.2, fontconfig, freetype.6, intl.8, png16.16, zlib 1.3.1

## Requires user Terminal (no WindowServer over ssh)

- zsh scripts/control-steam.zsh start steam (must be normal Terminal)
- zsh scripts/control-steam.zsh start game pc2 (2688950) / 33 (1903340) / er (1245620 offline)
- Steam text rendering = freetype path; Elden Ring D3D12 = D3DMetal redirect tree

## Known gaps

- Remote Play loopback audio (winecoreaudio-sck-loopback.patch + winemac-sck-capture follow-ups) not ported to 11.21 yet
- toolchain/MANIFEST.md still claims WineForge 40a8a7b — stale, actual base 9a445e9
- GnuTLS stays 3.8.13 (latest)
