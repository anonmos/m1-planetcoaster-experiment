// regkey_probe.c — replicate winebus Devices key enumeration + child open.
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <winternl.h>

typedef NTSTATUS (NTAPI *pNtOpenKey)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES);
typedef NTSTATUS (NTAPI *pNtEnumerateKey)(HANDLE, ULONG, int, PVOID, ULONG, PULONG);
typedef NTSTATUS (NTAPI *pNtQueryValueKey)(HANDLE, PUNICODE_STRING, int, PVOID, ULONG, PULONG);
typedef NTSTATUS (NTAPI *pNtClose)(HANDLE);

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    pNtOpenKey o = (void *)GetProcAddress(ntdll, "NtOpenKey");
    pNtEnumerateKey e = (void *)GetProcAddress(ntdll, "NtEnumerateKey");
    pNtQueryValueKey q = (void *)GetProcAddress(ntdll, "NtQueryValueKey");
    pNtClose c = (void *)GetProcAddress(ntdll, "NtClose");
    WCHAR path[] = L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\WineBus\\Devices";
    UNICODE_STRING us;
    OBJECT_ATTRIBUTES attr;
    HANDLE key;
    us.Buffer = path; us.Length = wcslen(path) * 2; us.MaximumLength = us.Length + 2;
    attr.Length = sizeof(attr); attr.RootDirectory = 0;
    attr.ObjectName = &us; attr.Attributes = 0x40; attr.SecurityDescriptor = 0; attr.SecurityQualityOfService = 0;
    NTSTATUS st = o(&key, KEY_ALL_ACCESS, &attr);
    printf("REGKEY: open Devices => 0x%08lx h=%p\n", (unsigned long)st, (void *)key);
    if (st) return 1;
    for (ULONG idx = 0; idx < 8; idx++) {
        char buf[600];
        ULONG sz = 0;
        st = e(key, idx, 3, buf, sizeof(buf), &sz);
        if (st) { printf("REGKEY: enum %lu end 0x%08lx\n", (unsigned long)idx, (unsigned long)st); break; }
        ULONG *nl = (ULONG *)buf; /* KEY_NAME_INFORMATION: NameLength @0, Name @4 */
        int n = nl[0] / 2;
        WCHAR *nm = (WCHAR *)(buf + 4);
        printf("REGKEY: child[%lu] len=%d name=%.*ls\n", (unsigned long)idx, n, n, nm);
        {
            UNICODE_STRING cs;
            OBJECT_ATTRIBUTES ca;
            HANDLE sub = 0;
            cs.Buffer = nm; cs.Length = nl[0]; cs.MaximumLength = cs.Length;
            ca.Length = sizeof(ca); ca.RootDirectory = 0;
            ca.ObjectName = &cs; ca.Attributes = 0x40; ca.SecurityDescriptor = 0; ca.SecurityQualityOfService = 0;
            NTSTATUS st2 = o(&sub, KEY_ALL_ACCESS, &ca);
            printf("REGKEY: open child rel-root0 => 0x%08lx h=%p\n", (unsigned long)st2, (void *)sub);
            if (!st2) {
                UNICODE_STRING vn;
                WCHAR vnbuf[] = L"Hidraw";
                char vbuf[64];
                ULONG vsz = 0;
                vn.Buffer = vnbuf; vn.Length = 12; vn.MaximumLength = 14;
                NTSTATUS st3 = q(sub, &vn, 2, vbuf, sizeof(vbuf), &vsz);
                printf("REGKEY: query Hidraw => 0x%08lx\n", (unsigned long)st3);
                if (!st3) {
                    ULONG *pi = (ULONG *)vbuf;
                    printf("REGKEY: Hidraw type=%lu val=%lu\n",
                        (unsigned long)pi[0], (unsigned long)(*(DWORD *)(vbuf + 12)));
                }
                c(sub);
            }
        }
    }
    c(key);
    return 0;
}
