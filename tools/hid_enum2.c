// hid_enum2.c — enumerate like Wine: schedule + runloop + callbacks.
#include <stdio.h>
#include <IOKit/hid/IOHIDManager.h>

static void added(void *ctx, IOReturn r, void *sender, IOHIDDeviceRef d) {
    (void)ctx; (void)r; (void)sender;
    CFStringRef prod = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
    char buf[128] = "?";
    if (prod) CFStringGetCString(prod, buf, sizeof(buf), kCFStringEncodingUTF8);
    long vp = -1, up = -1;
    CFTypeRef o;
    if ((o = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDPrimaryUsagePageKey))) &&
        CFGetTypeID(o) == CFNumberGetTypeID())
        CFNumberGetValue(o, kCFNumberLongType, &vp);
    if ((o = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDPrimaryUsageKey))) &&
        CFGetTypeID(o) == CFNumberGetTypeID())
        CFNumberGetValue(o, kCFNumberLongType, &up);
    printf("HIDENUM: added page=%ld usage=%ld product=%s\n", vp, up, buf);
    fflush(stdout);
}

static void removed(void *ctx, IOReturn r, void *sender, IOHIDDeviceRef d) {
    (void)ctx; (void)r; (void)sender; (void)d;
    printf("HIDENUM: removed\n");
    fflush(stdout);
}

int main(void) {
    setbuf(stdout, NULL);
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, NULL);
    IOHIDManagerRegisterDeviceMatchingCallback(m, added, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(m, removed, NULL);
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    printf("HIDENUM: open, running loop 5s\n");
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 5, FALSE);
    printf("HIDENUM: done\n");
    return 0;
}
