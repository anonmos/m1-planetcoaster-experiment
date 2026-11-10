/* dinput_probe.c — enumerate DirectInput game controllers. Headless-safe. */
#define WIN32_LEAN_AND_MEAN
#define DIRECTINPUT_VERSION 0x0800
#include <stdio.h>
#include <windows.h>
#include <dinput.h>

static int count = 0;
static BOOL CALLBACK cb(const DIDEVICEINSTANCEW *pd, void *pv) {
    (void)pv;
    wprintf(L"DINPUT: found type=0x%02lx sub=%lu name=%ls\n",
        (unsigned long)GET_DIDEVICE_TYPE(pd->dwDevType),
        (unsigned long)GET_DIDEVICE_SUBTYPE(pd->dwDevType), pd->tszInstanceName);
    count++;
    return DIENUM_CONTINUE;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    HMODULE h = LoadLibraryW(L"dinput8.dll");
    printf("DINPUT: dinput8=%p\n", (void *)h);
    IDirectInput8W *di = NULL;
    HRESULT hr = DirectInput8Create(GetModuleHandleW(NULL), DIRECTINPUT_VERSION,
        &IID_IDirectInput8W, (void **)&di, NULL);
    printf("DINPUT: create hr=0x%08lx di=%p\n", (long)hr, (void *)di);
    if (FAILED(hr) || !di) return 1;
    hr = IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, cb, NULL, DIEDFL_ATTACHEDONLY);
    printf("DINPUT: enum hr=0x%08lx count=%d\n", (long)hr, count);
    hr = IDirectInput8_EnumDevices(di, DI8DEVCLASS_ALL, cb, NULL, DIEDFL_ATTACHEDONLY);
    printf("DINPUT: enum-all hr=0x%08lx count=%d\n", (long)hr, count);
    IDirectInput8_Release(di);
    return count ? 0 : 2;
}
