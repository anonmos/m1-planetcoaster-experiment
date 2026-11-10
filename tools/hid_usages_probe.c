/* hid_usages_probe.c — print raw HID usages per input report on the Xbox XI child.
 * Opens the XI child device directly, parses reports with the OS preparsed
 * data, prints timestamp + button usages + hat + axis raw values on change.
 * Build: x86_64-w64-mingw32-gcc -O2 -o hid_usages_probe.exe hid_usages_probe.c
 *        -lhid -lsetupapi -static-libgcc
 * Run under wine, press pad buttons in order, Ctrl-C to stop. Logs to stdout.
 */
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <setupapi.h>
#include <devguid.h>
#include <hidsdi.h>
#include <initguid.h>
DEFINE_GUID(GUID_DEVINTERFACE_WINEXINPUT, 0x6c53d5fd, 0x6480, 0x440f, 0xb6, 0x18, 0x47, 0x67, 0x50, 0xc5, 0xe1, 0xa6);

int main(void) {
    setbuf(stdout, NULL);
    GUID guid = GUID_DEVINTERFACE_WINEXINPUT;
    HDEVINFO set = SetupDiGetClassDevsA(&guid, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE) { printf("no devinfo\n"); return 1; }
    char path[MAX_PATH * 2] = {0};
    for (DWORD i = 0; ; i++) {
        SP_DEVICE_INTERFACE_DATA dif = {.cbSize = sizeof(dif)};
        if (!SetupDiEnumDeviceInterfaces(set, NULL, &guid, i, &dif)) break;
        DWORD need = 0;
        SetupDiGetDeviceInterfaceDetailA(set, &dif, NULL, 0, &need, NULL);
        SP_DEVICE_INTERFACE_DETAIL_DATA_A *det = malloc(need);
        det->cbSize = sizeof(*det);
        if (SetupDiGetDeviceInterfaceDetailA(set, &dif, det, need, NULL, NULL)) {
            if (strstr(det->DevicePath, "045e")) {
                strcpy(path, det->DevicePath);
                free(det);
                break;
            }
        }
        free(det);
    }
    SetupDiDestroyDeviceInfoList(set);
    if (!path[0]) { printf("XI_PATH: not found\n"); return 1; }
    printf("XI_PATH: %s\n", path);
    HANDLE h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
    if (h == INVALID_HANDLE_VALUE) { printf("open failed %lu\n", GetLastError()); return 1; }
    PHIDP_PREPARSED_DATA ppd = NULL;
    if (!HidD_GetPreparsedData(h, &ppd)) { printf("preparsed failed\n"); return 1; }
    HIDP_CAPS caps;
    if (HidP_GetCaps(ppd, &caps) != HIDP_STATUS_SUCCESS) { printf("caps failed\n"); return 1; }
    printf("CAPS: inlen=%d nbtncaps=%d nvalcaps=%d\n", caps.InputReportByteLength,
           caps.NumberInputButtonCaps, caps.NumberInputValueCaps);
    char *buf = calloc(1, caps.InputReportByteLength);
    char *prev = calloc(1, caps.InputReportByteLength);
    DWORD t0 = GetTickCount();
    printf("USAGES: press buttons one at a time (~4s each), Ctrl-C to stop\n");
    for (;;) {
        DWORD n = 0;
        if (!ReadFile(h, buf, caps.InputReportByteLength, &n, NULL)) {
            printf("read failed %lu\n", GetLastError());
            return 1;
        }
        if (n != caps.InputReportByteLength) continue;
        if (!memcmp(buf, prev, n)) continue;
        memcpy(prev, buf, n);
        USAGE us[32];
        ULONG nu = 32;
        NTSTATUS st = HidP_GetUsages(HidP_Input, 9, 0, us, &nu, ppd, buf, n);
        ULONG hat = 99;
        HidP_GetUsageValue(HidP_Input, 1, 0, 0x39, &hat, ppd, buf, n);
        ULONG x = 0, y = 0, z = 0, rz = 0, br = 0, ac = 0;
        HidP_GetUsageValue(HidP_Input, 1, 0, 0x30, &x, ppd, buf, n);
        HidP_GetUsageValue(HidP_Input, 1, 0, 0x31, &y, ppd, buf, n);
        HidP_GetUsageValue(HidP_Input, 1, 0, 0x32, &z, ppd, buf, n);
        HidP_GetUsageValue(HidP_Input, 1, 0, 0x35, &rz, ppd, buf, n);
        HidP_GetUsageValue(HidP_Input, 2, 0, 0xc5, &br, ppd, buf, n);
        HidP_GetUsageValue(HidP_Input, 2, 0, 0xc4, &ac, ppd, buf, n);
        printf("t=%5lu btn%s", (unsigned long)(GetTickCount() - t0) / 1000,
               st == HIDP_STATUS_SUCCESS ? "=" : "?=");
        if (st == HIDP_STATUS_SUCCESS)
            for (ULONG k = 0; k < nu; k++) printf("%u,", us[k]);
        printf(" hat=%lu X=%04lx Y=%04lx Z=%04lx Rz=%04lx br=%03lx ac=%03lx b14=%02x b15=%02x\n",
               hat, x, y, z, rz, br, ac,
               (unsigned char)buf[13], (unsigned char)buf[14]);
        fflush(stdout);
    }
    return 0;
}
