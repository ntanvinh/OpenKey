//
//  OpenKeyManager.m
//  OpenKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "OpenKeyManager.h"
#import "AppUpdater.h"
#import "SecureInputMonitor.h"
#import "SuggestionController.h"
#import "InputSourceGuard.h"
#import "Diagnostics.h"
#import "AppInfo.h"

extern void OpenKeyInit(void);

extern CGEventRef OpenKeyCallback(CGEventTapProxy proxy,
                                  CGEventType type,
                                  CGEventRef event,
                                  void *refcon);

extern NSString* ConvertUtil(NSString* str);

extern CGEventSourceRef myEventSource; //the source of every key event the typing makes, OpenKey.mm

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

    //the log first: it has to be on before the first key is handled
    [VOKDiagnostics start];
    [VOKDiagnostics setTapEnabledCheck:^NSInteger{
        return eventTap == NULL ? -1 : (CGEventTapIsEnabled(eventTap) ? 1 : 0);
    }];
    
    // Create an event tap. We are interested in key presses.
    eventMask = ((1 << kCGEventKeyDown) |
                 (1 << kCGEventKeyUp) |
                 (1 << kCGEventFlagsChanged) |
                 (1 << kCGEventLeftMouseDown) |
                 (1 << kCGEventLeftMouseUp) |
                 (1 << kCGEventScrollWheel) |
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
    VOKDiag(@"tap", @"event tap made and enabled");
    //what the typing posts should come out at the end of the event chain, the log counts how much of it does
    if (myEventSource != NULL)
        [VOKDiagnostics watchDeliveryFromSource:CGEventSourceGetSourceStateID(myEventSource)];
    
    // macOS hides keys from event taps while secure input is on, see SecureInputMonitor
    [SecureInputMonitor start];

    //suggestion bar: dictionaries, learned words
    [SuggestionController start];

    //macOS' own Vietnamese input source would convert every letter a second time
    [InputSourceGuard start];

    return YES;
}

+(void)reenableEventTap {
    VOKDiag(@"tap", @"event tap switched on again (it was off: %d)", eventTap && !CGEventTapIsEnabled(eventTap));
    if (eventTap)
        CGEventTapEnable(eventTap, true);
}

