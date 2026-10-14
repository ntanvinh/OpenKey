//
//  MacroPresets.mm
//  VOpenKey
//

#import "MacroPresets.h"
#include <string>
#include <vector>
#include "Engine.h"

NSString* const VOKMacrosDidChangeNotification = @"VOKMacrosDidChange";

typedef std::pair<std::string, std::string> Abbreviation;

static std::vector<Abbreviation> LoadPresets(void) {
    std::vector<Abbreviation> presets;
    NSString* path = [[NSBundle mainBundle] pathForResource:@"vi-macros" ofType:@"txt"];
    NSString* text = path != nil ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    BOOL first = YES;
    for (NSString* line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if (first) { //the heading line
            first = NO;
            continue;
        }
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound || colon.location == 0)
            continue;
        NSString* key = [line substringToIndex:colon.location];
        NSString* content = [line substringFromIndex:colon.location + 1];
        if (content.length == 0)
            continue;
        presets.push_back(Abbreviation(key.UTF8String, content.UTF8String));
    }
    return presets;
}

@implementation MacroPresets

+(void)countTotal:(NSUInteger*)total missing:(NSUInteger*)missing {
    std::vector<Abbreviation> presets = LoadPresets();
    NSUInteger count = 0;
    for (const Abbreviation& item : presets) {
        if (!hasMacro(item.first))
            count++;
    }
    if (total != NULL)
        *total = presets.size();
    if (missing != NULL)
        *missing = count;
}

+(NSUInteger)addMissing {
    NSUInteger added = 0;
    for (const Abbreviation& item : LoadPresets()) {
        if (hasMacro(item.first))
            continue;
        addMacro(item.first, item.second);
        added++;
    }
    if (added > 0) {
        std::vector<Byte> data;
        getMacroSaveData(data);
        [[NSUserDefaults standardUserDefaults] setObject:[NSData dataWithBytes:data.data() length:data.size()] forKey:@"macroData"];
        [[NSNotificationCenter defaultCenter] postNotificationName:VOKMacrosDidChangeNotification object:nil];
    }
    return added;
}

+(NSString*)examples {
    return @"ko → không, dc → được, vs → với, mn → mọi người, ntn → như thế nào";
}

@end
