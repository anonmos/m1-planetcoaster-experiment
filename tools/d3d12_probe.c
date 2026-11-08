#define COBJMACROS
#include <stdio.h>
#include <dxgi1_6.h>
#include <d3d12.h>

static const GUID MY_IID_IDXGIFactory4 =
    {0x1bc6ea02, 0xef36, 0x464f, {0xbf, 0x0c, 0xf4, 0x5a, 0xd6, 0x84, 0xa8, 0xe9}};
static const GUID MY_IID_ID3D12Device =
    {0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x62, 0xb8, 0x5f, 0x9d}};

int main(void) {
    HRESULT hr;
    IDXGIFactory4 *factory = NULL;
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("PROBE: calling CreateDXGIFactory2\n");
    hr = CreateDXGIFactory2(0, &MY_IID_IDXGIFactory4, (void **)&factory);
    printf("PROBE: CreateDXGIFactory2 hr=0x%08lx factory=%p\n", (long)hr, (void *)factory);
    if (FAILED(hr)) return 1;
    for (int i = 0; i < 4; i++) {
        IDXGIAdapter1 *a = NULL;
        hr = IDXGIFactory4_EnumAdapters1(factory, i, &a);
        printf("PROBE: EnumAdapters1(%d) hr=0x%08lx adapter=%p\n", i, (long)hr, (void *)a);
        if (FAILED(hr)) break;
        DXGI_ADAPTER_DESC1 desc;
        hr = IDXGIAdapter1_GetDesc1(a, &desc);
        printf("PROBE: adapter %d desc hr=0x%08lx vendor=0x%x device=0x%x flags=0x%x\n",
               i, (long)hr, desc.VendorId, desc.DeviceId, desc.Flags);
        ID3D12Device *dev = NULL;
        printf("PROBE: calling D3D12CreateDevice on adapter %d\n", i);
        hr = D3D12CreateDevice((IUnknown *)a, D3D_FEATURE_LEVEL_11_0, &MY_IID_ID3D12Device, (void **)&dev);
        printf("PROBE: D3D12CreateDevice hr=0x%08lx dev=%p\n", (long)hr, (void *)dev);
        if (SUCCEEDED(hr)) {
            printf("PROBE: SUCCESS\n");
            ID3D12Device_Release(dev);
            IDXGIAdapter1_Release(a);
            break;
        }
        IDXGIAdapter1_Release(a);
    }
    IDXGIFactory4_Release(factory);
    printf("PROBE: done\n");
    return 0;
}
