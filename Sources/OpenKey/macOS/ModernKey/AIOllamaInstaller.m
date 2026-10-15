//
//  AIOllamaInstaller.m
//  VOpenKey
//

#import "AIOllamaInstaller.h"
#import "AppInfo.h"
#import "AIOllama.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSError* InstallError(VOKAILocalErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAILocalErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL IsPlainIdentifier(NSString* text) {
    if (text.length == 0 || text.length > 100)
        return NO;
    NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-"];
    return [text rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

#pragma mark - Running tools

/// Runs a program of the system and gives its output (both streams) and exit status. Stops it after `timeout` seconds.
static BOOL RunTool(NSString* path, NSArray<NSString*>* arguments, NSTimeInterval timeout, NSString** output, int* status, NSTask* __strong * holder) {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSMutableData* collected = [NSMutableData data];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
        NSData* data = [handle availableData];
        if (data.length > 0) {
            @synchronized (collected) { if (collected.length < (1 << 20)) [collected appendData:data]; }
        }
    };
    task.terminationHandler = ^(NSTask* t) { dispatch_semaphore_signal(finished); };
    NSError* launchError = nil;
    if (holder) *holder = task;
    if (![task launchAndReturnError:&launchError]) {
        pipe.fileHandleForReading.readabilityHandler = nil;
        if (output) *output = launchError.localizedDescription;
        return NO;
    }
    BOOL timedOut = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0;
    if (timedOut) {
        [task terminate];
        dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    pipe.fileHandleForReading.readabilityHandler = nil;
    NSData* rest = [pipe.fileHandleForReading readDataToEndOfFile];
    @synchronized (collected) { [collected appendData:rest]; }
    if (holder) *holder = nil;
    if (output) *output = [[NSString alloc] initWithData:collected encoding:NSUTF8StringEncoding] ?: @"";
    if (status) *status = timedOut ? -1 : task.terminationStatus;
    return !timedOut;
}

static NSOperatingSystemVersion ParseVersion(NSString* text) {
    NSArray<NSString*>* parts = [text componentsSeparatedByString:@"."];
    NSOperatingSystemVersion v = {0, 0, 0};
    if (parts.count > 0) v.majorVersion = [parts[0] integerValue];
    if (parts.count > 1) v.minorVersion = [parts[1] integerValue];
    if (parts.count > 2) v.patchVersion = [parts[2] integerValue];
    return v;
}

#pragma mark - The verifier

@implementation AIOllamaVerifier

-(instancetype)initWithTeamIdentifier:(NSString*)teamIdentifier bundleIdentifier:(NSString*)bundleIdentifier {
    if (!IsPlainIdentifier(teamIdentifier) || !IsPlainIdentifier(bundleIdentifier))
        return nil;                                         //they go into a requirement: no quotes, no operators
    self = [super init];
    if (self) {
        _teamIdentifier = [teamIdentifier copy];
        _bundleIdentifier = [bundleIdentifier copy];
        _requiresNotarization = YES;
    }
    return self;
}

+(AIOllamaVerifier*)standard {
    //Infra Technologies, Inc, the company that makes Ollama. Found on the application of the official download, which Apple
    //notarized (see the note ai-local-setup of the project). If Ollama ever signs with another identity, the download is
    //refused until this is updated: that is the point of pinning.
    return [[AIOllamaVerifier alloc] initWithTeamIdentifier:@"3MU9H2V9Y9" bundleIdentifier:@"com.electron.ollama"];
}

/// Checks the signature of one thing (the application, or a program inside) against a requirement.
-(BOOL)checkPath:(NSURL*)url requirement:(NSString*)requirementText name:(NSString*)name error:(NSError**)error {
    SecStaticCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    BOOL ok = NO;
    CFErrorRef failure = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecRequirementCreateWithString((__bridge CFStringRef)requirementText, kSecCSDefaultFlags, &requirement) == errSecSuccess) {
        OSStatus status = SecStaticCodeCheckValidityWithErrors(code, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate, requirement, &failure);
        ok = status == errSecSuccess;
    }
    if (failure != NULL) CFRelease(failure);
    if (code != NULL) CFRelease(code);
    if (requirement != NULL) CFRelease(requirement);
    if (!ok && error != NULL)
        *error = InstallError(VOKAILocalErrorUnsafeDownload,
                              [NSString stringWithFormat:@"%@ không phải bản chính thức của Ollama (chữ ký số không khớp hoặc đã bị sửa). VOpenKey AI không cài nó.", name]);
    return ok;
}

