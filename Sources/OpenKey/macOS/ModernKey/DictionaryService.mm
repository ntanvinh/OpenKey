//
//  DictionaryService.mm
//  VOpenKey
//

#import "DictionaryService.h"
#import "ShortcutRecorder.h"
#include "DictCatalog.h"
#include "DictStore.h"

int vDictionaryHotKey = VOK_DICTIONARY_DEFAULT_HOTKEY;
NSNotificationName const VOKDictionaryDidChangeNotification = @"VOKDictionaryDidChangeNotification";

static NSString* const kHotKeyDefaultsKey = @"DictionaryHotKey";
static NSString* const kStateFileName = @"state.json";

static BOOL DictionaryAddressAllowed(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"])
        return url.host.length > 0;
    NSString* host = url.host.lowercaseString;
    return [scheme isEqualToString:@"http"] &&
           ([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"]);
}

static NSError* DictionaryError(NSInteger code, NSString* message) {
    return [NSError errorWithDomain:@"VOKDictionaryError" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Lỗi từ điển"}];
}

static NSString* SafeUTF8String(const std::string& s) {
    if (s.empty()) return @"";
    return [NSString stringWithUTF8String:s.c_str()] ?: @"";
}

#pragma mark - Value Classes

@implementation VOKDictionaryFormattedLine
-(instancetype)initWithKind:(VOKDictionaryBlockKind)kind text:(NSString*)text secondary:(NSString*)secondary {
    if ((self = [super init])) {
        _kind = kind;
        _text = [text copy] ?: @"";
        _secondary = [secondary copy] ?: @"";
    }
    return self;
}
@end

@implementation VOKDictionaryDefinition
-(instancetype)initWithSection:(const vdict::DefinitionSection&)sec {
    if ((self = [super init])) {
        _dictId = SafeUTF8String(sec.dictId);
        _dictName = SafeUTF8String(sec.dictName);
        _shortName = SafeUTF8String(sec.shortName);
        _badge = SafeUTF8String(sec.badge);
        _headword = SafeUTF8String(sec.headword);
        _matchedVia = SafeUTF8String(sec.matchedVia);
        _rawText = SafeUTF8String(sec.rawText);
        NSMutableArray* lines = [NSMutableArray arrayWithCapacity:sec.lines.size()];
        for (size_t i = 0; i < sec.lines.size(); ++i) {
            const vdict::FormattedLine& ln = sec.lines[i];
            [lines addObject:[[VOKDictionaryFormattedLine alloc] initWithKind:(VOKDictionaryBlockKind)ln.kind
                                                                         text:SafeUTF8String(ln.text)
                                                                    secondary:SafeUTF8String(ln.secondary)]];
        }
        _lines = [lines copy];
    }
    return self;
}
@end

@interface VOKDictionarySearchHit ()
@property (nonatomic, assign) vdict::SearchItem cppItem;
@end

@implementation VOKDictionarySearchHit
-(instancetype)initWithSearchItem:(const vdict::SearchItem&)item {
    if ((self = [super init])) {
        _cppItem = item;
        _headword = SafeUTF8String(item.headword);
        _subtitle = SafeUTF8String(item.subtitle);
        _isExact = item.isExact;
        _dictCount = item.refs.size();
        NSMutableArray<NSString*>* labels = [NSMutableArray array];
        for (size_t i = 0; i < item.refs.size() && labels.count < 2; ++i) {
            NSString* b = SafeUTF8String(item.refs[i].badge.empty() ? item.refs[i].shortName : item.refs[i].badge);
            if (b.length > 0 && ![labels containsObject:b])
                [labels addObject:b];
        }
        _primaryBadge = labels.firstObject ?: @"";
        if (item.refs.size() > 2)
            _badgesSummary = [NSString stringWithFormat:@"%@ +%lu", labels.firstObject ?: @"", (unsigned long)(item.refs.size() - 1)];
        else
            _badgesSummary = [labels componentsJoinedByString:@" · "];
    }
    return self;
}
@end

@interface VOKDictionaryCatalogItem ()
@property (nonatomic, copy, readwrite) NSString* dictId;
@property (nonatomic, copy, readwrite) NSString* name;
@property (nonatomic, copy, readwrite) NSString* shortName;
@property (nonatomic, copy, readwrite) NSString* badge;
@property (nonatomic, copy, readwrite) NSString* sourceLang;
@property (nonatomic, copy, readwrite) NSString* targetLang;
@property (nonatomic, copy, readwrite) NSString* author;
@property (nonatomic, copy, readwrite) NSString* license;
@property (nonatomic, copy, readwrite) NSString* descriptionText;
@property (nonatomic, assign, readwrite) NSInteger priority;
@property (nonatomic, assign, readwrite) BOOL recommended;
@property (nonatomic, assign, readwrite) BOOL isCustom;
@property (nonatomic, assign, readwrite) uint64_t headwordCount;
@property (nonatomic, assign, readwrite) uint64_t downloadBytes;
@property (nonatomic, copy, readwrite) NSString* downloadSizeText;
@property (nonatomic, assign, readwrite) BOOL installed;
@property (nonatomic, assign, readwrite) BOOL enabled;
@property (nonatomic, assign, readwrite) BOOL downloading;
@property (nonatomic, assign, readwrite) double downloadProgress;
@property (nonatomic, copy, readwrite) NSString* statusText;
@property (nonatomic, copy, readwrite, nullable) NSString* errorText;
@end

@implementation VOKDictionaryCatalogItem
@end

#pragma mark - Download Task Helper

@interface VOKDictDownloadJob : NSObject
@property (nonatomic, copy) NSString* dictId;
@property (nonatomic, copy) NSArray<NSURL*>* fileURLs;
@property (nonatomic, strong) NSMutableArray<NSNumber*>* fileSizes;
@property (nonatomic, strong) NSMutableArray<NSURL*>* downloadedFiles;
@property (nonatomic, assign) NSUInteger currentFileIndex;
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask* task;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation VOKDictDownloadJob
@end

#pragma mark - DictionaryService

@interface DictionaryService () <NSURLSessionDownloadDelegate, NSURLSessionTaskDelegate>
@end

@implementation DictionaryService {
    NSURL* _directory;
    NSURL* _catalogURL;
    NSUserDefaults* _defaults;
    dispatch_queue_t _workQueue;
    dispatch_queue_t _searchQueue;
    id _engineLock;
    vdict::DictEngine _engine;

    std::vector<vdict::CatalogEntry> _catalog;
    NSMutableDictionary<NSString*, NSMutableDictionary*>* _installedMeta; // dictId -> state dict
    NSMutableDictionary<NSString*, VOKDictDownloadJob*>* _activeJobs;
    NSURLSession* _session;
}

+(instancetype)shared {
    static DictionaryService* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL* appSupport = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                                   inDomain:NSUserDomainMask
                                                          appropriateForURL:nil
                                                                     create:YES
                                                                      error:nil];
        NSURL* dir = [[appSupport URLByAppendingPathComponent:@"VOpenKey" isDirectory:YES]
                         URLByAppendingPathComponent:@"LookupDictionaries" isDirectory:YES];
        NSURL* catalogURL = [[NSBundle mainBundle] URLForResource:@"catalog" withExtension:@"json"];
        instance = [[DictionaryService alloc] initWithDirectory:dir catalogURL:catalogURL userDefaults:[NSUserDefaults standardUserDefaults]];
    });
    return instance;
}

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kHotKeyDefaultsKey: @(VOK_DICTIONARY_DEFAULT_HOTKEY)}];
}

