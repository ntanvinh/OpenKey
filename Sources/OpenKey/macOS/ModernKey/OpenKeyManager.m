//
//  OpenKeyManager.m
//  OpenKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "OpenKeyManager.h"
#import "SecureInputMonitor.h"
#import "SuggestionController.h"
#import "AppInfo.h"

extern void OpenKeyInit(void);

extern CGEventRef OpenKeyCallback(CGEventTapProxy proxy,
                                  CGEventType type,
                                  CGEventRef event,
                                  void *refcon);

extern NSString* ConvertUtil(NSString* str);

@interface OpenKeyManager ()

@end

@implementation OpenKeyManager {

}
static BOOL _isInited = NO;

static CFMachPortRef      eventTap;
static CGEventMask        eventMask;
static CFRunLoopSourceRef runLoopSource;

+(BOOL)isInited {
    return _isInited;
}

+(BOOL)initEventTap {
    if (_isInited)
        return true;
    
    //init modernKey
    OpenKeyInit();
    
    // Create an event tap. We are interested in key presses.
    eventMask = ((1 << kCGEventKeyDown) |
                 (1 << kCGEventKeyUp) |
                 (1 << kCGEventFlagsChanged) |
                 (1 << kCGEventLeftMouseDown) |
                 (1 << kCGEventRightMouseDown) |
                 (1 << kCGEventLeftMouseDragged) |
                 (1 << kCGEventRightMouseDragged));
    
    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                0,
                                eventMask,
                                OpenKeyCallback,
                                NULL);
    
    if (!eventTap) {
        
        fprintf(stderr, "failed to create event tap\n");
        return NO;
    }
    
    _isInited = YES;
    
    // Create a run loop source.
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    
    // Add to the current run loop.
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
    // Enable the event tap.
    CGEventTapEnable(eventTap, true);
    
    // macOS hides keys from event taps while secure input is on, see SecureInputMonitor
    [SecureInputMonitor start];

    //suggestion bar: dictionaries, learned words
    [SuggestionController start];

    return YES;
}

+(void)reenableEventTap {
    if (eventTap)
        CGEventTapEnable(eventTap, true);
}

+(BOOL)stopEventTap {
    if (_isInited) { //release all object
        [SecureInputMonitor stop];

        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = nil;
        
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = nil;
        
        _isInited = false;
    }
    return YES;
}

+(NSArray*)getTableCodes {
    return [[NSArray alloc] initWithObjects:
            @"Unicode",
            @"TCVN3 (ABC)",
            @"VNI Windows",
            @"Unicode tổ hợp",
            @"Vietnamese Locale CP 1258", nil];
}

+(NSString*)getBuildDate {
    return [NSString stringWithUTF8String:__DATE__];
}

#pragma mark -Convert feature
+(BOOL)quickConvert {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *htmlString = [pasteboard stringForType:NSPasteboardTypeHTML];
    NSString *rawString = [pasteboard stringForType:NSPasteboardTypeString];
    bool converted = false;
    if (htmlString != nil) {
        htmlString = ConvertUtil(htmlString);
        converted = true;
    }
    if (rawString != nil) {
        rawString = ConvertUtil(rawString);
        converted = true;
    }
    if (converted) {
        [pasteboard clearContents];
        if (htmlString != nil)
            [pasteboard setString:htmlString forType:NSPasteboardTypeHTML];
        if (rawString != nil)
            [pasteboard setString:rawString forType:NSPasteboardTypeString];
        
        return YES;
    }
    return NO;
}

+(void)showMessage:(NSWindow*)window message:(NSString*)msg subMsg:(NSString*)subMsg {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:msg];
    [alert setInformativeText:subMsg];
    [alert addButtonWithTitle:@"OK"];
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        }];
    } else {
        [alert runModal];
    }
}

#pragma mark -AutoUpdate feature

+(void)checkNewVersion:(NSWindow*)parent callbackFunc:(CheckNewVersionCallback) callback {
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:VOK_VERSION_JSON_URL]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:15];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary* latest = nil;
        if (data != nil && ((NSHTTPURLResponse *)response).statusCode == 200) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:[NSDictionary class]])
                latest = [object valueForKey:@"latestVersion"];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (callback != nil) {
                callback();
            }
            if (![latest isKindOfClass:[NSDictionary class]]) {
                //the user asked for the check, so say it did not work instead of leaving them waiting
                if (callback != nil)
                    [self showMessage:parent message:@"Không kiểm tra được phiên bản mới" subMsg:@"Hãy kiểm tra kết nối mạng rồi thử lại."];
                return;
            }
            NSInteger versionCode = [[latest valueForKey:@"versionCode"] integerValue];
            NSInteger currentVersionCode = [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"] integerValue];
            if (versionCode > currentVersionCode || callback != nil) {
                [self showUpdateMessage:parent needUpdating:versionCode > currentVersionCode newVersion:[latest valueForKey:@"versionName"]];
            }
        });
    }] resume];
}

+(void)showUpdateMessage:(NSWindow*)parent needUpdating:(BOOL)needUpdating newVersion:(NSString*)versionString {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:(needUpdating ? [NSString stringWithFormat:@"%@ có phiên bản mới (%@)", VOK_APP_NAME, versionString] : @"Bạn đang dùng phiên bản mới nhất")];
    [alert setInformativeText:(needUpdating ? @"Trang tải về sẽ mở trong trình duyệt." : @"")];
    
    //buttons say what they do, not Yes and No; the one that goes on is the default
    if (!needUpdating) {
        [alert addButtonWithTitle:@"OK"];
    } else {
        [alert addButtonWithTitle:@"Tải về"];
        [alert addButtonWithTitle:@"Để sau"].keyEquivalent = @"\033";
    }
    if (parent == nil) {
        [alert.window makeKeyAndOrderFront:nil];
        [alert.window setLevel:NSStatusWindowLevel];
        NSModalResponse res = [alert runModal];
        if (res == NSAlertFirstButtonReturn && needUpdating) {
            [self openReleasePage];
        }
    } else {
        [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn && needUpdating) {
                [self openReleasePage];
            }
        }];
    }
}

+(void)openReleasePage {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:VOK_RELEASES_URL]];
}
@end
