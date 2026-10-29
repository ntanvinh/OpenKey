//
//  Does the suggestion bar know a secret is being typed? The attribute sets below are what macOS Accessibility really
//  answered for the login page of the Bravo 10 web app (a Chrome app) on 2026-10-29: its password field is an ordinary
//  "text field" for macOS, no AXSecureTextField, only the placeholder tells.
//
//  VOK_PROBE_PID=<pid> additionally asks a real running application (read-only, nothing is typed, nothing is focused):
//    - the field that has the keyboard there (only an active application reports its real field; Chrome says "web area" otherwise),
//    - with VOK_PROBE_PLACEHOLDER=<text>, the field of that application whose placeholder is that text, wherever the focus is.
//

#import <Cocoa/Cocoa.h>
#import "SensitiveField.h"

static int failures;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); failures++; } } while (0)

static BOOL Secret(NSDictionary* attributes) {
    return [SensitiveField attributesDescribeSecret:attributes];
}

static NSDictionary* Field(NSString* placeholder) {
    return @{@"AXRole": @"AXTextField", @"AXRoleDescription": @"text field", @"AXPlaceholderValue": placeholder, @"AXDOMIdentifier": @"input"};
}

static void CheckLabel(NSString* label, BOOL secret) {
    NSString* message = [NSString stringWithFormat:@"placeholder \"%@\" is %@", label, secret ? @"a secret" : @"not a secret"];
    CHECK(Secret(Field(label)) == secret, message.UTF8String);
}

//the first element below `element` that has the given placeholder, looking at most 25 levels deep
static AXUIElementRef FindByPlaceholder(AXUIElementRef element, NSString* placeholder, int depth) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, CFSTR("AXPlaceholderValue"), &value) == kAXErrorSuccess && value != NULL) {
        BOOL found = CFGetTypeID(value) == CFStringGetTypeID() && [(__bridge NSString*)value isEqualToString:placeholder];
        CFRelease(value);
        if (found)
            return (AXUIElementRef)CFRetain(element);
    }
    if (depth >= 25)
        return NULL;
    CFTypeRef children = NULL;
    AXUIElementRef result = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &children) == kAXErrorSuccess && children != NULL) {
        for (id child in (__bridge NSArray*)children) {
            result = FindByPlaceholder((__bridge AXUIElementRef)child, placeholder, depth + 1);
            if (result != NULL)
                break;
        }
        CFRelease(children);
    }
    return result;
}

static const char* Name(SensitiveFieldVerdict verdict) {
    return verdict == SensitiveFieldSensitive ? "SENSITIVE (no suggestions, nothing learned)" : (verdict == SensitiveFieldNormal ? "normal" : "unknown");
}