+(BOOL)stopEventTap {
    if (_isInited) { //release all object
        VOKDiag(@"tap", @"event tap stopped");
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

#pragma mark - Updates

//The state of an update is AppUpdater's; here is what the user is told and asked. Looking for a new version, downloading it and
//installing it are the same steps whether they were asked for or are automatic.

static const NSTimeInterval kUpdateCheckInterval = 6 * 3600;    //while the app stays open for days
static const NSTimeInterval kUpdateRetryInterval = 10 * 60;     //the Mac has not got its network yet when the app starts at login
static NSTimer* sUpdateTimer;
static NSString* sOfferedVersion;                               //the version that the user was already told about, in this run

+(void)startAutomaticUpdates {
    [AppUpdater registerDefaults];
    AppUpdater* updater = [AppUpdater shared];
    NSString* failure = [updater takeLastInstallFailure];
    if (failure != nil)
        [self showMessage:nil message:@"Chưa cập nhật được VOpenKey AI" subMsg:failure];
    [updater loadReadyUpdate:^{
        if ([[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"])
            return;
        //an update that was downloaded and not installed (the user said later) is installed now that the app starts: nothing is
        //being typed. Once: if it did not work, the user is asked instead of the app restarting forever.
        if (updater.state == AppUpdaterStateReady && [AppUpdater automaticInstallEnabled] && !updater.readyUpdateWasTried &&
            [self installReadyUpdateAndQuit:nil showErrors:NO])
            return;
        [self scheduleUpdateCheck:0];
    }];
}

+(void)scheduleUpdateCheck:(NSTimeInterval)delay {
    [sUpdateTimer invalidate];
    sUpdateTimer = [NSTimer timerWithTimeInterval:MAX(delay, 1) target:self selector:@selector(updateTimerFired:) userInfo:nil repeats:NO];
    sUpdateTimer.tolerance = MIN(60, delay / 10);
    [[NSRunLoop mainRunLoop] addTimer:sUpdateTimer forMode:NSRunLoopCommonModes];
}

+(void)updateTimerFired:(NSTimer*)timer {
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"])
        return;                                                     //switched off: it is looked at again when the app starts
    [[AppUpdater shared] checkForUpdate:^(AppUpdateRelease* release, NSError* error) {
        [self scheduleUpdateCheck:error != nil ? kUpdateRetryInterval : kUpdateCheckInterval];
        if (release != nil)
            [self handleFoundRelease:release];
    }];
}

//A check nobody asked for found a newer version: download it quietly, or say that it is there.
+(void)handleFoundRelease:(AppUpdateRelease*)release {
    AppUpdater* updater = [AppUpdater shared];
    BOOL automatic = [AppUpdater automaticInstallEnabled] && updater.reasonCannotInstall == nil;
    if (updater.state == AppUpdaterStateDownloading || [sOfferedVersion isEqualToString:release.version])
        return;
    if (updater.state == AppUpdaterStateReady) {
        sOfferedVersion = release.version;
        [self showRestartMessage:nil];
    } else if (automatic) {
        [updater downloadUpdate:^(NSError* error) {
            if (error == nil && updater.state == AppUpdaterStateReady) {
                sOfferedVersion = release.version;
                [self showRestartMessage:nil];
            }                                                       //a failure is not worth an alert: the next check tries again
        }];
    } else {
        sOfferedVersion = release.version;
        [self showUpdateDialog:nil];
    }
}

+(void)checkNewVersion:(NSWindow*)parent {
    [[AppUpdater shared] checkForUpdate:^(AppUpdateRelease* release, NSError* error) {
        if (error != nil) {
            //the user asked for the check, so say it did not work instead of leaving them waiting
            [self showMessage:parent message:@"Không kiểm tra được phiên bản mới"
                       subMsg:[error.localizedDescription stringByAppendingString:@" Hãy kiểm tra kết nối mạng rồi thử lại."]];
        } else if (release == nil) {
            [self showMessage:parent message:@"Bạn đang dùng phiên bản mới nhất"
                       subMsg:[NSString stringWithFormat:@"%@ %@", VOK_APP_NAME, [AppUpdater shared].currentVersion]];
        } else {
            [self showUpdateDialog:parent];
        }
    }];
}

//Shows an alert as a sheet of the window, or by itself above the other windows when there is none (the app has no window of its own to show)
+(void)present:(NSAlert*)alert parent:(NSWindow*)parent completion:(void (^)(NSModalResponse))completion {
    if (parent == nil) {
        [alert.window makeKeyAndOrderFront:nil];
        [alert.window setLevel:NSStatusWindowLevel];
        NSModalResponse response = [alert runModal];
        if (completion != nil) completion(response);
    } else {
        [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
            if (completion != nil) completion(response);
        }];
    }
}

//What to say about the new version, by how far it has come
+(void)showUpdateDialog:(NSWindow*)parent {
    AppUpdater* updater = [AppUpdater shared];
    AppUpdateRelease* release = updater.availableRelease;
    if (release == nil)
        return;
    if (updater.state == AppUpdaterStateReady) {
        [self showRestartMessage:parent];
        return;
    }
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ có phiên bản mới (%@)", VOK_APP_NAME, release.version];
    if (updater.state == AppUpdaterStateDownloading) {
        alert.informativeText = @"Đang tải bản mới. Khi tải xong, bạn sẽ được hỏi có khởi động lại để cập nhật không.";
        [alert addButtonWithTitle:@"OK"];
        [self present:alert parent:parent completion:nil];
        return;
    }
    NSString* reason = updater.reasonCannotInstall;
    //buttons say what they do, not Yes and No; the one that goes on is the default
    if (reason == nil) {
        alert.informativeText = [NSString stringWithFormat:@"Bạn đang dùng %@. %@ sẽ tải bản mới rồi tự khởi động lại để cập nhật, mất vài giây.",
                                 updater.currentVersion, VOK_APP_NAME];
        [alert addButtonWithTitle:@"Cập nhật"];
    } else {
        alert.informativeText = [NSString stringWithFormat:@"%@\nTrang tải về sẽ mở trong trình duyệt.", reason];
        [alert addButtonWithTitle:@"Tải về"];
    }
    [alert addButtonWithTitle:@"Để sau"].keyEquivalent = @"\033";
    [self present:alert parent:parent completion:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn)
            return;
        if (reason != nil)
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:VOK_RELEASES_URL]];
        else
            [self downloadAndRestart:parent];
    }];
}

//The user said yes: download, and when it is there restart without asking again
+(void)downloadAndRestart:(NSWindow*)parent {
    [[AppUpdater shared] downloadUpdate:^(NSError* error) {
        if (error == nil) {
            [self installReadyUpdateAndQuit:parent showErrors:YES];
        } else if (error.code != AppUpdateErrorCancelled) {
            [self showMessage:parent message:@"Không cập nhật được" subMsg:error.localizedDescription];
        }
    }];
}

+(void)showRestartMessage:(NSWindow*)parent {
    AppUpdateRelease* release = [AppUpdater shared].availableRelease;
    if (release == nil)
        return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ %@ đã sẵn sàng", VOK_APP_NAME, release.version];
    alert.informativeText = @"Khởi động lại để dùng bản mới, mất vài giây. Nếu để sau, bản mới sẽ được cài khi bạn mở lại ứng dụng.";
    [alert addButtonWithTitle:@"Khởi động lại"];
    [alert addButtonWithTitle:@"Để sau"].keyEquivalent = @"\033";
    [self present:alert parent:parent completion:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn)
            [self installReadyUpdateAndQuit:parent showErrors:YES];
    }];
}

+(void)restartToUpdate:(NSWindow*)parent {
    [self installReadyUpdateAndQuit:parent showErrors:YES];
}

//Hands the app over to the helper that replaces it, and quits. NO when the helper could not start.
+(BOOL)installReadyUpdateAndQuit:(NSWindow*)parent showErrors:(BOOL)showErrors {
    NSError* error = nil;
    if ([[AppUpdater shared] installReadyUpdate:&error]) {
        [NSApp terminate:nil];
        return YES;
    }
    if (showErrors)
        [self showMessage:parent message:@"Không cập nhật được" subMsg:error.localizedDescription];
    return NO;
}
@end
