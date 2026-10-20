//
//  AppUpdater.m
//  VOpenKey
//
//  Programs are started with posix_spawn and not with NSTask on purpose: NSTask turns every argument into the decomposed form of Unicode,
//  and the home folder of a user (it is in the paths here) can have Vietnamese letters in its name.
//

#import "AppUpdater.h"
#import "AppInfo.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <crt_externs.h>
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

NSString* const AppUpdaterDidChangeNotification = @"AppUpdaterDidChangeNotification";
NSString* const AppUpdateErrorDomain = @"vn.io.lssoft.vopenkey.update";

static NSString* const kAutoInstallKey = @"AutoInstallUpdates";
static NSString* const kTriedVersionKey = @"UpdateInstallTriedVersion";
static NSString* const kDownloadPrefix = @"download-";
static NSString* const kReadyFolder = @"ready";
static NSString* const kResultFile = @"result";

//the dmg is about 3 MB. A file many times that is not VOpenKey AI: stop before it fills the disk.
static const int64_t kMaxDownload = 300LL * 1000 * 1000;

static NSError* UpdateError(AppUpdateErrorCode code, NSString* message) {
    return [NSError errorWithDomain:AppUpdateErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL IsHex(NSString* text, NSUInteger length) {
    if (text.length != length)
        return NO;
    NSCharacterSet* hexDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [text rangeOfCharacterFromSet:hexDigits.invertedSet].location == NSNotFound;
}

static BOOL IsPlainIdentifier(NSString* text) {
    if (text.length == 0 || text.length > 100)
        return NO;
    NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-"];
    return [text rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

/// Whether an address may be fetched: https, or this Mac (for tests).
static BOOL AddressAllowed(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"])
        return url.host.length > 0;
    NSString* host = url.host.lowercaseString;
    return [scheme isEqualToString:@"http"] && ([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"]);
}

static NSString* WithoutTrailingSlashes(NSString* text) {
    while ([text hasSuffix:@"/"])
        text = [text substringToIndex:text.length - 1];
    return text;
}

#pragma mark - Running programs

//Starts a program. With `detached` it gets a session of its own, so that it goes on when this app has quit. Standard input is nothing,
//the output goes to `output` (a descriptor) or nowhere. Returns the pid, or 0 with the error number in *code.
static pid_t SpawnProgram(NSString* path, NSArray<NSString*>* arguments, int output, BOOL detached, int* code) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    if (output >= 0) {
        posix_spawn_file_actions_adddup2(&actions, output, 1);          //dup2 gives the new descriptor without close-on-exec
        posix_spawn_file_actions_adddup2(&actions, output, 2);
    } else {
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    }
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attributes, &none);                     //not what this app had blocked or ignored (SIGPIPE...)
    posix_spawnattr_setsigdefault(&attributes, &all);
    short flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
    if (detached) {
        flags |= POSIX_SPAWN_SETSID;
    } else {
        posix_spawnattr_setpgroup(&attributes, 0);                      //a group of its own: stopping it stops what it started
        flags |= POSIX_SPAWN_SETPGROUP;
    }
    posix_spawnattr_setflags(&attributes, flags);

    NSMutableArray<NSString*>* argv = [NSMutableArray arrayWithObject:path];
    [argv addObjectsFromArray:arguments];
    char** list = calloc(argv.count + 1, sizeof(char*));
    for (NSUInteger i = 0; i < argv.count; i++)
        list[i] = strdup(argv[i].UTF8String);
    pid_t pid = 0;
    int result = posix_spawn(&pid, path.fileSystemRepresentation, &actions, &attributes, list, *_NSGetEnviron());
    for (NSUInteger i = 0; i < argv.count; i++)
        free(list[i]);
    free(list);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    if (result != 0) {
        if (code != NULL) *code = result;
        return 0;
    }
    return pid;
}

/// Runs a program of the system and waits for it; YES when it ended with status 0 within `timeout` seconds (it is stopped after that).
/// What it says is thrown away: the answer of the tools used here is their status.
static BOOL RunTool(NSString* path, NSArray<NSString*>* arguments, NSTimeInterval timeout) {
    int code = 0;
    pid_t pid = SpawnProgram(path, arguments, -1, NO, &code);
    if (pid == 0)
        return NO;
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    int raw = 0;
    for (;;) {
        pid_t done = waitpid(pid, &raw, WNOHANG);
        if (done == pid)
            return WIFEXITED(raw) && WEXITSTATUS(raw) == 0;
        if (done < 0 && errno != EINTR)
            return NO;
        if (deadline.timeIntervalSinceNow <= 0) {
            killpg(pid, SIGKILL);
            waitpid(pid, &raw, 0);
            return NO;
        }
        usleep(20000);
    }
}

#pragma mark - A release

@implementation AppUpdateRelease

-(instancetype)initWithVersion:(NSString*)version pageURL:(NSURL*)pageURL fileURL:(NSURL*)fileURL size:(uint64_t)size
                        sha256:(NSString*)sha256 checksumURL:(NSURL*)checksumURL {
    self = [super init];
    if (self) {
        _version = [version copy];
        _pageURL = [pageURL copy];
        _fileURL = [fileURL copy];
        _size = size;
        _sha256 = [sha256 copy];
        _checksumURL = [checksumURL copy];
    }
    return self;
}

-(id)copyWithZone:(NSZone*)zone {
    return self;                                                        //immutable
}

static NSArray<NSNumber*>* VersionNumbers(NSString* text) {
    NSArray<NSString*>* parts = [text componentsSeparatedByString:@"."];
    if (parts.count != 3)
        return nil;
    NSMutableArray<NSNumber*>* numbers = [NSMutableArray array];
    for (NSString* part in parts) {
        if (part.length == 0 || part.length > 6)
            return nil;
        NSCharacterSet* digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
        if ([part rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound)
            return nil;
        [numbers addObject:@(part.integerValue)];
    }
    return numbers;
}

+(BOOL)isValidVersion:(NSString*)text {
    return [text isKindOfClass:[NSString class]] && VersionNumbers(text) != nil;
}

+(NSComparisonResult)compareVersion:(NSString*)a toVersion:(NSString*)b {
    NSArray<NSNumber*>* x = VersionNumbers(a);
    NSArray<NSNumber*>* y = VersionNumbers(b);
    if (x == nil || y == nil)
        return x == nil && y == nil ? NSOrderedSame : (x == nil ? NSOrderedAscending : NSOrderedDescending);
    for (NSUInteger i = 0; i < 3; i++) {
        NSComparisonResult result = [x[i] compare:y[i]];
        if (result != NSOrderedSame)
            return result;
    }
    return NSOrderedSame;
}

+(NSString*)fileNameForVersion:(NSString*)version {
    return [NSString stringWithFormat:@"%@-%@.dmg", VOK_RELEASE_FILE_NAME, version];
}

/// "v3.7.5" -> "3.7.5"; nil when it is not a tag of a release.
static NSString* VersionOfTag(NSString* tag) {
    if (![tag isKindOfClass:[NSString class]] || ![tag hasPrefix:@"v"])
        return nil;
    NSString* version = [tag substringFromIndex:1];
    return [AppUpdateRelease isValidVersion:version] ? version : nil;
}

+(AppUpdateRelease*)releaseFromAPIData:(NSData*)data repository:(NSURL*)repository error:(NSError**)error {
    NSError* __autoreleasing ignored = nil;
    if (error == NULL) error = &ignored;
    id object = data.length > 0 && data.length < (4 << 20) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![object isKindOfClass:[NSDictionary class]]) {
        *error = UpdateError(AppUpdateErrorNoRelease, @"Không đọc được thông tin bản phát hành mới nhất từ GitHub.");
        return nil;
    }
    if ([object[@"draft"] boolValue] || [object[@"prerelease"] boolValue]) {
        *error = UpdateError(AppUpdateErrorNoRelease, @"Bản phát hành mới nhất chưa sẵn sàng.");
        return nil;
    }
    NSString* tag = object[@"tag_name"];
    NSString* version = VersionOfTag(tag);
    if (version == nil) {
        *error = UpdateError(AppUpdateErrorNoRelease, @"Bản phát hành mới nhất có tên lạ (không dạng v3.7.5).");
        return nil;
    }
    NSString* base = WithoutTrailingSlashes(repository.absoluteString);
    NSString* prefix = [base stringByAppendingString:@"/releases/download/"];
    NSString* fileName = [self fileNameForVersion:version];
    NSString* checksumName = [fileName stringByAppendingString:@".sha256"];
    NSDictionary* file = nil;
    NSURL* checksumURL = nil;
    NSArray* assets = [object[@"assets"] isKindOfClass:[NSArray class]] ? object[@"assets"] : @[];
    for (id candidate in assets) {
        if (![candidate isKindOfClass:[NSDictionary class]] || ![candidate[@"name"] isKindOfClass:[NSString class]])
            continue;
        NSString* address = [candidate[@"browser_download_url"] isKindOfClass:[NSString class]] ? candidate[@"browser_download_url"] : nil;
        //a file of the repository, nowhere else
        if (address == nil || ![address hasPrefix:prefix] || [NSURL URLWithString:address] == nil)
            continue;
        if ([candidate[@"name"] isEqualToString:fileName])
            file = candidate;
        else if ([candidate[@"name"] isEqualToString:checksumName])
            checksumURL = [NSURL URLWithString:address];
    }
    if (file == nil) {
        *error = UpdateError(AppUpdateErrorNoRelease, [NSString stringWithFormat:@"Bản phát hành v%@ chưa có file %@.", version, fileName]);
        return nil;
    }
    NSString* sha = nil;
    NSString* digest = [file[@"digest"] isKindOfClass:[NSString class]] ? file[@"digest"] : nil;
    if (digest != nil) {
        NSString* hex = [digest hasPrefix:@"sha256:"] ? [digest substringFromIndex:7] : nil;
        if (!IsHex(hex, 64)) {
            *error = UpdateError(AppUpdateErrorUnsafe, @"Mã kiểm tra (SHA-256) của file cập nhật không đọc được. VOpenKey AI không tải.");
            return nil;
        }
        sha = hex.lowercaseString;
    }
    uint64_t size = [file[@"size"] isKindOfClass:[NSNumber class]] ? [file[@"size"] unsignedLongLongValue] : 0;
    NSString* page = [object[@"html_url"] isKindOfClass:[NSString class]] ? object[@"html_url"] : nil;
    NSURL* pageURL = page != nil && [page hasPrefix:base] ? [NSURL URLWithString:page] : nil;
    if (pageURL == nil)
        pageURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/releases/tag/%@", base, tag]];
    return [[AppUpdateRelease alloc] initWithVersion:version pageURL:pageURL fileURL:[NSURL URLWithString:file[@"browser_download_url"]]
                                                size:size sha256:sha checksumURL:checksumURL];
}

+(AppUpdateRelease*)releaseForTag:(NSString*)tag repository:(NSURL*)repository {
    NSString* version = VersionOfTag(tag);
    if (version == nil)
        return nil;
    NSString* base = WithoutTrailingSlashes(repository.absoluteString);
    NSString* fileName = [self fileNameForVersion:version];
    NSString* downloads = [NSString stringWithFormat:@"%@/releases/download/%@", base, tag];
    return [[AppUpdateRelease alloc] initWithVersion:version
                                             pageURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/releases/tag/%@", base, tag]]
                                             fileURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", downloads, fileName]]
                                                size:0 sha256:nil
                                         checksumURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@.sha256", downloads, fileName]]];
}

@end

#pragma mark - Who made it

@implementation AppUpdateVerifier

-(instancetype)initWithRequirement:(NSString*)requirement bundleIdentifier:(NSString*)bundleIdentifier {
    if (requirement.length == 0 || !IsPlainIdentifier(bundleIdentifier))
        return nil;
    self = [super init];
    if (self) {
        _requirement = [requirement copy];
        _bundleIdentifier = [bundleIdentifier copy];
    }
    return self;
}

+(NSString*)requirementForTeam:(NSString*)team bundleIdentifier:(NSString*)bundleIdentifier {
    if (!IsPlainIdentifier(team) || !IsPlainIdentifier(bundleIdentifier))
        return nil;                                                     //they go into a requirement: no quotes, no operators
    //signed with a Developer ID Application certificate (1.2.840.113635.100.6.1.13) of the Team, issued by Apple (...6.2.6 is Apple's
    //Developer ID intermediate certificate)
    return [NSString stringWithFormat:@"anchor apple generic and identifier \"%@\" and certificate leaf[subject.OU] = \"%@\" and "
            @"certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists",
            bundleIdentifier, team];
}

+(AppUpdateVerifier*)standard {
    //Pinned on purpose: if the releases are ever signed by another certificate, the apps that are out refuse the update (and say so),
    //and the new version has to be downloaded by hand once.
    return [[AppUpdateVerifier alloc] initWithRequirement:[self requirementForTeam:VOK_TEAM_ID bundleIdentifier:VOK_BUNDLE_ID]
                                         bundleIdentifier:VOK_BUNDLE_ID];
}

-(BOOL)verifyApplication:(NSURL*)app expectedVersion:(NSString*)version error:(NSError**)error {
    NSError* __autoreleasing ignored = nil;
    if (error == NULL) error = &ignored;
    NSDictionary* info = [NSDictionary dictionaryWithContentsOfURL:[app URLByAppendingPathComponent:@"Contents/Info.plist"]];
    if (![info[@"CFBundleIdentifier"] isEqual:self.bundleIdentifier]) {
        *error = UpdateError(AppUpdateErrorUnsafe, [NSString stringWithFormat:@"Bản tải về không phải %@ (tên định danh không khớp). VOpenKey AI không cài nó.", VOK_APP_NAME]);
        return NO;
    }
    if (![info[@"CFBundleShortVersionString"] isEqual:version]) {
        *error = UpdateError(AppUpdateErrorUnsafe, [NSString stringWithFormat:@"Bản tải về không đúng phiên bản %@ đã công bố. VOpenKey AI không cài nó.", version]);
        return NO;
    }
    SecStaticCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    BOOL ok = NO;
    CFErrorRef failure = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)app, kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecRequirementCreateWithString((__bridge CFStringRef)self.requirement, kSecCSDefaultFlags, &requirement) == errSecSuccess) {
        OSStatus status = SecStaticCodeCheckValidityWithErrors(code, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate, requirement, &failure);
        ok = status == errSecSuccess;
    }
    if (failure != NULL) CFRelease(failure);
    if (code != NULL) CFRelease(code);
    if (requirement != NULL) CFRelease(requirement);
    if (!ok)
        *error = UpdateError(AppUpdateErrorUnsafe, [NSString stringWithFormat:@"Bản tải về không phải bản chính thức của %@ (chữ ký số không khớp hoặc file đã bị sửa). VOpenKey AI không cài nó.", VOK_APP_NAME]);
    return ok;
}

-(BOOL)runningApplicationSatisfiesRequirement {
    SecCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    BOOL ok = NO;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecRequirementCreateWithString((__bridge CFStringRef)self.requirement, kSecCSDefaultFlags, &requirement) == errSecSuccess)
        ok = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement) == errSecSuccess;
    if (code != NULL) CFRelease(code);
    if (requirement != NULL) CFRelease(requirement);
    return ok;
}

@end

#pragma mark - The updater

//Takes the address a redirect leads to and does not follow it: GitHub answers /releases/latest with a redirect to the page of the tag
@interface AppUpdateRedirectProbe : NSObject <NSURLSessionTaskDelegate>
@property (copy) NSURL* location;
@end

@implementation AppUpdateRedirectProbe
-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response
        newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler {
    self.location = request.URL;
    completionHandler(nil);
}
@end

//What the helper does when this app has quit. Arguments: pid, the new app, the app to replace, the program that opens an app, the file
//the outcome is written to, the version. A failure at any step leaves the old app where it was and opens it again.
static NSString* const kHelperScript =
    @"PATH=/usr/bin:/bin:/usr/sbin:/sbin\n"
    @"PID=\"$1\"; NEW=\"$2\"; DEST=\"$3\"; OPEN=\"$4\"; RESULT=\"$5\"; VERSION=\"$6\"\n"
    @"PARENT=\"${DEST%/*}\"\n"
    @"COPY=\"$PARENT/.VOpenKey-update-new\"\n"
    @"OLD=\"$PARENT/.VOpenKey-update-old\"\n"
    @"fail() { printf 'failed %s\\n' \"$1\" > \"$RESULT\"; \"$OPEN\" \"$DEST\"; exit 1; }\n"
    @"n=0\n"
    @"while kill -0 \"$PID\" 2>/dev/null; do\n"
    @"    n=$((n + 1))\n"
    @"    if [ \"$n\" -gt 600 ]; then printf 'failed quit\\n' > \"$RESULT\"; exit 1; fi\n"
    @"    sleep 0.1\n"
    @"done\n"
    @"rm -rf \"$COPY\" \"$OLD\"\n"
    @"if ! /usr/bin/ditto \"$NEW\" \"$COPY\"; then rm -rf \"$COPY\"; fail copy; fi\n"
    @"if ! mv \"$DEST\" \"$OLD\"; then rm -rf \"$COPY\"; fail move; fi\n"
    @"if ! mv \"$COPY\" \"$DEST\"; then mv \"$OLD\" \"$DEST\"; rm -rf \"$COPY\"; fail place; fi\n"
    @"/usr/bin/xattr -dr com.apple.quarantine \"$DEST\" 2>/dev/null\n"
    @"printf 'ok %s\\n' \"$VERSION\" > \"$RESULT\"\n"
    @"rm -rf \"$OLD\"\n"
    @"\"$OPEN\" \"$DEST\"\n";

@interface AppUpdater () <NSURLSessionDataDelegate>
@end

@implementation AppUpdater {
    NSURL* _apiURL;
    NSURL* _repositoryURL;
    NSURL* _workDirectory;
    NSURL* _installTarget;
    AppUpdateVerifier* _verifier;
    dispatch_queue_t _queue;

    //what the rest of the app sees: only touched on the main queue
    AppUpdaterState _state;
    AppUpdaterState _stateBeforeCheck;
    AppUpdateRelease* _release;
    double _progress;
    NSMutableArray<void (^)(AppUpdateRelease*, NSError*)>* _checkWaiters;

    //the work in the background
    BOOL _cancelled;
    NSURLSession* _session;
    NSURLSessionTask* _task;
    dispatch_semaphore_t _downloadDone;
    NSURLSessionDataTask* _downloadTask;
    NSURL* _downloadTarget;                 //where the file is written as it arrives
    NSFileHandle* _downloadFile;
    int64_t _downloadReceived;
    int64_t _downloadExpected;              //what the server announced; <= 0 when it did not
    BOOL _downloadSaved;
    BOOL _downloadTooBig;
    NSError* _downloadError;
    NSInteger _downloadStatus;
}

#pragma mark Setting up

+(AppUpdater*)shared {
    static AppUpdater* shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL* support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                          URLByAppendingPathComponent:VOK_DATA_DIR_NAME isDirectory:YES];
        NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        shared = [[AppUpdater alloc] initWithAPIURL:[NSURL URLWithString:VOK_RELEASE_API_URL] repositoryURL:[NSURL URLWithString:VOK_REPO_URL]
                                      workDirectory:[support URLByAppendingPathComponent:@"Updates" isDirectory:YES]
                                      installTarget:[NSBundle mainBundle].bundleURL
                                     currentVersion:[AppUpdateRelease isValidVersion:version] ? version : @"0.0.0"
                                           verifier:[AppUpdateVerifier standard]];
    });
    return shared;
}

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kAutoInstallKey: @YES}];
}

