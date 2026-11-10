// hid_enum.c — list IOHIDManager devices the way Wine's winebus sees them.
#include <stdio.h>
#include <IOKit/hid/IOHIDManager.h>

static long numProp(IOHIDDeviceRef d, CFStringRef k) {
    long v = -1;
    CFTypeRef o = IOHIDDeviceGetProperty(d, k);
    if (o && CFGetTypeID(o) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)o, kCFNumberLongType, &v);
    return v;
}

int main(void) {
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
    CFSetRef devs = IOHIDManagerCopyDevices(m);
    CFIndex n = devs ? CFSetGetCount(devs) : 0;
    printf("HIDENUM: %ld devices\n", (long)n);
    if (devs) {
        const void **vals = malloc(sizeof(void *) * (n ? n : 1));
        CFSetGetValues(devs, vals);
        for (CFIndex i = 0; i < n; i++) {
            IOHIDDeviceRef d = (IOHIDDeviceRef)vals[i];
            CFStringRef prod = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
            char buf[128] = "?";
            if (prod) CFStringGetCString(prod, buf, sizeof(buf), kCFStringEncodingUTF8);
            printf("HIDENUM: vid=%04lx pid=%04lx page=%ld usage=%ld product=%s\n",
                numProp(d, CFSTR(kIOHIDVendorIDKey)), numProp(d, CFSTR(kIOHIDProductIDKey)),
                numProp(d, CFSTR(kIOHIDPrimaryUsagePageKey)), numProp(d, CFSTR(kIOHIDPrimaryUsageKey)), buf);
        }
        free(vals);
    }
    return 0;
}
