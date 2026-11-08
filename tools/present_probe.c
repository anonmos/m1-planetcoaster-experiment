#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#include <dxgi.h>
#include <d3d11.h>

static const GUID MY_IID_IDXGIFactory1 = {
    0x770aae78, 0xf26f, 0x4dba, {0xa8, 0x29, 0x25, 0x3b, 0x9e, 0xb8, 0x92, 0x92}};
static const GUID MY_IID_ID3D11Device = {
    0xdb6f6ddb, 0xac77, 0x4e88, {0x82, 0x53, 0x81, 0x9d, 0xf2, 0xbc, 0xd1, 0x38}};

static const GUID MY_IID_IDXGIDevice =
    {0x54ec77b1, 0xe9b9, 0x4a68, {0xaa, 0x46, 0xcd, 0x4d, 0xe8, 0xb0, 0xd9, 0x92}};
static const GUID MY_IID_ID3D11Texture2D =
    {0x6f15aaf2, 0xd208, 0x4e89, {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};
static const char *CLASS_NAME = "PresentProbe";

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(h, m, w, l);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("PRESENT: registering window class\n");
    WNDCLASSEXA wc = {0};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = CLASS_NAME;
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)32512);
    if (!RegisterClassExA(&wc)) { printf("PRESENT: RegisterClassEx FAILED err=%lu\n", (unsigned long)GetLastError()); return 1; }

    printf("PRESENT: creating window 800x600\n");
    HWND hwnd = CreateWindowExA(0, CLASS_NAME, "D3D11 Present Test",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 800, 600,
        NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { printf("PRESENT: CreateWindowEx FAILED err=%lu\n", (unsigned long)GetLastError()); return 1; }
    printf("PRESENT: window hwnd=%p\n", (void *)hwnd);

    printf("PRESENT: CreateDXGIFactory1\n");
    IDXGIFactory1 *factory = NULL;
    HRESULT hr = CreateDXGIFactory1(&MY_IID_IDXGIFactory1, (void **)&factory);
    printf("PRESENT: factory hr=0x%08lx factory=%p\n", (long)hr, (void *)factory);
    if (FAILED(hr)) return 1;

    printf("PRESENT: D3D11CreateDevice (default adapter, FL 11_0)\n");
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL obtained = 0;
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
        D3D11_SDK_VERSION, &dev, &obtained, &ctx);
    printf("PRESENT: device hr=0x%08lx dev=%p fl=0x%x\n", (long)hr, (void *)dev, (unsigned)obtained);
    if (FAILED(hr) || !dev) return 1;

    printf("PRESENT: creating swapchain for hwnd\n");
    IDXGIDevice *dxgiDev = NULL;
    hr = ID3D11Device_QueryInterface(dev, &MY_IID_IDXGIDevice, (void **)&dxgiDev);
    printf("PRESENT: QI IDXGIDevice hr=0x%08lx\n", (long)hr);
    if (FAILED(hr)) return 1;
    IDXGIAdapter *adapter = NULL;
    hr = IDXGIDevice_GetAdapter(dxgiDev, &adapter);
    printf("PRESENT: GetAdapter hr=0x%08lx\n", (long)hr);
    if (FAILED(hr)) return 1;
    IDXGIFactory *dxgiFactory = NULL;
    hr = IDXGIAdapter_GetParent(adapter, &MY_IID_IDXGIFactory1, (void **)&dxgiFactory);
    printf("PRESENT: GetParent(factory) hr=0x%08lx\n", (long)hr);
    if (FAILED(hr)) return 1;

    DXGI_SWAP_CHAIN_DESC scd = {0};
    scd.BufferCount = 2;
    scd.BufferDesc.Width = 800;
    scd.BufferDesc.Height = 600;
    scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scd.OutputWindow = hwnd;
    scd.SampleDesc.Count = 1;
    scd.Windowed = TRUE;
    scd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    IDXGISwapChain *sc = NULL;
    hr = IDXGIFactory_CreateSwapChain(dxgiFactory, (IUnknown *)dev, &scd, &sc);
    printf("PRESENT: CreateSwapChain hr=0x%08lx sc=%p\n", (long)hr, (void *)sc);
    if (FAILED(hr) || !sc) return 1;

    printf("PRESENT: getting backbuffer + RTV\n");
    ID3D11Texture2D *bb = NULL;
    hr = IDXGISwapChain_GetBuffer(sc, 0, &MY_IID_ID3D11Texture2D, (void **)&bb);
    printf("PRESENT: GetBuffer hr=0x%08lx\n", (long)hr);
    if (FAILED(hr)) return 1;
    ID3D11RenderTargetView *rtv = NULL;
    hr = ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);
    printf("PRESENT: CreateRTV hr=0x%08lx\n", (long)hr);
    if (FAILED(hr)) return 1;

    printf("PRESENT: entering 600-frame present loop (watch the window cycle colors)\n");
    for (int i = 0; i < 600; i++) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) { printf("PRESENT: quit requested\n"); goto done; }
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        float t = (float)(i % 300) / 300.0f;
        float clear[4] = {t, 0.2f, 1.0f - t, 1.0f};
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
        hr = IDXGISwapChain_Present(sc, 1, 0);
        if (FAILED(hr)) { printf("PRESENT: Present FAILED at frame %d hr=0x%08lx\n", i, (long)hr); return 1; }
        if ((i % 60) == 0) printf("PRESENT: frame %d ok\n", i);
    }
done:
    printf("PRESENT: SUCCESS - presented 600 frames\n");
    return 0;
}
