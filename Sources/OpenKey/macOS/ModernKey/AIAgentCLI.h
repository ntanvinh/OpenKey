//
//  AIAgentCLI.h
//  VOpenKey
//
//  The AI agents that run as a program in the Terminal (Codex of OpenAI, Claude Code of Anthropic, Antigravity of Google) used as
//  the AI of the assistant, for whoever prefers not to keep an API key or to run a model on the Mac. Each of them is already
//  signed in by itself, so VOpenKey AI never sees an account, a token or a key: it only runs the program.
//
//  An agent is made to work on files and run commands, the assistant only needs it to write text. So every request is run
//  - in a folder of its own that is empty and private, so there is nothing to read or change around it;
//  - with the agent's tools, its read-write access, and what the user set up for it (hooks, MCP servers, rules) turned off, as far
//    as each program allows it, and with a line in the prompt saying that nothing but text is wanted;
//  - with the text of the request on the standard input, not in the arguments, where every program could list it (Antigravity only
//    takes it as an argument);
//  - and with a Unicode-exact call: the arguments are passed as they are (precomposed Vietnamese), see AIAgentProcess.
//  This file knows, for each program, where it usually is, what models it has, what to pass to it and how to read what it prints.
//  AIAgentRunner runs it.
//

#import <Foundation/Foundation.h>
#import "AIProvider.h"

typedef NS_ENUM(NSInteger, AIAgentKind) {
    AIAgentKindCodex,
    AIAgentKindClaude,
    AIAgentKindAntigravity
};

/// What the program prints on its standard output.
typedef NS_ENUM(NSInteger, AIAgentOutput) {
    AIAgentOutputPlain,         //the answer itself
    AIAgentOutputClaudeJSON,    //one JSON object per line (stream-json): text deltas, then a result
    AIAgentOutputCodexJSON      //one JSON object per line (`codex exec --json`): the thread, the messages of the agent, the end
};

/// Saved as the thinking level when the user wants what the program does by itself: no level is passed to it.
extern NSString* const AIAgentEffortProgramDefault;

/// A model of an agent, as offered in the menus.
@interface AIAgentModel : NSObject
/// What the program takes after --model.
@property (nonatomic, copy) NSString* identifier;
/// As shown in a menu.
@property (nonatomic, copy) NSString* name;
/// One line about it, nil when there is none.
@property (nonatomic, copy) NSString* summary;
/// The thinking levels it accepts, lowest first. nil when it is not known: the usual ones may be tried.
@property (nonatomic, copy) NSArray<NSString*>* efforts;
/// What the program uses when it is not told, nil when not known.
@property (nonatomic, copy) NSString* defaultEffort;
/// For a model whose levels are separate models of the program (Antigravity lists gemini-3.8-flash-low, -medium and -high): the
/// model to ask for, by level. `identifier` is then the name they share (gemini-3.8-flash). nil for the others.
@property (nonatomic, copy) NSDictionary<NSString*, NSString*>* variants;
/// Fast and cheap, good enough for writing, translating and correcting: what is used until the user chooses.
@property (nonatomic) BOOL light;
@end

@interface AIAgentCLI : NSObject

@property (nonatomic, readonly) AIAgentKind kind;
/// "codex", "claude", "agy": the name of the program.
@property (nonatomic, readonly, copy) NSString* command;
/// "Codex CLI": as the user knows it.
@property (nonatomic, readonly, copy) NSString* displayName;
/// What to type in the Terminal to sign in, in Vietnamese words where the command is not enough.
@property (nonatomic, readonly, copy) NSString* loginHint;
/// How to install it, nil when unknown.
@property (nonatomic, readonly, copy) NSString* installHint;
/// The program can make pictures (Codex, with its imagegen skill). The others cannot.
@property (nonatomic, readonly) BOOL canMakeImages;
/// What the user should know besides where the text goes, nil when there is nothing to add. Antigravity keeps every request as a
/// conversation of its own in its folder, and has no way to ask it not to; the others are told not to keep anything.
@property (nonatomic, readonly, copy) NSString* storageNote;
@property (nonatomic, readonly) AIAgentOutput output;

/// nil for a provider that is not an agent program.
+(AIAgentCLI*)forProvider:(AIProvider*)provider;

#pragma mark Finding the program

