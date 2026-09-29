#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <stdio.h>

int main(void) {
    HRESULT hr;
    IMMDeviceEnumerator *penum = NULL;
    IMMDevice *dev = NULL;
    IAudioClient *client = NULL;
    IAudioCaptureClient *cap = NULL;
    WAVEFORMATEX *mix = NULL;
    LPWSTR id = NULL;
    IPropertyStore *props = NULL;
    PROPVARIANT name;

    CoInitializeEx(NULL, COINIT_MULTITHREADED);

    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                          &IID_IMMDeviceEnumerator, (void **)&penum);
    if (FAILED(hr)) { printf("CoCreateInstance enumerator: 0x%08lx\n", hr); return 10; }

    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(penum, eRender, eConsole, &dev);
    if (FAILED(hr)) { printf("GetDefaultAudioEndpoint: 0x%08lx\n", hr); return 11; }

    if (SUCCEEDED(IMMDevice_GetId(dev, &id))) { printf("endpoint: %ls\n", id); CoTaskMemFree(id); }
    if (SUCCEEDED(IMMDevice_OpenPropertyStore(dev, STGM_READ, &props))) {
        PropVariantInit(&name);
        if (SUCCEEDED(IPropertyStore_GetValue(props, &PKEY_Device_FriendlyName, &name)))
            printf("friendly: %ls\n", name.pwszVal ? name.pwszVal : L"(null)");
        PropVariantClear(&name);
        IPropertyStore_Release(props);
    }

    hr = IMMDevice_Activate(dev, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client);
    if (FAILED(hr)) { printf("Activate IAudioClient: 0x%08lx\n", hr); return 12; }

    hr = IAudioClient_GetMixFormat(client, &mix);
    if (FAILED(hr)) { printf("GetMixFormat: 0x%08lx\n", hr); return 13; }
    printf("mix: %lu ch x %lu Hz x %u bits tag %u\n",
           (unsigned long)mix->nChannels, (unsigned long)mix->nSamplesPerSec,
           mix->wBitsPerSample, mix->wFormatTag);

    hr = IAudioClient_Initialize(client, AUDCLNT_SHAREMODE_SHARED,
                                 AUDCLNT_STREAMFLAGS_LOOPBACK,
                                 10000000, 0, mix, NULL);
    printf("loopback Initialize: 0x%08lx\n", hr);
    if (FAILED(hr)) { CoTaskMemFree(mix); return 1; }

    {
        UINT32 bufsize = 0;
        REFERENCE_TIME def = 0, minp = 0;
        if (SUCCEEDED(IAudioClient_GetBufferSize(client, &bufsize)))
            printf("buffer size: %lu frames (%.1f ms)\n", (unsigned long)bufsize,
                   bufsize * 1000.0 / mix->nSamplesPerSec);
        if (SUCCEEDED(IAudioClient_GetDevicePeriod(client, &def, &minp)))
            printf("device period: def %lld min %lld (100ns)\n", def, minp);
    }

    hr = IAudioClient_GetService(client, &IID_IAudioCaptureClient, (void **)&cap);
    if (FAILED(hr)) { printf("GetService capture: 0x%08lx\n", hr); return 14; }
    hr = IAudioClient_Start(client);
    if (FAILED(hr)) { printf("Start: 0x%08lx\n", hr); return 15; }

    {
        UINT64 total = 0, nonsilent = 0, packets = 0, i;
        UINT64 empties = 0, lastprint = 0;
        float peak = 0.0f;
        UINT64 lastpos = 0;
        int pprinted = 0;
        DWORD t0 = GetTickCount();
        while (GetTickCount() - t0 < 3000) {
            UINT32 n = 0;
            int drained = 0;
            /* Drain everything currently available, then wait one period:
               mimics a sane WASAPI client instead of a spin loop. */
            for (;;) {
                BYTE *buf = NULL;
                UINT32 frames = 0;
                DWORD flags = 0;
                UINT64 pos = 0, pcpos = 0;
                if (FAILED(IAudioCaptureClient_GetNextPacketSize(cap, &n))) break;
                if (!n) break;
                if (FAILED(IAudioCaptureClient_GetBuffer(cap, &buf, &frames, &flags, &pos, &pcpos))) break;
                drained = 1;
            packets++;
            if (pprinted < 40) {
                long long d = packets == 1 ? 0 : (long long)pos - (long long)lastpos;
                printf("pkt %llu frames %lu devpos %llu delta %+lld flags %lu\n",
                       packets, (unsigned long)frames, pos, d, (unsigned long)flags);
                pprinted++;
            }
            lastpos = pos;
            {
                float *s = (float *)buf;
                UINT64 count = (UINT64)frames * mix->nChannels;
                for (i = 0; i < count; i++) {
                    float v = s[i] < 0 ? -s[i] : s[i];
                    if (v > peak) peak = v;
                    if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && v > 0.000001f) nonsilent++;
                }
                total += count;
            }
            IAudioCaptureClient_ReleaseBuffer(cap, frames);
            }
            if (!drained) empties++;
            /* True ~30ms cadence: Wine Sleep undersleeps, so spin on the
               tick count to emulate a gulpy WASAPI client. */
            {
                DWORD w = GetTickCount();
                while (GetTickCount() - w < 30) Sleep(1);
            }
        }
        printf("capture: %llu packets, %llu samples, nonsilent %llu, peak %f\n",
               packets, total, nonsilent, peak);
        printf("empty polls (starved): %llu\n", empties);
    }

    CoTaskMemFree(mix);
    return 0;
}
