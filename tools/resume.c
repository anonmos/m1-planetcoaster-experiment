/* resume.c — resume a suspended thread by TID, report previous suspend count. */
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { printf("usage: resume.exe <tid-dec>\n"); return 1; }
    DWORD tid = (DWORD)strtoul(argv[1], NULL, 10);
    HANDLE h = OpenThread(THREAD_SUSPEND_RESUME, FALSE, tid);
    if (!h) { printf("RESUME: OpenThread(%lu) FAILED err=%lu\n", (unsigned long)tid, (unsigned long)GetLastError()); return 1; }
    DWORD prev = ResumeThread(h);
    printf("RESUME: tid=%lu prev_suspend_count=%lu err=%lu\n", (unsigned long)tid, (unsigned long)prev, (unsigned long)GetLastError());
    CloseHandle(h);
    return 0;
}
