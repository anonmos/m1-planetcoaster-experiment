/* cr_repro.c — CONTROL Resonant window-hang reproducer.
 *
 * Mimics the game's cross-thread init handshake (from relay-cr-saved.log):
 *  Thread A (main): RegisterClassW("AppWindowClass") -> spawn workers ->
 *    PostThreadMessageA(workerB, WM_APP) -> SleepConditionVariableSRW (park)
 *  Thread B (job worker): CreateWindowExW(atom, "CONTROL Resonant",
 *    WS_POPUP|WS_VISIBLE, 0,33,1728,1117)  <-- hangs in NtUserGetClassInfoEx
 *
 * Game's WNDCLASS (disassembled at CONTROLResonant.exe+0x400714):
 *   style=8 (CS_DBLCLKS), custom WndProc, extras=0/0, hInstance=module,
 *   hIcon=LoadIcon(101), hCursor=loaded, hbrBackground=GetStockObject(4
 *   =BLACK_BRUSH), menu=NULL, class=L"AppWindowClass".
 *
 * Self-diagnosing: watchdog exits 2 on hang, 0 on success. No debugger needed.
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <objbase.h>

static const wchar_t *CLASS_NAME = L"AppWindowClass";
static const wchar_t *WIN_TITLE  = L"CONTROL Resonant";

static SRWLOCK g_lock = SRWLOCK_INIT;
static CONDITION_VARIABLE g_cv = CONDITION_VARIABLE_INIT;
static HANDLE g_workerReady = NULL;   /* worker queue exists */
static HANDLE g_goEvent = NULL;       /* worker may call CreateWindow */
static HANDLE g_doneEvent = NULL;     /* worker finished CreateWindow */
static DWORD g_workerTid = 0;
static HWND g_hwnd = NULL;
static DWORD g_createErr = 0;
static ATOM g_regAtom = 0;
static volatile LONG g_hangReported = 0;

#define N_PARKERS 8

/* Watchdog: game does ~5000 relay lines of work between resume and post.
 * Sleep 3s (main parks meanwhile), then open the gate. At 20s, declare hang. */
static DWORD WINAPI WatchdogThread(LPVOID p) {
    (void)p;
    /* Main parks immediately after posting now; no gate needed. Pure reporter. */
#ifdef LONG_WATCH
    DWORD wr = WaitForSingleObject(g_doneEvent, 90000);
#else
    DWORD wr = WaitForSingleObject(g_doneEvent, 20000);
#endif
    if (wr != WAIT_OBJECT_0 && !g_hwnd) {
        g_hangReported = 1;
        printf("REPRO: HANG REPRODUCED - CreateWindowExW never returned (err so far=%lu)\n",
            (unsigned long)g_createErr);
        fflush(stdout);
        TerminateProcess(GetCurrentProcess(), 2);
    }
    return 0;
}

static LRESULT CALLBACK ReproWndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    return DefWindowProcW(h, m, w, l);
}

static DWORD WINAPI ParkerThread(LPVOID p) {
    (void)p;
    AcquireSRWLockExclusive(&g_lock);
    SleepConditionVariableSRW(&g_cv, &g_lock, INFINITE, 0);
    ReleaseSRWLockExclusive(&g_lock);
    return 0;
}

