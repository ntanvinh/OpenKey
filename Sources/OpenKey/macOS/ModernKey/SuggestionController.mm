//
//  SuggestionController.mm
//  VOpenKey
//

#import "SuggestionController.h"
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "AppInfo.h"
#import "CaretLocator.h"
#import "SuggestionPanel.h"
#import "Diagnostics.h"
#include <memory>
#include "SuggestSession.h"

int vSuggestEnabled = 0;
int vSuggestNextWord = 1;
int vSuggestLearn = 1;
int vSuggestCompounds = 1;
int vSuggestTabAccepts = 1;
int vMacroConfirm = 1;

extern int vMacroNeedsConfirm; //Engine.cpp

static NSString* const kExcludedAppsKey = @"SuggestionExcludedApps"; //legacy extra bundle ids

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

//A word fits the bar, the full text of an abbreviation may be a paragraph: one line, not too long (what is typed is the full text)
static NSString* BarText(const std::string& text) {
    static const NSUInteger kMaxLength = 36;
    NSString* line = [ToNSString(text) stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    line = [line stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    line = [line stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    if (line.length <= kMaxLength)
        return line;
    NSRange safe = [line rangeOfComposedCharacterSequenceAtIndex:kMaxLength - 1];
    return [[line substringToIndex:NSMaxRange(safe)] stringByAppendingString:@"…"];
}

void BarHost::showCandidates(const std::vector<vsuggest::Candidate>& candidates, const std::string& typed) {
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    for (const vsuggest::Candidate& c : candidates)
        [words addObject:BarText(c.text)];
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
    NSRect _lastLine;            //the line of the caret the bar is under, in Cocoa screen coordinates
    BOOL _anchorValid;
    BOOL _locating;              //the application is being asked where the caret is
    BOOL _locateAgain;           //the word changed meanwhile
    int _staleAnswers;           //answers in a row that described text from before the typing
    NSUInteger _generation;      //changes every time the bar is hidden, so late answers are ignored
    dispatch_queue_t _accessibilityQueue;
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
    return [support URLByAppendingPathComponent:VOK_DATA_DIR_NAME isDirectory:YES];
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
            @"VOpenKey AI - Từ điển gợi ý\n\n"
            @"Thả các file .txt vào thư mục này rồi vào Cài đặt > Gõ tắt > \"Tải lại từ điển\" (hoặc mở lại VOpenKey AI).\n"
            @"Mỗi dòng một mục, dùng phím Tab để ngăn cách chữ và số lần dùng:\n\n"
            @"    xin chào<TAB>3000          một từ và số lần dùng (có thể bỏ số)\n"
            @"    xin chào các bạn<TAB>20    nhiều từ: VOpenKey AI học từ nào hay đi sau từ nào\n"
            @"    # dòng bắt đầu bằng # là ghi chú\n\n"
            @"    thiết_kế<TAB>900           từ ghép (nối các âm tiết bằng dấu _): gõ liền \"thietke\" ra \"thiết kế\"\n"
            @"    #!compounds                từ dòng này trở xuống, nhiều từ trên một dòng là MỘT từ ghép, nên có thể viết\n"
            @"                               danh sách từ ghép bằng dấu cách; #!context để quay lại như cũ\n\n"
            @"\"Từ\" ở đây là một âm tiết giữa hai dấu cách. Không cần gõ đúng dấu: gõ \"hoc\" vẫn tìm ra \"học\".\n"
            @"Từ bạn gõ được VOpenKey AI học và lưu ở file learned.txt trong thư mục cha; xoá file đó để quên hết.\n"
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
                                                              @"SuggestionCompounds": @1, @"SuggestionTab": @1,
                                                              @"MacroConfirm": @1, @"SuggestionAppExclusionsEnabled": @YES}];
}

// Versioned separately: older releases treated SuggestionExcludedApps as additions
// to an immutable default list. Preserve those additions on the first migration.
+(NSArray<NSString*>*)excludedApps {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSArray* saved = [defaults arrayForKey:@"SuggestionExcludedAppsList"];
    if (saved == nil) {
        NSMutableOrderedSet* initial = [NSMutableOrderedSet orderedSetWithArray:DefaultExcludedApps()];
        [initial addObjectsFromArray:[defaults arrayForKey:kExcludedAppsKey] ?: @[]];
        saved = initial.array;
        [defaults setObject:saved forKey:@"SuggestionExcludedAppsList"];
    }
    return saved;
}

+(void)setExcludedApps:(NSArray<NSString*>*)identifiers {
    NSMutableOrderedSet* unique = [NSMutableOrderedSet orderedSet];
    for (NSString* identifier in identifiers) {
        if ([identifier isKindOfClass:NSString.class] && identifier.length > 0)
            [unique addObject:identifier];
    }
    [[NSUserDefaults standardUserDefaults] setObject:unique.array forKey:@"SuggestionExcludedAppsList"];
    [self reloadSettings];
}

+(NSString*)defaultNameForExcludedApp:(NSString*)identifier {
    NSDictionary* names = @{
        @"com.apple.Terminal": @"Terminal", @"com.googlecode.iterm2": @"iTerm2",
        @"com.mitchellh.ghostty": @"Ghostty", @"dev.warp.Warp-Stable": @"Warp",
        @"net.kovidgoyal.kitty": @"kitty", @"org.alacritty": @"Alacritty",
        @"co.zeit.hyper": @"Hyper", @"com.github.wez.wezterm": @"WezTerm",
    };
    return names[identifier] ?: identifier;
}

+(BOOL)appExclusionsEnabled {
    NSNumber* enabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"SuggestionAppExclusionsEnabled"];
    return enabled == nil || enabled.boolValue;
}

