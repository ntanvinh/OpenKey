//
//  InputSourceGuard.m
//  VOpenKey
//

#import "InputSourceGuard.h"
#import "SecureInputMonitor.h"
#import "Diagnostics.h"

extern int vLanguage;
extern void RequestNewSession(void);

int vForceABC = 1;

static NSString* const kForceKey = @"ForceABCWhenVietnamese";
static NSString* const kVietnameseIMPrefix = @"com.apple.inputmethod.VietnameseIM";

static NSString* SourceID(TISInputSourceRef source) {
    return source != NULL ? (__bridge NSString*)TISGetInputSourceProperty(source, kTISPropertyInputSourceID) : nil;
}

static BOOL IsKeyboardLayout(TISInputSourceRef source) {
    CFStringRef type = (CFStringRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceType);
    return type != NULL && CFEqual(type, kTISTypeKeyboardLayout);
}

static BOOL IsSelectable(TISInputSourceRef source) {
    CFBooleanRef selectable = (CFBooleanRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable);
    return selectable != NULL && CFBooleanGetValue(selectable);
}

//the source with that identifier, if the user has it enabled; the caller releases it
static TISInputSourceRef CopyEnabledSource(NSString* identifier) {
    NSDictionary* filter = @{(__bridge NSString*)kTISPropertyInputSourceID: identifier};
    CFArrayRef list = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, false); //enabled sources only
    if (list == NULL)
        return NULL;
    TISInputSourceRef found = NULL;
    if (CFArrayGetCount(list) > 0) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, 0);
        if (IsSelectable(source))
            found = (TISInputSourceRef)CFRetain(source);
    }
    CFRelease(list);
    return found;
}

//ABC, else US, else any English-capable keyboard layout that is enabled
static TISInputSourceRef CopyABCSource(void) {
    for (NSString* identifier in @[@"com.apple.keylayout.ABC", @"com.apple.keylayout.US"]) {
        TISInputSourceRef source = CopyEnabledSource(identifier);
        if (source != NULL)
            return source;
    }
    TISInputSourceRef found = NULL;
    CFArrayRef list = TISCreateASCIICapableInputSourceList();
    if (list != NULL) {
        for (CFIndex i = 0; i < CFArrayGetCount(list) && found == NULL; i++) {
            TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
            if (IsKeyboardLayout(source) && IsSelectable(source))
                found = (TISInputSourceRef)CFRetain(source);
        }
        CFRelease(list);
    }
    return found;
}

@implementation InputSourceGuard

+(BOOL)isVietnameseSource:(TISInputSourceRef)source {
    if (source == NULL)
        return NO;
    if ([SourceID(source) hasPrefix:kVietnameseIMPrefix])
        return YES;
    //Only input methods convert what is typed. A plain keyboard layout does not, even one that lists Vietnamese among its
    //languages: Unicode Hex Input lists them all, and macOS' "Vietnamese" layout is a layout of keys with no Telex.
    if (IsKeyboardLayout(source))
        return NO;
    NSArray* languages = (__bridge NSArray*)TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages);
    return [languages containsObject:@"vi"];
}

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kForceKey: @YES}];
}

+(void)start {
    static BOOL started;
    if (started)
        return;
    started = YES;
    [self registerDefaults];
    vForceABC = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kForceKey];

    //macOS tells when the input source changes, from the keyboard menu, a shortcut or another program
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(sourceChanged:)
                                                            name:(__bridge NSString*)kTISNotifySelectedKeyboardInputSourceChanged
                                                          object:nil
                                              suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [self enforce];
}

+(void)sourceChanged:(NSNotification*)notification {
    VOKDiag(@"input", @"input source changed to %@ (VOpenKey AI language %d, forcing ABC: %d)", [VOKDiagnostics currentInputSourceID], vLanguage, vForceABC);
    [self enforce];
}

+(BOOL)enforce {
    if (!vForceABC || vLanguage != 1)
        return NO;
    //macOS' Vietnamese source stands in on purpose while a background app holds secure input
    if ([SecureInputMonitor isFallbackActive])
        return NO;

    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    BOOL vietnamese = [self isVietnameseSource:current];
    NSString* was = SourceID(current);
    if (current != NULL)
        CFRelease(current);
    if (!vietnamese)
        return NO;

    TISInputSourceRef abc = CopyABCSource();
    if (abc == NULL) {
        NSLog(@"macOS types Vietnamese (%@) as well as VOpenKey AI, but no ABC or US layout is enabled to switch to", was);
        return NO;
    }
    OSStatus status = TISSelectInputSource(abc);
    VOKDiag(@"input", @"guard: %@ -> %@ (status %d)", was, SourceID(abc), (int)status);
    if (status == noErr)
        NSLog(@"macOS input source %@ -> %@, so that Vietnamese is not typed twice", was, SourceID(abc));
    else
        NSLog(@"Could not switch the input source to %@ (error %d)", SourceID(abc), (int)status);
    CFRelease(abc);
    if (status == noErr)
        RequestNewSession();
    return status == noErr;
}

@end
