//
//  The agent programs (Codex, Claude Code, Antigravity) as the AI of the assistant: the models they list, what is passed to them, how
//  their output is read and what their errors mean. The cases follow macOS' ai_agent_test.m (the list of `agy models` is what the real
//  program printed there). Also the command line that Windows starts them with. ASCII-only source.
//
#include "../AIAgent.h"
#include "../MiniJson.h"
#include <cstdio>
#include <string>
#include <vector>

using namespace vai;
using namespace vai::agent;

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { std::printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

typedef std::vector<std::string> List;

static List ids(const std::vector<Model>& models) {
    List out;
    for (size_t i = 0; i < models.size(); i++)
        out.push_back(models[i].id);
    return out;
}

static List listOf(const char* a = NULL, const char* b = NULL, const char* c = NULL, const char* d = NULL, const char* e = NULL, const char* f = NULL) {
    List out;
    const char* all[] = {a, b, c, d, e, f};
    for (size_t i = 0; i < 6 && all[i] != NULL; i++)
        out.push_back(all[i]);
    return out;
}

static bool has(const List& list, const std::string& value) {
    for (size_t i = 0; i < list.size(); i++)
        if (list[i] == value)
            return true;
    return false;
}

//the argument that follows a flag
static std::string after(const List& args, const std::string& flag) {
    for (size_t i = 0; i + 1 < args.size(); i++)
        if (args[i] == flag)
            return args[i + 1];
    return "<none>";
}

static const char* const kCatalog =
    "{\"models\": ["
    "{\"slug\": \"big\", \"display_name\": \"Big\", \"description\": \"Frontier intelligence for the most demanding work.\", \"visibility\": \"list\", \"priority\": 3,"
    " \"default_reasoning_level\": \"low\", \"supported_reasoning_levels\": [{\"effort\": \"low\"}, {\"effort\": \"high\"}, {\"effort\": \"ultra\"}]},"
    "{\"slug\": \"work\", \"display_name\": \"Work\", \"description\": \"Latest workhorse model for coding and everyday work.\", \"visibility\": \"list\", \"priority\": 1,"
    " \"supported_reasoning_levels\": [{\"effort\": \"low\"}, {\"effort\": \"medium\"}]},"
    "{\"slug\": \"mini\", \"display_name\": \"Mini\", \"description\": \"Fast and affordable model for easier tasks.\", \"visibility\": \"list\", \"priority\": 4,"
    " \"default_reasoning_level\": \"medium\", \"supported_reasoning_levels\": [\"minimal\", \"low\", \"medium\"]},"
    "{\"slug\": \"old-mini\", \"description\": \"Older fast and efficient model.\", \"visibility\": \"list\", \"priority\": 9},"
    "{\"slug\": \"hidden\", \"description\": \"Automatic review, fast.\", \"visibility\": \"hide\", \"priority\": 0},"
    "{\"slug\": \"\", \"description\": \"no name\"}, {\"display_name\": \"no slug\"}, 42, \"text\", null,"
    "{\"slug\": \"mini\", \"description\": \"a duplicate\"}]}";

static const char* const kRealList =
    "gemini-4-argon-medium\tGemini 4 Argon (Medium)\ngemini-4-argon-high\tGemini 4 Argon (High)\ngemini-4-argon-low\tGemini 4 Argon (Low)\n"
    "gemini-3.8-flash-high\tGemini 3.8 Flash (High)\ngemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)\ngemini-3.8-flash-low\tGemini 3.8 Flash (Low)\n"
    "claude-opus-5-5-low\tClaude Opus 5.5 (Low)\nclaude-opus-5-5-medium\tClaude Opus 5.5 (Medium)\nclaude-opus-5-5-high\tClaude Opus 5.5 (High)\n"
    "claude-sonnet-5-5-low\tClaude Sonnet 5.5 (Low)\nclaude-sonnet-5-5-medium\tClaude Sonnet 5.5 (Medium)\nclaude-sonnet-5-5-high\tClaude Sonnet 5.5 (High)\n"
    "gpt-oss-120b-medium\tGPT-OSS 120B (Medium)\n";

static void testAgents() {
    std::printf("-- the agents\n");
    const Agent* codex = find("codex-cli");
    const Agent* claude = find("claude-cli");
    const Agent* agy = find("agy-cli");
    CHECK(codex && claude && agy && !find("openai") && !find("") && all().size() == 3);
    CHECK(codex->command == "codex" && claude->command == "claude" && agy->command == "agy");
    CHECK(codex->output == Output::Plain && claude->output == Output::ClaudeJson && agy->output == Output::Plain);
    CHECK(!codex->promptInArguments && !claude->promptInArguments && agy->promptInArguments && agy->keepsConversations && !codex->keepsConversations);
    //the providers of the settings know them
    const Provider* provider = findProvider("claude-cli");
    CHECK(provider && provider->protocol == Protocol::Agent && !provider->needsKey && provider->baseUrl.empty());
    CHECK(findProvider("codex-cli") && findProvider("agy-cli") && findProvider("openai")->protocol == Protocol::OpenAI);
    //every agent is a provider and every provider that is an agent has its entry here
    for (size_t i = 0; i < providers().size(); i++)
        CHECK((providers()[i].protocol == Protocol::Agent) == (find(providers()[i].id) != NULL));
}

static void testCatalog() {
    std::printf("-- catalog of Codex\n");
    std::vector<Model> models = modelsFromCodexCatalog(kCatalog);
    //by priority, what is only for the program itself left out, nothing twice
    CHECK(ids(models) == listOf("work", "big", "mini", "old-mini"));
    const Model* mini = findModel(models, "mini");
    CHECK(mini && mini->name == "Mini" && mini->light && mini->defaultEffort == "medium");
    CHECK(mini && mini->efforts == listOf("minimal", "low", "medium")); //levels given as plain strings too
    CHECK(!findModel(models, "big")->light);                              //"frontier", "demanding": not for everyday text
    CHECK(!findModel(models, "work")->light);
    CHECK(!findModel(models, "old-mini")->light);                         //an older one is not what to start with
    CHECK(findModel(models, "old-mini")->efforts.empty() && findModel(models, "old-mini")->name == "old-mini");
    CHECK(findModel(models, "hidden") == NULL);
    //words, not pieces of words: "mini" is not in "Gemini" or "minimal", "fast" is not in "breakfast"
    std::vector<Model> worded = modelsFromCodexCatalog(
        "{\"models\": [{\"slug\": \"a\", \"description\": \"Gemini based, minimal and breakfast ready\", \"visibility\": \"list\"},"
        "{\"slug\": \"b\", \"description\": \"A mini model.\", \"visibility\": \"list\"},"
        "{\"slug\": \"c\", \"description\": \"Quick, cheap answers\", \"visibility\": \"list\"}]}");
    CHECK(worded.size() == 3 && !findModel(worded, "a")->light && findModel(worded, "b")->light && findModel(worded, "c")->light);
    //what is not a catalog is nothing, not a crash
    CHECK(modelsFromCodexCatalog("").empty() && modelsFromCodexCatalog("not json").empty() && modelsFromCodexCatalog("{\"models\": \"x\"}").empty());
    CHECK(modelsFromCodexCatalog("[{\"slug\": \"as-array\"}]").size() == 1); //a bare list too
    CHECK(modelsFromCodexCatalog("{\"models\": [{\"slug\": 5}, {\"slug\": []}]}").empty());
}

static void testAntigravityList() {
    std::printf("-- list of Antigravity\n");
    std::vector<Model> models = modelsFromAntigravityList(kRealList);
    //one model for the entries that are its levels, in the order of the program
    CHECK(ids(models) == listOf("gemini-4-argon", "gemini-3.8-flash", "claude-opus-5-5", "claude-sonnet-5-5", "gpt-oss-120b"));
    const Model* flash = findModel(models, "gemini-3.8-flash");
    CHECK(flash && flash->name == "Gemini 3.8 Flash" && flash->light);
    CHECK(flash && flash->efforts == listOf("low", "medium", "high")); //lowest first, whatever the order of the list
    CHECK(flash && *flash->variant("low") == "gemini-3.8-flash-low" && *flash->variant("high") == "gemini-3.8-flash-high" && flash->variant("max") == NULL);
    CHECK(!findModel(models, "gemini-4-argon")->light && !findModel(models, "claude-opus-5-5")->light);
    CHECK(findModel(models, "gpt-oss-120b")->efforts == listOf("medium"));
    CHECK(findModel(models, "gpt-oss-120b")->name == "GPT-OSS 120B");

    //a status line on the output, a model without levels, one whose name does not match its identifier (so they are not levels)
    models = modelsFromAntigravityList("Fetching available models...\nplain-model\tA Model Without Levels\nsome-low\tSomething Else\nx-high\tX (Low)\ny-high\tY (High)\n");
    CHECK(ids(models) == listOf("plain-model", "some-low", "x-high", "y"));
    CHECK(findModel(models, "y") && findModel(models, "y")->efforts == listOf("high") && findModel(models, "plain-model")->efforts.empty());
    //no tabs at all: a column of identifiers, bullets and headings dropped, nothing twice
    models = modelsFromAntigravityList("Models:\n- model-a  Model A\n\xE2\x80\xA2 model-b\n# comment\nmodel-a\n");
    CHECK(ids(models) == listOf("model-a", "model-b") && findModel(models, "model-a")->name == "Model A");
    CHECK(modelsFromAntigravityList("").empty() && modelsFromAntigravityList("\x1B[2K\x1B[1G\n").empty());
    //colours around the lines
    models = modelsFromAntigravityList("\x1B[32mm-1\x1B[0m\tOne\n");
    CHECK(ids(models) == listOf("m-1"));
}

static void testChoices() {
    std::printf("-- model and level\n");
    const Agent& codex = *find("codex-cli");
    const Agent& claude = *find("claude-cli");
    const Agent& agy = *find("agy-cli");
    std::vector<Model> models = modelsFromCodexCatalog(kCatalog);
    std::vector<Model> none;
    CHECK(modelToPass(codex, "", models) == "mini");                       //choose for me: the first light model
    CHECK(modelToPass(codex, "  big ", models) == "big");
    CHECK(modelToPass(codex, "typed-by-hand", none) == "typed-by-hand");
    CHECK(modelToPass(codex, "", none).empty());                           //the catalog is not known: the program's own default
    CHECK(modelToPass(claude, "", none) == "haiku" && modelToPass(claude, "opus", none) == "opus");
    CHECK(modelToPass(agy, "", none).empty() && modelToPass(agy, "Gemini Flash (Low)", none) == "Gemini Flash (Low)");
    CHECK(claudeModels().size() == 4 && claudeModels()[0].id == "haiku" && claudeModels()[0].light && !claudeModels()[1].light);

    //the level: "choose for me" is the fast one the model accepts
    CHECK(effortToPass(codex, "", "mini", models) == "low");
    CHECK(effortToPass(codex, "", "big", models) == "low");                //big accepts low
    CHECK(effortToPass(codex, "high", "big", models) == "high");
    CHECK(effortToPass(codex, "medium", "mini", models) == "medium");
    CHECK(effortToPass(codex, "ultra", "mini", models) == "low");          //not accepted by this model: back to automatic
    CHECK(effortToPass(codex, kEffortProgramDefault, "mini", models).empty()); //the program's own
    CHECK(effortToPass(codex, "", "", none) == "low");                     //model not known: the common levels
    CHECK(effortToPass(claude, "", "haiku", none) == "low" && effortToPass(claude, "max", "opus", none) == "max");
    CHECK(effortToPass(agy, "", "", none).empty());                        //a model that is not known keeps its own level
    CHECK(effortToPass(agy, "high", "", none) == "high");
    std::vector<Model> noLow = modelsFromCodexCatalog("{\"models\": [{\"slug\": \"m\", \"visibility\": \"list\", \"supported_reasoning_levels\": [\"medium\", \"high\"]}]}");
    CHECK(effortToPass(codex, "", "m", noLow) == "medium");                //no "low": the lowest it has

    //Antigravity with the list it really gave: a light model, and its levels are models
    std::vector<Model> list = modelsFromAntigravityList(kRealList);
    CHECK(modelToPass(agy, "", list) == "gemini-3.8-flash");
    CHECK(effortToPass(agy, "", "gemini-3.8-flash", list) == "low");
    CHECK(effortToPass(agy, "", "gpt-oss-120b", list) == "medium");        //its only level
    CHECK(effortToPass(agy, "xhigh", "gemini-3.8-flash", list) == "low");  //not one of its levels: automatic
    std::string model, effort;
    resolve(agy, "", "", list, model, effort);                             //nothing chosen: the light model, its fast level
    CHECK(model == "gemini-3.8-flash-low" && effort.empty());              //the level is in the name, nothing else is passed
    resolve(agy, "gemini-3.8-flash", "high", list, model, effort);
    CHECK(model == "gemini-3.8-flash-high" && effort.empty());
    resolve(agy, "claude-opus-5-5", "", list, model, effort);
    CHECK(model == "claude-opus-5-5-low" && effort.empty());
    resolve(agy, "claude-sonnet-5-5", kEffortProgramDefault, list, model, effort); //"the program's own": a medium one, it has to be some
    CHECK(model == "claude-sonnet-5-5-medium" && effort.empty());
    resolve(agy, "gpt-oss-120b", "", list, model, effort);
    CHECK(model == "gpt-oss-120b-medium" && effort.empty());
    resolve(agy, "typed-by-hand", "", list, model, effort);                //not in the list: passed as it is
    CHECK(model == "typed-by-hand" && effort.empty());
    resolve(agy, "typed-by-hand", "high", list, model, effort);
    CHECK(model == "typed-by-hand" && effort == "high");
    resolve(agy, "gemini-3.8-flash-high", "", list, model, effort);        //the full name of a level, typed
    CHECK(model == "gemini-3.8-flash-high" && effort.empty());
    resolve(agy, "", "", none, model, effort);                             //no list: the program's own
    CHECK(model.empty() && effort.empty());
    //the others have no variants: what was chosen is what is passed
    resolve(codex, "", "", models, model, effort);
    CHECK(model == "mini" && effort == "low");
    resolve(claude, "", "", none, model, effort);
    CHECK(model == "haiku" && effort == "low");

    CHECK(isPlausibleModelName("gpt-5-mini") && isPlausibleModelName("Gemini Flash (Low)") && !isPlausibleModelName("") && !isPlausibleModelName("-x") &&
          !isPlausibleModelName("a\nb") && !isPlausibleModelName(std::string(121, 'a')));
    CHECK(isPlausibleEffort("low") && isPlausibleEffort("xhigh") && !isPlausibleEffort("") && !isPlausibleEffort("-low") && !isPlausibleEffort("Low") &&
          !isPlausibleEffort("lo\"w") && !isPlausibleEffort("a b") && !isPlausibleEffort(std::string(17, 'a')));
}

static void testArguments() {
    std::printf("-- what is passed\n");
    const Agent& codex = *find("codex-cli");
    const Agent& claude = *find("claude-cli");
    const Agent& agy = *find("agy-cli");
    List args = arguments(codex, "mini", "low", "Be brief.", "the request", "C:\\work dir");
    CHECK(args.front() == "exec" && args.back() == "-");
    CHECK(has(args, "--ignore-user-config") && has(args, "--ignore-rules") && has(args, "--ephemeral") && has(args, "--skip-git-repo-check"));
    CHECK(after(args, "-s") == "read-only" && after(args, "--disable") == "shell_tool" && after(args, "-C") == "C:\\work dir" && after(args, "--color") == "never");
    CHECK(after(args, "-m") == "mini" && after(args, "-c") == "model_reasoning_effort=\"low\"");
    CHECK(!has(args, "the request") && !has(args, "Be brief."));              //the request is on the standard input
    args = arguments(codex, "", "", "", "x", "");
    CHECK(!has(args, "-m") && !has(args, "-c") && after(args, "-C") == ".");
    args = arguments(codex, "-evil", "Low\"", "", "x", "d");                   //what cannot be a model or a level is not passed
    CHECK(!has(args, "-m") && !has(args, "-c") && !has(args, "-evil"));

    args = arguments(claude, "haiku", "low", "Be brief.", "the request", "d");
    CHECK(args.front() == "-p" && has(args, "--safe-mode") && has(args, "--no-session-persistence") && has(args, "--include-partial-messages"));
    CHECK(after(args, "--tools").empty() && after(args, "--output-format") == "stream-json" && after(args, "--model") == "haiku" && after(args, "--effort") == "low");
    CHECK(after(args, "--system-prompt") == instruction("Be brief.") && !has(args, "the request"));

    args = arguments(agy, "gemini-3.8-flash-low", "", "Be brief.", "the request", "d");
    CHECK(after(args, "--model") == "gemini-3.8-flash-low" && !has(args, "--effort") && after(args, "--output-format") == "text");
    CHECK(args.size() >= 2 && args[args.size() - 2] == "-p" && args.back() == instruction("Be brief.") + "\n\nthe request"); //the prompt is the last argument
    args = arguments(agy, "", "", "", "-rm", "d");
    CHECK(args.back() == instruction("") + "\n\n-rm" && args.back()[0] != '-');   //a request that looks like a flag starts with our own text

    std::string input;
    CHECK(standardInput(codex, "the request", "Be brief.", input) && input == instruction("Be brief.") + "\n\nthe request");
    CHECK(standardInput(claude, "the request", "Be brief.", input) && input == "the request");
    CHECK(!standardInput(agy, "the request", "Be brief.", input) && input.empty());
    CHECK(instruction("").find("no tools") != std::string::npos && instruction("X").find("\n\nX") != std::string::npos);

    List listing;
    CHECK(listModelsArguments(codex, listing) && listing == listOf("debug", "models"));
    CHECK(listModelsArguments(agy, listing) && listing == listOf("models"));
    CHECK(!listModelsArguments(claude, listing) && listing.empty());
}

//the output, cut in pieces of `chunk` bytes
static std::string readAll(Output format, const std::string& data, size_t chunk, std::string* errorMessage = NULL, std::string* thread = NULL,
                           std::string* leftover = NULL) {
    OutputParser parser(format);
    std::string all;
    for (size_t i = 0; i < data.size(); i += chunk) {
        List pieces = parser.feed(data.substr(i, chunk));
        for (size_t k = 0; k < pieces.size(); k++)
            all += pieces[k];
    }
    List rest = parser.finish();
    for (size_t k = 0; k < rest.size(); k++)
        all += rest[k];
    if (errorMessage) *errorMessage = parser.errorMessage();
    if (thread) *thread = parser.threadId();
    if (leftover) *leftover = parser.leftover();
    return all;
}

static std::string delta(const char* kind, const char* key, const std::string& text) {
    return std::string("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"") + kind + "\",\"" + key +
           "\":" + vjson::write(vjson::Value::string(text), false) + "}}}\n";
}

static void testOutput() {
    std::printf("-- reading the output\n");
    //plain text, cut anywhere, byte by byte: a letter of Vietnamese or an emoji cut in two is still one letter
    std::string text = "Ti\xE1\xBA\xBF" "ng Vi\xE1\xBB\x87" "t \xE2\x9D\xA4\xEF\xB8\x8F \xF0\x9F\x98\x80 \xC4\x91\xE1\xBA\xB9" "p\nD\xC3\xB2" "ng hai";
    for (size_t chunk = 1; chunk <= 7; chunk++)
        CHECK(readAll(Output::Plain, text, chunk) == text);
    //colours of a program that thinks it is in a terminal
    CHECK(readAll(Output::Plain, "\x1B[1mXin\x1B[0m \x1B[38;5;12mch\xC3\xA0o\x1B[0m\x1B]0;title\x07!", 1000) == "Xin ch\xC3\xA0o!");
    CHECK(withoutEscapes("a\x1B[0mb") == "ab" && withoutEscapes("plain") == "plain" && withoutEscapes("\x1B]0;t\x1B\\x") == "x");
    //half of a letter at the very end is nothing
    CHECK(readAll(Output::Plain, std::string("ok\xE1\xBA", 4), 1000) == "ok");

    //Claude: the pieces of the answer, not the thinking, nothing twice
    std::string stream = "{\"type\":\"system\",\"subtype\":\"init\"}\n";
    stream += delta("thinking_delta", "thinking", "hmm, let me think");
    stream += delta("text_delta", "text", "Xin ch\xC3\xA0o");
    stream += delta("text_delta", "text", ", th\xE1\xBA\xBF gi\xE1\xBB\x9B" "i");
    stream += "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Xin ch\xC3\xA0o, th\xE1\xBA\xBF gi\xE1\xBB\x9B" "i\"}]}}\n";
    stream += "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"Xin ch\xC3\xA0o, th\xE1\xBA\xBF gi\xE1\xBB\x9B" "i\"}\n";
    std::string error;
    for (size_t chunk = 1; chunk <= 9; chunk += 4) {
        std::string got = readAll(Output::ClaudeJson, stream, chunk, &error);
        CHECK(got == "Xin ch\xC3\xA0o, th\xE1\xBA\xBF gi\xE1\xBB\x9B" "i" && error.empty());
    }
    //no pieces: the message that completes it, or the result
    CHECK(readAll(Output::ClaudeJson, "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"whole\"}]}}\n", 5) == "whole");
    CHECK(readAll(Output::ClaudeJson, "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"from result\"}", 5) == "from result"); //no line feed at the end
    //a failure says why
    readAll(Output::ClaudeJson, "{\"type\":\"result\",\"subtype\":\"error_during_execution\",\"is_error\":true,\"result\":\"Not logged in\"}\n", 3, &error);
    CHECK(error == "Not logged in");
    readAll(Output::ClaudeJson, "{\"type\":\"result\",\"subtype\":\"error_max_turns\",\"errors\":[\"one\",\"two\"]}\n", 3, &error);
    CHECK(error == "one two");
    readAll(Output::ClaudeJson, "{\"type\":\"result\",\"is_error\":true}\n", 3, &error);
    CHECK(error == "error");
    readAll(Output::ClaudeJson, "{\"type\":\"assistant\",\"message\":{\"error\":\"authentication_failed\",\"content\":[{\"type\":\"text\",\"text\":\"Please run /login\"}]}}\n", 3, &error);
    CHECK(error == "Please run /login");
    //what is not the shape it should be is skipped
    std::string leftover;
    CHECK(readAll(Output::ClaudeJson, "{\"type\": 5}\n{\"type\":\"stream_event\",\"event\":\"x\"}\n{\"type\":\"stream_event\",\"event\":{\"delta\":[]}}\nWarning: something\n[1]\n",
                  4, &error, NULL, &leftover).empty());
    CHECK(leftover.find("Warning: something") != std::string::npos && leftover.find("[1]") != std::string::npos);

    //Codex --json: the thread, the messages of the agent one after the other, how it ended
    std::string events = "{\"type\":\"thread.started\",\"thread_id\":\"01a1539b-a6e8\"}\n{\"type\":\"turn.started\"}\n"
                         "{\"type\":\"item.completed\",\"item\":{\"type\":\"reasoning\",\"text\":\"thinking\"}}\n"
                         "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"First\"}}\n"
                         "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Second\"}}\n{\"type\":\"turn.completed\"}\n";
    std::string thread;
    CHECK(readAll(Output::CodexJson, events, 7, &error, &thread) == "First\n\nSecond" && thread == "01a1539b-a6e8" && error.empty());
    readAll(Output::CodexJson, "{\"type\":\"error\",\"message\":\"first reason\"}\n{\"type\":\"turn.failed\",\"error\":{\"message\":\"second\"}}\n", 6, &error);
    CHECK(error == "first reason");                                         //the first reason stays
    readAll(Output::CodexJson, "{\"type\":\"turn.failed\",\"error\":{}}\n", 6, &error);
    CHECK(error == "error");
}

static void testErrors() {
    std::printf("-- errors\n");
    const Agent& codex = *find("codex-cli");
    CHECK(gistOfErrorOutput("").empty());
    //the lines that start with "error" are what the program said; a log may put a time in front
    std::string gist = gistOfErrorOutput("starting up\n2026-11-04T10:00:00Z ERROR: the thing broke\nusage: codex exec [options]\nretrying");
    CHECK(gist == "2026-11-04T10:00:00Z ERROR: the thing broke");
    CHECK(gistOfErrorOutput("Error: one\nError: two\nError: three\nError: four") == "Error: two Error: three Error: four"); //the last three
    //a line that starts with "error" wins over lines that only mention one (the request may have been echoed back)
    CHECK(gistOfErrorOutput("you typed: invalid login quota\nError: the real failure\nsee the unknown limit above") == "Error: the real failure");
    CHECK(gistOfErrorOutput("errors are counted below\nfatal: cannot go on") == "fatal: cannot go on");       //"errors" is not the word "error"
    CHECK(gistOfErrorOutput("hello\nyou are not logged in\nbye") == "you are not logged in");     //only mentions
    CHECK(gistOfErrorOutput("plain\nlines\nof\ntext") == "lines of text");                          //neither: the last lines
    CHECK(gistOfErrorOutput("\x1B[31mError: red\x1B[0m") == "Error: red");
    CHECK(gistOfErrorOutput("Error: " + std::string(600, 'x')).size() <= 420 + 3);                  //cut
    CHECK(gistOfErrorOutput("Error: key sk-abcdefghijklmnopqrstuvwxyz0123456789 leaked").find("sk-abcdefgh") == std::string::npos); //a key is taken out
    CHECK(gistOfErrorOutput("errors in tests: none\n").size() > 0);                                  //"errors" is no start of an error but is shown as the last line

    CHECK(errorForMessage(codex, "Error: unsupported value for reasoning effort", 1, "m", "xhigh").code == ErrorCode::Effort);
    CHECK(errorForMessage(codex, "Error: unsupported value for reasoning effort", 1, "m", "").code != ErrorCode::Effort);      //no level was passed
    CHECK(errorForMessage(codex, "Error: model 'x' does not exist", 1, "x", "").code == ErrorCode::Model);
    CHECK(errorForMessage(codex, "Error: not logged in. Run codex login", 1, "", "").code == ErrorCode::Login);
    CHECK(errorForMessage(codex, "Error: 401 Unauthorized", 1, "", "").code == ErrorCode::Login);
    CHECK(errorForMessage(codex, "error: unexpected argument '--safe-mode' found", 2, "", "").code == ErrorCode::OldProgram);
    CHECK(errorForMessage(codex, "Error: rate limit reached, try later", 1, "", "").code == ErrorCode::RateLimit);
    CHECK(errorForMessage(codex, "Error: getaddrinfo ENOTFOUND api.openai.com", 1, "", "").code == ErrorCode::Network);
    Error other = errorForMessage(codex, "Error: something odd", 3, "", "");
    CHECK(other.code == ErrorCode::Server && other.detail == "Error: something odd" && other.status == 3);
    Error silent = errorForMessage(codex, "", 9, "", "");
    CHECK(silent.code == ErrorCode::Server && silent.detail.empty() && silent.status == 9);
}

//what CommandLineToArgvW and the C runtime make of a command line (the rules of Microsoft), to see that what was quoted reads back
static List parseCommandLine(const std::string& line) {
    List args;
    size_t i = 0;
    for (;;) {
        while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) i++;
        if (i >= line.size())
            break;
        std::string arg;
        bool inQuotes = false;
        while (i < line.size()) {
            size_t backslashes = 0;
            while (i < line.size() && line[i] == '\\') { backslashes++; i++; }
            if (i < line.size() && line[i] == '"') {
                arg.append(backslashes / 2, '\\');
                if (backslashes % 2 == 1) { arg.push_back('"'); i++; }
                else { inQuotes = !inQuotes; i++; }
            } else {
                arg.append(backslashes, '\\');
                if (i >= line.size() || (!inQuotes && (line[i] == ' ' || line[i] == '\t')))
                    break;
                arg.push_back(line[i++]);
            }
        }
        args.push_back(arg);
    }
    return args;
}

static void testCommandLine() {
    std::printf("-- the command line of Windows\n");
    List tricky;
    tricky.push_back("");
    tricky.push_back("plain");
    tricky.push_back("a b");
    tricky.push_back("a\"b");
    tricky.push_back("\"");
    tricky.push_back("\\");
    tricky.push_back("a\\");
    tricky.push_back("a b\\");
    tricky.push_back("a b\\\\");
    tricky.push_back("\\\\\"");
    tricky.push_back("x\\\\y");
    tricky.push_back("C:\\Program Files\\dir\\");
    tricky.push_back("a\nb\n\nc");
    tricky.push_back("tab\there");
    tricky.push_back("model_reasoning_effort=\"low\"");
    tricky.push_back("caf\xC3\xA9 \xC4\x91\xE1\xBA\xB9p");
    tricky.push_back("--tools");
    tricky.push_back("say \"hi\" \\\" there\\");
    for (size_t i = 0; i < tricky.size(); i++) {
        List back = parseCommandLine("prog " + quoteArgument(tricky[i]) + " next");
        CHECK(back.size() == 3 && back[0] == "prog" && back[1] == tricky[i] && back[2] == "next");
    }
    //a whole command line, as it is started
    List args = arguments(*find("claude-cli"), "haiku", "low", "Tr\xE1\xBA\xA3 l\xE1\xBB\x9D" "i \"ng\xE1\xBA\xAFn\".", "x", "d");
    std::string line = commandLine("C:\\Users\\Nguy\xE1\xBB\x85n V\xC4\x83n A\\.local\\bin\\claude.exe", args);
    List back = parseCommandLine(line);
    CHECK(back.size() == args.size() + 1 && back[0] == "C:\\Users\\Nguy\xE1\xBB\x85n V\xC4\x83n A\\.local\\bin\\claude.exe");
    for (size_t i = 0; i < args.size() && i + 1 < back.size(); i++)
        CHECK(back[i + 1] == args[i]);
    CHECK(quoteArgument("simple") == "simple" && quoteArgument("") == "\"\"" && quoteArgument("a b") == "\"a b\"");

    //what a script of cmd.exe cannot be given
    CHECK(safeForCommandShell(arguments(*find("codex-cli"), "mini", "low", "", "x", "C:\\Users\\a\\Temp\\VOpenKey-agent-1")));
    CHECK(safeForCommandShell(listOf("--model", "gpt-5-mini", "model_reasoning_effort=\"low\"")));
    CHECK(!safeForCommandShell(listOf("a&b")) && !safeForCommandShell(listOf("a|b")) && !safeForCommandShell(listOf("a<b")) && !safeForCommandShell(listOf("a>b")) &&
          !safeForCommandShell(listOf("a^b")) && !safeForCommandShell(listOf("100%")) && !safeForCommandShell(listOf("hi!")) && !safeForCommandShell(listOf("two\nlines")) &&
          !safeForCommandShell(listOf("cr\r")));
    CHECK(!safeForCommandShell(arguments(*find("claude-cli"), "haiku", "", "Be brief.", "x", "d"))); //its system prompt has two paragraphs
}

static void testPictures() {
    std::printf("-- pictures\n");
    const Agent& codex = *find("codex-cli");
    CHECK(find("codex-cli")->canMakeImages && !find("claude-cli")->canMakeImages && !find("agy-cli")->canMakeImages);
    const std::string cat = "m\xE1\xBB\x99t con m\xC3\xA8o";   //"mot con meo" with its marks
    const std::string expected = "Use $imagegen skill to create picture " + cat + ", follow our design system.";
    std::string tpl = defaultImagePromptTemplate();
    CHECK(tpl == "Use $imagegen skill to create picture {prompt}, follow our design system.");
    CHECK(imagePromptForRequest(cat, tpl) == expected);
    CHECK(imagePromptForRequest("  " + cat + " \n\n", tpl) == expected);
    CHECK(imagePromptForRequest("a {prompt} b", "X {prompt} Y {prompt}") == "X a {prompt} b Y a {prompt} b");   //what is asked is not read again as a template
    CHECK(imagePromptForRequest("cat", "Use $imagegen skill, picture:") == "Use $imagegen skill, picture: cat");  //no {prompt}: the request comes after
    CHECK(imagePromptForRequest("cat", "  ") == "Use $imagegen skill to create picture cat, follow our design system.");
    CHECK(imagePromptForRequest("cat", "") == "Use $imagegen skill to create picture cat, follow our design system.");

    List a = imageArguments(codex, "mini", "low", "C:\\work");
    List text = arguments(codex, "mini", "low", "x", "y", "C:\\work");
    CHECK(a[0] == "exec" && a[1] == "--json" && a.size() == text.size() + 1);       //the same run, with the events
    List without = a;
    without.erase(without.begin() + 1);
    CHECK(without == text);
    CHECK(after(a, "-s") == "read-only" && after(a, "--disable") == "shell_tool" && has(a, "--ephemeral") && a.back() == "-");
    CHECK(imageStandardInput("Use $imagegen skill: \xE1\xBA\xBF") == "Use $imagegen skill: \xE1\xBA\xBF");   //as it is

    CHECK(codexHomeFolder("D:\\codex", "C:\\Users\\a", '\\') == "D:\\codex");
    CHECK(codexHomeFolder("", "C:\\Users\\a", '\\') == "C:\\Users\\a\\.codex");
    CHECK(codexHomeFolder("", "/home/a", '/') == "/home/a/.codex");

    CHECK(isSafeThreadId("01a1539b-a6e8-7fa1-a860-f7cd426576ff") && isSafeThreadId("thread_A-1") && isSafeThreadId(std::string(80, 'x')));
    CHECK(!isSafeThreadId("") && !isSafeThreadId("../evil") && !isSafeThreadId("/etc") && !isSafeThreadId("a/b") && !isSafeThreadId("a\\b") &&
          !isSafeThreadId("a b") && !isSafeThreadId(std::string(81, 'x')) && !isSafeThreadId("thread-a/../../evil") && !isSafeThreadId("..") && !isSafeThreadId("a:b"));
    CHECK(isPictureFileName("a.png") && isPictureFileName("A.JPG") && isPictureFileName("a.b.jpeg") && isPictureFileName("x.webp") && isPictureFileName("x.gif"));
    CHECK(!isPictureFileName("notes.txt") && !isPictureFileName("png") && !isPictureFileName("a.png.exe") && !isPictureFileName("") && !isPictureFileName("pngx"));

    //finding the picture of a run (the times are made up: bigger is newer)
    std::vector<PictureEntry> entries;
    PictureEntry e;
    e.folder = "thread-a"; e.name = "old.png"; e.modified = 100; entries.push_back(e);
    e.folder = "thread-a"; e.name = "new.png"; e.modified = 5000; entries.push_back(e);
    e.folder = "thread-a"; e.name = "notes.txt"; e.modified = 9000; entries.push_back(e);          //not a picture
    e.folder = "thread-b"; e.name = "other.jpg"; e.modified = 3000; entries.push_back(e);
    long long started = 2000;
    int i = choosePicture("thread-a", entries, started, true);
    CHECK(i >= 0 && entries[(size_t)i].name == "new.png");                                          //by its thread: the newest of it, whenever it was made
    i = choosePicture("thread-a", entries, 0, false);
    CHECK(i >= 0 && entries[(size_t)i].name == "new.png");
    i = choosePicture("thread-a", entries, 6000, true);
    CHECK(i >= 0 && entries[(size_t)i].name == "new.png");                                          //... even if it is older than the start
    i = choosePicture("nothing", entries, started, true);
    CHECK(i >= 0 && entries[(size_t)i].name == "new.png");                                          //a thread without a folder: the newest since the start, in any folder
    i = choosePicture("", entries, 3500, true);
    CHECK(i >= 0 && entries[(size_t)i].name == "new.png");
    i = choosePicture("", entries, 5001, true);
    CHECK(i == -1);                                                                                 //nothing was made since
    CHECK(choosePicture("nothing", entries, 0, false) == -1);                                       //without a time there is no guessing
    std::vector<PictureEntry> other(entries.begin() + 3, entries.end());                            //only thread-b
    i = choosePicture("thread-a", other, started, true);
    CHECK(i >= 0 && other[(size_t)i].name == "other.jpg");
    CHECK(choosePicture("thread-a", std::vector<PictureEntry>(), started, true) == -1);
    //a thread name that leads out of the folder is not looked up as a folder; the fallback still works on what was listed
    e.folder = "evil"; e.name = "secret.png"; e.modified = 1; entries.push_back(e);
    CHECK(choosePicture("../evil", entries, 0, false) == -1);
    i = choosePicture("evil/..", entries, started, true);
    CHECK(i >= 0 && entries[(size_t)i].name == "new.png");
    //the first of two with the same time wins (a tie is not newer)
    std::vector<PictureEntry> ties;
    e.folder = "t"; e.name = "first.png"; e.modified = 10; ties.push_back(e);
    e.folder = "t"; e.name = "second.png"; e.modified = 10; ties.push_back(e);
    CHECK(choosePicture("t", ties, 0, false) == 0);
}

int main() {
    testAgents();
    testCatalog();
    testAntigravityList();
    testChoices();
    testArguments();
    testOutput();
    testErrors();
    testCommandLine();
    testPictures();
    std::printf(failures == 0 ? "ai_agent_test: all passed\n" : "ai_agent_test: %d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
