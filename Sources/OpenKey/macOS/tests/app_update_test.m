// Tests of the updater (AppUpdater, AppUpdateRelease, AppUpdateVerifier) against a fake GitHub: MockGitHub answers the requests of the
// updater from the fake releases that app_update_fixtures.py made, inside this program (no port is opened). Run with run-app-update-test.sh:
//
//   app_update_test <fixtures folder> <work folder>
//
// The "disk image" of a fake release is a zip, which TestUpdater opens with ditto (the real updater asks hdiutil: the one step that is not
// tried unless the fixtures have a real dmg, see TestRealDiskImage). The apps are signed ad hoc; the requirement they are checked against
// is the one of their identifier. Nothing is installed outside the work folder.
#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import "AppInfo.h"
#import "AppUpdater.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* const kTestIdentifier = @"vn.io.lssoft.vopenkey.test";
static NSString* const kFakeHost = @"http://127.0.0.1:8080";            //nothing listens there: MockGitHub answers before the network is asked

static NSString* gFixtures;
static NSString* gRoot;

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

static BOOL Exists(NSString* path) {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

static int RunProgram(NSString* path, NSArray<NSString*>* arguments) {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil])
        return -1;
    [task waitUntilExit];
    return task.terminationStatus;
}

#pragma mark - The fake GitHub

//what was asked for in each scenario, "METHOD /kind/rest"
static NSMutableDictionary<NSString*, NSMutableArray<NSString*>*>* gLog;

static NSArray<NSString*>* ServerLog(NSString* scenario) {
    @synchronized ([NSURLProtocol class]) { return [gLog[scenario] copy] ?: @[]; }
}

/// Answers /s/<scenario>/... from <fixtures>/<scenario>:
///   api/releases/latest                    api.json (with __BASE__ replaced by the address of the repository), or the status in api.status
///   repo/releases/download/<tag>/<file>    files/<file>; next to it <file>.status answers that status, <file>.cut (a number) drops the
///                                          connection after that many bytes, <file>.claim (a number) announces that many bytes, sends a
///                                          few and stalls
///   repo/releases/latest                   a redirect to .../releases/tag/<tag>, with the tag of latest.txt (404 without it)
@interface MockGitHub : NSURLProtocol
@end

@implementation MockGitHub {
    BOOL _stopped;
}

+(BOOL)canInitWithRequest:(NSURLRequest*)request {
    return [request.URL.host isEqualToString:@"127.0.0.1"] && [request.URL.path hasPrefix:@"/s/"];
}

+(NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request {
    return request;
}

-(void)stopLoading {
    @synchronized (self) { _stopped = YES; }
}

-(BOOL)stopped {
    @synchronized (self) { return _stopped; }
}

-(void)startLoading {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self respond]; });
}

-(void)sendStatus:(NSInteger)status body:(NSData*)body headers:(NSDictionary*)headers announce:(long long)announce {
    NSMutableDictionary* fields = [headers mutableCopy] ?: [NSMutableDictionary dictionary];
    fields[@"Content-Length"] = [NSString stringWithFormat:@"%lld", announce >= 0 ? announce : (long long)body.length];
    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:fields];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (body.length > 0 && ![self.request.HTTPMethod isEqualToString:@"HEAD"])
        [self.client URLProtocol:self didLoadData:body];
}

-(void)finish {
    [self.client URLProtocolDidFinishLoading:self];
}

-(void)fail:(NSInteger)code {
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:code userInfo:nil]];
}

-(void)respond {
    NSString* method = self.request.HTTPMethod ?: @"GET";
    NSArray<NSString*>* parts = [self.request.URL.path componentsSeparatedByString:@"/"];       // "", "s", scenario, kind, ...
    if (parts.count < 5) {
        [self sendStatus:404 body:nil headers:nil announce:-1];
        return [self finish];
    }
    NSString* scenario = parts[2];
    NSString* kind = parts[3];
    NSString* rest = [[parts subarrayWithRange:NSMakeRange(4, parts.count - 4)] componentsJoinedByString:@"/"];
    @synchronized ([NSURLProtocol class]) {
        if (gLog == nil) gLog = [NSMutableDictionary dictionary];
        if (gLog[scenario] == nil) gLog[scenario] = [NSMutableArray array];
        [gLog[scenario] addObject:[NSString stringWithFormat:@"%@ /%@/%@", method, kind, rest]];
    }
    NSString* folder = [gFixtures stringByAppendingPathComponent:scenario];
    NSString* base = [NSString stringWithFormat:@"%@/s/%@/repo", kFakeHost, scenario];

    if ([kind isEqualToString:@"api"] && [rest isEqualToString:@"releases/latest"]) {
        NSString* status = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@"api.status"] encoding:NSUTF8StringEncoding error:nil];
        NSData* body = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"api.json"]];
        if (status != nil)
            [self sendStatus:status.integerValue body:nil headers:nil announce:-1];
        else if (body == nil)
            [self sendStatus:404 body:nil headers:nil announce:-1];
        else {
            NSString* json = [[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"__BASE__" withString:base];
            [self sendStatus:200 body:[json dataUsingEncoding:NSUTF8StringEncoding] headers:@{@"Content-Type": @"application/json"} announce:-1];
        }
        return [self finish];
    }
    if ([kind isEqualToString:@"repo"] && [rest isEqualToString:@"releases/latest"]) {
        NSString* tag = [[NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@"latest.txt"] encoding:NSUTF8StringEncoding error:nil]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (tag == nil) {
            [self sendStatus:404 body:nil headers:nil announce:-1];
            return [self finish];
        }
        NSURL* target = [NSURL URLWithString:[NSString stringWithFormat:@"%@/releases/tag/%@", base, tag]];
        NSHTTPURLResponse* redirect = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:302 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{@"Location": target.absoluteString, @"Content-Length": @"0"}];
        [self.client URLProtocol:self wasRedirectedToRequest:[NSURLRequest requestWithURL:target] redirectResponse:redirect];
        return;
    }
    if ([kind isEqualToString:@"repo"] && [rest hasPrefix:@"releases/download/"]) {
        NSString* file = [folder stringByAppendingPathComponent:[@"files" stringByAppendingPathComponent:rest.lastPathComponent]];
        NSString* status = [NSString stringWithContentsOfFile:[file stringByAppendingString:@".status"] encoding:NSUTF8StringEncoding error:nil];
        NSData* body = [NSData dataWithContentsOfFile:file];
        NSString* cut = [NSString stringWithContentsOfFile:[file stringByAppendingString:@".cut"] encoding:NSUTF8StringEncoding error:nil];
        NSString* claim = [NSString stringWithContentsOfFile:[file stringByAppendingString:@".claim"] encoding:NSUTF8StringEncoding error:nil];
        if (status != nil) {
            [self sendStatus:status.integerValue body:nil headers:nil announce:-1];
            return [self finish];
        }
        if (body == nil) {
            [self sendStatus:404 body:nil headers:nil announce:-1];
            return [self finish];
        }
        if (claim != nil) {
            [self sendStatus:200 body:[body subdataWithRange:NSMakeRange(0, MIN((NSUInteger)2000, body.length))] headers:nil announce:claim.longLongValue];
            for (int i = 0; i < 30 && ![self stopped]; i++)
                usleep(100000);
            if (![self stopped]) [self fail:NSURLErrorTimedOut];
            return;
        }
        if (cut != nil) {
            [self sendStatus:200 body:[body subdataWithRange:NSMakeRange(0, MIN((NSUInteger)cut.integerValue, body.length))] headers:nil announce:(long long)body.length];
            return [self fail:NSURLErrorNetworkConnectionLost];
        }
        [self sendStatus:200 body:body headers:@{@"Content-Type": @"application/octet-stream"} announce:-1];
        return [self finish];
    }
    [self sendStatus:404 body:nil headers:nil announce:-1];
    [self finish];
}

