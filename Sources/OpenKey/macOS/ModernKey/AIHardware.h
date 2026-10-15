//
//  AIHardware.h
//  VOpenKey
//
//  What this Mac can do, as far as running an AI model on it is concerned: the memory, the kind of processor, how much room
//  is left on the disk, the version of macOS, and a few things about the moment (on battery, memory in use, too hot).
//  AIModelAdvisor turns it into advice. The values are plain properties so that tests can describe any Mac.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AIMemoryPressure) {
    AIMemoryPressureNormal,
    AIMemoryPressureWarning,
    AIMemoryPressureCritical
};

@interface AIHardware : NSObject

/// "Apple M1 Max", "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"
@property (nonatomic, copy) NSString* chipName;
/// Apple Silicon: the model runs on the GPU, which shares the memory of the Mac. Intel: only the processor, much slower.
@property (nonatomic) BOOL isAppleSilicon;
/// Installed RAM.
@property (nonatomic) uint64_t memoryBytes;
/// What is free or can be taken back at once (free, inactive, purgeable) at this moment. 0 when unknown.
@property (nonatomic) uint64_t availableMemoryBytes;
/// Free on the disk where the models are kept, counting what macOS can free by itself.
@property (nonatomic) uint64_t freeDiskBytes;
@property (nonatomic) NSInteger osMajor;
@property (nonatomic) NSInteger osMinor;
/// Number of cores that do the work, performance cores first.
@property (nonatomic) NSInteger cpuCores;
@property (nonatomic) BOOL onBattery;
@property (nonatomic) BOOL lowPowerMode;
/// 0 nominal, 1 fair, 2 serious, 3 critical (NSProcessInfoThermalState).
@property (nonatomic) NSInteger thermalState;
@property (nonatomic) AIMemoryPressure memoryPressure;

/// This Mac, now. `directory` is on the volume that will hold the models (nil: the home folder).
+(AIHardware*)currentForDirectory:(NSURL*)directory;
+(AIHardware*)current;

/// A Mac described by the caller, for tests: Apple Silicon, macOS 15, plugged in, nothing unusual.
+(AIHardware*)appleSiliconWithMemoryGiB:(double)gib freeDiskGiB:(double)freeGiB;

/// "Apple M1 Max · 32 GB RAM · macOS 15.7 · 283 GB trống"
-(NSString*)summary;

@end

/// A size in the units people know, with the decimal point of the Vietnamese ("4,7 GB", "806 MB").
NSString* VOKAIFormatBytes(uint64_t bytes);
