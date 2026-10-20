//
//  AppUpdater.h
//  VOpenKey
//
//  Updates VOpenKey AI from the releases of its GitHub repository: finds the newest release, downloads its dmg, checks it (size, SHA-256
//  and above all the signature: only an app signed by the Apple Developer Team of VOpenKey AI is ever installed) and replaces the
//  running app with it once it has quit. Nothing here shows a window: the alerts are in OpenKeyManager, the menu item in
//  StatusMenuController, the button in the Settings; they listen to AppUpdaterDidChangeNotification.
//
//  The work is done in steps that each one can be tested without GitHub (tests/run-app-update-test.sh runs them against a fake one).
//

#import <Foundation/Foundation.h>

//posted on the main queue each time the state or the progress changes
extern NSString* const AppUpdaterDidChangeNotification;
extern NSString* const AppUpdateErrorDomain;

typedef NS_ENUM(NSInteger, AppUpdateErrorCode) {
    AppUpdateErrorNetwork = 1,      //GitHub could not be reached, or answered with an error
    AppUpdateErrorNoRelease,        //the answer is not a release this updater can use (no dmg yet, a draft...)
    AppUpdateErrorUnsafe,           //the file is not what was published, or not signed by us: it is never installed
    AppUpdateErrorInstall,          //the new version could not be put in place
    AppUpdateErrorCancelled,
};

#pragma mark - A release

@interface AppUpdateRelease : NSObject <NSCopying>
@property (readonly, copy) NSString* version;       //3.7.5
@property (readonly, copy) NSURL* pageURL;          //the page of the release on GitHub
@property (readonly, copy) NSURL* fileURL;          //VOpenKey-3.7.5.dmg
@property (readonly) uint64_t size;                 //of the dmg; 0 when the release does not say
@property (readonly, copy) NSString* sha256;        //of the dmg, lower case; nil when the release does not say
@property (readonly, copy) NSURL* checksumURL;      //the VOpenKey-3.7.5.dmg.sha256 of the release; nil when there is none

/// "3.7.5": three numbers, nothing else.
+(BOOL)isValidVersion:(NSString*)text;
/// Numeric, so that 3.7.10 is newer than 3.7.9. Both must be valid versions.
+(NSComparisonResult)compareVersion:(NSString*)a toVersion:(NSString*)b;
/// The file name of the dmg of a version, "VOpenKey-3.7.5.dmg".
+(NSString*)fileNameForVersion:(NSString*)version;
/// Reads the answer of GitHub (releases/latest). Every address in it must be inside `repository`, the address of the repository.
/// A draft, a pre-release, a tag that is not v<version> or a release without its dmg gives nil and AppUpdateErrorNoRelease.
+(AppUpdateRelease*)releaseFromAPIData:(NSData*)data repository:(NSURL*)repository error:(NSError**)error;
/// The release of a tag, with the addresses its files have by the conventions of scripts/release.sh. Nil when the tag is not v<version>.
+(AppUpdateRelease*)releaseForTag:(NSString*)tag repository:(NSURL*)repository;
@end

#pragma mark - Who made it

@interface AppUpdateVerifier : NSObject
@property (readonly, copy) NSString* requirement;           //what the signature of an update has to satisfy
@property (readonly, copy) NSString* bundleIdentifier;      //what an update says it is

-(instancetype)initWithRequirement:(NSString*)requirement bundleIdentifier:(NSString*)bundleIdentifier;
/// The requirement of the real updates: Apple's certificate chain, a Developer ID certificate of the Team, the identifier of the app.
/// Nil when the team or the identifier are not plain letters, digits, dots and dashes (they go into the requirement).
+(NSString*)requirementForTeam:(NSString*)team bundleIdentifier:(NSString*)bundleIdentifier;
/// VOK_TEAM_ID and VOK_BUNDLE_ID.
+(AppUpdateVerifier*)standard;

