// gc_poll.m — Apple's GameController interpretation of the pad. No UI needed.
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

int main(void) {
    @autoreleasepool {
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8.0];
        printf("GCPOLL: polling 8s\n");
        fflush(stdout);
        while ([end timeIntervalSinceNow] > 0) {
            for (GCController *c in [GCController controllers]) {
                GCExtendedGamepad *g = c.extendedGamepad;
                if (!g) continue;
                printf("GCPOLL: LX=%.3f LYup+=%.3f RX=%.3f RYup+=%.3f LT=%.3f RT=%.3f A=%d B=%d X=%d Y=%d LB=%d RB=%d menu=%d\n",
                    g.leftThumbstick.xAxis.value, g.leftThumbstick.yAxis.value,
                    g.rightThumbstick.xAxis.value, g.rightThumbstick.yAxis.value,
                    g.leftTrigger.value, g.rightTrigger.value,
                    g.buttonA.pressed, g.buttonB.pressed, g.buttonX.pressed, g.buttonY.pressed,
                    g.leftShoulder.pressed, g.rightShoulder.pressed, g.buttonMenu.pressed);
                fflush(stdout);
            }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        }
        printf("GCPOLL: done\n");
    }
    return 0;
}
