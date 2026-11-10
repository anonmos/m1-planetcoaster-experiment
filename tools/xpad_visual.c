/* xpad_visual.c — visual Xbox controller tester for Wine.
 *
 * Polls XInput (30 Hz timer), draws sticks/buttons/triggers/dpad live.
 * Usage: run it, press everything. pkt counter proves liveness.
 * Build: x86_64-w64-mingw32-gcc -O2 -o xpad_visual.exe xpad_visual.c
 *        -lxinput -lgdi32 -luser32 -lkernel32 -static-libgcc
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <xinput.h>

#define WIN_W 660
#define WIN_H 440

static int g_slot = -1;
static XINPUT_STATE g_st = {0};
static DWORD g_lastPkt = 0;
static int g_stallMs = 0;

static void fill_circle(HDC dc, int cx, int cy, int r, COLORREF col) {
    HBRUSH b = CreateSolidBrush(col);
    HBRUSH old = SelectObject(dc, b);
    HPEN p = CreatePen(PS_SOLID, 1, RGB(60, 60, 60));
    HPEN oldp = SelectObject(dc, p);
    Ellipse(dc, cx - r, cy - r, cx + r, cy + r);
    SelectObject(dc, oldp);
    SelectObject(dc, old);
    DeleteObject(p);
    DeleteObject(b);
}

static void ring(HDC dc, int cx, int cy, int r) {
    HPEN p = CreatePen(PS_SOLID, 2, RGB(120, 120, 120));
    HPEN oldp = SelectObject(dc, p);
    HBRUSH oldb = SelectObject(dc, GetStockObject(NULL_BRUSH));
    Ellipse(dc, cx - r, cy - r, cx + r, cy + r);
    SelectObject(dc, oldb);
    SelectObject(dc, oldp);
    DeleteObject(p);
}

static void bar(HDC dc, int x, int y, int w, int h, int val, int max) {
    Rectangle(dc, x, y, x + w, y + h);
    if (val > 0) {
        int fh = (h * val) / max;
        HBRUSH b = CreateSolidBrush(RGB(60, 180, 255));
        RECT r = { x + 1, y + h - fh, x + w - 1, y + h - 1 };
        FillRect(dc, &r, b);
        DeleteObject(b);
    }
}

static void btn(HDC dc, int x, int y, const char *label, int on) {
    fill_circle(dc, x, y, 16, on ? RGB(60, 220, 80) : RGB(45, 45, 45));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(230, 230, 230));
    TextOutA(dc, x - 4, y - 8, label, 1);
}

static void stick(HDC dc, int cx, int cy, int sx, int sy, const char *label) {
    ring(dc, cx, cy, 52);
    int dx = (sx * 44) / 32768;
    int dy = -(sy * 44) / 32768;
    fill_circle(dc, cx + dx, cy + dy, 12, RGB(90, 160, 255));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(150, 150, 150));
    TextOutA(dc, cx - 20, cy + 58, label, lstrlenA(label));
    char v[64];
    wsprintfA(v, "%d,%d", sx, sy);
    TextOutA(dc, cx - 30, cy + 74, v, lstrlenA(v));
}

static void paint(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    HDC mem = CreateCompatibleDC(dc);
    HBITMAP bmp = CreateCompatibleBitmap(dc, WIN_W, WIN_H);
    HBITMAP old = SelectObject(mem, bmp);
    RECT full = { 0, 0, WIN_W, WIN_H };
    HBRUSH bg = CreateSolidBrush(RGB(24, 24, 28));
    FillRect(mem, &full, bg);
    DeleteObject(bg);

    WORD b = g_st.Gamepad.wButtons;
    char hdr[128];
    if (g_slot < 0)
        wsprintfA(hdr, "xpad_visual — no controller (slot search...)");
    else
        wsprintfA(hdr, "xpad_visual — slot %d  pkt=%lu%s", g_slot,
            (unsigned long)g_st.dwPacketNumber,
            g_stallMs > 1500 ? "  STALLED?" : "  LIVE");
    SetBkMode(mem, TRANSPARENT);
    SetTextColor(mem, RGB(255, 255, 255));
    TextOutA(mem, 16, 10, hdr, lstrlenA(hdr));

    /* bumpers + triggers */
    btn(mem, 150, 70, "L", (b & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0);
    btn(mem, 510, 70, "R", (b & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0);
    bar(mem, 120, 100, 60, 90, g_st.Gamepad.bLeftTrigger, 255);
    bar(mem, 480, 100, 60, 90, g_st.Gamepad.bRightTrigger, 255);
    SetTextColor(mem, RGB(150, 150, 150));
    TextOutA(mem, 132, 192, "LT", 2);
    TextOutA(mem, 492, 192, "RT", 2);

    /* ABXY diamond */
    btn(mem, 510, 250, "Y", (b & XINPUT_GAMEPAD_Y) != 0);
    btn(mem, 470, 290, "X", (b & XINPUT_GAMEPAD_X) != 0);
    btn(mem, 550, 290, "B", (b & XINPUT_GAMEPAD_B) != 0);
    btn(mem, 510, 330, "A", (b & XINPUT_GAMEPAD_A) != 0);

    /* back/start/sticks-click */
    btn(mem, 280, 130, "B", (b & XINPUT_GAMEPAD_BACK) != 0);
    btn(mem, 380, 130, "S", (b & XINPUT_GAMEPAD_START) != 0);
    btn(mem, 280, 175, "L", (b & XINPUT_GAMEPAD_LEFT_THUMB) != 0);
    btn(mem, 380, 175, "R", (b & XINPUT_GAMEPAD_RIGHT_THUMB) != 0);

    /* dpad */
    {
        int x = 150, y = 290, s = 22;
        COLORREF on = RGB(60, 220, 80), off = RGB(45, 45, 45);
        HBRUSH bo = CreateSolidBrush(off), bn = CreateSolidBrush(on);
        RECT r;
        r.left = x; r.top = y - s; r.right = x + s; r.bottom = y;
        FillRect(mem, &r, (b & XINPUT_GAMEPAD_DPAD_UP) ? bn : bo);
        r.top = y + s; r.bottom = y + 2 * s;
        FillRect(mem, &r, (b & XINPUT_GAMEPAD_DPAD_DOWN) ? bn : bo);
        r.left = x - s; r.top = y; r.right = x; r.bottom = y + s;
        FillRect(mem, &r, (b & XINPUT_GAMEPAD_DPAD_LEFT) ? bn : bo);
        r.left = x + s; r.right = x + 2 * s;
        FillRect(mem, &r, (b & XINPUT_GAMEPAD_DPAD_RIGHT) ? bn : bo);
        DeleteObject(bo); DeleteObject(bn);
        SetTextColor(mem, RGB(150, 150, 150));
        TextOutA(mem, x - 12, y + 2 * s + 6, "dpad", 4);
    }

    /* sticks */
    stick(mem, 150, 290 - 140, g_st.Gamepad.sThumbLX, g_st.Gamepad.sThumbLY, "left");
    stick(mem, 330, 290, g_st.Gamepad.sThumbRX, g_st.Gamepad.sThumbRY, "right");

    BitBlt(dc, 0, 0, WIN_W, WIN_H, mem, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    EndPaint(hwnd, &ps);
}

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_TIMER:
        {
            int found = -1;
            XINPUT_STATE st;
            for (int i = 0; i < 4; i++) {
                if (XInputGetState(i, &st) == ERROR_SUCCESS) { found = i; break; }
            }
            if (found >= 0) {
                if (st.dwPacketNumber != g_lastPkt) {
                    g_lastPkt = st.dwPacketNumber;
                    g_stallMs = 0;
                } else {
                    g_stallMs += 33;
                }
                g_slot = found;
                g_st = st;
            } else {
                g_slot = -1;
            }
            InvalidateRect(h, NULL, FALSE);
        }
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    case WM_PAINT:
        paint(h);
        return 0;
    }
    return DefWindowProcA(h, m, w, l);
}

int WINAPI WinMain(HINSTANCE hi, HINSTANCE p, LPSTR c, int show) {
    (void)p; (void)c;
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hi;
    wc.lpszClassName = "XPadVisual";
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)32512);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    if (!RegisterClassA(&wc)) return 1;
    HWND hwnd = CreateWindowExA(0, "XPadVisual", "Xbox Pad Visual Tester",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        200, 200, WIN_W + 16, WIN_H + 39, NULL, NULL, hi, NULL);
    if (!hwnd) return 1;
    ShowWindow(hwnd, show);
    UpdateWindow(hwnd);
    SetTimer(hwnd, 1, 33, NULL);
    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return 0;
}
