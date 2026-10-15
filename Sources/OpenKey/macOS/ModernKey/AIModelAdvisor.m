//
//  AIModelAdvisor.m
//  VOpenKey
//

#import "AIModelAdvisor.h"

static const double GiB = 1073741824.0;

/// The conversation (the longer it is, the more memory it takes) and the working buffers of the engine. Measured with the models
/// of the list: 1 to 2 GB over the size of the file.
static const double kWorkingSpaceGiB = 1.5;
/// Share of the RAM a footprint may take: Apple Silicon (the GPU can use about two thirds of the RAM: 21.3 of 32 GiB were
/// measured), then Intel (processor only, and macOS and the applications take their part).
static const double kSmoothShare = 0.50, kTightShare = 0.66;
static const double kSmoothShareIntel = 0.35, kTightShareIntel = 0.50;
/// The download of the program: 207 MB, and 641 MB once opened. Counted with some room.
static const uint64_t kRuntimeDiskBytes = 1000000000ULL;
/// Ollama requires macOS 14 (its Info.plist says LSMinimumSystemVersion 14.0).
static const NSInteger kRuntimeMinimumOS = 14;
/// What must stay free on the disk once everything is installed, so that macOS can still work.
static const uint64_t kDiskMargin = 3ULL * 1000000000ULL;
static const uint64_t kDiskComfort = 10ULL * 1000000000ULL;

/// The sizes of RAM Macs have been sold with.
static NSInteger RoundUpToSoldRAM(double gib) {
    static const NSInteger sizes[] = {4, 8, 16, 24, 32, 36, 48, 64, 96, 128, 192, 256, 512};
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
        if (gib <= sizes[i] + 0.0001)
            return sizes[i];
    return (NSInteger)ceil(gib);
}

@implementation AIModelAssessment
-(BOOL)canInstall {
    return self.blockers.count == 0;
}
@end

@implementation AIModelAdvisor

+(NSInteger)runtimeMinimumMajorOS { return kRuntimeMinimumOS; }
+(uint64_t)runtimeDiskBytes { return kRuntimeDiskBytes; }

+(uint64_t)memoryNeededForModel:(AILocalModel*)model {
    return model.bytes + (uint64_t)(kWorkingSpaceGiB * GiB);
}

+(AIModelFit)fitOfFootprint:(uint64_t)footprint hardware:(AIHardware*)hardware {
    double smooth = hardware.isAppleSilicon ? kSmoothShare : kSmoothShareIntel;
    double tight = hardware.isAppleSilicon ? kTightShare : kTightShareIntel;
    double ram = (double)hardware.memoryBytes;
    if (footprint <= ram * smooth)
        return AIModelFitSmooth;
    if (footprint <= ram * tight)
        return AIModelFitTight;
    return AIModelFitTooBig;
}