-(NSString*)requirementForIdentifier:(BOOL)withIdentifier {
    //signed by a Developer ID certificate of the Team ID, issued by Apple
    NSMutableString* text = [NSMutableString stringWithString:@"anchor apple generic"];
    if (withIdentifier)
        [text appendFormat:@" and identifier \"%@\"", self.bundleIdentifier];
    [text appendFormat:@" and certificate leaf[subject.OU] = \"%@\"", self.teamIdentifier];
    [text appendString:@" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"];
    return text;
}

-(BOOL)verifySignatureOfApplication:(NSURL*)app error:(NSError**)error {
    if (![self checkPath:app requirement:[self requirementForIdentifier:YES] name:@"Ứng dụng tải về" error:error])
        return NO;
    NSURL* server = [app URLByAppendingPathComponent:@"Contents/Resources/ollama"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:server.path]) {
        if (error) *error = InstallError(VOKAILocalErrorUnsafeDownload, @"Bản tải về không có chương trình chạy model (ollama).");
        return NO;
    }
    //the server is a program of its own inside the application: its signature is checked on its own, and it must be the
    //same signer (its identifier is not the one of the application)
    return [self checkPath:server requirement:[self requirementForIdentifier:NO] name:@"Chương trình chạy model" error:error];
}

-(BOOL)verifyApplication:(NSURL*)app minimumOS:(NSOperatingSystemVersion*)minimumOS error:(NSError**)error {
    NSDictionary* info = [NSDictionary dictionaryWithContentsOfURL:[app URLByAppendingPathComponent:@"Contents/Info.plist"]];
    if (![info[@"CFBundleIdentifier"] isEqual:self.bundleIdentifier]) {
        if (error) *error = InstallError(VOKAILocalErrorUnsafeDownload, @"Bản tải về không phải ứng dụng Ollama (tên định danh không khớp). VOpenKey AI không cài nó.");
        return NO;
    }
    if (![self verifySignatureOfApplication:app error:error])
        return NO;
    if (self.requiresNotarization) {
        NSString* output = nil;
        int status = 0;
        BOOL ran = RunTool(@"/usr/sbin/spctl", @[@"--assess", @"--type", @"execute", @"--verbose=4", app.path], 120, &output, &status, NULL);
        if (!ran || status != 0 || ![output containsString:@"source=Notarized Developer ID"]) {
            if (error) *error = InstallError(VOKAILocalErrorUnsafeDownload, @"Không xác nhận được Apple đã công chứng bản tải về này (macOS sẽ không cho chạy nó). Có thể do mạng, hoặc bản tải về không hợp lệ. VOpenKey AI không cài; hãy thử lại sau.");
            return NO;
        }
    }
    if (minimumOS != NULL)
        *minimumOS = [info[@"LSMinimumSystemVersion"] isKindOfClass:[NSString class]] ? ParseVersion(info[@"LSMinimumSystemVersion"]) : (NSOperatingSystemVersion){0, 0, 0};
    return YES;
}

@end

#pragma mark - The installer

static NSString* const kWorkPrefix = @"ollama-install-";

@interface AIOllamaInstaller () <NSURLSessionDownloadDelegate>
@end

@implementation AIOllamaInstaller {
    NSURL* _releaseURL;
    NSURL* _fallbackURL;
    NSURL* _installDirectory;
    NSURL* _workDirectory;
    AIOllamaVerifier* _verifier;
    dispatch_queue_t _queue;
    BOOL _cancelled;
    BOOL _running;
    NSURLSession* _session;
    NSURLSessionTask* _task;
    NSTask* _tool;
    //the download in progress
    dispatch_semaphore_t _downloadDone;
    NSURL* _downloadTarget;             //where the file is moved to as soon as it is complete
    BOOL _downloadSaved;
    BOOL _downloadTooBig;
    NSError* _downloadError;
    void (^_downloadProgress)(uint64_t done, uint64_t total);
    NSInteger _downloadStatus;
}

+(NSString*)applicationName { return @"Ollama.app"; }

+(NSURL*)defaultInstallDirectory {
    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Applications"] isDirectory:YES];
}

+(AIOllamaInstaller*)standardInstaller {
    NSURL* support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                      URLByAppendingPathComponent:VOK_DATA_DIR_NAME isDirectory:YES];
    return [[AIOllamaInstaller alloc] initWithReleaseURL:[NSURL URLWithString:@"https://api.github.com/repos/ollama/ollama/releases/latest"]
                                             fallbackURL:[NSURL URLWithString:@"https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip"]
                                        installDirectory:[self defaultInstallDirectory] workDirectory:support verifier:[AIOllamaVerifier standard]];
}

