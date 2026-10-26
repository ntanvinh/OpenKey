#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "SuggestionController.h"
#import "SuggestionPanel.h"
#import "SettingsWindowController.h"
#import "VOKUI.h"

@interface SettingsWindowController (SuggestionAppsTesting)
-(NSView*)sectionSuggestionApps;
-(NSView*)sectionSuggestion;
-(void)reloadSuggestionApps;
-(void)removeSuggestionApp:(NSButton*)sender;
-(void)toggleSuggestionAppExclusions:(NSSwitch*)sender;
-(void)toggleSuggestionAppsExpanded:(id)sender;
@end

static NSUserDefaults* isolated;
static id TestDefaults(id self, SEL cmd) { return isolated; }
static int failures;
#define CHECK(c, m) do { if (!(c)) { NSLog(@"FAIL: %s", m); failures++; } } while (0)

static NSSwitch* FindSwitch(NSView* root) {
    if ([root isKindOfClass:NSSwitch.class]) return (NSSwitch*)root;
    for (NSView* child in root.subviews) {
        NSSwitch* found = FindSwitch(child);
        if (found) return found;
    }
    return nil;
}

static NSSlider* FindSlider(NSView* root) {
    if ([root isKindOfClass:NSSlider.class]) return (NSSlider*)root;
    for (NSView* child in root.subviews) {
        NSSlider* found = FindSlider(child);
        if (found) return found;
    }
    return nil;
}