+(void)start {
    vDictionaryHotKey = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kHotKeyDefaultsKey];
    if (vDictionaryHotKey == 0)
        vDictionaryHotKey = VOK_SHORTCUT_NONE;
    // Warm up mmap engine lazily on background queue so app launch is instant
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self shared];
    });
}

+(void)saveHotKey:(int)hotKey {
    vDictionaryHotKey = hotKey;
    [[NSUserDefaults standardUserDefaults] setInteger:hotKey forKey:kHotKeyDefaultsKey];
}

-(instancetype)initWithDirectory:(NSURL*)directory
                      catalogURL:(nullable NSURL*)catalogURL
                    userDefaults:(nullable NSUserDefaults*)defaults {
    if ((self = [super init])) {
        _directory = [directory copy];
        _catalogURL = [catalogURL copy];
        _defaults = defaults ?: [NSUserDefaults standardUserDefaults];
        _workQueue = dispatch_queue_create("vn.io.lssoft.vopenkey.dict.work", DISPATCH_QUEUE_SERIAL);
        _searchQueue = dispatch_queue_create("vn.io.lssoft.vopenkey.dict.search", DISPATCH_QUEUE_SERIAL);
        _engineLock = [[NSObject alloc] init];
        _installedMeta = [NSMutableDictionary dictionary];
        _activeJobs = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration* cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        cfg.timeoutIntervalForRequest = 60.0;
        cfg.timeoutIntervalForResource = 1800.0;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];

        [[NSFileManager defaultManager] createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:nil];
        [self loadCatalog];
        [self loadStateAndReloadEngine];
    }
    return self;
}