+(BOOL)automaticInstallEnabled {
    [self registerDefaults];
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAutoInstallKey];
}

-(instancetype)initWithAPIURL:(NSURL*)apiURL repositoryURL:(NSURL*)repositoryURL workDirectory:(NSURL*)workDirectory
                installTarget:(NSURL*)installTarget currentVersion:(NSString*)currentVersion verifier:(AppUpdateVerifier*)verifier {
    if (apiURL == nil || repositoryURL == nil || workDirectory == nil || installTarget == nil || verifier == nil ||
        ![AppUpdateRelease isValidVersion:currentVersion])
        return nil;
    self = [super init];
    if (self) {
        _apiURL = apiURL;
        _repositoryURL = repositoryURL;
        _workDirectory = workDirectory;
        _installTarget = installTarget;
        _currentVersion = [currentVersion copy];
        _verifier = verifier;
        _queue = dispatch_queue_create("vn.io.lssoft.vopenkey.update", DISPATCH_QUEUE_SERIAL);
        _checkWaiters = [NSMutableArray array];
        _progress = -1;
        _relaunchTool = @"/usr/bin/open";
        _processToWaitFor = getpid();
        _requiresSignedHost = YES;
    }
    return self;
}

#pragma mark State

-(AppUpdaterState)state { return _state; }
-(AppUpdateRelease*)availableRelease { return _release; }
-(double)progress { return _progress; }