+(AIModelAssessment*)assessModel:(AILocalModel*)model hardware:(AIHardware*)hardware
                runtimeInstalled:(BOOL)runtimeInstalled modelDownloaded:(BOOL)modelDownloaded {
    AIModelAssessment* result = [[AIModelAssessment alloc] init];
    result.model = model;
    uint64_t footprint = [self memoryNeededForModel:model];
    result.memoryNeededBytes = footprint;
    result.fit = [self fitOfFootprint:footprint hardware:hardware];
    BOOL sizeUnknown = model.bytes == 0;                    //a model the user named, from a source that does not tell its size
    if (sizeUnknown)
        result.fit = AIModelFitTight;

    double smooth = hardware.isAppleSilicon ? kSmoothShare : kSmoothShareIntel;
    double tight = hardware.isAppleSilicon ? kTightShare : kTightShareIntel;
    result.minimumRAMGB = RoundUpToSoldRAM(footprint / GiB / tight);
    result.comfortableRAMGB = RoundUpToSoldRAM(footprint / GiB / smooth);

    uint64_t disk = (modelDownloaded ? 0 : model.bytes) + (runtimeInstalled ? 0 : kRuntimeDiskBytes);
    result.diskNeededBytes = disk + (disk > 0 ? kDiskMargin : 0);

    NSMutableArray<NSString*>* blockers = [NSMutableArray array];
    NSMutableArray<NSString*>* warnings = [NSMutableArray array];

    if (!runtimeInstalled && hardware.osMajor > 0 && hardware.osMajor < kRuntimeMinimumOS) {
        [blockers addObject:[NSString stringWithFormat:@"Ollama, chương trình chạy model, cần macOS %ld trở lên; máy bạn đang dùng macOS %ld. "
                             @"Hãy cập nhật macOS, hoặc dùng AI qua dịch vụ trực tuyến (ChatGPT, Gemini, Claude...).",
                             (long)kRuntimeMinimumOS, (long)hardware.osMajor]];
    }
    if (sizeUnknown) {
        [warnings addObject:@"Chưa biết dung lượng model này nên VOpenKey AI không đánh giá được máy bạn có chạy nổi không. Model quá nặng sẽ làm máy rất chậm hoặc treo; nếu vậy, hãy chọn model nhỏ hơn."];
    }
    if (result.fit == AIModelFitTooBig) {
        NSString* ramNow = [NSString stringWithFormat:@"%.0f GB", round(hardware.memoryBytes / GiB)];
        [blockers addObject:[NSString stringWithFormat:@"Model này cần ít nhất %ld GB RAM, máy bạn có %@. Hãy chọn model nhỏ hơn%@.",
                             (long)result.minimumRAMGB, ramNow,
                             hardware.isAppleSilicon ? @"" : @" (Mac dùng chip Intel chạy model bằng CPU nên giới hạn thấp hơn)"]];
    }
    if (disk > 0 && hardware.freeDiskBytes < result.diskNeededBytes) {
        [blockers addObject:[NSString stringWithFormat:@"Ổ đĩa chỉ còn trống %@, cần ít nhất %@ để tải và cài (còn chừa chỗ cho macOS hoạt động). Hãy dọn bớt ổ đĩa hoặc chọn model nhỏ hơn.",
                             VOKAIFormatBytes(hardware.freeDiskBytes), VOKAIFormatBytes(result.diskNeededBytes)]];
    } else if (disk > 0 && hardware.freeDiskBytes - disk < kDiskComfort) {
        [warnings addObject:[NSString stringWithFormat:@"Sau khi cài, ổ đĩa chỉ còn trống khoảng %@. Nên chừa ít nhất 10 GB để macOS chạy ổn định.",
                             VOKAIFormatBytes(hardware.freeDiskBytes - disk)]];
    }

    if (result.fit == AIModelFitTight && !sizeUnknown) {
        [warnings addObject:[NSString stringWithFormat:@"Model dùng khoảng %@ trên tổng %.0f GB RAM, tức là phần lớn bộ nhớ. Nên đóng bớt trình duyệt nhiều tab, máy ảo và các ứng dụng nặng khi dùng AI; nếu thấy máy chậm hẳn, chọn model nhỏ hơn.",
                             VOKAIFormatBytes(footprint), round(hardware.memoryBytes / GiB)]];
    }
    if (!hardware.isAppleSilicon) {
        [warnings addObject:@"Máy dùng chip Intel: model chạy bằng CPU, không có GPU hỗ trợ nên chậm, một câu trả lời có thể mất vài chục giây đến vài phút. Model nhỏ (1B - 4B) là hợp lý nhất. Dịch vụ trực tuyến sẽ nhanh hơn nhiều."];
    }
    if (hardware.memoryPressure != AIMemoryPressureNormal && result.fit != AIModelFitTooBig) {
        [warnings addObject:hardware.memoryPressure == AIMemoryPressureCritical
         ? @"Bộ nhớ của máy đang quá tải. Hãy đóng bớt ứng dụng trước khi dùng AI, nếu không model sẽ rất chậm."
         : @"Bộ nhớ của máy đang khá đầy. Nên đóng bớt ứng dụng nặng trước khi dùng AI."];
    }
    if (hardware.cpuLoadRatio >= 0.7) {
        [warnings addObject:[NSString stringWithFormat:@"Máy đang bận (mức tải bộ xử lý khoảng %.0f%%). Chạy model rất nặng: nó chiếm hết sức của máy, câu trả lời sẽ chậm và các ứng dụng khác bị ì. AI chạy trên máy chỉ hợp khi máy đang rảnh; lúc bận nên dùng dịch vụ trực tuyến.",
                             hardware.cpuLoadRatio * 100]];
    }
    if (hardware.onBattery) {
        [warnings addObject:@"Máy đang dùng pin. Chạy model rất tốn điện: pin sẽ tụt nhanh và máy có thể chạy chậm hơn. Nên cắm sạc khi dùng."];
    }
    if (hardware.lowPowerMode) {
        [warnings addObject:@"Chế độ Nguồn điện thấp đang bật nên máy sẽ chạy model chậm hơn bình thường."];
    }
    if (hardware.thermalState >= 2) {
        [warnings addObject:@"Máy đang rất nóng nên hệ thống giảm tốc độ. Để máy nguội bớt rồi hãy cài và dùng."];
    }

    result.blockers = blockers;
    result.warnings = warnings;
    if (blockers.count > 0 && result.fit != AIModelFitTooBig)
        result.headline = @"Chưa thể cài trên máy này";
    else if (result.fit == AIModelFitTooBig)
        result.headline = @"Quá nặng cho máy này";
    else if (sizeUnknown)
        result.headline = @"Chưa rõ máy có chạy nổi không";
    else if (result.fit == AIModelFitTight)
        result.headline = @"Chạy được nhưng sát giới hạn";
    else
        result.headline = hardware.isAppleSilicon ? @"Chạy mượt trên máy này" : @"Chạy được, nhưng chậm (chip Intel)";
    return result;
}

