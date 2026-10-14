//
//  SuggestionController.mm
//  VOpenKey
//

#import "SuggestionController.h"
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "AppInfo.h"
#import "SuggestionPanel.h"
#include <memory>
#include "SuggestSession.h"

int vSuggestEnabled = 0;
int vSuggestNextWord = 1;
int vSuggestLearn = 1;
int vSuggestCompounds = 1;
int vSuggestTabAccepts = 0;

static NSString* const kExcludedAppsKey = @"SuggestionExcludedApps"; //optional: extra bundle ids to leave alone

//Tab completes shell commands and moves between fields, these applications would lose that
static NSArray<NSString*>* DefaultExcludedApps(void) {
    return @[@"com.apple.Terminal", @"com.googlecode.iterm2", @"com.mitchellh.ghostty", @"dev.warp.Warp-Stable",
             @"net.kovidgoyal.kitty", @"org.alacritty", @"co.zeit.hyper", @"com.github.wez.wezterm"];
}

static NSString* ToNSString(const std::string& s) {
    return [NSString stringWithUTF8String:s.c_str()] ?: @"";
}

@class SuggestionController;

//The shared engine talks to the platform through this
class BarHost : public vsuggest::Host {
public:
    explicit BarHost(SuggestionController* owner) : owner_(owner) {}
    void showCandidates(const std::vector<vsuggest::Candidate>& candidates, const std::string& typed) override;
    void hideCandidates() override;
private:
    __unsafe_unretained SuggestionController* owner_;
};

@interface SuggestionController ()
-(void)showBarWithWords:(NSArray<NSString*>*)words typed:(NSString*)typed;
-(void)hideBar;
@end

void BarHost::showCandidates(const std::vector<vsuggest::Candidate>& candidates, const std::string& typed) {
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    for (const vsuggest::Candidate& c : candidates)
        [words addObject:ToNSString(c.text)];
    [owner_ showBarWithWords:words typed:ToNSString(typed)];
}

void BarHost::hideCandidates() {
    [owner_ hideBar];
}

@implementation SuggestionController {
    std::unique_ptr<vsuggest::Engine> _engine;
    std::unique_ptr<BarHost> _host;
    std::unique_ptr<vsuggest::Session> _session;

    BOOL _started;
    BOOL _appExcluded;
    BOOL _refreshScheduled;
    NSTimer* _saveTimer;

    SuggestionPanel* _panel;
    NSArray<NSString*>* _lastWords;
    NSString* _lastTyped;
    NSRect _anchorRect;          //where the word being typed starts, in Cocoa screen coordinates
    BOOL _anchorValid;
    BOOL _anchorQueryInFlight;
    NSUInteger _generation;      //changes every time the bar is hidden, so late answers are ignored
    dispatch_queue_t _accessibilityQueue;
    NSMutableSet<NSNumber*>* _manualAccessibility; //only touched on _accessibilityQueue
}

+(SuggestionController*)shared {
    static SuggestionController* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[SuggestionController alloc] init]; });
    return instance;
}

#pragma mark - Files

-(NSURL*)dataFolder {
    NSURL* support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:VOK_APP_NAME isDirectory:YES];
}

-(NSURL*)dictionaryFolder {
    return [[self dataFolder] URLByAppendingPathComponent:@"Dictionaries" isDirectory:YES];
}

-(NSURL*)learnedFile {
    return [[self dataFolder] URLByAppendingPathComponent:@"learned.txt"];
}