/// Where the programs of the user usually are. An application started from the Dock does not have the PATH of the Terminal
/// (the folders of nvm, Homebrew, ~/.local/bin are missing), so they are listed here. Folders that do not exist are left out.
+(NSArray<NSString*>*)searchDirectoriesForHome:(NSString*)home environmentPath:(NSString*)path;
+(NSArray<NSString*>*)searchDirectories;
/// For tests: the only folders where programs are looked for, so that a test does not depend on what is installed on the Mac that runs
/// it. nil puts the usual ones back.
+(void)setSearchDirectoriesForTesting:(NSArray<NSString*>*)directories;

/// The program: `override` (the path the user chose) when it can be run, otherwise the first one found in the usual folders.
/// nil when there is none.
-(NSString*)locateExecutableWithOverride:(NSString*)override home:(NSString*)home environmentPath:(NSString*)path;
-(NSString*)locateExecutableWithOverride:(NSString*)override;

/// A file the user may run: it exists, is not a folder, has the execute permission.
+(BOOL)isRunnableFile:(NSString*)path;

/// The PATH to give the program: its own folder first (a script that starts with `env node` needs the node that sits next to it),
/// then the usual folders, then the PATH this application has.
+(NSString*)pathForExecutable:(NSString*)executable home:(NSString*)home environmentPath:(NSString*)path;

#pragma mark Models and thinking levels

/// The thinking levels any of the programs knows, lowest first: low, medium, high, xhigh, max.
+(NSArray<NSString*>*)commonEfforts;
/// "Thấp", "Vừa", "Cao"...: how a level is shown.
+(NSString*)nameOfEffort:(NSString*)effort;

/// The models known now, without asking the program: what it told last time, or what is built in. May be empty.
-(NSArray<AIAgentModel*>*)knownModels;
/// Asks the program which models it has (Codex: `codex debug models`, it does not need the network; Antigravity: `agy models`).
/// Claude Code has no such list: the built-in one is returned. `completion` is called on the main thread.
-(void)loadModelsFromExecutable:(NSString*)executable completion:(void (^)(NSArray<AIAgentModel*>* models, NSError* error))completion;
/// What `codex debug models` prints: the models meant for the menu, the best first.
+(NSArray<AIAgentModel*>*)modelsFromCodexCatalog:(NSData*)json;
/// What `agy models` prints: a line for each model, "identifier<TAB>name". The ones that only differ by the level at the end of their
/// identifier and of their name ("gemini-3.8-flash-low" "Gemini 3.8 Flash (Low)") are one model with several levels.
+(NSArray<AIAgentModel*>*)modelsFromAntigravityList:(NSString*)text;

/// What to pass after --model. `saved` is what the user chose: empty means "choose for me", which is a light model. nil: pass
/// nothing, the program uses its own.
-(NSString*)modelToPassForSaved:(NSString*)saved models:(NSArray<AIAgentModel*>*)models;
/// What to pass as the thinking level. `saved` is what the user chose: nil/empty means "choose for me" (low, which is the fast one,
/// when the model accepts it), AIAgentEffortProgramDefault means nothing is passed. nil: pass nothing.
-(NSString*)effortToPassForSaved:(NSString*)saved modelToPass:(NSString*)model models:(NSArray<AIAgentModel*>*)models;
/// The thinking level that a request will really have, as the name of a level; nil when the program is left to its own. For a model whose
/// levels are models of the program it is the level of the one that will be asked for.
-(NSString*)effectiveEffortForSavedModel:(NSString*)savedModel effort:(NSString*)savedEffort models:(NSArray<AIAgentModel*>*)models;
/// What a level costs in time, in words ("Chậm hơn, có thể 15 đến 40 giây"), measured on real programs: the level decides most of the wait.
+(NSString*)speedNoteForEffort:(NSString*)effort;
/// The levels that answer in a few seconds: the lowest ones, and the program's own default (nil) which is not known.
+(BOOL)isFastEffort:(NSString*)effort;
/// The choice as it is told to the user: "GPT-6-Luna · Thấp (nhanh nhất)". `savedModel` and `savedEffort` are what the user chose
/// (empty: "choose for me"), `models` what is known of the program.
-(NSString*)summaryForSavedModel:(NSString*)savedModel effort:(NSString*)savedEffort models:(NSArray<AIAgentModel*>*)models;
/// What to put after --model and --effort, from what the user chose: the model and the level chosen as above, and then, for a model
/// whose levels are models of the program, the one of the level (and no --effort: the level is in its name). Either can be nil.
-(void)resolveModel:(NSString*)savedModel effort:(NSString*)savedEffort models:(NSArray<AIAgentModel*>*)models
      modelArgument:(NSString**)modelArgument effortArgument:(NSString**)effortArgument;