+(void)setAppExclusionsEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"SuggestionAppExclusionsEnabled"];
    [self reloadSettings];
}

+(BOOL)isAppIdentifierExcluded:(NSString*)identifier {
    return [self appExclusionsEnabled] && identifier.length > 0 && [[self excludedApps] containsObject:identifier];
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
    vMacroConfirm = (int)[defaults integerForKey:@"MacroConfirm"];

    _accessibilityQueue = dispatch_queue_create("vn.io.lssoft.vopenkey.suggestion.accessibility", DISPATCH_QUEUE_SERIAL);

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
    return [SuggestionController isAppIdentifierExcluded:app.bundleIdentifier];
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
    //The bar is also there for abbreviations alone (words off). Where it cannot be (Terminal...) they are replaced at once, as before.
    BOOL askAboutMacros = vUseMacro && vMacroConfirm && !_appExcluded;
    settings.enabled = (vSuggestEnabled && !_appExcluded) || askAboutMacros;
    settings.words = vSuggestEnabled && !_appExcluded;
    settings.nextWord = vSuggestNextWord;
    settings.learn = vSuggestLearn;
    settings.compounds = vSuggestCompounds;
    _session->setSettings(settings);
    vMacroNeedsConfirm = askAboutMacros;
}

#pragma mark - Called while typing

