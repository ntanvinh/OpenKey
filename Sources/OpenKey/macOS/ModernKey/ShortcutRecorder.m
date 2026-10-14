//
//  ShortcutRecorder.m
//  VOpenKey
//

#import "ShortcutRecorder.h"
#import <Carbon/Carbon.h>

int vRecordingShortcut = 0;

static const NSEventModifierFlags kModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption |
                                                  NSEventModifierFlagCommand | NSEventModifierFlagShift;
static const int kBeepBit = 0x8000;
static const unsigned short kNoKey = 0xFE;

static const CGFloat kHeight = 22;
static const CGFloat kWidth = 168;
static const CGFloat kClearSize = 16;
static const CGFloat kCornerRadius = 6;

#pragma mark - Reading and showing a shortcut

static int BitsOfModifiers(NSEventModifierFlags flags) {
    int bits = 0;
    if (flags & NSEventModifierFlagControl) bits |= 0x100;
    if (flags & NSEventModifierFlagOption)  bits |= 0x200;
    if (flags & NSEventModifierFlagCommand) bits |= 0x400;
    if (flags & NSEventModifierFlagShift)   bits |= 0x800;
    return bits;
}

static int CountBits(int bits) {
    int count = 0;
    for (int mask = 0x100; mask <= 0x800; mask <<= 1)
        if (bits & mask) count++;
    return count;
}

//in the order macOS writes them
static NSString* GlyphsOfBits(int bits) {
    NSMutableString* glyphs = [NSMutableString string];
    if (bits & 0x100) [glyphs appendString:@"⌃"];
    if (bits & 0x200) [glyphs appendString:@"⌥"];
    if (bits & 0x800) [glyphs appendString:@"⇧"];
    if (bits & 0x400) [glyphs appendString:@"⌘"];
    return glyphs;
}

BOOL VOKShortcutIsEmpty(int data) {
    return (data & ~kBeepBit) == (int)VOK_SHORTCUT_NONE;
}

BOOL VOKShortcutsEqual(int a, int b) {
    if (VOKShortcutIsEmpty(a) || VOKShortcutIsEmpty(b))
        return NO;
    return ((a ^ b) & 0xFFF) == 0; //modifiers and key
}

//what a key is called when it is written out; keys that print a character are written as that character
static NSString* NameOfSpecialKey(unsigned short code) {
    static NSDictionary<NSNumber*, NSString*>* names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{@(kVK_Space): @"Space", @(kVK_Return): @"↩", @(kVK_ANSI_KeypadEnter): @"⌅", @(kVK_Tab): @"⇥",
                  @(kVK_Delete): @"⌫", @(kVK_ForwardDelete): @"⌦", @(kVK_Escape): @"⎋",
                  @(kVK_LeftArrow): @"←", @(kVK_RightArrow): @"→", @(kVK_UpArrow): @"↑", @(kVK_DownArrow): @"↓",
                  @(kVK_Home): @"↖", @(kVK_End): @"↘", @(kVK_PageUp): @"⇞", @(kVK_PageDown): @"⇟",
                  @(kVK_F1): @"F1", @(kVK_F2): @"F2", @(kVK_F3): @"F3", @(kVK_F4): @"F4", @(kVK_F5): @"F5",
                  @(kVK_F6): @"F6", @(kVK_F7): @"F7", @(kVK_F8): @"F8", @(kVK_F9): @"F9", @(kVK_F10): @"F10",
                  @(kVK_F11): @"F11", @(kVK_F12): @"F12", @(kVK_F13): @"F13", @(kVK_F14): @"F14", @(kVK_F15): @"F15",
                  @(kVK_F16): @"F16", @(kVK_F17): @"F17", @(kVK_F18): @"F18", @(kVK_F19): @"F19", @(kVK_F20): @"F20"};
    });
    return names[@(code)];
}

//the character of the keys of an American keyboard, by key code, for when the stored character is not usable
static NSString* AnsiCharacter(unsigned short code) {
    static const char* const table[] = {
        "a", "s", "d", "f", "h", "g", "z", "x", "c", "v", "", "b", "q", "w", "e", "r", "y", "t", "1", "2", "3", "4", "6",
        "5", "=", "9", "7", "-", "8", "0", "]", "o", "u", "[", "i", "p", "", "l", "j", "'", "k", ";", "\\", ",", "/",
        "n", "m", ".", "", "", "`"};
    if (code >= sizeof(table) / sizeof(table[0]))
        return @"";
    return [NSString stringWithUTF8String:table[code]];
}