-(void)didChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:AppUpdaterDidChangeNotification object:self];
}

-(void)setState:(AppUpdaterState)state {
    _state = state;
    [self didChange];
}

-(BOOL)isCancelled {
    @synchronized (self) { return _cancelled; }
}

-(void)cancel {
    @synchronized (self) {
        _cancelled = YES;
        [_task cancel];
    }
}

-(NSString*)reasonCannotInstall {
    NSString* path = _installTarget.path;
    if ([path containsString:@"/AppTranslocation/"])
        return [NSString stringWithFormat:@"%@ đang chạy từ vị trí tạm của macOS. Hãy kéo nó vào thư mục Applications rồi mở lại.", VOK_APP_NAME];
    if (![path.pathExtension isEqualToString:@"app"])
        return [NSString stringWithFormat:@"%@ không chạy từ một ứng dụng (.app).", VOK_APP_NAME];
    if (![[NSFileManager defaultManager] isWritableFileAtPath:path.stringByDeletingLastPathComponent])
        return [NSString stringWithFormat:@"Không có quyền ghi vào thư mục chứa %@ (%@).", VOK_APP_NAME, path.stringByDeletingLastPathComponent];
    if (self.requiresSignedHost && ![_verifier runningApplicationSatisfiesRequirement])
        return [NSString stringWithFormat:@"Bản %@ này không do %@ ký (tự build từ mã nguồn?), nên không được thay bằng bản tải về.", VOK_APP_NAME, VOK_COMPANY];
    return nil;
}

