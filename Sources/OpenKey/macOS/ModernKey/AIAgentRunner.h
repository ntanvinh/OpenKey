//
//  AIAgentRunner.h
//  VOpenKey
//
//  Asks an AI agent program (see AIAgentCLI) for text, the way AIClient asks a service: one runner makes one request, the pieces
//  of the answer come as the program prints them. Each request is a run of its own, in an empty private folder that is removed
//  afterwards, so nothing of the user's is around for the agent to read or change.
//

#import <Foundation/Foundation.h>
#import "AISettings.h"
#import "AIAgentCLI.h"

@interface AIAgentRunner : NSObject

-(instancetype)initWithConfiguration:(AIConfiguration*)configuration;

/// Runs the program. `onText` gets each piece of the answer, `completion` is called once at the end with nil or the error. Both are
/// called on the main thread, and not at all after -cancel.
-(void)generateWithPrompt:(NSString*)prompt
                   onText:(void (^)(NSString* piece))onText
               completion:(void (^)(NSError* error))completion;

/// Stops the program, and what it started. Whatever came is kept by the caller, nothing more is delivered.
-(void)cancel;

/// The longest a request may take, in seconds. A program that thinks for long on the highest levels needs minutes; 0 is the
/// default of 10 minutes.
@property (nonatomic) NSTimeInterval timeout;
/// Where the private folder of the request is made, the temporary folder of the user when nil. For tests.
@property (nonatomic, copy) NSString* workRoot;
@end
