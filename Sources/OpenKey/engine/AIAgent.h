//
//  AIAgent.h
//  VOpenKey AI, portable
//
//  The AI agents that run as a program (Codex of OpenAI, Claude Code of Anthropic, Antigravity of Google) used as the AI of the
//  assistant, for whoever prefers not to keep an API key or to run a model on the computer. Each of them is signed in by itself, so
//  VOpenKey AI never sees an account, a token or a key: it only runs the program. macOS has the same rules in AIAgentCLI.m.
//
//  An agent is made to work on files and run commands, the assistant only needs it to write text. So every request is run in a
//  folder of its own that is empty and private, with the tools of the agent and what the user set up for it (hooks, servers, rules)
//  turned off as far as each program allows, with the text of the request on the standard input where the program takes it there (not
//  in the arguments, where every program can list it; Antigravity only takes it as an argument), and with a line in the prompt saying
//  that nothing but text is wanted.
//
//  This file knows, for each program, what its models are, what to pass to it and how to read what it prints. Finding the program,
//  starting it and the sentences the user reads are the platform's. Plain C++11, UTF-8, ASCII source.
//
#ifndef AIAgent_h
#define AIAgent_h

#include "AIProtocol.h"
#include <string>
#include <utility>
#include <vector>

namespace vai {
namespace agent {

enum class Kind { Codex, Claude, Antigravity };

/// What the program prints on its standard output.
enum class Output {
    Plain,        //the answer itself
    ClaudeJson,   //one JSON object per line (stream-json): text deltas, then a result
    CodexJson     //one JSON object per line (`codex exec --json`): the thread, the messages of the agent, the end
};

struct Agent {
    Kind kind;
    std::string providerId;      //"codex-cli": the id of the provider in the settings
    std::string command;         //"codex", "claude", "agy": the name of the program
    std::string displayName;     //"Codex CLI"
    std::string loginHint;       //what to type in a terminal to sign in
    std::string installHint;     //how to install it, empty when unknown
    Output output;
    bool promptInArguments;      //the request goes in the arguments (Antigravity), not on the standard input
    bool keepsConversations;     //it saves every request as a conversation of its own and cannot be told not to (Antigravity)
    bool canMakeImages;          //it can make pictures (Codex, with its imagegen skill)
};

/// nullptr for a provider that is not an agent program.
const Agent* find(const std::string& providerId);
const std::vector<Agent>& all();

/// Saved as the thinking level when the user wants what the program does by itself: no level is passed to it.
extern const char* const kEffortProgramDefault;   //"default"

// --- models and thinking levels -----------------------------------------------------------------------------------------

struct Model {
    std::string id;                                 //what the program takes after --model
    std::string name;                               //as shown in a menu
    std::string summary;                            //one line about it, empty when there is none
    std::vector<std::string> efforts;               //the levels it accepts, lowest first; empty when not known
    std::string defaultEffort;                      //what the program uses when it is not told; empty when not known
    std::vector<std::pair<std::string, std::string> > variants;   //for a model whose levels are models of the program (Antigravity): level -> model to ask for
    bool light;                                     //fast and cheap, good enough for writing, translating and correcting
    Model() : light(false) {}
    const std::string* variant(const std::string& level) const;
};

/// Claude Code has no command that lists its models: it takes these names for "the latest of the family".
std::vector<Model> claudeModels();
/// The JSON of `codex debug models`: by priority, what is for the program itself left out, nothing twice. Not a catalog gives nothing.
std::vector<Model> modelsFromCodexCatalog(const std::string& json);
/// What `agy models` prints: "identifier<TAB>name" lines, the entries that only differ by their level made one model with levels.
std::vector<Model> modelsFromAntigravityList(const std::string& text);
/// The model with this id among `models`, nullptr when it is not there.
const Model* findModel(const std::vector<Model>& models, const std::string& id);
/// The levels most programs know, lowest first.
std::vector<std::string> commonEfforts();

/// What to pass after --model when the user chose `saved` ("" = choose for me: a light model of the list, nothing when the list is not
/// known and the program may use its own default).
std::string modelToPass(const Agent& agent, const std::string& saved, const std::vector<Model>& models);
/// The thinking level to pass: nothing for kEffortProgramDefault, the one the user chose when the model takes it, otherwise the fastest.
std::string effortToPass(const Agent& agent, const std::string& savedEffort, const std::string& model, const std::vector<Model>& models);
/// Both, resolved: for a model whose levels are models of the program the model of the level is given and no level besides.
void resolve(const Agent& agent, const std::string& savedModel, const std::string& savedEffort, const std::vector<Model>& models,
             std::string& modelArgument, std::string& effortArgument);

/// A name that can be given to a program as the value of --model: not empty, not too long, not starting with a dash (it would be taken
/// for a flag), no control characters. A level goes into an argument that Codex reads as TOML: letters, digits, _ and -, starting with a letter.
bool isPlausibleModelName(const std::string& name);
bool isPlausibleEffort(const std::string& effort);

// --- one request --------------------------------------------------------------------------------------------------------

/// Everything said to the agent besides the request: that nothing but text is wanted, and the instruction of the user.
std::string instruction(const std::string& systemPrompt);

/// The arguments of one request (without the name of the program). `model` and `effort` are what resolve() gave; empty = not passed.
/// For Antigravity the prompt is the last argument.
std::vector<std::string> arguments(const Agent& agent, const std::string& model, const std::string& effort, const std::string& systemPrompt,
                                   const std::string& prompt, const std::string& workDirectory);
/// What goes on the standard input. False when the prompt is in the arguments.
bool standardInput(const Agent& agent, const std::string& prompt, const std::string& systemPrompt, std::string& out);
/// The arguments that list the models of the program, and whether it has such a command (Claude has not).
bool listModelsArguments(const Agent& agent, std::vector<std::string>& out);

// --- pictures (Codex) ---------------------------------------------------------------------------------------------------

/// "Use $imagegen skill to create picture {prompt}, follow our design system." Codex makes poor pictures unless its imagegen skill is named in
/// the request, so the request is put in a sentence that names it; the user can change the sentence in the settings.
std::string defaultImagePromptTemplate();
/// `request` goes where {prompt} is in `templateText` (once, in one pass: what was asked is not read again as a template); a template without
/// {prompt} gets the request after it; an empty template is the default one. Blanks around both are dropped.
std::string imagePromptForRequest(const std::string& request, const std::string& templateText);
/// The arguments of a picture: the same locked-down run as a text, with the events as JSON (they say which thread it was, and so where the picture
/// is). The request is on the standard input as it is (no rule about texts in front, it would forbid the picture): see imageStandardInput.
std::vector<std::string> imageArguments(const Agent& agent, const std::string& model, const std::string& effort, const std::string& workDirectory);
std::string imageStandardInput(const std::string& prompt);
/// Where Codex keeps what it makes (under generated_images): $CODEX_HOME when it is set, else <home>/.codex. `separator` is the one of the system.
std::string codexHomeFolder(const std::string& codexHomeVariable, const std::string& homeFolder, char separator);
/// The name of a thread comes out of a program: only what such a name is made of may go into a path (1 to 80 of letters, digits, - and _).
bool isSafeThreadId(const std::string& id);
bool isPictureFileName(const std::string& name);   //png, jpg, jpeg, webp, gif
/// A file in a folder under generated_images, with when it was last written (any unit, as long as `since` has the same).
struct PictureEntry {
    std::string folder;
    std::string name;
    long long modified;
};
/// Which of `entries` is the picture of a run, -1 when none: the newest picture in the folder of its thread (when the thread id is safe), otherwise
/// the newest picture written since the run started (`hasSince`; no leeway: the picture of the run before must not be taken for this one), otherwise
/// nothing: without a time there is no guessing.
int choosePicture(const std::string& threadId, const std::vector<PictureEntry>& entries, long long since, bool hasSince);

// --- what comes back ----------------------------------------------------------------------------------------------------

/// What a program that thinks it is in a terminal adds to its text: colours and the like.
std::string withoutEscapes(const std::string& text);

/// Cuts the output of a program into the pieces of the answer.
class OutputParser {
public:
    explicit OutputParser(Output format);
    /// Bytes as they arrive, cut anywhere (a Vietnamese letter can be cut in two). Returns the text completed by them.
    std::vector<std::string> feed(const std::string& bytes);
    /// The output ended: what was held back, and for stream-json the text of the final message when no piece of the answer was seen.
    std::vector<std::string> finish();
    /// The message of the error that the output carried (stream-json has a final message that says it failed); empty when none.
    const std::string& errorMessage() const { return errorMessage_; }
    /// What came on the output that was not the answer (a line that is not JSON...), for the message of an error.
    const std::string& leftover() const { return leftover_; }
    /// `codex exec --json`: the thread that was started; empty until the first line.
    const std::string& threadId() const { return threadId_; }

private:
    Output format_;
    std::string pending_;        //plain: the start of a letter whose end has not come; json: the line that is not complete yet
    std::string fallback_;       //json: the whole text of the messages, used when no piece arrived in pieces
    std::string resultText_;
    std::string errorMessage_;
    std::string leftover_;
    std::string threadId_;
    bool sawPiece_;
    void takeLine(const std::string& line, std::vector<std::string>& pieces);
};

/// The part of what a program printed on its standard error that says what went wrong: the lines about an error, otherwise the last
/// ones. Cut, with anything that looks like a key taken out.
std::string gistOfErrorOutput(const std::string& text);

/// The error to show when the program ended badly. `message` is what it said (its standard error, or the error in its output); the
/// detail of the error is the gist of it, the status is the exit status. Codes: Effort, Model, Login, OldProgram, RateLimit, Network,
/// otherwise Server.
Error errorForMessage(const Agent& agent, const std::string& message, int exitStatus, const std::string& model, const std::string& effort);

// --- starting a program on Windows --------------------------------------------------------------------------------------

/// One argument as the Microsoft C runtime (and CommandLineToArgvW) reads it back: quoted when it has a blank or a quote, the quotes and
/// the backslashes in front of them escaped. UTF-8 in, UTF-8 out.
std::string quoteArgument(const std::string& argument);
/// The program and its arguments as one command line.
std::string commandLine(const std::string& program, const std::vector<std::string>& arguments);
/// A script (.cmd, .bat) is run by cmd.exe, which reads &, |, <, >, ^, % and ! as its own and ends the command at a line break:
/// whether every argument is free of them. A program (.exe) is started as it is and has no such limit.
bool safeForCommandShell(const std::vector<std::string>& arguments);

} // namespace agent
} // namespace vai

#endif /* AIAgent_h */