static BOOL IsPrintable(unsigned short character) {
    return character > 0x20 && character < 0x7F;
}

//the text of the key: from the character that was stored with it, or from its place on the keyboard
static NSString* KeyText(unsigned short code, unsigned short character) {
    NSString* special = NameOfSpecialKey(code);
    if (special != nil)
        return special;
    if (IsPrintable(character))
        return [[NSString stringWithFormat:@"%c", character] uppercaseString];
    NSString* ansi = AnsiCharacter(code);
    return ansi.length > 0 ? ansi.uppercaseString : [NSString stringWithFormat:@"Phím %d", code];
}

NSString* VOKShortcutDescription(int data) {
    if (VOKShortcutIsEmpty(data))
        return nil;
    unsigned short code = data & 0xFF;
    unsigned short character = ((unsigned)data >> 24) & 0xFF;
    NSString* glyphs = GlyphsOfBits(data & 0xF00);
    if (code == kNoKey)
        return glyphs.length > 0 ? glyphs : nil;
    NSString* key = KeyText(code, character);
    //a word next to symbols needs a little air, a single character does not
    return glyphs.length > 0 && key.length > 1 ? [NSString stringWithFormat:@"%@ %@", glyphs, key]
                                               : [glyphs stringByAppendingString:key];
}

NSString* VOKShortcutKeyEquivalent(int data) {
    if (VOKShortcutIsEmpty(data))
        return @"";
    unsigned short code = data & 0xFF;
    unsigned short character = ((unsigned)data >> 24) & 0xFF;
    if (code == kNoKey)
        return @"";
    if (code == kVK_Space)
        return @" ";
    if (NameOfSpecialKey(code) != nil)
        return @"";
    if (IsPrintable(character))
        return [[NSString stringWithFormat:@"%c", character] lowercaseString];
    return AnsiCharacter(code);
}

NSEventModifierFlags VOKShortcutModifierMask(int data) {
    NSEventModifierFlags flags = 0;
    if (data & 0x100) flags |= NSEventModifierFlagControl;
    if (data & 0x200) flags |= NSEventModifierFlagOption;
    if (data & 0x400) flags |= NSEventModifierFlagCommand;
    if (data & 0x800) flags |= NSEventModifierFlagShift;
    return flags;
}

#pragma mark - The field

@implementation ShortcutRecorder {
    BOOL _recording;
    int _held;              //modifiers held right now, as bits
    BOOL _keyPressed;       //a key was pressed during this chord of modifiers
    NSString* _message;     //why the last attempt was refused, shown for a moment
}

-(instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)];
    if (self) {
        _value = VOK_SHORTCUT_NONE;
        _placeholder = @"Ghi phím tắt";
        self.focusRingType = NSFocusRingTypeDefault;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.widthAnchor constraintEqualToConstant:kWidth].active = YES;
        [self.heightAnchor constraintEqualToConstant:kHeight].active = YES;
    }
    return self;
}

-(void)dealloc {
    if (_recording)
        vRecordingShortcut = 0;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSSize)intrinsicContentSize {
    return NSMakeSize(kWidth, kHeight);
}

-(BOOL)acceptsFirstResponder {
    return self.enabled;
}

-(BOOL)isFlipped {
    return YES;
}

-(void)setValue:(int)value {
    _value = value;
    self.needsDisplay = YES;
    [self setAccessibilityValue:VOKShortcutDescription(value) ?: @"Chưa có"];
}

-(void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    if (!enabled)
        [self cancelRecording];
    self.needsDisplay = YES;
}

#pragma mark Recording

-(void)beginRecording {
    if (_recording || !self.enabled)
        return;
    [self.window makeFirstResponder:self];
    _recording = YES;
    _held = 0;
    _keyPressed = NO;
    _message = nil;
    vRecordingShortcut = 1;
    //leaving the application, or its window, ends it: nothing may keep the event tap from working
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelRecording)
                                                 name:NSApplicationDidResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelRecording)
                                                 name:NSWindowDidResignKeyNotification object:self.window];
    self.needsDisplay = YES;
    NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey: @"Nhấn phím tắt mới, Esc để hủy, Xóa để bỏ phím tắt"});
}