-(BOOL)readyUpdateWasTried {
    return _release != nil && [[[NSUserDefaults standardUserDefaults] stringForKey:kTriedVersionKey] isEqualToString:_release.version];
}

#pragma mark Checking

-(void)checkForUpdate:(void (^)(AppUpdateRelease*, NSError*))completion {
    if (_state == AppUpdaterStateDownloading || _state == AppUpdaterStateReady) {
        //past the check already; a newer release than the one in hand is found after the restart
        if (completion != nil) completion(_release, nil);
        return;
    }
    if (completion != nil)
        [_checkWaiters addObject:[completion copy]];
    if (_state == AppUpdaterStateChecking)
        return;
    _stateBeforeCheck = _state;
    [self setState:AppUpdaterStateChecking];
    @synchronized (self) { _cancelled = NO; }
    dispatch_async(_queue, ^{
        NSError* error = nil;
        AppUpdateRelease* release = [self lookUpLatestRelease:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ [self finishCheck:release error:error]; });
    });
}

-(void)finishCheck:(AppUpdateRelease*)release error:(NSError*)error {
    NSArray* waiters = [_checkWaiters copy];
    [_checkWaiters removeAllObjects];
    AppUpdateRelease* newer = nil;
    if (error != nil) {
        //a check that failed tells nothing new: what was known stays
        _state = _stateBeforeCheck;
        [self didChange];
    } else {
        if (release != nil && [AppUpdateRelease compareVersion:release.version toVersion:_currentVersion] == NSOrderedDescending)
            newer = release;
        _release = newer;
        _progress = -1;
        [self setState:newer != nil ? AppUpdaterStateAvailable : AppUpdaterStateIdle];
    }
    for (void (^waiter)(AppUpdateRelease*, NSError*) in waiters)
        waiter(newer, error);
}

