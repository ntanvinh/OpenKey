//
//  Donation.h
//  VOpenKey
//
//  What a donation needs: the VietQR code of the bank account (a static code, the donor types the amount in their banking app) and
//  whether the user said they have donated. Like the donate screen of VMonitor AI, the app never checks a transfer: "Tôi đã ủng hộ"
//  is the user's own word, and it only hides the donate item of the menu.
//

#import <Cocoa/Cocoa.h>

/// Posted when the user confirms a donation or takes the confirmation back.
extern NSString* const DonationDidChangeNotification;

@interface Donation : NSObject

/// The user's confirmation that they donated. Stored in the defaults of the app; the "Khôi phục mặc định" button does not touch it.
@property (class, nonatomic) BOOL acknowledged;

/// The text inside the QR code for VOK_DONATE_ACCOUNT_NO and VOK_DONATE_NOTE (EMVCo / VietQR, no amount), nil when it cannot be made
/// (the bank is not the one VOK_DONATE_BANK_BIN belongs to, a field is not plain ASCII or is too long).
+(NSString*)qrPayload;
+(NSString*)qrPayloadForBank:(NSString*)bank bin:(NSString*)bin account:(NSString*)account note:(NSString*)note;

/// CRC-16/CCITT-FALSE of the text, as the four capital hex digits that end a QR payload (it covers the "6304" before them).
+(NSString*)checksumOfPayload:(NSString*)payload;

/// The QR code as a picture, black on white with its quiet margin, at most `side` points wide and made of whole points per module so
/// that the edges stay sharp. nil when the code cannot be made.
+(NSImage*)qrImageForPayload:(NSString*)payload side:(CGFloat)side;

@end
