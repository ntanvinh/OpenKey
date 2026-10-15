//
//  AILocalModels.m
//  VOpenKey
//

#import "AILocalModels.h"

@implementation AILocalModel

-(instancetype)initWithTag:(NSString*)tag name:(NSString*)name family:(NSString*)family parameters:(NSString*)parameters
                   summary:(NSString*)summary vietnamese:(NSString*)vietnamese bytes:(uint64_t)bytes
                   quality:(NSInteger)quality speed:(NSInteger)speed custom:(BOOL)custom {
    self = [super init];
    if (self) {
        _tag = [tag copy];
        _name = [name copy];
        _family = [family copy];
        _parameters = [parameters copy];
        _summary = [summary copy];
        _vietnamese = [vietnamese copy];
        _bytes = bytes;
        _quality = quality;
        _speed = speed;
        _isCustom = custom;
    }
    return self;
}

+(AILocalModel*)customModelWithTag:(NSString*)tag bytes:(uint64_t)bytes {
    return [[AILocalModel alloc] initWithTag:tag name:tag family:@"Model do bạn chọn" parameters:@""
                                     summary:@"Model bạn tự nhập tên. VOpenKey không biết nó viết tiếng Việt tốt đến đâu. Model có chế độ suy nghĩ (qwen3, gemma4, deepseek-r1…) sẽ chậm hơn lúc bắt đầu trả lời; VOpenKey bỏ phần suy nghĩ và chỉ lấy câu trả lời."
                                  vietnamese:@"Chưa rõ" bytes:bytes quality:0 speed:0 custom:YES];
}

@end

@implementation AILocalModels

+(NSArray<AILocalModel*>*)catalog {
    static NSArray<AILocalModel*>* catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL* file = [[NSBundle mainBundle] URLForResource:@"local-models" withExtension:@"json"];
        catalog = file != nil ? [self catalogFromFile:file] : @[];
    });
    return catalog;
}

+(NSArray<AILocalModel*>*)catalogFromFile:(NSURL*)file {
    NSData* data = file != nil ? [NSData dataWithContentsOfURL:file] : nil;
    id root = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray* list = [root isKindOfClass:[NSDictionary class]] ? root[@"models"] : nil;
    NSMutableArray<AILocalModel*>* models = [NSMutableArray array];
    if (![list isKindOfClass:[NSArray class]])
        return models;
    for (id item in list) {
        if (![item isKindOfClass:[NSDictionary class]])
            continue;
        NSString* tag = [self validTagFromText:item[@"tag"]];
        NSNumber* bytes = item[@"bytes"];
        if (tag == nil || ![bytes isKindOfClass:[NSNumber class]] || bytes.unsignedLongLongValue == 0)
            continue;                                              //an entry that cannot be used is left out, not shown half
        NSString* (^text)(NSString*) = ^NSString*(NSString* key) { return [item[key] isKindOfClass:[NSString class]] ? item[key] : @""; };
        [models addObject:[[AILocalModel alloc] initWithTag:tag name:text(@"name").length > 0 ? text(@"name") : tag
                                                     family:text(@"family") parameters:text(@"parameters") summary:text(@"summary")
                                                 vietnamese:text(@"vietnamese") bytes:bytes.unsignedLongLongValue
                                                    quality:[item[@"quality"] integerValue] speed:[item[@"speed"] integerValue] custom:NO]];
    }
    [models sortUsingComparator:^NSComparisonResult(AILocalModel* a, AILocalModel* b) {
        return a.bytes < b.bytes ? NSOrderedAscending : (a.bytes > b.bytes ? NSOrderedDescending : NSOrderedSame);
    }];
    return models;
}

+(NSString*)validTagFromText:(NSString*)text {
    if (![text isKindOfClass:[NSString class]])
        return nil;
    NSString* name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0 || name.length > 120)
        return nil;
    //path/name:tag, each part made of letters, digits and . _ - ; no "..", no leading or trailing separator
    static NSRegularExpression* pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9._\\-]*(/[A-Za-z0-9][A-Za-z0-9._\\-]*){0,2}(:[A-Za-z0-9][A-Za-z0-9._\\-]*)?$" options:0 error:nil];
    });
    if ([pattern numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)] != 1)
        return nil;
    if ([name containsString:@".."])
        return nil;
    return name;
}

@end