-(void)dealloc {
    [_session invalidateAndCancel];
}

-(void)loadCatalog {
    if (_catalogURL == nil)
        return;
    NSData* data = [NSData dataWithContentsOfURL:_catalogURL];
    if (data.length == 0)
        return;
    std::string text((const char*)data.bytes, data.length);
    vdict::parseCatalog(text, _catalog, NULL);
}

-(NSURL*)vdictURLForID:(NSString*)dictId {
    NSString* safe = [[dictId stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                             stringByReplacingOccurrencesOfString:@".." withString:@"_"];
    return [_directory URLByAppendingPathComponent:[safe stringByAppendingString:@".vdict"]];
}

-(NSURL*)stateFileURL {
    return [_directory URLByAppendingPathComponent:kStateFileName];
}

-(void)loadStateAndReloadEngine {
    NSData* data = [NSData dataWithContentsOfURL:[self stateFileURL]];
    if (data.length > 0) {
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]] && [obj[@"installed"] isKindOfClass:[NSDictionary class]]) {
            @synchronized (_installedMeta) {
                [obj[@"installed"] enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL* stop) {
                    if ([key isKindOfClass:[NSString class]] && [val isKindOfClass:[NSDictionary class]])
                        _installedMeta[key] = [val mutableCopy];
                }];
            }
        }
    }
    [self reloadEngine];
}

-(void)persistStateLocked {
    NSDictionary* root = @{@"version": @1, @"installed": [_installedMeta copy]};
    NSData* data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    if (data)
        [data writeToURL:[self stateFileURL] atomically:YES];
}

-(void)reloadEngine {
    std::vector<vdict::DictionarySpec> specs;
    @synchronized (_installedMeta) {
        for (NSString* dictId in _installedMeta) {
            NSDictionary* meta = _installedMeta[dictId];
            BOOL enabled = meta[@"enabled"] == nil || [meta[@"enabled"] boolValue];
            NSURL* vurl = [self vdictURLForID:dictId];
            if (![[NSFileManager defaultManager] fileExistsAtPath:vurl.path])
                continue;
            vdict::DictionarySpec spec;
            spec.vdictPath = vurl.path.UTF8String;
            spec.dictId = dictId.UTF8String;
            if ([meta[@"name"] isKindOfClass:[NSString class]])
                spec.displayName = [meta[@"name"] UTF8String];
            if ([meta[@"shortName"] isKindOfClass:[NSString class]])
                spec.shortName = [meta[@"shortName"] UTF8String];
            if ([meta[@"badge"] isKindOfClass:[NSString class]])
                spec.badge = [meta[@"badge"] UTF8String];
            spec.priority = meta[@"priority"] != nil ? [meta[@"priority"] intValue] : 250;
            spec.enabled = enabled;
            specs.push_back(spec);
        }
    }
    @synchronized (_engineLock) {
        _engine.setDictionaries(specs);
    }
}

-(void)notifyChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VOKDictionaryDidChangeNotification object:self];
    });
}

#pragma mark - Public Inspection

