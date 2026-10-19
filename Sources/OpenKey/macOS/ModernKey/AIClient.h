//
//  AIClient.h
//  VOpenKey
//
//  Asks an AI service for text and receives it as it is written. One AIClient makes one request.
//
//  Care taken with what is sent and received:
//  - the session keeps nothing: no cache, no cookies, no stored credentials, so neither the text nor the key lands on disk;
//  - a redirect is never followed, so the key is never sent to another server than the one the user chose;
//  - the key goes only in a header (never in the address, where it would show up in logs and proxies);
//  - the messages of errors have the key and anything that looks like one taken out (VOKAIRedact).
//

#import <Foundation/Foundation.h>
#import "AIProvider.h"
#import "AISettings.h"

/// Some models (DeepSeek R1, Qwen 3 on some servers...) write their reasoning first, between <think> and </think>, in the text of
/// the answer. It is not the answer: this removes it as the text arrives, even when a tag is cut in two pieces. Only a block
/// at the very start of the answer counts as reasoning, so an answer that talks about the tag keeps it.
@interface AIThinkFilter : NSObject
/// The part of `text` that belongs to the answer (may be empty: the text may still be a start of a tag).
-(NSString*)feed:(NSString*)text;
/// The answer ended: whatever was held back in case it was a tag. Nothing when the reasoning never ended.
-(NSString*)flush;
@end

/// Reads the stream of an answer as it arrives and says what text it carried. Public because it is the part most worth testing.
@interface AIStreamParser : NSObject

-(instancetype)initWithProtocol:(AIProtocol)protocol;

/// Gives bytes as they arrive, cut anywhere (a Vietnamese letter can be cut in two). Returns the pieces of text completed by
/// them. When the stream carries an error or a refusal, *error is set and nothing more is read.
-(NSArray<NSString*>*)feed:(NSData*)data error:(NSError**)error;

/// The stream ended: the text still held back (see AIThinkFilter). Call once, after the last bytes.
-(NSArray<NSString*>*)flush;

/// The service said it has finished.
@property (nonatomic, readonly) BOOL finished;

/// Text of an answer that was not streamed (a server that ignores "stream"), nil when it has none.
+(NSString*)textOfCompleteAnswer:(NSData*)data protocol:(AIProtocol)protocol error:(NSError**)error;

@end

@interface AIClient : NSObject

-(instancetype)initWithConfiguration:(AIConfiguration*)configuration;

/// Sends the request. `onText` gets each piece of the answer, `completion` is called once at the end with nil or the error.
/// Both are called on the main thread, and not at all after -cancel.
-(void)generateWithPrompt:(NSString*)prompt
                   onText:(void (^)(NSString* piece))onText
               completion:(void (^)(NSError* error))completion;

/// A picture, from a program that makes them (Codex): `onNote` gets what the program says meanwhile, `completion` the file of the picture
/// or the error. Main thread, and not at all after -cancel. Any other service gives an error.
-(void)generateImageWithPrompt:(NSString*)prompt
                        onNote:(void (^)(NSString* note))onNote
                    completion:(void (^)(NSURL* image, NSError* error))completion;

/// Stops the request. Whatever came is kept by the caller, nothing more is delivered.
-(void)cancel;

/// The names of the models the service offers, to choose from. Also tells whether the key and the address work. Calls
/// `completion` on the main thread.
+(void)listModelsForConfiguration:(AIConfiguration*)configuration
                       completion:(void (^)(NSArray<NSString*>* models, NSError* error))completion;

/// The request that would be sent, for tests.
+(NSURLRequest*)requestForConfiguration:(AIConfiguration*)configuration prompt:(NSString*)prompt error:(NSError**)error;

@end