+(AILocalModel*)recommendedModelAmong:(NSArray<AILocalModel*>*)models hardware:(AIHardware*)hardware {
    AILocalModel* best = nil;
    for (AILocalModel* model in models) {
        if (model.isCustom || [self fitOfFootprint:[self memoryNeededForModel:model] hardware:hardware] != AIModelFitSmooth)
            continue;
        //the best quality; the ratings are coarse, so of two equal ones the larger is the more capable
        if (best == nil || model.quality > best.quality || (model.quality == best.quality && model.bytes > best.bytes))
            best = model;
    }
    if (best != nil)
        return best;
    for (AILocalModel* model in models) {               //none runs smoothly: the smallest, if it fits at all
        if (!model.isCustom && [self fitOfFootprint:[self memoryNeededForModel:model] hardware:hardware] == AIModelFitTight &&
            (best == nil || model.bytes < best.bytes))
            best = model;
    }
    return best;
}

+(NSString*)overviewForHardware:(AIHardware*)hardware models:(NSArray<AILocalModel*>*)models {
    NSMutableString* text = [NSMutableString string];
    double ram = round(hardware.memoryBytes / GiB);
    AILocalModel* best = [self recommendedModelAmong:models hardware:hardware];
    if (best == nil) {
        [text appendString:@"Máy này không đủ bộ nhớ cho các model trong danh sách. Bạn nên dùng AI qua dịch vụ trực tuyến."];
        return text;
    }
    AILocalModel* biggest = nil;
    for (AILocalModel* model in models)
        if (!model.isCustom && [self fitOfFootprint:[self memoryNeededForModel:model] hardware:hardware] != AIModelFitTooBig &&
            (biggest == nil || model.bytes > biggest.bytes))
            biggest = model;
    [text appendFormat:@"Với %.0f GB RAM, model lớn nhất chạy được là %@", ram, biggest.name];
    BOOL biggestIsTight = [self fitOfFootprint:[self memoryNeededForModel:biggest] hardware:hardware] == AIModelFitTight;
    if (biggest != best)
        [text appendFormat:@"%@; model nên chọn là %@, chạy thoải mái.", biggestIsTight ? @" (sát giới hạn)" : @"", best.name];
    else
        [text appendString:@"."];
    if (!hardware.isAppleSilicon)
        [text appendString:@" Chip Intel không có GPU cho AI nên các model chạy chậm."];
    return text;
}

@end
