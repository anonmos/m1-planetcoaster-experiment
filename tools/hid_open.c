// hid_open.c — replicate Wine bus_iohid checks: open + conform + descriptor.
#include <stdio.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>

static void added(void *ctx, IOReturn r, void *sender, IOHIDDeviceRef d) {
    (void)ctx; (void)r; (void)sender;
    CFStringRef prod = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
    char buf[128] = "?";
    if (prod) CFStringGetCString(prod, buf, sizeof(buf), kCFStringEncodingUTF8);
    if (!strstr(buf, "Xbox") && !strstr(buf, "GamePad") && !strstr(buf, "Controller")) return;
    printf("HIDOPEN: candidate product=%s\n", buf);
    IOReturn oret = IOHIDDeviceOpen(d, 0);
    printf("HIDOPEN: open(0) => 0x%x\n", (unsigned)oret);
    if (oret != kIOReturnSuccess) return;
    printf("HIDOPEN: conforms GamePad=%d Joystick=%d\n",
        IOHIDDeviceConformsTo(d, kHIDPage_GenericDesktop, kHIDUsage_GD_GamePad),
        IOHIDDeviceConformsTo(d, kHIDPage_GenericDesktop, kHIDUsage_GD_Joystick));
    CFDataRef rdesc = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDReportDescriptorKey));
    printf("HIDOPEN: report descriptor len=%ld\n",
        (long)(rdesc ? CFDataGetLength(rdesc) : -1));
    uint8_t rep[64] = {0};
    CFIndex replen = sizeof(rep);
    IOReturn rret = IOHIDDeviceGetReport(d, kIOHIDReportTypeInput, 0, rep, &replen);
    printf("HIDOPEN: getReport => 0x%x len=%ld b0=%02x b1=%02x\n",
        (unsigned)rret, (long)replen, rep[0], rep[1]);
    IOHIDDeviceClose(d, 0);
    printf("HIDOPEN: closed\n");
    fflush(stdout);
}

int main(void) {
    setbuf(stdout, NULL);
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, NULL);
    IOHIDManagerRegisterDeviceMatchingCallback(m, added, NULL);
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    printf("HIDOPEN: open, loop 6s\n");
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 6, FALSE);
    printf("HIDOPEN: done\n");
    return 0;
}
