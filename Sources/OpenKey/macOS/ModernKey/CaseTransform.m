//
//  CaseTransform.m
//  VOpenKey
//

#import "CaseTransform.h"

//what a composed character (a letter with its accents) is for cutting a text into words
typedef NS_ENUM(NSInteger, Kind) {
    KindSeparator,
    KindLower,
    KindUpper,
    KindDigit,
    KindOther       //a letter with no case: Chinese, Thai...
};

static Kind KindOfCharacter(NSString* character) {
    static NSCharacterSet *lower, *upper, *digits, *letters, *marks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lower = [NSCharacterSet lowercaseLetterCharacterSet];
        NSMutableCharacterSet* uppers = [[NSCharacterSet uppercaseLetterCharacterSet] mutableCopy];
        [uppers formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"ǅǈǋǲ"]]; //titlecase letters
        upper = uppers;
        digits = [NSCharacterSet decimalDigitCharacterSet];
        letters = [NSCharacterSet letterCharacterSet];
        marks = [NSCharacterSet nonBaseCharacterSet];
    });
    UTF32Char first = [character characterAtIndex:0];
    if (CFStringIsSurrogateHighCharacter((UniChar)first) && character.length > 1)
        first = CFStringGetLongCharacterForSurrogatePair((UniChar)first, [character characterAtIndex:1]);
    if ([upper longCharacterIsMember:first])
        return KindUpper;
    if ([lower longCharacterIsMember:first])
        return KindLower;
    if ([digits longCharacterIsMember:first])
        return KindDigit;
    if ([letters longCharacterIsMember:first] || [marks longCharacterIsMember:first])
        return KindOther;
    return KindSeparator;
}

static NSArray<NSString*>* ComposedCharacters(NSString* text) {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:text.length];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString* character, NSRange r, NSRange er, BOOL* stop) { [result addObject:character]; }];
    return result;
}

//The words of a line as one name sees them: cut at everything that is not a letter or a digit, and, with `splitCamel`, inside
//"myVariableName" and "HTMLParser" (HTML, Parser).
static NSArray<NSString*>* WordsOfLine(NSString* line, BOOL splitCamel) {
    NSArray<NSString*>* characters = ComposedCharacters(line);
    NSMutableArray<NSNumber*>* kinds = [NSMutableArray arrayWithCapacity:characters.count];
    for (NSString* character in characters)
        [kinds addObject:@(KindOfCharacter(character))];

    NSMutableArray<NSString*>* words = [NSMutableArray array];
    NSMutableString* word = [NSMutableString string];
    Kind previous = KindSeparator;
    for (NSUInteger i = 0; i < characters.count; i++) {
        Kind kind = (Kind)kinds[i].integerValue;
        if (kind == KindSeparator) {
            if (word.length > 0)
                [words addObject:[word copy]];
            [word setString:@""];
            previous = KindSeparator;
            continue;
        }
        if (splitCamel && word.length > 0) {
            Kind next = i + 1 < characters.count ? (Kind)kinds[i + 1].integerValue : KindSeparator;
            BOOL lowerToUpper = (previous == KindLower || previous == KindDigit) && kind == KindUpper;
            BOOL acronymEnds = previous == KindUpper && kind == KindUpper && next == KindLower; //HTMLParser: the P starts a word
            if (lowerToUpper || acronymEnds) {
                [words addObject:[word copy]];
                [word setString:@""];
            }
        }
        [word appendString:characters[i]];
        previous = kind;
    }
    if (word.length > 0)
        [words addObject:[word copy]];
    return words;
}

//The first letter in capitals, the rest in small letters. Title case of the system, so "ǆ" becomes "ǅ" and not "Ǆ".
static NSString* Capitalized(NSString* word) {
    return [[word lowercaseString] capitalizedString];
}

//One line to one name: `join` between the words and `style` for each of them (index 0 is the first word)
static NSString* NameFromLine(NSString* line, BOOL splitCamel, NSString* join, NSString* (^style)(NSString* word, NSUInteger index)) {
    //the spaces at both ends stay where they were (indentation, a line break of Windows)
    NSCharacterSet* space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger start = 0, end = line.length;
    while (start < end && [space characterIsMember:[line characterAtIndex:start]])
        start++;
    while (end > start && [space characterIsMember:[line characterAtIndex:end - 1]])
        end--;
    NSString* core = [line substringWithRange:NSMakeRange(start, end - start)];
    NSArray<NSString*>* words = WordsOfLine(core, splitCamel);
    if (words.count == 0)
        return line;
    NSMutableArray* styled = [NSMutableArray arrayWithCapacity:words.count];
    for (NSUInteger i = 0; i < words.count; i++)
        [styled addObject:style(words[i], i)];
    return [NSString stringWithFormat:@"%@%@%@", [line substringToIndex:start], [styled componentsJoinedByString:join],
            [line substringFromIndex:end]];
}

