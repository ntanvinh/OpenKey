//
//  OpenKey.m
//  OpenKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#import "Engine.h"
#import "AppDelegate.h"
#import "OpenKeyManager.h"
#import "SecureInputMonitor.h"
#import "SuggestionController.h"
#import "ShortcutRecorder.h"
#import "SuggestionKeys.h"
#import "AIAssistant.h"
#import "AISettings.h"
#import "SnippetPalette.h"
#import "SnippetInserter.h"
#import "CaseBar.h"
#import "WordRestore.h"
#import "Diagnostics.h"

#define FRONT_APP [[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier
#define OTHER_CONTROL_KEY (_flag & kCGEventFlagMaskCommand) || (_flag & kCGEventFlagMaskControl) || \
                            (_flag & kCGEventFlagMaskAlternate) || (_flag & kCGEventFlagMaskSecondaryFn) || \
                            (_flag & kCGEventFlagMaskNumericPad) || (_flag & kCGEventFlagMaskHelp)

#define DYNA_DATA(macro, pos) (macro ? pData->macroData[pos] : pData->charData[pos])
#define MAX_UNICODE_STRING  20
#define EMPTY_HOTKEY 0xFE0000FE
#define LOAD_DATA(VAR, KEY) VAR = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@#KEY]

// Ignore code for Modifier keys and numpad
// Reference: https://eastmanreference.com/complete-list-of-applescript-key-codes
NSDictionary *keyStringToKeyCodeMap = @{
    // Characters from number row
    @"`": @50, @"~": @50, @"1": @18, @"!": @18, @"2": @19, @"@": @19, @"3": @20, @"#": @20, @"4": @21, @"$": @21,
    @"5": @23, @"%": @23, @"6": @22, @"^": @22, @"7": @26, @"&": @26, @"8": @28, @"*": @28, @"9": @25, @"(": @25,
    @"0": @29, @")": @29, @"-": @27, @"_": @27, @"=": @24, @"+": @24,
    // Characters from first keyboard row
    @"q": @12, @"w": @13, @"e": @14, @"r": @15, @"t": @17, @"y": @16, @"u": @32, @"i": @34, @"o": @31, @"p": @35,
    @"[": @33, @"{": @33, @"]": @30, @"}": @30, @"\\": @42, @"|": @42,
    // Characters from second keyboard row
    @"a": @0, @"s": @1, @"d": @2, @"f": @3, @"g": @5, @"h": @4, @"j": @38, @"k": @40, @"l": @37,
    @";": @41, @":": @41, @"'": @39, @"\"": @39,
    // Characters from second third row
    @"z": @6, @"x": @7, @"c": @8, @"v": @9, @"b": @11, @"n": @45, @"m": @46,
    @",": @43, @"<": @43, @".": @47, @">": @47, @"/": @44, @"?": @44
};

extern AppDelegate* appDelegate;
extern int vSendKeyStepByStep;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;

