// The AI agent programs for real: every one that is installed on this Mac (Codex, Claude Code, Antigravity) is asked a question
// through the same code the assistant uses, with what the user would have by default (a light model, the fast level). It shows the
// command that is run (without the request), how long it took, what came back, and whether Vietnamese came back as it was written.
//
//   ai_agent_e2e [codex-cli] [claude-cli] [agy-cli]
//
// This uses the accounts the programs are signed in with, a few words each. Run it with run-ai-agent-e2e.sh (VOK_E2E=1). Nothing of
// the user's is changed: no setting, no key; the programs run in an empty folder of their own.
#import <Foundation/Foundation.h>
#import "AIProvider.h"
#import "AISettings.h"
#import "AIClient.h"
#import "AIAgentCLI.h"

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        Spin(0.01);
    return done();
}

static int problems = 0;

//the text that must come back exactly (precomposed Vietnamese)
static NSString* const kSentence = @"Xin chào, tiếng Việt có dấu.";

static void Try(NSString* providerId) {
    AIProvider* provider = [AIProvider providerWithIdentifier:providerId];
    AIAgentCLI* cli = [AIAgentCLI forProvider:provider];
    printf("\n== %s\n", provider.name.UTF8String);
    NSString* executable = [AISettings executablePathForProvider:provider];
    if (executable == nil) {
        printf("   SKIPPED: `%s` is not installed here\n", cli.command.UTF8String);
        return;
    }
    printf("   program: %s\n", executable.UTF8String);

    //its models
    __block NSArray<AIAgentModel*>* models = nil;
    __block NSError* listError = nil;
    __block BOOL listed = NO;
    NSDate* started = [NSDate date];
    [cli loadModelsFromExecutable:executable completion:^(NSArray<AIAgentModel*>* m, NSError* e) { models = m; listError = e; listed = YES; }];
    SpinUntil(^BOOL { return listed; }, 60);
    if (models.count > 0) {
        NSMutableArray* names = [NSMutableArray array];
        for (AIAgentModel* m in models)
            [names addObject:m.efforts.count > 0 ? [NSString stringWithFormat:@"%@ [%@]", m.identifier, [m.efforts componentsJoinedByString:@","]] : m.identifier];
        printf("   models (%.1f s): %s\n", -[started timeIntervalSinceNow], [names componentsJoinedByString:@"  "].UTF8String);
    } else {
        printf("   models: none (%s)\n", listError.localizedDescription.UTF8String ?: "no error");
    }

    //what is run, by default
    NSError* configError = nil;
    AIConfiguration* configuration = [AISettings configurationForProvider:provider error:&configError];
    if (configuration == nil) {
        printf("   PROBLEM: %s\n", configError.localizedDescription.UTF8String);
        problems++;
        return;
    }
    NSString* model = nil, *effort = nil;
    [cli resolveModel:configuration.model effort:configuration.effort models:[cli knownModels] modelArgument:&model effortArgument:&effort];
    NSArray<NSString*>* arguments = [cli argumentsWithModel:model effort:effort systemPrompt:configuration.systemPrompt prompt:@"…" workDirectory:@"<empty folder>"];
    NSMutableArray* shown = [NSMutableArray array];
    for (NSString* argument in arguments)
        [shown addObject:argument.length > 90 ? [[argument substringToIndex:60] stringByAppendingString:@"…"] : argument];
    printf("   model: %s, level: %s\n", (model ?: @"(its own)").UTF8String, (effort ?: @"(its own)").UTF8String);
    printf("   command: %s %s\n", cli.command.UTF8String, [shown componentsJoinedByString:@" "].UTF8String);

    //a real request
    NSString* prompt = [NSString stringWithFormat:@"Lặp lại đúng câu sau, không thêm gì khác, không dấu ngoặc kép: %@", kSentence];
    __block NSMutableString* text = [NSMutableString string];
    __block NSError* error = nil;
    __block BOOL finished = NO;
    __block NSUInteger pieces = 0;
    __block NSTimeInterval firstPiece = 0;
    started = [NSDate date];
    AIClient* client = [[AIClient alloc] initWithConfiguration:configuration];
    [client generateWithPrompt:prompt onText:^(NSString* piece) {
        if (pieces == 0)
            firstPiece = -[started timeIntervalSinceNow];
        pieces++;
        [text appendString:piece];
    } completion:^(NSError* e) { error = e; finished = YES; }];
    SpinUntil(^BOOL { return finished; }, 240);
    NSTimeInterval took = -[started timeIntervalSinceNow];
    if (!finished) {
        printf("   PROBLEM: no answer after %.0f s\n", took);
        [client cancel];
        problems++;
        return;
    }
    if (error != nil) {
        printf("   PROBLEM (%.1f s): [code %ld] %s\n", took, (long)error.code, error.localizedDescription.UTF8String);
        problems++;
        return;
    }
    NSString* answer = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    printf("   answer (%.1f s, first text after %.1f s, %lu pieces): %s\n", took, firstPiece, (unsigned long)pieces, answer.UTF8String);
    BOOL exact = [answer rangeOfString:kSentence options:NSLiteralSearch].location != NSNotFound;
    BOOL decomposed = !exact && [answer rangeOfString:kSentence].location != NSNotFound;
    if (exact)
        printf("   OK: the sentence came back exactly as it was written\n");
    else if (decomposed) {
        printf("   PROBLEM: the sentence came back, but with the accents taken apart\n");
        problems++;
    } else {
        printf("   NOTE: the answer is not the sentence (the model may have worded it otherwise)\n");
    }
}

int main(int argc, char** argv) {
    @autoreleasepool {
        NSMutableArray<NSString*>* which = [NSMutableArray array];
        for (int i = 1; i < argc; i++)
            [which addObject:[NSString stringWithUTF8String:argv[i]]];
        if (which.count == 0)
            which = [@[@"codex-cli", @"claude-cli", @"agy-cli"] mutableCopy];
        for (NSString* identifier in which)
            Try(identifier);
        printf(problems ? "\n%d PROBLEMS\n" : "\nDONE\n", problems);
    }
    return problems ? 1 : 0;
}