-(NSArray<VOKDictionaryCatalogItem*>*)allDictionaries {
    NSMutableArray<VOKDictionaryCatalogItem*>* items = [NSMutableArray array];
    NSMutableSet<NSString*>* seenIds = [NSMutableSet set];

    @synchronized (_installedMeta) {
        for (size_t i = 0; i < _catalog.size(); ++i) {
            const vdict::CatalogEntry& ce = _catalog[i];
            NSString* did = SafeUTF8String(ce.id);
            [seenIds addObject:did];
            NSDictionary* inst = _installedMeta[did];
            VOKDictDownloadJob* job = _activeJobs[did];

            VOKDictionaryCatalogItem* item = [[VOKDictionaryCatalogItem alloc] init];
            item.dictId = did;
            item.name = SafeUTF8String(ce.name);
            item.shortName = SafeUTF8String(ce.shortName);
            item.badge = SafeUTF8String(ce.badge);
            item.sourceLang = SafeUTF8String(ce.sourceLang);
            item.targetLang = SafeUTF8String(ce.targetLang);
            item.author = SafeUTF8String(ce.author);
            item.license = SafeUTF8String(ce.license);
            item.descriptionText = SafeUTF8String(ce.description);
            item.priority = ce.priority;
            item.recommended = ce.recommended;
            item.isCustom = NO;
            uint64_t compiledCount = inst != nil ? [inst[@"entryCount"] unsignedLongLongValue] : 0;
            item.headwordCount = compiledCount > 0 ? compiledCount : ce.headwordCount;
            item.downloadBytes = ce.downloadBytes;
            item.downloadSizeText = SafeUTF8String(vdict::formatByteSize(ce.downloadBytes));
            item.installed = (inst != nil) && [[NSFileManager defaultManager] fileExistsAtPath:[self vdictURLForID:did].path];
            item.enabled = item.installed && (inst[@"enabled"] == nil || [inst[@"enabled"] boolValue]);
            item.downloading = (job != nil && !job.cancelled);
            item.downloadProgress = inst[@"progress"] != nil ? [inst[@"progress"] doubleValue] : (item.downloading ? 0.0 : 0.0);
            item.errorText = [inst[@"error"] isKindOfClass:[NSString class]] ? inst[@"error"] : nil;
            if (!item.installed && !item.downloading && [inst[@"lastError"] isKindOfClass:[NSString class]])
                item.errorText = inst[@"lastError"];
            if (item.downloading)
                item.statusText = [inst[@"status"] isKindOfClass:[NSString class]] ? inst[@"status"] : @"Đang tải…";
            else if (item.installed)
                item.statusText = item.enabled ? @"Đã cài & đang bật" : @"Đã cài (tạm tắt)";
            else
                item.statusText = @"Chưa tải";
            [items addObject:item];
        }

        // Append custom user-imported dictionaries sorted by priority/name
        NSMutableArray<VOKDictionaryCatalogItem*>* customItems = [NSMutableArray array];
        for (NSString* did in _installedMeta) {
            if ([seenIds containsObject:did]) continue;
            NSDictionary* inst = _installedMeta[did];
            if (![[NSFileManager defaultManager] fileExistsAtPath:[self vdictURLForID:did].path])
                continue;
            VOKDictionaryCatalogItem* item = [[VOKDictionaryCatalogItem alloc] init];
            item.dictId = did;
            item.name = [inst[@"name"] isKindOfClass:[NSString class]] ? inst[@"name"] : did;
            item.shortName = [inst[@"shortName"] isKindOfClass:[NSString class]] ? inst[@"shortName"] : item.name;
            item.badge = [inst[@"badge"] isKindOfClass:[NSString class]] ? inst[@"badge"] : @"FILE";
            item.sourceLang = [inst[@"sourceLang"] isKindOfClass:[NSString class]] ? inst[@"sourceLang"] : @"";
            item.targetLang = [inst[@"targetLang"] isKindOfClass:[NSString class]] ? inst[@"targetLang"] : @"";
            item.author = @"Từ điển nhập từ máy";
            item.license = @"Người dùng tự nhập";
            item.descriptionText = @"Từ điển StarDict hoặc văn bản do bạn nhập từ máy tính.";
            item.priority = inst[@"priority"] != nil ? [inst[@"priority"] integerValue] : 250;
            item.recommended = NO;
            item.isCustom = YES;
            item.headwordCount = [inst[@"entryCount"] unsignedLongLongValue];
            item.downloadBytes = [inst[@"fileBytes"] unsignedLongLongValue];
            item.downloadSizeText = item.downloadBytes > 0 ? SafeUTF8String(vdict::formatByteSize(item.downloadBytes)) : @"Trên máy";
            item.installed = YES;
            item.enabled = inst[@"enabled"] == nil || [inst[@"enabled"] boolValue];
            item.downloading = NO;
            item.statusText = item.enabled ? @"Đã nhập & đang bật" : @"Đã nhập (tạm tắt)";
            [customItems addObject:item];
        }
        [customItems sortUsingComparator:^NSComparisonResult(VOKDictionaryCatalogItem* a, VOKDictionaryCatalogItem* b) {
            return [a.name localizedStandardCompare:b.name];
        }];
        [items addObjectsFromArray:customItems];
    }
    return items;
}

-(NSArray<VOKDictionaryCatalogItem*>*)installedDictionaries {
    NSMutableArray* out = [NSMutableArray array];
    for (VOKDictionaryCatalogItem* item in [self allDictionaries]) {
        if (item.installed)
            [out addObject:item];
    }
    return out;
}

