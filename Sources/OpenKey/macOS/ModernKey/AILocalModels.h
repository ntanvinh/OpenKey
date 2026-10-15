//
//  AILocalModels.h
//  VOpenKey
//
//  The models offered to the user who wants an AI that runs on their Mac: a list that ships with the app
//  (engine/ai/local-models.json, rebuilt by scripts/update-local-models.py), each with the size of its download, and the
//  opinion of the authors on its quality. Models are the ones of Ollama, named like `gemma3:4b`.
//

#import <Foundation/Foundation.h>

@interface AILocalModel : NSObject

/// The name Ollama knows it by: "gemma3:4b". It is what is asked for when the model is downloaded.
@property (nonatomic, copy, readonly) NSString* tag;
/// "Gemma 3 4B"
@property (nonatomic, copy, readonly) NSString* name;
/// "Gemma 3 (Google)"
@property (nonatomic, copy, readonly) NSString* family;
/// "4B"
@property (nonatomic, copy, readonly) NSString* parameters;
/// One or two sentences about what it is good for, in Vietnamese.
@property (nonatomic, copy, readonly) NSString* summary;
/// The Vietnamese it writes: "Cơ bản", "Khá", "Tốt", "Rất tốt".
@property (nonatomic, copy, readonly) NSString* vietnamese;
/// What `ollama pull` downloads, in bytes.
@property (nonatomic, readonly) uint64_t bytes;
/// 1 to 5, compared with the others of the list.
@property (nonatomic, readonly) NSInteger quality;
@property (nonatomic, readonly) NSInteger speed;
/// A model that is not in the list: the user typed its name, and its size came from the registry (0 when unknown).
@property (nonatomic, readonly) BOOL isCustom;

-(instancetype)initWithTag:(NSString*)tag name:(NSString*)name family:(NSString*)family parameters:(NSString*)parameters
                   summary:(NSString*)summary vietnamese:(NSString*)vietnamese bytes:(uint64_t)bytes
                   quality:(NSInteger)quality speed:(NSInteger)speed custom:(BOOL)custom;

/// A model the user named by hand.
+(AILocalModel*)customModelWithTag:(NSString*)tag bytes:(uint64_t)bytes;

@end

@interface AILocalModels : NSObject

/// The list of the app, smallest first. Empty when the file is missing or damaged.
+(NSArray<AILocalModel*>*)catalog;

/// The list in a file given by the caller, for tests.
+(NSArray<AILocalModel*>*)catalogFromFile:(NSURL*)file;

/// Whether a name can be a model of Ollama: letters, digits, "._-/" and one ":" tag. Anything else (spaces, "..", a path that goes
/// up, shell characters) is refused before it is sent anywhere. Returns the name trimmed, nil when it is not acceptable.
+(NSString*)validTagFromText:(NSString*)text;

@end
