//
//  AIAgentProcess.h
//  VOpenKey
//
//  One run of a program: gives it its input, hands out what it prints as it prints it, and says how it ended. It is the part of
//  running an AI agent that has nothing to do with AI, so that it can be tested with any program.
//
//  Things it takes care of, because the programs it runs are agents that start other programs:
//  - a program that ended but left a child holding its output open (a server it started) does not make the run wait for ever:
//    shortly after the end, whatever is readable is read and the run is over;
//  - stopping it stops the children too, not only the program that was started;
//  - writing the input to a program that has already ended does not kill VOpenKey AI with SIGPIPE.
//

#import <Foundation/Foundation.h>

@interface AIAgentProcess : NSObject

/// Called with each piece of the standard output, on the queue of the process (not the main thread).
@property (nonatomic, copy) void (^onOutput)(NSData* data);
/// Called once when the program has ended and its output has been read, on the queue of the process. `status` is the exit code, or
/// the number of the signal that ended it when `signaled`. `errorOutput` is the end of what it printed on its standard error.
@property (nonatomic, copy) void (^onExit)(int status, BOOL signaled, NSString* errorOutput);

/// Starts the program. `input` is written to its standard input, which is then closed. NO with the reason in *error when it cannot be
/// started (does not exist, is not allowed...). When NO, neither block is called.
-(BOOL)launchExecutable:(NSString*)executable arguments:(NSArray<NSString*>*)arguments environment:(NSDictionary<NSString*, NSString*>*)environment
              directory:(NSString*)directory input:(NSData*)input error:(NSError**)error;

/// Stops the program and everything it started: asks first (SIGTERM), then, a little later, forces it (SIGKILL). `onExit` follows.
-(void)terminate;

@property (nonatomic, readonly) BOOL running;

/// For tests: how long after the end of the program the output is still waited for.
@property (nonatomic) NSTimeInterval drainTimeout;

/// Runs a program to its end and gives all it printed on the standard output (up to `limit` bytes) to `completion`, on the main
/// thread. The program is stopped after `timeout` seconds. `error` says why when the program could not be started, timed out, or
/// ended with an error (the output is then given too, when there is some).
+(void)captureOutputOfExecutable:(NSString*)executable arguments:(NSArray<NSString*>*)arguments environment:(NSDictionary<NSString*, NSString*>*)environment
                         timeout:(NSTimeInterval)timeout limit:(NSUInteger)limit
                      completion:(void (^)(NSData* output, NSString* errorOutput, NSError* error))completion;

@end
