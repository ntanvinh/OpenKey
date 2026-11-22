//
//  DictionaryService.h
//  VOpenKey
//
//  Manages the open-source dictionary catalog, downloads, StarDict/FVDP local imports,
//  and sub-millisecond multi-dictionary search on macOS.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// 'd' + Ctrl+Option (`⌃⌥D`): keyCode 0x02 (kVK_ANSI_D), flags Ctrl+Alt (0x03 in ShortcutRecorder byte layout)
#define VOK_DICTIONARY_DEFAULT_HOTKEY 0x64000302
extern int vDictionaryHotKey;

extern NSNotificationName const VOKDictionaryDidChangeNotification;

typedef NS_ENUM(NSInteger, VOKDictionaryBlockKind) {
    VOKDictionaryBlockKindHeadword = 0,
    VOKDictionaryBlockKindPhonetic = 1,
    VOKDictionaryBlockKindPartOfSpeech = 2,
    VOKDictionaryBlockKindSense = 3,
    VOKDictionaryBlockKindSubSense = 4,
    VOKDictionaryBlockKindExample = 5,
    VOKDictionaryBlockKindNote = 6,
    VOKDictionaryBlockKindPlain = 7,
    VOKDictionaryBlockKindIdiom = 8,        // a phrase of the entry; `secondary` is what it means
    VOKDictionaryBlockKindSection = 9       // a field ("Chuyên ngành kỹ thuật") the senses below belong to
};

@interface VOKDictionaryFormattedLine : NSObject
@property (nonatomic, readonly) VOKDictionaryBlockKind kind;
@property (nonatomic, copy, readonly) NSString* text;
@property (nonatomic, copy, readonly) NSString* secondary;
/// "1.", "2." for a sense whose part of speech has several; empty for a sense alone.
@property (nonatomic, copy, readonly) NSString* marker;
@end

@interface VOKDictionaryDefinition : NSObject
@property (nonatomic, copy, readonly) NSString* dictId;
@property (nonatomic, copy, readonly) NSString* dictName;
@property (nonatomic, copy, readonly) NSString* shortName;
@property (nonatomic, copy, readonly) NSString* badge;
@property (nonatomic, copy, readonly) NSString* headword;
@property (nonatomic, copy, readonly) NSString* matchedVia;
@property (nonatomic, copy, readonly) NSString* rawText;
@property (nonatomic, copy, readonly) NSArray<VOKDictionaryFormattedLine*>* lines;
@end

@interface VOKDictionarySearchHit : NSObject
@property (nonatomic, copy, readonly) NSString* headword;
@property (nonatomic, copy, readonly) NSString* subtitle;
@property (nonatomic, readonly) BOOL isExact;
@property (nonatomic, copy, readonly) NSString* badgesSummary;
@property (nonatomic, copy, readonly) NSString* primaryBadge;
@property (nonatomic, readonly) NSUInteger dictCount;
@end

@interface VOKDictionaryCatalogItem : NSObject
@property (nonatomic, copy, readonly) NSString* dictId;
@property (nonatomic, copy, readonly) NSString* name;
@property (nonatomic, copy, readonly) NSString* shortName;
@property (nonatomic, copy, readonly) NSString* badge;
@property (nonatomic, copy, readonly) NSString* sourceLang;
@property (nonatomic, copy, readonly) NSString* targetLang;
@property (nonatomic, copy, readonly) NSString* author;
@property (nonatomic, copy, readonly) NSString* license;
@property (nonatomic, copy, readonly) NSString* descriptionText;
@property (nonatomic, readonly) NSInteger priority;
@property (nonatomic, readonly) BOOL recommended;
@property (nonatomic, readonly) BOOL isCustom;
@property (nonatomic, readonly) uint64_t headwordCount;
@property (nonatomic, readonly) uint64_t downloadBytes;
@property (nonatomic, copy, readonly) NSString* downloadSizeText;
@property (nonatomic, readonly) BOOL installed;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL downloading;
@property (nonatomic, readonly) double downloadProgress; // 0..1, or -1 if indeterminate
@property (nonatomic, copy, readonly) NSString* statusText;
@property (nonatomic, copy, readonly, nullable) NSString* errorText;
@end

@interface DictionaryService : NSObject

+(instancetype)shared;
+(void)registerDefaults;
+(void)start;
+(void)saveHotKey:(int)hotKey;

/// Designated initializer for tests (isolated storage, mock catalog JSON, isolated NSUserDefaults).
-(instancetype)initWithDirectory:(NSURL*)directory
                      catalogURL:(nullable NSURL*)catalogURL
                    userDefaults:(nullable NSUserDefaults*)defaults;

-(NSArray<VOKDictionaryCatalogItem*>*)allDictionaries;
-(NSArray<VOKDictionaryCatalogItem*>*)installedDictionaries;
-(BOOL)hasInstalledDictionary;
-(BOOL)hasActiveDownload;

-(void)downloadDictionariesWithIDs:(NSArray<NSString*>*)dictIds;
-(void)cancelDownloadForID:(NSString*)dictId;
-(void)setDictionaryID:(NSString*)dictId enabled:(BOOL)enabled;
-(void)removeDictionaryID:(NSString*)dictId;
-(void)importLocalURL:(NSURL*)url
           completion:(void (^)(VOKDictionaryCatalogItem* _Nullable item, NSError* _Nullable error))completion;

-(NSArray<VOKDictionarySearchHit*>*)search:(NSString*)query
                              filterDictId:(nullable NSString*)filterDictId
                                maxResults:(NSUInteger)maxResults;

-(void)searchAsync:(NSString*)query
      filterDictId:(nullable NSString*)filterDictId
        maxResults:(NSUInteger)maxResults
        completion:(void (^)(NSArray<VOKDictionarySearchHit*>* hits))completion;

-(NSArray<VOKDictionaryDefinition*>*)definitionsForHit:(VOKDictionarySearchHit*)hit
                                          filterDictId:(nullable NSString*)filterDictId;

@end

NS_ASSUME_NONNULL_END
