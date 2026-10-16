//
//  Diagnostics.h
//  VOpenKey
//
//  A log for finding out why typing stops working: "typing a tone deletes the whole word", "the chosen suggestion does not appear".
//  That happened after hours of running, in every application, and went away when the app was restarted, so there is nothing to
//  catch afterwards without a record made on the way.
//
//  The log never holds what was typed. It holds counts, flags, identifiers of applications and input sources and timings, which is
//  what tells the causes apart:
//    - the event tap switched off by macOS, or the main thread blocked (typing is converted on that thread)
//    - macOS' own Vietnamese input source selected while VOpenKey converts as well
//    - the engine asking to delete characters without typing any back
//    - a suggestion that was chosen but refused
//    - modifier flags that stuck to the events the app makes (they turn typed text into shortcuts)
//    - key events the app posted that never reached the end of the event chain
//
//  The switch: defaults key DiagnosticsLog (bool).
//      Debug builds (scripts/dev.sh)   on by default
//      Release builds (the releases)   off by default
//      to turn it on or off yourself:  defaults write vn.io.lssoft.vopenkey DiagnosticsLog -bool YES   (or NO), then restart
//  The file: ~/Library/Logs/VOpenKey/diagnostics.log (the one before it is diagnostics.1.log), at most about 2 MB in all.
//  What to look for after an incident:  grep -E "ANOMALY|TAP|STALL" ~/Library/Logs/VOpenKey/diagnostics.log
//

#ifndef Diagnostics_h
#define Diagnostics_h

#import <Foundation/Foundation.h>

//1 while the log is on. The macro reads it first, so a switched off log costs a load and a branch, not the formatting.
extern int vDiagnostics;

#define VOKDiag(category, ...) \
    do { if (vDiagnostics) [VOKDiagnostics log:(category) message:[NSString stringWithFormat:__VA_ARGS__]]; } while (0)

//The synthetic key events the app posts, by what they are for
typedef NS_ENUM(NSInteger, VOKEventKind) {
    VOKEventKindBackspace = 0,
    VOKEventKindEmptyChar,      //the invisible character sent before a replacement
    VOKEventKindText,           //key 0 with a text: what the user reads
    VOKEventKindCount
};

#define VOKDiagPosted(eventKind, eventCount) \
    do { if (vDiagnostics) [VOKDiagnostics countPosted:(eventKind) pairs:(eventCount)]; } while (0)

@interface VOKDiagnostics : NSObject

//Reads the switch; when on, opens the file and starts the watchdog. Main thread, once, before the event tap is made.
+(void)start;
+(void)stop;
+(BOOL)isOn;

+(void)log:(NSString*)category message:(NSString*)message;

//What the watchdog asks of the event tap: 1 enabled, 0 switched off, -1 not made yet. Called on a background queue.
+(void)setTapEnabledCheck:(NSInteger (^)(void))check;
//Called on the main thread every minute: the state of the typing engine in one line. May log anomalies itself.
+(void)setSnapshotProvider:(NSString* (^)(void))provider;
//Counts the key events of this event source state id that reach the end of the event chain, to compare with what was posted
+(void)watchDeliveryFromSource:(int64_t)sourceStateID;
//Only names the source (what watchDeliveryFromSource: does before it starts listening); for the tests, which feed countArrived: themselves
+(void)setWatchedSource:(int64_t)sourceStateID;
+(void)countPosted:(VOKEventKind)kind pairs:(NSUInteger)pairs;
//An event of the typing source was seen at the end of the chain (called by the listener, public for the tests)
+(void)countArrived:(VOKEventKind)kind down:(BOOL)down;

//The input source macOS has selected, "com.apple.keylayout.ABC" for example. Main thread.
+(NSString*)currentInputSourceID;
+(NSString*)logDirectory;

//For the tests: everything configurable, and a way to wait for the writer
+(void)startWithDirectory:(NSString*)directory
                  enabled:(BOOL)enabled
             maxFileBytes:(NSUInteger)maxBytes
         watchdogInterval:(NSTimeInterval)interval
           stallThreshold:(NSTimeInterval)stall;
+(void)flush;
//Forgets what was counted as posted and arrived so far
+(void)resetDeliveryCounters;

@end

#endif /* Diagnostics_h */
