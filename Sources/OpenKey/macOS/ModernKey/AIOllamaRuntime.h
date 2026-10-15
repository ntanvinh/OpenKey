//
//  AIOllamaRuntime.h
//  VOpenKey
//
//  Finds Ollama on this Mac and makes sure its server runs when the AI assistant needs it.
//
//  Ollama is two things: an application with a window and a menu bar icon, and, inside it, the server that actually runs the
//  models. VOpenKey runs only the server, as its own child process, listening on this Mac alone (127.0.0.1). So there is no
//  second icon in the menu bar, no updater, and when VOpenKey quits the server quits with it. If an Ollama is already running
//  (the user's own), it is used as it is and never stopped.
//
//  The server needs 20 to 40 seconds to answer the first time (it looks for the GPU: 20 and 35 seconds were measured).
//

#import <Foundation/Foundation.h>

@interface AIOllamaRuntime : NSObject

/// The one the application uses: the standard address and the usual places.
+(AIOllamaRuntime*)shared;
/// Replaces the one the application uses (a test), nil puts the standard one back.
+(void)setShared:(AIOllamaRuntime*)runtime;
/// ~/Applications/Ollama.app (where VOpenKey installs it), /Applications/Ollama.app, and the command line tools of Homebrew.
+(NSArray<NSString*>*)defaultSearchPaths;

-(instancetype)initWithBaseURL:(NSURL*)baseURL searchPaths:(NSArray<NSString*>*)searchPaths;

@property (nonatomic, readonly) NSURL* baseURL;
/// The server program found, nil when Ollama is not on this Mac. Looked for again at every call.
@property (nonatomic, readonly) NSURL* serverProgram;
@property (nonatomic, readonly) BOOL isInstalled;
/// VOpenKey started the server and it is still running.
@property (nonatomic, readonly) BOOL isManaged;
/// How long to wait for the server to answer after starting it. 90 seconds; a test shortens it.
@property (nonatomic) NSTimeInterval startTimeout;
/// What the server wrote last (the end of it), to say why it did not start.
@property (nonatomic, readonly, copy) NSString* lastOutput;

/// Makes sure an Ollama answers at the address: the one that runs, or the server started now. `completion` is called on the main
/// thread, once, with nil or the reason (Ollama is not installed, the address is taken by something else, the server stopped or
/// did not answer). Calls made while the server is starting wait for the same start.
-(void)ensureRunning:(void (^)(NSError* error))completion;

/// Stops the server if VOpenKey started it. Waits up to `seconds` for it to end, then forces it. Does nothing to an Ollama that
/// VOpenKey did not start.
-(void)stopWaiting:(NSTimeInterval)seconds;

@end
