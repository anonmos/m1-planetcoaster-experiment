#define COBJMACROS
#include <stdio.h>
#include <windows.h>

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { printf("usage: sl_probe.exe <dll>\n"); return 2; }
    printf("PROBE: loading %s\n", argv[1]);
    HMODULE h = LoadLibraryA(argv[1]);
    printf("PROBE: LoadLibrary returned %p err=%lu\n", (void *)h, (unsigned long)GetLastError());
    if (h) { printf("PROBE: SUCCESS\n"); FreeLibrary(h); }
    printf("PROBE: done\n");
    return 0;
}