@end

static NSUInteger Count(NSArray<NSString*>* log, NSString* needle) {
    NSUInteger count = 0;
    for (NSString* line in log)
        if ([line containsString:needle])
            count++;
    return count;
}

/// An updater that talks to MockGitHub and not to the network.
@interface StubbedUpdater : AppUpdater
@end
@implementation StubbedUpdater
-(NSArray<Class>*)protocolClasses {
    return @[[MockGitHub class]];
}
@end

/// What the real updater does with a dmg, done with a zip: the volume is the folder.
@interface TestUpdater : StubbedUpdater
@end
@implementation TestUpdater
-(BOOL)mountImage:(NSURL*)image at:(NSURL*)mountPoint {
    return RunProgram(@"/usr/bin/ditto", @[@"-x", @"-k", image.path, mountPoint.path]) == 0;
}
-(void)unmountImageAt:(NSURL*)mountPoint {
}
@end

static AppUpdateVerifier* MakeVerifier(void) {
    return [[AppUpdateVerifier alloc] initWithRequirement:[NSString stringWithFormat:@"identifier \"%@\"", kTestIdentifier] bundleIdentifier:kTestIdentifier];
}

static NSString* gLastWork;

/// An updater for a scenario of the fake GitHub, with a folder of its own for its files and another for the app it would replace.
static AppUpdater* NewUpdaterOfClass(Class updaterClass, NSString* scenario, NSString* currentVersion) {
    NSString* base = [NSString stringWithFormat:@"%@/s/%@", kFakeHost, scenario];
    NSString* folder = [gRoot stringByAppendingPathComponent:scenario];
    [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:[folder stringByAppendingPathComponent:@"apps"] withIntermediateDirectories:YES attributes:nil error:nil];
    gLastWork = [folder stringByAppendingPathComponent:@"work"];
    AppUpdater* updater = [[updaterClass alloc] initWithAPIURL:[NSURL URLWithString:[base stringByAppendingString:@"/api/releases/latest"]]
                                                 repositoryURL:[NSURL URLWithString:[base stringByAppendingString:@"/repo"]]
                                                 workDirectory:[NSURL fileURLWithPath:gLastWork isDirectory:YES]
                                                 installTarget:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"apps/VOpenKey AI.app"] isDirectory:YES]
                                                currentVersion:currentVersion
                                                      verifier:MakeVerifier()];
    updater.requiresSignedHost = NO;
    return updater;
}

static TestUpdater* NewUpdater(NSString* scenario, NSString* currentVersion) {
    return (TestUpdater*)NewUpdaterOfClass([TestUpdater class], scenario, currentVersion);
}

typedef struct { AppUpdateRelease* release; NSError* error; BOOL finished; } CheckOutcome;

static CheckOutcome Check(AppUpdater* updater) {
    __block CheckOutcome outcome = {nil, nil, NO};
    [updater checkForUpdate:^(AppUpdateRelease* release, NSError* error) {
        outcome.release = release; outcome.error = error; outcome.finished = YES;
    }];
    SpinUntil(^BOOL { return outcome.finished; }, 30);
    return outcome;
}

/// nil error and finished = the download is ready
static NSError* Download(AppUpdater* updater, BOOL* finished) {
    __block NSError* result = nil;
    __block BOOL done = NO;
    [updater downloadUpdate:^(NSError* error) { result = error; done = YES; }];
    SpinUntil(^BOOL { return done; }, 60);
    if (finished) *finished = done;
    return result;
}

static NSString* VersionOfApp(NSString* app) {
    NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"]];
    return info[@"CFBundleShortVersionString"];
}

static NSString* ReadyApp(void) {
    NSString* ready = [gLastWork stringByAppendingPathComponent:@"ready"];
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ready error:nil])
        if ([name hasSuffix:@".app"])
            return [ready stringByAppendingPathComponent:name];
    return nil;
}

/// Nothing that a download leaves behind: no working folder, nothing ready
static BOOL NothingLeftBehind(void) {
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:gLastWork error:nil])
        if ([name hasPrefix:@"download-"])
            return NO;
    return !Exists([gLastWork stringByAppendingPathComponent:@"ready"]);
}

#pragma mark - Versions and releases

static NSData* Json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static NSDictionary* Asset(NSString* name, NSString* base, NSString* tag, NSString* digest, NSNumber* size) {
    NSMutableDictionary* asset = [@{@"name": name, @"browser_download_url": [NSString stringWithFormat:@"%@/releases/download/%@/%@", base, tag, name]} mutableCopy];
    if (digest) asset[@"digest"] = digest;
    if (size) asset[@"size"] = size;
    return asset;
}

static void TestVersions(void) {
    CHECK([AppUpdateRelease isValidVersion:@"3.7.5"]);
    CHECK([AppUpdateRelease isValidVersion:@"0.0.0"]);
    CHECK(![AppUpdateRelease isValidVersion:@"3.7"]);
    CHECK(![AppUpdateRelease isValidVersion:@"3.7.5.1"]);
    CHECK(![AppUpdateRelease isValidVersion:@"v3.7.5"]);
    CHECK(![AppUpdateRelease isValidVersion:@"3.7.x"]);
    CHECK(![AppUpdateRelease isValidVersion:@"3..5"]);
    CHECK(![AppUpdateRelease isValidVersion:@""]);
    CHECK(![AppUpdateRelease isValidVersion:nil]);
    CHECK(![AppUpdateRelease isValidVersion:@"3.7.5 "]);
    CHECK([AppUpdateRelease compareVersion:@"3.7.10" toVersion:@"3.7.9"] == NSOrderedDescending);       //numbers, not text
    CHECK([AppUpdateRelease compareVersion:@"3.7.9" toVersion:@"3.7.10"] == NSOrderedAscending);
    CHECK([AppUpdateRelease compareVersion:@"3.7.5" toVersion:@"3.7.5"] == NSOrderedSame);
    CHECK([AppUpdateRelease compareVersion:@"3.10.0" toVersion:@"3.9.9"] == NSOrderedDescending);
    CHECK([AppUpdateRelease compareVersion:@"4.0.0" toVersion:@"3.99.99"] == NSOrderedDescending);
    CHECK([AppUpdateRelease compareVersion:@"3.7.4" toVersion:@"3.7.5"] == NSOrderedAscending);
    CHECK([[AppUpdateRelease fileNameForVersion:@"3.7.5"] isEqualToString:@"VOpenKey-3.7.5.dmg"]);
}

