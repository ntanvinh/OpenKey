//
//  AIPresets.h
//  VOpenKey
//
//  The ready-made conversions of the AI window: one click turns the text in the box (what was selected, or what was typed) into a
//  corrected, politer, shorter, translated or rhymed version of itself. They are the writing modes of the assistant of VAlo
//  (packages/core/src/ai/writing.ts) written for this window, which is not tied to one chat application.
//
//  A preset is an instruction. The window sends it in front of the text, so it works with every AI the window can use (an address with
//  a key, a model on this Mac, a program like Codex), and the answer replaces the selection like any other answer.
//

#import <Foundation/Foundation.h>

@interface AIPreset : NSObject
/// Short and stable (a test and the accessibility description use it): @"fix", @"polite", @"lucBat"...
@property (nonatomic, readonly) NSString* identifier;
/// What the button says.
@property (nonatomic, readonly) NSString* title;
/// One line for the tooltip: what the AI will do with the text.
@property (nonatomic, readonly) NSString* summary;
/// What the AI is told to do with the text.
@property (nonatomic, readonly) NSString* instruction;
/// A poem: the AI is asked to keep to the rules of the form, but the answer is not checked for the number of syllables and the rhymes
/// (VAlo does check, and asks again). The window says so under the answer.
@property (nonatomic, readonly) BOOL isPoem;
@end

@interface AIPresets : NSObject

/// In the order the buttons are shown: corrections and tones, then poems, then length and translation.
+(NSArray<AIPreset*>*)all;
+(AIPreset*)presetWithIdentifier:(NSString*)identifier;

/// What is sent to the AI: the instruction, what to return and how, and the text to work on. The text comes after a line that says it is
/// the text to work on and not a request, which keeps most models from obeying a sentence of the text; it is no guarantee.
+(NSString*)promptForPreset:(AIPreset*)preset draft:(NSString*)draft;

@end
