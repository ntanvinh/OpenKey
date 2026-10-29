//
//  The suggestion bar that was up for the field before must go away when macOS starts hiding the keys (a password field
//  got the keyboard). Seen on 2026-10-29 in the log of the Bravo 10 web app: the bar of the user name field stayed up
//  for 1.9 s over the password field, because nothing told it that typing was no longer seen.
//
//  SecureInputMonitor.m is compiled with IsSecureEventInputEnabled replaced by FakeSecure: no real secure input is used.
//

#import <Cocoa/Cocoa.h>
#import "SecureInputMonitor.h"
#import "SuggestionController.h"
#import "Diagnostics.h"

static BOOL fakeSecure;
Boolean FakeSecure(void) { return fakeSecure; }

int vLanguage = 1;
int vInputType = 0;
int vDiagnostics = 0;
int vUseMacro = 0;
static int newSessions;
void RequestNewSession(void) { newSessions++; }

static int barResets;
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation SuggestionController
+(void)reset { barResets++; }
@end
@implementation VOKDiagnostics
+(void)log:(NSString*)category message:(NSString*)message {}
@end

static int failures;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s (bar resets %d, new sessions %d)\n", m, barResets, newSessions); failures++; } } while (0)

static void Evaluate(void) {
    [SecureInputMonitor performSelector:NSSelectorFromString(@"evaluate")];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        fakeSecure = NO;
        [SecureInputMonitor start];
        Evaluate();
        CHECK(barResets == 0, "nothing changed: the bar is left alone");

        fakeSecure = YES; //a password field got the keyboard
        Evaluate();
        CHECK(newSessions == 1, "the typing engine starts a new word when secure input starts");
        CHECK(barResets == 1, "the suggestion bar is put away when secure input starts");

        Evaluate();
        Evaluate();
        CHECK(barResets == 1, "polling again while secure input stays on does not reset again");

        fakeSecure = NO; //the field lost the keyboard
        Evaluate();
        CHECK(barResets == 2, "the suggestion bar is put away when secure input ends: keys typed meanwhile were never seen");
        CHECK(newSessions == 2, "the typing engine starts a new word when secure input ends");

        [SecureInputMonitor stop];
        printf(failures == 0 ? "secure_input_suggestion_test: all checks passed\n" : "secure_input_suggestion_test: %d FAILED\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
