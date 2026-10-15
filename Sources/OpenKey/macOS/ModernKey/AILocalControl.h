//
//  AILocalControl.h
//  VOpenKey
//
//  What the settings show and do about the AI that runs on this Mac once there is one (Ollama installed, or a server running):
//  whether it runs, who started it, what it holds in memory, how busy the Mac is, and the three things the user can do: start it,
//  stop it, take the models out of memory.
//
//  A model that runs is heavy: it takes the processor and a lot of memory. It suits a Mac that has little else to do, which is why
//  the state of the Mac is said next to the buttons, and why stopping is one click away.
//

#import <Foundation/Foundation.h>
#import "AIHardware.h"
#import "AIOllamaRuntime.h"

@interface AILocalControl : NSObject

+(AILocalControl*)shared;
-(instancetype)initWithRuntime:(AIOllamaRuntime*)runtime;

/// Called on the main thread when something changed (the status was read, an action began or ended).
@property (nonatomic, copy) void (^onChange)(void);

/// There is an AI on this Mac: the buttons are worth showing. False when Ollama is neither installed nor running.
@property (nonatomic, readonly) BOOL detected;
/// An action is in progress: the buttons wait.
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL canStart;
@property (nonatomic, readonly) BOOL canStop;
@property (nonatomic, readonly) BOOL canUnload;

/// Two lines of words: what the AI is doing, and the state of the Mac.
@property (nonatomic, readonly, copy) NSString* statusText;
@property (nonatomic, readonly, copy) NSString* loadText;
/// The same two in a few words, for the line the user reads; statusText and loadText are what the tooltip says.
@property (nonatomic, readonly, copy) NSString* briefStatusText;
@property (nonatomic, readonly, copy) NSString* briefLoadText;
/// The Mac is busy: shown in a warm colour.
@property (nonatomic, readonly) BOOL macIsBusy;
/// The last action failed: what to tell. nil otherwise.
@property (nonatomic, readonly, copy) NSString* problemText;

/// Reads the state again (the settings call it when they open and every few seconds while they are shown).
-(void)refresh;
-(void)start;
-(void)stop;
-(void)unload;

/// How the Mac is described now (a test gives its own).
@property (nonatomic, copy) AIHardware* (^hardwareProvider)(void);

@end
