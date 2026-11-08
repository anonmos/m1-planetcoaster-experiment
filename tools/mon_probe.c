#define COBJMACROS
#include <stdio.h>
#include <windows.h>

static int g_n = 0;
static BOOL CALLBACK moncb(HMONITOR h, HDC dc, LPRECT r, LPARAM p) {
    MONITORINFOEXA mi;
    mi.cbSize = sizeof(mi);
    printf("PROBE: monitor %d h=%p rect=(%ld,%ld)-(%ld,%ld) ", g_n, (void *)h,
           (long)r->left, (long)r->top, (long)r->right, (long)r->bottom);
    if (GetMonitorInfoA(h, (LPMONITORINFO)&mi))
        printf("name=%s flags=0x%lx", mi.szDevice, (unsigned long)mi.dwFlags);
    else
        printf("GetMonitorInfo FAILED err=%lu", (unsigned long)GetLastError());
    printf("\n");
    g_n++;
    return TRUE;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("PROBE: calling EnumDisplayMonitors\n");
    BOOL r = EnumDisplayMonitors(NULL, NULL, moncb, 0);
    printf("PROBE: EnumDisplayMonitors returned %d err=%lu count=%d\n", (int)r, (unsigned long)GetLastError(), g_n);
    printf("PROBE: calling EnumDisplayDevicesA\n");
    for (int i = 0; i < 6; i++) {
        DISPLAY_DEVICEA dd;
        dd.cb = sizeof(dd);
        BOOL ok = EnumDisplayDevicesA(NULL, i, &dd, 0);
        printf("PROBE: adapter %d ok=%d name=%.32s str=%.128s state=0x%lx\n",
               i, (int)ok, dd.DeviceName, dd.DeviceString, (unsigned long)dd.StateFlags);
        if (!ok) break;
    }
    printf("PROBE: done\n");
    return 0;
}
