// Tests of the first half of "AI on this Mac": the list of models, the reading of the Mac, and the advice given before anything
// is downloaded. Everything is computed from values given by the test, except the few checks of the real Mac.
// Run with run-ai-local-test.sh. Nothing is downloaded and nothing is installed.
//
//   ai_local_advisor_test <local-models.json>
#import <Foundation/Foundation.h>
#import "AILocalModels.h"
#import "AIHardware.h"
#import "AIModelAdvisor.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSArray<AILocalModel*>* gModels;

static AILocalModel* Model(NSString* tag) {
    for (AILocalModel* model in gModels)
        if ([model.tag isEqualToString:tag])
            return model;
    return nil;
}

static AIModelAssessment* Assess(NSString* tag, AIHardware* hardware) {
    return [AIModelAdvisor assessModel:Model(tag) hardware:hardware runtimeInstalled:YES modelDownloaded:NO];
}

static NSString* Recommended(AIHardware* hardware) {
    return [AIModelAdvisor recommendedModelAmong:gModels hardware:hardware].tag ?: @"none";
}

static BOOL AnyContains(NSArray<NSString*>* lines, NSString* needle) {
    for (NSString* line in lines)
        if ([line containsString:needle])
            return YES;
    return NO;
}

//the models that run smoothly / tightly on a Mac, as a string such as "gemma3:1b qwen2.5:3b"
static NSString* Tags(AIHardware* hardware, AIModelFit fit) {
    NSMutableArray* tags = [NSMutableArray array];
    for (AILocalModel* model in gModels)
        if (Assess(model.tag, hardware).fit == fit)
            [tags addObject:model.tag];
    return [tags componentsJoinedByString:@" "];
}

