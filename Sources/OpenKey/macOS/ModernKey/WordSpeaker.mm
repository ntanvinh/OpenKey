//
//  WordSpeaker.mm
//  VOpenKey
//

#import "WordSpeaker.h"
#import <AVFoundation/AVFoundation.h>
#include <string>
#include <vector>
#include "WordSpeech.h"

//a little slower than the default so that a learner hears each sound
static const float kRateFactor = 0.9f;

@implementation WordSpeaker {
    AVSpeechSynthesizer* _synthesizer;
}

+(WordSpeaker*)shared {
    static WordSpeaker* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[WordSpeaker alloc] init]; });
    return instance;
}

+(NSString*)textToSpeakForHeadword:(NSString*)headword sourceLangs:(NSArray<NSString*>*)sourceLangs {
    std::vector<std::string> langs;
    for (NSString* lang in sourceLangs)
        langs.push_back(lang.UTF8String ?: "");
    std::string text = vspeech::TextToSpeak(headword.UTF8String ?: "", langs);
    return text.empty() ? nil : [NSString stringWithUTF8String:text.c_str()];
}

//en-US first (the pronunciation most dictionaries print), then the other English ones; among those, the best quality
+(AVSpeechSynthesisVoice*)bestEnglishVoice {
    AVSpeechSynthesisVoice* best = nil;
    NSInteger bestScore = -1;
    for (AVSpeechSynthesisVoice* voice in [AVSpeechSynthesisVoice speechVoices]) {
        NSString* language = voice.language ?: @"";
        if (![language.lowercaseString hasPrefix:@"en"])
            continue;
        NSInteger score = (NSInteger)voice.quality * 10 + ([language isEqualToString:@"en-US"] ? 5 : 0);
        if (score > bestScore) {
            best = voice;
            bestScore = score;
        }
    }
    return best;
}

-(NSString*)voiceLanguage {
    return [WordSpeaker bestEnglishVoice].language;
}

-(BOOL)speaking {
    return _synthesizer != nil && _synthesizer.speaking;
}

-(BOOL)speak:(NSString*)text {
    if (text.length == 0)
        return NO;
    AVSpeechSynthesisVoice* voice = [WordSpeaker bestEnglishVoice];
    if (self.speakHook != nil) {
        self.speakHook(text, voice.language ?: @"en-US");
        return YES;
    }
    if (voice == nil)
        return NO;
    if (_synthesizer == nil)
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
    [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance* utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = voice;
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * kRateFactor;
    [_synthesizer speakUtterance:utterance];
    return YES;
}

-(void)stop {
    if (_synthesizer != nil)
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

@end
