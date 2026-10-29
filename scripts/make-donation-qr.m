// Writes the QR code of the donation (Donation.m, the same code the macOS donate window shows) as a 24-bit BMP with one pixel per
// module and its quiet margin. The Windows donate window has no QR encoder: it shows this picture, enlarged by a whole number.
//
//   scripts/make-donation-qr.sh   (compiles this with Donation.m and writes engine/donation/donation-qr.bmp)
#import <Cocoa/Cocoa.h>
#import "Donation.h"

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: make-donation-qr <file.bmp>\n");
            return 2;
        }
        NSString* payload = [Donation qrPayload];
        if (payload == nil) {
            fprintf(stderr, "no payload: the bank or an account number is not accepted\n");
            return 1;
        }
        //the first side that holds a code with one point per module is the width of the code and of its margin
        NSImage* image = nil;
        for (NSInteger side = 29; side <= 200 && image == nil; side++)
            image = [Donation qrImageForPayload:payload side:side];
        if (image == nil || image.size.width != image.size.height) {
            fprintf(stderr, "no picture\n");
            return 1;
        }
        NSInteger n = (NSInteger)image.size.width;
        NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:n pixelsHigh:n bitsPerSample:8 samplesPerPixel:4
                                                                          hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext setCurrentContext:context];
        context.imageInterpolation = NSImageInterpolationNone;
        [image drawInRect:NSMakeRect(0, 0, n, n)];
        [NSGraphicsContext restoreGraphicsState];

        //a module is black or white: anything else would be a blur that a scanner may not read
        NSInteger rowBytes = ((n * 3) + 3) & ~3;
        NSMutableData* bmp = [NSMutableData dataWithLength:54 + rowBytes * n];
        uint8_t* b = bmp.mutableBytes;
        uint32_t size = (uint32_t)bmp.length, offset = 54, header = 40, pixelBytes = (uint32_t)(rowBytes * n);
        int32_t width = (int32_t)n, height = (int32_t)n;
        uint16_t planes = 1, bits = 24;
        b[0] = 'B'; b[1] = 'M';
        memcpy(b + 2, &size, 4); memcpy(b + 10, &offset, 4); memcpy(b + 14, &header, 4);
        memcpy(b + 18, &width, 4); memcpy(b + 22, &height, 4); memcpy(b + 26, &planes, 2); memcpy(b + 28, &bits, 2);
        memcpy(b + 34, &pixelBytes, 4);
        const uint8_t* pixels = rep.bitmapData;
        for (NSInteger y = 0; y < n; y++) {
            for (NSInteger x = 0; x < n; x++) {
                const uint8_t* p = pixels + y * rep.bytesPerRow + x * 4;
                uint8_t v = p[0] < 128 ? 0 : 255;
                if (p[0] != p[1] || p[1] != p[2] || (p[0] > 8 && p[0] < 247)) {
                    fprintf(stderr, "a module that is not black or white at %ld,%ld\n", (long)x, (long)y);
                    return 1;
                }
                uint8_t* out = b + 54 + (n - 1 - y) * rowBytes + x * 3;      //a BMP is stored from the bottom row up, as blue green red
                out[0] = out[1] = out[2] = v;
            }
        }
        if (![bmp writeToFile:@(argv[1]) atomically:YES]) {
            fprintf(stderr, "cannot write %s\n", argv[1]);
            return 1;
        }
        printf("%ld x %ld pixels, %lu bytes, for %lu characters\n", (long)n, (long)n, (unsigned long)bmp.length, (unsigned long)payload.length);
    }
    return 0;
}
