#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach_time.h>
#import <notify.h>
#import <unistd.h>

typedef CFTypeRef IOHIDEventRef;
typedef CFTypeRef IOHIDEventSystemClientRef;
typedef double IOHIDFloat;
typedef uint32_t IOOptionBits;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t transducerType, uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat barrelPressure, Boolean range, Boolean touch, IOOptionBits options);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t index, uint32_t identity, uint32_t eventMask, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat twist, Boolean range, Boolean touch, IOOptionBits options);
extern void IOHIDEventSetSenderID(IOHIDEventRef event, uint64_t senderID);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef event, uint32_t field, int32_t value);
extern void IOHIDEventSetFloatValue(IOHIDEventRef event, uint32_t field, IOHIDFloat value);
extern void IOHIDEventAppendEvent(IOHIDEventRef event, IOHIDEventRef child, IOOptionBits options);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);

static NSString * const kLogPath = @"/var/mobile/Library/Preferences/catmcp-touch-bridge-sb.log";
static NSString * const kCommandPath = @"/var/mobile/Library/Preferences/catmcp-touch-bridge-command.json";
static const char *kSlotNotifyPrefix = "com.ratush.catmcp.touchbridge.slot";
static const int kNotifySlots = 64;
static IOHIDEventSystemClientRef gClient;
static dispatch_queue_t gQueue;
static double gFingerX[20];
static double gFingerY[20];
static BOOL gFingerValid[20];
static int gSlotTokens[64];
static uint8_t gCurrentEpoch;
static uint32_t gExpectedSequence = 1;

static void SBLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *out = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!fh) {
        [@"" writeToFile:kLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    }
    [fh seekToEndOfFile];
    [fh writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static void DispatchPhase(NSInteger finger, double x, double y, NSInteger phase) {
    if (!gClient || finger < 0 || finger >= 20) return;
    uint32_t rangeMask = 1u << 0;
    uint32_t touchMask = 1u << 1;
    uint32_t positionMask = 1u << 2;
    uint32_t mask = touchMask;
    Boolean range = false;
    Boolean touch = false;
    if (phase == 0) {
        mask = rangeMask | touchMask;
        range = true;
        touch = true;
        gFingerX[finger] = x;
        gFingerY[finger] = y;
        gFingerValid[finger] = YES;
    } else if (phase == 1) {
        mask = positionMask;
        range = true;
        touch = true;
        gFingerX[finger] = x;
        gFingerY[finger] = y;
        gFingerValid[finger] = YES;
    } else {
        if (gFingerValid[finger]) {
            x = gFingerX[finger];
            y = gFingerY[finger];
        }
        gFingerValid[finger] = NO;
    }

    uint64_t now = mach_absolute_time();
    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, now, 3, 99, 1, 0, 0, 0, 0, 0, 0, 0, false, false, 0);
    IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, now, (uint32_t)finger + 1, 3, mask, x, y, 0, 0, 0, range, touch, 0);
    if (!parent || !child) {
        if (parent) CFRelease(parent);
        if (child) CFRelease(child);
        SBLog(@"create event failed");
        return;
    }
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04);
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04);
    IOHIDEventAppendEvent(parent, child, 0);
    CFRelease(child);
    IOHIDEventSetIntegerValue(parent, 0xb0019, 1);
    IOHIDEventSetIntegerValue(parent, 0x4, 1);
    IOHIDEventSetIntegerValue(parent, 0xb0007, 0x23);
    IOHIDEventSetIntegerValue(parent, 0xb0008, touch ? 1 : 0);
    IOHIDEventSetIntegerValue(parent, 0xb0009, touch ? 1 : 0);
    IOHIDEventSetSenderID(parent, 0x8000000817319372ULL);
    IOHIDEventSystemClientDispatchEvent(gClient, parent);
    CFRelease(parent);
}

