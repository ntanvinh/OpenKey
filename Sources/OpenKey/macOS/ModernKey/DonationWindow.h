//
//  DonationWindow.h
//  VOpenKey
//
//  The "Ủng hộ VOpenKey AI" window, the same screen as the donate screen of VMonitor AI:
//  - "Việt Nam": the VietQR code of the bank account (any amount, typed in the banking app) and the account details, each with a
//    "Sao chép" button. "Quốc tế": the PayPal address, copied or opened in the browser.
//  - "Tôi đã ủng hộ" is the user's own word (nothing is checked): the window thanks them, and the "Ủng hộ" item of the menu goes
//    away. "Bấm nhầm? Hoàn tác" takes it back. The Settings page keeps a way in to this window whatever was said.
//  - Esc closes it. It opens on "Việt Nam" for a Mac whose first language is Vietnamese, on "Quốc tế" otherwise.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, DonationChannel) {
    DonationChannelVietnam,
    DonationChannelInternational
};

@interface DonationWindow : NSObject

/// Opens the window (and makes the application active: a menu bar application is not, and the window would open behind the others).
+(void)show;
+(DonationWindow*)shared;

@property (nonatomic, readonly) NSWindow* window;

#pragma mark For tests

/// Where "Sao chép" puts the text; the general pasteboard unless a test says otherwise (it must not touch the clipboard of the user).
@property (nonatomic, strong) NSPasteboard* pasteboard;
/// What "Mở PayPal" does with the address; it opens the browser unless a test says otherwise.
@property (nonatomic, copy) void (^openURL)(NSURL* url);

/// The most the window may be high, in points, as a low screen would allow (0: what the screen of the window leaves). A test makes it small to see the
/// content scroll.
@property (nonatomic) CGFloat maximumHeightForTesting;
/// What the window shows, inside its scroll view.
@property (nonatomic, readonly) NSView* documentView;

@property (nonatomic, readonly) DonationChannel channel;
@property (nonatomic, readonly) BOOL showingThanks;
@property (nonatomic, readonly) NSSegmentedControl* channelControl;
@property (nonatomic, readonly) NSImageView* qrView;
@property (nonatomic, readonly) NSTextField* noticeLabel;
@property (nonatomic, readonly) NSButton* confirmButton;
@property (nonatomic, readonly) NSButton* undoButton;
@property (nonatomic, readonly) NSButton* payPalButton;
/// The "Sao chép" buttons of the page that is shown, in the order of their rows.
@property (nonatomic, readonly) NSArray<NSButton*>* copyButtons;

-(void)selectChannel:(DonationChannel)channel;
-(void)confirmDonation;
-(void)undoDonation;
-(void)openPayPal;

@end