static void TestParsing(void) {
    NSURL* repository = [NSURL URLWithString:@"https://github.com/ntanvinh/OpenKey"];
    NSString* base = repository.absoluteString;
    NSString* hex = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    NSError* error = nil;
    NSDictionary* good = @{@"tag_name": @"v3.7.5", @"draft": @NO, @"prerelease": @NO,
                           @"html_url": @"https://github.com/ntanvinh/OpenKey/releases/tag/v3.7.5",
                           @"assets": @[Asset(@"VOpenKey-3.7.5.dmg", base, @"v3.7.5", [@"sha256:" stringByAppendingString:hex.uppercaseString], @(2800000)),
                                        Asset(@"VOpenKey-3.7.5.dmg.sha256", base, @"v3.7.5", nil, @(90)),
                                        Asset(@"VOpenKey.dmg", base, @"v3.7.5", nil, @(1)),
                                        Asset(@"VOpenKey-3.7.5-Windows.zip", base, @"v3.7.5", nil, @(1))]};
    AppUpdateRelease* release = [AppUpdateRelease releaseFromAPIData:Json(good) repository:repository error:&error];
    CHECK(release != nil && error == nil);
    CHECK([release.version isEqualToString:@"3.7.5"]);
    CHECK([release.fileURL.absoluteString isEqualToString:@"https://github.com/ntanvinh/OpenKey/releases/download/v3.7.5/VOpenKey-3.7.5.dmg"]);
    CHECK([release.checksumURL.absoluteString hasSuffix:@"/v3.7.5/VOpenKey-3.7.5.dmg.sha256"]);
    CHECK([release.sha256 isEqualToString:hex]);                                                      //lower case
    CHECK(release.size == 2800000);
    CHECK([release.pageURL.absoluteString isEqualToString:@"https://github.com/ntanvinh/OpenKey/releases/tag/v3.7.5"]);
    //a repository address with a slash at its end is the same
    CHECK([AppUpdateRelease releaseFromAPIData:Json(good) repository:[NSURL URLWithString:@"https://github.com/ntanvinh/OpenKey/"] error:nil] != nil);

    //no digest, no size: nothing published about the file
    NSMutableDictionary* plain = [good mutableCopy];
    plain[@"assets"] = @[Asset(@"VOpenKey-3.7.5.dmg", base, @"v3.7.5", nil, nil)];
    release = [AppUpdateRelease releaseFromAPIData:Json(plain) repository:repository error:&error];
    CHECK(release != nil && release.sha256 == nil && release.size == 0 && release.checksumURL == nil);

    //what is not a release to install
    NSDictionary* variants[] = {
        @{@"draft": @YES}, @{@"prerelease": @YES}, @{@"tag_name": @"3.7.5"}, @{@"tag_name": @"v3.7"}, @{@"tag_name": @"v3.7.5-beta"},
        @{@"assets": @[]},                                                                            //a release without its dmg
        @{@"assets": @[Asset(@"VOpenKey.dmg", base, @"v3.7.5", nil, nil)]},                           //the fixed-name copy is not what is downloaded
        @{@"assets": @[Asset(@"VOpenKey-3.7.4.dmg", base, @"v3.7.5", nil, nil)]},                     //the dmg of another version
        @{@"assets": @[@{@"name": @"VOpenKey-3.7.5.dmg", @"browser_download_url": @"https://evil.example/ntanvinh/OpenKey/releases/download/v3.7.5/VOpenKey-3.7.5.dmg"}]},
        @{@"assets": @[@{@"name": @"VOpenKey-3.7.5.dmg", @"browser_download_url": @"https://github.com/someone/else/releases/download/v3.7.5/VOpenKey-3.7.5.dmg"}]},
        @{@"assets": @[@{@"name": @"VOpenKey-3.7.5.dmg"}]},                                           //no address
    };
    for (size_t i = 0; i < sizeof variants / sizeof variants[0]; i++) {
        NSMutableDictionary* variant = [good mutableCopy];
        [variant addEntriesFromDictionary:variants[i]];
        error = nil;
        CHECK([AppUpdateRelease releaseFromAPIData:Json(variant) repository:repository error:&error] == nil);
        CHECK(error.code == AppUpdateErrorNoRelease);
        if (error.code != AppUpdateErrorNoRelease) printf("  (variant %zu)\n", i);
    }
    CHECK([AppUpdateRelease releaseFromAPIData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding] repository:repository error:&error] == nil);
    CHECK([AppUpdateRelease releaseFromAPIData:Json(@[@1]) repository:repository error:&error] == nil);
    CHECK([AppUpdateRelease releaseFromAPIData:nil repository:repository error:&error] == nil && error.code == AppUpdateErrorNoRelease);

    //a hash that is there and cannot be read is not ignored
    for (NSString* digest in @[@"sha256:abc", @"md5:0123456789abcdef0123456789abcdef", @"sha256:zzzz456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]) {
        NSMutableDictionary* variant = [good mutableCopy];
        variant[@"assets"] = @[Asset(@"VOpenKey-3.7.5.dmg", base, @"v3.7.5", digest, nil)];
        error = nil;
        CHECK([AppUpdateRelease releaseFromAPIData:Json(variant) repository:repository error:&error] == nil && error.code == AppUpdateErrorUnsafe);
    }

    //the addresses that follow from a tag, for when GitHub's API says no
    AppUpdateRelease* byTag = [AppUpdateRelease releaseForTag:@"v3.7.5" repository:repository];
    CHECK([byTag.version isEqualToString:@"3.7.5"]);
    CHECK([byTag.fileURL.absoluteString isEqualToString:@"https://github.com/ntanvinh/OpenKey/releases/download/v3.7.5/VOpenKey-3.7.5.dmg"]);
    CHECK([byTag.checksumURL.absoluteString isEqualToString:@"https://github.com/ntanvinh/OpenKey/releases/download/v3.7.5/VOpenKey-3.7.5.dmg.sha256"]);
    CHECK([byTag.pageURL.absoluteString isEqualToString:@"https://github.com/ntanvinh/OpenKey/releases/tag/v3.7.5"]);
    CHECK(byTag.sha256 == nil && byTag.size == 0);
    CHECK([AppUpdateRelease releaseForTag:@"3.7.5" repository:repository] == nil);
    CHECK([AppUpdateRelease releaseForTag:@"v3.7.5/../../x" repository:repository] == nil);
    CHECK([AppUpdateRelease releaseForTag:nil repository:repository] == nil);
}