/// The newest release, nil without an error when there is none. Asks the GitHub API and, when it refuses (it answers 403 when it is
/// asked too often from the same address), the page of the newest release.
-(AppUpdateRelease*)lookUpLatestRelease:(NSError**)error {
    if (!AddressAllowed(_apiURL)) {
        *error = UpdateError(AppUpdateErrorNetwork, @"Địa chỉ kiểm tra bản mới không hợp lệ.");
        return nil;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:_apiURL];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    request.timeoutInterval = 20;
    NSData* data = nil; NSInteger status = 0; NSError* networkError = nil;
    [self fetch:request data:&data status:&status error:&networkError];
    if ([self isCancelled]) {
        *error = UpdateError(AppUpdateErrorCancelled, @"Đã hủy.");
        return nil;
    }
    if (status == 200)
        return [AppUpdateRelease releaseFromAPIData:data repository:_repositoryURL error:error];
    if (status == 404)
        return nil;                                                     //no release was ever published
    if (networkError == nil && (status == 403 || status == 429 || status >= 500)) {
        AppUpdateRelease* release = [self lookUpByRedirect];
        if (release != nil)
            return release;
    }
    *error = UpdateError(AppUpdateErrorNetwork, networkError != nil
                         ? @"Không kết nối được tới GitHub."
                         : [NSString stringWithFormat:@"GitHub trả về lỗi %ld.", (long)status]);
    return nil;
}

-(AppUpdateRelease*)lookUpByRedirect {
    NSURL* latest = [NSURL URLWithString:[WithoutTrailingSlashes(_repositoryURL.absoluteString) stringByAppendingString:@"/releases/latest"]];
    if (latest == nil || !AddressAllowed(latest))
        return nil;
    AppUpdateRedirectProbe* probe = [[AppUpdateRedirectProbe alloc] init];
    NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    if (self.protocolClasses.count > 0)
        configuration.protocolClasses = self.protocolClasses;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:configuration delegate:probe delegateQueue:nil];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:latest];
    request.HTTPMethod = @"HEAD";
    request.timeoutInterval = 20;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) { dispatch_semaphore_signal(done); }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];
    NSString* tag = probe.location.path.lastPathComponent;
    NSString* expectedFolder = [WithoutTrailingSlashes(_repositoryURL.path) stringByAppendingString:@"/releases/tag"];
    if (probe.location == nil || ![probe.location.path.stringByDeletingLastPathComponent isEqualToString:expectedFolder])
        return nil;
    return [AppUpdateRelease releaseForTag:tag repository:_repositoryURL];
}

#pragma mark Downloading

-(void)downloadUpdate:(void (^)(NSError*))completion {
    AppUpdateRelease* release = _release;
    if (_state == AppUpdaterStateReady) {
        if (completion != nil) completion(nil);
        return;
    }
    NSString* reason = [self reasonCannotInstall];
    if (_state != AppUpdaterStateAvailable || release == nil || reason != nil) {
        if (completion != nil)
            completion(UpdateError(AppUpdateErrorInstall, reason ?: @"Chưa có bản mới để tải."));
        return;
    }
    @synchronized (self) { _cancelled = NO; }
    _progress = -1;
    [self setState:AppUpdaterStateDownloading];
    dispatch_async(_queue, ^{
        NSError* error = nil;
        BOOL ok = [self stageRelease:release error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (self) { [self->_session invalidateAndCancel]; self->_session = nil; self->_task = nil; }
            self->_progress = -1;
            [self setState:ok ? AppUpdaterStateReady : AppUpdaterStateAvailable];
            if (completion != nil) completion(ok ? nil : error);
        });
    });
}

