//
//  AIOllamaInstaller.h
//  VOpenKey
//
//  Puts Ollama, the program that runs AI models, on this Mac, without the user visiting a website: downloads the official
//  release, checks it, and installs it in ~/Applications (the folder of the applications of this user, no administrator needed).
//
//  A program is downloaded from the internet and then run, so nothing is trusted until it is checked, in this order:
//  1. only https is followed (a redirect to plain http is refused);
//  2. the size and the SHA-256 that GitHub publishes for the file must match;
//  3. the zip is opened in a folder that is private to this run, which is empty before;
//  4. the application must be signed by Apple's Developer ID of Ollama's company (the Team ID and the bundle id are pinned), the
//     signature must be intact on every part, including the server inside, and Apple must have notarized it (spctl);
//  5. only then is it moved to its place. What fails any check is deleted, never run, never installed.
//  Nothing is ever executed from the download folder.
//

#import <Foundation/Foundation.h>

/// What is pinned about Ollama's application: who signed it and what it is called.
@interface AIOllamaVerifier : NSObject
/// 3MU9H2V9Y9 (Infra Technologies, Inc, the company of Ollama) and com.electron.ollama. Both must be plain identifiers.
-(instancetype)initWithTeamIdentifier:(NSString*)teamIdentifier bundleIdentifier:(NSString*)bundleIdentifier;
+(AIOllamaVerifier*)standard;
@property (nonatomic, readonly, copy) NSString* teamIdentifier;
@property (nonatomic, readonly, copy) NSString* bundleIdentifier;
/// Whether Apple's notarization is required (always, but a test of the rest can turn it off).
@property (nonatomic) BOOL requiresNotarization;

/// Checks the application and the server program inside it. On failure the error says why, in Vietnamese. `minimumOS` gets the
/// version of macOS the application asks for (all zero when it asks for none).
-(BOOL)verifyApplication:(NSURL*)app minimumOS:(NSOperatingSystemVersion*)minimumOS error:(NSError**)error;
/// Only the signature, quick: for an application that was verified when it was installed.
-(BOOL)verifySignatureOfApplication:(NSURL*)app error:(NSError**)error;
@end

typedef NS_ENUM(NSInteger, AIInstallPhase) {
    AIInstallPhaseLooking,          //which version is the latest
    AIInstallPhaseDownloading,
    AIInstallPhaseVerifying,        //size, hash, signature, notarization
    AIInstallPhaseInstalling
};

@interface AIOllamaInstaller : NSObject

/// The latest release of Ollama from GitHub, installed in ~/Applications, checked with AIOllamaVerifier standard.
+(AIOllamaInstaller*)standardInstaller;
+(NSURL*)defaultInstallDirectory;
/// "Ollama.app"
+(NSString*)applicationName;

/// `releaseURL`: the page of GitHub's API that describes the latest release (https; this Mac only for tests). `fallbackURL`: the
/// file itself, used when the description cannot be read (GitHub limits how many times it is asked), nil for none. The
/// application is installed as `installDirectory`/Ollama.app, and the work is done in a private folder created in
/// `workDirectory` (on the same volume, so that the last step is a move, not a copy).
-(instancetype)initWithReleaseURL:(NSURL*)releaseURL fallbackURL:(NSURL*)fallbackURL installDirectory:(NSURL*)installDirectory
                    workDirectory:(NSURL*)workDirectory verifier:(AIOllamaVerifier*)verifier;

/// Does everything. `progress` is called on the main thread: the phase, how far (0 to 1, -1 when not measurable), and for the
/// download the bytes so far and in all. `completion` once, on the main thread: the installed application, or the error.
-(void)installWithProgress:(void (^)(AIInstallPhase phase, double fraction, uint64_t done, uint64_t total))progress
                completion:(void (^)(NSURL* application, NSError* error))completion;

/// Stops, and removes what was downloaded. The completion is called with VOKAILocalErrorCancelled.
-(void)cancel;

/// Removes the working folders that an interrupted run left behind (the program was quit during a download).
+(void)removeLeftoversInWorkDirectory:(NSURL*)workDirectory;

@end