-(BOOL)hasInstalledDictionary {
    return [self installedDictionaries].count > 0;
}

-(BOOL)hasActiveDownload {
    @synchronized (_installedMeta) {
        return _activeJobs.count > 0;
    }
}

#pragma mark - Search & Definitions

-(NSArray<VOKDictionarySearchHit*>*)search:(NSString*)query
                              filterDictId:(nullable NSString*)filterDictId
                                maxResults:(NSUInteger)maxResults {
    std::string q = query ? query.UTF8String : "";
    std::string f = filterDictId ? filterDictId.UTF8String : "";
    std::vector<vdict::SearchItem> raw;
    @synchronized (_engineLock) {
        raw = _engine.search(q, f, (size_t)(maxResults > 0 ? maxResults : 80));
    }
    NSMutableArray<VOKDictionarySearchHit*>* out = [NSMutableArray arrayWithCapacity:raw.size()];
    for (size_t i = 0; i < raw.size(); ++i)
        [out addObject:[[VOKDictionarySearchHit alloc] initWithSearchItem:raw[i]]];
    return out;
}

-(void)searchAsync:(NSString*)query
      filterDictId:(nullable NSString*)filterDictId
        maxResults:(NSUInteger)maxResults
        completion:(void (^)(NSArray<VOKDictionarySearchHit*>* hits))completion {
    NSString* qCopy = [query copy];
    NSString* fCopy = [filterDictId copy];
    dispatch_async(_searchQueue, ^{
        NSArray<VOKDictionarySearchHit*>* hits = [self search:qCopy filterDictId:fCopy maxResults:maxResults];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(hits);
        });
    });
}

-(NSArray<VOKDictionaryDefinition*>*)definitionsForHit:(VOKDictionarySearchHit*)hit
                                          filterDictId:(nullable NSString*)filterDictId {
    if (hit == nil)
        return @[];
    std::string f = filterDictId ? filterDictId.UTF8String : "";
    std::vector<vdict::DefinitionSection> secs;
    @synchronized (_engineLock) {
        secs = _engine.loadDefinitions(hit.cppItem, f);
    }
    NSMutableArray<VOKDictionaryDefinition*>* out = [NSMutableArray arrayWithCapacity:secs.size()];
    for (size_t i = 0; i < secs.size(); ++i)
        [out addObject:[[VOKDictionaryDefinition alloc] initWithSection:secs[i]]];
    return out;
}

#pragma mark - Download & Compile

-(void)setStatus:(NSString*)status progress:(double)progress error:(nullable NSString*)error forID:(NSString*)dictId {
    @synchronized (_installedMeta) {
        NSMutableDictionary* meta = _installedMeta[dictId];
        if (!meta) {
            meta = [NSMutableDictionary dictionary];
            _installedMeta[dictId] = meta;
        }
        if (status != nil) meta[@"status"] = status; else [meta removeObjectForKey:@"status"];
        meta[@"progress"] = @(progress);
        if (error != nil) meta[@"lastError"] = error; else [meta removeObjectForKey:@"lastError"];
    }
    [self notifyChanged];
}

-(void)downloadDictionariesWithIDs:(NSArray<NSString*>*)dictIds {
    for (NSString* dictId in dictIds) {
        const vdict::CatalogEntry* entry = vdict::findCatalogEntry(_catalog, dictId ? dictId.UTF8String : "");
        if (entry == NULL) continue;

        @synchronized (_installedMeta) {
            if (_activeJobs[dictId] != nil)
                continue;
            VOKDictDownloadJob* job = [[VOKDictDownloadJob alloc] init];
            job.dictId = dictId;
            NSMutableArray<NSURL*>* urls = [NSMutableArray array];
            NSMutableArray<NSNumber*>* sizes = [NSMutableArray array];
            for (size_t i = 0; i < entry->files.size(); ++i) {
                NSURL* u = [NSURL URLWithString:SafeUTF8String(entry->files[i].url)];
                if (u != nil && DictionaryAddressAllowed(u)) {
                    [urls addObject:u];
                    [sizes addObject:@(entry->files[i].sizeBytes)];
                }
            }
            if (urls.count == 0) continue;
            job.fileURLs = urls;
            job.fileSizes = sizes;
            job.downloadedFiles = [NSMutableArray array];
            job.currentFileIndex = 0;
            _activeJobs[dictId] = job;

            NSMutableDictionary* meta = _installedMeta[dictId] ?: [NSMutableDictionary dictionary];
            meta[@"status"] = @"Đang chuẩn bị tải…";
            meta[@"progress"] = @0.0;
            [meta removeObjectForKey:@"lastError"];
            _installedMeta[dictId] = meta;

            [self startNextDownloadFileForJob:job];
        }
    }
    [self notifyChanged];
}

