// The whole installation of an AI on the Mac, for real: the real GitHub, the real library of Ollama, the real Ollama, a real
// model, a real question. It is NOT part of run-ai-local-test.sh: it downloads about 0.5 GB and takes minutes. Run it with
// run-ai-local-e2e.sh, which keeps everything in a folder of its own (a different HOME for Ollama, a different port) and removes
// it afterwards, so nothing of the user's is touched.
//
//   ai_local_e2e <folder> <port> <model>
#import <Foundation/Foundation.h>
#import "AIClient.h"
#import "AILocalSetup.h"
#import "AIModelAdvisor.h"
#import "AISettings.h"

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 4) { printf("usage: ai_local_e2e <folder> <port> <model>\n"); return 2; }
        NSString* home = @(argv[1]);
        NSString* port = @(argv[2]);
        NSString* tag = @(argv[3]);
        setenv("HOME", home.UTF8String, 1);          //what the child process (ollama) uses; NSHomeDirectory() does not follow it
        [[NSFileManager defaultManager] createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:nil];
        [AISettings registerDefaults];
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        #define SAY(...) do { printf("[+%6.1fs] ", CFAbsoluteTimeGetCurrent() - t0); printf(__VA_ARGS__); printf("\n"); fflush(stdout); } while (0)

        AIHardware* mac = [AIHardware current];
        SAY("the Mac: %s", [[mac summary] UTF8String]);
        SAY("battery %d, low power %d, thermal %ld, memory pressure %ld, available memory %s", mac.onBattery, mac.lowPowerMode, (long)mac.thermalState, (long)mac.memoryPressure,
            [VOKAIFormatBytes(mac.availableMemoryBytes) UTF8String]);

        //the size of the model, from the real library
        __block uint64_t size = 0; __block NSError* sizeError = nil; __block BOOL looked = NO;
        [AIOllama librarySizeOfTag:tag registry:[AIOllama defaultRegistryURL] completion:^(uint64_t b, NSError* e) { size = b; sizeError = e; looked = YES; }];
        SpinUntil(^BOOL { return looked; }, 30);
        SAY("size of %s in the library: %s%s", tag.UTF8String, [VOKAIFormatBytes(size) UTF8String], sizeError ? [[@" ERROR " stringByAppendingString:sizeError.localizedDescription] UTF8String] : "");
        if (size == 0) return 1;
        AILocalModel* model = [AILocalModel customModelWithTag:tag bytes:size];

        NSURL* apps = [NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Applications"] isDirectory:YES];
        NSURL* work = [NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"Library/Application Support/VOpenKey"] isDirectory:YES];
        AIOllamaRuntime* runtime = [[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:[@"http://127.0.0.1:" stringByAppendingString:port]]
                                                                searchPaths:@[[apps.path stringByAppendingPathComponent:@"Ollama.app/Contents/Resources/ollama"]]];
        AIModelAssessment* assessment = [AIModelAdvisor assessModel:model hardware:mac runtimeInstalled:runtime.isInstalled modelDownloaded:NO];
        SAY("advice: %s | blockers %lu | warnings %lu | needs RAM %ld-%ld GB, disk %s", assessment.headline.UTF8String, (unsigned long)assessment.blockers.count,
            (unsigned long)assessment.warnings.count, (long)assessment.minimumRAMGB, (long)assessment.comfortableRAMGB, [VOKAIFormatBytes(assessment.diskNeededBytes) UTF8String]);
        for (NSString* line in assessment.blockers) SAY("  blocker: %s", line.UTF8String);
        for (NSString* line in assessment.warnings) SAY("  warning: %s", line.UTF8String);
        if (!assessment.canInstall) return 1;

        //the installer of the application, with the real addresses, the real verifier, and folders of this test
        AIOllamaInstaller* installer = [[AIOllamaInstaller alloc] initWithReleaseURL:[NSURL URLWithString:@"https://api.github.com/repos/ollama/ollama/releases/latest"]
            fallbackURL:[NSURL URLWithString:@"https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip"]
            installDirectory:apps workDirectory:work verifier:[AIOllamaVerifier standard]];
        AILocalSetup* setup = [[AILocalSetup alloc] initWithInstaller:installer runtime:runtime];
        __block CFAbsoluteTime lastPrint = 0;
        __block NSMutableArray<NSString*>* last = [NSMutableArray arrayWithObjects:@"", @"", @"", @"", @"", nil];
        __weak AILocalSetup* weakSetup = setup;
        setup.onChange = ^{
            AILocalSetup* setup = weakSetup;
            for (int i = 0; i < AILocalStepCount; i++) {
                NSString* text = [NSString stringWithFormat:@"%d %@", (int)[setup stateOfStep:(AILocalStep)i], [setup detailOfStep:(AILocalStep)i]];
                BOOL progress = [setup stateOfStep:(AILocalStep)i] == AILocalStepRunning && [setup fractionOfStep:(AILocalStep)i] >= 0;
                if ([text isEqualToString:last[i]])
                    continue;
                if (progress && CFAbsoluteTimeGetCurrent() - lastPrint < 5)
                    continue;
                if (progress) lastPrint = CFAbsoluteTimeGetCurrent();
                last[i] = text;
                SAY("step %d %-38s state %d: %s", i, [[AILocalSetup titleOfStep:(AILocalStep)i] UTF8String], (int)[setup stateOfStep:(AILocalStep)i], [[setup detailOfStep:(AILocalStep)i] UTF8String]);
            }
        };
        [setup installModel:model];
        SpinUntil(^BOOL { return !setup.running; }, 1800);
        SAY("finished: succeeded %d, error: %s", setup.succeeded, setup.error ? setup.error.localizedDescription.UTF8String : "none");
        int status = setup.succeeded ? 0 : 1;

        if (setup.succeeded) {
            //what the assistant would do now: the settings say Ollama and the model; ask it for a Vietnamese text
            AIProvider* provider = AISettings.provider;
            NSError* problem = nil;
            AIConfiguration* configuration = [AISettings configurationForProvider:provider error:&problem];
            SAY("settings: provider %s, model %s, address %s, ready %d", provider.identifier.UTF8String, configuration.model.UTF8String, configuration.baseURL.UTF8String, configuration != nil);
            if (configuration == nil) { SAY("  %s", problem.localizedDescription.UTF8String); status = 1; }
            else {
                __block NSMutableString* answer = [NSMutableString string];
                __block NSError* failure = nil; __block BOOL done = NO;
                AIClient* client = [[AIClient alloc] initWithConfiguration:configuration];
                CFAbsoluteTime asked = CFAbsoluteTimeGetCurrent();
                [client generateWithPrompt:@"Dịch sang tiếng Anh: Hôm nay trời đẹp, chúng ta đi dạo nhé." onText:^(NSString* piece) { [answer appendString:piece]; }
                                completion:^(NSError* e) { failure = e; done = YES; }];
                SpinUntil(^BOOL { return done; }, 300);
                SAY("answer in %.1fs: %s%s", CFAbsoluteTimeGetCurrent() - asked, [answer UTF8String], failure ? [[@" ERROR " stringByAppendingString:failure.localizedDescription] UTF8String] : "");
                if (failure != nil || answer.length == 0) status = 1;
            }
            //the model is on the disk, as the window reads it
            NSSet* tags = [AILocalSetup installedTagsInModelsDirectory:[NSURL fileURLWithPath:[home stringByAppendingPathComponent:@".ollama/models"]]];
            SAY("models on the disk: %s", [[[tags allObjects] componentsJoinedByString:@", "] UTF8String]);
            if (![tags containsObject:tag]) status = 1;
        }
        BOOL managed = runtime.isManaged;
        SAY("server started by the application: %d", managed);
        [runtime stopWaiting:5];
        SAY("server stopped");
        [AISettings resetToDefaults];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
        return status;
    }
}
