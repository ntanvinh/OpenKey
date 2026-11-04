//
//  AIAgent.cpp
//  VOpenKey AI, portable
//
#include "AIAgent.h"
#include "MiniJson.h"
#include <algorithm>

namespace vai {
namespace agent {

const char* const kEffortProgramDefault = "default";

namespace {

bool isAsciiAlnum(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

std::string lower(const std::string& text) {
    std::string out = text;
    for (size_t i = 0; i < out.size(); i++) {
        if (out[i] >= 'A' && out[i] <= 'Z')
            out[i] = (char)(out[i] - 'A' + 'a');
    }
    return out;
}

bool isBlank(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\v' || c == '\f';
}

std::string trim(const std::string& text) {
    size_t a = 0, b = text.size();
    while (a < b && isBlank(text[a])) a++;
    while (b > a && isBlank(text[b - 1])) b--;
    return text.substr(a, b - a);
}

bool hasSuffix(const std::string& text, const std::string& suffix) {
    return text.size() >= suffix.size() && text.compare(text.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool contains(const std::string& text, const std::string& part) {
    return text.find(part) != std::string::npos;
}

//whether one of `words` is a word of `text`: "mini" is a word of "gpt-5-mini" and of "A mini model", not a part of "gemini" or "minimal"
bool hasWord(const std::string& text, const char* const* words, size_t count) {
    std::string low = lower(text);
    std::vector<std::string> parts;
    std::string current;
    for (size_t i = 0; i < low.size(); i++) {
        if (isAsciiAlnum((unsigned char)low[i])) {
            current += low[i];
        } else {
            if (!current.empty())
                parts.push_back(current);
            current.clear();
        }
    }
    if (!current.empty())
        parts.push_back(current);
    for (size_t w = 0; w < count; w++) {
        if (std::find(parts.begin(), parts.end(), words[w]) != parts.end())
            return true;
    }
    return false;
}

//a text cut at `limit` bytes without cutting a letter of UTF-8 in two, and "..." (a real ellipsis) after it
std::string shorten(const std::string& text, size_t limit) {
    if (text.size() <= limit)
        return text;
    size_t cut = limit;
    while (cut > 0 && ((unsigned char)text[cut] & 0xC0) == 0x80)
        cut--;
    return text.substr(0, cut) + "\xE2\x80\xA6";
}

const std::vector<std::string>& effortOrder() {
    static std::vector<std::string> order;
    if (order.empty()) {
        const char* names[] = {"minimal", "low", "medium", "high", "xhigh", "max", "ultra"};
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
            order.push_back(names[i]);
    }
    return order;
}

bool inList(const std::vector<std::string>& list, const std::string& value) {
    return std::find(list.begin(), list.end(), value) != list.end();
}

} // namespace

// --- the agents ---------------------------------------------------------------------------------------------------------

const std::vector<Agent>& all() {
    static std::vector<Agent> agents;
    if (agents.empty()) {
        Agent codex;
        codex.kind = Kind::Codex;
        codex.providerId = "codex-cli";
        codex.command = "codex";
        codex.displayName = "Codex CLI";
        codex.loginHint = "codex login";
        codex.installHint = "npm install -g @openai/codex";
        codex.output = Output::Plain;
        codex.promptInArguments = false;
        codex.keepsConversations = false;
        codex.canMakeImages = true;
        agents.push_back(codex);

        Agent claude;
        claude.kind = Kind::Claude;
        claude.providerId = "claude-cli";
        claude.command = "claude";
        claude.displayName = "Claude Code CLI";
        claude.loginHint = "claude auth login";
        claude.installHint = "npm install -g @anthropic-ai/claude-code";
        claude.output = Output::ClaudeJson;
        claude.promptInArguments = false;
        claude.keepsConversations = false;
        claude.canMakeImages = false;
        agents.push_back(claude);

        Agent agy;
        agy.kind = Kind::Antigravity;
        agy.providerId = "agy-cli";
        agy.command = "agy";
        agy.displayName = "Antigravity CLI";
        agy.loginHint = "agy";
        agy.output = Output::Plain;
        agy.promptInArguments = true;
        agy.keepsConversations = true;
        agy.canMakeImages = false;
        agents.push_back(agy);
    }
    return agents;
}

const Agent* find(const std::string& providerId) {
    const std::vector<Agent>& agents = all();
    for (size_t i = 0; i < agents.size(); i++) {
        if (agents[i].providerId == providerId)
            return &agents[i];
    }
    return NULL;
}

// --- models -------------------------------------------------------------------------------------------------------------

const std::string* Model::variant(const std::string& level) const {
    for (size_t i = 0; i < variants.size(); i++) {
        if (variants[i].first == level)
            return &variants[i].second;
    }
    return NULL;
}

static Model makeModel(const char* id, const char* name, bool light) {
    Model model;
    model.id = id;
    model.name = name;
    model.light = light;
    return model;
}

std::vector<Model> claudeModels() {
    std::vector<Model> models;
    models.push_back(makeModel("haiku", "Haiku", true));
    models.push_back(makeModel("sonnet", "Sonnet", false));
    models.push_back(makeModel("opus", "Opus", false));
    models.push_back(makeModel("fable", "Fable", false));
    return models;
}

std::vector<Model> modelsFromCodexCatalog(const std::string& json) {
    std::vector<Model> result;
    vjson::Value root;
    if (json.empty() || !vjson::parse(json, root))
        return result;
    const vjson::Value* list = NULL;
    if (root.isObject() && root["models"].isArray())
        list = &root["models"];
    else if (root.isArray())
        list = &root;
    if (list == NULL)
        return result;

    static const char* const lightWords[] = {"fast", "affordable", "efficient", "lightweight", "small", "cheap", "quick", "mini"};
    static const char* const heavyWords[] = {"older", "previous", "legacy", "deprecated", "frontier", "demanding"};
    struct Entry { Model model; double priority; size_t index; };
    std::vector<Entry> entries;
    for (size_t i = 0; i < list->items().size(); i++) {
        const vjson::Value& item = list->items()[i];
        if (!item.isObject() || !item["slug"].isString() || item["slug"].asString().empty())
            continue;
        //only what is meant for a menu: the rest is for the program itself (automatic review...)
        std::string visibility = item["visibility"].isString() ? item["visibility"].asString() : "list";
        if (visibility != "list")
            continue;
        Entry entry;
        entry.model.id = item["slug"].asString();
        entry.model.name = item["display_name"].isString() && !item["display_name"].asString().empty() ? item["display_name"].asString()
                                                                                                      : entry.model.id;
        std::string description = item["description"].isString() ? item["description"].asString() : "";
        entry.model.summary = description;
        const vjson::Value& levels = item["supported_reasoning_levels"];
        for (size_t k = 0; levels.isArray() && k < levels.items().size(); k++) {
            const vjson::Value& level = levels.items()[k];
            std::string effort = level.isObject() ? level["effort"].stringOr("") : level.stringOr("");
            if (!effort.empty() && !inList(entry.model.efforts, effort))
                entry.model.efforts.push_back(effort);
        }
        entry.model.defaultEffort = item["default_reasoning_level"].stringOr("");
        entry.model.light = hasWord(description, lightWords, sizeof(lightWords) / sizeof(lightWords[0])) &&
                            !hasWord(description, heavyWords, sizeof(heavyWords) / sizeof(heavyWords[0]));
        entry.priority = item["priority"].isNumber() ? item["priority"].asNumber() : 1000;
        entry.index = i;
        entries.push_back(entry);
    }
    //the program lists the newest and most prominent first by `priority`; the order of the file breaks ties
    std::stable_sort(entries.begin(), entries.end(), [](const Entry& a, const Entry& b) {
        return a.priority != b.priority ? a.priority < b.priority : a.index < b.index;
    });
    for (size_t i = 0; i < entries.size(); i++) {
        if (findModel(result, entries[i].model.id) == NULL)
            result.push_back(entries[i].model);
    }
    return result;
}

std::string withoutEscapes(const std::string& text) {
    if (text.find('\x1B') == std::string::npos)
        return text;
    std::string out;
    size_t i = 0;
    while (i < text.size()) {
        if (text[i] != '\x1B') {
            out += text[i++];
            continue;
        }
        //ESC [ ... final byte (colours, cursor), ESC ] ... BEL or ESC \ (a title), ESC and one more character
        i++;
        if (i >= text.size())
            break;
        if (text[i] == '[') {
            i++;
            while (i < text.size() && ((text[i] >= '0' && text[i] <= '9') || text[i] == ';' || text[i] == '?'))
                i++;
            while (i < text.size() && text[i] >= ' ' && text[i] <= '/')
                i++;
            if (i < text.size() && text[i] >= '@' && text[i] <= '~')
                i++;
        } else if (text[i] == ']') {
            i++;
            while (i < text.size() && text[i] != '\x07' && text[i] != '\x1B')
                i++;
            if (i < text.size() && text[i] == '\x07')
                i++;
            else if (i + 1 < text.size() && text[i] == '\x1B' && text[i + 1] == '\\')
                i += 2;
        } else if ((text[i] >= '@' && text[i] <= 'Z') || (text[i] >= '\\' && text[i] <= '_')) {
            i++;
        }
    }
    return out;
}

static bool startsWithAt(const std::string& text, size_t position, const char* part) {
    return text.compare(position, std::string(part).size(), part) == 0;
}

//drops the bullets a list may put in front of a line: - * > and blanks, and the real bullets of UTF-8 (a dot, two ticks, a triangle)
static std::string withoutBullets(const std::string& line) {
    size_t i = 0;
    for (;;) {
        if (i < line.size() && (line[i] == '-' || line[i] == '*' || line[i] == '>' || line[i] == ' ' || line[i] == '\t')) {
            i++;
        } else if (startsWithAt(line, i, "\xE2\x80\xA2") || startsWithAt(line, i, "\xE2\x9C\x93") || startsWithAt(line, i, "\xE2\x9C\x94") ||
                   startsWithAt(line, i, "\xE2\x96\xB6")) {
            i += 3;
        } else {
            break;
        }
    }
    return line.substr(i);
}

std::vector<Model> modelsFromAntigravityList(const std::string& text) {
    //the lines: "identifier<TAB>name". Another program may print a status line ("Fetching...") on its output, so when there are tabs, only
    //the lines with one are models. Without any, the line is the name and what --model takes (a bullet in front is dropped)
    std::vector<std::string> lines;
    bool anyTab = false;
    std::string current;
    for (size_t i = 0; i <= text.size(); i++) {
        if (i == text.size() || text[i] == '\n' || text[i] == '\r') {
            std::string line = withoutEscapes(current);
            size_t tab = line.find('\t');
            if (tab != std::string::npos && !trim(line.substr(0, tab)).empty())
                anyTab = true;
            lines.push_back(line);
            current.clear();
        } else {
            current += text[i];
        }
    }
    std::vector<std::pair<std::string, std::string> > entries;   //identifier, name
    for (size_t n = 0; n < lines.size(); n++) {
        std::string line = lines[n];
        std::string identifier, name;
        size_t tab = line.find('\t');
        if (anyTab) {
            if (tab == std::string::npos)
                continue;
            identifier = trim(line.substr(0, tab));
            name = trim(line.substr(tab));
        } else {
            line = trim(withoutBullets(line));
            if (line.empty() || line[line.size() - 1] == ':' || line[0] == '#')
                continue;
            //"id    Name": a column of identifiers, then the name
            size_t gap = line.find("  ");
            identifier = gap != std::string::npos && gap > 0 ? line.substr(0, gap) : line;
            name = gap != std::string::npos && gap > 0 ? trim(line.substr(gap)) : line;
        }
        bool seen = false;
        for (size_t k = 0; k < entries.size(); k++)
            seen = seen || entries[k].first == identifier;
        if (identifier.empty() || identifier.size() > 120 || seen)
            continue;
        entries.push_back(std::make_pair(identifier, name.empty() ? identifier : name));
    }

    //models that only differ by their level are one model with levels
    static const char* const lightWords[] = {"flash", "mini", "lite", "haiku", "nano", "small", "fast"};
    std::vector<Model> models;
    for (size_t n = 0; n < entries.size(); n++) {
        const std::string& identifier = entries[n].first;
        const std::string& name = entries[n].second;
        std::string level;
        const std::vector<std::string>& order = effortOrder();
        for (size_t c = 0; c < order.size(); c++) {
            const std::string& candidate = order[c];
            bool inIdentifier = hasSuffix(identifier, "-" + candidate) && identifier.size() > candidate.size() + 1;
            bool inName = hasSuffix(lower(name), " (" + candidate + ")") && name.size() > candidate.size() + 3;
            if (inIdentifier && inName) {
                level = candidate;
                break;
            }
        }
        if (level.empty()) {
            Model model;
            model.id = identifier;
            model.name = name;
            models.push_back(model);
            continue;
        }
        std::string family = identifier.substr(0, identifier.size() - level.size() - 1);
        Model* model = NULL;
        for (size_t k = 0; k < models.size(); k++) {
            if (!models[k].variants.empty() && models[k].id == family)
                model = &models[k];
        }
        if (model == NULL) {
            Model made;
            made.id = family;
            made.name = name.substr(0, name.size() - level.size() - 3);
            made.light = hasWord(family, lightWords, sizeof(lightWords) / sizeof(lightWords[0]));
            models.push_back(made);
            model = &models.back();
        }
        model->variants.push_back(std::make_pair(level, identifier));
    }
    for (size_t k = 0; k < models.size(); k++) {
        if (models[k].variants.empty())
            continue;
        const std::vector<std::string>& order = effortOrder();
        for (size_t c = 0; c < order.size(); c++) {
            if (models[k].variant(order[c]) != NULL)
                models[k].efforts.push_back(order[c]);
        }
    }
    return models;
}

const Model* findModel(const std::vector<Model>& models, const std::string& id) {
    for (size_t i = 0; i < models.size(); i++) {
        if (models[i].id == id)
            return &models[i];
    }
    return NULL;
}

std::vector<std::string> commonEfforts() {
    std::vector<std::string> efforts;
    efforts.push_back("low");
    efforts.push_back("medium");
    efforts.push_back("high");
    efforts.push_back("xhigh");
    efforts.push_back("max");
    return efforts;
}

std::string modelToPass(const Agent& agent, const std::string& saved, const std::vector<Model>& models) {
    std::string chosen = trim(saved);
    if (!chosen.empty())
        return chosen;
    if (agent.kind == Kind::Claude)
        return "haiku";
    for (size_t i = 0; i < models.size(); i++) {
        if (models[i].light)
            return models[i].id;
    }
    return std::string(); //the list is not known: the program uses its own default
}

std::string effortToPass(const Agent& agent, const std::string& savedEffort, const std::string& model, const std::vector<Model>& models) {
    if (savedEffort == kEffortProgramDefault)
        return std::string();
    const Model* known = model.empty() ? NULL : findModel(models, model);
    std::vector<std::string> allowed = known != NULL && !known->efforts.empty() ? known->efforts : commonEfforts();
    if (!savedEffort.empty() && inList(allowed, savedEffort))
        return savedEffort;
    //"choose for me": the fast level. A model of Antigravity that is not known to have levels keeps the one in its name.
    if (agent.kind == Kind::Antigravity && (known == NULL || known->efforts.empty()))
        return std::string();
    return inList(allowed, "low") ? "low" : allowed.front();
}

void resolve(const Agent& agent, const std::string& savedModel, const std::string& savedEffort, const std::vector<Model>& models,
             std::string& modelArgument, std::string& effortArgument) {
    std::string model = modelToPass(agent, savedModel, models);
    std::string effort = effortToPass(agent, savedEffort, model, models);
    const Model* known = model.empty() ? NULL : findModel(models, model);
    if (known != NULL && !known->variants.empty()) {
        //the levels of this model are models of the program: the one of the level asked for, and no level besides
        const std::string* variant = effort.empty() ? NULL : known->variant(effort);
        if (variant == NULL)
            variant = known->variant(known->defaultEffort.empty() ? "medium" : known->defaultEffort);
        if (variant == NULL && !known->efforts.empty())
            variant = known->variant(known->efforts.front());
        if (variant != NULL)
            model = *variant;
        effort.clear();
    }
    modelArgument = model;
    effortArgument = effort;
}

bool isPlausibleModelName(const std::string& name) {
    if (name.empty() || name.size() > 120 || name[0] == '-')
        return false;
    for (size_t i = 0; i < name.size(); i++) {
        unsigned char c = (unsigned char)name[i];
        if (c < 0x20 || c == 0x7F)
            return false;
    }
    return true;
}

bool isPlausibleEffort(const std::string& effort) {
    if (effort.empty() || effort.size() > 16 || !(effort[0] >= 'a' && effort[0] <= 'z'))
        return false;
    for (size_t i = 0; i < effort.size(); i++) {
        char c = effort[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-'))
            return false;
    }
    return true;
}

// --- one request --------------------------------------------------------------------------------------------------------

std::string instruction(const std::string& systemPrompt) {
    std::string rule = "You are the writing assistant of a typing application. Reply with the text that was asked for and nothing else. "
                       "You have no tools here: do not run commands, do not read, create or change files, do not browse the web.";
    return systemPrompt.empty() ? rule : rule + "\n\n" + systemPrompt;
}

std::vector<std::string> arguments(const Agent& agent, const std::string& model, const std::string& effort, const std::string& systemPrompt,
                                   const std::string& prompt, const std::string& workDirectory) {
    bool hasModel = isPlausibleModelName(model);
    bool hasEffort = isPlausibleEffort(effort);
    std::vector<std::string> args;
    switch (agent.kind) {
        case Kind::Codex:
            //`exec` runs once without asking anything. The user's own configuration (hooks, MCP servers, rules) is left out, nothing is
            //saved, the files can only be read, the program may not run commands, and the request comes on the standard input ("-")
            args.push_back("exec");
            args.push_back("--ignore-user-config");
            args.push_back("--ignore-rules");
            args.push_back("--skip-git-repo-check");
            args.push_back("--ephemeral");
            args.push_back("--color");
            args.push_back("never");
            args.push_back("-s");
            args.push_back("read-only");
            args.push_back("--disable");
            args.push_back("shell_tool");
            args.push_back("-C");
            args.push_back(workDirectory.empty() ? "." : workDirectory);
            if (hasModel) {
                args.push_back("-m");
                args.push_back(model);
            }
            if (hasEffort) {
                args.push_back("-c");
                args.push_back("model_reasoning_effort=\"" + effort + "\"");
            }
            args.push_back("-");
            break;
        case Kind::Claude:
            //safe mode: nothing of the user's (CLAUDE.md, hooks, MCP servers, plugins, skills); no tools at all; nothing saved; the
            //answer comes as it is written
            args.push_back("-p");
            args.push_back("--safe-mode");
            args.push_back("--tools");
            args.push_back("");
            args.push_back("--no-session-persistence");
            args.push_back("--output-format");
            args.push_back("stream-json");
            args.push_back("--include-partial-messages");
            args.push_back("--verbose");
            args.push_back("--system-prompt");
            args.push_back(instruction(systemPrompt));
            if (hasModel) {
                args.push_back("--model");
                args.push_back(model);
            }
            if (hasEffort) {
                args.push_back("--effort");
                args.push_back(effort);
            }
            break;
        case Kind::Antigravity:
            if (hasModel) {
                args.push_back("--model");
                args.push_back(model);
            }
            if (hasEffort) {
                args.push_back("--effort");
                args.push_back(effort);
            }
            //the flags come first: what follows -p is the prompt, which starts with our own text so it can never look like a flag
            args.push_back("--output-format");
            args.push_back("text");
            args.push_back("-p");
            args.push_back(instruction(systemPrompt) + "\n\n" + prompt);
            break;
    }
    return args;
}

bool standardInput(const Agent& agent, const std::string& prompt, const std::string& systemPrompt, std::string& out) {
    switch (agent.kind) {
        case Kind::Codex:
            out = instruction(systemPrompt) + "\n\n" + prompt;
            return true;
        case Kind::Claude:
            out = prompt;
            return true;
        case Kind::Antigravity:
            break;
    }
    out.clear();
    return false;
}

bool listModelsArguments(const Agent& agent, std::vector<std::string>& out) {
    out.clear();
    switch (agent.kind) {
        case Kind::Codex:
            out.push_back("debug");
            out.push_back("models");
            return true;
        case Kind::Antigravity:
            out.push_back("models");
            return true;
        case Kind::Claude:
            break;
    }
    return false;
}

// --- pictures (Codex) ---------------------------------------------------------------------------------------------------

std::string defaultImagePromptTemplate() {
    return "Use $imagegen skill to create picture {prompt}, follow our design system.";
}

std::string imagePromptForRequest(const std::string& request, const std::string& templateText) {
    std::string wanted = trim(request);
    std::string pattern = trim(templateText);
    if (pattern.empty())
        pattern = defaultImagePromptTemplate();
    const std::string marker = "{prompt}";
    if (pattern.find(marker) == std::string::npos)
        return pattern + " " + wanted;
    std::string out;
    size_t from = 0;
    for (;;) {
        size_t at = pattern.find(marker, from);
        if (at == std::string::npos) {
            out += pattern.substr(from);
            break;
        }
        out += pattern.substr(from, at - from) + wanted;
        from = at + marker.size();
    }
    return out;
}

std::vector<std::string> imageArguments(const Agent& agent, const std::string& model, const std::string& effort, const std::string& workDirectory) {
    //the arguments of a text, with the events in JSON; the skill makes the picture with a tool of Codex itself, no command is needed
    std::vector<std::string> args = arguments(agent, model, effort, std::string(), std::string(), workDirectory);
    args.insert(args.begin() + 1, "--json");
    return args;
}

std::string imageStandardInput(const std::string& prompt) {
    return prompt;
}

std::string codexHomeFolder(const std::string& codexHomeVariable, const std::string& homeFolder, char separator) {
    if (!codexHomeVariable.empty())
        return codexHomeVariable;
    return homeFolder + std::string(1, separator) + ".codex";
}

bool isSafeThreadId(const std::string& id) {
    if (id.empty() || id.size() > 80)
        return false;
    for (size_t i = 0; i < id.size(); i++) {
        unsigned char c = (unsigned char)id[i];
        if (!(isAsciiAlnum(c) || c == '-' || c == '_'))
            return false;
    }
    return true;
}

bool isPictureFileName(const std::string& name) {
    size_t dot = name.find_last_of('.');
    if (dot == std::string::npos)
        return false;
    std::string extension = lower(name.substr(dot + 1));
    return extension == "png" || extension == "jpg" || extension == "jpeg" || extension == "webp" || extension == "gif";
}

int choosePicture(const std::string& threadId, const std::vector<PictureEntry>& entries, long long since, bool hasSince) {
    //by its thread: the newest picture of it, whenever it was made
    if (isSafeThreadId(threadId)) {
        int best = -1;
        for (size_t i = 0; i < entries.size(); i++) {
            if (entries[i].folder == threadId && isPictureFileName(entries[i].name) && (best < 0 || entries[i].modified > entries[(size_t)best].modified))
                best = (int)i;
        }
        if (best >= 0)
            return best;
    }
    //not found by its thread: the newest picture of the folders, if it was written since the run started
    if (!hasSince)
        return -1;
    int best = -1;
    for (size_t i = 0; i < entries.size(); i++) {
        if (!isPictureFileName(entries[i].name) || entries[i].modified < since)
            continue;
        if (best < 0 || entries[i].modified > entries[(size_t)best].modified)
            best = (int)i;
    }
    return best;
}

// --- what comes back ----------------------------------------------------------------------------------------------------

//how many bytes at the end of `bytes` are the start of a letter whose end has not come
static size_t incompleteTail(const std::string& bytes) {
    for (size_t back = 1; back <= 3 && back <= bytes.size(); back++) {
        unsigned char byte = (unsigned char)bytes[bytes.size() - back];
        if ((byte & 0xC0) == 0x80)
            continue; //a continuation: look further back for its start
        size_t needed = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : (byte >= 0xC0 ? 2 : 1));
        return needed > back ? back : 0;
    }
    return 0;
}

OutputParser::OutputParser(Output format) : format_(format), sawPiece_(false) {}

std::vector<std::string> OutputParser::feed(const std::string& bytes) {
    std::vector<std::string> pieces;
    if (format_ == Output::Plain) {
        pending_ += bytes;
        size_t keep = incompleteTail(pending_);
        size_t usable = pending_.size() - keep;
        if (usable == 0)
            return pieces;
        std::string head = withoutEscapes(pending_.substr(0, usable));
        pending_.erase(0, usable);
        if (!head.empty())
            pieces.push_back(head);
        return pieces;
    }
    size_t start = 0;
    for (size_t i = 0; i < bytes.size(); i++) {
        if (bytes[i] != '\n')
            continue;
        pending_ += bytes.substr(start, i - start);
        start = i + 1;
        takeLine(pending_, pieces);
        pending_.clear();
    }
    pending_ += bytes.substr(start);
    if (pending_.size() > (1u << 22))
        pending_.clear(); //a line of 4 MB is not one of ours
    return pieces;
}

std::vector<std::string> OutputParser::finish() {
    std::vector<std::string> pieces;
    if (format_ == Output::Plain) {
        //a letter cut at the very end of the output is dropped: half of a letter is no text
        std::string rest = withoutEscapes(pending_.substr(0, pending_.size() - incompleteTail(pending_)));
        pending_.clear();
        if (!rest.empty())
            pieces.push_back(rest);
        return pieces;
    }
    if (!pending_.empty()) {
        takeLine(pending_, pieces);
        pending_.clear();
    }
    if (!sawPiece_ && errorMessage_.empty()) {
        //the answer did not come in pieces: it is in the message that completes it, or in the result
        const std::string& whole = !fallback_.empty() ? fallback_ : resultText_;
        if (!whole.empty()) {
            pieces.push_back(whole);
            sawPiece_ = true;
        }
    }
    return pieces;
}

//one line of stream-json
void OutputParser::takeLine(const std::string& line, std::vector<std::string>& pieces) {
    std::string trimmed = trim(line);
    if (trimmed.empty())
        return;
    vjson::Value json;
    if (trimmed[0] != '{' || !vjson::parse(trimmed, json) || !json.isObject()) {
        if (leftover_.size() < 4000)
            leftover_ += trimmed + "\n";
        return;
    }
    std::string type = json["type"].stringOr("");
    if (format_ == Output::CodexJson) {
        //the events of `codex exec --json`: which thread, what the agent says, and how it ended
        if (type == "thread.started") {
            threadId_ = json["thread_id"].stringOr("");
        } else if (type == "item.completed") {
            const vjson::Value& item = json["item"];
            std::string message = item["text"].stringOr("");
            if (item["type"].stringOr("") == "agent_message" && !message.empty()) {
                pieces.push_back(!fallback_.empty() ? "\n\n" + message : message); //one message after the other
                sawPiece_ = true;
                fallback_ += message;
            }
        } else if (type == "turn.failed") {
            std::string reason = json["error"]["message"].stringOr("");
            if (errorMessage_.empty()) //the first reason stays: an "error" event has said it already
                errorMessage_ = !reason.empty() ? reason : "error";
        } else if (type == "error") {
            std::string reason = json["message"].stringOr("");
            if (errorMessage_.empty())
                errorMessage_ = !reason.empty() ? reason : "error";
        }
        return;
    }
    if (type == "stream_event") {
        const vjson::Value& event = json["event"];
        const vjson::Value& delta = event["delta"];
        std::string piece = delta["text"].stringOr("");
        //only the answer: what the model thinks (thinking_delta) is not part of it
        if (event["type"].stringOr("") == "content_block_delta" && delta["type"].stringOr("") == "text_delta" && !piece.empty()) {
            sawPiece_ = true;
            pieces.push_back(piece);
        }
    } else if (type == "assistant") {
        const vjson::Value& message = json["message"];
        const vjson::Value& content = message["content"];
        for (size_t i = 0; content.isArray() && i < content.items().size(); i++) {
            const vjson::Value& part = content.items()[i];
            if (part.isObject() && part["type"].stringOr("") == "text" && part["text"].isString())
                fallback_ += part["text"].asString();
        }
        //a message that is an error ("authentication_failed"...) says what went wrong in its text
        if (message["error"].isString() && errorMessage_.empty() && !fallback_.empty())
            errorMessage_ = fallback_;
    } else if (type == "result") {
        std::string result = json["result"].stringOr("");
        bool failed = (json["is_error"].isBool() && json["is_error"].asBool()) || json["subtype"].stringOr("").compare(0, 5, "error") == 0;
        if (failed) {
            const vjson::Value& errors = json["errors"];
            std::string detail = result;
            if (detail.empty() && errors.isArray()) {
                for (size_t i = 0; i < errors.items().size(); i++) {
                    std::string one = errors.items()[i].stringOr("");
                    if (!one.empty())
                        detail += (detail.empty() ? "" : " ") + one;
                }
            }
            errorMessage_ = !detail.empty() ? detail : "error";
        } else {
            resultText_ = result;
        }
    }
}

//"error", "fatal" or "panic" as a word at the start of a line, with at most one word (a time, a level) in front of it
static bool startsWithError(const std::string& line) {
    std::string low = lower(line);
    static const char* const words[] = {"error", "fatal", "panic"};
    size_t positions[2] = {0, std::string::npos};
    size_t i = 0;
    while (i < low.size() && !isBlank(low[i])) i++;
    size_t afterWord = i;
    while (afterWord < low.size() && isBlank(low[afterWord])) afterWord++;
    if (afterWord > i)
        positions[1] = afterWord;
    for (int p = 0; p < 2; p++) {
        if (positions[p] == std::string::npos)
            continue;
        for (size_t w = 0; w < 3; w++) {
            size_t length = std::string(words[w]).size();
            if (low.compare(positions[p], length, words[w]) == 0 &&
                (positions[p] + length == low.size() || !isAsciiAlnum((unsigned char)low[positions[p] + length]) )) {
                return true;
            }
        }
    }
    return false;
}

std::string gistOfErrorOutput(const std::string& text) {
    std::vector<std::string> lines;
    std::string current;
    std::string clean = withoutEscapes(text);
    for (size_t i = 0; i <= clean.size(); i++) {
        if (i == clean.size() || clean[i] == '\n' || clean[i] == '\r') {
            std::string line = trim(current);
            if (!line.empty())
                lines.push_back(line);
            current.clear();
        } else {
            current += clean[i];
        }
    }
    //the lines that start with "error" (a log may put a time in front) are the program saying what went wrong; the lines that only
    //mention it may be the request that was echoed; and with neither, the last lines
    static const char* const markers[] = {"error", "failed", "denied", "unauthor", "not logged", "login", "limit", "quota", "invalid",
                                          "unsupported", "not found", "unknown"};
    std::vector<std::string> about, mentions;
    for (size_t i = 0; i < lines.size(); i++) {
        if (startsWithError(lines[i])) {
            about.push_back(lines[i]);
            continue;
        }
        std::string low = lower(lines[i]);
        for (size_t m = 0; m < sizeof(markers) / sizeof(markers[0]); m++) {
            if (contains(low, markers[m])) {
                mentions.push_back(lines[i]);
                break;
            }
        }
    }
    if (about.empty())
        about = mentions;
    const std::vector<std::string>& chosen = !about.empty() ? about : lines;
    size_t count = std::min((size_t)3, chosen.size());
    std::string joined;
    for (size_t i = chosen.size() - count; i < chosen.size(); i++)
        joined += (joined.empty() ? "" : " ") + shorten(chosen[i], 220);
    return redact(shorten(joined, 420), "");
}

static bool hasAny(const std::string& low, const char* const* words, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (contains(low, words[i]))
            return true;
    }
    return false;
}

#define COUNT_OF(a) (sizeof(a) / sizeof((a)[0]))

Error errorForMessage(const Agent& agent, const std::string& message, int exitStatus, const std::string& model, const std::string& effort) {
    (void)agent;
    (void)model;
    std::string gist = gistOfErrorOutput(message);
    std::string low = lower(gist);
    static const char* const effortWords[] = {"effort", "reasoning"};
    static const char* const notAccepted[] = {"unsupported", "not supported", "invalid", "unknown", "not allowed", "expected"};
    static const char* const modelWord[] = {"model"};
    static const char* const modelProblems[] = {"not found", "not exist", "does not exist", "unsupported", "not supported", "invalid", "unknown",
                                                "no access", "not available", "not allowed"};
    static const char* const login[] = {"not logged in", "not signed in", "please run /login", "codex login", "login required", "log in", "sign in",
                                        "authenticat", "unauthorized", "401", "invalid api key", "credentials", "expired token", "token expired", "oauth"};
    static const char* const oldProgram[] = {"unknown option", "unrecognized option", "unexpected argument", "unknown argument",
                                             "unrecognized argument", "invalid option", "unknown flag", "flag provided but not defined"};
    static const char* const rateLimit[] = {"rate limit", "rate_limit", "usage limit", "quota", "429", "too many requests", "overloaded",
                                            "limit reached", "credit"};
    static const char* const network[] = {"enotfound", "econnrefused", "econnreset", "network", "offline", "timed out", "timeout", "dns",
                                          "fetch failed", "connection"};
    if (!effort.empty() && hasAny(low, effortWords, COUNT_OF(effortWords)) && hasAny(low, notAccepted, COUNT_OF(notAccepted)))
        return Error(ErrorCode::Effort, gist, exitStatus);
    if (hasAny(low, modelWord, COUNT_OF(modelWord)) && hasAny(low, modelProblems, COUNT_OF(modelProblems)))
        return Error(ErrorCode::Model, gist, exitStatus);
    if (hasAny(low, login, COUNT_OF(login)))
        return Error(ErrorCode::Login, gist, exitStatus);
    //an option of the program that this version does not know: it is older (or newer) than the call that was written for it
    if (hasAny(low, oldProgram, COUNT_OF(oldProgram)))
        return Error(ErrorCode::OldProgram, gist, exitStatus);
    if (hasAny(low, rateLimit, COUNT_OF(rateLimit)))
        return Error(ErrorCode::RateLimit, gist, exitStatus);
    if (hasAny(low, network, COUNT_OF(network)))
        return Error(ErrorCode::Network, gist, exitStatus);
    return Error(ErrorCode::Server, gist, exitStatus);
}

// --- starting a program on Windows --------------------------------------------------------------------------------------

std::string quoteArgument(const std::string& argument) {
    if (!argument.empty() && argument.find_first_of(" \t\n\v\"") == std::string::npos)
        return argument;
    std::string out = "\"";
    for (size_t i = 0;; i++) {
        size_t backslashes = 0;
        while (i < argument.size() && argument[i] == '\\') {
            i++;
            backslashes++;
        }
        if (i == argument.size()) {
            out.append(backslashes * 2, '\\'); //in front of the closing quote
            break;
        } else if (argument[i] == '"') {
            out.append(backslashes * 2 + 1, '\\');
            out.push_back('"');
        } else {
            out.append(backslashes, '\\');
            out.push_back(argument[i]);
        }
    }
    out.push_back('"');
    return out;
}

std::string commandLine(const std::string& program, const std::vector<std::string>& args) {
    std::string line = quoteArgument(program);
    for (size_t i = 0; i < args.size(); i++)
        line += " " + quoteArgument(args[i]);
    return line;
}

bool safeForCommandShell(const std::vector<std::string>& args) {
    for (size_t i = 0; i < args.size(); i++) {
        for (size_t k = 0; k < args[i].size(); k++) {
            unsigned char c = (unsigned char)args[i][k];
            if (c < 0x20 || c == 0x7F || c == '&' || c == '|' || c == '<' || c == '>' || c == '^' || c == '%' || c == '!')
                return false;
        }
    }
    return true;
}

} // namespace agent
} // namespace vai