#pragma mark - The signature

static void TestSignatures(NSString* apps) {
    NSString* newApp = [apps stringByAppendingPathComponent:@"new/VOpenKey AI.app"];
    NSURL* app = [NSURL fileURLWithPath:newApp isDirectory:YES];
    NSError* error = nil;

    CHECK([MakeVerifier() verifyApplication:app expectedVersion:@"9.9.9" error:&error] && error == nil);
    CHECK(![MakeVerifier() verifyApplication:app expectedVersion:@"9.9.8" error:&error] && error.code == AppUpdateErrorUnsafe);
    AppUpdateVerifier* other = [[AppUpdateVerifier alloc] initWithRequirement:@"identifier \"com.other.app\"" bundleIdentifier:@"com.other.app"];
    CHECK(![other verifyApplication:app expectedVersion:@"9.9.9" error:&error] && error.code == AppUpdateErrorUnsafe);
    //the identifier is right, the requirement is not
    AppUpdateVerifier* wrongRequirement = [[AppUpdateVerifier alloc] initWithRequirement:@"identifier \"com.other.app\"" bundleIdentifier:kTestIdentifier];
    CHECK(![wrongRequirement verifyApplication:app expectedVersion:@"9.9.9" error:&error] && error.code == AppUpdateErrorUnsafe);
    CHECK(![MakeVerifier() verifyApplication:[NSURL fileURLWithPath:@"/nonexistent/App.app"] expectedVersion:@"9.9.9" error:&error]);
    //an app that says it is another one is refused even when its signature satisfies the requirement
    NSURL* evil = [NSURL fileURLWithPath:[apps stringByAppendingPathComponent:@"wrongid/VOpenKey AI.app"] isDirectory:YES];
    AppUpdateVerifier* trusting = [[AppUpdateVerifier alloc] initWithRequirement:@"identifier \"com.evil.vopenkey\"" bundleIdentifier:kTestIdentifier];
    CHECK([trusting verifyApplication:evil expectedVersion:@"9.9.9" error:nil] == NO);
    AppUpdateVerifier* evilVerifier = [[AppUpdateVerifier alloc] initWithRequirement:@"identifier \"com.evil.vopenkey\"" bundleIdentifier:@"com.evil.vopenkey"];
    CHECK([evilVerifier verifyApplication:evil expectedVersion:@"9.9.9" error:nil]);                    //(it does verify against what it is told to trust)

    //the real requirement, the one of the Developer ID of the team: an app signed ad hoc is what an attacker makes
    AppUpdateVerifier* standard = [AppUpdateVerifier standard];
    CHECK(standard != nil);
    CHECK([standard.bundleIdentifier isEqualToString:VOK_BUNDLE_ID]);
    CHECK([standard.requirement containsString:[NSString stringWithFormat:@"certificate leaf[subject.OU] = \"%@\"", VOK_TEAM_ID]]);
    CHECK([standard.requirement hasPrefix:@"anchor apple generic and identifier"]);
    CHECK(![standard verifyApplication:app expectedVersion:@"9.9.9" error:&error]);
    CHECK(![standard runningApplicationSatisfiesRequirement]);                                         //this test program is nothing of the sort

    //a copy changed after it was signed
    NSString* copy = [gRoot stringByAppendingPathComponent:@"tamper/VOpenKey AI.app"];
    [[NSFileManager defaultManager] removeItemAtPath:[gRoot stringByAppendingPathComponent:@"tamper"] error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:[gRoot stringByAppendingPathComponent:@"tamper"] withIntermediateDirectories:YES attributes:nil error:nil];
    CHECK(RunProgram(@"/usr/bin/ditto", @[newApp, copy]) == 0);
    NSURL* copyURL = [NSURL fileURLWithPath:copy isDirectory:YES];
    CHECK([MakeVerifier() verifyApplication:copyURL expectedVersion:@"9.9.9" error:nil]);
    NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:[copy stringByAppendingPathComponent:@"Contents/Resources/data.txt"]];
    [handle seekToEndOfFile];
    [handle writeData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
    CHECK(![MakeVerifier() verifyApplication:copyURL expectedVersion:@"9.9.9" error:&error] && error.code == AppUpdateErrorUnsafe);

    //what goes into a requirement
    NSString* text = [AppUpdateVerifier requirementForTeam:@"39SH232CQ4" bundleIdentifier:@"vn.io.lssoft.vopenkey"];
    CHECK([text isEqualToString:@"anchor apple generic and identifier \"vn.io.lssoft.vopenkey\" and certificate leaf[subject.OU] = \"39SH232CQ4\" and "
          @"certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"]);
    CHECK([AppUpdateVerifier requirementForTeam:@"X\" or anchor apple" bundleIdentifier:@"a.b"] == nil);
    CHECK([AppUpdateVerifier requirementForTeam:@"ABCDE12345" bundleIdentifier:@"a.b\" or true"] == nil);
    CHECK([AppUpdateVerifier requirementForTeam:@"" bundleIdentifier:@"a.b"] == nil);
    CHECK([[AppUpdateVerifier alloc] initWithRequirement:@"" bundleIdentifier:@"a.b"] == nil);
    CHECK([[AppUpdateVerifier alloc] initWithRequirement:@"anchor apple" bundleIdentifier:@"a b"] == nil);
}

#pragma mark - Looking and downloading