-(void)endRecording {
    if (!_recording)
        return;
    _recording = NO;
    vRecordingShortcut = 0;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.needsDisplay = YES;
}

-(void)cancelRecording {
    [self endRecording];
}

-(BOOL)resignFirstResponder {
    [self cancelRecording];
    self.needsDisplay = YES;
    return [super resignFirstResponder];
}

-(BOOL)becomeFirstResponder {
    self.needsDisplay = YES;
    return [super becomeFirstResponder];
}

-(void)viewWillMoveToWindow:(NSWindow*)newWindow {
    if (newWindow == nil)
        [self cancelRecording];
    [super viewWillMoveToWindow:newWindow];
}

-(void)refuse:(NSString*)message {
    _message = message;
    self.needsDisplay = YES;
    NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityAnnouncementRequestedNotification,
                                                @{NSAccessibilityAnnouncementKey: message});
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(forgetMessage) object:nil];
    [self performSelector:@selector(forgetMessage) withObject:nil afterDelay:2.5];
}

-(void)forgetMessage {
    _message = nil;
    self.needsDisplay = YES;
}

-(void)commit:(int)bits key:(unsigned short)key character:(unsigned short)character {
    int data = (int)(((unsigned)character << 24) | (unsigned)(_value & kBeepBit) | (unsigned)bits | key);
    if (self.conflict != nil) {
        NSString* user = self.conflict(data);
        if (user != nil) {
            [self refuse:[NSString stringWithFormat:@"Đã dùng cho %@", user]];
            return;
        }
    }
    [self endRecording];
    [self setValue:data];
    if (self.onChange != nil)
        self.onChange(data);
}

-(void)clear {
    [self endRecording];
    int data = (int)((unsigned)VOK_SHORTCUT_NONE | (unsigned)(_value & kBeepBit));
    [self setValue:data];
    if (self.onChange != nil)
        self.onChange(data);
}

//a key pressed while recording
-(void)recordKeyDown:(NSEvent*)event {
    unsigned short code = event.keyCode;
    int bits = BitsOfModifiers(event.modifierFlags & kModifierMask);
    if (bits == 0 && code == kVK_Escape) {
        [self cancelRecording];
        return;
    }
    if (bits == 0 && (code == kVK_Delete || code == kVK_ForwardDelete)) {
        [self clear];
        return;
    }
    if (bits == 0) {
        [self refuse:@"Giữ một phím ⌃ ⌥ ⌘ ⇧ rồi bấm phím"];
        return;
    }
    _keyPressed = YES;
    NSString* typed = [event.charactersIgnoringModifiers lowercaseString];
    unsigned short character = kNoKey;
    if (code == kVK_Space) {
        character = 0x20;
    } else if (NameOfSpecialKey(code) == nil) {
        unichar first = typed.length > 0 ? [typed characterAtIndex:0] : 0;
        character = IsPrintable(first) ? first : (unsigned short)[AnsiCharacter(code) UTF8String][0];
        if (character == 0)
            character = kNoKey;
    }
    [self commit:bits key:code character:character];
}

//modifiers pressed or released while recording. Pressing some and letting go of them together, with no key in between,
//is a shortcut of its own: ⌃⇧.
-(void)recordFlagsChanged:(NSEvent*)event {
    int bits = BitsOfModifiers(event.modifierFlags & kModifierMask);
    BOOL released = bits != _held && (bits & ~_held) == 0;
    if (released && !_keyPressed && _held != 0) {
        int chord = _held;
        _held = bits;
        if (CountBits(chord) < 2) {
            [self refuse:@"Bấm hai phím ⌃ ⌥ ⌘ ⇧ cùng lúc, hoặc thêm một phím"];
            return;
        }
        [self commit:chord key:kNoKey character:kNoKey];
        return;
    }
    if (bits == 0)
        _keyPressed = NO;
    if (bits != 0)
        _message = nil;
    _held = bits;
    self.needsDisplay = YES;
}

-(void)keyDown:(NSEvent*)event {
    if (_recording) {
        [self recordKeyDown:event];
        return;
    }
    if (event.keyCode == kVK_Space || event.keyCode == kVK_Return) { //from the keyboard: as a click
        [self beginRecording];
        return;
    }
    [super keyDown:event];
}

