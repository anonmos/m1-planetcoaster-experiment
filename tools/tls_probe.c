#include <windows.h>
#include <winhttp.h>
#include <stdio.h>

static void report_error(const char *where) {
    fprintf(stderr, "%s failed: Win32 error %lu\n", where, (unsigned long)GetLastError());
}

int main(void) {
    HINTERNET session = NULL, connection = NULL, request = NULL;
    DWORD status = 0, status_size = sizeof(status);
    const wchar_t *host = L"www.cloudflare.com";

    session = WinHttpOpen(L"GPTK-TLS-Probe/1.0",
                          WINHTTP_ACCESS_TYPE_NO_PROXY,
                          WINHTTP_NO_PROXY_NAME,
                          WINHTTP_NO_PROXY_BYPASS,
                          0);
    if (!session) { report_error("WinHttpOpen"); return 1; }
    if (!WinHttpSetTimeouts(session, 5000, 5000, 10000, 10000)) {
        report_error("WinHttpSetTimeouts"); return 7;
    }

    connection = WinHttpConnect(session, host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!connection) { report_error("WinHttpConnect"); return 2; }

    request = WinHttpOpenRequest(connection, L"GET", L"/",
                                 NULL, WINHTTP_NO_REFERER,
                                 WINHTTP_DEFAULT_ACCEPT_TYPES,
                                 WINHTTP_FLAG_SECURE);
    if (!request) { report_error("WinHttpOpenRequest"); return 3; }

    if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
        report_error("WinHttpSendRequest"); return 4;
    }
    if (!WinHttpReceiveResponse(request, NULL)) {
        report_error("WinHttpReceiveResponse"); return 5;
    }
    if (!WinHttpQueryHeaders(request,
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX,
                             &status, &status_size,
                             WINHTTP_NO_HEADER_INDEX)) {
        report_error("WinHttpQueryHeaders"); return 6;
    }

    printf("TLS probe succeeded; HTTPS status: %lu\n", (unsigned long)status);
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return 0;
}
