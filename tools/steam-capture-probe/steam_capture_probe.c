#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fill_rect(HDC dc, int l, int t, int r, int b, COLORREF color)
{
    RECT rect = { l, t, r, b };
    HBRUSH brush = CreateSolidBrush(color);
    FillRect(dc, &rect, brush);
    DeleteObject(brush);
}

static LRESULT CALLBACK pattern_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    (void)wp; (void)lp;
    if (msg == WM_PAINT) {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        RECT r;
        GetClientRect(hwnd, &r);
        int mx = r.right / 2, my = r.bottom / 2;
        fill_rect(dc, 0, 0, mx, my, RGB(255, 0, 0));
        fill_rect(dc, mx, 0, r.right, my, RGB(0, 255, 0));
        fill_rect(dc, 0, my, mx, r.bottom, RGB(0, 0, 255));
        fill_rect(dc, mx, my, r.right, r.bottom, RGB(255, 255, 255));
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(0, 0, 0));
        HFONT font = CreateFontA(28, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                 DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                 ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, "Arial");
        HFONT old = (HFONT)SelectObject(dc, font);
        RECT label = { 24, 20, mx - 20, my - 16 };
        DrawTextA(dc, "RED 255,0,0", -1, &label, DT_LEFT | DT_TOP | DT_SINGLELINE);
        label.left = mx + 24; label.right = r.right - 20;
        DrawTextA(dc, "GREEN 0,255,0", -1, &label, DT_LEFT | DT_TOP | DT_SINGLELINE);
        label.left = 24; label.top = my + 20; label.right = mx - 20;
        DrawTextA(dc, "BLUE 0,0,255", -1, &label, DT_LEFT | DT_TOP | DT_SINGLELINE);
        label.left = mx + 24; label.right = r.right - 20;
        DrawTextA(dc, "WHITE 255,255,255", -1, &label, DT_LEFT | DT_TOP | DT_SINGLELINE);
        SelectObject(dc, old);
        DeleteObject(font);
        fill_rect(dc, mx - 18, my - 18, mx + 18, my + 18, RGB(0, 0, 0));
        EndPaint(hwnd, &ps);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

#pragma pack(push, 1)
typedef struct { WORD type; DWORD size; WORD r1, r2; DWORD offset; } BMP_FILE_HEADER;
#pragma pack(pop)

static int save_bmp(const char *path, int w, int h, const uint8_t *pixels)
{
    BMP_FILE_HEADER fh = { 0 };
    BITMAPINFOHEADER ih = { 0 };
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    fh.type = 0x4d42;
    fh.offset = sizeof(fh) + sizeof(ih);
    fh.size = fh.offset + (DWORD)(w * h * 4);
    ih.biSize = sizeof(ih); ih.biWidth = w; ih.biHeight = -h;
    ih.biPlanes = 1; ih.biBitCount = 32; ih.biCompression = BI_RGB;
    ih.biSizeImage = (DWORD)(w * h * 4);
    int ok = fwrite(&fh, sizeof(fh), 1, f) == 1 &&
             fwrite(&ih, sizeof(ih), 1, f) == 1 &&
             fwrite(pixels, (size_t)w * h * 4, 1, f) == 1;
    fclose(f);
    return ok;
}

static uint64_t hash_rgb(const uint8_t *p, size_t pixels)
{
    uint64_t h = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < pixels; ++i)
        for (int c = 0; c < 3; ++c) h = (h ^ p[i * 4 + c]) * UINT64_C(1099511628211);
    return h;
}

static void sample(const uint8_t *p, int w, int x, int y, unsigned *r, unsigned *g, unsigned *b)
{
    const uint8_t *q = p + ((size_t)y * w + x) * 4;
    *b = q[0]; *g = q[1]; *r = q[2];
}

static void capture_one(const char *out, FILE *csv, unsigned frame, const char *method,
                        DWORD rop, HDC src, HDC mem, uint8_t *px, int w, int h, size_t count)
{
    memset(px, 0, count * 4);
    SetLastError(ERROR_SUCCESS);
    BOOL ok = BitBlt(mem, 0, 0, w, h, src, 0, 0, rop);
    DWORD err = GetLastError();
    size_t nonblack = 0;
    for (size_t j = 0; j < count; ++j)
        if ((unsigned)px[j * 4] + px[j * 4 + 1] + px[j * 4 + 2] > 20) ++nonblack;
    unsigned rr, rg, rb, gr, gg, gb, br, bg, bb, wr, wg, wb, cr, cg, cb;
    sample(px, w, w / 4, h / 4, &rr, &rg, &rb);
    sample(px, w, 3 * w / 4, h / 4, &gr, &gg, &gb);
    sample(px, w, w / 4, 3 * h / 4, &br, &bg, &bb);
    sample(px, w, 3 * w / 4, 3 * h / 4, &wr, &wg, &wb);
    sample(px, w, w / 2, h / 2, &cr, &cg, &cb);
    char path[MAX_PATH * 2];
    snprintf(path, sizeof(path), "%s\\frame_%04u_%s.bmp", out, frame, method);
    if (!save_bmp(path, w, h, px)) fprintf(stderr, "BMP write failed: %s\n", path);
    fprintf(csv, "%u,%s,%u,%lu,%016llx,%.3f,%u:%u:%u,%u:%u:%u,%u:%u:%u,%u:%u:%u,%u:%u:%u\n",
            frame, method, ok ? 1u : 0u, (unsigned long)err,
            (unsigned long long)hash_rgb(px, count), 100.0 * (double)nonblack / (double)count,
            rr, rg, rb, gr, gg, gb, br, bg, bb, wr, wg, wb, cr, cg, cb);
    fflush(csv);
    printf("frame %u %s: BitBlt=%s error=%lu nonblack=%.1f%% samples TL=%u,%u,%u TR=%u,%u,%u BL=%u,%u,%u BR=%u,%u,%u\n",
           frame, method, ok ? "ok" : "FAIL", (unsigned long)err,
           100.0 * (double)nonblack / (double)count, rr, rg, rb, gr, gg, gb, br, bg, bb, wr, wg, wb);
}