-(void)prepareFolders {
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:[self dictionaryFolder] withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL* readme = [[self dictionaryFolder] URLByAppendingPathComponent:@"README.txt"];
    if (![fm fileExistsAtPath:readme.path]) {
        NSString* text =
            @"VOpenKey - Từ điển gợi ý\n\n"
            @"Thả các file .txt vào thư mục này rồi vào Cài đặt > Gõ tắt > \"Tải lại từ điển\" (hoặc mở lại VOpenKey).\n"
            @"Mỗi dòng một mục, dùng phím Tab để ngăn cách chữ và số lần dùng:\n\n"
            @"    xin chào<TAB>3000          một từ và số lần dùng (có thể bỏ số)\n"
            @"    xin chào các bạn<TAB>20    nhiều từ: VOpenKey học từ nào hay đi sau từ nào\n"
            @"    # dòng bắt đầu bằng # là ghi chú\n\n"
            @"    thiết_kế<TAB>900           từ ghép (nối các âm tiết bằng dấu _): gõ liền \"thietke\" ra \"thiết kế\"\n"
            @"    #!compounds                từ dòng này trở xuống, nhiều từ trên một dòng là MỘT từ ghép, nên có thể viết\n"
            @"                               danh sách từ ghép bằng dấu cách; #!context để quay lại như cũ\n\n"
            @"\"Từ\" ở đây là một âm tiết giữa hai dấu cách. Không cần gõ đúng dấu: gõ \"hoc\" vẫn tìm ra \"học\".\n"
            @"Từ bạn gõ được VOpenKey học và lưu ở file learned.txt trong thư mục cha; xoá file đó để quên hết.\n"
            @"Muốn tạo từ điển lớn từ văn bản tiếng Việt: scripts/build-dictionary.py trong mã nguồn.\n";
        [text writeToURL:readme atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void LoadFile(vsuggest::Engine& engine, NSString* path, vsuggest::Target target) {
    NSData* data = path.length > 0 ? [NSData dataWithContentsOfFile:path] : nil;
    if (data.length == 0)
        return;
    engine.loadText(std::string((const char*)data.bytes, data.length), target);
}

-(void)loadDictionaries {
    _engine->clear(vsuggest::Target::Base);
    _engine->clear(vsuggest::Target::User);

    //shipped with the app: a small list with real word counts, then the words of the Vietnamese Wiktionary
    for (NSString* name in @[@"vi-base", @"vi-wiktionary"])
        LoadFile(*_engine, [[NSBundle mainBundle] pathForResource:name ofType:@"txt"], vsuggest::Target::Base);

    NSArray<NSString*>* names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self dictionaryFolder].path error:nil];
    for (NSString* name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if ([name.pathExtension.lowercaseString isEqualToString:@"txt"] && ![name isEqualToString:@"README.txt"])
            LoadFile(*_engine, [[self dictionaryFolder] URLByAppendingPathComponent:name].path, vsuggest::Target::Base);
    }
    LoadFile(*_engine, [self learnedFile].path, vsuggest::Target::User);
}

-(void)saveLearning {
    if (!_engine || !_engine->hasUnsavedLearning())
        return;
    std::string text = _engine->serializeUser();
    NSData* data = [NSData dataWithBytes:text.data() length:text.size()];
    NSURL* file = [self learnedFile];
    if ([data writeToURL:file options:NSDataWritingAtomic error:nil]) {
        //it holds what was typed: only for this user
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:file.path error:nil];
    }
}

#pragma mark - Life cycle

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"SuggestionNextWord": @1, @"SuggestionLearn": @1,
                                                              @"SuggestionCompounds": @1, @"SuggestionTab": @0}];
}

+(void)start {
    [[self shared] startUp];
}

+(void)stop {
    [[self shared] shutDown];
}

-(void)startUp {
    if (_started)
        return;
    _started = YES;

    [SuggestionController registerDefaults];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    vSuggestEnabled = (int)[defaults integerForKey:@"SuggestionEnabled"];
    vSuggestNextWord = (int)[defaults integerForKey:@"SuggestionNextWord"];
    vSuggestLearn = (int)[defaults integerForKey:@"SuggestionLearn"];
    vSuggestCompounds = (int)[defaults integerForKey:@"SuggestionCompounds"];
    vSuggestTabAccepts = (int)[defaults integerForKey:@"SuggestionTab"];

    _accessibilityQueue = dispatch_queue_create("vn.io.lssoft.vopenkey.suggestion.accessibility", DISPATCH_QUEUE_SERIAL);
    _manualAccessibility = [NSMutableSet set];

    _engine.reset(new vsuggest::Engine());
    _host.reset(new BarHost(self));
    _session.reset(new vsuggest::Session(*_engine, *_host));

    //words the dictionaries lack are completed by the spell checker of macOS
    _engine->setFallback([](const std::string& typed, std::vector<std::string>& words) {
        NSString* partial = ToNSString(typed);
        NSArray<NSString*>* found = [[NSSpellChecker sharedSpellChecker] completionsForPartialWordRange:NSMakeRange(0, partial.length)
                                                                                               inString:partial
                                                                                               language:@"vi"
                                                                                 inSpellDocumentWithTag:0];
        for (NSString* word in found)
            words.push_back(word.UTF8String);
    });

    [self prepareFolders];
    [self loadDictionaries];

    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    [[workspace notificationCenter] addObserver:self
                                       selector:@selector(applicationActivated:)
                                           name:NSWorkspaceDidActivateApplicationNotification
                                         object:nil];
    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer* timer) {
        [self saveLearning];
    }];

    _appExcluded = [self isExcluded:workspace.frontmostApplication];
    [self applySettings];
}

