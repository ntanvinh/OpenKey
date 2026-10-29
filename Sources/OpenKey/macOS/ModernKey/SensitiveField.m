//
//  SensitiveField.m
//  VOpenKey
//

#import "SensitiveField.h"
#import "CaretLocator.h"

//The names that say a field holds a secret. Written without accents and in lower case: the text of the field is folded the same way.
//These are long enough not to be part of other words, so they count anywhere in the text (so "loginPassword" and "matkhau" do too).
static NSArray<NSString*>* SecretWords(void) {
    return @[@"password", @"passwd", @"passcode", @"passphrase", @"passwort", @"mot de passe", @"contrasena",
             @"mat khau", @"matkhau", @"mat ma", @"пароль", @"密码", @"密碼", @"パスワード", @"비밀번호"];
}

//These are short or common words ("pin" is in "spinning", "secret" in "secretary"): only as whole words.
static NSRegularExpression* SecretPhrases(void) {
    static NSRegularExpression* expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
                      @"\\b(pin|otp|cvv|cvc|2fa|secret|ma xac thuc|ma xac minh|ma bao mat|security code|verification code|one[- ]time code)\\b"
                                                               options:0 error:nil];
    });
    return expression;
}

//An application may answer with a whole paragraph (the description of a text editor): the name of a field is at the start
static const NSUInteger kMaxLength = 160;

//lower case, no accents (also when they come as separate marks), Vietnamese đ as d
static NSString* Fold(NSString* text) {
    if (text.length > kMaxLength)
        text = [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:kMaxLength - 1].location];
    NSString* folded = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch locale:nil];
    return [folded stringByReplacingOccurrencesOfString:@"đ" withString:@"d"];
}

static BOOL NamesASecret(NSString* text) {
    NSString* folded = Fold(text);
    for (NSString* word in SecretWords()) {
        if ([folded containsString:word])
            return YES;
    }
    return [SecretPhrases() firstMatchInString:folded options:0 range:NSMakeRange(0, folded.length)] != nil;
}

static NSString* StringAttribute(AXUIElementRef element, NSString* attribute, AXError* error) {
    CFTypeRef value = NULL;
    AXError result = AXUIElementCopyAttributeValue(element, (__bridge CFStringRef)attribute, &value);
    if (error != NULL)
        *error = result;
    NSString* text = nil;
    if (result == kAXErrorSuccess && value != NULL && CFGetTypeID(value) == CFStringGetTypeID())
        text = [(__bridge NSString*)value copy];
    if (value != NULL)
        CFRelease(value);
    return text;
}

@implementation SensitiveField

+(BOOL)attributesDescribeSecret:(NSDictionary<NSString*, NSString*>*)attributes {
    //the operating system's own word for it
    if ([attributes[@"AXSubrole"] isEqualToString:@"AXSecureTextField"] || [attributes[@"AXRole"] isEqualToString:@"AXSecureTextField"] ||
        [attributes[@"AXRoleDescription"] localizedCaseInsensitiveContainsString:@"secure text field"])
        return YES;
    //the names a page or an application gives the field
    for (NSString* name in @[@"AXPlaceholderValue", @"AXTitle", @"AXDescription", @"AXHelp", @"AXIdentifier", @"AXDOMIdentifier", @"AXLabel"]) {
        NSString* text = attributes[name];
        if (text.length > 0 && NamesASecret(text))
            return YES;
    }
    return NO;
}

+(SensitiveFieldVerdict)verdictForElement:(AXUIElementRef)element {
    if (element == NULL)
        return SensitiveFieldUnknown;

    //if the application does not even tell what the element is, asking for the rest would only wait for time-outs
    AXError error = kAXErrorSuccess;
    NSString* role = StringAttribute(element, @"AXRole", &error);
    if (role == nil)
        return SensitiveFieldUnknown;

    NSMutableDictionary<NSString*, NSString*>* attributes = [NSMutableDictionary dictionaryWithObject:role forKey:@"AXRole"];
    for (NSString* name in @[@"AXSubrole", @"AXRoleDescription", @"AXPlaceholderValue", @"AXTitle", @"AXDescription", @"AXHelp",
                             @"AXIdentifier", @"AXDOMIdentifier"]) {
        NSString* text = StringAttribute(element, name, &error);
        if (text.length > 0)
            attributes[name] = text;
    }

    //the label the field points to (<label for=...> in a web page)
    CFTypeRef label = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute, &label) == kAXErrorSuccess && label != NULL) {
        if (CFGetTypeID(label) == AXUIElementGetTypeID()) {
            NSString* text = StringAttribute((AXUIElementRef)label, @"AXValue", &error) ?: StringAttribute((AXUIElementRef)label, @"AXTitle", &error);
            if (text.length > 0)
                attributes[@"AXLabel"] = text;
        }
        CFRelease(label);
    }
    return [self attributesDescribeSecret:attributes] ? SensitiveFieldSensitive : SensitiveFieldNormal;
}

+(SensitiveFieldVerdict)verdictForFocusedFieldInProcess:(pid_t)pid {
    AXUIElementRef focused = [CaretLocator copyFocusedElementInProcess:pid];
    if (focused == NULL)
        return SensitiveFieldUnknown;
    SensitiveFieldVerdict verdict = [self verdictForElement:focused];
    CFRelease(focused);
    return verdict;
}

@end