-(void)startNextDownloadFileForJob:(VOKDictDownloadJob*)job {
    if (job.cancelled || job.currentFileIndex >= job.fileURLs.count)
        return;
    NSURL* url = job.fileURLs[job.currentFileIndex];
    NSURLRequest* req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    NSURLSessionDownloadTask* task = [_session downloadTaskWithRequest:req];
    task.taskDescription = job.dictId;
    job.task = task;
    [task resume];
}

-(void)cancelDownloadForID:(NSString*)dictId {
    VOKDictDownloadJob* job = nil;
    @synchronized (_installedMeta) {
        job = _activeJobs[dictId];
        if (job != nil) {
            job.cancelled = YES;
            [_activeJobs removeObjectForKey:dictId];
            NSMutableDictionary* meta = _installedMeta[dictId];
            [meta removeObjectForKey:@"status"];
            [meta removeObjectForKey:@"progress"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:[self vdictURLForID:dictId].path])
                [_installedMeta removeObjectForKey:dictId];
        }
    }
    if (job != nil) {
        [job.task cancel];
        for (NSURL* u in job.downloadedFiles)
            [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    }
    [self notifyChanged];
}

-(VOKDictDownloadJob*)jobForTask:(NSURLSessionTask*)task {
    NSString* did = task.taskDescription;
    if (did.length == 0) return nil;
    @synchronized (_installedMeta) {
        return _activeJobs[did];
    }
}

#pragma mark - NSURLSession Delegates

-(void)URLSession:(NSURLSession*)session
             task:(NSURLSessionTask*)task
willPerformHTTPRedirection:(NSHTTPURLResponse*)response
       newRequest:(NSURLRequest*)request
completionHandler:(void (^)(NSURLRequest* _Nullable))completionHandler {
    if (request.URL && DictionaryAddressAllowed(request.URL))
        completionHandler(request);
    else
        completionHandler(nil);
}

-(void)URLSession:(NSURLSession*)session
     downloadTask:(NSURLSessionDownloadTask*)downloadTask
     didWriteData:(int64_t)bytesWritten
totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    VOKDictDownloadJob* job = [self jobForTask:downloadTask];
    if (job == nil || job.cancelled) return;

    int64_t expected = totalBytesExpectedToWrite;
    if (expected <= 0 && job.currentFileIndex < job.fileSizes.count)
        expected = [job.fileSizes[job.currentFileIndex] longLongValue];

    double frac = (expected > 0) ? (double)totalBytesWritten / (double)expected : 0.5;
    if (frac > 1.0) frac = 1.0;
    double overall = ((double)job.currentFileIndex + frac) / (double)MAX(job.fileURLs.count, 1) * 0.9;
    NSString* status = [NSString stringWithFormat:@"Đang tải %d%%…", (int)(overall * 100.0)];
    [self setStatus:status progress:overall error:nil forID:job.dictId];
}

-(void)URLSession:(NSURLSession*)session
     downloadTask:(NSURLSessionDownloadTask*)downloadTask
didFinishDownloadingToURL:(NSURL*)location {
    VOKDictDownloadJob* job = [self jobForTask:downloadTask];
    if (job == nil || job.cancelled) return;

    NSHTTPURLResponse* http = [downloadTask.response isKindOfClass:[NSHTTPURLResponse class]]
        ? (NSHTTPURLResponse*)downloadTask.response : nil;
    if (http && (http.statusCode < 200 || http.statusCode >= 300)) {
        [self failJob:job message:[NSString stringWithFormat:@"Máy chủ trả về mã lỗi HTTP %ld.", (long)http.statusCode]];
        return;
    }

    NSURL* stagingDir = [_directory URLByAppendingPathComponent:@".staging" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:stagingDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* fileName = [NSString stringWithFormat:@"%@_%lu_%@", job.dictId, (unsigned long)job.currentFileIndex,
                          downloadTask.originalRequest.URL.lastPathComponent ?: @"dict.bin"];
    NSURL* localCopy = [stagingDir URLByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtURL:localCopy error:nil];
    NSError* copyErr = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:localCopy error:&copyErr]) {
        [self failJob:job message:copyErr.localizedDescription ?: @"Không lưu được tệp đã tải."];
        return;
    }

    @synchronized (_installedMeta) {
        [job.downloadedFiles addObject:localCopy];
        job.currentFileIndex++;
        if (job.currentFileIndex < job.fileURLs.count) {
            [self startNextDownloadFileForJob:job];
            return;
        }
    }
    [self compileDownloadedJob:job];
}

