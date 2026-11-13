// steamwebhelper-shim.c — Steam CEF renderer flag injector (Wine/macOS black-window fix).
//
// Background: steam.exe filters most -cef-* flags instead of forwarding them to
// steamwebhelper.exe, and the stock multi-process CEF present path paints black
// under Wine (cross-process swapchain/GDI present is lost; verified black with
// stock helper on client build 1794424036, Nov 2026). The Aug-2026 working setup
// ran the helper as steamwebhelper_real.exe with "--disable-gpu --single-process"
// first on its command line; the Nov-12 client update replaced the shim that did
// that with a stock binary and the black window returned.
//
// Install: this file is built with mingw and installed AS steamwebhelper.exe,
// with Valve's genuine binary moved to steamwebhelper_real.exe beside it (see
// scripts/install-webhelper-shim.zsh; re-run after every Steam client update).
// It prepends "--disable-gpu --single-process" to every invocation (browser and
// --type=* children alike, matching the Aug-2026 working command lines) and
// waits on the child so steam.exe's process tracking keeps working.
#include <windows.h>
#include <stdio.h>
#include <string.h>

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow) {
  (void)hInst; (void)hPrev; (void)lpCmd; (void)nShow;
  char self[MAX_PATH], real[MAX_PATH], *s;

  if (!GetModuleFileNameA(NULL, self, sizeof(self))) return 1;
  strncpy(real, self, sizeof(real) - 1);
  real[sizeof(real) - 1] = '\0';
  s = strrchr(real, '\\');
  if (!s) s = strrchr(real, '/');
  if (!s) return 1;
  strcpy(s + 1, "steamwebhelper_real.exe");

  // Take our own command line verbatim minus argv[0] to preserve quoting.
  const char *cmd = GetCommandLineA();
  if (cmd[0] == '"') {
    cmd = strchr(cmd + 1, '"');
    if (!cmd) return 1;
    cmd++;
  } else {
    while (*cmd && *cmd != ' ' && *cmd != '\t') cmd++;
  }
  while (*cmd == ' ' || *cmd == '\t') cmd++;

  static char child[MAX_PATH * 2 + 32768];
  _snprintf(child, sizeof(child) - 1, "\"%s\" --disable-gpu --single-process %s",
            real, cmd);
  child[sizeof(child) - 1] = '\0';

  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  ZeroMemory(&pi, sizeof(pi));
  if (!CreateProcessA(NULL, child, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
    return 1;
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return (int)code;
}
