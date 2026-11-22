//
//  dictionary_test.m
//  VOpenKey
//
//  End-to-end macOS tests for DictionaryService, DictionaryPalette, HTTP mock catalog download,
//  error handling, local ZIP import, accent-folded search, multi-dict selection, and keyboard navigation.
//
//  Usage: dictionary_test <catalog.json> <local-import.zip> [snapshot-dir]
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "DictionaryService.h"
#import "DictionaryPalette.h"
#import "CaseBar.h"

static int gFailures = 0;
#define CHECK(cond, fmt, ...) do { \
    if (!(cond)) { \
        printf("FAIL line %d: " fmt "\n", __LINE__, ##__VA_ARGS__); \
        gFailures++; \
    } \
} while (0)

static void Spin(NSTimeInterval seconds) {
    NSDate* limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
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

static void SaveSnapshot(NSWindow* window, NSString* path) {
    if (path.length == 0 || window == nil) return;
    NSView* view = window.contentView;
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep* rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    if (rep == nil) return;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    }];
    NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:path atomically:YES];
}

int main(int argc, const char** argv) {
    @autoreleasepool {
        if (argc < 3) {
            printf("usage: dictionary_test <catalog.json> <local-import.zip> [snapshot-dir]\n");
            return 2;
        }
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;

        NSString* catalogPath = [NSString stringWithUTF8String:argv[1]];
        NSString* localZipPath = [NSString stringWithUTF8String:argv[2]];
        NSString* snapDir = argc >= 4 ? [NSString stringWithUTF8String:argv[3]] : nil;

        NSString* tmpRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSURL* workDir = [NSURL fileURLWithPath:tmpRoot isDirectory:YES];
        NSString* suiteName = [@"vok.dict.test." stringByAppendingString:[[NSUUID UUID] UUIDString]];
        NSUserDefaults* defs = [[NSUserDefaults alloc] initWithSuiteName:suiteName];

        DictionaryService* service = [[DictionaryService alloc] initWithDirectory:workDir
                                                                       catalogURL:[NSURL fileURLWithPath:catalogPath]
                                                                     userDefaults:defs];
        DictionaryPalette* palette = [[DictionaryPalette alloc] initWithService:service];

        // 1. Initial empty state: catalog puts Anh-Viet & Viet-Anh first
        NSArray<VOKDictionaryCatalogItem*>* all = [service allDictionaries];
        CHECK(all.count == 4, "expected 4 mock catalog items, got %lu", (unsigned long)all.count);
        CHECK([all[0].dictId isEqualToString:@"en-vi-mock"], "first must be en-vi-mock: %s", all[0].dictId.UTF8String);
        CHECK([all[1].dictId isEqualToString:@"vi-en-mock"], "second must be vi-en-mock: %s", all[1].dictId.UTF8String);
        CHECK(![service hasInstalledDictionary], "starts with 0 installed dictionaries");

        [palette showWithQuery:nil captureSelection:NO];
        [[palette panel] setFrameOrigin:NSMakePoint(-20000, -20000)];
        Spin(0.1);
        CHECK(palette.panel.visible, "panel opens");
        CHECK(palette.showingManager, "opens into Manager when 0 dictionaries installed");
        if (snapDir) {
            palette.panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            SaveSnapshot(palette.panel, [snapDir stringByAppendingPathComponent:@"dict-manager-light.png"]);
            palette.panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            SaveSnapshot(palette.panel, [snapDir stringByAppendingPathComponent:@"dict-manager-dark.png"]);
            palette.panel.appearance = nil;
        }

        // 2. Download Anh-Viet & Viet-Anh concurrently from mock HTTP server
        [service downloadDictionariesWithIDs:@[@"en-vi-mock", @"vi-en-mock"]];
        BOOL downloaded = WaitUntil(10.0, ^BOOL{
            return ![service hasActiveDownload] && [service installedDictionaries].count == 2;
        });
        CHECK(downloaded, "downloads finished cleanly (%lu installed)", (unsigned long)[service installedDictionaries].count);

        // 3. Test failed HTTP 500 download records clean Vietnamese error without installing
        [service downloadDictionariesWithIDs:@[@"broken-mock"]];
        BOOL settledFail = WaitUntil(8.0, ^BOOL{
            for (VOKDictionaryCatalogItem* it in [service allDictionaries]) {
                if ([it.dictId isEqualToString:@"broken-mock"] && !it.downloading && it.errorText.length > 0)
                    return YES;
            }
            return NO;
        });
        CHECK(settledFail, "broken download reports clear errorText");
        CHECK([service installedDictionaries].count == 2, "broken download does not install");

        // 4. Local ZIP import
        __block VOKDictionaryCatalogItem* importedItem = nil;
        __block NSError* importErr = nil;
        __block BOOL importDone = NO;
        [service importLocalURL:[NSURL fileURLWithPath:localZipPath] completion:^(VOKDictionaryCatalogItem* item, NSError* error) {
            importedItem = item;
            importErr = error;
            importDone = YES;
        }];
        CHECK(WaitUntil(8.0, ^BOOL{ return importDone; }), "local import finishes");
        CHECK(importErr == nil && importedItem != nil, "local import succeeded (%s)", importErr.localizedDescription.UTF8String ?: "");
        CHECK([service installedDictionaries].count == 3, "now 3 dictionaries installed");

        // 5. Switch to Lookup mode and verify multi-dictionary auto-match on "hello"
        [palette setShowingManager:NO];
        palette.searchField.stringValue = @"hello";
        [palette reloadResultsAndSelectFirst:YES];
        Spin(0.08);
        CHECK(!palette.showingManager, "in lookup mode");
        CHECK(palette.currentHits.count >= 1, "found hits for hello");
        CHECK([palette.currentHits[0].headword isEqualToString:@"hello"] && palette.currentHits[0].isExact,
              "auto-matched exact hello (dictCount=%lu)", (unsigned long)palette.currentHits[0].dictCount);
        CHECK(palette.currentHits[0].dictCount >= 2, "hello matched across >= 2 dictionaries");
        NSString* defText = palette.definitionView.string;
        CHECK([defText containsString:@"xin chào"] && [defText containsString:@"greeting"],
              "definition pane renders combined Anh-Viet and WordNet meanings");

        if (snapDir) {
            palette.panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            SaveSnapshot(palette.panel, [snapDir stringByAppendingPathComponent:@"dict-lookup-light.png"]);
            palette.panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            SaveSnapshot(palette.panel, [snapDir stringByAppendingPathComponent:@"dict-lookup-dark.png"]);
            palette.panel.appearance = nil;
        }

        // 6. Synonym inflection auto-match ("stopped" -> "stop")
        palette.searchField.stringValue = @"stopped";
        [palette reloadResultsAndSelectFirst:YES];
        CHECK(palette.currentHits.count >= 1 && [palette.currentHits[0].headword isEqualToString:@"stop"],
              "stopped resolved to canonical stop");

        // 7. Accent-insensitive Vietnamese search ("xin chao" -> "xin chào")
        palette.searchField.stringValue = @"xin chao";
        [palette reloadResultsAndSelectFirst:YES];
        CHECK(palette.currentHits.count >= 1 && [palette.currentHits[0].headword isEqualToString:@"xin chào"],
              "unaccented query finds xin chào");

        // 8. Filter pill restricts results cleanly
        [palette selectFilterDictId:@"vi-en-mock"];
        palette.searchField.stringValue = @"apple";
        [palette reloadResultsAndSelectFirst:YES];
        CHECK(palette.currentHits.count == 0, "apple absent when filtered to vi-en-mock");
        [palette selectFilterDictId:nil];

        // 9. Keyboard Esc first clears query, second Esc hides window
        [palette.panel sendEvent:KeyEvent(palette.panel, @"\x1b", kVK_Escape, 0)];
        Spin(0.05);
        CHECK(palette.searchField.stringValue.length == 0 && palette.panel.visible, "first Esc clears query");
        [palette.panel cancelOperation:nil];
        Spin(0.05);
        CHECK(!palette.panel.visible, "second Esc closes panel");

        // 10. Remove dictionary leaves others active
        [service removeDictionaryID:importedItem.dictId];
        CHECK([service installedDictionaries].count == 2, "removed imported dictionary");

        [[NSFileManager defaultManager] removeItemAtURL:workDir error:nil];
        [defs removePersistentDomainForName:suiteName];

        printf("%s (%d failures)\n", gFailures == 0 ? "ALL OK" : "FAILED", gFailures);
        return gFailures == 0 ? 0 : 1;
    }
}