-(instancetype)initWithReleaseURL:(NSURL*)releaseURL fallbackURL:(NSURL*)fallbackURL installDirectory:(NSURL*)installDirectory
                    workDirectory:(NSURL*)workDirectory verifier:(AIOllamaVerifier*)verifier {
    if (releaseURL == nil || installDirectory == nil || workDirectory == nil || verifier == nil)
        return nil;
    self = [super init];
    if (self) {
        _releaseURL = releaseURL;
        _fallbackURL = fallbackURL;
        _installDirectory = installDirectory;
        _workDirectory = workDirectory;
        _verifier = verifier;
        _queue = dispatch_queue_create("vn.io.lssoft.vopenkey.ollama-install", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark Cancelling

-(BOOL)isCancelled {
    @synchronized (self) { return _cancelled; }
}

-(void)cancel {
    @synchronized (self) {
        _cancelled = YES;
        [_task cancel];
        if (_tool.isRunning)
            [_tool terminate];
    }
}

#pragma mark Allowed addresses

/// Whether an address may be fetched: https, or this Mac (for tests).
static BOOL AddressAllowed(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"])
        return url.host.length > 0;
    NSString* host = url.host.lowercaseString;
    return [scheme isEqualToString:@"http"] && ([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"]);
}

#pragma mark Running

-(void)installWithProgress:(void (^)(AIInstallPhase, double, uint64_t, uint64_t))progress
                completion:(void (^)(NSURL*, NSError*))completion {
    @synchronized (self) {
        if (_running) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, InstallError(VOKAILocalErrorInstall, @"Đang cài rồi.")); });
            return;
        }
        _running = YES;
        _cancelled = NO;
    }
    dispatch_async(_queue, ^{
        NSError* error = nil;
        NSURL* app = [self runWithProgress:progress error:&error];
        @synchronized (self) {
            [_session invalidateAndCancel];
            _session = nil;
            _task = nil;
            _running = NO;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error == nil ? app : nil, error); });
    });
}

-(void)report:(void (^)(AIInstallPhase, double, uint64_t, uint64_t))progress phase:(AIInstallPhase)phase fraction:(double)fraction done:(uint64_t)done total:(uint64_t)total {
    if (progress != nil)
        dispatch_async(dispatch_get_main_queue(), ^{ progress(phase, fraction, done, total); });
}

-(NSError*)cancelledError { return InstallError(VOKAILocalErrorCancelled, @"Đã hủy."); }

