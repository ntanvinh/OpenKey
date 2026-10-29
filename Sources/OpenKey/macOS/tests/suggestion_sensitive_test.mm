//
//  The suggestion bar in a field where a secret is typed: no bar, nothing learned, and normal fields keep working.
//  The real SuggestionController runs with a dictionary folder in a temporary directory (the real learned.txt is never
//  touched), the answer of Accessibility is replaced (SensitiveField, CaretLocator) and the panel never shows.
//

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "SuggestionController.h"
#import "SensitiveField.h"
#import "CaretLocator.h"

static int failures;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); failures++; } } while (0)

static NSURL* dataFolder;
static NSUserDefaults* isolated;
static _Atomic int asked;                       //how often Accessibility was asked whether the field is a secret
static _Atomic SensitiveFieldVerdict verdict = SensitiveFieldNormal;

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void Key(VOKSuggestionKey kind, NSString* word) {
    [SuggestionController keyProcessed:kind word:word raw:word macro:nil];
    Spin(0.06);
}

//letters typed one by one, like the typing engine reports them
static void Type(NSString* word) {
    for (NSUInteger i = 1; i <= word.length; i++)
        Key(VOKSuggestionKeyOther, [word substringToIndex:i]);
}

static NSString* LearnedText(void) {
    NSString* text = [NSString stringWithContentsOfURL:[dataFolder URLByAppendingPathComponent:@"learned.txt"] encoding:NSUTF8StringEncoding error:nil];
    return text ?: @"";
}

int main(void) {
    @autoreleasepool {
        NSString* suite = [@"vopenkey.test.sensitive." stringByAppendingString:NSUUID.UUID.UUIDString];
        isolated = [[NSUserDefaults alloc] initWithSuiteName:suite];
        method_setImplementation(class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults)),
                                 imp_implementationWithBlock(^id(id self) { return isolated; }));
        [NSApplication sharedApplication];

        dataFolder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSURL* dictionaries = [dataFolder URLByAppendingPathComponent:@"Dictionaries" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:dictionaries withIntermediateDirectories:YES attributes:nil error:nil];
        [@"xin\t100\nxinh\t30\nxin chào\t50\nxin lỗi\t20\n" writeToURL:[dictionaries URLByAppendingPathComponent:@"test.txt"] atomically:YES
                                                                  encoding:NSUTF8StringEncoding error:nil];

        //nothing outside this test is touched or shown
        method_setImplementation(class_getInstanceMethod(SuggestionController.class, NSSelectorFromString(@"dataFolder")),
                                 imp_implementationWithBlock(^NSURL*(id self) { return dataFolder; }));
        Class panel = NSClassFromString(@"SuggestionPanel");
        method_setImplementation(class_getInstanceMethod(panel, @selector(showBelowRect:)), imp_implementationWithBlock(^void(id self, NSRect r) {}));
        method_setImplementation(class_getInstanceMethod(panel, @selector(showNearPoint:)), imp_implementationWithBlock(^void(id self, NSPoint p) {}));
        method_setImplementation(class_getClassMethod(CaretLocator.class, @selector(locateInProcess:word:)),
                                 imp_implementationWithBlock(^CaretLocation*(id self, pid_t pid, NSString* word) { return [[CaretLocation alloc] init]; }));
        method_setImplementation(class_getClassMethod(SensitiveField.class, @selector(verdictForFocusedFieldInProcess:)),
                                 imp_implementationWithBlock(^SensitiveFieldVerdict(id self, pid_t pid) { asked++; return verdict; }));

        [SuggestionController registerDefaults];
        [isolated setInteger:1 forKey:@"SuggestionEnabled"];
        [isolated setBool:NO forKey:@"SuggestionAppExclusionsEnabled"]; //whatever application the owner is in, it counts
        [SuggestionController start];

        //an ordinary field: the bar shows, and the Accessibility question is asked once per word, not once per key
        verdict = SensitiveFieldNormal;
        asked = 0;
        Type(@"xin");
        CHECK([SuggestionController isShowing], "ordinary field: the bar shows");
        CHECK(asked == 1, "the field is asked about once for the word, not once per key");
        Key(VOKSuggestionKeySpace, @"");
        Type(@"xin");
        CHECK(asked == 2, "the next word asks again: the field may have changed (Tab, a click)");
        Key(VOKSuggestionKeySpace, @"");
        [SuggestionController stop];
        CHECK([LearnedText() containsString:@"xin"], "ordinary field: the word is learned");

        //a field the application describes as a secret: no bar, nothing learned
        [SuggestionController forgetLearnedWords];
        verdict = SensitiveFieldSensitive;
        Key(VOKSuggestionKeyOther, @""); //Tab into the password field
        Type(@"xin");
        CHECK(![SuggestionController isShowing], "password field: no bar");
        Key(VOKSuggestionKeySpace, @"");
        Type(@"xinh");
        Key(VOKSuggestionKeySpace, @"");
        [SuggestionController stop];
        CHECK(![LearnedText() containsString:@"xin"], "password field: nothing is learned");

        //Tab from the password field back to an ordinary one: the bar works again
        [SuggestionController forgetLearnedWords];
        verdict = SensitiveFieldNormal;
        Key(VOKSuggestionKeyOther, @"");
        Type(@"xin");
        CHECK([SuggestionController isShowing], "back in an ordinary field: the bar shows again");

        //Tab from an ordinary field, where the bar is up, to a password field: the bar goes at once and stays away
        verdict = SensitiveFieldSensitive;
        Key(VOKSuggestionKeyOther, @"");
        CHECK(![SuggestionController isShowing], "Tab put the bar of the field before away");
        Type(@"xi");
        CHECK(![SuggestionController isShowing], "the password field does not get the bar");

        //an application that does not answer is not a reason to stop helping
        [SuggestionController reset];
        verdict = SensitiveFieldUnknown;
        Key(VOKSuggestionKeyOther, @"");
        Type(@"xi");
        CHECK([SuggestionController isShowing], "no answer from the application: the bar shows");

        [SuggestionController reset];
        [[NSFileManager defaultManager] removeItemAtURL:dataFolder error:nil];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:suite];
        printf(failures == 0 ? "suggestion_sensitive_test: all checks passed\n" : "suggestion_sensitive_test: %d FAILED\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