-(void)reportProgress:(double)fraction {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_state != AppUpdaterStateDownloading)
            return;
        if (fraction >= 0 && self->_progress >= 0 && fraction - self->_progress < 0.01 && fraction < 1)
            return;                                                     //not every byte is news
        self->_progress = fraction;
        [self didChange];
    });
}

-(NSURL*)readyDirectory {
    return [_workDirectory URLByAppendingPathComponent:kReadyFolder isDirectory:YES];
}

/// The .app inside a folder: exactly one, a real folder and not a link to somewhere else.
static NSURL* OnlyApplicationIn(NSURL* folder) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* found = nil;
    for (NSString* name in [fm contentsOfDirectoryAtPath:folder.path error:nil]) {
        if (![name.pathExtension isEqualToString:@"app"])
            continue;
        struct stat info;
        NSURL* url = [folder URLByAppendingPathComponent:name isDirectory:YES];
        if (lstat(url.path.fileSystemRepresentation, &info) != 0 || !S_ISDIR(info.st_mode))
            return nil;
        if (found != nil)
            return nil;
        found = url;
    }
    return found;
}

-(BOOL)stageRelease:(AppUpdateRelease*)release error:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* work = nil;
    NSURL* mount = nil;
    @try {
        //1. a folder of its own that nobody else can read, in which nothing exists yet
        if (![fm createDirectoryAtURL:_workDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil]) {
            *error = UpdateError(AppUpdateErrorInstall, @"Không tạo được thư mục làm việc của VOpenKey AI.");
            return NO;
        }
        for (NSString* name in [fm contentsOfDirectoryAtPath:_workDirectory.path error:nil]) {
            if ([name hasPrefix:kDownloadPrefix])
                [fm removeItemAtURL:[_workDirectory URLByAppendingPathComponent:name] error:nil];       //what a crash left
        }
        work = [_workDirectory URLByAppendingPathComponent:[kDownloadPrefix stringByAppendingString:[[NSUUID UUID] UUIDString]] isDirectory:YES];
        if (![fm createDirectoryAtURL:work withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:nil]) {
            *error = UpdateError(AppUpdateErrorInstall, @"Không tạo được thư mục tạm để tải bản mới.");
            return NO;
        }

        //2. the hash that was published, when the release did not carry it
        NSString* sha = release.sha256;
        if (sha == nil && release.checksumURL != nil && AddressAllowed(release.checksumURL)) {
            NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:release.checksumURL];
            request.timeoutInterval = 20;
            NSData* data = nil; NSInteger status = 0; NSError* networkError = nil;
            [self fetch:request data:&data status:&status error:&networkError];
            NSString* text = status == 200 && data.length > 0 && data.length < 4096 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            NSString* first = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].firstObject;
            if (IsHex(first, 64))
                sha = first.lowercaseString;
        }
        if ([self isCancelled]) { *error = UpdateError(AppUpdateErrorCancelled, @"Đã hủy."); return NO; }

        //3. download
        NSURL* dmg = [work URLByAppendingPathComponent:[AppUpdateRelease fileNameForVersion:release.version]];
        if (![self download:release.fileURL to:dmg error:error])
            return NO;

        //4. it is the file that was published
        [self reportProgress:-1];
        if (![self checkFile:dmg size:release.size sha256:sha error:error])
            return NO;
        if ([self isCancelled]) { *error = UpdateError(AppUpdateErrorCancelled, @"Đã hủy."); return NO; }

        //5. opened on a folder of ours; only the app is taken out of it
        mount = [work URLByAppendingPathComponent:@"disk" isDirectory:YES];
        [fm createDirectoryAtURL:mount withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:nil];
        if (![self mountImage:dmg at:mount]) {
            mount = nil;                                                //nothing to detach
            *error = UpdateError(AppUpdateErrorUnsafe, @"File tải về không mở được: nó bị hỏng. Hãy thử lại.");
            return NO;
        }
        NSURL* app = OnlyApplicationIn(mount);
        if (app == nil) {
            *error = UpdateError(AppUpdateErrorUnsafe, @"File tải về không đúng cấu trúc của VOpenKey AI. VOpenKey AI không cài nó.");
            return NO;
        }
        NSURL* copyFolder = [work URLByAppendingPathComponent:@"app" isDirectory:YES];
        [fm createDirectoryAtURL:copyFolder withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:nil];
        NSURL* copy = [copyFolder URLByAppendingPathComponent:app.lastPathComponent isDirectory:YES];
        if (!RunTool(@"/usr/bin/ditto", @[app.path, copy.path], 180)) {
            *error = UpdateError(AppUpdateErrorInstall, @"Không chép được bản mới ra khỏi file tải về.");
            return NO;
        }
        [self unmountImageAt:mount];
        mount = nil;
        if ([self isCancelled]) { *error = UpdateError(AppUpdateErrorCancelled, @"Đã hủy."); return NO; }

        //6. who made it: checked on the copy, which is the one that is installed
        if (![_verifier verifyApplication:copy expectedVersion:release.version error:error])
            return NO;
        NSDictionary* info = [NSDictionary dictionaryWithContentsOfURL:[copy URLByAppendingPathComponent:@"Contents/Info.plist"]];
        NSString* minimum = [info[@"LSMinimumSystemVersion"] isKindOfClass:[NSString class]] ? info[@"LSMinimumSystemVersion"] : nil;
        if (minimum != nil && !IsPlainIdentifier(minimum)) minimum = nil;
        if (minimum != nil) {
            NSArray<NSString*>* parts = [minimum componentsSeparatedByString:@"."];
            NSOperatingSystemVersion needed = {parts.count > 0 ? parts[0].integerValue : 0, parts.count > 1 ? parts[1].integerValue : 0, parts.count > 2 ? parts[2].integerValue : 0};
            if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:needed]) {
                *error = UpdateError(AppUpdateErrorNoRelease, [NSString stringWithFormat:@"Bản %@ mới cần macOS %@ trở lên, máy bạn thấp hơn. Bản hiện tại vẫn dùng bình thường.", release.version, minimum]);
                return NO;
            }
        }

        //7. kept, until the app restarts
        NSURL* ready = [self readyDirectory];
        [fm removeItemAtURL:ready error:nil];
        if (![fm createDirectoryAtURL:ready withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:nil] ||
            ![fm moveItemAtURL:copy toURL:[ready URLByAppendingPathComponent:copy.lastPathComponent isDirectory:YES] error:nil]) {
            *error = UpdateError(AppUpdateErrorInstall, @"Không lưu được bản mới để cài.");
            return NO;
        }
        return YES;
    } @finally {
        if (mount != nil)
            [self unmountImageAt:mount];
        if (work != nil)
            [fm removeItemAtURL:work error:nil];
    }
}

