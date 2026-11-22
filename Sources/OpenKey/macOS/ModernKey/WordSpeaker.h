//
//  WordSpeaker.h
//  VOpenKey
//
//  Reads an English word aloud with a voice of the system (AVSpeechSynthesizer): no network, no key, no cost. The rules for what is
//  an English word to read are in engine/WordSpeech.h, the same on Windows.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WordSpeaker : NSObject

+(WordSpeaker*)shared;

/// What to read for a headword found in dictionaries whose source languages are `sourceLangs` ("en", "vi", "" when not given);
/// nil when it is not an English word (a Vietnamese headword, a number, an accented word).
+(nullable NSString*)textToSpeakForHeadword:(NSString*)headword sourceLangs:(NSArray<NSString*>*)sourceLangs;

/// Reads `text` in English, after stopping what is being read. NO when the Mac has no English voice (nothing is read then).
-(BOOL)speak:(NSString*)text;
-(void)stop;

@property (nonatomic, readonly) BOOL speaking;

/// The voice that is used (en-US first, then any other English one, the best quality first), nil when there is none.
@property (nonatomic, readonly, nullable) NSString* voiceLanguage;

/// Tests: called with the text and the language of the voice instead of making any sound.
@property (nonatomic, copy, nullable) void (^speakHook)(NSString* text, NSString* language);

@end

NS_ASSUME_NONNULL_END