+(void)reloadSettings {
    SuggestionController* s = [self shared];
    if (s->_started) {
        s->_appExcluded = [s isExcluded:NSWorkspace.sharedWorkspace.frontmostApplication];
        [s resetState];
        [s applySettings];
    }
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

+(void)keyProcessed:(VOKSuggestionKey)key word:(NSString*)word raw:(NSString*)raw macro:(NSString*)macro {
    SuggestionController* s = [self shared];
    if (!s->_started || !s->_session->settings().enabled)
        return;
    vsuggest::KeyKind kind = key == VOKSuggestionKeySpace ? vsuggest::KeyKind::Space :
                             (key == VOKSuggestionKeyDelete ? vsuggest::KeyKind::Delete : vsuggest::KeyKind::Other);
    s->_session->keyProcessed(kind, word.UTF8String ?: "", raw.UTF8String ?: "", macro.UTF8String ?: "");
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
    if (!s->_session->accept((size_t)slot, word.UTF8String ?: "", acceptance)) {
        if (vDiagnostics) {
            size_t count = s->_session->candidateCount();
            if ((size_t)slot >= count) {
                VOKDiag(@"suggest", @"slot %ld pressed but the bar holds %lu suggestions: the key goes to the application", (long)slot, (unsigned long)count);
            } else {
                //lengths and the place where the two words part, never the words
                NSString* shown = ToNSString(s->_session->shownFor());
                NSUInteger common = 0;
                while (common < shown.length && common < word.length && [shown characterAtIndex:common] == [word characterAtIndex:common])
                    common++;
                VOKDiag(@"ANOMALY", @"SUGGESTION REFUSED: slot %ld pressed, the bar was made for a word of %lu characters, the word the engine "
                        "has now is %lu characters, they are the same for the first %lu: the key goes to the application and nothing is typed",
                        (long)slot, (unsigned long)shown.length, (unsigned long)word.length, (unsigned long)common);
            }
        }
        return NO;
    }
    *text = ToNSString(acceptance.text);
    *erase = acceptance.eraseCount;
    [s scheduleRefresh];
    return YES;
}

#pragma mark - The bar

//The bar goes under the line of the caret. That line is asked of the application after every change of the word, not
//once per word: the first answer may come before the application has drawn what was typed, and a line given once
//and kept would leave the bar on top of the line that is being typed (after a new line, for example).
-(void)showBarWithWords:(NSArray<NSString*>*)words typed:(NSString*)typed {
    if (!_panel)
        _panel = [[SuggestionPanel alloc] init];
    if (_lastWords == nil) {
        VOKDiag(@"suggest", @"bar shown with %lu suggestions", (unsigned long)words.count);
    }
    _lastWords = words;
    _lastTyped = typed;
    _panel.firstWordUsesTab = vSuggestTabAccepts != 0;
    [_panel setWords:words];
    if (_anchorValid) //where it was, until the application says where the line is now
        [_panel showBelowRect:_lastLine];
    [self requestLocation];
}

-(void)requestLocation {
    if (_locating) {
        _locateAgain = YES;
        return;
    }
    _locating = YES;
    _locateAgain = NO;
    NSUInteger generation = _generation;
    NSString* typed = _lastTyped ?: @"";
    pid_t pid = [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier;

    dispatch_async(_accessibilityQueue, ^{
        CaretLocation* location = [CaretLocator locateInProcess:pid word:typed];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_locating = NO;
            if (!self->_session->isShowing())
                return;
            //the bar was hidden, or the word has changed since: the answer is for something else
            if (generation != self->_generation || ![typed isEqualToString:self->_lastTyped ?: @""]) {
                if (self->_lastWords)
                    [self requestLocation];
                return;
            }
            [self placeBarFor:location typed:typed];
            if (self->_locateAgain)
                [self requestLocation];
        });
    });
}

-(void)placeBarFor:(CaretLocation*)location typed:(NSString*)typed {
    BOOL known = !NSIsEmptyRect(location.caret);
    if (known && (location.textMatches || !location.canCheckText)) {
        _lastLine = [CaretLocator lineForLocation:location typing:typed.length > 0];
        _anchorValid = YES;
        _staleAnswers = 0;
        [_panel showBelowRect:_lastLine];
        return;
    }
    if (known && _staleAnswers < 5) {
        //the application still describes the text from before: the bar stays where it was (or stays hidden), and asks again
        _staleAnswers++;
        NSUInteger generation = _generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation == self->_generation && self->_lastWords)
                [self requestLocation];
        });
        return;
    }
    _staleAnswers = 0;
    //no position for the caret: under the text field, which at least does not cover what is being typed in it...
    if (!NSIsEmptyRect(location.field)) {
        _lastLine = NSMakeRect(location.field.origin.x + 8, location.field.origin.y, 0, 0);
        _anchorValid = YES;
        [_panel showBelowRect:_lastLine];
        return;
    }
    //...and when even that is unknown, under the mouse pointer
    [_panel showNearPoint:[NSEvent mouseLocation]];
}

-(void)hideBar {
    if (_lastWords != nil) {
        VOKDiag(@"suggest", @"bar hidden");
    }
    _generation++;
    _anchorValid = NO;
    _locateAgain = NO;
    _staleAnswers = 0;
    _lastWords = nil;
    [_panel orderOut:nil];
}

@end