int main(void) {
    @autoreleasepool {
        //the Bravo 10 login page, as macOS Accessibility describes it
        CHECK(Secret(Field(@"Mật khẩu")), "Bravo 10 password field (only the placeholder says so)");
        CHECK(!Secret(Field(@"Tên người dùng")), "Bravo 10 user name field");

        //the operating system's own word for it
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXSubrole": @"AXSecureTextField"}), "AXSecureTextField subrole");
        CHECK(Secret(@{@"AXRole": @"AXSecureTextField"}), "AXSecureTextField role");
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXRoleDescription": @"secure text field"}), "role description 'secure text field'");

        //names of password fields, in the languages of the users
        for (NSString* label in @[@"Password", @"PASSWORD", @"Enter your password", @"Confirm password:", @"New passwords",
                                  @"Mật khẩu", @"MẬT KHẨU", @"Nhập mật khẩu mới *", @"Mat khau", @"mật mã", @"Passcode", @"Passphrase",
                                  @"Mã PIN", @"PIN", @"OTP", @"Mã OTP", @"Mã xác thực", @"Mã bảo mật", @"CVV", @"Security code",
                                  @"Verification code", @"Secret key"])
            CheckLabel(label, YES);

        //the same name written as separate marks (NFD), which is how some applications return text
        NSString* decomposed = [@"Mật khẩu" decomposedStringWithCanonicalMapping];
        CHECK(![decomposed isEqualToString:@"Mật khẩu"], "the fixture really is decomposed");
        CheckLabel(decomposed, YES);

        //every attribute that names a field counts, not only the placeholder
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXTitle": @"Password"}), "title");
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXDescription": @"Mật khẩu"}), "description");
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXHelp": @"Nhập mật khẩu của bạn"}), "help");
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXDOMIdentifier": @"password"}), "DOM identifier");
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXIdentifier": @"loginPassword"}), "identifier in camel case is not split, but contains the word");
        CHECK(Secret(@{@"AXRole": @"AXTextField", @"AXLabel": @"Mật khẩu"}), "label element the field points to");

        //ordinary fields, and words that only contain the letters of a secret
        for (NSString* label in @[@"Tên người dùng", @"Tên đăng nhập", @"Email", @"Search", @"Tìm kiếm", @"Địa chỉ", @"Message", @"Ghi chú",
                                  @"Bình luận", @"Shipping address", @"Spinning speed", @"Opinion", @"Options", @"Hotpot", @"Passenger name",
                                  @"Tên mật", @"Ngày sinh", @"Số điện thoại", @""])
            CheckLabel(label, NO);
        CHECK(!Secret(@{}), "no attributes");
        CHECK(!Secret(nil), "nil attributes");
        CHECK(!Secret(@{@"AXRole": @"AXTextArea", @"AXDescription": @"Editor content"}), "a code editor");

        //a very long description is not read to the end, and does not make the answer slow
        NSString* longText = [[@"" stringByPaddingToLength:20000 withString:@"lorem ipsum " startingAtIndex:0] stringByAppendingString:@" password"];
        NSDate* start = [NSDate date];
        BOOL longAnswer = Secret(@{@"AXRole": @"AXTextArea", @"AXDescription": longText});
        CHECK(!longAnswer, "a secret far behind a long text is not looked for");
        CHECK(-[start timeIntervalSinceNow] < 0.05, "a long description is answered quickly");

        //unknown answers are not secrets: typing is never blocked by a guess
        CHECK([SensitiveField verdictForFocusedFieldInProcess:getpid()] != SensitiveFieldSensitive, "this process has no secret field");

        const char* probe = getenv("VOK_PROBE_PID");
        if (probe != NULL) {
            pid_t pid = (pid_t)atoi(probe);
            SensitiveFieldVerdict verdict = [SensitiveField verdictForFocusedFieldInProcess:pid];
            printf("LIVE: the field that has the keyboard in pid %s is %s\n", probe, Name(verdict));
            const char* expect = getenv("VOK_PROBE_EXPECT");
            const char* placeholder = getenv("VOK_PROBE_PLACEHOLDER");
            if (placeholder != NULL) {
                AXUIElementRef application = AXUIElementCreateApplication(pid);
                AXUIElementSetMessagingTimeout(application, 1.0);
                AXUIElementRef field = FindByPlaceholder(application, @(placeholder), 0);
                CHECK(field != NULL, "the field with that placeholder is in the application");
                if (field != NULL) {
                    verdict = [SensitiveField verdictForElement:field];
                    printf("LIVE: the field with the placeholder \"%s\" in pid %s is %s\n", placeholder, probe, Name(verdict));
                    CFRelease(field);
                }
                CFRelease(application);
            }
            if (expect != NULL) {
                SensitiveFieldVerdict expected = strcmp(expect, "sensitive") == 0 ? SensitiveFieldSensitive : SensitiveFieldNormal;
                CHECK(verdict == expected, "the live field is classified as expected");
            }
        }

        printf(failures == 0 ? "sensitive_field_test: all checks passed\n" : "sensitive_field_test: %d FAILED\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
