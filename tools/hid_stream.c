// hid_stream.c — dump live input reports from the Xbox pad for 12s.
#include <stdio.h>
#include <string.h>
#include <IOKit/hid/IOHIDManager.h>

static void report(void *ctx, IOReturn r, void *sender, IOHIDReportType type,
                   uint32_t rid, uint8_t *data, CFIndex len) {
    (void)ctx; (void)r; (void)sender; (void)type;
    printf("HIDREP: id=%u len=%ld ", (unsigned)rid, (long)len);
    for (CFIndex i = 0; i < len && i < 17; i++) printf("%02x", data[i]);
    printf("\n");
    fflush(stdout);
}

static void added(void *ctx, IOReturn r, void *sender, IOHIDDeviceRef d) {
    (void)ctx; (void)r; (void)sender;
    CFStringRef prod = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
    char buf[128] = "?";
    if (prod) CFStringGetCString(prod, buf, sizeof(buf), kCFStringEncodingUTF8);
    if (!strstr(buf, "Xbox")) return;
    printf("HIDREP: watching %s\n", buf);
    if (IOHIDDeviceOpen(d, 0) != kIOReturnSuccess) { printf("HIDREP: open failed\n"); return; }
    uint8_t *b = malloc(128);
    IOHIDDeviceRegisterInputReportCallback(d, b, 128, report, NULL);
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    fflush(stdout);
}

int main(void) {
    setbuf(stdout, NULL);
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, NULL);
    IOHIDManagerRegisterDeviceMatchingCallback(m, added, NULL);
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    printf("HIDREP: move sticks + press bumpers for 18s\n");
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 18, FALSE);
    printf("HIDREP: done\n");
    return 0;
}
