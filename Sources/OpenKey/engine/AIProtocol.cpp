//
//  AIProtocol.cpp
//  VOpenKey
//
#include "AIProtocol.h"
#include "MiniJson.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>

namespace vai {

// --- the services -------------------------------------------------------------------------------------------------------

static Provider make(const char* id, const char* name, Protocol protocol, const char* baseUrl, const char* model, bool local,
                     bool needsKey, const char* keyPage) {
    Provider p;
    p.id = id;
    p.name = name;
    p.protocol = protocol;
    p.baseUrl = baseUrl;
    p.model = model;
    p.isLocal = local;
    p.needsKey = needsKey;
    p.keyPage = keyPage;
    return p;
}

const std::vector<Provider>& providers() {
    static std::vector<Provider> all;
    if (all.empty()) {
        all.push_back(make("openai", "OpenAI (ChatGPT)", Protocol::OpenAI, "https://api.openai.com/v1", "gpt-4o-mini", false, true,
                           "https://platform.openai.com/api-keys"));
        all.push_back(make("gemini", "Google Gemini", Protocol::Gemini, "https://generativelanguage.googleapis.com/v1beta",
                           "gemini-flash-latest", false, true, "https://aistudio.google.com/apikey"));
        all.push_back(make("anthropic", "Anthropic (Claude)", Protocol::Anthropic, "https://api.anthropic.com/v1",
                           "claude-haiku-4-5-20251001", false, true, "https://console.anthropic.com/settings/keys"));
        all.push_back(make("deepseek", "DeepSeek", Protocol::OpenAI, "https://api.deepseek.com/v1", "deepseek-chat", false, true,
                           "https://platform.deepseek.com/api_keys"));
        all.push_back(make("qwen", "Qwen (Alibaba Cloud)", Protocol::OpenAI, "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                           "qwen-plus", false, true, "https://www.alibabacloud.com/help/en/model-studio/get-api-key"));
        all.push_back(make("openrouter", "OpenRouter", Protocol::OpenAI, "https://openrouter.ai/api/v1", "openai/gpt-4o-mini", false,
                           true, "https://openrouter.ai/keys"));
        all.push_back(make("ollama", "Ollama (local)", Protocol::OpenAI, "http://localhost:11434/v1", "llama3.2", true, false, ""));
        all.push_back(make("lmstudio", "LM Studio (local)", Protocol::OpenAI, "http://localhost:1234/v1", "local-model", true, false, ""));
        all.push_back(make("custom", "Other (OpenAI compatible)", Protocol::OpenAI, "", "", false, false, ""));
    }
    return all;
}

const Provider* findProvider(const std::string& id) {
    const std::vector<Provider>& all = providers();
    for (size_t i = 0; i < all.size(); i++) {
        if (all[i].id == id)
            return &all[i];
    }
    return NULL;
}

const Provider& defaultProvider() {
    return providers()[0];
}

// --- small text helpers -------------------------------------------------------------------------------------------------

static std::string lower(std::string s) {
    for (size_t i = 0; i < s.size(); i++)
        s[i] = (char)std::tolower((unsigned char)s[i]);
    return s;
}

static bool isSpace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && isSpace(s[a])) a++;
    while (b > a && isSpace(s[b - 1])) b--;
    return s.substr(a, b - a);
}

static bool startsWith(const std::string& s, const std::string& prefix) {
    return s.compare(0, prefix.size(), prefix) == 0;
}

static bool endsWith(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

static bool contains(const std::string& s, const std::string& part) {
    return s.find(part) != std::string::npos;
}

//cuts a long text, never inside a UTF-8 letter
static std::string shorten(const std::string& text, size_t limit) {
    if (text.size() <= limit)
        return text;
    size_t cut = limit;
    while (cut > 0 && ((unsigned char)text[cut] & 0xC0) == 0x80)
        cut--;
    return text.substr(0, cut) + "\xE2\x80\xA6";
}

// --- the address --------------------------------------------------------------------------------------------------------

Url parseUrl(const std::string& address) {
    Url url;
    size_t schemeEnd = address.find("://");
    if (schemeEnd == std::string::npos || schemeEnd == 0)
        return url;
    url.scheme = lower(address.substr(0, schemeEnd));
    for (size_t i = 0; i < url.scheme.size(); i++) {
        if (!std::isalnum((unsigned char)url.scheme[i]) && url.scheme[i] != '+' && url.scheme[i] != '-' && url.scheme[i] != '.')
            return url;
    }
    std::string rest = address.substr(schemeEnd + 3);
    size_t fragment = rest.find('#');
    if (fragment != std::string::npos) {
        url.hasFragment = true;
        rest = rest.substr(0, fragment);
    }
    size_t query = rest.find('?');
    if (query != std::string::npos)
        url.hasQuery = true;
    size_t pathStart = rest.find_first_of("/?");
    std::string authority = pathStart == std::string::npos ? rest : rest.substr(0, pathStart);
    url.pathAndQuery = pathStart == std::string::npos ? "/" : rest.substr(pathStart);
    if (url.pathAndQuery[0] == '?')
        url.pathAndQuery = "/" + url.pathAndQuery;
    size_t at = authority.rfind('@');
    if (at != std::string::npos) {
        url.hasUserInfo = true;
        authority = authority.substr(at + 1);
    }
    std::string host = authority;
    std::string port;
    if (!authority.empty() && authority[0] == '[') {
        size_t close = authority.find(']');
        if (close == std::string::npos)
            return url;
        host = authority.substr(1, close - 1);
        if (close + 1 < authority.size()) {
            if (authority[close + 1] != ':')
                return url;
            port = authority.substr(close + 2);
        }
    } else {
        size_t colon = authority.rfind(':');
        if (colon != std::string::npos) {
            host = authority.substr(0, colon);
            port = authority.substr(colon + 1);
        }
    }
    if (host.empty())
        return url;
    url.host = lower(host);
    if (port.empty()) {
        url.port = url.scheme == "https" ? 443 : 80;
    } else {
        for (size_t i = 0; i < port.size(); i++) {
            if (!std::isdigit((unsigned char)port[i]))
                return url;
        }
        long value = std::strtol(port.c_str(), NULL, 10);
        if (value <= 0 || value > 65535)
            return url;
        url.port = (int)value;
    }
    url.valid = true;
    return url;
}

bool hostIsLocal(const std::string& hostIn) {
    std::string host = lower(hostIn);
    if (host.size() >= 2 && host[0] == '[' && host[host.size() - 1] == ']')
        host = host.substr(1, host.size() - 2);
    if (host.empty())
        return false;
    if (host == "localhost" || endsWith(host, ".localhost") || endsWith(host, ".local"))
        return true;
    if (contains(host, ":")) //IPv6: this computer, link-local and the private ranges
        return host == "::1" || startsWith(host, "fe80:") || startsWith(host, "fc") || startsWith(host, "fd");
    //IPv4 in the private ranges, loopback and link-local
    std::vector<std::string> parts;
    size_t from = 0;
    while (true) {
        size_t dot = host.find('.', from);
        if (dot == std::string::npos) {
            parts.push_back(host.substr(from));
            break;
        }
        parts.push_back(host.substr(from, dot - from));
        from = dot + 1;
    }
    if (parts.size() == 4) {
        int octets[4];
        for (int i = 0; i < 4; i++) {
            if (parts[(size_t)i].empty() || parts[(size_t)i].size() > 3)
                return false;
            for (size_t k = 0; k < parts[(size_t)i].size(); k++) {
                if (!std::isdigit((unsigned char)parts[(size_t)i][k]))
                    return false;
            }
            int value = std::atoi(parts[(size_t)i].c_str());
            if (value > 255)
                return false;
            octets[i] = value;
        }
        if (octets[0] == 127 || octets[0] == 10) return true;
        if (octets[0] == 192 && octets[1] == 168) return true;
        if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
        if (octets[0] == 169 && octets[1] == 254) return true;
        return false;
    }
    //a name without a dot is something of the local network ("mac-mini")
    return !contains(host, ".");
}

std::string cleanBaseUrl(const std::string& address, AddressProblem& problem) {
    problem = AddressProblem::None;
    std::string text = trim(address);
    while (!text.empty() && text[text.size() - 1] == '/')
        text.erase(text.size() - 1);
    if (text.empty()) {
        problem = AddressProblem::Empty;
        return "";
    }
    Url url = parseUrl(text);
    if (!url.valid) {
        problem = AddressProblem::Invalid;
        return "";
    }
    if (url.hasUserInfo) {
        problem = AddressProblem::HasCredentials;
        return "";
    }
    if (url.hasQuery || url.hasFragment) {
        problem = AddressProblem::HasQueryOrFragment;
        return "";
    }
    if (url.scheme == "https")
        return text;
    if (url.scheme == "http") {
        if (hostIsLocal(url.host))
            return text;
        problem = AddressProblem::InsecureRemote;
        return "";
    }
    problem = AddressProblem::BadScheme;
    return "";
}

std::string cleanKey(const std::string& key, KeyProblem& problem) {
    problem = KeyProblem::None;
    std::string text = trim(key);
    if (text.empty()) {
        problem = KeyProblem::Empty;
        return "";
    }
    for (size_t i = 0; i < text.size(); i++) {
        unsigned char c = (unsigned char)text[i];
        if (c < 0x21 || c > 0x7E) {
            problem = KeyProblem::BadCharacters;
            return "";
        }
    }
    if (text.size() > 512) {
        problem = KeyProblem::TooLong;
        return "";
    }
    return text;
}

static bool isKeyChar(char c, bool allowDot) {
    return std::isalnum((unsigned char)c) || c == '_' || c == '-' || (allowDot && c == '.');
}

std::string redact(const std::string& message, const std::string& key) {
    if (message.empty())
        return message;
    const std::string mask = "\xE2\x80\xA2\xE2\x80\xA2\xE2\x80\xA2\xE2\x80\xA2";
    std::string text = message;
    if (key.size() >= 6) {
        size_t at = 0;
        while ((at = text.find(key, at)) != std::string::npos) {
            text.replace(at, key.size(), mask);
            at += mask.size();
        }
    }
    //OpenAI and Anthropic ("sk-...", "sk-ant-..."), Google ("AIza..."), a bearer token of any service
    std::string out;
    size_t i = 0;
    while (i < text.size()) {
        size_t end = 0;
        if (text.compare(i, 3, "sk-") == 0) {
            size_t j = i + 3;
            while (j < text.size() && isKeyChar(text[j], false)) j++;
            if (j - (i + 3) >= 6) end = j;
        } else if (text.compare(i, 4, "AIza") == 0) {
            size_t j = i + 4;
            while (j < text.size() && isKeyChar(text[j], false)) j++;
            if (j - (i + 4) >= 10) end = j;
        } else if (i + 6 <= text.size() && lower(text.substr(i, 6)) == "bearer" && i + 6 < text.size() && isSpace(text[i + 6])) {
            size_t j = i + 6;
            while (j < text.size() && isSpace(text[j])) j++;
            size_t tokenStart = j;
            while (j < text.size() && isKeyChar(text[j], true)) j++;
            if (j - tokenStart >= 8) end = j;
        }
        if (end > 0) {
            out += mask;
            i = end;
        } else {
            out += text[i++];
        }
    }
    return out;
}

// --- a request ----------------------------------------------------------------------------------------------------------

static std::string pathComponentOfModel(const std::string& model) {
    std::string name = startsWith(model, "models/") ? model.substr(7) : model;
    std::string out;
    for (size_t i = 0; i < name.size(); i++) {
        unsigned char c = (unsigned char)name[i];
        if (std::isalnum(c) || c == '-' || c == '.' || c == '_' || c == '~' || c == '/' || c == ':') {
            out += (char)c;
        } else {
            const char* digits = "0123456789ABCDEF";
            out += '%';
            out += digits[c >> 4];
            out += digits[c & 15];
        }
    }
    return out;
}

static void setKeyHeaders(HttpRequest& request, const Config& config) {
    if (config.key.empty())
        return;
    switch (config.provider.protocol) {
        case Protocol::OpenAI:
            request.headers.push_back(std::make_pair("Authorization", "Bearer " + config.key));
            break;
        case Protocol::Gemini:
            request.headers.push_back(std::make_pair("x-goog-api-key", config.key));
            break;
        case Protocol::Anthropic:
            request.headers.push_back(std::make_pair("x-api-key", config.key));
            request.headers.push_back(std::make_pair("anthropic-version", "2023-06-01"));
            break;
    }
}

bool buildRequest(const Config& config, const std::string& prompt, HttpRequest& out, Error& error) {
    AddressProblem problem;
    std::string base = cleanBaseUrl(config.baseUrl, problem);
    if (base.empty()) {
        error = Error(ErrorCode::BadAddress);
        return false;
    }
    using vjson::Value;
    Value body = Value::object();
    std::string address;
    switch (config.provider.protocol) {
        case Protocol::OpenAI: {
            Value messages = Value::array();
            if (!config.systemPrompt.empty()) {
                Value system = Value::object();
                system.set("role", Value::string("system"));
                system.set("content", Value::string(config.systemPrompt));
                messages.push(system);
            }
            Value user = Value::object();
            user.set("role", Value::string("user"));
            user.set("content", Value::string(prompt));
            messages.push(user);
            address = base + "/chat/completions";
            body.set("model", Value::string(config.model));
            body.set("messages", messages);
            body.set("stream", Value::boolean(true));
            break;
        }
        case Protocol::Gemini: {
            Value part = Value::object();
            part.set("text", Value::string(prompt));
            Value parts = Value::array();
            parts.push(part);
            Value content = Value::object();
            content.set("role", Value::string("user"));
            content.set("parts", parts);
            Value contents = Value::array();
            contents.push(content);
            body.set("contents", contents);
            if (!config.systemPrompt.empty()) {
                Value systemPart = Value::object();
                systemPart.set("text", Value::string(config.systemPrompt));
                Value systemParts = Value::array();
                systemParts.push(systemPart);
                Value instruction = Value::object();
                instruction.set("parts", systemParts);
                body.set("systemInstruction", instruction);
            }
            address = base + "/models/" + pathComponentOfModel(config.model) + ":streamGenerateContent?alt=sse";
            break;
        }
        case Protocol::Anthropic: {
            Value user = Value::object();
            user.set("role", Value::string("user"));
            user.set("content", Value::string(prompt));
            Value messages = Value::array();
            messages.push(user);
            body.set("model", Value::string(config.model));
            body.set("max_tokens", Value::number(4096));
            body.set("stream", Value::boolean(true));
            body.set("messages", messages);
            if (!config.systemPrompt.empty())
                body.set("system", Value::string(config.systemPrompt));
            address = base + "/messages";
            break;
        }
    }
    out = HttpRequest();
    out.method = "POST";
    out.url = address;
    out.body = vjson::write(body, false);
    out.headers.push_back(std::make_pair("Content-Type", "application/json"));
    out.headers.push_back(std::make_pair("Accept", "text/event-stream, application/json"));
    setKeyHeaders(out, config);
    return true;
}

bool buildModelsRequest(const Config& config, HttpRequest& out, Error& error) {
    AddressProblem problem;
    std::string base = cleanBaseUrl(config.baseUrl, problem);
    if (base.empty()) {
        error = Error(ErrorCode::BadAddress);
        return false;
    }
    out = HttpRequest();
    out.method = "GET";
    out.url = config.provider.protocol == Protocol::Gemini ? base + "/models?pageSize=200" : base + "/models";
    out.headers.push_back(std::make_pair("Accept", "application/json"));
    setKeyHeaders(out, config);
    return true;
}

std::vector<std::string> modelNames(const std::string& body, const Config& config) {
    std::vector<std::string> names;
    vjson::Value json;
    if (!vjson::parse(body, json) || !json.isObject())
        return names;
    if (config.provider.protocol == Protocol::Gemini) {
        const vjson::Value& models = json["models"];
        for (size_t i = 0; models.isArray() && i < models.items().size(); i++) {
            const vjson::Value& model = models.items()[i];
            if (!model.isObject() || !model["name"].isString())
                continue;
            const vjson::Value& methods = model["supportedGenerationMethods"];
            if (methods.isArray()) {
                bool canGenerate = false;
                for (size_t k = 0; k < methods.items().size(); k++)
                    canGenerate = canGenerate || (methods.items()[k].isString() && methods.items()[k].asString() == "generateContent");
                if (!canGenerate)
                    continue; //embeddings and the like
            }
            std::string name = model["name"].asString();
            names.push_back(startsWith(name, "models/") ? name.substr(7) : name);
        }
    } else {
        bool openAI = contains(config.baseUrl, "api.openai.com");
        static const char* notForText[] = {"embedding", "whisper", "tts", "dall-e", "davinci", "babbage", "moderation", "transcribe",
                                           "realtime", "audio", "image"};
        const vjson::Value& data = json["data"];
        for (size_t i = 0; data.isArray() && i < data.items().size(); i++) {
            const vjson::Value& model = data.items()[i];
            if (!model.isObject() || !model["id"].isString() || model["id"].asString().empty())
                continue;
            std::string id = model["id"].asString();
            bool skip = false;
            for (size_t k = 0; k < sizeof(notForText) / sizeof(notForText[0]); k++) {
                if (openAI && contains(lower(id), notForText[k]))
                    skip = true;
            }
            if (!skip)
                names.push_back(id);
        }
    }
    std::sort(names.begin(), names.end());
    return names;
}

// --- reasoning in the text ----------------------------------------------------------------------------------------------

static const char kThinkOpen[] = "<think>";
static const char kThinkClose[] = "</think>";

ThinkFilter::ThinkFilter() : state_(Undecided), trimStart_(false) {}

std::string ThinkFilter::take(const std::string& text) {
    if (!trimStart_ || text.empty())
        return text;
    size_t first = 0;
    while (first < text.size() && isSpace(text[first])) first++;
    if (first == text.size())
        return "";
    trimStart_ = false;
    return text.substr(first);
}

std::string ThinkFilter::feed(const std::string& text) {
    if (text.empty())
        return "";
    if (state_ == Passing)
        return take(text);
    held_ += text;
    const std::string open = kThinkOpen, close = kThinkClose;
    if (state_ == Undecided) {
        std::string start = trim(held_);
        if (start.empty())
            return ""; //only blanks so far
        if (start.size() < open.size() && open.compare(0, start.size(), start) == 0)
            return ""; //could still become the opening tag
        if (!startsWith(start, open)) {
            state_ = Passing;
            std::string all = held_;
            held_.clear();
            return all;
        }
        size_t tag = held_.find(open);
        held_ = held_.substr(tag + open.size());
        state_ = Thinking;
    }
    //inside the reasoning: everything is dropped up to the closing tag
    size_t at = held_.find(close);
    if (at != std::string::npos) {
        std::string answer = held_.substr(at + close.size());
        held_.clear();
        state_ = Passing;
        trimStart_ = true;
        return take(answer);
    }
    if (held_.size() > close.size()) //only the end can be the start of the closing tag
        held_.erase(0, held_.size() - (close.size() - 1));
    return "";
}

std::string ThinkFilter::flush() {
    std::string rest = state_ == Undecided ? held_ : "";
    held_.clear();
    state_ = Passing;
    return rest;
}

// --- errors in a body ---------------------------------------------------------------------------------------------------

static std::string messageOf(const vjson::Value& json) {
    if (json.isObject()) {
        const vjson::Value& error = json["error"];
        if (error.isObject() && error["message"].isString())
            return error["message"].asString();
        if (error.isString())
            return error.asString();
        static const char* keys[] = {"message", "detail", "msg"};
        for (size_t i = 0; i < 3; i++) {
            if (json[keys[i]].isString())
                return json[keys[i]].asString();
        }
    } else if (json.isArray() && !json.items().empty()) {
        return messageOf(json.items()[0]); //Gemini wraps an error in a list at times
    }
    return "";
}

std::string serverMessage(const std::string& body) {
    vjson::Value json;
    if (body.empty() || !vjson::parse(body, json))
        return "";
    return messageOf(json);
}

//the message of an error found in the stream or in the body: which kind it is
static Error errorFromJson(const vjson::Value& json) {
    std::string message = messageOf(json);
    if (message.empty())
        return Error();
    std::string type;
    if (json.isObject() && json["error"].isObject()) {
        const vjson::Value& error = json["error"];
        std::string code = error["code"].isString() ? error["code"].asString()
                                                    : (error["code"].isNumber() ? std::to_string((long long)error["code"].asNumber()) : "");
        type = lower(error["type"].stringOr("") + " " + code);
    }
    ErrorCode code = ErrorCode::Server;
    if (contains(type, "auth") || contains(type, "api_key") || contains(type, "invalid_key") || contains(type, "permission"))
        code = ErrorCode::Authentication;
    else if (contains(type, "rate") || contains(type, "quota") || contains(type, "overloaded"))
        code = ErrorCode::RateLimit;
    else if (contains(type, "model") || contains(type, "not_found"))
        code = ErrorCode::Model;
    return Error(code, shorten(redact(message, ""), 240));
}

Error errorForStatus(int status, const std::string& body, const Config& config) {
    std::string server = serverMessage(body);
    std::string detail = server.empty() ? "" : shorten(redact(server, config.key), 200);
    if (status == 401 || status == 403)
        return Error(ErrorCode::Authentication, detail, status);
    if (status == 404)
        return Error(ErrorCode::Model, detail, status);
    if (status == 429)
        return Error(ErrorCode::RateLimit, detail, status);
    return Error(ErrorCode::Server, detail, status);
}

// --- the stream ---------------------------------------------------------------------------------------------------------

StreamParser::StreamParser(Protocol protocol) : protocol_(protocol), stopped_(false), finished_(false) {}

std::vector<std::string> StreamParser::flush() {
    std::vector<std::string> pieces;
    if (protocol_ == Protocol::OpenAI) {
        std::string rest = think_.flush();
        if (!rest.empty())
            pieces.push_back(rest);
    }
    return pieces;
}

std::vector<std::string> StreamParser::feed(const std::string& bytes, Error& error) {
    std::vector<std::string> pieces;
    if (stopped_)
        return pieces;
    buffer_ += bytes;
    //a line is complete at its line feed, and a line feed is never inside a letter: lines can be decoded as soon as they are whole
    size_t start = 0;
    for (size_t i = 0; i < buffer_.size() && !stopped_; i++) {
        if (buffer_[i] != '\n')
            continue;
        size_t end = i;
        if (end > start && buffer_[end - 1] == '\r')
            end--;
        std::string line = buffer_.substr(start, end - start);
        start = i + 1;
        Error lineError;
        std::string piece = textOfLine(line, lineError);
        if (!piece.empty())
            pieces.push_back(piece);
        if (!lineError.ok()) {
            stopped_ = true;
            error = lineError;
        }
    }
    buffer_.erase(0, start);
    if (buffer_.size() > (1u << 20))
        buffer_.clear();
    return pieces;
}

std::string StreamParser::textOfLine(const std::string& line, Error& error) {
    if (!startsWith(line, "data:"))
        return ""; //"event:", comments (":"), blank lines
    std::string payload = trim(line.substr(5));
    if (payload.empty())
        return "";
    if (payload == "[DONE]") {
        finished_ = true;
        return "";
    }
    vjson::Value json;
    if (!vjson::parse(payload, json) || !json.isObject())
        return "";
    if (json.has("error")) {
        Error problem = errorFromJson(json);
        if (!problem.ok()) {
            error = problem;
            return "";
        }
    }
    switch (protocol_) {
        case Protocol::OpenAI: {
            const vjson::Value& choices = json["choices"];
            if (!choices.isArray() || choices.items().empty() || !choices.items()[0].isObject())
                return "";
            const vjson::Value& choice = choices.items()[0];
            if (choice["finish_reason"].isString() && !choice["finish_reason"].asString().empty())
                finished_ = true;
            const vjson::Value& content = choice["delta"]["content"]; //"reasoning_content" is the thinking, not the answer
            if (!content.isString())
                return "";
            return think_.feed(content.asString());                    //and so is what is between <think> and </think>
        }
        case Protocol::Gemini: {
            const vjson::Value& feedback = json["promptFeedback"];
            if (feedback.isObject() && feedback["blockReason"].isString()) {
                error = Error(ErrorCode::Rejected, feedback["blockReason"].asString());
                return "";
            }
            const vjson::Value& candidates = json["candidates"];
            if (!candidates.isArray() || candidates.items().empty())
                return "";
            const vjson::Value& candidate = candidates.items()[0];
            std::string text;
            const vjson::Value& parts = candidate["content"]["parts"];
            for (size_t i = 0; parts.isArray() && i < parts.items().size(); i++) {
                const vjson::Value& part = parts.items()[i];
                if (!part.isObject() || part["thought"].asBool())
                    continue; //what the model thought before answering is not the answer
                if (part["text"].isString())
                    text += part["text"].asString();
            }
            std::string finish = candidate["finishReason"].stringOr("");
            if (!finish.empty() && finish != "STOP" && finish != "MAX_TOKENS" && text.empty()) {
                error = Error(ErrorCode::Rejected, finish);
                return "";
            }
            if (!finish.empty())
                finished_ = true;
            return text;
        }
        case Protocol::Anthropic: {
            std::string type = json["type"].stringOr("");
            if (type == "message_stop") {
                finished_ = true;
                return "";
            }
            if (type == "content_block_delta") {
                const vjson::Value& delta = json["delta"];
                if (delta.isObject() && delta["type"].stringOr("") == "text_delta" && delta["text"].isString())
                    return delta["text"].asString();
            }
            return "";
        }
    }
    return "";
}

std::string StreamParser::textOfCompleteAnswer(const std::string& body, Protocol protocol, Error& error) {
    vjson::Value json;
    if (!vjson::parse(body, json) || !json.isObject())
        return "";
    if (json.has("error")) {
        Error problem = errorFromJson(json);
        if (!problem.ok()) {
            error = problem;
            return "";
        }
    }
    switch (protocol) {
        case Protocol::OpenAI: {
            const vjson::Value& choices = json["choices"];
            if (!choices.isArray() || choices.items().empty())
                return "";
            const vjson::Value& content = choices.items()[0]["message"]["content"];
            if (!content.isString())
                return "";
            ThinkFilter filter;
            return filter.feed(content.asString()) + filter.flush();
        }
        case Protocol::Gemini: {
            //the same shape as a piece of the stream
            StreamParser parser(Protocol::Gemini);
            std::string line = "data: " + vjson::write(json, false) + "\n";
            std::vector<std::string> pieces = parser.feed(line, error);
            std::string text;
            for (size_t i = 0; i < pieces.size(); i++)
                text += pieces[i];
            return text;
        }
        case Protocol::Anthropic: {
            std::string text;
            const vjson::Value& blocks = json["content"];
            for (size_t i = 0; blocks.isArray() && i < blocks.items().size(); i++) {
                if (blocks.items()[i].isObject() && blocks.items()[i]["text"].isString())
                    text += blocks.items()[i]["text"].asString();
            }
            return text;
        }
    }
    return "";
}

} // namespace vai
