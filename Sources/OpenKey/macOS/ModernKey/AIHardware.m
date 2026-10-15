//
//  AIHardware.m
//  VOpenKey
//

#import "AIHardware.h"
#import <IOKit/ps/IOPowerSources.h>
#import <mach/mach.h>
#import <sys/sysctl.h>

static NSString* SysctlString(const char* name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0)
        return @"";
    NSMutableData* data = [NSMutableData dataWithLength:size];
    if (sysctlbyname(name, data.mutableBytes, &size, NULL, 0) != 0)
        return @"";
    return [[NSString alloc] initWithBytes:data.bytes length:strnlen(data.bytes, size) encoding:NSUTF8StringEncoding] ?: @"";
}

static uint64_t SysctlNumber(const char* name) {
    uint64_t value = 0;
    size_t size = sizeof(value);
    if (sysctlbyname(name, &value, &size, NULL, 0) != 0)
        return 0;
    return size == sizeof(uint32_t) ? (uint32_t)value : value;      //some answer with 32 bits
}

@implementation AIHardware

+(AIHardware*)current {
    return [self currentForDirectory:nil];
}

+(AIHardware*)currentForDirectory:(NSURL*)directory {
    AIHardware* hardware = [[AIHardware alloc] init];
    hardware.chipName = SysctlString("machdep.cpu.brand_string");
    hardware.isAppleSilicon = SysctlNumber("hw.optional.arm64") == 1;
    hardware.memoryBytes = SysctlNumber("hw.memsize");
    hardware.cpuCores = (NSInteger)(hardware.isAppleSilicon ? SysctlNumber("hw.perflevel0.logicalcpu") : SysctlNumber("hw.physicalcpu"));
    if (hardware.cpuCores == 0)
        hardware.cpuCores = (NSInteger)SysctlNumber("hw.ncpu");

    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    hardware.osMajor = os.majorVersion;
    hardware.osMinor = os.minorVersion;
    hardware.lowPowerMode = [[NSProcessInfo processInfo] isLowPowerModeEnabled];
    hardware.thermalState = [[NSProcessInfo processInfo] thermalState];

    NSURL* target = directory ?: [NSURL fileURLWithPath:NSHomeDirectory()];
    while (target.path.length > 1 && ![[NSFileManager defaultManager] fileExistsAtPath:target.path])
        target = [target URLByDeletingLastPathComponent];           //the folder of the models may not exist yet
    NSNumber* free = [[target resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil]
                      objectForKey:NSURLVolumeAvailableCapacityForImportantUsageKey];
    hardware.freeDiskBytes = free.unsignedLongLongValue;

    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info != NULL) {
        CFStringRef source = IOPSGetProvidingPowerSourceType(info);       //"Battery Power", "AC Power" or "UPS Power"
        hardware.onBattery = source != NULL && CFStringCompare(source, CFSTR("Battery Power"), 0) == kCFCompareEqualTo;
        CFRelease(info);
    }

    //kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical
    uint64_t level = SysctlNumber("kern.memorystatus_vm_pressure_level");
    hardware.memoryPressure = level >= 4 ? AIMemoryPressureCritical : (level == 2 ? AIMemoryPressureWarning : AIMemoryPressureNormal);

    double load[1] = {0};
    if (getloadavg(load, 1) == 1 && hardware.cpuCores > 0) {
        NSInteger logical = (NSInteger)SysctlNumber("hw.logicalcpu");
        hardware.cpuLoadRatio = load[0] / (double)(logical > 0 ? logical : hardware.cpuCores);
    }

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0;
    if (host_page_size(mach_host_self(), &page) == KERN_SUCCESS &&
        host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        hardware.availableMemoryBytes = ((uint64_t)vm.free_count + vm.inactive_count + vm.purgeable_count) * page;
    }
    return hardware;
}

+(AIHardware*)appleSiliconWithMemoryGiB:(double)gib freeDiskGiB:(double)freeGiB {
    AIHardware* hardware = [[AIHardware alloc] init];
    hardware.chipName = @"Apple M-test";
    hardware.isAppleSilicon = YES;
    hardware.memoryBytes = (uint64_t)(gib * 1073741824.0);
    hardware.availableMemoryBytes = hardware.memoryBytes / 2;
    hardware.freeDiskBytes = (uint64_t)(freeGiB * 1073741824.0);
    hardware.osMajor = 15;
    hardware.osMinor = 0;
    hardware.cpuCores = 8;
    return hardware;
}

-(BOOL)isBusy {
    return self.cpuLoadRatio >= 0.7 || self.memoryPressure != AIMemoryPressureNormal;
}

-(NSString*)loadDescription {
    if (self.cpuLoadRatio >= 1.0 || self.memoryPressure == AIMemoryPressureCritical)
        return @"đang bận";
    if ([self isBusy] || self.cpuLoadRatio >= 0.4)
        return @"hơi bận";
    return @"đang rảnh";
}

-(NSString*)summary {
    NSMutableArray* parts = [NSMutableArray array];
    [parts addObject:self.chipName.length > 0 ? self.chipName : (self.isAppleSilicon ? @"Apple Silicon" : @"Intel")];
    [parts addObject:[NSString stringWithFormat:@"%.0f GB RAM", round(self.memoryBytes / 1073741824.0)]];
    [parts addObject:[NSString stringWithFormat:@"macOS %ld.%ld", (long)self.osMajor, (long)self.osMinor]];
    [parts addObject:[NSString stringWithFormat:@"%@ trống", VOKAIFormatBytes(self.freeDiskBytes)]];
    return [parts componentsJoinedByString:@" · "];
}

@end

NSString* VOKAIFormatBytes(uint64_t bytes) {
    NSString* text;
    if (bytes >= 999500000ULL) {                  //999.6 MB would be written "1000 MB"
        double gb = bytes / 1e9;
        text = [NSString stringWithFormat:gb >= 100 ? @"%.0f GB" : @"%.1f GB", gb];
    } else {
        text = [NSString stringWithFormat:@"%.0f MB", bytes / 1e6];
    }
    return [text stringByReplacingOccurrencesOfString:@"." withString:@","];       //4,7 GB
}
