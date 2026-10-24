// Tests of the AI protocol (portable C++): addresses, keys, requests, streams, errors.
//
//   clang++ -std=c++11 -I.. ai_protocol_test.cpp ../AIProtocol.cpp ../MiniJson.cpp -o /tmp/ai_protocol_test && /tmp/ai_protocol_test
#include "AIProtocol.h"
#include "MiniJson.h"
#include <cstdio>

using namespace vai;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static std::string clean(const std::string& a, AddressProblem* p = NULL) {
    AddressProblem problem;
    std::string r = cleanBaseUrl(a, problem);
    if (p) *p = problem;
    return r;
}

static std::string header(const HttpRequest& r, const std::string& name) {
    for (size_t i = 0; i < r.headers.size(); i++) if (r.headers[i].first == name) return r.headers[i].second;
    return "<none>";
}

static Config config(const char* id, const std::string& key = "KEY12345") {
    Config c;
    c.provider = *findProvider(id);
    c.baseUrl = c.provider.baseUrl;
    c.model = c.provider.model;
    c.key = key;
    c.systemPrompt = "SYS";
    return c;
}

//feeds a stream in pieces of `step` bytes and collects the text
static std::string stream(Protocol protocol, const std::string& text, size_t step, Error* error = NULL, bool* finished = NULL) {
    StreamParser parser(protocol);
    std::string all;
    Error e;
    for (size_t i = 0; i < text.size(); i += step) {
        std::vector<std::string> pieces = parser.feed(text.substr(i, step), e);
        for (size_t k = 0; k < pieces.size(); k++) all += pieces[k];
        if (!e.ok()) break;
    }
    std::vector<std::string> rest = parser.flush();
    for (size_t k = 0; k < rest.size(); k++) all += rest[k];
    if (error) *error = e;
    if (finished) *finished = parser.finished();
    return all;
}