static void ProcessJSONData(NSData *data, NSString *origin) {
    if (!data.length) return;
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<binary>";
        SBLog(@"bad json from %@ len=%lu err=%@ raw=%@", origin, (unsigned long)data.length, error, raw);
        return;
    }
    NSString *action = json[@"action"];
    NSDictionary *body = json[@"body"];
    NSInteger finger = [body[@"finger"] respondsToSelector:@selector(integerValue)] ? [body[@"finger"] integerValue] : 0;
    double x = [body[@"x"] respondsToSelector:@selector(doubleValue)] ? [body[@"x"] doubleValue] : 0.0;
    double y = [body[@"y"] respondsToSelector:@selector(doubleValue)] ? [body[@"y"] doubleValue] : 0.0;
    SBLog(@"command %@ from=%@ finger=%ld x=%.4f y=%.4f", action, origin, (long)finger, x, y);
    if ([action isEqualToString:@"touch/down"]) DispatchPhase(finger, x, y, 0);
    else if ([action isEqualToString:@"touch/move"]) DispatchPhase(finger, x, y, 1);
    else if ([action isEqualToString:@"touch/up"]) DispatchPhase(finger, x, y, 2);
}

static void HandleCommand(void) {
    NSData *data = [NSData dataWithContentsOfFile:kCommandPath];
    ProcessJSONData(data, @"notify-file");
}

typedef struct {
    BOOL valid;
    uint8_t epoch;
    uint8_t action;
    uint8_t finger;
    uint32_t sequence;
    double x;
    double y;
} PendingTouch;

static PendingTouch gPending[64];

static void SlotName(int slot, char *name, size_t size) {
    snprintf(name, size, "%s.%02d", kSlotNotifyPrefix, slot);
}

static void HandlePacked(uint64_t packed) {
    uint8_t action = (uint8_t)(packed & 3ULL);
    uint8_t finger = (uint8_t)((packed >> 2) & 15ULL);
    double x = (double)((packed >> 6) & 0xffffULL) / 65535.0;
    double y = (double)((packed >> 22) & 0xffffULL) / 65535.0;
    uint32_t sequence = (uint32_t)((packed >> 38) & 0x3ffffULL);
    uint8_t epoch = (uint8_t)(packed >> 56);
    if (!epoch || !sequence || action > 2 || finger > 15) return;
    if (epoch != gCurrentEpoch) {
        memset(gPending, 0, sizeof(gPending));
        memset(gFingerValid, 0, sizeof(gFingerValid));
        gCurrentEpoch = epoch;
        gExpectedSequence = 1;
    }
    if (sequence < gExpectedSequence) return;
    PendingTouch *event = &gPending[sequence % (uint32_t)kNotifySlots];
    event->valid = YES;
    event->epoch = epoch;
    event->action = action;
    event->finger = finger;
    event->sequence = sequence;
    event->x = x;
    event->y = y;
    for (;;) {
        PendingTouch *next = &gPending[gExpectedSequence % (uint32_t)kNotifySlots];
        if (!next->valid || next->epoch != gCurrentEpoch || next->sequence != gExpectedSequence) break;
        PendingTouch ready = *next;
        next->valid = NO;
        DispatchPhase(ready.finger, ready.x, ready.y, ready.action);
        gExpectedSequence = (gExpectedSequence % 0x3ffffU) + 1U;
    }
}

__attribute__((constructor))
static void CatMCPSpringBoardTouchBridgeInit(void) {
    @autoreleasepool {
        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
        if (![bid isEqualToString:@"com.apple.springboard"]) return;
        gQueue = dispatch_queue_create("com.ratush.catmcp.touchbridge.sb", DISPATCH_QUEUE_SERIAL);
        gClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        SBLog(@"springboard bridge loaded pid=%d client=%p", getpid(), gClient);
        for (int i = 0; i < kNotifySlots; i++) {
            char name[96];
            SlotName(i, name, sizeof(name));
            notify_register_dispatch(name, &gSlotTokens[i], gQueue, ^(int token) {
                uint64_t packed = 0;
                if (notify_get_state(token, &packed) == NOTIFY_STATUS_OK) HandlePacked(packed);
            });
        }
        SBLog(@"registered %d ordered notify slots", kNotifySlots);
        int token = 0;
        notify_register_dispatch("com.ratush.catmcp.touchbridge.command", &token, gQueue, ^(int t) {
            (void)t;
            HandleCommand();
        });
    }
}