-(NSURL*)runWithProgress:(void (^)(AIInstallPhase, double, uint64_t, uint64_t))progress error:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* work = nil;
    NSURL* app = nil;
    @try {
        //1. which file
        [self report:progress phase:AIInstallPhaseLooking fraction:-1 done:0 total:0];
        NSURL* fileURL = nil; uint64_t size = 0; NSString* sha = nil;
        if (![self lookUpRelease:&fileURL size:&size sha256:&sha error:error])
            return nil;
        if ([self isCancelled]) { *error = [self cancelledError]; return nil; }

        //2. a folder of its own, that nobody else can read, in which nothing exists yet
        if (![fm createDirectoryAtURL:_workDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
            *error = InstallError(VOKAILocalErrorInstall, @"Không tạo được thư mục làm việc của VOpenKey AI.");
            return nil;
        }
        work = [_workDirectory URLByAppendingPathComponent:[kWorkPrefix stringByAppendingString:[[NSUUID UUID] UUIDString]] isDirectory:YES];
        if (![fm createDirectoryAtURL:work withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:nil]) {
            *error = InstallError(VOKAILocalErrorInstall, @"Không tạo được thư mục tạm để tải Ollama.");
            return nil;
        }

        //3. download
        NSURL* zip = [work URLByAppendingPathComponent:@"Ollama-darwin.zip"];
        if (![self download:fileURL to:zip expectedSize:size progress:^(uint64_t done, uint64_t total) {
                [self report:progress phase:AIInstallPhaseDownloading fraction:total > 0 ? (double)done / (double)total : -1 done:done total:total];
            } error:error])
            return nil;

        //4. the file is the one that was published
        [self report:progress phase:AIInstallPhaseVerifying fraction:-1 done:0 total:0];
        if (![self checkFile:zip size:size sha256:sha error:error])
            return nil;
        if ([self isCancelled]) { *error = [self cancelledError]; return nil; }

        //5. opened in an empty folder; only the application may come out
        NSURL* extract = [work URLByAppendingPathComponent:@"extracted" isDirectory:YES];
        [fm createDirectoryAtURL:extract withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:nil];
        NSString* output = nil; int status = 0;
        BOOL ran = RunTool(@"/usr/bin/ditto", @[@"-x", @"-k", zip.path, extract.path], 600, &output, &status, &_tool);
        if ([self isCancelled]) { *error = [self cancelledError]; return nil; }
        if (!ran || status != 0) {
            *error = InstallError(VOKAILocalErrorUnsafeDownload, @"File tải về không giải nén được: nó bị hỏng. Hãy thử lại.");
            return nil;
        }
        NSArray<NSString*>* items = [fm contentsOfDirectoryAtPath:extract.path error:nil];
        NSURL* extractedApp = [extract URLByAppendingPathComponent:[AIOllamaInstaller applicationName] isDirectory:YES];
        BOOL isDirectory = NO;
        if (items.count != 1 || ![items[0] isEqualToString:[AIOllamaInstaller applicationName]] ||
            ![fm fileExistsAtPath:extractedApp.path isDirectory:&isDirectory] || !isDirectory) {
            *error = InstallError(VOKAILocalErrorUnsafeDownload, @"File tải về không đúng cấu trúc của Ollama. VOpenKey AI không cài nó.");
            return nil;
        }
        if ([[fm contentsOfDirectoryAtPath:work.path error:nil] count] != 2) {          //the zip and "extracted", nothing else
            *error = InstallError(VOKAILocalErrorUnsafeDownload, @"File tải về có nội dung lạ. VOpenKey AI không cài nó.");
            return nil;
        }

        //6. who made it
        NSOperatingSystemVersion minimum;
        if (![_verifier verifyApplication:extractedApp minimumOS:&minimum error:error])
            return nil;
        if ([self isCancelled]) { *error = [self cancelledError]; return nil; }
        if (minimum.majorVersion > 0 && ![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:minimum]) {
            *error = InstallError(VOKAILocalErrorUnsupported, [NSString stringWithFormat:@"Bản Ollama mới nhất cần macOS %ld.%ld trở lên, máy bạn thấp hơn. Hãy cập nhật macOS, hoặc dùng AI qua dịch vụ trực tuyến.",
                                                               (long)minimum.majorVersion, (long)minimum.minorVersion]);
            return nil;
        }

        //7. in its place
        [self report:progress phase:AIInstallPhaseInstalling fraction:-1 done:0 total:0];
        app = [self place:extractedApp error:error];
        if (app == nil)
            return nil;
        if (![_verifier verifySignatureOfApplication:app error:error]) {                //still intact after the move
            [fm removeItemAtURL:app error:nil];
            return nil;
        }
        return app;
    } @finally {
        if (work != nil)
            [fm removeItemAtURL:work error:nil];
    }
}

#pragma mark Steps