int main(int argc, char **argv)
{
    const char *out = argc > 1 ? argv[1] : "Z:/private/tmp/steam-rp-capture-probe";
    unsigned frames = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 8;
    unsigned fps = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 2;
    SetProcessDPIAware();
    int w = GetSystemMetrics(SM_CXSCREEN), h = GetSystemMetrics(SM_CYSCREEN);
    if (!frames || frames > 10000 || !fps || fps > 60 || w < 2 || h < 2) return 2;
    CreateDirectoryA(out, NULL);

    WNDCLASSA wc = { 0 };
    wc.lpfnWndProc = pattern_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "SteamCaptureProbePattern";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClassA(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        fprintf(stderr, "RegisterClass failed: %lu\n", GetLastError()); return 3;
    }
    HWND win = CreateWindowExA(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, wc.lpszClassName,
                               "Steam BitBlt capture probe", WS_POPUP, 0, 0, w, h,
                               NULL, NULL, wc.hInstance, NULL);
    if (!win) { fprintf(stderr, "CreateWindowEx failed: %lu\n", GetLastError()); return 4; }
    ShowWindow(win, SW_SHOW); SetForegroundWindow(win); UpdateWindow(win); Sleep(500);

    BITMAPINFO bmi = { 0 };
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w; bmi.bmiHeader.biHeight = -h;
    bmi.bmiHeader.biPlanes = 1; bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    HDC mem = CreateCompatibleDC(NULL);
    void *bits = NULL;
    HBITMAP dib = CreateDIBSection(mem, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!mem || !dib || !bits) { fprintf(stderr, "CreateDIBSection failed: %lu\n", GetLastError()); return 5; }
    HBITMAP old = (HBITMAP)SelectObject(mem, dib);
    HDC screen = GetDC(NULL);
    if (!screen) { fprintf(stderr, "GetDC(NULL) failed: %lu\n", GetLastError()); return 6; }

    char path[MAX_PATH * 2];
    snprintf(path, sizeof(path), "%s\\manifest.csv", out);
    FILE *csv = fopen(path, "w");
    if (!csv) { fprintf(stderr, "Cannot write %s\n", path); return 7; }
    fprintf(csv, "frame,method,bitblt_ok,last_error,rgb_hash,nonblack_pct,red_rgb,green_rgb,blue_rgb,white_rgb,center_rgb\n");
    printf("Capturing %u GDI BitBlt frames at %dx%d, %u fps into %s\n", frames, w, h, fps, out);

    size_t count = (size_t)w * h;
    uint8_t *px = (uint8_t *)bits;
    DWORD interval = 1000 / fps;
    HWND desktop_window = GetDesktopWindow();
    HDC desktop_window_dc = GetDC(desktop_window);
    HDC window_dc = GetDC(win);
    if (!window_dc || !desktop_window_dc) { fprintf(stderr, "GetDC failed: %lu\n", GetLastError()); return 9; }
    RECT desktop_rect = { 0 };
    GetClientRect(desktop_window, &desktop_rect);
    printf("Desktop HWND client size: %ldx%ld; capture checks: window, desktop HWND, GetDC(NULL) plain and CAPTUREBLT\n",
           desktop_rect.right - desktop_rect.left, desktop_rect.bottom - desktop_rect.top);
    for (unsigned i = 0; i < frames; ++i) {
        ULONGLONG t0 = GetTickCount64();
        capture_one(out, csv, i, "window_dc", SRCCOPY, window_dc, mem, px, w, h, count);
        capture_one(out, csv, i, "desktop_window_dc", SRCCOPY, desktop_window_dc, mem, px, w, h, count);
        capture_one(out, csv, i, "screen_srccopy", SRCCOPY, screen, mem, px, w, h, count);
        capture_one(out, csv, i, "screen_captureblt", SRCCOPY | CAPTUREBLT, screen, mem, px, w, h, count);
        DWORD spent = (DWORD)(GetTickCount64() - t0);
        if (i + 1 < frames && spent < interval) Sleep(interval - spent);
    }
    ReleaseDC(win, window_dc);
    ReleaseDC(desktop_window, desktop_window_dc);
    fclose(csv); ReleaseDC(NULL, screen); SelectObject(mem, old);
    DeleteObject(dib); DeleteDC(mem); DestroyWindow(win);
    printf("Done. Frames and manifest: %s\n", out);
    return 0;
}