static NSURL* WriteFile(NSString* dir, NSString* name, NSString* content) {
    NSURL* url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
    [content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}

static void TestCatalog(NSString* path, NSString* dir) {
    CHECK(gModels.count == 8);
    uint64_t previous = 0;
    for (AILocalModel* model in gModels) {
        CHECK(model.bytes >= previous);                              //smallest first
        previous = model.bytes;
        CHECK(model.name.length > 0 && model.summary.length > 0 && model.vietnamese.length > 0);
        CHECK(model.quality >= 1 && model.quality <= 5 && model.speed >= 1 && model.speed <= 5);
        CHECK(!model.isCustom);
        CHECK([AILocalModels validTagFromText:model.tag] != nil);
    }
    CHECK([Model(@"gemma3:1b") bytes] == 806067407);                 //the size the registry gave
    CHECK([AILocalModels catalog].count == 0);                       //no bundle resource in a test program: empty, not a crash

    //files that are not what is expected give an empty list, never a crash
    CHECK([AILocalModels catalogFromFile:nil].count == 0);
    CHECK([AILocalModels catalogFromFile:[NSURL fileURLWithPath:@"/nonexistent/x.json"]].count == 0);
    CHECK([AILocalModels catalogFromFile:WriteFile(dir, @"a.json", @"not json {")].count == 0);
    CHECK([AILocalModels catalogFromFile:WriteFile(dir, @"b.json", @"[1,2,3]")].count == 0);
    CHECK([AILocalModels catalogFromFile:WriteFile(dir, @"c.json", @"{\"models\": 5}")].count == 0);
    CHECK([AILocalModels catalogFromFile:WriteFile(dir, @"d.json", @"{\"models\": [1, \"x\", null]}")].count == 0);
    //an entry with a bad tag or without a size is left out, the others stay; wrong types inside an entry do not crash
    NSString* mixed = @"{\"version\":1,\"models\":["
        "{\"tag\":\"ok:1b\",\"bytes\":500,\"name\":5,\"quality\":\"high\"},"
        "{\"tag\":\"../evil\",\"bytes\":500},"
        "{\"tag\":\"nosize:1b\"},"
        "{\"tag\":\"zero:1b\",\"bytes\":0},"
        "{\"tag\":\"big:9b\",\"bytes\":900,\"name\":\"Big\",\"summary\":\"s\",\"vietnamese\":\"Tốt\",\"quality\":4,\"speed\":2}]}";
    NSArray<AILocalModel*>* some = [AILocalModels catalogFromFile:WriteFile(dir, @"e.json", mixed)];
    CHECK(some.count == 2);
    CHECK([some[0].tag isEqualToString:@"ok:1b"] && [some[0].name isEqualToString:@"ok:1b"] && some[0].summary.length == 0);
    CHECK([some[1].tag isEqualToString:@"big:9b"] && some[1].quality == 4);
    CHECK([AILocalModels catalogFromFile:[NSURL fileURLWithPath:path]].count == 8);
}

static void TestTags(void) {
    for (NSString* good in @[@"gemma3:4b", @"llama3.2", @"qwen2.5:7b-instruct-q4_K_M", @"hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M",
                             @"library/gemma3:latest", @"  gemma3:1b \n", @"a", @"deepseek-r1:1.5b"])
        CHECK([AILocalModels validTagFromText:good] != nil);
    CHECK([[AILocalModels validTagFromText:@"  gemma3:1b \n"] isEqualToString:@"gemma3:1b"]);
    for (NSString* bad in @[@"", @"   ", @"../x", @"a/../b", @"..", @"a b", @"a;rm -rf", @"a|b", @"a&b", @"$(x)", @"`x`", @"a:b:c", @"gemma3:", @":4b",
                            @"/abs/path", @"a//b", @"a/b/c/d", @"-flag", @"a\nb", @"a\"b", @"mô-đen", @"a%2fb", @"a\\b", @"a:b/c", @"gemma3 :4b",
                            @"http://x/y"])
        CHECK([AILocalModels validTagFromText:bad] == nil);
    CHECK([AILocalModels validTagFromText:[@"" stringByPaddingToLength:121 withString:@"a" startingAtIndex:0]] == nil);
    CHECK([AILocalModels validTagFromText:[@"" stringByPaddingToLength:120 withString:@"a" startingAtIndex:0]] != nil);
    CHECK([AILocalModels validTagFromText:nil] == nil);
    CHECK([AILocalModels validTagFromText:(NSString*)@5] == nil);
    AILocalModel* custom = [AILocalModel customModelWithTag:@"qwen3:8b" bytes:0];
    CHECK(custom.isCustom && [custom.tag isEqualToString:@"qwen3:8b"] && custom.bytes == 0 && custom.summary.length > 0);
}

static void TestFitMatrix(void) {
    AIHardware* mac;
    mac = [AIHardware appleSiliconWithMemoryGiB:8 freeDiskGiB:200];
    CHECK([Tags(mac, AIModelFitSmooth) isEqualToString:@"gemma3:1b qwen2.5:3b"]);
    CHECK([Tags(mac, AIModelFitTight) isEqualToString:@"gemma3:4b"]);
    CHECK([Recommended(mac) isEqualToString:@"qwen2.5:3b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200];
    CHECK([Tags(mac, AIModelFitSmooth) isEqualToString:@"gemma3:1b qwen2.5:3b gemma3:4b qwen2.5:7b"]);
    CHECK([Tags(mac, AIModelFitTight) isEqualToString:@"gemma3:12b qwen2.5:14b"]);
    CHECK([Recommended(mac) isEqualToString:@"qwen2.5:7b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:24 freeDiskGiB:200];
    CHECK([Tags(mac, AIModelFitTight) isEqualToString:@""]);
    CHECK(Assess(@"gemma3:27b", mac).fit == AIModelFitTooBig && Assess(@"qwen2.5:32b", mac).fit == AIModelFitTooBig);
    CHECK([Recommended(mac) isEqualToString:@"qwen2.5:14b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];      //the Mac of the author
    CHECK([Tags(mac, AIModelFitTight) isEqualToString:@"gemma3:27b qwen2.5:32b"]);
    CHECK([Recommended(mac) isEqualToString:@"qwen2.5:14b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:36 freeDiskGiB:200];
    CHECK([Tags(mac, AIModelFitTight) isEqualToString:@"qwen2.5:32b"]);
    CHECK([Recommended(mac) isEqualToString:@"gemma3:27b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:48 freeDiskGiB:200];
    CHECK([Tags(mac, AIModelFitSmooth) componentsSeparatedByString:@" "].count == 8);
    CHECK([Recommended(mac) isEqualToString:@"qwen2.5:32b"]);
    CHECK([Recommended([AIHardware appleSiliconWithMemoryGiB:128 freeDiskGiB:200]) isEqualToString:@"qwen2.5:32b"]);

    //Intel: only the processor, lower limits
    mac = [AIHardware appleSiliconWithMemoryGiB:8 freeDiskGiB:200];  mac.isAppleSilicon = NO;
    CHECK([Tags(mac, AIModelFitSmooth) isEqualToString:@"gemma3:1b"] && [Tags(mac, AIModelFitTight) isEqualToString:@"qwen2.5:3b"]);
    CHECK([Recommended(mac) isEqualToString:@"gemma3:1b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200]; mac.isAppleSilicon = NO;
    CHECK([Recommended(mac) isEqualToString:@"gemma3:4b"] && Assess(@"qwen2.5:7b", mac).fit == AIModelFitTight);
    mac = [AIHardware appleSiliconWithMemoryGiB:64 freeDiskGiB:200]; mac.isAppleSilicon = NO;
    CHECK([Recommended(mac) isEqualToString:@"qwen2.5:32b"]);

    //little memory: the smallest model if it fits at all, otherwise nothing
    mac = [AIHardware appleSiliconWithMemoryGiB:4 freeDiskGiB:200];
    CHECK(Assess(@"gemma3:1b", mac).fit == AIModelFitTight && Assess(@"qwen2.5:3b", mac).fit == AIModelFitTooBig);
    CHECK([Recommended(mac) isEqualToString:@"gemma3:1b"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:2 freeDiskGiB:200];
    CHECK([Recommended(mac) isEqualToString:@"none"]);
    CHECK([[AIModelAdvisor overviewForHardware:mac models:gModels] containsString:@"trực tuyến"]);
    CHECK([AIModelAdvisor recommendedModelAmong:@[] hardware:mac] == nil);
    //a model the user named is never recommended
    AILocalModel* custom = [AILocalModel customModelWithTag:@"x:1b" bytes:100];
    CHECK([AIModelAdvisor recommendedModelAmong:@[custom] hardware:[AIHardware appleSiliconWithMemoryGiB:64 freeDiskGiB:200]] == nil);
}

static void TestRequirements(void) {
    AIHardware* mac = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200];
    NSDictionary* minimum = @{@"gemma3:1b": @4, @"qwen2.5:3b": @8, @"gemma3:4b": @8, @"qwen2.5:7b": @16, @"gemma3:12b": @16, @"qwen2.5:14b": @16,
                              @"gemma3:27b": @32, @"qwen2.5:32b": @32};
    NSDictionary* comfortable = @{@"gemma3:1b": @8, @"qwen2.5:3b": @8, @"gemma3:4b": @16, @"qwen2.5:7b": @16, @"gemma3:12b": @24, @"qwen2.5:14b": @24,
                                  @"gemma3:27b": @36, @"qwen2.5:32b": @48};
    for (AILocalModel* model in gModels) {
        AIModelAssessment* a = Assess(model.tag, mac);
        CHECK(a.minimumRAMGB == [minimum[model.tag] integerValue]);
        CHECK(a.comfortableRAMGB == [comfortable[model.tag] integerValue]);
        CHECK(a.memoryNeededBytes == model.bytes + (uint64_t)(1.5 * 1073741824.0));
        CHECK(a.minimumRAMGB <= a.comfortableRAMGB);
        //what is said about the requirements agrees with the verdict, on every size of RAM that was sold
        for (NSNumber* ram in @[@4, @8, @16, @18, @24, @32, @36, @48, @64, @96, @128]) {
            AIModelAssessment* b = Assess(model.tag, [AIHardware appleSiliconWithMemoryGiB:ram.doubleValue freeDiskGiB:200]);
            if (ram.integerValue >= b.comfortableRAMGB) CHECK(b.fit == AIModelFitSmooth);
            else if (ram.integerValue >= b.minimumRAMGB) CHECK(b.fit != AIModelFitTooBig);
            else CHECK(b.fit == AIModelFitTooBig);
        }
    }
    CHECK([AIModelAdvisor runtimeMinimumMajorOS] == 14);
    CHECK([AIModelAdvisor runtimeDiskBytes] >= 700000000);       //the program opened takes 641 MB
}

static void TestBlockersAndWarnings(void) {
    AILocalModel* small = Model(@"gemma3:1b");
    AIHardware* mac;
    AIModelAssessment* a;

    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];
    a = [AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:NO modelDownloaded:NO];
    CHECK(a.canInstall && a.blockers.count == 0 && a.warnings.count == 0);
    CHECK([a.headline isEqualToString:@"Chạy mượt trên máy này"]);
    CHECK(a.diskNeededBytes == small.bytes + [AIModelAdvisor runtimeDiskBytes] + 3000000000ULL);

    //macOS older than 14: a blocker unless the program is already there
    mac.osMajor = 13;
    a = [AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:NO modelDownloaded:NO];
    CHECK(!a.canInstall && AnyContains(a.blockers, @"macOS 14") && AnyContains(a.blockers, @"macOS 13"));
    a = [AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:YES modelDownloaded:NO];
    CHECK(a.canInstall);
    mac.osMajor = 0;                                            //unknown version: not a reason to refuse
    CHECK([AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:NO modelDownloaded:NO].canInstall);

    //too big: blocker with the RAM it needs, headline says so
    mac = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200];
    a = Assess(@"gemma3:27b", mac);
    CHECK(!a.canInstall && AnyContains(a.blockers, @"32 GB RAM") && AnyContains(a.blockers, @"16 GB"));
    CHECK([a.headline isEqualToString:@"Quá nặng cho máy này"]);
    mac.isAppleSilicon = NO;
    CHECK(AnyContains(Assess(@"gemma3:27b", mac).blockers, @"Intel"));

    //tight: warning, can be installed
    mac = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200];
    a = Assess(@"gemma3:12b", mac);
    CHECK(a.canInstall && a.fit == AIModelFitTight && AnyContains(a.warnings, @"phần lớn bộ nhớ"));
    CHECK([a.headline isEqualToString:@"Chạy được nhưng sát giới hạn"]);

    //disk
    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:3];
    a = [AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:NO modelDownloaded:NO];
    CHECK(!a.canInstall && AnyContains(a.blockers, @"Ổ đĩa") && [a.headline isEqualToString:@"Chưa thể cài trên máy này"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:6];      //enough to install, little left: a warning
    a = [AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:NO modelDownloaded:NO];
    CHECK(a.canInstall && AnyContains(a.warnings, @"10 GB"));
    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:0.1];    //everything is already there: nothing to download
    a = [AIModelAdvisor assessModel:small hardware:mac runtimeInstalled:YES modelDownloaded:YES];
    CHECK(a.canInstall && a.diskNeededBytes == 0 && a.warnings.count == 0);
    mac.freeDiskBytes = 0;                                               //exactly enough, without the margin, is refused
    a = [AIModelAdvisor assessModel:small hardware:[AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:1] runtimeInstalled:YES modelDownloaded:NO];
    CHECK(!a.canInstall);
    AIHardware* edge = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:1];
    edge.freeDiskBytes = small.bytes + 3000000000ULL;
    CHECK([AIModelAdvisor assessModel:small hardware:edge runtimeInstalled:YES modelDownloaded:NO].canInstall);
    edge.freeDiskBytes -= 1;
    CHECK(![AIModelAdvisor assessModel:small hardware:edge runtimeInstalled:YES modelDownloaded:NO].canInstall);

    //the moment: battery, low power mode, heat, memory in use; none of them stops the installation
    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];
    mac.onBattery = YES; mac.lowPowerMode = YES; mac.thermalState = 2; mac.memoryPressure = AIMemoryPressureWarning;
    a = Assess(@"gemma3:4b", mac);
    CHECK(a.canInstall && a.warnings.count == 4);
    CHECK(AnyContains(a.warnings, @"pin") && AnyContains(a.warnings, @"Nguồn điện thấp") && AnyContains(a.warnings, @"nóng") && AnyContains(a.warnings, @"khá đầy"));
    mac.thermalState = 1; mac.memoryPressure = AIMemoryPressureCritical;
    a = Assess(@"gemma3:4b", mac);
    CHECK(a.warnings.count == 3 && AnyContains(a.warnings, @"quá tải") && !AnyContains(a.warnings, @"nóng"));
    mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];
    mac.isAppleSilicon = NO;
    a = Assess(@"gemma3:1b", mac);
    CHECK(a.canInstall && AnyContains(a.warnings, @"Intel") && [a.headline containsString:@"Intel"]);
    //warnings about the memory in use say nothing when the model does not fit anyway
    mac = [AIHardware appleSiliconWithMemoryGiB:8 freeDiskGiB:200];
    mac.memoryPressure = AIMemoryPressureCritical;
    CHECK(!AnyContains(Assess(@"gemma3:27b", mac).warnings, @"quá tải"));
}

static void TestUnknownSize(void) {
    //a model the user named, whose size is not known: neither "fits" nor "does not", and it says so
    AILocalModel* unknown = [AILocalModel customModelWithTag:@"someone/model:Q4" bytes:0];
    AIHardware* mac = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200];
    AIModelAssessment* a = [AIModelAdvisor assessModel:unknown hardware:mac runtimeInstalled:YES modelDownloaded:NO];
    CHECK(a.canInstall && a.fit == AIModelFitTight && [a.headline isEqualToString:@"Chưa rõ máy có chạy nổi không"]);
    CHECK(a.warnings.count == 1 && AnyContains(a.warnings, @"Chưa biết dung lượng"));
    CHECK(a.diskNeededBytes == 0 || a.diskNeededBytes == 3000000000ULL);
    a = [AIModelAdvisor assessModel:unknown hardware:mac runtimeInstalled:NO modelDownloaded:NO];
    CHECK(a.canInstall && a.diskNeededBytes == [AIModelAdvisor runtimeDiskBytes] + 3000000000ULL);
    //the other checks still apply to it
    mac.osMajor = 13;
    CHECK(![AIModelAdvisor assessModel:unknown hardware:mac runtimeInstalled:NO modelDownloaded:NO].canInstall);
    //a model whose size was found is judged like the others
    AILocalModel* found = [AILocalModel customModelWithTag:@"qwen3:8b" bytes:5200000000ULL];
    CHECK([AIModelAdvisor assessModel:found hardware:[AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:200] runtimeInstalled:YES modelDownloaded:NO].fit == AIModelFitSmooth);
    CHECK([AIModelAdvisor assessModel:found hardware:[AIHardware appleSiliconWithMemoryGiB:8 freeDiskGiB:200] runtimeInstalled:YES modelDownloaded:NO].fit == AIModelFitTooBig);
}

static void TestBusyMac(void) {
    AIHardware* mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];
    struct { double load; AIMemoryPressure pressure; NSString* word; BOOL busy; } cases[] = {
        {0.0, AIMemoryPressureNormal, @"đang rảnh", NO}, {0.39, AIMemoryPressureNormal, @"đang rảnh", NO}, {0.4, AIMemoryPressureNormal, @"hơi bận", NO},
        {0.69, AIMemoryPressureNormal, @"hơi bận", NO}, {0.7, AIMemoryPressureNormal, @"hơi bận", YES}, {0.99, AIMemoryPressureNormal, @"hơi bận", YES},
        {1.0, AIMemoryPressureNormal, @"đang bận", YES}, {3.0, AIMemoryPressureNormal, @"đang bận", YES},
        {0.1, AIMemoryPressureWarning, @"hơi bận", YES}, {0.1, AIMemoryPressureCritical, @"đang bận", YES},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        mac.cpuLoadRatio = cases[i].load;
        mac.memoryPressure = cases[i].pressure;
        CHECK([[mac loadDescription] isEqualToString:cases[i].word] && [mac isBusy] == cases[i].busy);
    }
    //the advice says so when the processor is busy, and not otherwise
    mac.memoryPressure = AIMemoryPressureNormal;
    mac.cpuLoadRatio = 0.69;
    CHECK(!AnyContains(Assess(@"gemma3:4b", mac).warnings, @"Máy đang bận"));
    mac.cpuLoadRatio = 0.7;
    AIModelAssessment* a = Assess(@"gemma3:4b", mac);
    CHECK(a.canInstall && AnyContains(a.warnings, @"Máy đang bận (mức tải bộ xử lý khoảng 70%)") && AnyContains(a.warnings, @"chỉ hợp khi máy đang rảnh"));
    mac.cpuLoadRatio = 2.5;
    CHECK(AnyContains(Assess(@"gemma3:4b", mac).warnings, @"khoảng 250%") && Assess(@"gemma3:4b", mac).canInstall);     //a warning, not a block
}

static void TestOverview(void) {
    AIHardware* mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];
    NSString* text = [AIModelAdvisor overviewForHardware:mac models:gModels];
    CHECK([text containsString:@"32 GB RAM"] && [text containsString:@"Qwen 2.5 32B (sát giới hạn)"] && [text containsString:@"Qwen 2.5 14B"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:24 freeDiskGiB:200];        //the biggest and the best are both smooth
    text = [AIModelAdvisor overviewForHardware:mac models:gModels];
    CHECK([text containsString:@"model lớn nhất chạy được là Qwen 2.5 14B"] && ![text containsString:@"sát giới hạn"]);
    mac = [AIHardware appleSiliconWithMemoryGiB:64 freeDiskGiB:200];
    text = [AIModelAdvisor overviewForHardware:mac models:gModels];
    CHECK([text containsString:@"Qwen 2.5 32B."] && ![text containsString:@"nên chọn"]);
    mac.isAppleSilicon = NO;
    CHECK([[AIModelAdvisor overviewForHardware:mac models:gModels] containsString:@"Intel"]);
}

static void TestRealMac(void) {
    AIHardware* mac = [AIHardware current];
    CHECK(mac.memoryBytes >= 2ULL * 1073741824ULL);
    CHECK(mac.chipName.length > 0);
    CHECK(mac.osMajor >= 11);
    CHECK(mac.cpuCores >= 1);
    CHECK(mac.freeDiskBytes > 100000000ULL);
    CHECK(mac.thermalState >= 0 && mac.thermalState <= 3);
    CHECK(mac.cpuLoadRatio >= 0 && mac.cpuLoadRatio < 100);                //the load of the processor of this Mac was read
    CHECK(mac.availableMemoryBytes > 0 && mac.availableMemoryBytes <= mac.memoryBytes);
#if defined(__arm64__)
    CHECK(mac.isAppleSilicon);                                   //this program is native: the Mac is Apple Silicon
#endif
    CHECK([[mac summary] containsString:@"GB RAM"] && [[mac summary] containsString:@"macOS"] && [[mac summary] containsString:@"trống"]);
    //the folder of the models does not exist yet: the volume it will be on is measured
    AIHardware* other = [AIHardware currentForDirectory:[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"no/such/folder/yet"]]];
    CHECK(other.freeDiskBytes > 100000000ULL);
    int64_t difference = (int64_t)other.freeDiskBytes - (int64_t)mac.freeDiskBytes;
    CHECK(llabs(difference) < 2000000000LL);                     //the same volume, as free space moves a little
    CHECK([AIHardware currentForDirectory:[NSURL fileURLWithPath:@"/"]].freeDiskBytes > 0);
}

static void TestFormat(void) {
    CHECK([VOKAIFormatBytes(0) isEqualToString:@"0 MB"]);
    CHECK([VOKAIFormatBytes(806067407) isEqualToString:@"806 MB"]);
    CHECK([VOKAIFormatBytes(4683087332ULL) isEqualToString:@"4,7 GB"]);
    CHECK([VOKAIFormatBytes(999999999ULL) isEqualToString:@"1,0 GB"]);
    CHECK([VOKAIFormatBytes(999400000ULL) isEqualToString:@"999 MB"]);
    CHECK([VOKAIFormatBytes(123456789012ULL) isEqualToString:@"123 GB"]);
    CHECK([VOKAIFormatBytes(99900000000ULL) isEqualToString:@"99,9 GB"]);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 2) { printf("usage: ai_local_advisor_test <local-models.json>\n"); return 2; }
        NSString* path = @(argv[1]);
        gModels = [AILocalModels catalogFromFile:[NSURL fileURLWithPath:path]];
        NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        TestCatalog(path, dir);
        TestTags();
        TestFitMatrix();
        TestRequirements();
        TestBlockersAndWarnings();
        TestUnknownSize();
        TestBusyMac();
        TestOverview();
        TestRealMac();
        TestFormat();
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        printf(failures == 0 ? "ai_local_advisor_test: all passed\n" : "ai_local_advisor_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
