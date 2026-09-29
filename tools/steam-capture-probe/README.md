# Steam Remote Play capture probe

This Win32 program runs under the WineForge prefix. It displays a known four-quadrant GDI pattern, then tests BitBlt captures from the pattern window DC, the desktop-window DC, and the global screen DC. The screen DC is tested with both SRCCOPY and SRCCOPY | CAPTUREBLT. Every capture is written as a top-down BMP, and manifest.csv records the BitBlt result, last-error value, RGB hash, nonblack-pixel percentage, and sampled quadrant colors.

The runner also feeds the successful pattern-window BMP sequence through the host's FFmpeg/libx264 H.264 encoder and decodes it back to PNG. This is a standard H.264 round-trip cross-check. It uses macOS FFmpeg, not Steam's Windows codec DLLs, and does not test Steam's Remote Play transport or client renderer.

Run on the Mac host with scripts/run-steam-capture-probe.zsh. Optional environment variables: CAPTURE_FRAMES (default 8), CAPTURE_FPS (default 2), and CAPTURE_OUTPUT_DIR (defaults to a timestamped folder under /private/tmp).

The executable and output stay under /private/tmp. The test does not stop Steam, alter the Wine prefix, or install DLLs.