/// Reads the description of the latest release; falls back to the plain address of the file.
-(BOOL)lookUpRelease:(NSURL**)fileURL size:(uint64_t*)size sha256:(NSString**)sha error:(NSError**)error {
    if (!AddressAllowed(_releaseURL)) {
        *error = InstallError(VOKAILocalErrorInstall, @"Địa chỉ tải Ollama không hợp lệ.");
        return NO;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:_releaseURL];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    request.timeoutInterval = 20;
    NSData* data = nil; NSInteger status = 0; NSError* networkError = nil;
    [self fetch:request data:&data status:&status error:&networkError];
    if ([self isCancelled]) { *error = [self cancelledError]; return NO; }
    id object = status == 200 && data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray* assets = [object isKindOfClass:[NSDictionary class]] ? object[@"assets"] : nil;
    NSDictionary* asset = nil;
    if ([assets isKindOfClass:[NSArray class]]) {
        for (id candidate in assets)
            if ([candidate isKindOfClass:[NSDictionary class]] && [candidate[@"name"] isEqual:@"Ollama-darwin.zip"])
                asset = candidate;
    }
    if (asset != nil) {
        NSURL* url = [asset[@"browser_download_url"] isKindOfClass:[NSString class]] ? [NSURL URLWithString:asset[@"browser_download_url"]] : nil;
        if (url == nil || !AddressAllowed(url)) {
            *error = InstallError(VOKAILocalErrorUnsafeDownload, @"Thông tin bản phát hành của Ollama có địa chỉ tải không an toàn. VOpenKey AI không tải.");
            return NO;
        }
        *fileURL = url;
        *size = [asset[@"size"] isKindOfClass:[NSNumber class]] ? [asset[@"size"] unsignedLongLongValue] : 0;
        NSString* digest = [asset[@"digest"] isKindOfClass:[NSString class]] ? asset[@"digest"] : nil;
        if (digest != nil) {
            NSString* hex = [digest hasPrefix:@"sha256:"] ? [digest substringFromIndex:7] : nil;
            NSCharacterSet* hexDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
            if (hex.length != 64 || [hex rangeOfCharacterFromSet:hexDigits.invertedSet].location != NSNotFound) {
                *error = InstallError(VOKAILocalErrorUnsafeDownload, @"Mã kiểm tra của file Ollama (SHA-256) không đọc được. VOpenKey AI không tải.");
                return NO;
            }
            *sha = hex.lowercaseString;
        }
        return YES;
    }
    //the description is not available (GitHub answers 403 when it was asked too often) or has no such file
    if (_fallbackURL != nil && AddressAllowed(_fallbackURL) && (networkError != nil || status == 403 || status == 429 || status >= 500 || status == 200)) {
        *fileURL = _fallbackURL;
        *size = 0;
        *sha = nil;
        return YES;
    }
    *error = networkError != nil
        ? InstallError(VOKAILocalErrorFailed, @"Không kết nối được tới GitHub để tải Ollama. Hãy kiểm tra mạng rồi thử lại.")
        : InstallError(VOKAILocalErrorFailed, @"Không đọc được thông tin bản Ollama mới nhất từ GitHub. Hãy thử lại sau ít phút.");
    return NO;
}

-(NSURLSession*)session {
    @synchronized (self) {
        if (_session == nil) {
            NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            configuration.URLCache = nil;
            configuration.HTTPCookieStorage = nil;
            configuration.timeoutIntervalForRequest = 60;
            configuration.timeoutIntervalForResource = 3600;
            NSOperationQueue* queue = [[NSOperationQueue alloc] init];
            queue.maxConcurrentOperationCount = 1;
            _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
        }
        return _session;
    }
}

/// A small request, waited for.
-(void)fetch:(NSURLRequest*)request data:(NSData**)data status:(NSInteger*)status error:(NSError**)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData* body = nil; __block NSInteger code = 0; __block NSError* failure = nil;
    NSURLSessionDataTask* task = [[self session] dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* response, NSError* e) {
        body = d; failure = e;
        code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*)response statusCode] : 0;
        dispatch_semaphore_signal(done);
    }];
    @synchronized (self) { _task = task; if (_cancelled) [task cancel]; }
    [task resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    *data = body; *status = code; *error = failure;
}

-(BOOL)download:(NSURL*)url to:(NSURL*)destination expectedSize:(uint64_t)size progress:(void (^)(uint64_t, uint64_t))progress error:(NSError**)error {
    _downloadDone = dispatch_semaphore_create(0);
    _downloadTarget = destination;
    _downloadSaved = NO;
    _downloadTooBig = NO;
    _downloadError = nil;
    _downloadStatus = 0;
    _downloadProgress = progress;
    NSURLSessionDownloadTask* task = [[self session] downloadTaskWithURL:url];
    @synchronized (self) { _task = task; if (_cancelled) [task cancel]; }
    [task resume];
    dispatch_semaphore_wait(_downloadDone, DISPATCH_TIME_FOREVER);
    _downloadProgress = nil;
    if ([self isCancelled]) { *error = [self cancelledError]; return NO; }
    if (_downloadTooBig) {
        *error = InstallError(VOKAILocalErrorUnsafeDownload, @"File tải về lớn bất thường so với Ollama. VOpenKey AI dừng lại và không cài.");
        return NO;
    }
    if (_downloadError != nil || !_downloadSaved) {
        *error = _downloadStatus >= 400
            ? InstallError(VOKAILocalErrorFailed, [NSString stringWithFormat:@"Máy chủ tải Ollama trả về lỗi %ld. Hãy thử lại sau ít phút.", (long)_downloadStatus])
            : InstallError(VOKAILocalErrorFailed, @"Tải Ollama bị gián đoạn. Hãy kiểm tra mạng rồi thử lại.");
        return NO;
    }
    return YES;
}

