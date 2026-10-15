//
//  AILocalSetup.h
//  VOpenKey
//
//  Does what the user asked for with one click on "Cài đặt": from a Mac that has nothing to a Mac where the AI assistant answers
//  with a model that runs on it. In order:
//    1. Ollama, the program that runs models: downloaded and checked (AIOllamaInstaller), unless it is already there;
//    2. its server is started (AIOllamaRuntime), unless one already runs;
//    3. the model is downloaded (AIOllama), unless it is already there; a download that was interrupted continues where it was;
//    4. a short question is asked to the model, to know that it really answers, and how fast;
//    5. the AI assistant is set to use it.
//  Each step says what it is doing, how far it is, and what failed if it did. The window (AILocalSetupController) only shows this.
//

#import <Foundation/Foundation.h>
#import "AILocalModels.h"
#import "AIOllama.h"
#import "AIOllamaInstaller.h"
#import "AIOllamaRuntime.h"

typedef NS_ENUM(NSInteger, AILocalStep) {
    AILocalStepRuntime,         //Ollama itself
    AILocalStepStart,           //its server
    AILocalStepModel,           //the model
    AILocalStepTest,            //a question to it
    AILocalStepApply,           //the settings of the assistant
    AILocalStepCount
};

typedef NS_ENUM(NSInteger, AILocalStepState) {
    AILocalStepPending,
    AILocalStepRunning,
    AILocalStepDone,
    AILocalStepSkipped,         //nothing to do: already there
    AILocalStepFailed
};

/// Posted (on the main thread) when a model has been installed and the assistant set to use it.
extern NSString* const VOKAILocalSetupDidFinishNotification;

@interface AILocalSetup : NSObject

/// With the installer and the runtime of the application.
+(AILocalSetup*)standardSetup;
-(instancetype)initWithInstaller:(AIOllamaInstaller*)installer runtime:(AIOllamaRuntime*)runtime;

/// Called on the main thread after each change.
@property (nonatomic, copy) void (^onChange)(void);

@property (nonatomic, readonly) AILocalModel* model;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) BOOL succeeded;
/// What stopped it, in words to show. nil when it did not fail.
@property (nonatomic, readonly) NSError* error;
@property (nonatomic, readonly) BOOL wasCancelled;
@property (nonatomic, readonly) AILocalStep failedStep;

+(NSString*)titleOfStep:(AILocalStep)step;
-(AILocalStepState)stateOfStep:(AILocalStep)step;
/// 0 to 1, or -1 when it cannot be measured.
-(double)fractionOfStep:(AILocalStep)step;
/// What the step is doing now or did: "Đã tải 1,2 GB / 4,7 GB · 11 MB/giây · còn khoảng 5 phút".
-(NSString*)detailOfStep:(AILocalStep)step;

/// Runs all the steps for a model. Does nothing while it already runs.
-(void)installModel:(AILocalModel*)model;
/// Stops. What was downloaded of a model is kept, and continues next time.
-(void)cancel;

/// Takes a model out of the Mac (its files, often several GB). The server is started if it is not running.
-(void)removeModel:(AILocalModel*)model completion:(void (^)(NSError* error))completion;

#pragma mark What is on the Mac

/// The models in the folder of Ollama (~/.ollama/models), as "gemma3:4b", read from the disk: the server does not have to run.
+(NSSet<NSString*>*)installedTagsInModelsDirectory:(NSURL*)directory;
+(NSURL*)defaultModelsDirectory;

#pragma mark For tests and for the window

/// What puts the settings of the assistant on the model. The default writes them (AISettings): service Ollama, address, model.
@property (nonatomic, copy) void (^applyHandler)(AILocalModel* model, NSURL* baseURL);
/// What asks the model a short question. `done` is called with nil and a text such as "khoảng 31 token/giây", or with an error.
@property (nonatomic, copy) void (^testHandler)(AILocalModel* model, NSURL* baseURL, void (^done)(NSError* error, NSString* summary));
@property (nonatomic, readonly) AIOllamaRuntime* runtime;

@end
