//
//  SnippetStore.mm
//  VOpenKey
//

#import "SnippetStore.h"
#import "AppInfo.h"
#include <memory>
#include "SnippetSearch.h"

NSString* const VOKSnippetsDidChangeNotification = @"VOKSnippetsDidChange";

static NSString* const kBuiltInPrefix = @"builtin.";
static const NSTimeInterval kSaveDelay = 0.4;   //changes made in quick succession (typing in the editor) are saved once

#pragma mark - One snippet

@interface VOKSnippet ()
-(instancetype)initWithIdentifier:(NSString*)identifier;
@end

@implementation VOKSnippet

-(instancetype)initWithIdentifier:(NSString*)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _title = @"";
        _keywords = @"";
        _content = @"";
    }
    return self;
}

-(BOOL)isBuiltIn {
    return [_identifier hasPrefix:kBuiltInPrefix];
}

//what is written in the file: only what is known, so that a file edited by hand with a typo still loads
-(NSDictionary*)dictionary {
    return @{@"id": _identifier, @"title": _title, @"keywords": _keywords, @"content": _content,
             @"useCount": @(_useCount), @"lastUsed": @(_lastUsed)};
}

+(VOKSnippet*)snippetFromDictionary:(NSDictionary*)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]])
        return nil;
    NSString* identifier = dictionary[@"id"];
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0)
        return nil;
    VOKSnippet* snippet = [[VOKSnippet alloc] initWithIdentifier:identifier];
    for (NSString* key in @[@"title", @"keywords", @"content"]) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSString class]])
            [snippet setValue:value forKey:key];
    }
    if ([dictionary[@"useCount"] isKindOfClass:[NSNumber class]])
        snippet.useCount = MAX(0, [dictionary[@"useCount"] intValue]);
    if ([dictionary[@"lastUsed"] isKindOfClass:[NSNumber class]])
        snippet.lastUsed = MAX(0, [dictionary[@"lastUsed"] doubleValue]);
    return snippet;
}

@end

#pragma mark - The store

@implementation SnippetStore {
    NSURL* _file;
    NSURL* _defaultsFile;
    NSMutableArray<VOKSnippet*>* _snippets;
    NSMutableSet<NSString*>* _seeded;               //ready-made snippets that were added to the list once, even if deleted since

    std::unique_ptr<vsnippet::Index> _index;
    NSArray<VOKSnippet*>* _indexed;                 //the snippets, in the order the index was made with
    BOOL _indexIsStale;

    BOOL _needsSave;
    BOOL _saveScheduled;
}

static SnippetStore* sShared;

+(SnippetStore*)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL* support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                inDomains:NSUserDomainMask].firstObject;
        NSURL* file = [[[support URLByAppendingPathComponent:VOK_DATA_DIR_NAME isDirectory:YES]
                        URLByAppendingPathComponent:@"Snippets" isDirectory:YES] URLByAppendingPathComponent:@"snippets.json"];
        NSURL* defaults = [[NSBundle mainBundle] URLForResource:@"default-snippets" withExtension:@"json"];
        sShared = [[SnippetStore alloc] initWithFileURL:file defaultsURL:defaults];
    });
    return sShared;
}

+(void)flushShared {
    [sShared flush];
}

-(instancetype)initWithFileURL:(NSURL*)file defaultsURL:(NSURL*)defaults {
    self = [super init];
    if (self) {
        _file = file;
        _defaultsFile = defaults;
        _snippets = [NSMutableArray array];
        _seeded = [NSMutableSet set];
        _indexIsStale = YES;
        [self load];
    }
    return self;
}

-(NSURL*)fileURL {
    return _file;
}

-(NSArray<VOKSnippet*>*)snippets {
    return [_snippets copy];
}

#pragma mark Reading and writing the file

//The ready-made snippets of this version of the app
-(NSArray<VOKSnippet*>*)defaultSnippets {
    NSData* data = _defaultsFile != nil ? [NSData dataWithContentsOfURL:_defaultsFile] : nil;
    id root = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray* list = [root isKindOfClass:[NSDictionary class]] ? root[@"snippets"] : nil;
    NSMutableArray* result = [NSMutableArray array];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id item in list) {
            VOKSnippet* snippet = [VOKSnippet snippetFromDictionary:item];
            if (snippet != nil && snippet.isBuiltIn)
                [result addObject:snippet];
        }
    }
    return result;
}

-(void)load {
    NSData* data = [NSData dataWithContentsOfURL:_file];
    BOOL fileExists = data != nil;
    id root = fileExists ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (fileExists && ![root isKindOfClass:[NSDictionary class]]) {
        //not something this app wrote and not readable: keep it where the user can find it, then start over
        NSString* stamp = [NSString stringWithFormat:@"%.0f", [NSDate date].timeIntervalSince1970];
        NSURL* broken = [[_file URLByDeletingLastPathComponent] URLByAppendingPathComponent:[NSString stringWithFormat:@"snippets-unreadable-%@.json", stamp]];
        [[NSFileManager defaultManager] moveItemAtURL:_file toURL:broken error:nil];
        NSLog(@"%@: the snippet file could not be read, kept as %@", VOK_APP_NAME, broken.lastPathComponent);
        root = nil;
    }

    NSMutableSet<NSString*>* known = [NSMutableSet set];
    for (VOKSnippet* snippet in [self snippetsFromRoot:root]) {
        if ([known containsObject:snippet.identifier])
            continue;
        [known addObject:snippet.identifier];
        [_snippets addObject:snippet];
    }
    NSArray* seeded = [root isKindOfClass:[NSDictionary class]] ? root[@"seeded"] : nil;
    if ([seeded isKindOfClass:[NSArray class]]) {
        for (id identifier in seeded)
            if ([identifier isKindOfClass:[NSString class]])
                [_seeded addObject:identifier];
    }

    //ready-made snippets this list has never had: all of them on a new installation, only the new ones after an update
    BOOL added = NO;
    for (VOKSnippet* snippet in [self defaultSnippets]) {
        if ([_seeded containsObject:snippet.identifier])
            continue;
        [_seeded addObject:snippet.identifier];
        if (![known containsObject:snippet.identifier])
            [_snippets addObject:snippet];
        added = YES;
    }
    if (added || !fileExists)
        [self markForSaving];
}