static NSString* ByLine(NSString* text, NSString* (^convert)(NSString* line)) {
    if (![text containsString:@"\n"])
        return convert(text);
    NSMutableArray* lines = [NSMutableArray array];
    for (NSString* line in [text componentsSeparatedByString:@"\n"])
        [lines addObject:convert(line)];
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - Sentence case

static BOOL IsLetter(NSString* character) {
    Kind kind = KindOfCharacter(character);
    return kind == KindLower || kind == KindUpper || kind == KindOther;
}

//All small, then a capital at the start and after the end of a sentence: ! ? … and a full stop followed by a space (not the
//one in "3.14" or "vinh.com"), and after every line break.
static NSString* SentenceCase(NSString* text) {
    NSString* lowered = [text lowercaseString];
    NSArray<NSString*>* characters = ComposedCharacters(lowered);
    NSMutableString* result = [NSMutableString stringWithCapacity:lowered.length];
    BOOL needsCapital = YES;
    for (NSUInteger i = 0; i < characters.count; i++) {
        NSString* character = characters[i];
        unichar c = [character characterAtIndex:0];
        if (needsCapital && IsLetter(character)) {
            [result appendString:[character capitalizedString]];
            needsCapital = NO;
            continue;
        }
        [result appendString:character];
        if (KindOfCharacter(character) == KindDigit) {
            needsCapital = NO;
        } else if (c == '!' || c == '?' || c == 0x2026 || c == '\n' || c == '\r' || c == 0x3002 || c == 0xFF01 || c == 0xFF1F) {
            needsCapital = YES;
        } else if (c == '.') {
            NSString* next = i + 1 < characters.count ? characters[i + 1] : nil;
            if (next == nil || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[next characterAtIndex:0]])
                needsCapital = YES;
        }
    }
    return result;
}

#pragma mark - Without accents

//Letters that have no accent to take off and still have a plain form
static NSDictionary<NSString*, NSString*>* PlainLetters(void) {
    static NSDictionary* letters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        letters = @{@"đ": @"d", @"Đ": @"D", @"ł": @"l", @"Ł": @"L", @"ø": @"o", @"Ø": @"O",
                    @"ħ": @"h", @"Ħ": @"H", @"ı": @"i", @"ð": @"d", @"Ð": @"D", @"ß": @"ss"};
    });
    return letters;
}

//Only the accents of Latin letters go: the marks of other scripts (Thai, Hindi...) are part of their letters
static BOOL IsLatinBase(unichar c) {
    return c < 0x250 || (c >= 0x1E00 && c <= 0x1EFF);
}

static NSString* StripMarks(NSString* text) {
    NSMutableString* result = [NSMutableString stringWithCapacity:text.length];
    for (NSString* character in ComposedCharacters(text)) {
        unichar first = [character characterAtIndex:0];
        if (!IsLatinBase(first) || (character.length == 1 && first < 0x80)) {
            [result appendString:character];
            continue;
        }
        NSString* plain = PlainLetters()[character];
        if (plain != nil) {
            [result appendString:plain];
            continue;
        }
        NSString* decomposed = [character decomposedStringWithCanonicalMapping];
        NSMutableString* kept = [NSMutableString string];
        for (NSUInteger i = 0; i < decomposed.length; i++) {
            unichar c = [decomposed characterAtIndex:i];
            if (c < 0x300 || c > 0x36F)
                [kept appendFormat:@"%C", c];
        }
        NSString* base = [kept precomposedStringWithCanonicalMapping];
        [result appendString:PlainLetters()[base] ?: base];
    }
    return result;
}

#pragma mark - Title case

