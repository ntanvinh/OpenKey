//
//  dictionary_speech_test.m
//  VOpenKey
//
//  The dictionary window of the Mac, without any network:
//   - the edge of the window is a hairline of the system separator, in light and in dark (it was a white line of 55% in dark,
//     a black one in light, because -colorWithAlphaComponent: replaces the alpha of a system colour instead of multiplying it);
//   - the speaker button and ⌘P read an English headword aloud, and only that: not "ba" of a Vietnamese-English dictionary, not an
//     accented word, not an empty state. Nothing is played: WordSpeaker.speakHook takes the place of the voice.
//
//  Usage: dictionary_speech_test <catalog.json> <en-vi.zip> <vi-en.zip> <work-dir> [snapshot-dir]
//  The catalog lists "en-vi-test" (English) and "vi-en-test" (Vietnamese); both are made "installed" from the two zips by writing
//  the state file and the compiled files, so that nothing is downloaded.
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "DictionaryService.h"
#import "DictionaryPalette.h"
#import "WordSpeaker.h"

static int gFailures = 0;
#define CHECK(cond, fmt, ...) do { \
    if (!(cond)) { \
        printf("FAIL line %d: " fmt "\n", __LINE__, ##__VA_ARGS__); \
        gFailures++; \
    } \
} while (0)

static void Spin(NSTimeInterval seconds) {
    NSDate* limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

static BOOL WaitUntil(NSTimeInterval timeout, BOOL (^pred)(void)) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([deadline timeIntervalSinceNow] > 0) {
        if (pred()) return YES;
        Spin(0.03);
    }
    return pred();
}

static NSEvent* KeyEvent(NSWindow* win, NSString* ch, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:win.windowNumber context:nil characters:ch charactersIgnoringModifiers:ch
                           isARepeat:NO keyCode:code];
}

//the window drawn into a bitmap, as the other tests do (the blur and the rim of the window server are not in it; what is drawn by
//this program, the edge included, is)
static NSBitmapImageRep* Render(NSWindow* window, NSAppearanceName appearance, NSString* pngPath) {
    window.appearance = [NSAppearance appearanceNamed:appearance];
    Spin(0.15);
    NSView* view = window.contentView;
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep* rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    }];
    if (pngPath.length > 0)
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:pngPath atomically:NO];
    window.appearance = nil;
    return rep;
}

static int Grey(NSBitmapImageRep* rep, NSInteger x, NSInteger y) {
    unsigned char* p = rep.bitmapData + y * rep.bytesPerRow + x * (rep.bitsPerPixel / 8);
    return (p[0] + p[1] + p[2]) / 3;
}

//how much the outermost pixel of each of the four sides differs from the fill 4 pixels in: the weight of the edge
static int EdgeContrast(NSBitmapImageRep* rep) {
    NSInteger w = rep.pixelsWide, h = rep.pixelsHigh;
    int worst = 0;
    int samples[4][2][2] = {
        {{(int)w / 2, 0}, {(int)w / 2, 4}},                      //top
        {{(int)w / 2, (int)h - 1}, {(int)w / 2, (int)h - 5}},    //bottom
        {{0, (int)h / 2}, {4, (int)h / 2}},                      //left
        {{(int)w - 1, (int)h / 2}, {(int)w - 5, (int)h / 2}},    //right
    };
    for (int i = 0; i < 4; i++) {
        int edge = Grey(rep, samples[i][0][0], samples[i][0][1]);
        int fill = Grey(rep, samples[i][1][0], samples[i][1][1]);
        worst = MAX(worst, abs(edge - fill));
    }
    return worst;
}

static void Search(DictionaryPalette* palette, NSString* query) {
    palette.searchField.stringValue = query;
    [palette reloadResultsAndSelectFirst:YES];
    Spin(0.08);
}

