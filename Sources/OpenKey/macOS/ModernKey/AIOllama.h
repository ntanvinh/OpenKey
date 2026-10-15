//
//  AIOllama.h
//  VOpenKey
//
//  Talks to Ollama, the program that runs AI models on this Mac: is it running, which models does it have, download one (with
//  its progress), delete one. The chat itself goes through AIClient, as with any other service that speaks the OpenAI way.
//
//  Only this Mac is ever addressed (127.0.0.1, localhost, ::1): the commands that download and delete models are never sent to
//  another machine. Nothing the user writes passes through here.
//

#import <Foundation/Foundation.h>

extern NSString* const VOKAILocalErrorDomain;

typedef NS_ENUM(NSInteger, VOKAILocalErrorCode) {
    VOKAILocalErrorNotRunning = 1,      //nothing answers at the address of Ollama
    VOKAILocalErrorNotFound,            //the model does not exist in the library
    VOKAILocalErrorFailed,              //Ollama (or the library) refused or failed: the message says why
    VOKAILocalErrorInterrupted,         //the download stopped before it was complete
    VOKAILocalErrorBadResponse,         //what came back is not what Ollama sends
    VOKAILocalErrorCancelled,
    VOKAILocalErrorUnsafeDownload,      //what was downloaded did not pass the checks (size, hash, signature)
    VOKAILocalErrorInstall,             //it could not be put in place
    VOKAILocalErrorUnsupported,         //this Mac cannot run it (macOS too old, no room)
    VOKAILocalErrorNotInstalled,        //Ollama is not on this Mac
    VOKAILocalErrorNetwork              //the connection to the library broke during a download (it can be tried again)
};

/// Where a download is. One per line of progress that Ollama sends.
@interface AIPullProgress : NSObject
/// What is being done, in words to show: "Đang tải model", "Đang kiểm tra file tải về", "Xong".
@property (nonatomic, copy) NSString* status;
/// Over all the files of the model.
@property (nonatomic) uint64_t completedBytes;
@property (nonatomic) uint64_t totalBytes;
/// 0 to 1, or -1 when there is nothing to measure (checking, writing).
@property (nonatomic) double fraction;
@property (nonatomic) BOOL finished;
@end

/// Reads the lines Ollama sends while it downloads a model (one JSON object per line, cut anywhere) and tells where the download
/// is. Several files are downloaded one after another and each reports its own size, so the progress is added up; when the size
/// of the whole is known in advance (the list of models has it) it is the total, which keeps the bar from jumping back when the
/// small files come after the big one.
@interface AIPullParser : NSObject
-(instancetype)initWithExpectedBytes:(uint64_t)expectedBytes;
/// Bytes as they arrive. Returns the progress reports they completed.
-(NSArray<AIPullProgress*>*)feed:(NSData*)data;
/// The last line was "success".
@property (nonatomic, readonly) BOOL succeeded;
/// Set when Ollama sent an error, or the lines are not what it sends. Nothing more is read after.
@property (nonatomic, readonly, copy) NSString* errorMessage;
/// The error is a broken connection (EOF, reset, time out, no host...): trying again is reasonable.
@property (nonatomic, readonly) BOOL errorIsNetwork;
@end

@interface AIOllamaTask : NSObject
-(void)cancel;
@end

@interface AIOllama : NSObject

/// http://127.0.0.1:11434, where Ollama listens unless told otherwise.
+(NSURL*)defaultBaseURL;

/// nil when the address is not this Mac.
-(instancetype)initWithBaseURL:(NSURL*)baseURL;
@property (nonatomic, readonly) NSURL* baseURL;

/// The version of Ollama that answers, or an error. Right after Ollama starts it does not answer for some seconds (it looks for
/// the GPU), hence the timeout. `completion` is called on the main thread.
-(void)versionWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSString* version, NSError* error))completion;

/// The models Ollama has: dictionaries with "name" and "size".
-(void)installedModelsWithCompletion:(void (^)(NSArray<NSDictionary*>* models, NSError* error))completion;
/// Whether a failed download is worth starting again at once: the connection broke (VOKAILocalErrorNetwork, VOKAILocalErrorInterrupted).
/// What was downloaded is kept by Ollama and the next try continues from it.
+(BOOL)errorIsRetryable:(NSError*)error;
/// The models that are loaded in memory now (they leave it on their own a while after the last use): dictionaries with "name" and "size"
/// (bytes of memory taken).
-(void)loadedModelsWithCompletion:(void (^)(NSArray<NSDictionary*>* models, NSError* error))completion;
/// Takes a model out of memory at once. The server keeps running; the files of the model stay on the disk.
-(void)unloadModel:(NSString*)tag completion:(void (^)(NSError* error))completion;

/// "gemma3" is "gemma3:latest".
+(BOOL)tag:(NSString*)tag isAmongInstalled:(NSArray<NSDictionary*>*)models;

/// Downloads a model. `expectedBytes` is the size of the whole when known (0 when not). `progress` is called at most ten times
/// a second, on the main thread, and a last time with `finished`; `completion` once, with nil when the model is complete.
/// Downloads that stopped can be started again: Ollama continues where it was.
-(AIOllamaTask*)pullModel:(NSString*)tag expectedBytes:(uint64_t)expectedBytes
                 progress:(void (^)(AIPullProgress* progress))progress completion:(void (^)(NSError* error))completion;

-(void)deleteModel:(NSString*)tag completion:(void (^)(NSError* error))completion;

/// The size of a model of the public library of Ollama, from its manifest: what the download will be. `registry` is
/// https://registry.ollama.ai unless a test says otherwise. A model that is not in the library gives VOKAILocalErrorNotFound;
/// one that lives elsewhere (hf.co/...) gives 0 and no error: its size is not known.
+(void)librarySizeOfTag:(NSString*)tag registry:(NSURL*)registry completion:(void (^)(uint64_t bytes, NSError* error))completion;
+(NSURL*)defaultRegistryURL;

@end