/// The model with this identifier among `models`, nil when it is not there.
+(AIAgentModel*)modelWithIdentifier:(NSString*)identifier among:(NSArray<AIAgentModel*>*)models;
/// A name that can safely be given to a program as the value of --model: not empty, not too long, not starting with a dash (it would
/// be taken for a flag), no control characters.
+(BOOL)isPlausibleModelName:(NSString*)name;

#pragma mark Running it

/// Everything said to the agent besides the request: that nothing but text is wanted, and the instruction of the user.
+(NSString*)instructionWithSystemPrompt:(NSString*)systemPrompt;

/// The arguments for one request. `model` and `effort` are what -modelToPass… and -effortToPass… gave (nil: not passed).
/// For Antigravity the prompt is the last argument; the other two take it on the standard input (-standardInputForPrompt…).
-(NSArray<NSString*>*)argumentsWithModel:(NSString*)model effort:(NSString*)effort systemPrompt:(NSString*)systemPrompt
                                  prompt:(NSString*)prompt workDirectory:(NSString*)workDirectory;
/// What goes in the standard input, nil when the prompt is in the arguments.
-(NSData*)standardInputForPrompt:(NSString*)prompt systemPrompt:(NSString*)systemPrompt;

#pragma mark Pictures

/// What is said to Codex to make a picture. Without the skill named it makes poor ones, so the request is put in a sentence that names it:
/// `request` goes where {prompt} is in `template`; a template without {prompt} gets the request after it.
+(NSString*)imagePromptForRequest:(NSString*)request template:(NSString*)template;
/// "Use $imagegen skill to create picture {prompt}, follow our design system."
+(NSString*)defaultImagePromptTemplate;
/// The arguments for a picture: the same locked-down run as a text, with the events as JSON (they say which thread it was, and so where
/// the picture is). The prompt is on the standard input as it is: -standardInputForImagePrompt:.
-(NSArray<NSString*>*)imageArgumentsWithModel:(NSString*)model effort:(NSString*)effort workDirectory:(NSString*)workDirectory;
-(NSData*)standardInputForImagePrompt:(NSString*)prompt;
/// Where Codex keeps what it generates: $CODEX_HOME, or ~/.codex.
+(NSString*)codexHomeForEnvironment:(NSDictionary<NSString*, NSString*>*)environment;
/// The picture a run made: in the folder of its thread under generated_images, or else the newest picture there that was made since
/// `since`. nil when there is none.
+(NSURL*)generatedImageForThread:(NSString*)thread codexHome:(NSString*)codexHome since:(NSDate*)since;

/// The environment of the program: this application's, with a PATH that finds what it needs, and no colours.
-(NSDictionary<NSString*, NSString*>*)environmentForExecutable:(NSString*)executable;

/// The error to show when the program ended badly. `message` is what it said (its standard error, or the error in its output).
-(NSError*)errorForMessage:(NSString*)message exitStatus:(int)status model:(NSString*)model effort:(NSString*)effort;
/// Same for a program that could not be started.
-(NSError*)errorForLaunchFailure:(NSString*)reason;
/// The part of what a program printed on its standard error that says what went wrong: the lines about an error, otherwise the
/// last ones. Cut, with anything that looks like a key taken out.
+(NSString*)gistOfErrorOutput:(NSString*)text;

@end

/// Cuts the output of a program into the pieces of the answer.
@interface AIAgentOutputParser : NSObject
-(instancetype)initWithFormat:(AIAgentOutput)format;
/// Bytes as they arrive, cut anywhere (a Vietnamese letter can be cut in two). Returns the text completed by them.
-(NSArray<NSString*>*)feed:(NSData*)data;
/// The output ended: what was held back, and for stream-json the text of the final message when no piece of the answer was seen.
-(NSArray<NSString*>*)finish;
/// `codex exec --json`: the thread that was started (the folder of its pictures is named after it), nil until the first line.
@property (nonatomic, readonly, copy) NSString* threadIdentifier;
/// The message of the error that the output carried (stream-json has a final message that says it failed), nil when none.
@property (nonatomic, readonly, copy) NSString* errorMessage;
/// What came on the output that was not the answer (a line that is not JSON...), for the message of an error.
@property (nonatomic, readonly, copy) NSString* leftover;
@end
