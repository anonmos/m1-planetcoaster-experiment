// dinput_state.c — open first gamepad, poll state 15s. Headless-safe.
#define WIN32_LEAN_AND_MEAN
#define DIRECTINPUT_VERSION 0x0800
#include <stdio.h>
#include <windows.h>
#include <dinput.h>

static IDirectInputDevice8W *dev = NULL;

static BOOL CALLBACK cb(const DIDEVICEINSTANCEW *pd, void *pv) {
    (void)pv;
    if (GET_DIDEVICE_TYPE(pd->dwDevType) != DI8DEVTYPE_GAMEPAD &&
        GET_DIDEVICE_TYPE(pd->dwDevType) != DI8DEVTYPE_JOYSTICK)
        return DIENUM_CONTINUE;
    IDirectInput8W *di = pv;
    if (FAILED(IDirectInput8_CreateDevice(di, &pd->guidInstance, &dev, NULL)))
        return DIENUM_CONTINUE;
    return DIENUM_STOP;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    IDirectInput8W *di = NULL;
    if (FAILED(DirectInput8Create(GetModuleHandleW(NULL), DIRECTINPUT_VERSION,
        &IID_IDirectInput8W, (void **)&di, NULL))) return 1;
    IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, cb, di, DIEDFL_ATTACHEDONLY);
    if (!dev) { printf("DISTATE: no gamepad\n"); return 2; }
    printf("DISTATE: opened pad, set format+acquire\n");
    if (FAILED(IDirectInputDevice8_SetDataFormat(dev, &c_dfDIJoystick2))) return 1;
    IDirectInputDevice8_Acquire(dev);
    printf("DISTATE: move sticks + press bumpers for 15s\n");
    for (int t = 0; t < 150; t++) {
        DIJOYSTATE2 js;
        HRESULT hr = IDirectInputDevice8_Poll(dev);
        hr = IDirectInputDevice8_GetDeviceState(dev, sizeof(js), &js);
        if (SUCCEEDED(hr)) {
            printf("DISTATE: LX=%ld LY=%ld RX=%ld RY=%ld Z=%ld B=%02x%02x%02x%02x POV=%lu\n",
                (long)js.lX, (long)js.lY, (long)js.lRx, (long)js.lRy, (long)js.lZ,
                (unsigned)js.rgbButtons[0], (unsigned)js.rgbButtons[1],
                (unsigned)js.rgbButtons[2], (unsigned)js.rgbButtons[3],
                (unsigned long)js.rgdwPOV[0]);
        }
        Sleep(100);
    }
    printf("DISTATE: done\n");
    return 0;
}
