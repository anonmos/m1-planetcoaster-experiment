/* reg_probe.c — maps RegisterClassW-vs-ExW err=123 behavior. */
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>

static LRESULT CALLBACK WP(HWND h, UINT m, WPARAM w, LPARAM l) {
    return DefWindowProcW(h, m, w, l);
}

static void tryW(const wchar_t *n) {
    WNDCLASSW wc = {0};
    wc.style = 8; wc.lpfnWndProc = WP;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
    wc.hbrBackground = GetStockObject(BLACK_BRUSH);
    wc.lpszClassName = n;
    SetLastError(0);
    ATOM a = RegisterClassW(&wc);
    wprintf(L"PROBE: RegisterClassW(%ls) => 0x%x err=%lu\n", n, (unsigned)a, (unsigned long)GetLastError());
}

static void tryEx(const wchar_t *n) {
    WNDCLASSEXW wx = { sizeof(wx) };
    wx.style = 8; wx.lpfnWndProc = WP;
    wx.hInstance = GetModuleHandleW(NULL);
    wx.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
    wx.hbrBackground = GetStockObject(BLACK_BRUSH);
    wx.lpszClassName = n;
    SetLastError(0);
    ATOM a = RegisterClassExW(&wx);
    wprintf(L"PROBE: RegisterClassExW(%ls) => 0x%x err=%lu\n", n, (unsigned)a, (unsigned long)GetLastError());
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    tryW(L"W1");
    tryW(L"W2");
    tryEx(L"E1");
    tryW(L"W3");
    tryEx(L"AppWindowClass");
    return 0;
}