int main() {
    // the services
    CHECK(providers().size() == 9);
    CHECK(findProvider("openai") && findProvider("openai")->protocol == Protocol::OpenAI && findProvider("openai")->needsKey);
    CHECK(findProvider("ollama") && findProvider("ollama")->isLocal && !findProvider("ollama")->needsKey);
    CHECK(findProvider("nope") == NULL);
    CHECK(defaultProvider().id == "openai");
    for (size_t i = 0; i < providers().size(); i++) {
        const Provider& p = providers()[i];
        AddressProblem problem;
        if (!p.baseUrl.empty()) CHECK(!cleanBaseUrl(p.baseUrl, problem).empty());   // their own addresses are allowed
    }

    // addresses
    AddressProblem p;
    CHECK(clean("https://api.openai.com/v1/") == "https://api.openai.com/v1");
    CHECK(clean("  https://api.openai.com/v1  ") == "https://api.openai.com/v1");
    CHECK(clean("", &p) == "" && p == AddressProblem::Empty);
    CHECK(clean("api.openai.com", &p) == "" && p == AddressProblem::Invalid);
    CHECK(clean("https://user:pw@host/v1", &p) == "" && p == AddressProblem::HasCredentials);
    CHECK(clean("https://host/v1?key=1", &p) == "" && p == AddressProblem::HasQueryOrFragment);
    CHECK(clean("https://host/v1#x", &p) == "" && p == AddressProblem::HasQueryOrFragment);
    CHECK(clean("http://api.example.com/v1", &p) == "" && p == AddressProblem::InsecureRemote);   // a key never goes in the clear
    CHECK(clean("http://localhost:11434/v1") == "http://localhost:11434/v1");
    CHECK(clean("http://192.168.1.20:8080/v1") == "http://192.168.1.20:8080/v1");
    CHECK(clean("http://10.0.0.5/v1") != "");
    CHECK(clean("http://172.20.0.1/v1") != "");
    CHECK(clean("http://172.32.0.1/v1") == "");                                                    // outside the private range
    CHECK(clean("http://8.8.8.8/v1") == "");
    CHECK(clean("http://mac-mini:1234/v1") != "");                                                 // a name without a dot is local
    CHECK(clean("http://[::1]:1234/v1") != "");
    CHECK(clean("ftp://host/v1", &p) == "" && p == AddressProblem::BadScheme);
    CHECK(clean("https://host:99999/v1", &p) == "" && p == AddressProblem::Invalid);
    Url u = parseUrl("HTTPS://Example.COM:8443/a/b?x=1");
    CHECK(u.valid && u.scheme == "https" && u.host == "example.com" && u.port == 8443 && u.pathAndQuery == "/a/b?x=1" && u.hasQuery);
    u = parseUrl("http://host");
    CHECK(u.valid && u.port == 80 && u.pathAndQuery == "/");
    CHECK(!hostIsLocal("example.com") && hostIsLocal("my.local") && hostIsLocal("localhost") && hostIsLocal("169.254.1.1"));

    // keys
    KeyProblem k;
    CHECK(cleanKey("  sk-abc123  \n", k) == "sk-abc123" && k == KeyProblem::None);
    CHECK(cleanKey("", k) == "" && k == KeyProblem::Empty);
    CHECK(cleanKey("sk abc", k) == "" && k == KeyProblem::BadCharacters);
    CHECK(cleanKey("sk-\xC3\xA9", k) == "" && k == KeyProblem::BadCharacters);
    CHECK(cleanKey("a\nb", k) == "" && k == KeyProblem::BadCharacters);
    CHECK(cleanKey(std::string(600, 'a'), k) == "" && k == KeyProblem::TooLong);

    // redaction
    const std::string dots = "\xE2\x80\xA2\xE2\x80\xA2\xE2\x80\xA2\xE2\x80\xA2";
    CHECK(redact("bad key MYSECRETKEY here", "MYSECRETKEY") == "bad key " + dots + " here");
    CHECK(redact("Incorrect API key: sk-proj-abc123XYZ789 end", "") == "Incorrect API key: " + dots + " end");
    CHECK(redact("key AIzaSyA1b2C3d4E5f6 end", "") == "key " + dots + " end");
    CHECK(redact("Authorization: Bearer abcdef123456.token", "") == "Authorization: " + dots);
    CHECK(redact("a task-force", "") == "a task-force");                                           // "sk-" inside a word, short
    CHECK(redact("short sk-ab", "") == "short sk-ab");

    // requests
    HttpRequest r; Error e;
    CHECK(buildRequest(config("openai"), "Hello", r, e) && e.ok());
    CHECK(r.method == "POST" && r.url == "https://api.openai.com/v1/chat/completions");
    CHECK(header(r, "Authorization") == "Bearer KEY12345" && header(r, "Content-Type") == "application/json");
    vjson::Value body;
    CHECK(vjson::parse(r.body, body) && body["model"].asString() == "gpt-4o-mini" && body["stream"].asBool());
    CHECK(body["messages"].items().size() == 2 && body["messages"].items()[0]["role"].asString() == "system" &&
          body["messages"].items()[1]["content"].asString() == "Hello");
    CHECK(r.url.find("KEY12345") == std::string::npos);                                            // never in the address

    CHECK(buildRequest(config("gemini"), "Xin ch\xC3\xA0o", r, e));
    CHECK(r.url == "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse");
    CHECK(header(r, "x-goog-api-key") == "KEY12345" && header(r, "Authorization") == "<none>");
    CHECK(vjson::parse(r.body, body) && body["contents"].items()[0]["parts"].items()[0]["text"].asString() == "Xin ch\xC3\xA0o");
    CHECK(body["systemInstruction"]["parts"].items()[0]["text"].asString() == "SYS");
    Config g = config("gemini"); g.model = "models/gemini pro";
    CHECK(buildRequest(g, "x", r, e) && r.url.find("/models/gemini%20pro:stream") != std::string::npos);

    CHECK(buildRequest(config("anthropic"), "Hi", r, e));
    CHECK(r.url == "https://api.anthropic.com/v1/messages" && header(r, "x-api-key") == "KEY12345" && header(r, "anthropic-version") == "2023-06-01");
    CHECK(vjson::parse(r.body, body) && body["system"].asString() == "SYS" && body["max_tokens"].asNumber() == 4096);

    Config noKey = config("ollama", "");
    noKey.systemPrompt = "";
    CHECK(buildRequest(noKey, "Hi", r, e) && header(r, "Authorization") == "<none>");
    CHECK(vjson::parse(r.body, body) && body["messages"].items().size() == 1);                     // no system message when empty
    Config bad = config("openai"); bad.baseUrl = "http://evil.example.com/v1";
    CHECK(!buildRequest(bad, "Hi", r, e) && e.code == ErrorCode::BadAddress);
    CHECK(buildModelsRequest(config("openai"), r, e) && r.method == "GET" && r.url == "https://api.openai.com/v1/models");
    CHECK(buildModelsRequest(config("gemini"), r, e) && r.url.find("/models?pageSize=200") != std::string::npos);

    // OpenAI stream, cut every way
    std::string openai =
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\"Xin ch\xC3\xA0o\"}}]}\r\n\r\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\" th\xE1\xBA\xBF gi\xE1\xBB\x9Bi\"},\"finish_reason\":null}]}\n\n"
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        "data: [DONE]\n\n";
    for (size_t step = 1; step <= 7; step += 2) {
        bool done = false;
        CHECK(stream(Protocol::OpenAI, openai, step, &e, &done) == "Xin ch\xC3\xA0o th\xE1\xBA\xBF gi\xE1\xBB\x9Bi");
        CHECK(e.ok() && done);
    }
    CHECK(stream(Protocol::OpenAI, openai, openai.size()) == "Xin ch\xC3\xA0o th\xE1\xBA\xBF gi\xE1\xBB\x9Bi");

    // reasoning is not the answer, even when the tags are cut
    std::string think =
        "data: {\"choices\":[{\"delta\":{\"content\":\"<thi\"}}]}\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\"nk>hmm let me\"}}]}\n"
        "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"secret\"}}]}\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\" think</th\"}}]}\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\"ink>\\n\\nThe answer\"}}]}\n";
    for (size_t step = 1; step <= 9; step += 4)
        CHECK(stream(Protocol::OpenAI, think, step) == "The answer");
    CHECK(stream(Protocol::OpenAI, "data: {\"choices\":[{\"delta\":{\"content\":\"Use the <think> tag\"}}]}\n", 3) == "Use the <think> tag");
    CHECK(stream(Protocol::OpenAI, "data: {\"choices\":[{\"delta\":{\"content\":\"<th\"}}]}\n", 100) == "<th");   // never lost at the end
    CHECK(stream(Protocol::OpenAI, "data: {\"choices\":[{\"delta\":{\"content\":\"<think>never ends\"}}]}\n", 100) == "");

    // errors inside a stream
    CHECK(stream(Protocol::OpenAI, "data: {\"error\":{\"message\":\"Incorrect API key sk-abcdef123456\",\"type\":\"invalid_request_error\",\"code\":\"invalid_api_key\"}}\n", 5, &e) == "");
    CHECK(e.code == ErrorCode::Authentication && e.detail.find("sk-abcdef") == std::string::npos);
    CHECK(stream(Protocol::OpenAI, "data: {\"error\":{\"message\":\"slow down\",\"type\":\"rate_limit_exceeded\"}}\n", 5, &e) == "" && e.code == ErrorCode::RateLimit);
    CHECK(stream(Protocol::OpenAI, "data: {\"error\":\"plain\"}\n", 5, &e) == "" && e.code == ErrorCode::Server && e.detail == "plain");
    CHECK(stream(Protocol::OpenAI, "data: not json\ndata: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n", 4, &e) == "ok" && e.ok());

    // Gemini
    std::string gemini =
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Xin \"}]}}]}\r\n\r\n"
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"thinking\",\"thought\":true},{\"text\":\"ch\xC3\xA0o\"}]},\"finishReason\":\"STOP\"}]}\r\n\r\n";
    bool done = false;
    CHECK(stream(Protocol::Gemini, gemini, 3, &e, &done) == "Xin ch\xC3\xA0o" && e.ok() && done);
    stream(Protocol::Gemini, "data: {\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}\n", 4, &e);
    CHECK(e.code == ErrorCode::Rejected && e.detail == "SAFETY");
    stream(Protocol::Gemini, "data: {\"candidates\":[{\"finishReason\":\"RECITATION\"}]}\n", 4, &e);
    CHECK(e.code == ErrorCode::Rejected && e.detail == "RECITATION");
    CHECK(stream(Protocol::Gemini, "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"cut\"}]},\"finishReason\":\"MAX_TOKENS\"}]}\n", 9) == "cut");

    // Anthropic
    std::string claude =
        "event: message_start\ndata: {\"type\":\"message_start\"}\n\n"
        "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n"
        "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"text\":\"no\"}}\n\n"
        "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\" world\"}}\n\n"
        "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n";
    CHECK(stream(Protocol::Anthropic, claude, 6, &e, &done) == "Hello world" && done);
    CHECK(stream(Protocol::Anthropic, "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n", 6, &e) == "" && e.code == ErrorCode::RateLimit);

    // a server that ignores "stream" answers in one piece
    CHECK(StreamParser::textOfCompleteAnswer("{\"choices\":[{\"message\":{\"content\":\"<think>x</think>\\n\\nAnswer\"}}]}", Protocol::OpenAI, e) == "Answer");
    CHECK(StreamParser::textOfCompleteAnswer("{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"G\"}]},\"finishReason\":\"STOP\"}]}", Protocol::Gemini, e) == "G");
    CHECK(StreamParser::textOfCompleteAnswer("{\"content\":[{\"type\":\"text\",\"text\":\"A\"},{\"type\":\"text\",\"text\":\"B\"}]}", Protocol::Anthropic, e) == "AB");
    e = Error();
    CHECK(StreamParser::textOfCompleteAnswer("{\"error\":{\"message\":\"nope\",\"type\":\"model_not_found\"}}", Protocol::OpenAI, e) == "" && e.code == ErrorCode::Model);
    CHECK(StreamParser::textOfCompleteAnswer("not json", Protocol::OpenAI, e) == "");

    // statuses
    Config c = config("openai", "KEY12345");
    CHECK(errorForStatus(401, "{\"error\":{\"message\":\"bad KEY12345\"}}", c).code == ErrorCode::Authentication);
    CHECK(errorForStatus(401, "{\"error\":{\"message\":\"bad KEY12345\"}}", c).detail.find("KEY12345") == std::string::npos);
    CHECK(errorForStatus(403, "", c).code == ErrorCode::Authentication);
    CHECK(errorForStatus(404, "[{\"error\":{\"message\":\"no model\"}}]", c).detail == "no model");
    CHECK(errorForStatus(429, "", c).code == ErrorCode::RateLimit);
    CHECK(errorForStatus(500, "<html>", c).code == ErrorCode::Server && errorForStatus(500, "<html>", c).status == 500);
    CHECK(errorForStatus(302, "", c).code == ErrorCode::Server && errorForStatus(302, "", c).status == 302);
    CHECK(serverMessage("{\"detail\":\"d\"}") == "d" && serverMessage("{\"message\":\"m\"}") == "m" && serverMessage("") == "");
    std::string longMessage = "{\"message\":\"" + std::string(500, 'x') + "\"}";
    CHECK(errorForStatus(500, longMessage, c).detail.size() < 210);

    // the list of models
    Config oa = config("openai");
    std::vector<std::string> names = modelNames("{\"data\":[{\"id\":\"gpt-4o\"},{\"id\":\"text-embedding-3-small\"},{\"id\":\"whisper-1\"},{\"id\":\"gpt-4o-mini\"}]}", oa);
    CHECK(names.size() == 2 && names[0] == "gpt-4o" && names[1] == "gpt-4o-mini");
    Config ol = config("ollama");
    CHECK(modelNames("{\"data\":[{\"id\":\"llama3.2\"},{\"id\":\"nomic-embed-text\"}]}", ol).size() == 2);   // not filtered for a local server
    std::vector<std::string> gm = modelNames("{\"models\":[{\"name\":\"models/gemini-2.5-pro\",\"supportedGenerationMethods\":[\"generateContent\"]},"
                                             "{\"name\":\"models/embedding-001\",\"supportedGenerationMethods\":[\"embedContent\"]}]}", config("gemini"));
    CHECK(gm.size() == 1 && gm[0] == "gemini-2.5-pro");
    CHECK(modelNames("garbage", oa).empty());

    if (failures == 0)
        printf("ai_protocol_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