/// Opens the disk image on a folder of ours: not shown in the Finder, read only, nothing started from it.
-(BOOL)mountImage:(NSURL*)image at:(NSURL*)mountPoint {
    return RunTool(@"/usr/bin/hdiutil", @[@"attach", @"-nobrowse", @"-readonly", @"-noverify", @"-noautoopen", @"-mountpoint", mountPoint.path, image.path], 180);
}

-(void)unmountImageAt:(NSURL*)mountPoint {
    RunTool(@"/usr/bin/hdiutil", @[@"detach", mountPoint.path, @"-force"], 60);
}

#pragma mark Network

-(NSURLSession*)session {
    @synchronized (self) {
        if (_session == nil) {
            NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            configuration.URLCache = nil;
            configuration.HTTPCookieStorage = nil;
            configuration.timeoutIntervalForRequest = 60;
            configuration.timeoutIntervalForResource = 1800;
            if (self.protocolClasses.count > 0)
                configuration.protocolClasses = self.protocolClasses;
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

-(BOOL)download:(NSURL*)url to:(NSURL*)destination error:(NSError**)error {
    if (url == nil || !AddressAllowed(url)) {
        *error = UpdateError(AppUpdateErrorUnsafe, @"Địa chỉ tải bản mới không an toàn. VOpenKey AI không tải.");
        return NO;
    }
    _downloadDone = dispatch_semaphore_create(0);
    _downloadTarget = destination;
    _downloadFile = nil;
    _downloadSaved = NO;
    _downloadTooBig = NO;
    _downloadError = nil;
    _downloadStatus = 0;
    _downloadReceived = 0;
    _downloadExpected = 0;
    NSURLSessionDataTask* task = [[self session] dataTaskWithURL:url];
    _downloadTask = task;
    @synchronized (self) { _task = task; if (_cancelled) [task cancel]; }
    [task resume];
    dispatch_semaphore_wait(_downloadDone, DISPATCH_TIME_FOREVER);
    _downloadTask = nil;
    if ([self isCancelled]) { *error = UpdateError(AppUpdateErrorCancelled, @"Đã hủy."); return NO; }
    if (_downloadTooBig) {
        *error = UpdateError(AppUpdateErrorUnsafe, @"File tải về lớn bất thường so với VOpenKey AI. VOpenKey AI dừng lại và không cài.");
        return NO;
    }
    if (_downloadError != nil || !_downloadSaved) {
        *error = UpdateError(AppUpdateErrorNetwork, _downloadStatus >= 400
                             ? [NSString stringWithFormat:@"Máy chủ GitHub trả về lỗi %ld khi tải bản mới.", (long)_downloadStatus]
                             : @"Tải bản mới bị gián đoạn. Hãy kiểm tra mạng rồi thử lại.");
        return NO;
    }
    return YES;
}

/// The size and the hash published for the file; a size of 0 and a nil hash mean that nothing was published.
-(BOOL)checkFile:(NSURL*)file size:(uint64_t)size sha256:(NSString*)sha error:(NSError**)error {
    uint64_t actual = [[[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:nil] fileSize];
    if (actual == 0 || (size > 0 && actual != size)) {
        *error = UpdateError(AppUpdateErrorUnsafe, @"File tải về không đủ dung lượng như công bố: bị cắt hoặc bị thay. VOpenKey AI không cài nó.");
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
        *error = UpdateError(AppUpdateErrorUnsafe, @"Mã kiểm tra (SHA-256) của file tải về không khớp với mã GitHub công bố: file bị hỏng hoặc bị thay. VOpenKey AI không cài nó.");
        return NO;
    }
    return YES;
}

//The file is written straight to the folder of this run as it arrives: a download task would put it first in a folder of the system
//(which is not always writable) and ask for it to be moved.
-(void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveResponse:(NSURLResponse*)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (task != _downloadTask) {
        completionHandler(NSURLSessionResponseAllow);
        return;
    }
    _downloadStatus = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*)response statusCode] : 0;
    _downloadExpected = response.expectedContentLength;
    if (_downloadExpected > kMaxDownload) {
        _downloadTooBig = YES;
    } else if (_downloadStatus == 200) {
        //a new file, that nobody else can read: it is the folder of this run, nothing is in it yet
        int descriptor = open(_downloadTarget.path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        if (descriptor >= 0)
            _downloadFile = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:YES];
    }
    completionHandler(_downloadFile != nil && !_downloadTooBig ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}

-(void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data {
    if (task != _downloadTask || _downloadFile == nil)
        return;
    _downloadReceived += (int64_t)data.length;
    if (_downloadReceived > kMaxDownload) {
        _downloadTooBig = YES;
        [task cancel];
        return;
    }
    NSError* failure = nil;
    if (![_downloadFile writeData:data error:&failure]) {
        [task cancel];                                                  //the disk is full or gone: the file is not saved
        return;
    }
    if (_downloadExpected > 0)
        [self reportProgress:(double)_downloadReceived / (double)_downloadExpected];
}

-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    if (task != _downloadTask)
        return;
    BOOL wholeFile = _downloadExpected <= 0 || _downloadReceived == _downloadExpected;
    [_downloadFile closeFile];
    _downloadSaved = error == nil && _downloadFile != nil && _downloadStatus == 200 && wholeFile && !_downloadTooBig;
    _downloadFile = nil;
    _downloadError = error;
    dispatch_semaphore_signal(_downloadDone);
}

//only https (or this Mac, for tests) is followed: a redirect to plain http would let anyone on the way swap the file
-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response
        newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler {
    completionHandler(AddressAllowed(request.URL) ? request : nil);
}

#pragma mark Keeping and installing

-(void)loadReadyUpdate:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        NSFileManager* fm = [NSFileManager defaultManager];
        NSURL* ready = [self readyDirectory];
        AppUpdateRelease* release = nil;
        if ([fm fileExistsAtPath:ready.path]) {
            NSURL* app = OnlyApplicationIn(ready);
            NSDictionary* info = app != nil ? [NSDictionary dictionaryWithContentsOfURL:[app URLByAppendingPathComponent:@"Contents/Info.plist"]] : nil;
            NSString* version = info[@"CFBundleShortVersionString"];
            //newer than this app (an update that was installed leaves its copy behind), and still intact
            if ([AppUpdateRelease isValidVersion:version] &&
                [AppUpdateRelease compareVersion:version toVersion:self->_currentVersion] == NSOrderedDescending &&
                [self->_verifier verifyApplication:app expectedVersion:version error:nil])
                release = [AppUpdateRelease releaseForTag:[@"v" stringByAppendingString:version] repository:self->_repositoryURL];
            if (release == nil)
                [fm removeItemAtURL:ready error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (release != nil && (self->_state == AppUpdaterStateIdle || self->_state == AppUpdaterStateAvailable)) {
                self->_release = release;
                self->_progress = -1;
                [self setState:AppUpdaterStateReady];
            }
            if (completion != nil) completion();
        });
    });
}