static NSString* TitleCase(NSString* text) {
    NSMutableArray<NSValue*>* ranges = [NSMutableArray array];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByWords
                          usingBlock:^(NSString* word, NSRange r, NSRange er, BOOL* stop) { [ranges addObject:[NSValue valueWithRange:r]]; }];
    NSMutableString* result = [text mutableCopy];
    for (NSValue* value in [ranges reverseObjectEnumerator]) { //from the end: a replacement can be longer than the word
        NSRange range = value.rangeValue;
        [result replaceCharactersInRange:range withString:Capitalized([text substringWithRange:range])];
    }
    return result;
}

#pragma mark -

@implementation CaseTransform

+(NSArray<NSNumber*>*)stylesByPopularity {
    return @[@(VOKCaseUpper), @(VOKCaseLower), @(VOKCaseTitle), @(VOKCaseSentence), @(VOKCaseCamel), @(VOKCasePascal),
             @(VOKCaseSnake), @(VOKCaseKebab), @(VOKCaseConstant), @(VOKCaseStripMarks), @(VOKCaseSlug)];
}

+(NSString*)nameOfStyle:(VOKCaseStyle)style {
    switch (style) {
        case VOKCaseUpper: return @"CHỮ HOA";
        case VOKCaseLower: return @"chữ thường";
        case VOKCaseTitle: return @"Viết Hoa Từng Từ";
        case VOKCaseSentence: return @"Viết hoa đầu câu";
        case VOKCaseCamel: return @"camelCase";
        case VOKCasePascal: return @"PascalCase";
        case VOKCaseSnake: return @"snake_case";
        case VOKCaseKebab: return @"kebab-case";
        case VOKCaseConstant: return @"CONSTANT_CASE";
        case VOKCaseStripMarks: return @"Bỏ dấu tiếng Việt";
        case VOKCaseSlug: return @"Đường dẫn (bỏ dấu)";
    }
    return @"";
}

+(NSString*)apply:(VOKCaseStyle)style toText:(NSString*)text {
    if (text.length == 0)
        return text;
    switch (style) {
        case VOKCaseUpper:
            return [text uppercaseString];
        case VOKCaseLower:
            return [text lowercaseString];
        case VOKCaseTitle:
            return TitleCase(text);
        case VOKCaseSentence:
            return SentenceCase(text);
        case VOKCaseStripMarks:
            return StripMarks(text);
        case VOKCaseCamel:
            return ByLine(text, ^NSString*(NSString* line) {
                return NameFromLine(line, YES, @"", ^NSString*(NSString* word, NSUInteger index) {
                    return index == 0 ? [word lowercaseString] : Capitalized(word);
                });
            });
        case VOKCasePascal:
            return ByLine(text, ^NSString*(NSString* line) {
                return NameFromLine(line, YES, @"", ^NSString*(NSString* word, NSUInteger index) { return Capitalized(word); });
            });
        case VOKCaseSnake:
            return ByLine(text, ^NSString*(NSString* line) {
                return NameFromLine(line, YES, @"_", ^NSString*(NSString* word, NSUInteger index) { return [word lowercaseString]; });
            });
        case VOKCaseKebab:
            return ByLine(text, ^NSString*(NSString* line) {
                return NameFromLine(line, YES, @"-", ^NSString*(NSString* word, NSUInteger index) { return [word lowercaseString]; });
            });
        case VOKCaseConstant:
            return ByLine(text, ^NSString*(NSString* line) {
                return NameFromLine(line, YES, @"_", ^NSString*(NSString* word, NSUInteger index) { return [word uppercaseString]; });
            });
        case VOKCaseSlug:
            //an address is made of the words of a title: "iPhone" stays one word here
            return ByLine(StripMarks(text), ^NSString*(NSString* line) {
                return NameFromLine(line, NO, @"-", ^NSString*(NSString* word, NSUInteger index) { return [word lowercaseString]; });
            });
    }
    return text;
}

+(NSArray<NSDictionary*>*)offersForText:(NSString*)text {
    NSMutableArray* offers = [NSMutableArray array];
    NSMutableSet* seen = [NSMutableSet setWithObject:text];
    for (NSNumber* style in [self stylesByPopularity]) {
        NSString* result = [self apply:(VOKCaseStyle)style.integerValue toText:text];
        if ([seen containsObject:result])
            continue;
        [seen addObject:result];
        [offers addObject:@{@"style": style, @"name": [self nameOfStyle:(VOKCaseStyle)style.integerValue], @"text": result}];
    }
    return offers;
}

@end