extern "C" {
    //app which must sent special empty character
    NSArray* _niceSpaceApp = @[@"com.sublimetext.3",
                               @"com.sublimetext.2",
                             ];
    
    //app which error with unicode Compound
    NSArray* _unicodeCompoundApp = @[@"com.apple.",
                                     @"com.google.Chrome", @"com.brave.Browser",
                                     @"com.microsoft.edgemac.Dev", @"com.microsoft.edgemac.Beta", @"com.microsoft.Edge.Dev", @"com.microsoft.Edge"];
    NSArray* _recommendWorkaroundDisabledApp = @[@"com.apple.Spotlight"];
    
    CGEventSourceRef myEventSource = NULL;
    vKeyHookState* pData;
    CGEventRef eventBackSpaceDown;
    CGEventRef eventBackSpaceUp;
    UniChar _newChar, _newCharHi;
    CGEventRef _newEventDown, _newEventUp;
    CGKeyCode _keycode;
    CGEventFlags _flag, _lastFlag = 0, _privateFlag;
    CGEventTapProxy _proxy;
    
    Uint16 _newCharString[MAX_UNICODE_STRING];
    Uint16 _newCharSize;
    bool _willContinuteSending = false;
    bool _willSendControlKey = false;
    
    vector<Uint16> _syncKey;
    
    Uint16 _uniChar[2];
    int _i, _j, _k;
    Uint32 _tempChar;
    bool _hasJustUsedHotKey = false;
    int _swallowedKeyCode = -1; //key that chose a suggestion: its key up and key repeats must not reach the application either
    bool _optionTabRewritten = false; //a ⌥Tab was turned into a Tab: its key up gets the same treatment

    int _languageTemp = 0; //use for smart switch key
    vector<Byte> savedSmartSwitchKeyData; ////use for smart switch key
    
    NSString* _frontMostApp = @"UnknownApp";

    //The key events of the typing all come from one private event source, and such a source remembers the modifier flags of what was
    //posted with it. After a ⌘V (the snippets, the AI assistant, the case list) it went on making events that carry ⌘, until an event
    //without modifiers was posted (measured on macOS 15). A text event with ⌘ is a shortcut, not text, and Shift+Left with ⌘ selects
    //the whole line. So the events made here never keep the modifiers of the source.
    static const CGEventFlags kModifierFlags = kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate |
                                               kCGEventFlagMaskCommand | kCGEventFlagMaskSecondaryFn;

    CGEventFlags WithoutModifiers(CGEventFlags flags, const char* what) {
        if (flags & kModifierFlags) {
            VOKDiag(@"ANOMALY", @"FLAGS: a %s event of the typing source carried modifier flags 0x%llx, cleared", what, (unsigned long long)flags);
        }
        return flags & ~kModifierFlags;
    }

    void CleanEventFlags(CGEventRef down, CGEventRef up, const char* what) {
        CGEventFlags flags = CGEventGetFlags(down);
        if (flags & kModifierFlags) {
            CGEventSetFlags(down, WithoutModifiers(flags, what));
        }
        flags = CGEventGetFlags(up);
        if (flags & kModifierFlags) {
            CGEventSetFlags(up, flags & ~kModifierFlags);
        }
    }

    NSString* EventTypeName(CGEventType type) {
        switch (type) {
            case kCGEventKeyDown: return @"key down";
            case kCGEventKeyUp: return @"key up";
            case kCGEventFlagsChanged: return @"modifier";
            case kCGEventScrollWheel: return @"scroll";
            case kCGEventLeftMouseDown: case kCGEventLeftMouseUp: case kCGEventRightMouseDown:
            case kCGEventLeftMouseDragged: case kCGEventRightMouseDragged: return @"mouse";
            default: return [NSString stringWithFormat:@"type %d", (int)type];
        }
    }

    void RequestNewSession();
    bool OverlayHasKeyboard();

    void OpenKeyInit() {
        //load saved data
        vFreeMark = 0;//(int)[[NSUserDefaults standardUserDefaults] integerForKey:@"FreeMark"];
        LOAD_DATA(vCodeTable, CodeTable); if (vCodeTable < 0) vCodeTable = 0;
        LOAD_DATA(vCheckSpelling, Spelling);
        LOAD_DATA(vQuickTelex, QuickTelex);
        LOAD_DATA(vUseModernOrthography, ModernOrthography);
        LOAD_DATA(vRestoreIfWrongSpelling, RestoreIfInvalidWord);
        LOAD_DATA(vFixRecommendBrowser, FixRecommendBrowser);
        LOAD_DATA(vUseMacro, UseMacro);
        LOAD_DATA(vUseMacroInEnglishMode, UseMacroInEnglishMode);
        LOAD_DATA(vAutoCapsMacro, vAutoCapsMacro);
        LOAD_DATA(vSendKeyStepByStep, SendKeyStepByStep);
        LOAD_DATA(vUseSmartSwitchKey, UseSmartSwitchKey);
        LOAD_DATA(vUpperCaseFirstChar, UpperCaseFirstChar);
        
        LOAD_DATA(vTempOffSpelling, vTempOffSpelling);
        LOAD_DATA(vAllowConsonantZFWJ, vAllowConsonantZFWJ);
        LOAD_DATA(vQuickEndConsonant, vQuickEndConsonant);
        LOAD_DATA(vQuickStartConsonant, vQuickStartConsonant);
        LOAD_DATA(vRememberCode, vRememberCode);
        LOAD_DATA(vOtherLanguage, vOtherLanguage);
        LOAD_DATA(vTempOffOpenKey, vTempOffOpenKey);
        
        LOAD_DATA(vFixChromiumBrowser, vFixChromiumBrowser);
        
        LOAD_DATA(vPerformLayoutCompat, vPerformLayoutCompat);
        
        myEventSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
        pData = (vKeyHookState*)vKeyInit();

        //the log: every minute it writes where the typing stands, and notes two things that break typing without any error
        [VOKDiagnostics setSnapshotProvider:^NSString*{
            NSString* source = [VOKDiagnostics currentInputSourceID];
            if (vLanguage == 1 && [source hasPrefix:@"com.apple.inputmethod.VietnameseIM"]) {
                VOKDiag(@"ANOMALY", @"DOUBLE CONVERSION: VOpenKey AI is in Vietnamese mode and macOS has its own Vietnamese input source selected "
                        "(%@), so what is typed is converted twice", source);
            }
            CGEventFlags probeFlags = 0;
            CGEventRef probe = myEventSource != NULL ? CGEventCreateKeyboardEvent(myEventSource, 0, true) : NULL;
            if (probe != NULL) {
                probeFlags = CGEventGetFlags(probe);
                CFRelease(probe);
            }
            if (probeFlags & kModifierFlags) {
                VOKDiag(@"ANOMALY", @"FLAGS: a new event of the typing source already carries modifier flags 0x%llx", (unsigned long long)probeFlags);
            }
            return [NSString stringWithFormat:@"language=%d table=%d type=%d suggest=%d fixRecommend=%d restore=%d spelling=%d stepByStep=%d sourceFlags=0x%llx",
                    vLanguage, vCodeTable, vInputType, vSuggestEnabled, vFixRecommendBrowser, vRestoreIfWrongSpelling, vCheckSpelling,
                    vSendKeyStepByStep, (unsigned long long)probeFlags];
        }];

        //the ⌘V that pastes a snippet is ours: the tap leaves it alone like the keys it sends itself
        [SnippetInserter useEventSource:myEventSource];
        //what is typed in the snippet window must not become part of the next word typed in another application
        void (^typingBoundary)(void) = ^{
            RequestNewSession();
            [SuggestionController reset];
        };
        [SnippetPalette setTypingBoundaryHandler:typingBoundary];
        [AIAssistant setTypingBoundaryHandler:typingBoundary];
        [CaseBar setTypingBoundaryHandler:typingBoundary];
        [CaseBar setBlockedCheck:^BOOL{ return OverlayHasKeyboard(); }];

        eventBackSpaceDown = CGEventCreateKeyboardEvent (myEventSource, 51, true);
        eventBackSpaceUp = CGEventCreateKeyboardEvent (myEventSource, 51, false);
        
        //init and load macro data
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        NSData *data = [prefs objectForKey:@"macroData"];
        initMacroMap((Byte*)data.bytes, (int)data.length);
        
        //init and load smart switch key data
        data = [prefs objectForKey:@"smartSwitchKey"];
        initSmartSwitchKey((Byte*)data.bytes, (int)data.length);
        
        //init convert tool
        convertToolDontAlertWhenCompleted = ![prefs boolForKey:@"convertToolDontAlertWhenCompleted"];
        convertToolToAllCaps = [prefs boolForKey:@"convertToolToAllCaps"];
        convertToolToAllNonCaps = [prefs boolForKey:@"convertToolToAllNonCaps"];
        convertToolToCapsFirstLetter = [prefs boolForKey:@"convertToolToCapsFirstLetter"];
        convertToolToCapsEachWord = [prefs boolForKey:@"convertToolToCapsEachWord"];
        convertToolRemoveMark = [prefs boolForKey:@"convertToolRemoveMark"];
        convertToolFromCode = [prefs integerForKey:@"convertToolFromCode"];
        convertToolToCode = [prefs integerForKey:@"convertToolToCode"];
        convertToolHotKey = (int)[prefs integerForKey:@"convertToolHotKey"];
        if (convertToolHotKey == 0) {
            convertToolHotKey = EMPTY_HOTKEY;
        }
    }
    
    void RequestNewSession() {
        //send event signal to Engine
        vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
            _syncKey.clear();
        }
    }
    
    void queryFrontMostApp() {
        if ([[[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier compare:OPENKEY_BUNDLE] != 0) {
            _frontMostApp = [[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier;
            if (_frontMostApp == nil)
                _frontMostApp = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName != nil ?
                [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName : @"UnknownApp";
        }
    }
    
    NSString* ConvertUtil(NSString* str) {
        return [NSString stringWithUTF8String:convertUtil([str UTF8String]).c_str()];
    }
    
    BOOL containUnicodeCompoundApp(NSString* topApp) {
        if (topApp == nil) return false;
        for (_j = 0; _j < [_unicodeCompoundApp count]; _j++) {
            if ([topApp hasPrefix:[_unicodeCompoundApp objectAtIndex:_j]] || [[_unicodeCompoundApp objectAtIndex:_j] isEqualToString:topApp])
                return true;
        }
        return false;
    }

    //Asking the window server for the windows costs 2 ms on average and up to 40 ms on a busy Mac, and one key press asks more than once
    //(the invisible character, the selection, a macro, a suggestion). The answer is kept for the length of one call of the callback, in which
    //nothing can change it, and forgotten when the call ends: the next key asks again, so Spotlight is noticed as quickly as before.
    static int _spotlightMemo = -1; //-1 not asked in this call, 0 no, 1 yes

    BOOL isSpotlightVisible() {
        if (_spotlightMemo >= 0)
            return _spotlightMemo != 0;
        BOOL found = false;
        NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                                        kCGNullWindowID));
        for (NSDictionary *window in windows) {
            if ([[window objectForKey:(__bridge NSString *)kCGWindowOwnerName] isEqualToString:@"Spotlight"]) {
                found = true;
                break;
            }
        }
        _spotlightMemo = found ? 1 : 0;
        return found;
    }

    BOOL shouldUseRecommendWorkaround(NSString* topApp) {
        if (!vFixRecommendBrowser) return false;
        if (isSpotlightVisible()) return false;
        if (topApp == nil) return true;
        return ![_recommendWorkaroundDisabledApp containsObject:topApp];
    }

    BOOL shouldUseSelectionReplacement(NSString* topApp) {
        return isSpotlightVisible() || [_recommendWorkaroundDisabledApp containsObject:topApp];
    }
    
    void saveSmartSwitchKeyData() {
        getSmartSwitchKeySaveData(savedSmartSwitchKeyData);
        NSData* _data = [NSData dataWithBytes:savedSmartSwitchKeyData.data() length:savedSmartSwitchKeyData.size()];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setObject:_data forKey:@"smartSwitchKey"];
    }
    
    //What was remembered for each application (language and code table), for the Settings window to show and edit.
    //Each item: @"id" the bundle identifier, @"value" language | (code table << 1)
    NSArray<NSDictionary*>* RememberedApps() {
        vector<pair<string, int>> all;
        getAllAppInputMethodStatus(all);
        NSMutableArray* items = [NSMutableArray array];
        for (const auto& app : all) {
            [items addObject:@{@"id": [NSString stringWithUTF8String:app.first.c_str()] ?: @"", @"value": @(app.second)}];
        }
        return items;
    }

    void SetRememberedApp(NSString* bundleId, int value) {
        setAppInputMethodStatus(string(bundleId.UTF8String), value);
        saveSmartSwitchKeyData();
    }

    void ForgetRememberedApp(NSString* bundleId) {
        removeAppInputMethodStatus(string(bundleId.UTF8String));
        saveSmartSwitchKeyData();
    }

    void OnActiveAppChanged() { //use for smart switch key; improved on Sep 28th, 2019
        queryFrontMostApp();
        _languageTemp = getAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
        VOKDiag(@"app", @"active app %@: remembered %d, language was %d", _frontMostApp, _languageTemp, vLanguage);
        if ((_languageTemp & 0x01) != vLanguage) { //for input method
            if (_languageTemp != -1) {
                vLanguage = _languageTemp;
                [appDelegate onImputMethodChanged:NO];
                startNewSession();
            } else {
                saveSmartSwitchKeyData();
            }
        }
        if (vRememberCode && (_languageTemp >> 1) != vCodeTable) { //for remember table code feature
            if (_languageTemp != -1) {
                [appDelegate onCodeTableChanged:(_languageTemp >> 1)];
            } else {
                saveSmartSwitchKeyData();
            }
        }
    }
    
    void OnTableCodeChange() {
        onTableCodeChange();
        if (vRememberCode) {
            queryFrontMostApp();
            setAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
            saveSmartSwitchKeyData();
        }
    }
    
    void OnInputMethodChanged() {
        if (vUseSmartSwitchKey) {
            queryFrontMostApp();
            setAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
            saveSmartSwitchKeyData();
        }
    }
    
    void OnSpellCheckingChanged() {
        vSetCheckSpelling();
    }
    
    void InsertKeyLength(const Uint8& len) {
        _syncKey.push_back(len);
    }
    
    void SendPureCharacter(const Uint16& ch) {
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, 1, &ch);
        CGEventKeyboardSetUnicodeString(_newEventUp, 1, &ch);
        CleanEventFlags(_newEventDown, _newEventUp, "text");
        CGEventTapPostEvent(_proxy, _newEventDown);
        CGEventTapPostEvent(_proxy, _newEventUp);
        VOKDiagPosted(VOKEventKindText, 1);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
        if (IS_DOUBLE_CODE(vCodeTable)) {
            InsertKeyLength(1);
        }
    }
    
    void SendKeyCode(Uint32 data) {
        _newChar = (Uint16)data;
        if (!(data & CHAR_CODE_MASK)) {
            if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                InsertKeyLength(1);
            
            _newEventDown = CGEventCreateKeyboardEvent(myEventSource, _newChar, true);
            _newEventUp = CGEventCreateKeyboardEvent(myEventSource, _newChar, false);
            _privateFlag = WithoutModifiers(CGEventGetFlags(_newEventDown), "key");
            
            if (data & CAPS_MASK) {
                _privateFlag |= kCGEventFlagMaskShift;
            } else {
                _privateFlag &= ~kCGEventFlagMaskShift;
            }
            _privateFlag |= kCGEventFlagMaskNonCoalesced;
            
            CGEventSetFlags(_newEventDown, _privateFlag);
            CGEventSetFlags(_newEventUp, _privateFlag);
            CGEventTapPostEvent(_proxy, _newEventDown);
            CGEventTapPostEvent(_proxy, _newEventUp);
        } else {
            if (vCodeTable == 0) { //unicode 2 bytes code
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
                CleanEventFlags(_newEventDown, _newEventUp, "text");
                CGEventTapPostEvent(_proxy, _newEventDown);
                CGEventTapPostEvent(_proxy, _newEventUp);
                VOKDiagPosted(VOKEventKindText, 1);
            } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                _newCharHi = HIBYTE(_newChar);
                _newChar = LOBYTE(_newChar);
                
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
                CleanEventFlags(_newEventDown, _newEventUp, "text");
                CGEventTapPostEvent(_proxy, _newEventDown);
                CGEventTapPostEvent(_proxy, _newEventUp);
                if (_newCharHi > 32) {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(2);
                    CFRelease(_newEventDown);
                    CFRelease(_newEventUp);
                    _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                    _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                    CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newCharHi);
                    CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newCharHi);
                    CleanEventFlags(_newEventDown, _newEventUp, "text");
                    CGEventTapPostEvent(_proxy, _newEventDown);
                    CGEventTapPostEvent(_proxy, _newEventUp);
                } else {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(1);
                }
            } else if (vCodeTable == 3) { //Unicode Compound
                _newCharHi = (_newChar >> 13);
                _newChar &= 0x1FFF;
                _uniChar[0] = _newChar;
                _uniChar[1] = _newCharHi > 0 ? (_unicodeCompoundMark[_newCharHi - 1]) : 0;
                InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, (_newCharHi > 0 ? 2 : 1), _uniChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, (_newCharHi > 0 ? 2 : 1), _uniChar);
                CleanEventFlags(_newEventDown, _newEventUp, "text");
                CGEventTapPostEvent(_proxy, _newEventDown);
                CGEventTapPostEvent(_proxy, _newEventUp);
            }
        }
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
    }
    
    void SendEmptyCharacter() {
        if (IS_DOUBLE_CODE(vCodeTable)) //VNI or Unicode Compound
            InsertKeyLength(1);
        
        _newChar = 0x202F; //empty char
        if ([_niceSpaceApp containsObject:FRONT_APP]) {
            _newChar = 0x200C; //Unicode character with empty space
        }
        
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
        CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
        CleanEventFlags(_newEventDown, _newEventUp, "empty character");
        CGEventTapPostEvent(_proxy, _newEventDown);
        CGEventTapPostEvent(_proxy, _newEventUp);
        VOKDiagPosted(VOKEventKindEmptyChar, 1);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
    }
    
    void SendVirtualKey(const Byte& vKey) {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, vKey, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, vKey, false);
        CleanEventFlags(eventVkeyDown, eventVkeyUp, "key");
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }

    void SendBackspace() {
        CGEventTapPostEvent(_proxy, eventBackSpaceDown);
        CGEventTapPostEvent(_proxy, eventBackSpaceUp);
        VOKDiagPosted(VOKEventKindBackspace, 1);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
                    CGEventTapPostEvent(_proxy, eventBackSpaceDown);
                    CGEventTapPostEvent(_proxy, eventBackSpaceUp);
                    VOKDiagPosted(VOKEventKindBackspace, 1);
                }
            }
            _syncKey.pop_back();
        }
    }
    
    void SendShiftAndLeftArrow() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, false);
        _privateFlag = WithoutModifiers(CGEventGetFlags(eventVkeyDown), "Shift+Left");
        _privateFlag |= kCGEventFlagMaskShift;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
                    CGEventTapPostEvent(_proxy, eventVkeyDown);
                    CGEventTapPostEvent(_proxy, eventVkeyUp);
                }
            }
            _syncKey.pop_back();
        }
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    void SendCutKey() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_X, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_X, false);
        _privateFlag = WithoutModifiers(CGEventGetFlags(eventVkeyDown), "Cut");
        _privateFlag |= NX_COMMANDMASK;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    void SendNewCharString(const bool& dataFromMacro=false, const Uint16& offset=0) {
        _j = 0;
        _newCharSize = dataFromMacro ? pData->macroData.size() : pData->newCharCount;
        _willContinuteSending = false;
        _willSendControlKey = false;
        
        if (_newCharSize > 0) {
            for (_k = dataFromMacro ? offset : pData->newCharCount - 1 - offset;
                 dataFromMacro ? _k < pData->macroData.size() : _k >= 0;
                 dataFromMacro ? _k++ : _k--) {
                
                if (_j >= 16) {
                    _willContinuteSending = true;
                    break;
                }
                
                _tempChar = DYNA_DATA(dataFromMacro, _k);
                if (_tempChar & PURE_CHARACTER_MASK) {
                    _newCharString[_j++] = _tempChar;
                    if (IS_DOUBLE_CODE(vCodeTable)) {
                        InsertKeyLength(1);
                    }
                } else if (!(_tempChar & CHAR_CODE_MASK)) {
                    if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                        InsertKeyLength(1);
                    _newCharString[_j++] = keyCodeToCharacter(_tempChar);
                } else {
                    if (vCodeTable == 0) {  //unicode 2 bytes code
                        _newCharString[_j++] = _tempChar;
                    } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                        _newChar = _tempChar;
                        _newCharHi = HIBYTE(_newChar);
                        _newChar = LOBYTE(_newChar);
                        _newCharString[_j++] = _newChar;
                        
                        if (_newCharHi > 32) {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(2);
                            _newCharString[_j++] = _newCharHi;
                            _newCharSize++;
                        } else {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(1);
                        }
                    } else if (vCodeTable == 3) { //Unicode Compound
                        _newChar = _tempChar;
                        _newCharHi = (_newChar >> 13);
                        _newChar &= 0x1FFF;
                        
                        InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                        _newCharString[_j++] = _newChar;
                        if (_newCharHi > 0) {
                            _newCharSize++;
                            _newCharString[_j++] = _unicodeCompoundMark[_newCharHi - 1];
                        }
                        
                    }
                }
            }//end for
        }
        
        if (!_willContinuteSending && (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)) { //if is restore
            if (keyCodeToCharacter(_keycode) != 0) {
                _newCharSize++;
                _newCharString[_j++] = keyCodeToCharacter(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
            } else {
                _willSendControlKey = true;
            }
        }
        if (!_willContinuteSending && pData->code == vRestoreAndStartNewSession) {
            startNewSession();
        }
        
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, _willContinuteSending ? 16 : _newCharSize - offset, _newCharString);
        CGEventKeyboardSetUnicodeString(_newEventUp, _willContinuteSending ? 16 : _newCharSize - offset, _newCharString);
        CleanEventFlags(_newEventDown, _newEventUp, "text");
        CGEventTapPostEvent(_proxy, _newEventDown);
        CGEventTapPostEvent(_proxy, _newEventUp);
        if ((_willContinuteSending ? 16 : _newCharSize - offset) > 0 && vCodeTable == 0) {
            VOKDiagPosted(VOKEventKindText, 1);
        }
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);

        if (_willContinuteSending) {
            SendNewCharString(dataFromMacro, dataFromMacro ? _k : 16);
        }
        
        //the case when hCode is vRestore or vRestoreAndStartNewSession, the word is invalid and last key is control key such as TAB, LEFT ARROW, RIGHT ARROW,...
        if (_willSendControlKey) {
            SendKeyCode(_keycode);
        }
    }
            
    bool checkHotKey(int hotKeyData, bool checkKeyCode=true) {
        if ((hotKeyData & (~0x8000)) == EMPTY_HOTKEY)
            return false;
        if (HAS_CONTROL(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskControl))
            return false;
        if (HAS_OPTION(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskAlternate))
            return false;
        if (HAS_COMMAND(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskCommand))
            return false;
        if (HAS_SHIFT(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskShift))
            return false;
        if (checkKeyCode) {
            if (GET_SWITCH_KEY(hotKeyData) != _keycode)
                return false;
        }
        return true;
    }
    
    void switchLanguage() {
        if (vLanguage == 0)
            vLanguage = 1;
        else
            vLanguage = 0;
        if (HAS_BEEP(vSwitchKeyStatus))
            NSBeep();
        [appDelegate onImputMethodChanged:YES];
        startNewSession();
        [SuggestionController reset];
        VOKDiag(@"language", @"switched with the shortcut: language now %d, app %@", vLanguage, FRONT_APP);
    }
    
    //Opens the snippet window, or closes it when it is open. Not inside the callback: the tap must answer at once.
    void openSnippetPalette() {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SnippetPalette toggle];
        });
    }

    //The windows that take the keyboard from the typing engine: the snippets and the AI assistant. While one is open the keys are
    //for it: no suggestions, no restore shortcut.
    bool OverlayHasKeyboard() {
        return [SnippetPalette isVisible] || [AIAssistant isVisible];
    }

    //Opens the list that changes the case of the selection, or closes it when it is open. Not inside the callback.
    void openCaseBar() {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CaseBar toggle];
        });
    }

    //Opens the AI assistant, or closes it when it is open. Not inside the callback: the tap must answer at once.
    void openAIAssistant() {
        dispatch_async(dispatch_get_main_queue(), ^{
            [AIAssistant toggle];
        });
    }

    void handleMacro() {
        //fix autocomplete
        if (shouldUseRecommendWorkaround(FRONT_APP)) {
            SendEmptyCharacter();
            pData->backspaceCount++;
        }
        
        //send backspace
        if (pData->backspaceCount > 0) {
            for (int i = 0; i < pData->backspaceCount; i++) {
                SendBackspace();
            }
        }
        //send real data
        if (!vSendKeyStepByStep) {
            SendNewCharString(true);
        } else {
            for (int i = 0; i < pData->macroData.size(); i++) {
                if (pData->macroData[i] & PURE_CHARACTER_MASK) {
                    SendPureCharacter(pData->macroData[i]);
                } else {
                    SendKeyCode(pData->macroData[i]);
                }
            }
        }
        SendKeyCode(_keycode | (_flag & kCGEventFlagMaskShift ? CAPS_MASK : 0));
    }

    //The word being typed, as the typing engine has it (empty if none). Only meaningful with the Unicode table.
    NSString* CurrentTypingWord() {
        Uint16 buffer[MAX_BUFF];
        int length = vGetTypingWord(buffer, MAX_BUFF);
        return length > 0 ? [NSString stringWithCharacters:buffer length:length] : @"";
    }

    //The full text of the abbreviation being typed, when the user has to confirm it (nil when it is none, or replaced at once)
    NSString* CurrentMacroOffer() {
        if (!vMacroNeedsConfirm || !vUseMacro)
            return nil;
        static Uint16 buffer[65536]; //a macro is at most 65535 bytes long
        int length = vPeekMacro(buffer, 65536);
        return length > 0 ? [NSString stringWithCharacters:buffer length:length] : nil;
    }

    //The keys pressed for the word being typed, before Telex/VNI changed them ("hoso" when the screen shows an accent)
    NSString* CurrentRawTypingWord() {
        Uint16 buffer[MAX_BUFF];
        int length = vGetTypingRawWord(buffer, MAX_BUFF);
        return length > 0 ? [NSString stringWithCharacters:buffer length:length] : @"";
    }

    //Replaces the word that was typed with the chosen suggestion
    void SendSuggestionText(NSString* text, NSUInteger eraseCount) {
        //same preparation as for a macro: the address bar of a browser may have added a proposal
        //that the first backspace would remove instead of a letter
        if (eraseCount > 0 && shouldUseRecommendWorkaround(FRONT_APP)) {
            SendEmptyCharacter();
            eraseCount++;
        }
        for (NSUInteger i = 0; i < eraseCount; i++) {
            SendBackspace();
        }
        NSUInteger length = text.length;
        UniChar chunk[16];
        for (NSUInteger start = 0; start < length; start += 16) {
            NSUInteger count = MIN((NSUInteger)16, length - start);
            [text getCharacters:chunk range:NSMakeRange(start, count)];
            CGEventRef down = CGEventCreateKeyboardEvent(myEventSource, 0, true);
            CGEventRef up = CGEventCreateKeyboardEvent(myEventSource, 0, false);
            CGEventKeyboardSetUnicodeString(down, count, chunk);
            CGEventKeyboardSetUnicodeString(up, count, chunk);
            CleanEventFlags(down, up, "suggestion text");
            CGEventTapPostEvent(_proxy, down);
            CGEventTapPostEvent(_proxy, up);
            VOKDiagPosted(VOKEventKindText, 1);
            CFRelease(down);
            CFRelease(up);
        }
    }

    // TODO: Research API to convert character into CGKeyCode more elegantly!
    int ConvertKeyStringToKeyCode(NSString *keyString, CGKeyCode fallback) {
        // Infomation about capitalization (shift/caps) is already included
        // in the original CGEvent, only find out which position on keyboard a key is pressed
        NSString *lowercasedKeyString = [keyString lowercaseString];
        if (!lowercasedKeyString) {
            return fallback;
        }
        
        NSNumber *keycode = [keyStringToKeyCodeMap objectForKey:lowercasedKeyString];

        if (keycode) {
            return [keycode intValue];
        }
        return fallback;
    }

    // If conversion fails, return fallbackKeyCode
    CGKeyCode ConvertEventToKeyboadLayoutCompatKeyCode(CGEventRef keyEvent, CGKeyCode fallbackKeyCode) {
        NSEvent *kbLayoutCompatEvent = [NSEvent eventWithCGEvent:keyEvent];
        NSString *kbLayoutCompatKeyString = kbLayoutCompatEvent.charactersIgnoringModifiers;
        return ConvertKeyStringToKeyCode(kbLayoutCompatKeyString,
                                         fallbackKeyCode);
    }

    //Sends what the typing engine answered when it has replaced characters (code "process", and the two restores): deletes the
    //characters that are to go and types the new ones. Uses the key of the event, _keycode, only for the restores that end a word.
    void sendEngineResult() {
        //for the log: what the engine asked for (the numbers are changed below) and how it was carried out
        const int engineCode = pData->code, engineBackspaces = pData->backspaceCount, engineNew = pData->newCharCount, engineExt = pData->extCode;
        bool usedEmptyChar = false, usedShiftLeft = false, usedSelection = false;
        if (vDiagnostics) {
            if (engineCode == vWillProcess && engineBackspaces > 0 && engineNew == 0) {
                VOKDiag(@"ANOMALY", @"ENGINE: asks to delete %d characters and to type none, the text on screen would only get shorter", engineBackspaces);
            }
            if (engineBackspaces >= MAX_BUFF || engineNew > MAX_BUFF) {
                VOKDiag(@"ANOMALY", @"ENGINE: numbers out of range (delete %d, type %d), the engine and the screen are not the same word", engineBackspaces, engineNew);
            }
        }
        //fix autocomplete
        if (shouldUseRecommendWorkaround(FRONT_APP) && pData->extCode != 4) {
            if (vFixChromiumBrowser && [_unicodeCompoundApp containsObject:FRONT_APP]) {
                if (pData->backspaceCount > 0) {
                    SendShiftAndLeftArrow();
                    usedShiftLeft = true;
                    if (pData->backspaceCount == 1)
                        pData->backspaceCount--;
                }
            } else {
                SendEmptyCharacter();
                usedEmptyChar = true;
                pData->backspaceCount++;
            
            }
        }

        if (shouldUseSelectionReplacement(FRONT_APP) && pData->backspaceCount > 0) {
            usedSelection = true;
            for (_i = 0; _i < pData->backspaceCount; _i++) {
                SendShiftAndLeftArrow();
            }
            pData->backspaceCount = 0;
        }
        
        //send backspace
        if (pData->backspaceCount > 0 && pData->backspaceCount < MAX_BUFF) {
            for (_i = 0; _i < pData->backspaceCount; _i++) {
                SendBackspace();
            }
        }
        
        //send new character
        if (!vSendKeyStepByStep) {
            SendNewCharString();
        } else {
            if (pData->newCharCount > 0 && pData->newCharCount <= MAX_BUFF) {
                for (int i = pData->newCharCount - 1; i >= 0; i--) {
                    SendKeyCode(pData->charData[i]);
                }
            }
            if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession) {
                SendKeyCode(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
            }
            if (pData->code == vRestoreAndStartNewSession) {
                startNewSession();
            }
        }

        if (vDiagnostics) {
            NSString* source = [VOKDiagnostics currentInputSourceID];
            VOKDiag(@"inject", @"engine code=%d delete=%d type=%d ext=%d word=%lu emptyChar=%d shiftLeft=%d selection=%d table=%d stepByStep=%d app=%@ source=%@",
                    engineCode, engineBackspaces, engineNew, engineExt, (unsigned long)CurrentTypingWord().length, usedEmptyChar, usedShiftLeft,
                    usedSelection, vCodeTable, vSendKeyStepByStep, FRONT_APP, source);
            if ([source hasPrefix:@"com.apple.inputmethod.VietnameseIM"]) {
                VOKDiag(@"ANOMALY", @"DOUBLE CONVERSION: the engine replaced text while macOS has its own Vietnamese input source selected (%@)", source);
            }
        }
    }

    //The restore shortcut: gives back the keys typed for the word on screen ("rétỏe" -> "restore"). NO when there is nothing to
    //give back, then the key is left for the application.
    bool restoreTypingWord() {
        if (!vRestoreWord()) {
            VOKDiag(@"restore", @"restore shortcut: nothing to restore, the key goes to the application");
            return false;
        }
        VOKDiag(@"restore", @"restore shortcut: word restored");
        sendEngineResult();
        [SuggestionController reset]; //the word is no longer what the suggestion bar was looking at
        return true;
    }

    /**
     * MAIN HOOK entry, very important function.
     * MAIN Callback.
     */
    static CGEventRef OpenKeyCallbackImpl(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        //macOS turns an event tap off when it thinks it is stuck or after some user input, and OpenKey
        //silently stops working unless it is turned back on
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            VOKDiag(@"ANOMALY", @"TAP DISABLED by %@: macOS switched the event tap off, keys typed meanwhile were not converted and the engine may "
                    "no longer match the screen", type == kCGEventTapDisabledByTimeout ? @"timeout (the callback or the main thread was too slow)" : @"user input");
            //Keys typed while the tap was off were never seen, so the word the engine holds is not the word on the screen: the next tone would
            //delete letters that are not part of it. A new word starts, as after a mouse click; modifiers released unseen are forgotten too.
            RequestNewSession();
            [SuggestionController reset];
            _lastFlag = 0;
            _hasJustUsedHotKey = false;
            [OpenKeyManager reenableEventTap];
            return event;
        }

        //secure input is on and macOS' own Vietnamese input source is typing for us, converting here as well
        //would do it twice
        if ([SecureInputMonitor isFallbackActive]) {
            if ([SuggestionController isShowing]) {
                [SuggestionController reset];
            }
            if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged) {
                //keys only reach an event tap once secure input has been released
                [SecureInputMonitor secureInputMayHaveEnded];
            }
            return event;
        }

        //dont handle my event
        if (CGEventGetIntegerValueField(event, kCGEventSourceStateID) == CGEventSourceGetSourceStateID(myEventSource)) {
            return event;
        }

        //the wheel turns: the list that changes the case of the selection would be left behind where the text was
        if (type == kCGEventScrollWheel) {
            [CaseBar scrolled];
            return event;
        }

        //a field is waiting for the user to press a shortcut: the keys are for it, not for the language switch or the typing
        if (vRecordingShortcut) {
            return event;
        }
        
        _flag = CGEventGetFlags(event);
        _keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        //⌥Tab while the bar is up is a Tab that the bar does not take (to go on to the next field of a form). The Option is
        //taken off the key here, so the typing engine and the application both see an ordinary Tab
        bool tabForTheApplication = false;
        if (type == kCGEventKeyDown && VOK_SUGGESTION_ACTIVE && SuggestionIsOptionTab(_keycode, _flag) && [SuggestionController isShowing]) {
            _flag = SuggestionTakeOptionOff(event);
            _optionTabRewritten = true;
            tabForTheApplication = true;
        } else if (type == kCGEventKeyUp && _optionTabRewritten && _keycode == KEY_TAB) {
            SuggestionTakeOptionOff(event);
            _optionTabRewritten = false;
            return event;
        }

        if (_swallowedKeyCode >= 0 && (type == kCGEventKeyDown || type == kCGEventKeyUp)) {
            bool sameKey = _keycode == _swallowedKeyCode;
            if (type == kCGEventKeyUp && sameKey) {
                _swallowedKeyCode = -1;
                return NULL;
            }
            if (type == kCGEventKeyDown) {
                if (sameKey && CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0)
                    return NULL;
                _swallowedKeyCode = -1;
            }
        }
        
        if (type == kCGEventKeyDown && vPerformLayoutCompat) {
            // If conversion fail, use current keycode
           _keycode = ConvertEventToKeyboadLayoutCompatKeyCode(event, _keycode);
        }
        
        //switch language shortcut; convert hotkey
        if (type == kCGEventKeyDown) {
            bool isSnippetKey = vSnippetsEnabled && GET_SWITCH_KEY(vSnippetHotKey) == _keycode;
            bool isRestoreKey = GET_SWITCH_KEY(vRestoreHotKey) == _keycode;
            bool isAIKey = vAIEnabled && GET_SWITCH_KEY(vAIHotKey) == _keycode;
            bool isCaseKey = GET_SWITCH_KEY(vCaseBarHotKey) == _keycode;
            if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode && GET_SWITCH_KEY(convertToolHotKey) != _keycode && !isSnippetKey && !isRestoreKey && !isAIKey && !isCaseKey) {
                _lastFlag = 0;
            } else {
                if (GET_SWITCH_KEY(vSwitchKeyStatus) == _keycode && checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)){
                    switchLanguage();
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (GET_SWITCH_KEY(convertToolHotKey) == _keycode && checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)){
                    [appDelegate onQuickConvert];
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (isSnippetKey && checkHotKey(vSnippetHotKey)) {
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    openSnippetPalette();
                    return NULL;
                }
                if (isAIKey && checkHotKey(vAIHotKey)) {
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    openAIAssistant();
                    return NULL;
                }
                if (isCaseKey && checkHotKey(vCaseBarHotKey)) {
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    openCaseBar();
                    return NULL;
                }
                //restore the word being typed; with nothing to restore the key goes to the application (⌥Space is a space that does not break)
                if (isRestoreKey && vLanguage == 1 && checkHotKey(vRestoreHotKey) && !OverlayHasKeyboard()) {
                    _proxy = proxy;
                    if (restoreTypingWord()) {
                        _lastFlag = 0;
                        _hasJustUsedHotKey = true;
                        return NULL;
                    }
                }
                //the key of the snippet shortcut pressed with other modifiers (⌃⇧S) is an ordinary key, as it was before: without
                //this the modifiers still held would switch the language when released
                if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode && GET_SWITCH_KEY(convertToolHotKey) != _keycode)
                    _lastFlag = 0;
            }
            _hasJustUsedHotKey = _lastFlag != 0;
        } else if (type == kCGEventFlagsChanged) {
            if (_lastFlag == 0 || _lastFlag < _flag) {
                _lastFlag = _flag;
            } else if (_lastFlag > _flag)  {
                //check switch
                if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
                    _lastFlag = 0;
                    switchLanguage();
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)) {
                    _lastFlag = 0;
                    [appDelegate onQuickConvert];
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                //a snippet shortcut that is made of modifiers only, ⌃⇧ for example; one with a key is handled by the key
                if (vSnippetsEnabled && GET_SWITCH_KEY(vSnippetHotKey) == 0xFE && checkHotKey(vSnippetHotKey, false)) {
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    openSnippetPalette();
                    return NULL;
                }
                //an AI shortcut that is made of modifiers only
                if (vAIEnabled && GET_SWITCH_KEY(vAIHotKey) == 0xFE && checkHotKey(vAIHotKey, false)) {
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    openAIAssistant();
                    return NULL;
                }
                //a case list shortcut that is made of modifiers only
                if (GET_SWITCH_KEY(vCaseBarHotKey) == 0xFE && checkHotKey(vCaseBarHotKey, false)) {
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    openCaseBar();
                    return NULL;
                }
                //a restore shortcut that is made of modifiers only
                if (vLanguage == 1 && GET_SWITCH_KEY(vRestoreHotKey) == 0xFE && checkHotKey(vRestoreHotKey, false) && !OverlayHasKeyboard()) {
                    _proxy = proxy;
                    if (restoreTypingWord()) {
                        _lastFlag = 0;
                        _hasJustUsedHotKey = true;
                        return NULL;
                    }
                }
                //check temporarily turn off spell checking
                if (vTempOffSpelling && !_hasJustUsedHotKey && _lastFlag & kCGEventFlagMaskControl) {
                    vTempOffSpellChecking();
                }
                if (vTempOffOpenKey && !_hasJustUsedHotKey && _lastFlag & kCGEventFlagMaskCommand) {
                    vTempOffEngine();
                }
                _lastFlag = 0;
                _hasJustUsedHotKey = false;
            }
        }

        //the list that changes the case of the selected text: it watches the mouse for a selection being made, and takes ⌥1…⌥9
        //(and ↑ ↓ ↩ Esc when it was opened with the shortcut) while it is up
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
            [CaseBar mouseDown];
        } else if (type == kCGEventLeftMouseUp) {
            [CaseBar mouseUpWithClickCount:CGEventGetIntegerValueField(event, kCGMouseEventClickState) flags:_flag];
            return event;
        } else if (type == kCGEventKeyDown) {
            if ([CaseBar keyDown:(CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) flags:_flag]) {
                _swallowedKeyCode = (int)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode); //its key up and repeats too
                return NULL;
            }
        }

        // Also check correct event hooked
        if ((type != kCGEventKeyDown) && (type != kCGEventKeyUp) &&
            (type != kCGEventLeftMouseDown) && (type != kCGEventRightMouseDown) &&
            (type != kCGEventLeftMouseDragged) && (type != kCGEventRightMouseDragged))
            return event;
        
        _proxy = proxy;
        
        //If is in english mode
        if (vLanguage == 0) {
            if ([SuggestionController isShowing]) {
                [SuggestionController reset];
            }
            if (vUseMacro && vUseMacroInEnglishMode && type == kCGEventKeyDown) {
                vEnglishMode((type == kCGEventKeyDown ? vKeyEventState::KeyDown : vKeyEventState::MouseDown),
                             _keycode,
                             (_flag & kCGEventFlagMaskShift) || (_flag & kCGEventFlagMaskAlphaShift),
                             OTHER_CONTROL_KEY);
                
                if (pData->code == vReplaceMaro) { //handle macro in english mode
                    handleMacro();
                    return NULL;
                }
            }
            return event;
        }
        
        //handle mouse
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged) {
            RequestNewSession();
            [SuggestionController reset];
            return event;
        }

        //if "turn off Vietnamese when in other language" mode on
        if(vOtherLanguage){
            TISInputSourceRef isource = TISCopyCurrentKeyboardInputSource();
            if ( isource != NULL )
            {
                CFArrayRef languages = (CFArrayRef) TISGetInputSourceProperty(isource, kTISPropertyInputSourceLanguages);
                
                if (CFArrayGetCount(languages) > 0) {
                    CFStringRef langRef = (CFStringRef)CFArrayGetValueAtIndex(languages, 0);
                    NSString *currentLanguage = (__bridge NSString *)langRef;
                    if(![currentLanguage isLike:@"en"]){
                        return event;
                    }
                    CFRelease(langRef);
                    CFRelease(isource);
                }
            }
        }
        
        //Tab or ⌥1-5 chooses a suggestion from the bar
        if (type == kCGEventKeyDown && VOK_SUGGESTION_ACTIVE && !tabForTheApplication && [SuggestionController isShowing] && !OverlayHasKeyboard()) {
            int slot = SuggestionSlotForKey(_keycode, _flag, vSuggestTabAccepts != 0);
            if (slot >= 0) {
                NSString* suggestion = nil;
                NSUInteger eraseCount = 0;
                if ([SuggestionController acceptSlot:slot currentWord:CurrentTypingWord() text:&suggestion erase:&eraseCount]) {
                    VOKDiag(@"suggest", @"accepted slot %d: delete %lu, type %lu characters, app %@, source %@", slot, (unsigned long)eraseCount,
                            (unsigned long)suggestion.length, FRONT_APP, [VOKDiagnostics currentInputSourceID]);
                    SendSuggestionText(suggestion, eraseCount);
                    RequestNewSession(); //the word on screen is no longer what the typing engine has
                    _swallowedKeyCode = (int)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
                    return NULL;
                }
            }
        }

        //handle keyboard
        if (type == kCGEventKeyDown) {
            //send event signal to Engine
            vKeyHandleEvent(vKeyEvent::Keyboard,
                            vKeyEventState::KeyDown,
                            _keycode,
                            _flag & kCGEventFlagMaskShift ? 1 : (_flag & kCGEventFlagMaskAlphaShift ? 2 : 0),
                            OTHER_CONTROL_KEY);
            if (VOK_SUGGESTION_ACTIVE && !OverlayHasKeyboard()) { //the windows of the snippets and of the AI are not places to suggest words in
                VOKSuggestionKey kind = VOKSuggestionKeyOther;
                if (_keycode == KEY_SPACE && !(OTHER_CONTROL_KEY) && pData->code == vDoNothing) {
                    kind = VOKSuggestionKeySpace;
                } else if (_keycode == KEY_DELETE) {
                    kind = VOKSuggestionKeyDelete;
                }
                [SuggestionController keyProcessed:kind word:CurrentTypingWord() raw:CurrentRawTypingWord() macro:CurrentMacroOffer()];
            }
            if (pData->code == vDoNothing) { //do nothing
                if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
                    if (pData->extCode == 1) { //break key
                        _syncKey.clear();
                    } else if (pData->extCode == 2) { //delete key
                        if (_syncKey.size() > 0) {
                            if (_syncKey.back() > 1 && (vCodeTable == 2 || !containUnicodeCompoundApp(FRONT_APP))) {
                                //send one more backspace
                                CGEventTapPostEvent(_proxy, eventBackSpaceDown);
                                CGEventTapPostEvent(_proxy, eventBackSpaceUp);
                            }
                            _syncKey.pop_back();
                        }
                       
                    } else if (pData->extCode == 3) { //normal key
                        InsertKeyLength(1);
                    }
                }
                return event;
            } else if (pData->code == vWillProcess || pData->code == vRestore || pData->code == vRestoreAndStartNewSession) { //handle result signal
                
                sendEngineResult();
            } else if (pData->code == vReplaceMaro) { //MACRO
                handleMacro();
            }
            
            return NULL;
        }
        
        return event;
    }

    //The callback is the one place where being slow costs the user their typing: macOS switches the tap off when a key waits about a
    //second for it. With the log on, anything that takes 20 ms or more is written down.
    CGEventRef OpenKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        _spotlightMemo = -1;
        if (!vDiagnostics) {
            CGEventRef answer = OpenKeyCallbackImpl(proxy, type, event, refcon);
            _spotlightMemo = -1;
            return answer;
        }
        uint64_t started = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        CGEventRef result = OpenKeyCallbackImpl(proxy, type, event, refcon);
        _spotlightMemo = -1;
        double milliseconds = (double)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - started) / 1e6;
        if (milliseconds >= 20.0) {
            VOKDiag(@"ANOMALY", @"SLOW CALLBACK: %.0f ms for a %@ event (macOS switches the tap off after about a second), the event was %@",
                    milliseconds, EventTypeName(type), result == NULL ? @"taken" : @"passed on");
        }
        return result;
    }
}
