//
//  AppPermissions.m
//  VOpenKey
//

#import "AppPermissions.h"
#import <ApplicationServices/ApplicationServices.h>

static void OpenPrivacyPane(NSString* pane) {
    NSString* url = [NSString stringWithFormat:@"x-apple.systempreferences:com.apple.preference.security?%@", pane];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

@implementation AppPermissions

+(BOOL)accessibilityGranted {
    return AXIsProcessTrusted();
}

+(BOOL)inputMonitoringGranted {
    return CGPreflightListenEventAccess();
}

+(BOOL)allGranted {
    return [self accessibilityGranted] && [self inputMonitoringGranted];
}

+(void)requestAccessibility {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @YES});
    [self openAccessibilitySettings];
}

+(void)requestInputMonitoring {
    CGRequestListenEventAccess();
    [self openInputMonitoringSettings];
}

+(void)openAccessibilitySettings {
    OpenPrivacyPane(@"Privacy_Accessibility");
}

+(void)openInputMonitoringSettings {
    OpenPrivacyPane(@"Privacy_ListenEvent");
}

@end
