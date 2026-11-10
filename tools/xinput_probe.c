/* xinput_probe.c — poll XInput slots, report presence + state. Headless-safe. */
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <xinput.h>

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("XINPUT: probing slots 0-3 for 10s (press buttons/sticks if present)\n");
    int seen[4] = {0, 0, 0, 0};
    for (int t = 0; t < 100; t++) {
        for (int i = 0; i < 4; i++) {
            XINPUT_STATE st;
            DWORD r = XInputGetState(i, &st);
            if (r == ERROR_SUCCESS) {
                if (!seen[i]) {
                    XINPUT_CAPABILITIES cap;
                    DWORD cr = XInputGetCapabilities(i, XINPUT_FLAG_GAMEPAD, &cap);
                    printf("XINPUT: slot %d CONNECTED type=%u sub=%u caps=%lu\n",
                        i, (unsigned)st.dwPacketNumber ? 1 : 1,
                        0u, (unsigned long)cr);
                    printf("XINPUT: slot %d caps type=%u caps-flags=0x%x\n",
                        i, (unsigned)cap.Type, (unsigned)cap.Flags);
                    seen[i] = 1;
                }
                if (st.Gamepad.wButtons || (t % 10) == 0)
                    printf("XINPUT: slot %d buttons=0x%04x LX=%d LY=%d RX=%d RY=%d LT=%u RT=%u pkt=%lu\n",
                        i, (unsigned)st.Gamepad.wButtons, (int)st.Gamepad.sThumbLX,
                        (int)st.Gamepad.sThumbLY, (int)st.Gamepad.sThumbRX, (int)st.Gamepad.sThumbRY,
                        (unsigned)st.Gamepad.bLeftTrigger, (unsigned)st.Gamepad.bRightTrigger,
                        (unsigned long)st.dwPacketNumber);
            }
        }
        Sleep(100);
    }
    int n = seen[0] + seen[1] + seen[2] + seen[3];
    printf("XINPUT: done, %d slot(s) ever connected\n", n);
    return n ? 0 : 2;
}