int main(int argc, const char** argv) {
    @autoreleasepool {
        if (argc < 5) {
            printf("usage: dictionary_speech_test <catalog.json> <en-vi.zip> <vi-en.zip> <work-dir> [snapshot-dir]\n");
            return 2;
        }
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
        NSFileManager* fm = [NSFileManager defaultManager];

        NSURL* catalog = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSString* work = [NSString stringWithUTF8String:argv[4]];
        NSString* snapDir = argc >= 6 ? [NSString stringWithUTF8String:argv[5]] : nil;
        NSURL* dirImport = [NSURL fileURLWithPath:[work stringByAppendingPathComponent:@"import"] isDirectory:YES];
        NSURL* dirInstalled = [NSURL fileURLWithPath:[work stringByAppendingPathComponent:@"installed"] isDirectory:YES];
        [fm createDirectoryAtURL:dirInstalled withIntermediateDirectories:YES attributes:nil error:nil];
        NSString* suite = [@"vok.dict.speech.test." stringByAppendingString:[[NSUUID UUID] UUIDString]];
        NSUserDefaults* defs = [[NSUserDefaults alloc] initWithSuiteName:suite];

        // 1. compile the two zips with the service (a local import: no network), then install them under the ids of the catalog
        DictionaryService* importer = [[DictionaryService alloc] initWithDirectory:dirImport catalogURL:catalog userDefaults:defs];
        NSArray<NSString*>* zips = @[[NSString stringWithUTF8String:argv[2]], [NSString stringWithUTF8String:argv[3]]];
        NSArray<NSString*>* ids = @[@"en-vi-test", @"vi-en-test"];
        NSMutableDictionary* installed = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < zips.count; i++) {
            __block VOKDictionaryCatalogItem* item = nil;
            __block BOOL done = NO;
            [importer importLocalURL:[NSURL fileURLWithPath:zips[i]] completion:^(VOKDictionaryCatalogItem* it, NSError* e) {
                item = it;
                done = YES;
            }];
            CHECK(WaitUntil(10, ^BOOL{ return done; }) && item != nil, "import of %s", zips[i].UTF8String);
            if (item == nil) return 1;
            NSURL* from = [dirImport URLByAppendingPathComponent:[item.dictId stringByAppendingString:@".vdict"]];
            NSURL* to = [dirInstalled URLByAppendingPathComponent:[ids[i] stringByAppendingString:@".vdict"]];
            [fm removeItemAtURL:to error:nil];
            NSError* copyError = nil;
            CHECK([fm copyItemAtURL:from toURL:to error:&copyError], "copy of the compiled dictionary: %s", copyError.localizedDescription.UTF8String ?: "");
            installed[ids[i]] = @{@"enabled": @YES, @"entryCount": @3, @"priority": @(10 + i)};
        }
        NSData* state = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"installed": installed} options:0 error:nil];
        [state writeToURL:[dirInstalled URLByAppendingPathComponent:@"state.json"] atomically:NO];

        DictionaryService* service = [[DictionaryService alloc] initWithDirectory:dirInstalled catalogURL:catalog userDefaults:defs];
        NSArray<VOKDictionaryCatalogItem*>* all = [service installedDictionaries];
        CHECK(all.count == 2, "two dictionaries installed, got %lu", (unsigned long)all.count);
        for (VOKDictionaryCatalogItem* item in all) {
            if ([item.dictId isEqualToString:@"en-vi-test"]) CHECK([item.sourceLang isEqualToString:@"en"], "en-vi-test is English");
            if ([item.dictId isEqualToString:@"vi-en-test"]) CHECK([item.sourceLang isEqualToString:@"vi"], "vi-en-test is Vietnamese");
        }

        DictionaryPalette* palette = [[DictionaryPalette alloc] initWithService:service];
        __block NSMutableArray<NSString*>* spoken = [NSMutableArray array];
        __block NSString* spokenLanguage = nil;
        [WordSpeaker shared].speakHook = ^(NSString* text, NSString* language) {
            [spoken addObject:text];
            spokenLanguage = language;
        };

        [palette showWithQuery:nil captureSelection:NO];
        [[palette panel] setFrameOrigin:NSMakePoint(-20000, -20000)];
        Spin(0.1);
        CHECK(palette.panel.visible && !palette.showingManager, "the window opens on the lookup");

        // 2. the edge: a hairline, in light and in dark
        Search(palette, @"hello");
        NSBitmapImageRep* dark = Render(palette.panel, NSAppearanceNameDarkAqua, snapDir ? [snapDir stringByAppendingPathComponent:@"speech-dark.png"] : nil);
        NSBitmapImageRep* light = Render(palette.panel, NSAppearanceNameAqua, snapDir ? [snapDir stringByAppendingPathComponent:@"speech-light.png"] : nil);
        int darkEdge = EdgeContrast(dark), lightEdge = EdgeContrast(light);
        printf("edge contrast: dark %d, light %d (a hairline is about 25; the white line of 55%% was 115 and 137)\n", darkEdge, lightEdge);
        CHECK(darkEdge <= 45, "the edge is a hairline in dark (contrast %d)", darkEdge);
        CHECK(lightEdge <= 45, "the edge is a hairline in light (contrast %d)", lightEdge);
        CHECK(darkEdge >= 8 && lightEdge >= 8, "the edge is still drawn (dark %d, light %d)", darkEdge, lightEdge);
        CHECK(dark.bitmapData[3] < 128, "the corner of the window is cut round (alpha %d)", dark.bitmapData[3]);

        // 3. the speaker for an English headword
        CHECK([palette.speakText isEqualToString:@"hello"], "speakText for hello is hello, got %s", palette.speakText.UTF8String ?: "(nil)");
        CHECK(!palette.speakButton.hidden, "the speaker is shown for hello");
        CHECK(palette.speakButton.superview == palette.copyButton.superview, "the speaker is in the bar of the copy button");
        CHECK(NSMaxX(palette.speakButton.frame) <= NSMinX(palette.copyButton.frame), "the speaker does not overlap the copy button");
        [palette.speakButton performClick:nil];
        CHECK(spoken.count == 1 && [spoken[0] isEqualToString:@"hello"], "the button read \"hello\" (%lu reads)", (unsigned long)spoken.count);
        CHECK([spokenLanguage hasPrefix:@"en"], "the voice is English (%s)", spokenLanguage.UTF8String ?: "(nil)");

        // 4. ⌘P reads it too, also with the search field having the keyboard; other modifiers do not
        [palette.panel makeKeyAndOrderFront:nil];
        [palette.panel makeFirstResponder:palette.searchField];
        BOOL handled = [palette.panel performKeyEquivalent:KeyEvent(palette.panel, @"p", kVK_ANSI_P, NSEventModifierFlagCommand)];
        CHECK(handled && spoken.count == 2 && [spoken[1] isEqualToString:@"hello"], "⌘P read it (handled=%d, %lu reads)", handled, (unsigned long)spoken.count);
        [palette.panel performKeyEquivalent:KeyEvent(palette.panel, @"p", kVK_ANSI_P, NSEventModifierFlagCommand | NSEventModifierFlagShift)];
        [palette.panel performKeyEquivalent:KeyEvent(palette.panel, @"p", kVK_ANSI_P, 0)];
        CHECK(spoken.count == 2, "⌘⇧P and P alone read nothing (%lu reads)", (unsigned long)spoken.count);

        // 5. what is not read: the Vietnamese headword "ba" of the Vietnamese-English dictionary, an accented one, nothing found
        Search(palette, @"ba");
        CHECK(palette.speakText == nil && palette.speakButton.hidden, "\"ba\" of the Vietnamese dictionary is not read (speakText %s)", palette.speakText.UTF8String ?: "(nil)");
        handled = [palette.panel performKeyEquivalent:KeyEvent(palette.panel, @"p", kVK_ANSI_P, NSEventModifierFlagCommand)];
        CHECK(handled && spoken.count == 2, "⌘P on \"ba\" reads nothing but is not passed on (handled=%d, %lu reads)", handled, (unsigned long)spoken.count);
        Search(palette, @"xin chao");
        CHECK(palette.speakText == nil && palette.speakButton.hidden, "an accented headword is not read");
        Search(palette, @"zzzzqq");
        CHECK(palette.speakText == nil && palette.speakButton.hidden, "nothing found: nothing to read");

        // 6. a word that both dictionaries have is read: one of them is English
        Search(palette, @"an");
        CHECK([palette.speakText isEqualToString:@"an"], "\"an\" is in both dictionaries and is read (speakText %s)", palette.speakText.UTF8String ?: "(nil)");

        // 7. the speaker follows the word that is shown, and the manager has none
        Search(palette, @"apple");
        CHECK([palette.speakText isEqualToString:@"apple"], "the speaker follows the selection: apple");
        [palette setShowingManager:YES];
        NSUInteger before = spoken.count;
        [palette speakCurrentWord];
        CHECK(spoken.count == before, "nothing is read in the manager");
        [palette setShowingManager:NO];

        // 8. how an entry is set: no markup, numbered senses with a hanging indent, the part of speech in bold italic, examples in italic
        [palette setShowingManager:NO];
        Search(palette, @"hood");
        NSString* text = palette.definitionView.string;
        CHECK([text rangeOfString:@"font-family"].location == NSNotFound && [text rangeOfString:@"margin"].location == NSNotFound,
              "the style sheet of the dictionary is not shown: %s", text.UTF8String);
        CHECK([text containsString:@"1.\tmui xe"] && [text containsString:@"2.\tcái mũ trùm"], "senses are numbered: %s", text.UTF8String);
        CHECK([text containsString:@"/hʊd/"], "the phonetic is shown");
        NSTextStorage* storage = palette.definitionView.textStorage;
        NSRange posAt = [text rangeOfString:@"n."];
        CHECK(posAt.location != NSNotFound, "the part of speech is shown");
        if (posAt.location != NSNotFound) {
            NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:[storage attribute:NSFontAttributeName atIndex:posAt.location effectiveRange:NULL]];
            CHECK((traits & NSItalicFontMask) && (traits & NSBoldFontMask), "the part of speech is bold italic (traits %lx)", (unsigned long)traits);
        }
        NSRange senseAt = [text rangeOfString:@"mui xe"];
        if (senseAt.location != NSNotFound) {
            NSParagraphStyle* style = [storage attribute:NSParagraphStyleAttributeName atIndex:senseAt.location effectiveRange:NULL];
            CHECK(style.headIndent >= 20 && style.firstLineHeadIndent == 0, "hanging indent: the text lines up after the number (head %.0f, first %.0f)", style.headIndent, style.firstLineHeadIndent);
        }
        Search(palette, @"bàn");
        text = palette.definitionView.string;
        CHECK([text containsString:@"noun"] && [text containsString:@"verb"], "OVDP in one line: both parts of speech: %s", text.UTF8String);
        CHECK([text containsString:@"1.\tto discuss"] && [text containsString:@"2.\tto plan"], "the senses of the verb are numbered");
        CHECK([text containsString:@"Table\n"] && ![text containsString:@"1.\tTable"], "a sense alone has no number");
        CHECK([text containsString:@"“bàn ăn”"] && [text containsString:@"a dinner-table"], "the example and its translation");
        CHECK(![text containsString:@"* noun"] && ![text containsString:@"* verb"] && ![text containsString:@"- Table"] && ![text containsString:@"- to plan"] &&
              ![text containsString:@"=bàn"] && ![text containsString:@"+a dinner"], "no mark of the source is left: %s", text.UTF8String);
        NSRange exAt = [text rangeOfString:@"bàn ăn"];
        if (exAt.location != NSNotFound) {
            NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:[storage attribute:NSFontAttributeName atIndex:exAt.location effectiveRange:NULL]];
            CHECK(traits & NSItalicFontMask, "the example is in italic");
        }

        // 9. the footer tells about ⌘P
        [palette setShowingManager:NO];
        BOOL found = NO;
        NSMutableArray<NSView*>* queue = [NSMutableArray arrayWithObject:palette.panel.contentView];
        while (queue.count > 0) {
            NSView* v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([v isKindOfClass:[NSTextField class]] && [((NSTextField*)v).stringValue containsString:@"⌘P"]) found = YES;
            [queue addObjectsFromArray:v.subviews];
        }
        CHECK(found, "the footer names ⌘P");

        [WordSpeaker shared].speakHook = nil;
        [palette hide];
        [fm removeItemAtURL:[NSURL fileURLWithPath:work] error:nil];
        [defs removePersistentDomainForName:suite];
        printf("%s (%d failures)\n", gFailures == 0 ? "ALL OK" : "FAILED", gFailures);
        return gFailures == 0 ? 0 : 1;
    }
}