-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(nullable NSError*)error {
    if (error == nil) return;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
        return;
    VOKDictDownloadJob* job = [self jobForTask:task];
    if (job != nil && !job.cancelled)
        [self failJob:job message:@"Tải xuống thất bại. Kiểm tra kết nối mạng rồi thử lại."];
}

-(void)failJob:(VOKDictDownloadJob*)job message:(NSString*)message {
    NSArray<NSURL*>* cleanup = nil;
    @synchronized (_installedMeta) {
        cleanup = [job.downloadedFiles copy];
        [_activeJobs removeObjectForKey:job.dictId];
        NSMutableDictionary* meta = _installedMeta[job.dictId] ?: [NSMutableDictionary dictionary];
        [meta removeObjectForKey:@"status"];
        [meta removeObjectForKey:@"progress"];
        meta[@"lastError"] = message ?: @"Lỗi tải từ điển";
        _installedMeta[job.dictId] = meta;
    }
    for (NSURL* u in cleanup)
        [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    [self notifyChanged];
}

-(void)compileDownloadedJob:(VOKDictDownloadJob*)job {
    [self setStatus:@"Đang lập chỉ mục từ điển…" progress:0.93 error:nil forID:job.dictId];
    NSArray<NSURL*>* files = [job.downloadedFiles copy];
    NSString* dictId = [job.dictId copy];

    dispatch_async(_workQueue, ^{
        const vdict::CatalogEntry* ce = vdict::findCatalogEntry(_catalog, dictId.UTF8String);
        vdict::CompileMetadata meta;
        if (ce) {
            meta.dictId = ce->id;
            meta.displayName = ce->name;
            meta.shortName = ce->shortName;
            meta.badge = ce->badge;
            meta.sourceLang = ce->sourceLang;
            meta.targetLang = ce->targetLang;
            meta.author = ce->author;
            meta.license = ce->license;
        } else {
            meta.dictId = dictId.UTF8String;
            meta.displayName = dictId.UTF8String;
        }

        NSURL* outURL = [self vdictURLForID:dictId];
        std::string cppErr;
        BOOL ok = NO;
        if (files.count == 1) {
            ok = vdict::compileLocalPathToFile(files[0].path.UTF8String, meta, outURL.path.UTF8String, &cppErr);
        } else if (files.count > 1) {
            // Multiple downloaded StarDict files staged in one temp dir
            NSURL* dir = [[_directory URLByAppendingPathComponent:@".staging" isDirectory:YES]
                             URLByAppendingPathComponent:[dictId stringByAppendingString:@"_dir"] isDirectory:YES];
            [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
            [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
            for (size_t i = 0; i < files.count; ++i) {
                NSString* origName = ce && i < ce->files.size() ? SafeUTF8String(ce->files[i].name) : files[i].lastPathComponent;
                [[NSFileManager defaultManager] moveItemAtURL:files[i] toURL:[dir URLByAppendingPathComponent:origName] error:nil];
            }
            ok = vdict::compileDirectoryToFile(dir.path.UTF8String, meta, outURL.path.UTF8String, &cppErr);
            [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
        }

        for (NSURL* u in files)
            [[NSFileManager defaultManager] removeItemAtURL:u error:nil];

        if (!ok) {
            NSString* errMsg = SafeUTF8String(cppErr);
            if (errMsg.length == 0) errMsg = @"Dữ liệu từ điển tải về không hợp lệ.";
            [self failJob:job message:errMsg];
            return;
        }

        vdict::VdictReader verify;
        uint32_t entryCount = 0;
        if (verify.openFile(outURL.path.UTF8String))
            entryCount = verify.info().entryCount;

        @synchronized (_installedMeta) {
            [_activeJobs removeObjectForKey:dictId];
            NSMutableDictionary* saved = [NSMutableDictionary dictionary];
            saved[@"id"] = dictId;
            saved[@"name"] = ce ? SafeUTF8String(ce->name) : dictId;
            saved[@"shortName"] = ce ? SafeUTF8String(ce->shortName) : dictId;
            saved[@"badge"] = ce ? SafeUTF8String(ce->badge) : @"";
            saved[@"priority"] = @(ce ? ce->priority : 250);
            saved[@"enabled"] = @YES;
            saved[@"entryCount"] = @(entryCount);
            _installedMeta[dictId] = saved;
            [self persistStateLocked];
        }
        [self reloadEngine];
        [self notifyChanged];
    });
}

#pragma mark - Enable / Remove / Custom Import

-(void)setDictionaryID:(NSString*)dictId enabled:(BOOL)enabled {
    @synchronized (_installedMeta) {
        NSMutableDictionary* meta = _installedMeta[dictId];
        if (!meta) return;
        meta[@"enabled"] = @(enabled);
        [self persistStateLocked];
    }
    [self reloadEngine];
    [self notifyChanged];
}

-(void)removeDictionaryID:(NSString*)dictId {
    if ([_activeJobs objectForKey:dictId] != nil)
        [self cancelDownloadForID:dictId];

    NSURL* fileURL = [self vdictURLForID:dictId];
    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
    @synchronized (_installedMeta) {
        [_installedMeta removeObjectForKey:dictId];
        [self persistStateLocked];
    }
    [self reloadEngine];
    [self notifyChanged];
}

-(void)importLocalURL:(NSURL*)url
           completion:(void (^)(VOKDictionaryCatalogItem* _Nullable item, NSError* _Nullable error))completion {
    if (url == nil) {
        if (completion) completion(nil, DictionaryError(1, @"Không có tệp được chọn."));
        return;
    }
    NSURL* urlCopy = [url copy];
    dispatch_async(_workQueue, ^{
        NSString* rawStem = urlCopy.URLByDeletingPathExtension.lastPathComponent ?: @"custom-dict";
        if ([rawStem.lowercaseString hasSuffix:@".stardict"])
            rawStem = [rawStem substringToIndex:rawStem.length - 9];
        NSString* dictId = [NSString stringWithFormat:@"custom-%@", [[NSUUID UUID] UUIDString].lowercaseString];
        dictId = [dictId substringToIndex:MIN((NSUInteger)24, dictId.length)];

        vdict::CompileMetadata meta;
        meta.dictId = dictId.UTF8String;
        meta.displayName = ""; // compileStarDictToFile reads bookname from .ifo if available
        meta.shortName = rawStem.UTF8String;
        meta.badge = "FILE";

        NSURL* outURL = [self vdictURLForID:dictId];
        std::string cppErr;
        if (!vdict::compileLocalPathToFile(urlCopy.path.UTF8String, meta, outURL.path.UTF8String, &cppErr)) {
            NSString* msg = SafeUTF8String(cppErr);
            if (msg.length == 0) msg = @"Không đọc được bộ từ điển StarDict từ tệp hoặc thư mục này.";
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, DictionaryError(2, msg));
            });
            return;
        }

        vdict::VdictReader reader;
        uint32_t entryCount = 0;
        NSString* finalName = rawStem;
        if (reader.openFile(outURL.path.UTF8String)) {
            entryCount = reader.info().entryCount;
            if (!reader.info().displayName.empty() && reader.info().dictId != reader.info().displayName)
                finalName = SafeUTF8String(reader.info().displayName);
        }
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:outURL.path error:nil];
        uint64_t fileBytes = [attrs fileSize];

        @synchronized (_installedMeta) {
            NSMutableDictionary* saved = [NSMutableDictionary dictionary];
            saved[@"id"] = dictId;
            saved[@"name"] = finalName;
            saved[@"shortName"] = rawStem.length <= 16 ? rawStem : [rawStem substringToIndex:16];
            saved[@"badge"] = @"FILE";
            saved[@"priority"] = @250;
            saved[@"enabled"] = @YES;
            saved[@"entryCount"] = @(entryCount);
            saved[@"fileBytes"] = @(fileBytes);
            _installedMeta[dictId] = saved;
            [self persistStateLocked];
        }
        [self reloadEngine];
        [self notifyChanged];

        VOKDictionaryCatalogItem* importedItem = nil;
        for (VOKDictionaryCatalogItem* candidate in [self allDictionaries]) {
            if ([candidate.dictId isEqualToString:dictId]) {
                importedItem = candidate;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(importedItem, nil);
        });
    });
}

@end
