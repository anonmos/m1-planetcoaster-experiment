// setupdi_probe.c — list HID device interfaces Wine knows about.
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <setupapi.h>
#include <hidsdi.h>

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    GUID guid;
    HidD_GetHidGuid(&guid);
    HDEVINFO set = SetupDiGetClassDevsW(&guid, NULL, NULL,
        DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    printf("SETUPDI: set=%p err=%lu\n", (void *)set, (unsigned long)GetLastError());
    if (set == INVALID_HANDLE_VALUE) return 1;
    for (int i = 0; i < 16; i++) {
        SP_DEVICE_INTERFACE_DATA ifd = { sizeof(ifd) };
        if (!SetupDiEnumDeviceInterfaces(set, NULL, &guid, i, &ifd)) {
            printf("SETUPDI: enum end at %d err=%lu\n", i, (unsigned long)GetLastError());
            break;
        }
        DWORD need = 0;
        SetupDiGetDeviceInterfaceDetailW(set, &ifd, NULL, 0, &need, NULL);
        printf("SETUPDI: [%d] detail-bytes=%lu\n", i, (unsigned long)need);
        if (need > 0 && need < 1024) {
            char *buf = HeapAlloc(GetProcessHeap(), 0, need);
            SP_DEVICE_INTERFACE_DETAIL_DATA_W *det = (void *)buf;
            det->cbSize = sizeof(*det);
            if (SetupDiGetDeviceInterfaceDetailW(set, &ifd, det, need, NULL, NULL))
                wprintf(L"SETUPDI: [%d] path=%ls\n", i, det->DevicePath);
            HeapFree(GetProcessHeap(), 0, buf);
        }
    }
    SetupDiDestroyDeviceInfoList(set);
    return 0;
}