/// The application is the app (identifier), is the version it should be, has a signature that holds up (every file, every
/// architecture) and satisfies the requirement.
-(BOOL)verifyApplication:(NSURL*)app expectedVersion:(NSString*)version error:(NSError**)error;
/// Whether the app that is running now satisfies the requirement: an app that was not signed by us (built from the source, a copy
/// from a fork) is not replaced by an update.
-(BOOL)runningApplicationSatisfiesRequirement;
@end

#pragma mark - The updater

typedef NS_ENUM(NSInteger, AppUpdaterState) {
    AppUpdaterStateIdle,            //nothing is known, or the version is the newest
    AppUpdaterStateChecking,
    AppUpdaterStateAvailable,       //a newer release exists
    AppUpdaterStateDownloading,
    AppUpdaterStateReady,           //downloaded, verified, waiting for the app to restart
};

@interface AppUpdater : NSObject

/// The updater of this app: VOpenKey AI, its repository on GitHub, replaces the bundle that is running.
+(AppUpdater*)shared;
/// Settings that have a value before anything is read (AutoInstallUpdates).
+(void)registerDefaults;
/// Whether updates are downloaded by themselves (Settings > "Tự động tải và cài bản mới").
+(BOOL)automaticInstallEnabled;

-(instancetype)initWithAPIURL:(NSURL*)apiURL repositoryURL:(NSURL*)repositoryURL workDirectory:(NSURL*)workDirectory
                installTarget:(NSURL*)installTarget currentVersion:(NSString*)currentVersion verifier:(AppUpdateVerifier*)verifier NS_DESIGNATED_INITIALIZER;
-(instancetype)init NS_UNAVAILABLE;

//--- For tests: what is taken out so that the rest can be tried without a disk image or a second app
/// Opens the disk image on the folder (its volume appears there) and takes it away again. Override to give the folder something else.
-(BOOL)mountImage:(NSURL*)image at:(NSURL*)mountPoint;
-(void)unmountImageAt:(NSURL*)mountPoint;
@property (copy) NSArray<Class>* protocolClasses;       //what answers the requests instead of the network
@property (copy) NSString* relaunchTool;                //opens the new app; "/usr/bin/open"
@property pid_t processToWaitFor;                       //the helper waits until it has quit; this process
@property BOOL requiresSignedHost;                      //the running app has to satisfy the requirement to be replaced; YES

@property (readonly) AppUpdaterState state;
@property (readonly, copy) NSString* currentVersion;
@property (readonly, copy) AppUpdateRelease* availableRelease;   //the newer release (Available, Downloading, Ready); nil otherwise
@property (readonly) double progress;                   //0...1 while Downloading, -1 when it is not known
/// Nil when this app can replace itself; otherwise why not (it runs from a disk image or from a folder it cannot write...).
@property (readonly, copy) NSString* reasonCannotInstall;

/// Asks GitHub for the newest release. The completion (main queue) gets the release when it is newer than this app, or nil and no
/// error when it is not. Several calls at once share one request.
-(void)checkForUpdate:(void (^)(AppUpdateRelease* release, NSError* error))completion;
/// Downloads the release found by the check, verifies it and keeps it ready; then the state is Ready.
-(void)downloadUpdate:(void (^)(NSError* error))completion;
/// A download that an earlier run left ready (verified again). Calls back on the main queue; the state is Ready when there is one.
-(void)loadReadyUpdate:(void (^)(void))completion;
/// Starts the helper that waits for this app to quit, replaces it with the ready version and opens it. The caller quits the app.
-(BOOL)installReadyUpdate:(NSError**)error;
/// What the helper of the last install says when it did not manage (the old app is still there), in words for the user; nil when it
/// managed or there was no install. Said once: the helper's note is deleted by this.
-(NSString*)takeLastInstallFailure;
/// Whether an install of the ready update was already started and this app is still the old one: it is not tried again by itself.
@property (readonly) BOOL readyUpdateWasTried;
-(void)cancel;
@end
