//
//  make-ai-presets.m
//  VOpenKey
//
//  Writes engine/ai/ai-presets.json, the data file of the ready-made conversions and picture sizes that the Windows program reads, from
//  AIPresets.m, which is where the words are written. Run it through scripts/make-ai-presets.sh.
//

#import <Foundation/Foundation.h>
#import "AIPresets.h"

static NSString* Quote(NSString* text) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:@[text] options:NSJSONWritingWithoutEscapingSlashes error:nil];
    NSString* array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];    //["..."]
    return [array substringWithRange:NSMakeRange(1, array.length - 2)];
}

static void Group(NSMutableString* out, NSString* key, NSArray<AIPresetGroup*>* groups) {
    [out appendFormat:@"  \"%@\": [\n", key];
    for (NSUInteger i = 0; i < groups.count; i++)
        [out appendFormat:@"    { \"id\": %@, \"title\": %@ }%@\n", Quote(groups[i].identifier), Quote(groups[i].title), i + 1 < groups.count ? @"," : @""];
    [out appendString:@"  ],\n"];
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: make-ai-presets <output.json>\n");
            return 2;
        }
        NSArray<AIPreset*>* all = [AIPresets all];
        //the template of the request: made from a real preset and a marker for the text, so that it cannot differ from what the window sends
        NSString* made = [AIPresets promptForPreset:all[0] draft:@"@@TEXT@@"];
        NSString* promptTemplate = [[made stringByReplacingOccurrencesOfString:all[0].instruction withString:@"{instruction}"]
                                    stringByReplacingOccurrencesOfString:@"@@TEXT@@" withString:@"{text}"];
        NSMutableString* out = [NSMutableString string];
        [out appendString:@"{\n  \"version\": 2,\n"];
        [out appendFormat:@"  \"promptTemplate\": %@,\n", Quote(promptTemplate)];
        Group(out, @"groups", [AIPresets groups]);
        [out appendString:@"  \"presets\": [\n"];
        for (NSUInteger i = 0; i < all.count; i++) {
            AIPreset* preset = all[i];
            [out appendFormat:@"    {\n      \"id\": %@,\n      \"group\": %@,\n      \"title\": %@,\n      \"summary\": %@,\n      \"instruction\": %@,\n      \"poem\": %@\n    }%@\n",
             Quote(preset.identifier), Quote(preset.group), Quote(preset.title), Quote(preset.summary), Quote(preset.instruction),
             preset.isPoem ? @"true" : @"false", i + 1 < all.count ? @"," : @""];
        }
        [out appendString:@"  ],\n"];
        [out appendFormat:@"  \"imageNote\": %@,\n", Quote([AIPresets imageNoteTemplate])];
        Group(out, @"imageGroups", [AIPresets imageGroups]);
        [out appendString:@"  \"imageSizes\": [\n"];
        NSArray<AIImageSize*>* sizes = [AIPresets allImageSizes];
        for (NSUInteger i = 0; i < sizes.count; i++) {
            AIImageSize* size = sizes[i];
            [out appendFormat:@"    {\n      \"id\": %@,\n      \"group\": %@,\n      \"title\": %@,\n      \"summary\": %@,\n      \"width\": %ld,\n      \"height\": %ld,\n      \"ratio\": %@,\n      \"hint\": %@\n    }%@\n",
             Quote(size.identifier), Quote(size.group), Quote(size.title), Quote(size.summary), (long)size.width, (long)size.height, Quote(size.ratio),
             Quote(size.hint), i + 1 < sizes.count ? @"," : @""];
        }
        [out appendString:@"  ]\n}\n"];
        NSError* error = nil;
        if (![out writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            fprintf(stderr, "cannot write: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        printf("wrote %lu presets and %lu sizes to %s\n", (unsigned long)all.count, (unsigned long)sizes.count, argv[1]);
    }
    return 0;
}