-(NSArray<VOKSnippet*>*)snippetsFromRoot:(id)root {
    NSArray* list = [root isKindOfClass:[NSDictionary class]] ? root[@"snippets"] : nil;
    NSMutableArray* result = [NSMutableArray array];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id item in list) {
            VOKSnippet* snippet = [VOKSnippet snippetFromDictionary:item];
            if (snippet != nil)
                [result addObject:snippet];
        }
    }
    return result;
}

-(void)markForSaving {
    _needsSave = YES;
    if (_saveScheduled)
        return;
    _saveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSaveDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_saveScheduled = NO;
        [self flush];
    });
}

-(void)flush {
    if (!_needsSave)
        return;
    NSMutableArray* list = [NSMutableArray array];
    for (VOKSnippet* snippet in _snippets)
        [list addObject:[snippet dictionary]];
    NSDictionary* root = @{@"version": @1,
                           @"seeded": [_seeded.allObjects sortedArrayUsingSelector:@selector(compare:)],
                           @"snippets": list};
    NSData* data = [NSJSONSerialization dataWithJSONObject:root
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:[_file URLByDeletingLastPathComponent] withIntermediateDirectories:YES
                  attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSError* error = nil;
    if ([data writeToURL:_file options:NSDataWritingAtomic error:&error]) {
        //snippets can hold private text (an address, a signature): only for this user
        [fm setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:_file.path error:nil];
        _needsSave = NO;
    } else {
        NSLog(@"%@: could not save the snippets: %@", VOK_APP_NAME, error);
    }
}

#pragma mark Searching

-(void)rebuildIndexIfNeeded {
    if (!_indexIsStale && _index != nullptr)
        return;
    std::vector<vsnippet::Entry> entries;
    entries.reserve(_snippets.count);
    for (VOKSnippet* snippet in _snippets) {
        entries.push_back(vsnippet::Entry(snippet.title.UTF8String ?: "", snippet.keywords.UTF8String ?: "",
                                          snippet.content.UTF8String ?: "", snippet.useCount,
                                          (long long)(snippet.lastUsed * 1000)));
    }
    _index.reset(new vsnippet::Index(entries));
    _indexed = [_snippets copy];
    _indexIsStale = NO;
}

-(NSArray<VOKSnippet*>*)search:(NSString*)query {
    [self rebuildIndexIfNeeded];
    std::vector<size_t> found = _index->search(query.UTF8String ?: "");
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:found.size()];
    for (size_t position : found) {
        if (position < _indexed.count)
            [result addObject:_indexed[position]];
    }
    return result;
}

-(VOKSnippet*)snippetWithIdentifier:(NSString*)identifier {
    for (VOKSnippet* snippet in _snippets)
        if ([snippet.identifier isEqualToString:identifier])
            return snippet;
    return nil;
}

#pragma mark Changing the list

-(void)listDidChange {
    _indexIsStale = YES;
    [self markForSaving];
    [[NSNotificationCenter defaultCenter] postNotificationName:VOKSnippetsDidChangeNotification object:self];
}

-(VOKSnippet*)addSnippetWithTitle:(NSString*)title keywords:(NSString*)keywords content:(NSString*)content {
    VOKSnippet* snippet = [[VOKSnippet alloc] initWithIdentifier:[@"user." stringByAppendingString:[NSUUID UUID].UUIDString]];
    snippet.title = title ?: @"";
    snippet.keywords = keywords ?: @"";
    snippet.content = content ?: @"";
    [_snippets addObject:snippet];
    [self listDidChange];
    return snippet;
}

-(void)snippetDidChange:(VOKSnippet*)snippet {
    if ([_snippets containsObject:snippet])
        [self listDidChange];
}

-(void)removeSnippet:(VOKSnippet*)snippet {
    if (![_snippets containsObject:snippet])
        return;
    [_snippets removeObject:snippet];
    [self listDidChange];
}

-(void)recordUse:(VOKSnippet*)snippet {
    if (![_snippets containsObject:snippet])
        return;
    snippet.useCount += 1;
    snippet.lastUsed = [NSDate date].timeIntervalSince1970;
    _indexIsStale = YES;
    [self markForSaving];
}

-(void)restoreDefaults {
    for (VOKSnippet* original in [self defaultSnippets]) {
        VOKSnippet* current = [self snippetWithIdentifier:original.identifier];
        if (current != nil) {
            current.title = original.title;
            current.keywords = original.keywords;
            current.content = original.content;
        } else {
            [_snippets addObject:original];
        }
        [_seeded addObject:original.identifier];
    }
    [self listDidChange];
}

@end