-(void)shutDown {
    if (!_started)
        return;
    [_saveTimer invalidate];
    _saveTimer = nil;
    [self saveLearning];
}

-(BOOL)isExcluded:(NSRunningApplication*)app {
    NSString* identifier = app.bundleIdentifier;
    if (identifier.length == 0)
        return NO;
    if ([DefaultExcludedApps() containsObject:identifier])
        return YES;
    return [[[NSUserDefaults standardUserDefaults] arrayForKey:kExcludedAppsKey] containsObject:identifier];
}

-(void)applicationActivated:(NSNotification*)notification {
    NSRunningApplication* app = notification.userInfo[NSWorkspaceApplicationKey];
    _appExcluded = [self isExcluded:app];
    [self resetState];
    [self applySettings];
    [self saveLearning];
}

-(void)applySettings {
    vsuggest::Settings settings;
    settings.enabled = vSuggestEnabled && !_appExcluded;
    settings.nextWord = vSuggestNextWord;
    settings.learn = vSuggestLearn;
    settings.compounds = vSuggestCompounds;
    _session->setSettings(settings);
}

#pragma mark - Called while typing

+(void)reloadSettings {
    SuggestionController* s = [self shared];
    if (s->_started)
        [s applySettings];
}

+(void)reloadDictionaries {
    SuggestionController* s = [self shared];
    if (!s->_started)
        return;
    [s saveLearning];
    [s resetState];
    [s prepareFolders];
    [s loadDictionaries];
}

+(void)forgetLearnedWords {
    SuggestionController* s = [self shared];
    [[NSFileManager defaultManager] removeItemAtURL:[s learnedFile] error:nil];
    if (!s->_started)
        return;
    s->_engine->clear(vsuggest::Target::User);
    [s resetState];
}

+(void)openDictionaryFolder {
    SuggestionController* s = [self shared];
    [s prepareFolders];
    [[NSWorkspace sharedWorkspace] openURL:[s dictionaryFolder]];
}

+(BOOL)isShowing {
    SuggestionController* s = [self shared];
    return s->_session && s->_session->isShowing();
}

-(void)resetState {
    if (_session)
        _session->reset();
    [self hideBar];
}

+(void)reset {
    SuggestionController* s = [self shared];
    if (s->_started)
        [s resetState];
}

+(void)keyProcessed:(VOKSuggestionKey)key word:(NSString*)word raw:(NSString*)raw {
    SuggestionController* s = [self shared];
    if (!s->_started || !s->_session->settings().enabled)
        return;
    vsuggest::KeyKind kind = key == VOKSuggestionKeySpace ? vsuggest::KeyKind::Space :
                             (key == VOKSuggestionKeyDelete ? vsuggest::KeyKind::Delete : vsuggest::KeyKind::Other);
    s->_session->keyProcessed(kind, word.UTF8String ?: "", raw.UTF8String ?: "");
    [s scheduleRefresh];
}

//the suggestions are worked out after the key has been let through, so typing is never held up by them
-(void)scheduleRefresh {
    if (_refreshScheduled)
        return;
    _refreshScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_refreshScheduled = NO;
        if (self->_session)
            self->_session->refresh();
    });
}

+(BOOL)acceptSlot:(NSInteger)slot
      currentWord:(NSString*)word
             text:(NSString* __autoreleasing*)text
            erase:(NSUInteger*)erase {
    SuggestionController* s = [self shared];
    if (!s->_started || slot < 0)
        return NO;
    vsuggest::Acceptance acceptance;
    if (!s->_session->accept((size_t)slot, word.UTF8String ?: "", acceptance))
        return NO;
    *text = ToNSString(acceptance.text);
    *erase = acceptance.eraseCount;
    [s scheduleRefresh];
    return YES;
}

