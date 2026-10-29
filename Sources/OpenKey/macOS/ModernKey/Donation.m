//
//  Donation.m
//  VOpenKey
//

#import "Donation.h"
#import "AppInfo.h"
#import <CoreImage/CoreImage.h>

NSString* const DonationDidChangeNotification = @"DonationDidChangeNotification";

static NSString* const kAcknowledgedKey = @"DonationAcknowledged";

//TLV of the QR payload: two digits of id, two digits of length, the value. nil when the value is not plain ASCII or is too long.
static NSString* Field(NSString* identifier, NSString* value) {
    if (value == nil || value.length > 99)
        return nil;
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if (c < 0x20 || c > 0x7e)
            return nil;
    }
    return [NSString stringWithFormat:@"%@%02lu%@", identifier, (unsigned long)value.length, value];
}

@implementation Donation

+(BOOL)acknowledged {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAcknowledgedKey];
}

+(void)setAcknowledged:(BOOL)acknowledged {
    if (acknowledged == [self acknowledged])
        return;
    [[NSUserDefaults standardUserDefaults] setBool:acknowledged forKey:kAcknowledgedKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:DonationDidChangeNotification object:nil];
}

+(NSString*)checksumOfPayload:(NSString*)payload {
    uint16_t crc = 0xFFFF;
    for (const unsigned char* p = (const unsigned char*)payload.UTF8String; *p != 0; p++) {
        crc ^= (uint16_t)(*p << 8);
        for (int bit = 0; bit < 8; bit++)
            crc = (uint16_t)((crc << 1) ^ ((crc & 0x8000) ? 0x1021 : 0));
    }
    return [NSString stringWithFormat:@"%04X", crc];
}

+(NSString*)qrPayload {
    return [self qrPayloadForBank:VOK_DONATE_BANK_NAME bin:VOK_DONATE_BANK_BIN account:VOK_DONATE_ACCOUNT_NO note:VOK_DONATE_NOTE];
}

+(NSString*)qrPayloadForBank:(NSString*)bank bin:(NSString*)bin account:(NSString*)account note:(NSString*)note {
    //The code carries the NAPAS number of the bank, not its name: when the bank of the settings is not the one this number belongs
    //to, no code is better than a code that sends the money to somebody else.
    if (![bank.lowercaseString isEqualToString:VOK_DONATE_BANK_NAME.lowercaseString] || ![bin isEqualToString:VOK_DONATE_BANK_BIN])
        return nil;
    NSCharacterSet* notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (account.length == 0 || account.length > 19 || [account rangeOfCharacterFromSet:notDigits].location != NSNotFound)
        return nil;
    NSString* reference = Field(@"08", note);
    if (reference == nil)
        return nil;
    //from here on every field is made of constants, of the digits checked above or of the reference, so none of them can fail
    NSString* beneficiary = [Field(@"00", bin) stringByAppendingString:Field(@"01", account)];
    NSString* merchant = [NSString stringWithFormat:@"%@%@%@", Field(@"00", @"A000000727"), Field(@"01", beneficiary), Field(@"02", @"QRIBFTTA")];
    NSString* body = [NSString stringWithFormat:@"%@%@%@%@%@%@",
                      Field(@"00", @"01"),            //version
                      Field(@"01", @"11"),            //a static code: the donor chooses the amount
                      Field(@"38", merchant),         //the transfer through NAPAS, 24/7
                      Field(@"53", @"704"),           //dong
                      Field(@"58", @"VN"),
                      Field(@"62", reference)];       //the note of the transfer
    NSString* withoutChecksum = [body stringByAppendingString:@"6304"];
    return [withoutChecksum stringByAppendingString:[self checksumOfPayload:withoutChecksum]];
}

+(NSImage*)qrImageForPayload:(NSString*)payload side:(CGFloat)side {
    NSData* message = [payload dataUsingEncoding:NSISOLatin1StringEncoding];
    CIFilter* filter = message.length > 0 ? [CIFilter filterWithName:@"CIQRCodeGenerator"] : nil;
    if (filter == nil)
        return nil;
    [filter setValue:message forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage* output = filter.outputImage;
    if (output == nil || output.extent.size.width < 1)
        return nil;
    //one pixel per module, black on white; the image is drawn when it is first shown, so the picture must outlive this method
    CGImageRef created = [[CIContext contextWithOptions:nil] createCGImage:output fromRect:output.extent];
    if (created == NULL)
        return nil;
    id modules = CFBridgingRelease(created);
    NSInteger count = (NSInteger)CGImageGetWidth(created);
    const NSInteger quiet = 4;                                  //the margin the standard asks for, in modules
    NSInteger unit = (NSInteger)floor(side / (count + 2 * quiet));
    if (unit < 1)
        return nil;
    CGFloat total = (CGFloat)(unit * (count + 2 * quiet));
    return [NSImage imageWithSize:NSMakeSize(total, total) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor whiteColor] setFill];
        NSRectFill(rect);
        CGContextRef context = [NSGraphicsContext currentContext].CGContext;
        CGContextSetInterpolationQuality(context, kCGInterpolationNone);     //the edges of the squares stay sharp
        CGContextDrawImage(context, CGRectMake(quiet * unit, quiet * unit, count * unit, count * unit), (__bridge CGImageRef)modules);
        return YES;
    }];
}

@end