static DWORD WINAPI WorkerThread(LPVOID p) {
    MSG msg;
    (void)p;
    /* Game thread B blocks in GetMessageW (relay :8399540 Ret=1: it retrieves
     * the posted WM_APP), does an SRW pulse, then creates the window. */
    /* Queue does not exist until first GetMessage/Peek: realize it, signal
     * ready, then block retrieving like game thread B. */
    MSG pq;
    PeekMessageW(&pq, NULL, 0, 0, PM_NOREMOVE); /* realize queue deterministically */
    SetEvent(g_workerReady);
    if (GetMessageW(&msg, NULL, 0, 0) <= 0) {
        printf("REPRO: worker GetMessage quit/err\n");
        SetEvent(g_doneEvent);
        return 1;
    }
    AcquireSRWLockExclusive(&g_lock);
    ReleaseSRWLockExclusive(&g_lock);
    /* NOTE: a WM_APP posted by main is pending in this queue, exactly like
     * the game: PostThreadMessageA(B, WM_APP) precedes CreateWindowExW. */
    HINSTANCE inst = GetModuleHandleW(NULL);
    /* Game passes the class ATOM (0xC053), not the string. */
    HWND hwnd = CreateWindowExW(WS_EX_APPWINDOW, MAKEINTRESOURCEW(g_regAtom),
        WIN_TITLE, WS_POPUP | WS_VISIBLE,
        0, 33, 1728, 1117, NULL, NULL, inst, NULL);
    if (!hwnd) g_createErr = GetLastError();
    g_hwnd = hwnd;
    SetEvent(g_doneEvent);
    if (hwnd) {
        MSG m2;
        DWORD start = GetTickCount();
        while (GetTickCount() - start < 3000) {
            while (PeekMessageW(&m2, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&m2);
                DispatchMessageW(&m2);
            }
            Sleep(16);
        }
        DestroyWindow(hwnd);
        AcquireSRWLockExclusive(&g_lock);
        WakeAllConditionVariable(&g_cv);
        ReleaseSRWLockExclusive(&g_lock);
    }
    return hwnd ? 0 : 1;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("REPRO: main thread id=%lu\n", (unsigned long)GetCurrentThreadId());
#ifdef COM_MAIN
    {
        HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        printf("REPRO: CoInitializeEx(APARTMENT) hr=0x%08lx\n", (long)hr);
    }
#endif

    g_workerReady = CreateEventW(NULL, FALSE, FALSE, NULL);
    g_goEvent = CreateEventW(NULL, FALSE, FALSE, NULL);
    g_doneEvent = CreateEventW(NULL, FALSE, FALSE, NULL);

#ifdef PRELOAD_SL
    {
        HMODULE sl = LoadLibraryW(L"C:\\Program Files (x86)\\Steam\\steamapps\\common\\CONTROL Resonant\\sl.interposer.dll");
        printf("REPRO: preload sl.interposer.dll => %p err=%lu\n", (void *)sl, (unsigned long)GetLastError());
    }
#endif
#ifdef PRELOAD_D3D12
    {
        HMODULE ag = LoadLibraryW(L"C:\\Program Files (x86)\\Steam\\steamapps\\common\\CONTROL Resonant\\D3D12Core.dll");
        printf("REPRO: preload D3D12Core.dll => %p err=%lu\n", (void *)ag, (unsigned long)GetLastError());
    }
#endif
#ifdef PRELOAD_STEAMAPI
    {
        HMODULE st = LoadLibraryW(L"C:\\Program Files (x86)\\Steam\\steamapps\\common\\CONTROL Resonant\\steam_api64.dll");
        printf("REPRO: preload steam_api64.dll => %p err=%lu\n", (void *)st, (unsigned long)GetLastError());
#ifdef STEAM_INIT
        if (st) {
            int (WINAPI *pInit)(void) = (void *)GetProcAddress(st, "SteamInternal_SteamAPI_Init");
            void (WINAPI *pRun)(void) = (void *)GetProcAddress(st, "SteamAPI_RunCallbacks");
            printf("REPRO: SteamInternal_SteamAPI_Init ptr=%p RunCallbacks ptr=%p\n",
                (void *)pInit, (void *)pRun);
            if (pInit) {
                int r = pInit();
                printf("REPRO: SteamInternal_SteamAPI_Init => %d (0=OK)\n", r);
            }
            if (pRun) { for (int i = 0; i < 5; i++) { pRun(); Sleep(100); } printf("REPRO: ran callbacks\n"); }
        }
#endif
    }
#endif

    /* Game lifecycle: job workers spawn and park FIRST (relay lines ~193k),
     * class registration happens much LATER (~8394k). */
    for (int i = 0; i < N_PARKERS; i++) {
        HANDLE h = CreateThread(NULL, 0, ParkerThread, NULL, 0, NULL);
        if (h) CloseHandle(h);
    }
    /* Game spawns B SUSPENDED (relay CreateThread flag 0x4), resumes later. */
    HANDLE wh = CreateThread(NULL, 0, WorkerThread, NULL, CREATE_SUSPENDED, &g_workerTid);
    if (!wh) { printf("REPRO: worker spawn FAILED\n"); return 1; }
    DWORD rprev = ResumeThread(wh);
    printf("REPRO: resumed worker (prev=%lu)\n", (unsigned long)rprev);
    WaitForSingleObject(g_workerReady, INFINITE);
    printf("REPRO: %d parker threads + worker tid=%lu parked (game: job system up first)\n",
        N_PARKERS, (unsigned long)g_workerTid);
    Sleep(500);

    printf("REPRO: RegisterClassW(AppWindowClass) style=8 bg=BLACK_BRUSH\n");
    WNDCLASSW wc = {0};
    wc.style = 8;
    wc.lpfnWndProc = ReproWndProc;
    wc.hInstance = GetModuleHandleW(NULL);
    printf("REPRO: hInstance=%p\n", (void *)wc.hInstance);
    wc.hIcon = LoadIconW(wc.hInstance, MAKEINTRESOURCEW(101));
    printf("REPRO: LoadIcon(101)=%p err=%lu\n", (void *)wc.hIcon, (unsigned long)GetLastError());
    if (!wc.hIcon) wc.hIcon = LoadIconW(NULL, MAKEINTRESOURCEW(32512));
    wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
    printf("REPRO: cursor=%p\n", (void *)wc.hCursor);
    wc.hbrBackground = GetStockObject(BLACK_BRUSH);
    printf("REPRO: bg=%p\n", (void *)wc.hbrBackground);
    wc.lpszClassName = CLASS_NAME;
    SetLastError(0);
    ATOM reg = RegisterClassW(&wc);
    if (!reg) {
        DWORD e = GetLastError();
        printf("REPRO: RegisterClassW FAILED err=%lu; retrying W...\n", (unsigned long)e);
        SetLastError(0);
        ATOM reg2 = RegisterClassW(&wc);
        printf("REPRO: RegisterClassW retry => 0x%x err=%lu\n", (unsigned)reg2, (unsigned long)GetLastError());
        if (!reg2) { printf("REPRO: trying RegisterClassExW\n");
        WNDCLASSEXW wex = { sizeof(wex) };
        wex.style = 8; wex.lpfnWndProc = ReproWndProc;
        wex.hInstance = wc.hInstance; wex.hIcon = wc.hIcon;
        wex.hCursor = wc.hCursor; wex.hbrBackground = wc.hbrBackground;
        wex.lpszClassName = CLASS_NAME;
        SetLastError(0);
        reg = RegisterClassExW(&wex);
        printf("REPRO: RegisterClassExW => 0x%x err=%lu\n", (unsigned)reg, (unsigned long)GetLastError());
        } else { reg = reg2; }
    }
    if (!reg) { printf("REPRO: RegisterClassW FAILED err=%lu\n", (unsigned long)GetLastError()); return 1; }
    printf("REPRO: registered atom=0x%x (game: 0xc053)\n", (unsigned)reg);
    g_regAtom = reg;
    Sleep(500);

    /* Game order: create worker SUSPENDED (relay :8394450), resume it,
     * post WM_APP, then park on condvar INFINITE — BEFORE worker creates.
     * A watchdog thread opens the gate after 3s (game's interleave delay). */
    HANDLE wdog = CreateThread(NULL, 0, WatchdogThread, NULL, 0, NULL);
    if (wdog) CloseHandle(wdog);
    if (!PostThreadMessageW(g_workerTid, WM_APP, 0, 0))
        printf("REPRO: PostThreadMessageW FAILED err=%lu\n", (unsigned long)GetLastError());
    else
        printf("REPRO: posted WM_APP to worker; main parking (worker gated 3s)\n");
    AcquireSRWLockExclusive(&g_lock);
    SleepConditionVariableSRW(&g_cv, &g_lock, INFINITE, 0);
    ReleaseSRWLockExclusive(&g_lock);
    if (g_hwnd) {
        printf("REPRO: SUCCESS - worker created window hwnd=%p\n", (void *)g_hwnd);
        WaitForSingleObject(wh, INFINITE);
        CloseHandle(wh);
        return 0;
    }
    printf("REPRO: main woke unexpectedly\n");
    return 0;
}