-(BOOL)installReadyUpdate:(NSError**)error {
    NSError* __autoreleasing ignored = nil;
    if (error == NULL) error = &ignored;
    if (_state != AppUpdaterStateReady || _release == nil) {
        *error = UpdateError(AppUpdateErrorInstall, @"Chưa có bản mới nào sẵn sàng để cài.");
        return NO;
    }
    NSString* reason = [self reasonCannotInstall];
    if (reason != nil) {
        *error = UpdateError(AppUpdateErrorInstall, reason);
        return NO;
    }
    NSURL* app = OnlyApplicationIn([self readyDirectory]);
    if (app == nil || ![_verifier verifyApplication:app expectedVersion:_release.version error:error])   //once more: this is what gets installed
        return NO;
    NSURL* result = [_workDirectory URLByAppendingPathComponent:kResultFile];
    [[NSFileManager defaultManager] removeItemAtURL:result error:nil];
    int code = 0;
    pid_t pid = SpawnProgram(@"/bin/sh", @[@"-c", kHelperScript, @"sh", [NSString stringWithFormat:@"%d", _processToWaitFor], app.path, _installTarget.path,
                                          _relaunchTool, result.path, _release.version], -1, YES, &code);
    if (pid == 0) {
        *error = UpdateError(AppUpdateErrorInstall, @"Không khởi động được trình cài đặt bản mới.");
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject:_release.version forKey:kTriedVersionKey];
    return YES;
}

-(NSString*)takeLastInstallFailure {
    NSURL* result = [_workDirectory URLByAppendingPathComponent:kResultFile];
    NSString* text = [[NSString stringWithContentsOfURL:result encoding:NSUTF8StringEncoding error:nil]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text == nil)
        return nil;
    [[NSFileManager defaultManager] removeItemAtURL:result error:nil];
    if (![text hasPrefix:@"failed"])
        return nil;
    NSDictionary<NSString*, NSString*>* causes = @{@"failed copy": @"không chép được bản mới",
                                                   @"failed move": @"không thay được bản cũ",
                                                   @"failed place": @"không đặt được bản mới vào chỗ của bản cũ",
                                                   @"failed quit": @"ứng dụng không thoát kịp"};
    return [NSString stringWithFormat:@"Cập nhật không hoàn tất: %@. %@ vẫn là bản cũ, bạn có thể tải bản mới ở trang phát hành.",
            causes[text] ?: @"có lỗi không rõ", VOK_APP_NAME];
}

@end
