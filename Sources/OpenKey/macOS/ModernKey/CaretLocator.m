//
//  CaretLocator.m
//  VOpenKey
//

#import "CaretLocator.h"

@implementation CaretLocation
@end

//Accessibility counts from the top left of the main display, Cocoa from the bottom left
static NSRect CocoaRect(CGRect rect) {
    CGFloat mainHeight = CGDisplayBounds(CGMainDisplayID()).size.height;
    return NSMakeRect(rect.origin.x, mainHeight - rect.origin.y - rect.size.height, rect.size.width, rect.size.height);
}

static BOOL SelectedRange(AXUIElementRef element, CFRange* range) {
    CFTypeRef value = NULL;
    BOOL ok = NO;
    if (AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute, &value) == kAXErrorSuccess && value) {
        ok = AXValueGetValue((AXValueRef)value, (AXValueType)kAXValueTypeCFRange, range);
        CFRelease(value);
    }
    return ok;
}

//the text of a range, nil when the application cannot tell
static NSString* StringForRange(AXUIElementRef element, CFIndex location, CFIndex length) {
    if (location < 0)
        return nil;
    CFRange range = CFRangeMake(location, length);
    AXValueRef rangeValue = AXValueCreate((AXValueType)kAXValueTypeCFRange, &range);
    if (rangeValue == NULL)
        return nil;
    CFTypeRef text = NULL;
    NSString* result = nil;
    if (AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute, rangeValue, &text) == kAXErrorSuccess && text) {
        if (CFGetTypeID(text) == CFStringGetTypeID())
            result = [(__bridge NSString*)text copy];
        CFRelease(text);
    }
    CFRelease(rangeValue);
    return result;
}

//where a range is, NO when the application gives nothing usable (an empty answer, or one at the corner of the screen)
static BOOL BoundsForRange(AXUIElementRef element, CFIndex location, CFIndex length, NSRect* bounds) {
    if (location < 0)
        return NO;
    CFRange range = CFRangeMake(location, length);
    AXValueRef rangeValue = AXValueCreate((AXValueType)kAXValueTypeCFRange, &range);
    if (rangeValue == NULL)
        return NO;
    CFTypeRef value = NULL;
    BOOL ok = NO;
    if (AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute, rangeValue, &value) == kAXErrorSuccess && value) {
        CGRect rect;
        if (AXValueGetValue((AXValueRef)value, (AXValueType)kAXValueTypeCGRect, &rect) &&
            rect.size.height > 0 && !(rect.origin.x == 0 && rect.origin.y == 0)) {
            *bounds = CocoaRect(rect);
            ok = YES;
        }
        CFRelease(value);
    }
    CFRelease(rangeValue);
    return ok;
}

static NSRect FrameOfElement(AXUIElementRef element) {
    CFTypeRef position = NULL, size = NULL;
    NSRect frame = NSZeroRect;
    if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &position) == kAXErrorSuccess && position &&
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &size) == kAXErrorSuccess && size) {
        CGPoint origin;
        CGSize extent;
        if (AXValueGetValue((AXValueRef)position, (AXValueType)kAXValueTypeCGPoint, &origin) &&
            AXValueGetValue((AXValueRef)size, (AXValueType)kAXValueTypeCGSize, &extent) && extent.width > 0 && extent.height > 0)
            frame = CocoaRect(CGRectMake(origin.x, origin.y, extent.width, extent.height));
    }
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    return frame;
}

@implementation CaretLocator

+(CaretLocation*)locateInProcess:(pid_t)pid word:(NSString*)word {
    CaretLocation* none = [[CaretLocation alloc] init];
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (application == NULL)
        return none;
    AXUIElementSetMessagingTimeout(application, 0.25);

    //Chromium and Electron only describe their text fields once asked to
    static NSMutableSet<NSNumber*>* asked;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ asked = [NSMutableSet set]; });
    @synchronized (asked) {
        if (![asked containsObject:@(pid)]) {
            [asked addObject:@(pid)];
            AXUIElementSetAttributeValue(application, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
        }
    }

    CaretLocation* location = none;
    CFTypeRef focused = NULL;
    if (AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess && focused) {
        AXUIElementSetMessagingTimeout((AXUIElementRef)focused, 0.25);
        location = [self locateInElement:(AXUIElementRef)focused word:word retries:6];
        CFRelease(focused);
    }
    CFRelease(application);
    return location;
}

+(CaretLocation*)locateInElement:(AXUIElementRef)element word:(NSString*)word retries:(int)retries {
    CaretLocation* location = [[CaretLocation alloc] init];
    location.field = FrameOfElement(element);
    CFIndex typed = (CFIndex)word.length;
    CFRange caret = CFRangeMake(0, 0);

    for (int attempt = 0; ; attempt++) {
        if (!SelectedRange(element, &caret))
            return location;
        location.canCheckText = NO;
        location.textMatches = NO;
        if (caret.length == 0) {
            //what is before the caret: the word that was typed, or the space after it
            NSString* before = typed > 0 ? StringForRange(element, caret.location - typed, typed)
                                         : StringForRange(element, caret.location - 1, 1);
            if (before != nil) {
                location.canCheckText = YES;
                location.textMatches = typed > 0 ? [before isEqualToString:word]
                                                 : ([before isEqualToString:@" "] || [before isEqualToString:@" "]);
            }
        }
        if (!location.canCheckText || location.textMatches || attempt >= retries)
            break;
        [NSThread sleepForTimeInterval:0.03]; //the application has not caught up with the typing yet
    }

    NSRect bounds;
    if (caret.location >= 1 && BoundsForRange(element, caret.location - 1, 1, &bounds)) {
        location.caret = bounds;
    } else if (BoundsForRange(element, caret.location, 1, &bounds) || BoundsForRange(element, caret.location, 0, &bounds)) {
        location.caret = bounds;
    }
    if (typed > 1 && BoundsForRange(element, caret.location - typed, 1, &bounds))
        location.wordStart = bounds;
    return location;
}

+(NSRect)lineForLocation:(CaretLocation*)location typing:(BOOL)typing {
    NSRect caret = location.caret;
    CGFloat x = typing ? caret.origin.x : NSMaxX(caret); //after the space, the next word starts where the caret is
    NSRect start = location.wordStart;
    //a word that wraps onto the next line starts on the line above: then the bar goes by the line of the caret
    BOOL sameLine = !NSIsEmptyRect(start) && fabs(NSMidY(start) - NSMidY(caret)) < caret.size.height * 0.6;
    if (typing && sameLine)
        x = start.origin.x;
    return NSMakeRect(x, caret.origin.y, 0, caret.size.height);
}

@end
