//
//  AIModelAdvisor.h
//  VOpenKey
//
//  Looks at a Mac and a model and says, before anything is downloaded, whether the model will run well, what the Mac lacks if it
//  will not, and which model of the list suits it best.
//
//  How it judges (the numbers are in AIModelAdvisor.m, with the reasons):
//  - A model needs its own size in memory plus a working space (the conversation, the engine): the "footprint".
//  - On Apple Silicon the model runs on the GPU, and macOS lets the GPU use about two thirds of the RAM. The footprint is
//    "smooth" up to half of the RAM, which leaves the rest to macOS and the other applications, and "tight" up to two thirds.
//    Above that the model does not fit, or the Mac starts to use the disk as memory and everything becomes slow.
//  - On an Intel Mac there is no GPU for it: the processor does everything, the limits are lower and it is always slow.
//

#import <Foundation/Foundation.h>
#import "AIHardware.h"
#import "AILocalModels.h"

typedef NS_ENUM(NSInteger, AIModelFit) {
    AIModelFitSmooth,       //runs comfortably
    AIModelFitTight,        //runs, but it uses most of the memory: close other heavy applications
    AIModelFitTooBig        //does not fit in this Mac
};

@interface AIModelAssessment : NSObject
@property (nonatomic, strong) AILocalModel* model;
@property (nonatomic) AIModelFit fit;
/// The model and its working space, in memory.
@property (nonatomic) uint64_t memoryNeededBytes;
/// The smallest amount of RAM (GB, as sold: 8, 16, 24...) on which it is "tight", and the one on which it is "smooth".
@property (nonatomic) NSInteger minimumRAMGB;
@property (nonatomic) NSInteger comfortableRAMGB;
/// What has to be free on the disk to install, with a margin.
@property (nonatomic) uint64_t diskNeededBytes;
/// What prevents the installation. Empty when it can go on.
@property (nonatomic, copy) NSArray<NSString*>* blockers;
/// What the user should know before: not a reason to stop.
@property (nonatomic, copy) NSArray<NSString*>* warnings;
/// One line: "Chạy mượt trên máy này", "Chạy được nhưng sát giới hạn", "Quá nặng cho máy này".
@property (nonatomic, copy) NSString* headline;
@property (nonatomic, readonly) BOOL canInstall;
@end

@interface AIModelAdvisor : NSObject

/// `runtimeInstalled`: Ollama is already on the Mac (nothing to download for it, and macOS older than 14 is not a problem since
/// it is there). `modelDownloaded`: the model is already in its folder (no disk space needed).
+(AIModelAssessment*)assessModel:(AILocalModel*)model hardware:(AIHardware*)hardware
                runtimeInstalled:(BOOL)runtimeInstalled modelDownloaded:(BOOL)modelDownloaded;

/// The model to suggest: the best one that runs smoothly, the smallest one if none does. nil when the Mac cannot run any.
+(AILocalModel*)recommendedModelAmong:(NSArray<AILocalModel*>*)models hardware:(AIHardware*)hardware;

/// What the Mac can run and what to expect, before any model is chosen (the description of the Mac itself is AIHardware's summary).
+(NSString*)overviewForHardware:(AIHardware*)hardware models:(NSArray<AILocalModel*>*)models;

/// The minimum macOS and the disk space of the program that runs the models (Ollama), shown in the notes.
+(NSInteger)runtimeMinimumMajorOS;
+(uint64_t)runtimeDiskBytes;

@end
