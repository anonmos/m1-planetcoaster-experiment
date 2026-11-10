#include <windows.h>
#include <stdio.h>

int main(void) {
    LARGE_INTEGER freq, t0, t1;
    int i;
    long long d, hist[10] = {0,0,0,0,0,0,0,0,0,0};
    QueryPerformanceFrequency(&freq);
    for (i = 0; i < 500; i++) {
        QueryPerformanceCounter(&t0);
        Sleep(5);
        QueryPerformanceCounter(&t1);
        d = (t1.QuadPart - t0.QuadPart) * 1000000 / freq.QuadPart;
        if (d < 0) d = 0;
        hist[d / 2000 > 9 ? 9 : d / 2000]++;
    }
    for (i = 0; i < 10; i++)
        printf("%2d-%2dms: %lld\n", i*2, i*2+2, hist[i]);
    return 0;
}