-(void)flagsChanged:(NSEvent*)event {
    if (_recording)
        [self recordFlagsChanged:event];
    else
        [super flagsChanged:event];
}

//⌘ shortcuts arrive here before the menus and the window see them
-(BOOL)performKeyEquivalent:(NSEvent*)event {
    if (!_recording)
        return NO;
    [self recordKeyDown:event];
    return YES;
}

-(void)cancelOperation:(id)sender {
    [self cancelRecording];
}

#pragma mark Mouse

-(NSRect)clearRect {
    return NSMakeRect(NSWidth(self.bounds) - kClearSize - 4, (kHeight - kClearSize) / 2, kClearSize, kClearSize);
}

-(BOOL)acceptsFirstMouse:(NSEvent*)event {
    return YES;
}

-(void)mouseDown:(NSEvent*)event {
    if (!self.enabled)
        return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_recording) {
        [self cancelRecording];
    } else if (!VOKShortcutIsEmpty(_value) && NSPointInRect(point, [self clearRect])) {
        [self clear];
    } else {
        [self beginRecording];
    }
}

#pragma mark Drawing

-(NSString*)text {
    if (_message != nil)
        return _message;
    if (_recording) {
        NSString* glyphs = GlyphsOfBits(_held);
        return glyphs.length > 0 ? glyphs : @"Nhấn phím tắt…";
    }
    return VOKShortcutDescription(_value) ?: _placeholder;
}

-(NSColor*)textColor {
    if (!self.enabled)
        return [NSColor disabledControlTextColor];
    if (_message != nil)
        return [NSColor systemRedColor];
    if (_recording && _held == 0)
        return [NSColor secondaryLabelColor];
    if (!_recording && VOKShortcutIsEmpty(_value))
        return [NSColor secondaryLabelColor];
    return [NSColor labelColor];
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:kCornerRadius yRadius:kCornerRadius];
    [(_recording ? [NSColor textBackgroundColor] : [NSColor quaternarySystemFillColor]) setFill];
    [shape fill];
    if (_recording) {
        [[NSColor controlAccentColor] setStroke];
        shape.lineWidth = 2;
    } else {
        [[NSColor separatorColor] setStroke];
        shape.lineWidth = 0.5;
    }
    [shape stroke];

    BOOL showsClear = !_recording && self.enabled && !VOKShortcutIsEmpty(_value);
    NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary* attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:(_message != nil ? 11 : 13)],
                                 NSForegroundColorAttributeName: [self textColor],
                                 NSParagraphStyleAttributeName: style};
    NSString* text = [self text];
    CGFloat inset = showsClear ? kClearSize + 8 : 8;
    NSSize size = [text sizeWithAttributes:attributes];
    NSRect textRect = NSMakeRect(inset, (kHeight - size.height) / 2, NSWidth(self.bounds) - 2 * inset, size.height);
    [text drawInRect:textRect withAttributes:attributes];

    if (showsClear) {
        NSImage* clear = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Bỏ phím tắt"];
        clear = [clear imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular]];
        NSRect rect = [self clearRect];
        NSSize imageSize = clear.size;
        NSRect target = NSMakeRect(NSMidX(rect) - imageSize.width / 2, NSMidY(rect) - imageSize.height / 2, imageSize.width, imageSize.height);
        [clear drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        //the symbol is a template: tint it
        [[NSColor tertiaryLabelColor] set];
        NSRectFillUsingOperation(target, NSCompositingOperationSourceAtop);
    }
}

-(void)drawFocusRingMask {
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:kCornerRadius yRadius:kCornerRadius] fill];
}

-(NSRect)focusRingMaskBounds {
    return self.bounds;
}

-(void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

#pragma mark Accessibility

-(BOOL)isAccessibilityElement {
    return YES;
}

-(NSAccessibilityRole)accessibilityRole {
    return NSAccessibilityButtonRole;
}

-(NSString*)accessibilityLabel {
    return @"Phím tắt";
}

-(NSString*)accessibilityValue {
    return VOKShortcutDescription(_value) ?: @"Chưa có";
}

-(BOOL)accessibilityPerformPress {
    [self beginRecording];
    return YES;
}

@end