static void TestDownloadOK(void) {
    TestUpdater* updater = NewUpdater(@"ok", @"1.0.0");
    NSMutableArray<NSNumber*>* states = [NSMutableArray array];
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:AppUpdaterDidChangeNotification object:updater queue:nil usingBlock:^(NSNotification* n) {
        [states addObject:@(updater.state)];
    }];
    CHECK(updater.state == AppUpdaterStateIdle && updater.availableRelease == nil && updater.progress < 0);
    CHECK(updater.readyUpdateWasTried == NO);

    //two checks at once share one request
    __block int answers = 0;
    __block AppUpdateRelease* second = nil;
    [updater checkForUpdate:^(AppUpdateRelease* r, NSError* e) { answers++; second = r; }];
    CheckOutcome first = Check(updater);
    SpinUntil(^BOOL { return answers == 1; }, 5);
    CHECK(first.release != nil && first.error == nil);
    CHECK([first.release.version isEqualToString:@"9.9.9"]);
    CHECK(second == first.release);
    CHECK(Count(ServerLog(@"ok"), @"GET /api/releases/latest") == 1);
    CHECK(updater.state == AppUpdaterStateAvailable && updater.availableRelease == first.release);
    CHECK([states containsObject:@(AppUpdaterStateChecking)] && [states containsObject:@(AppUpdaterStateAvailable)]);

    BOOL finished = NO;
    NSError* error = Download(updater, &finished);
    CHECK(finished && error == nil);
    if (error != nil) printf("  (download: %s)\n", error.localizedDescription.UTF8String);
    CHECK(updater.state == AppUpdaterStateReady);
    CHECK([states containsObject:@(AppUpdaterStateDownloading)] && states.lastObject.integerValue == AppUpdaterStateReady);
    if (ReadyApp() == nil) {
        printf("  (nothing is ready: the rest of this test is skipped)\n");
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        return;
    }
    CHECK([VersionOfApp(ReadyApp()) isEqualToString:@"9.9.9"]);
    CHECK([MakeVerifier() verifyApplication:[NSURL fileURLWithPath:ReadyApp()] expectedVersion:@"9.9.9" error:nil]);
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:gLastWork error:nil])
        CHECK(![name hasPrefix:@"download-"]);
    NSArray* log = ServerLog(@"ok");
    CHECK(Count(log, @"GET /repo/releases/download/v9.9.9/VOpenKey-9.9.9.dmg") == 1);
    CHECK(Count(log, @".sha256") == 0);                                                              //the API had the hash
    CHECK(Count(log, @"VOpenKey.dmg") == 0 && Count(log, @"Windows") == 0);

    //a check while it is ready changes nothing, and a second download is already done
    CheckOutcome again = Check(updater);
    CHECK(again.release == first.release && again.error == nil && updater.state == AppUpdaterStateReady);
    CHECK(Download(updater, &finished) == nil && finished);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

static void TestHashes(void) {
    //the hash comes from the .sha256 file when the API does not carry it
    TestUpdater* updater = NewUpdater(@"nodigest", @"1.0.0");
    CHECK(Check(updater).release != nil);
    CHECK(Download(updater, NULL) == nil && updater.state == AppUpdaterStateReady);
    CHECK(Count(ServerLog(@"nodigest"), @"VOpenKey-9.9.9.dmg.sha256") == 1);

    //nothing published: the signature is what decides
    updater = NewUpdater(@"nodigest-nosum", @"1.0.0");
    CHECK(Check(updater).release != nil);
    CHECK(Download(updater, NULL) == nil && updater.state == AppUpdaterStateReady);

    NSArray* refused = @[@"nodigest-badsum", @"badhash", @"badsize"];
    for (NSString* name in refused) {
        updater = NewUpdater(name, @"1.0.0");
        CHECK(Check(updater).release != nil);
        BOOL finished = NO;
        NSError* error = Download(updater, &finished);
        CHECK(finished && error.code == AppUpdateErrorUnsafe);
        CHECK(updater.state == AppUpdaterStateAvailable && updater.availableRelease != nil);           //it can be tried again
        CHECK(NothingLeftBehind());
        if (error.code != AppUpdateErrorUnsafe) printf("  (%s: %s)\n", name.UTF8String, error.localizedDescription.UTF8String);
    }

    //a hash that cannot be read stops it at the check
    updater = NewUpdater(@"baddigest", @"1.0.0");
    CheckOutcome outcome = Check(updater);
    CHECK(outcome.release == nil && outcome.error.code == AppUpdateErrorUnsafe && updater.state == AppUpdaterStateIdle);
}

static void TestNotNewer(void) {
    for (NSString* name in @[@"same", @"older"]) {
        TestUpdater* updater = NewUpdater(name, @"1.0.0");
        CheckOutcome outcome = Check(updater);
        CHECK(outcome.finished && outcome.release == nil && outcome.error == nil);
        CHECK(updater.state == AppUpdaterStateIdle && updater.availableRelease == nil);
        BOOL finished = NO;
        NSError* error = Download(updater, &finished);                                                  //nothing to download
        CHECK(finished && error != nil);
    }
    TestUpdater* updater = NewUpdater(@"norelease", @"1.0.0");                                          //a repository without releases
    CheckOutcome outcome = Check(updater);
    CHECK(outcome.finished && outcome.release == nil && outcome.error == nil && updater.state == AppUpdaterStateIdle);

    //9.9.10 is newer than 9.9.9: numbers, not text
    updater = NewUpdater(@"tenth", @"9.9.9");
    outcome = Check(updater);
    CHECK([outcome.release.version isEqualToString:@"9.9.10"]);
    CHECK(Download(updater, NULL) == nil && updater.state == AppUpdaterStateReady);
    CHECK([VersionOfApp(ReadyApp()) isEqualToString:@"9.9.10"]);
}

static void TestNotARelease(void) {
    for (NSString* name in @[@"evilurl", @"prerelease", @"draft", @"badtag", @"nodmg"]) {
        TestUpdater* updater = NewUpdater(name, @"1.0.0");
        CheckOutcome outcome = Check(updater);
        CHECK(outcome.finished && outcome.release == nil && outcome.error.code == AppUpdateErrorNoRelease);
        CHECK(updater.state == AppUpdaterStateIdle);
        if (outcome.error.code != AppUpdateErrorNoRelease) printf("  (%s)\n", name.UTF8String);
    }
}