#pragma mark - The bar

-(void)showBarWithWords:(NSArray<NSString*>*)words typed:(NSString*)typed {
    if (!_panel)
        _panel = [[SuggestionPanel alloc] init];
    _lastWords = words;
    _lastTyped = typed;
    _panel.firstWordUsesTab = vSuggestTabAccepts != 0;
    [_panel setWords:words];

    //the bar stays where the word started while it is being typed, a new word is a new place
    if (_anchorValid && typed.length > 1) {
        [_panel showBelowRect:_anchorRect];
        return;
    }
    if (_anchorQueryInFlight)
        return;
    _anchorQueryInFlight = YES;
    NSUInteger generation = _generation;
    pid_t pid = [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier;
    NSUInteger back = MAX(typed.length, (NSUInteger)1);

    dispatch_async(_accessibilityQueue, ^{
        [NSThread sleepForTimeInterval:0.04]; //the application has to draw the new letter first
        NSValue* found = [self caretRectForProcess:pid charactersBack:back];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_anchorQueryInFlight = NO;
            if (!self->_session->isShowing())
                return;
            if (generation != self->_generation) { //hidden and shown again meanwhile
                if (self->_lastWords)
                    [self showBarWithWords:self->_lastWords typed:self->_lastTyped];
                return;
            }
            if (found != nil) {
                self->_anchorRect = [self cocoaRectFromAccessibilityRect:found.rectValue];
                self->_anchorValid = YES;
                [self->_panel showBelowRect:self->_anchorRect];
            } else {
                [self->_panel showNearPoint:[NSEvent mouseLocation]];
            }
        });
    });
}

-(void)hideBar {
    _generation++;
    _anchorValid = NO;
    _lastWords = nil;
    [_panel orderOut:nil];
}

-(NSRect)cocoaRectFromAccessibilityRect:(NSRect)rect {
    //Accessibility counts from the top left of the main display, Cocoa from the bottom left
    CGFloat mainHeight = [[NSScreen screens] firstObject].frame.size.height;
    return NSMakeRect(rect.origin.x, mainHeight - rect.origin.y - rect.size.height, rect.size.width, rect.size.height);
}

/// Where a letter of the text being typed is, asked of the application that has the keyboard. Runs off the main
/// thread because the application may be slow to answer. nil when it cannot say.
-(NSValue*)caretRectForProcess:(pid_t)pid charactersBack:(NSUInteger)back {
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (application == NULL)
        return nil;
    AXUIElementSetMessagingTimeout(application, 0.25);

    //Chromium and Electron only describe their text fields once asked to
    if (![_manualAccessibility containsObject:@(pid)]) {
        [_manualAccessibility addObject:@(pid)];
        AXUIElementSetAttributeValue(application, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
    }

    NSValue* result = nil;
    CFTypeRef focused = NULL;
    if (AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess && focused) {
        AXUIElementRef element = (AXUIElementRef)focused;
        AXUIElementSetMessagingTimeout(element, 0.25);
        CFTypeRef selection = NULL;
        if (AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute, &selection) == kAXErrorSuccess && selection) {
            CFRange caret;
            if (AXValueGetValue((AXValueRef)selection, (AXValueType)kAXValueTypeCFRange, &caret)) {
                CFRange target = CFRangeMake(MAX(caret.location - (CFIndex)back, (CFIndex)0), 1);
                AXValueRef targetValue = AXValueCreate((AXValueType)kAXValueTypeCFRange, &target);
                CFTypeRef bounds = NULL;
                if (targetValue != NULL &&
                    AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute,
                                                               targetValue, &bounds) == kAXErrorSuccess && bounds) {
                    CGRect rect;
                    if (AXValueGetValue((AXValueRef)bounds, (AXValueType)kAXValueTypeCGRect, &rect) &&
                        rect.size.height > 0 && !(rect.origin.x == 0 && rect.origin.y == 0))
                        result = [NSValue valueWithRect:NSRectFromCGRect(rect)];
                    CFRelease(bounds);
                }
                if (targetValue != NULL)
                    CFRelease(targetValue);
            }
            CFRelease(selection);
        }
        CFRelease(focused);
    }
    CFRelease(application);
    return result;
}

@end
