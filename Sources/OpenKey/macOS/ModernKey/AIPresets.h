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
//  The presets are in groups, one tab of the window each: the tone of a text, the occasion or the person it is for (a congratulation, a
//  message to the boss, to a colleague, to a friend...), poems, and length and translation. The ones for an occasion take a few ideas or a
//  draft and write the whole message, choosing the tone that suits the occasion and the person.
//
//  The same file also has the ready-made sizes of the pictures (a post of Instagram, a thumbnail of YouTube, an icon, a greeting card...).
//  A size is not an instruction to the AI alone: the AI is told the canvas it works on, and the picture that comes back is cut to exactly
//  that many pixels (AI models draw at a few sizes of their own and do not keep to a size that is asked for).
//

#import <Foundation/Foundation.h>

@interface AIPreset : NSObject
/// Short and stable (a test and the accessibility description use it): @"fix", @"polite", @"lucBat"...
@property (nonatomic, readonly) NSString* identifier;
/// The identifier of the group (tab) it is in: @"tone", @"occasion", @"poem", @"length".
@property (nonatomic, readonly) NSString* group;
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

/// A group of the presets, or of the sizes of the pictures: what a tab of the window, or a section of the menu of sizes, is called.
@interface AIPresetGroup : NSObject
@property (nonatomic, readonly) NSString* identifier;
@property (nonatomic, readonly) NSString* title;
@end

/// A ready-made size of a picture: where it is used and how many pixels it has.
@interface AIImageSize : NSObject
/// @"instagramSquare", @"youtubeThumbnail", @"appIcon"...
@property (nonatomic, readonly) NSString* identifier;
/// The identifier of the group: @"social", @"icon", @"card".
@property (nonatomic, readonly) NSString* group;
/// Where it is used, short: "Instagram · Vuông".
@property (nonatomic, readonly) NSString* title;
/// One line for the tooltip.
@property (nonatomic, readonly) NSString* summary;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
/// The proportions as people say them: "1:1", "4:5", "1.91:1".
@property (nonatomic, readonly) NSString* ratio;
/// What the picture is for, told to the AI (in English, like the rest of the request for a picture).
@property (nonatomic, readonly) NSString* hint;
/// The title with the pixels: "Instagram · Vuông (1080×1080)". This is what the menu of the sizes shows.
@property (nonatomic, readonly) NSString* label;
@end

@interface AIPresets : NSObject

/// The groups of the presets, in the order of the tabs.
+(NSArray<AIPresetGroup*>*)groups;
/// In the order the buttons are shown: by group (tones, occasions, poems, length and translation), and inside a group as they were written.
+(NSArray<AIPreset*>*)all;
+(NSArray<AIPreset*>*)presetsInGroup:(NSString*)groupIdentifier;
+(AIPreset*)presetWithIdentifier:(NSString*)identifier;

/// What is sent to the AI: the instruction, what to return and how, and the text to work on. The text comes after a line that says it is
/// the text to work on and not a request, which keeps most models from obeying a sentence of the text; it is no guarantee.
+(NSString*)promptForPreset:(AIPreset*)preset draft:(NSString*)draft;

#pragma mark Sizes of pictures

/// The groups of the sizes (social networks, icons and logos, cards and prints), in the order of the menu.
+(NSArray<AIPresetGroup*>*)imageGroups;
+(NSArray<AIImageSize*>*)allImageSizes;
+(AIImageSize*)imageSizeWithIdentifier:(NSString*)identifier;

/// The words that tell the AI the canvas, with {width}, {height}, {ratio} and {hint} in them (the Windows program has them in its data file).
+(NSString*)imageNoteTemplate;

/// What is put in the request for a picture in place of the description alone: the description, then the canvas (pixels and proportions),
/// the order to keep what matters away from the edges (the picture is cut to the proportions), and what the picture is for.
+(NSString*)imageRequestForSize:(AIImageSize*)size description:(NSString*)description;

/// The part of a picture of `source` pixels that has the proportions of `target` and is centred: what is kept when the picture is cut to
/// a size. The numbers are whole pixels of the source; as large as can be.
+(NSRect)coverCropOfSourceSize:(NSSize)source forTargetSize:(NSSize)target;

/// The picture (any format the system reads) cut to the proportions of `size` and scaled to exactly its pixels, as a PNG. A picture that has
/// the size already is returned as it is. nil when the data is not a picture.
+(NSData*)pngByFittingImageData:(NSData*)data toSize:(AIImageSize*)size;

@end