/// The size and the hash published for the file. A size of 0 and a nil hash mean that nothing was published.
-(BOOL)checkFile:(NSURL*)file size:(uint64_t)size sha256:(NSString*)sha error:(NSError**)error {
    NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:nil];
    uint64_t actual = [attributes fileSize];
    if (actual == 0 || (size > 0 && actual != size)) {
        *error = InstallError(VOKAILocalErrorUnsafeDownload, @"File Ollama tải về không đủ dung lượng như công bố: bị cắt hoặc bị thay. VOpenKey AI không cài nó.");
        return NO;
    }
    if (sha == nil)
        return YES;
    NSFileHandle* handle = [NSFileHandle fileHandleForReadingFromURL:file error:nil];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    for (;;) {
        @autoreleasepool {
            NSData* chunk = [handle readDataUpToLength:1 << 20 error:nil];
            if (chunk.length == 0)
                break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [handle closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString* hex = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", digest[i]];
    if (![hex isEqualToString:sha]) {
        *error = InstallError(VOKAILocalErrorUnsafeDownload, @"Mã kiểm tra (SHA-256) của file Ollama không khớp với mã GitHub công bố: file bị hỏng hoặc bị thay. VOpenKey AI không cài nó.");
        return NO;
    }
    return YES;
}

/// Moves the verified application to ~/Applications/Ollama.app. What was there is kept until the new one is in place.
-(NSURL*)place:(NSURL*)extractedApp error:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* failure = nil;
    if (![fm createDirectoryAtURL:_installDirectory withIntermediateDirectories:YES attributes:nil error:&failure]) {
        *error = InstallError(VOKAILocalErrorInstall, @"Không tạo được thư mục ~/Applications.");
        return nil;
    }
    NSURL* destination = [_installDirectory URLByAppendingPathComponent:[AIOllamaInstaller applicationName] isDirectory:YES];
    NSURL* previous = nil;
    if ([fm fileExistsAtPath:destination.path]) {
        previous = [_installDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@".Ollama-old-%@", [[NSUUID UUID] UUIDString]] isDirectory:YES];
        if (![fm moveItemAtURL:destination toURL:previous error:&failure]) {
            *error = InstallError(VOKAILocalErrorInstall, @"Không thay được bản Ollama cũ trong ~/Applications.");
            return nil;
        }
    }
    if (![fm moveItemAtURL:extractedApp toURL:destination error:&failure]) {
        if (previous != nil)
            [fm moveItemAtURL:previous toURL:destination error:nil];                      //put the old one back
        *error = InstallError(VOKAILocalErrorInstall, @"Không đưa Ollama vào ~/Applications được.");
        return nil;
    }
    if (previous != nil)
        [fm removeItemAtURL:previous error:nil];
    return destination;
}

+(void)removeLeftoversInWorkDirectory:(NSURL*)workDirectory {
    NSFileManager* fm = [NSFileManager defaultManager];
    for (NSString* name in [fm contentsOfDirectoryAtPath:workDirectory.path error:nil]) {
        if ([name hasPrefix:kWorkPrefix])
            [fm removeItemAtURL:[workDirectory URLByAppendingPathComponent:name] error:nil];
    }
}

#pragma mark Session delegate

/// Ollama is about 200 MB. A file several times that is not Ollama: stop before it fills the disk.
static const int64_t kMaxDownload = 1500LL * 1000 * 1000;

-(void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)task didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    if (total > kMaxDownload || expected > kMaxDownload) {
        _downloadTooBig = YES;
        [task cancel];
        return;
    }
    void (^progress)(uint64_t, uint64_t) = _downloadProgress;
    if (progress != nil)
        progress((uint64_t)total, expected > 0 ? (uint64_t)expected : 0);
}

-(void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)task didFinishDownloadingToURL:(NSURL*)location {
    NSInteger status = [task.response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*)task.response statusCode] : 0;
    _downloadStatus = status;
    if (status != 200)
        return;
    //the file of the system is deleted when this method returns: it goes at once to the private folder of this run
    _downloadSaved = [[NSFileManager defaultManager] moveItemAtURL:location toURL:_downloadTarget error:nil];
}

-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    if (![task isKindOfClass:[NSURLSessionDownloadTask class]])
        return;
    _downloadError = error;
    dispatch_semaphore_signal(_downloadDone);
}

//only https (or this Mac, for tests) is followed: a redirect to plain http would let anyone on the way swap the file
-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response
        newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler {
    completionHandler(AddressAllowed(request.URL) ? request : nil);
}

@end