static void TestNetworkFailures(void) {
    //GitHub's API refuses (it does when it is asked too often from one address): the page of the latest release tells the version
    TestUpdater* updater = NewUpdater(@"ratelimited", @"1.0.0");
    CheckOutcome outcome = Check(updater);
    CHECK([outcome.release.version isEqualToString:@"9.9.9"] && outcome.error == nil);
    NSArray* log = ServerLog(@"ratelimited");
    CHECK(Count(log, @"GET /api/releases/latest") == 1 && Count(log, @"HEAD /repo/releases/latest") == 1);
    CHECK(Download(updater, NULL) == nil && updater.state == AppUpdaterStateReady);
    CHECK(Count(ServerLog(@"ratelimited"), @"VOpenKey-9.9.9.dmg.sha256") == 1);                       //no digest: the hash file is read

    for (NSString* name in @[@"ratelimited-nofallback", @"unavailable"]) {
        updater = NewUpdater(name, @"1.0.0");
        outcome = Check(updater);
        CHECK(outcome.release == nil && outcome.error.code == AppUpdateErrorNetwork && updater.state == AppUpdaterStateIdle);
    }

    //a check that fails does not forget what an earlier one found: the server starts answering 500 between the two
    updater = NewUpdater(@"ok", @"1.0.0");
    CheckOutcome found = Check(updater);
    CHECK(found.release != nil && updater.state == AppUpdaterStateAvailable);
    NSString* statusFile = [[gFixtures stringByAppendingPathComponent:@"ok"] stringByAppendingPathComponent:@"api.status"];
    CHECK([@"500" writeToFile:statusFile atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    CheckOutcome failed = Check(updater);
    [[NSFileManager defaultManager] removeItemAtPath:statusFile error:nil];
    CHECK(failed.release == nil && failed.error.code == AppUpdateErrorNetwork);
    if (failed.error == nil || failed.release != nil) {
        printf("  (second check: release %s, error %s)\n", failed.release.version.UTF8String, failed.error.localizedDescription.UTF8String);
        for (NSString* line in ServerLog(@"ok")) printf("    %s\n", line.UTF8String);
    }
    CHECK(updater.state == AppUpdaterStateAvailable && updater.availableRelease == found.release);

    //the server is not there at all
    TestUpdater* dead = [[TestUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://127.0.0.1:1/api"] repositoryURL:[NSURL URLWithString:@"http://127.0.0.1:1/repo"]
                                              workDirectory:[NSURL fileURLWithPath:[gRoot stringByAppendingPathComponent:@"dead"] isDirectory:YES]
                                              installTarget:[NSURL fileURLWithPath:@"/tmp/x/VOpenKey AI.app"] currentVersion:@"1.0.0" verifier:MakeVerifier()];
    CheckOutcome gone = Check(dead);
    CHECK(gone.finished && gone.release == nil && gone.error.code == AppUpdateErrorNetwork && dead.state == AppUpdaterStateIdle);

    //an address that is not https (and not this Mac) is not fetched
    TestUpdater* plain = [[TestUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://example.com/api"] repositoryURL:[NSURL URLWithString:@"http://example.com/repo"]
                                               workDirectory:[NSURL fileURLWithPath:[gRoot stringByAppendingPathComponent:@"plain"] isDirectory:YES]
                                               installTarget:[NSURL fileURLWithPath:@"/tmp/x/VOpenKey AI.app"] currentVersion:@"1.0.0" verifier:MakeVerifier()];
    CHECK(Check(plain).error.code == AppUpdateErrorNetwork);
    CHECK([[AppUpdater alloc] initWithAPIURL:nil repositoryURL:[NSURL URLWithString:@"http://x"] workDirectory:[NSURL fileURLWithPath:@"/tmp"] installTarget:[NSURL fileURLWithPath:@"/tmp/A.app"]
                              currentVersion:@"1.0.0" verifier:MakeVerifier()] == nil);
    CHECK([[AppUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://x"] repositoryURL:[NSURL URLWithString:@"http://x"] workDirectory:[NSURL fileURLWithPath:@"/tmp"]
                               installTarget:[NSURL fileURLWithPath:@"/tmp/A.app"] currentVersion:@"v1" verifier:MakeVerifier()] == nil);
}

static void TestBadDownloads(void) {
    NSDictionary<NSString*, NSNumber*>* expected = @{
        @"status500": @(AppUpdateErrorNetwork), @"truncated": @(AppUpdateErrorNetwork), @"toobig": @(AppUpdateErrorUnsafe),
        @"garbage": @(AppUpdateErrorUnsafe), @"noapp": @(AppUpdateErrorUnsafe), @"twoapps": @(AppUpdateErrorUnsafe), @"linkedapp": @(AppUpdateErrorUnsafe),
        @"unsigned": @(AppUpdateErrorUnsafe), @"wrongid": @(AppUpdateErrorUnsafe), @"wrongversion": @(AppUpdateErrorUnsafe),
        @"tampered": @(AppUpdateErrorUnsafe), @"minos": @(AppUpdateErrorNoRelease),
    };
    for (NSString* name in expected) {
        TestUpdater* updater = NewUpdater(name, @"1.0.0");
        CHECK(Check(updater).release != nil);
        NSDate* started = [NSDate date];
        BOOL finished = NO;
        NSError* error = Download(updater, &finished);
        CHECK(finished);
        CHECK(error != nil && error.code == expected[name].integerValue);
        CHECK(updater.state == AppUpdaterStateAvailable && updater.availableRelease != nil);
        CHECK(NothingLeftBehind());
        CHECK(-[started timeIntervalSinceNow] < 20);
        if (error == nil || error.code != expected[name].integerValue)
            printf("  (%s: %s)\n", name.UTF8String, error ? error.localizedDescription.UTF8String : "no error");
    }
    TestUpdater* updater = NewUpdater(@"minos", @"1.0.0");
    CHECK(Check(updater).release != nil);
    CHECK([Download(updater, NULL).localizedDescription containsString:@"macOS 99.0"]);
}

static void TestCancel(void) {
    TestUpdater* updater = NewUpdater(@"stall", @"1.0.0");
    CHECK(Check(updater).release != nil);
    __block NSError* result = nil;
    __block BOOL done = NO;
    NSDate* started = [NSDate date];
    [updater downloadUpdate:^(NSError* error) { result = error; done = YES; }];
    SpinUntil(^BOOL { return updater.state == AppUpdaterStateDownloading; }, 5);
    SpinUntil(^BOOL { return NO; }, 0.5);
    [updater cancel];
    SpinUntil(^BOOL { return done; }, 20);
    CHECK(done && result.code == AppUpdateErrorCancelled);
    CHECK(-[started timeIntervalSinceNow] < 2.8);                                                      //not after the server gave up
    CHECK(updater.state == AppUpdaterStateAvailable && NothingLeftBehind());
}

#pragma mark - Keeping and installing

static void CopyApp(NSString* from, NSString* to) {
    [[NSFileManager defaultManager] createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    CHECK(RunProgram(@"/usr/bin/ditto", @[from, to]) == 0);
}

/// An updater whose folder has the new app in `ready` and whose target is the old one, with a script that records the openings.
static TestUpdater* UpdaterWithReadyApp(NSString* name, NSString* apps, NSString* currentVersion) {
    NSString* folder = [gRoot stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    NSString* work = [folder stringByAppendingPathComponent:@"work"];
    NSString* target = [folder stringByAppendingPathComponent:@"apps/VOpenKey AI.app"];
    CopyApp([apps stringByAppendingPathComponent:@"old/VOpenKey AI.app"], target);
    CopyApp([apps stringByAppendingPathComponent:@"new/VOpenKey AI.app"], [work stringByAppendingPathComponent:@"ready/VOpenKey AI.app"]);
    gLastWork = work;
    NSString* script = [folder stringByAppendingPathComponent:@"relaunch.sh"];
    CHECK([@"#!/bin/sh\necho \"$@\" >> \"$(dirname \"$0\")/launched.txt\"\n" writeToFile:script atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    chmod(script.fileSystemRepresentation, 0755);
    TestUpdater* updater = [[TestUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://127.0.0.1:1/api"] repositoryURL:[NSURL URLWithString:@"http://127.0.0.1:1/repo"]
                                                 workDirectory:[NSURL fileURLWithPath:work isDirectory:YES]
                                                 installTarget:[NSURL fileURLWithPath:target isDirectory:YES]
                                                currentVersion:currentVersion verifier:MakeVerifier()];
    updater.requiresSignedHost = NO;
    updater.relaunchTool = script;
    return updater;
}

static BOOL LoadReady(AppUpdater* updater) {
    __block BOOL done = NO;
    [updater loadReadyUpdate:^{ done = YES; }];
    SpinUntil(^BOOL { return done; }, 30);
    return done;
}

static void TestReadyUpdate(NSString* apps) {
    //an update that an earlier run left, and that is intact and newer
    TestUpdater* updater = UpdaterWithReadyApp(@"ready-ok", apps, @"1.0.0");
    CHECK(LoadReady(updater));
    CHECK(updater.state == AppUpdaterStateReady && [updater.availableRelease.version isEqualToString:@"9.9.9"]);
    CHECK(updater.availableRelease.pageURL != nil);

    //nothing left
    updater = UpdaterWithReadyApp(@"ready-none", apps, @"1.0.0");
    [[NSFileManager defaultManager] removeItemAtPath:[gLastWork stringByAppendingPathComponent:@"ready"] error:nil];
    CHECK(LoadReady(updater) && updater.state == AppUpdaterStateIdle);

    //it was installed: the app is now that version, what is left is rubbish
    updater = UpdaterWithReadyApp(@"ready-installed", apps, @"9.9.9");
    CHECK(LoadReady(updater) && updater.state == AppUpdaterStateIdle && !Exists([gLastWork stringByAppendingPathComponent:@"ready"]));

    //older than the app
    updater = UpdaterWithReadyApp(@"ready-older", apps, @"9.9.10");
    CHECK(LoadReady(updater) && updater.state == AppUpdaterStateIdle && !Exists([gLastWork stringByAppendingPathComponent:@"ready"]));

    //changed since: not offered, and removed
    updater = UpdaterWithReadyApp(@"ready-changed", apps, @"1.0.0");
    NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:[gLastWork stringByAppendingPathComponent:@"ready/VOpenKey AI.app/Contents/Resources/data.txt"]];
    [handle seekToEndOfFile];
    [handle writeData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
    CHECK(LoadReady(updater) && updater.state == AppUpdaterStateIdle && !Exists([gLastWork stringByAppendingPathComponent:@"ready"]));
}

static void TestReasons(NSString* apps) {
    TestUpdater* updater = UpdaterWithReadyApp(@"reasons", apps, @"1.0.0");
    CHECK(updater.reasonCannotInstall == nil);

    NSURL* work = [NSURL fileURLWithPath:gLastWork isDirectory:YES];
    NSArray<NSString*>* paths = @[@"/private/var/folders/xx/AppTranslocation/ABC/d/VOpenKey AI.app", @"/Users/x/Applications/VOpenKey", @"/nonexistent-folder/VOpenKey AI.app"];
    for (NSString* path in paths) {
        AppUpdater* other = [[AppUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://127.0.0.1:1/api"] repositoryURL:[NSURL URLWithString:@"http://127.0.0.1:1/repo"]
                                                 workDirectory:work installTarget:[NSURL fileURLWithPath:path] currentVersion:@"1.0.0" verifier:MakeVerifier()];
        other.requiresSignedHost = NO;
        CHECK(other.reasonCannotInstall.length > 0);
    }
    //an app that is not signed by us is not replaced (the standard requirement is the one of the team)
    AppUpdater* unsigned_ = [[AppUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://127.0.0.1:1/api"] repositoryURL:[NSURL URLWithString:@"http://127.0.0.1:1/repo"]
                                                 workDirectory:work installTarget:[NSURL fileURLWithPath:[gRoot stringByAppendingPathComponent:@"reasons/apps/VOpenKey AI.app"]]
                                                 currentVersion:@"1.0.0" verifier:[AppUpdateVerifier standard]];
    CHECK(unsigned_.reasonCannotInstall.length > 0);
    unsigned_.requiresSignedHost = NO;
    CHECK(unsigned_.reasonCannotInstall == nil);

    //a folder that cannot be written
    NSString* parent = [gRoot stringByAppendingPathComponent:@"reasons/apps"];
    chmod(parent.fileSystemRepresentation, 0555);
    CHECK(updater.reasonCannotInstall.length > 0);
    chmod(parent.fileSystemRepresentation, 0755);

    //not ready: nothing to install
    NSError* error = nil;
    CHECK(![updater installReadyUpdate:&error] && error.code == AppUpdateErrorInstall);
}

/// A process that quits after `seconds`, and that nobody has to collect: its parent is gone, so it does not stay a zombie that answers
/// kill -0 for ever. It stands for the running app, whose process the helper waits for.
static pid_t StartProcessThatQuits(double seconds) {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[@"-c", [NSString stringWithFormat:@"sleep %.1f >/dev/null 2>&1 </dev/null & echo $!", seconds]];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil])
        return 0;
    NSData* data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return (pid_t)[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] intValue];
}

static BOOL WaitForFile(NSString* path) {
    return SpinUntil(^BOOL { return Exists(path); }, 30);
}

static void TestInstall(NSString* apps) {
    NSString* folder = [gRoot stringByAppendingPathComponent:@"install"];
    TestUpdater* updater = UpdaterWithReadyApp(@"install", apps, @"1.0.0");
    NSString* target = [folder stringByAppendingPathComponent:@"apps/VOpenKey AI.app"];
    NSString* launched = [folder stringByAppendingPathComponent:@"launched.txt"];
    CHECK(LoadReady(updater) && updater.state == AppUpdaterStateReady);
    CHECK(!updater.readyUpdateWasTried);
    CHECK([VersionOfApp(target) isEqualToString:@"1.0.0"]);

    //the app that is running when the helper starts: here a program that quits after a second and a half
    updater.processToWaitFor = StartProcessThatQuits(1.5);
    CHECK(updater.processToWaitFor > 0);
    NSDate* started = [NSDate date];
    NSError* error = nil;
    CHECK([updater installReadyUpdate:&error] && error == nil);
    CHECK(updater.readyUpdateWasTried);
    SpinUntil(^BOOL { return NO; }, 0.5);
    CHECK([VersionOfApp(target) isEqualToString:@"1.0.0"]);                                          //it waits for the app to quit
    CHECK(!Exists(launched));
    CHECK(WaitForFile(launched));
    CHECK(-[started timeIntervalSinceNow] > 1.2);                                                      //it did wait for the app to quit
    NSString* record = [NSString stringWithContentsOfFile:launched encoding:NSUTF8StringEncoding error:nil];
    CHECK([record containsString:target]);
    CHECK([VersionOfApp(target) isEqualToString:@"9.9.9"]);
    CHECK([MakeVerifier() verifyApplication:[NSURL fileURLWithPath:target isDirectory:YES] expectedVersion:@"9.9.9" error:nil]);   //the signature survived the copy
    NSArray* around = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder stringByAppendingPathComponent:@"apps"] error:nil];
    CHECK(around.count == 1);                                                                          //no old copy, no half-copied new one
    CHECK([[NSString stringWithContentsOfFile:[gLastWork stringByAppendingPathComponent:@"result"] encoding:NSUTF8StringEncoding error:nil] hasPrefix:@"ok 9.9.9"]);
    CHECK([updater takeLastInstallFailure] == nil);
    CHECK(!Exists([gLastWork stringByAppendingPathComponent:@"result"]));                              //said once

    //the next start of the new version: what is left of the update is rubbish
    TestUpdater* next = [[TestUpdater alloc] initWithAPIURL:[NSURL URLWithString:@"http://127.0.0.1:1/api"] repositoryURL:[NSURL URLWithString:@"http://127.0.0.1:1/repo"]
                                              workDirectory:[NSURL fileURLWithPath:gLastWork isDirectory:YES] installTarget:[NSURL fileURLWithPath:target isDirectory:YES]
                                             currentVersion:@"9.9.9" verifier:MakeVerifier()];
    CHECK(LoadReady(next) && next.state == AppUpdaterStateIdle && !next.readyUpdateWasTried);
    CHECK(!Exists([gLastWork stringByAppendingPathComponent:@"ready"]));
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UpdateInstallTriedVersion"];
}

static void TestInstallFails(NSString* apps) {
    NSString* folder = [gRoot stringByAppendingPathComponent:@"install-fails"];
    TestUpdater* updater = UpdaterWithReadyApp(@"install-fails", apps, @"1.0.0");
    NSString* target = [folder stringByAppendingPathComponent:@"apps/VOpenKey AI.app"];
    NSString* parent = [folder stringByAppendingPathComponent:@"apps"];
    NSString* launched = [folder stringByAppendingPathComponent:@"launched.txt"];
    CHECK(LoadReady(updater));

    //the folder stops being writable after the checks and before the helper acts: the old app stays and is opened again
    updater.processToWaitFor = StartProcessThatQuits(1.5);
    CHECK(updater.processToWaitFor > 0);
    CHECK([updater installReadyUpdate:nil]);
    chmod(parent.fileSystemRepresentation, 0555);
    CHECK(WaitForFile(launched));
    chmod(parent.fileSystemRepresentation, 0755);
    CHECK([VersionOfApp(target) isEqualToString:@"1.0.0"]);
    CHECK([[NSString stringWithContentsOfFile:launched encoding:NSUTF8StringEncoding error:nil] containsString:target]);
    NSString* message = [updater takeLastInstallFailure];
    CHECK([message containsString:@"Cập nhật không hoàn tất"] && [message containsString:@"VOpenKey AI"]);
    CHECK([updater takeLastInstallFailure] == nil);
    CHECK([[NSFileManager defaultManager] contentsOfDirectoryAtPath:parent error:nil].count == 1);

    //the ready app is checked once more just before it is installed
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UpdateInstallTriedVersion"];
    updater = UpdaterWithReadyApp(@"install-changed", apps, @"1.0.0");
    NSString* launchedChanged = [[gLastWork stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"launched.txt"];
    CHECK(LoadReady(updater) && updater.state == AppUpdaterStateReady);
    NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:[gLastWork stringByAppendingPathComponent:@"ready/VOpenKey AI.app/Contents/Resources/data.txt"]];
    [handle seekToEndOfFile];
    [handle writeData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
    NSError* error = nil;
    CHECK(![updater installReadyUpdate:&error] && error.code == AppUpdateErrorUnsafe);
    SpinUntil(^BOOL { return NO; }, 0.5);
    CHECK(!Exists(launchedChanged));
    CHECK(!updater.readyUpdateWasTried);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UpdateInstallTriedVersion"];
}

//the one step the other tests take out: the disk image is opened by hdiutil, like in the app
static void TestRealDiskImage(void) {
    if (!Exists([gFixtures stringByAppendingPathComponent:@"realdmg"])) {
        printf("SKIPPED: the real disk image (VOK_TEST_REAL_DMG=1 makes one with hdiutil)\n");
        return;
    }
    AppUpdater* updater = NewUpdaterOfClass([StubbedUpdater class], @"realdmg", @"1.0.0");
    CHECK(Check(updater).release != nil);
    BOOL finished = NO;
    NSError* error = Download(updater, &finished);
    CHECK(finished && error == nil);
    CHECK(updater.state == AppUpdaterStateReady);
    CHECK(ReadyApp() != nil && [VersionOfApp(ReadyApp()) isEqualToString:@"9.9.9"]);
    CHECK([MakeVerifier() verifyApplication:[NSURL fileURLWithPath:ReadyApp()] expectedVersion:@"9.9.9" error:nil]);
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:gLastWork error:nil])
        CHECK(![name hasPrefix:@"download-"]);
    //the volume is gone: the folder it was on is not a mount point any more
    CHECK(RunProgram(@"/bin/sh", @[@"-c", [NSString stringWithFormat:@"mount | grep -q '%@'", gLastWork]]) != 0);
}

static void TestDefaults(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"AutoInstallUpdates"];
    CHECK([AppUpdater automaticInstallEnabled]);                                                       //on until the user turns it off
    [defaults setBool:NO forKey:@"AutoInstallUpdates"];
    CHECK(![AppUpdater automaticInstallEnabled]);
    [defaults removeObjectForKey:@"AutoInstallUpdates"];
    CHECK([AppUpdater shared] != nil);                                                                 //this program has no version of its own: it counts as 0.0.0
    CHECK([[AppUpdater shared].currentVersion isEqualToString:@"0.0.0"]);
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            printf("usage: app_update_test <fixtures> <work folder>\n");
            return 2;
        }
        gFixtures = @(argv[1]);
        gRoot = @(argv[2]);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UpdateInstallTriedVersion"];
        NSString* apps = [gFixtures stringByAppendingPathComponent:@"_apps"];

        TestVersions();
        TestParsing();
        TestSignatures(apps);
        TestDownloadOK();
        TestHashes();
        TestNotNewer();
        TestNotARelease();
        TestNetworkFailures();
        TestBadDownloads();
        TestCancel();
        TestReadyUpdate(apps);
        TestReasons(apps);
        TestInstall(apps);
        TestInstallFails(apps);
        TestRealDiskImage();
        TestDefaults();
    }
    printf(failures == 0 ? "app_update_test: all passed\n" : "app_update_test: %d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
