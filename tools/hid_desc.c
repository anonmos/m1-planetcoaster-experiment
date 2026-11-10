// hid_desc.c — dump the Xbox pad report descriptor bytes.
#include <stdio.h>
#include <string.h>
#include <IOKit/hid/IOHIDManager.h>

static void added(void *ctx, IOReturn r, void *sender, IOHIDDeviceRef d) {
    (void)ctx; (void)r; (void)sender;
    CFStringRef prod = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
    char buf[128] = "?";
    if (prod) CFStringGetCString(prod, buf, sizeof(buf), kCFStringEncodingUTF8);
    if (!strstr(buf, "Xbox")) return;
    CFDataRef rd = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDReportDescriptorKey));
    if (!rd) { printf("HIDDESC: no descriptor\n"); return; }
    CFIndex n = CFDataGetLength(rd);
    const uint8_t *b = CFDataGetBytePtr(rd);
    printf("HIDDESC: len=%ld\n", (long)n);
    for (CFIndex i = 0; i < n; i++) {
        printf("%02x", b[i]);
        if ((i + 1) % 32 == 0) printf("\n");
    }
    printf("\nHIDDESC: done\n");
    fflush(stdout);
}

int main(void) {
    setbuf(stdout, NULL);
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, NULL);
    IOHIDManagerRegisterDeviceMatchingCallback(m, added, NULL);
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 4, FALSE);
    return 0;
}
