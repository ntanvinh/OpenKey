//
//  SensitiveField.h
//  VOpenKey
//
//  Is the text field that has the keyboard one where a secret is typed (a password, a PIN, a one-time code)?
//  macOS already hides the keys of a real password field from every event tap (secure input, see SecureInputMonitor),
//  but not every field that holds a secret is protected that way: a password that was made visible, a field the
//  application draws itself, a field that macOS Accessibility describes as an ordinary text field. The suggestion bar
//  must not show what is typed into such a field, nor learn it. This asks the application through Accessibility.
//

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

typedef NS_ENUM(NSInteger, SensitiveFieldVerdict) {
    SensitiveFieldNormal,    //an ordinary text field
    SensitiveFieldSensitive, //a secret is typed here: no suggestions, nothing learned
    SensitiveFieldUnknown    //the application does not tell (no focused field, no answer in time): treated as normal
};

@interface SensitiveField : NSObject

/// The answers of an element's Accessibility attributes, keyed by attribute name ("AXRole", "AXSubrole",
/// "AXRoleDescription", "AXPlaceholderValue", "AXTitle", "AXDescription", "AXHelp", "AXIdentifier", "AXDOMIdentifier" and
/// "AXLabel" for the text of the label the field points to). Missing attributes are simply absent.
/// YES when they say the field holds a secret: a secure text field, or a name such as "Password", "Mật khẩu" or "OTP".
+(BOOL)attributesDescribeSecret:(NSDictionary<NSString*, NSString*>*)attributes;

/// The same, asking the element. Takes a moment when the application is slow: call it off the main thread.
+(SensitiveFieldVerdict)verdictForElement:(AXUIElementRef)element;

/// The same for the field that has the keyboard in an application. Off the main thread, like the above.
+(SensitiveFieldVerdict)verdictForFocusedFieldInProcess:(pid_t)pid;

@end
