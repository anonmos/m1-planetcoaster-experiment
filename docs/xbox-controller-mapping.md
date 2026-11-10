# Xbox Bluetooth Controller Mapping (045E:0B13) — Diagnosis and Fix

Pad: Xbox Wireless Controller over BLE, VID 045E PID 0B13, firmware 5.23.6.0,
serial 09710677724345. Symptom baseline (visual tester `tools/xpad_visual.exe`):
left stick vertically inverted, right stick drove LT/RT bars, LB/RB lit
Back/Start, Y lit LB, X lit Y, Back/Start lit nothing.

## 1. Ground truth: HID report descriptor (from macOS IOKit dump)

283-byte descriptor, 17-byte report 1. Input fields in order:

- X, Y — generic, 16-bit each (left stick)
- Z, Rz — generic, 16-bit each (**right stick**, not triggers)
- Brake, Accel — simulation page, 10-bit each (**LT, RT**)
- Hat switch — 4-bit (dpad)
- Buttons 1–15, 1 bit each (bits 104–118 → report bytes 15–16)
- Consumer menu bit (Guide, separate page)

## 2. Ground truth: button usage table (labeled raw captures)

`tools/hid_usages_probe.exe` opens the XI child and prints `HidP_GetUsages`
per report; `tools/hid_stream.c` (macOS side) confirmed raw bits:

A=U1, B=U2, X=U4, Y=U5, LB=U7, RB=U8, Back=U11, Start=U12,
LStick-click=U14, RStick-click=U15. (U3/U6/U9/U10/U13 unused by firmware.)

Y polarity: UP holds raw Y at 0x0000, DOWN at 0xFFFF → down-positive,
needs inversion to XInput convention. Share lights nothing (consumer-page,
out of scope).

## 3. Architecture finding (the reason several builds changed nothing)

The XInput child PDO (`...&xi_00`) passes reads **straight through to the
physical device** (`winexinput.sys` `try_complete_pending_read` forwards the
XInput IRP to the bus; `read_completion` translates only for the gamepad
child). `xinput1_3` parses raw firmware bytes with the physical descriptor
(inlen=17, 7 value caps, `Missing axis ThumbRX/RY` in logs). So:

- `winexinput.sys` quirks affect **DirectInput only**.
- All XInput behavior (visual tester, games) is decided in
  `dlls/xinput1_3/main.c`. That is where the fix lives.

## 4. Bugs fixed (WineForge branch `gptk4-beta3-wine11.21`)

- Quirk never activated twice over: matched `BTHENUM` bus prefix that
  `add_device` strips (bus id is always generic `WINEBUS`) → match
  `VID_045E&PID_0B13` directly; then `initialize_device` reset the flag to
  FALSE after `add_device` set it → preserve/re-detect, never clear.
- `xinput1_3`: Z/Rz → sThumbRX/RY, sim brake/accel → LT/RT (were LT/RT,
  leaving RX/RY missing); Y/RY negated with SHORT-overflow clamp
  (`-(-32768)` wrapped full-UP to full-DOWN — the stick "rollover").
- `xinput1_3`: button map per §2, gated on the quirk (1→A 2→B 4→X 5→Y
  7→LB 8→RB 11→Back 12→Start 14→LThumb 15→RThumb); caps presence follows
  the remap so the RX/RY warnings are gone.
- `winexinput.sys` translate got the mirror fix for the DirectInput child
  (physical usages → synthetic slots 1–10).
- `winebus.sys` Xbox BT padding fixup investigated and left as a harmless
  no-op: raw padding bits are permanently zero; firmware genuinely sends
  LB/RB as usages 7/8.

## 5. Re-verify

Rebuild (`zsh scripts/build-wineforge-full.zsh`), restart wineserver, run
`tools/xpad_visual.exe` (built from `tools/xpad_visual.c`): every button,
both sticks to full deflection, both triggers. `LIVE`/`pkt` proves reports
flow; `STALLED?` after 1.5 s means the pad slept, not a Wine bug.
`tools/hid_usages_probe.exe` re-derives §2 any time firmware changes.