int main(void) {
    @autoreleasepool {
        NSString* suite = [@"vopenkey.test.suggestion-apps." stringByAppendingString:NSUUID.UUID.UUIDString];
        isolated = [[NSUserDefaults alloc] initWithSuiteName:suite];
        Method defaults = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        IMP original = method_setImplementation(defaults, (IMP)TestDefaults);
        [NSApplication sharedApplication];
        CHECK([SuggestionController appExclusionsEnabled], "app exclusions default enabled before launch");
        [SuggestionController registerDefaults];
        CHECK([SuggestionController appExclusionsEnabled], "registered default enabled");
        [isolated setObject:@[@"test.legacy"] forKey:@"SuggestionExcludedApps"];
        NSArray* initial = [SuggestionController excludedApps];
        CHECK([initial containsObject:@"com.apple.Terminal"], "fresh defaults include Terminal");
        CHECK([initial containsObject:@"com.mitchellh.ghostty"], "fresh defaults include Ghostty");
        CHECK([initial containsObject:@"test.legacy"], "migration preserves custom exclusions");
        [SuggestionController setExcludedApps:@[@"test.custom", @"test.custom", @""]];
        CHECK([SuggestionController excludedApps].count == 1, "deduplicate additions and ignore empty identifiers");
        CHECK(![SuggestionController isAppIdentifierExcluded:@"com.apple.Terminal"], "default terminal can be removed");
        CHECK([SuggestionController isAppIdentifierExcluded:@"test.custom"], "custom application excluded");
        NSUserDefaults* reloaded = [[NSUserDefaults alloc] initWithSuiteName:suite];
        CHECK([[reloaded arrayForKey:@"SuggestionExcludedAppsList"] isEqual:@[@"test.custom"]], "edits persisted");
        [SuggestionController setAppExclusionsEnabled:NO];
        CHECK(![SuggestionController isAppIdentifierExcluded:@"test.custom"], "master off bypasses custom exclusions");
        CHECK([SuggestionController excludedApps].count == 1, "master off preserves list");
        CHECK(![reloaded boolForKey:@"SuggestionAppExclusionsEnabled"], "master off is persisted");
        [SuggestionController registerDefaults];
        CHECK(![SuggestionController appExclusionsEnabled], "registering defaults preserves explicit off");
        [SuggestionController setAppExclusionsEnabled:YES];
        CHECK([SuggestionController isAppIdentifierExcluded:@"test.custom"], "master on restores exclusions");
        [SuggestionController setExcludedApps:@[]];
        CHECK([SuggestionController excludedApps].count == 0, "empty list stays empty");
        CHECK(![SuggestionController isAppIdentifierExcluded:nil], "missing app identifier is safe");

        // Build only the actual settings section; do not start the event tap, dictionary or AI services.
        SettingsWindowController* controller = [SettingsWindowController alloc];
        NSView* section = [controller sectionSuggestionApps];
        NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,568,640)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
        scroll.hasVerticalScroller = YES;
        NSStackView* content = [NSStackView stackViewWithViews:@[section]];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        [section.widthAnchor constraintEqualToConstant:520].active = YES;
        scroll.documentView = content;
        window.contentView = scroll;
        controller.window = window;
        CHECK(![isolated boolForKey:@"SuggestionAppsExpanded"], "list defaults collapsed");
        CHECK(VOKFindButton(section, @selector(addSuggestionApp:)) == nil, "collapsed list hides add action");
        CHECK(FindSwitch(section).state == NSControlStateValueOn, "master switch starts on");
        [controller toggleSuggestionAppsExpanded:nil];
        CHECK([isolated boolForKey:@"SuggestionAppsExpanded"], "expansion persisted");
        CHECK(VOKFindButton(section, @selector(addSuggestionApp:)) != nil, "expansion exposes add action");
        NSMutableArray* many = [initial mutableCopy];
        for (NSUInteger i = 0; i < 40; i++)
            [many addObject:[NSString stringWithFormat:@"test.application.with.a.very.long.identifier.number.%lu", (unsigned long)i]];
        NSArray* scenarios = @[@[], @[@"test.one"], initial, many];
        NSUInteger index = 0;
        for (NSArray* apps in scenarios) {
            [SuggestionController setExcludedApps:apps];
            [controller reloadSuggestionApps];
            for (NSAppearanceName theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                window.appearance = [NSAppearance appearanceNamed:theme];
                [content setFrameSize:content.fittingSize];
                [content layoutSubtreeIfNeeded];
                CHECK(section.fittingSize.width <= 521, "section fits settings card width");
                CHECK(section.fittingSize.height > 0, "section has content in every state");
                NSBitmapImageRep* image = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
                [content cacheDisplayInRect:content.bounds toBitmapImageRep:image];
                NSString* path = [NSString stringWithFormat:@"/tmp/vopenkey-suggestion-apps-%lu-%@.png", (unsigned long)index, theme];
                [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
            }
            index++;
        }
        [SuggestionController setExcludedApps:initial];
        [controller reloadSuggestionApps];
        CGFloat expandedHeight = section.fittingSize.height;
        [controller toggleSuggestionAppsExpanded:nil];
        CHECK(section.fittingSize.height < expandedHeight, "collapse reduces section height");
        CHECK(![isolated boolForKey:@"SuggestionAppsExpanded"], "collapse persisted");
        CHECK(VOKFindButton(section, @selector(removeSuggestionApp:)) == nil, "collapsed list hides removal controls");
        NSSwitch* master = FindSwitch(section);
        master.state = NSControlStateValueOff;
        [controller toggleSuggestionAppExclusions:master];
        CHECK(![SuggestionController isAppIdentifierExcluded:@"com.apple.Terminal"], "UI switch bypasses default terminal");
        CHECK([SuggestionController excludedApps].count == initial.count, "UI switch preserves entries");
        for (NSAppearanceName theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            window.appearance = [NSAppearance appearanceNamed:theme];
            [content setFrameSize:content.fittingSize];
            [content layoutSubtreeIfNeeded];
            NSBitmapImageRep* image = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
            [content cacheDisplayInRect:content.bounds toBitmapImageRep:image];
            [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[NSString stringWithFormat:@"/tmp/vopenkey-suggestion-apps-collapsed-off-%@.png", theme] atomically:YES];
        }
        master.state = NSControlStateValueOn;
        [controller toggleSuggestionAppExclusions:master];
        CHECK([SuggestionController isAppIdentifierExcluded:@"com.apple.Terminal"], "UI switch restores terminal exclusion");
        [controller toggleSuggestionAppsExpanded:nil];
        CHECK(VOKFindButton(section, @selector(addSuggestionApp:)) != nil, "list can reopen after switching policy");
        [SuggestionController setExcludedApps:@[@"test.one"]];
        NSButton* remove = [[NSButton alloc] init];
        remove.identifier = @"test.one";
        [controller removeSuggestionApp:remove];
        CHECK([SuggestionController excludedApps].count == 0, "remove button updates saved list");

        NSView* suggestionSection = [controller sectionSuggestion];
        [suggestionSection.widthAnchor constraintEqualToConstant:520].active = YES;
        NSSlider* slider = FindSlider(suggestionSection);
        CHECK(slider != nil && slider.continuous, "native slider applies continuously");
        CHECK(slider.accessibilityLabel.length > 0, "slider has accessible label");
        CHECK(slider.minValue == 0 && slider.maxValue == 80, "slider matches supported range");
        [content removeArrangedSubview:section];
        [section removeFromSuperview];
        [content addArrangedSubview:suggestionSection];
        for (NSNumber* percent in @[@0, @50, @80]) {
            slider.doubleValue = percent.doubleValue;
            [slider sendAction:slider.action to:slider.target];
            CHECK(SuggestionPanel.transparencyPercent == percent.integerValue, "slider action saves chosen percentage");
            for (NSAppearanceName theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                window.appearance = [NSAppearance appearanceNamed:theme];
                [content setFrameSize:content.fittingSize];
                [content layoutSubtreeIfNeeded];
                CHECK(suggestionSection.fittingSize.width <= 521, "suggestion controls fit settings width");
                NSBitmapImageRep* image = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
                [content cacheDisplayInRect:content.bounds toBitmapImageRep:image];
                [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                    writeToFile:[NSString stringWithFormat:@"/tmp/vopenkey-suggestion-transparency-%@-%@.png", percent, theme] atomically:YES];
            }
        }
        NSView* reopened = [controller sectionSuggestion];
        CHECK(FindSlider(reopened).integerValue == 80, "reopened settings restore saved percentage");
        [isolated removePersistentDomainForName:suite];
        method_setImplementation(defaults, original);
        NSLog(@"Suggestion app exclusions: %d failures", failures);
        return failures ? 1 : 0;
    }
}
