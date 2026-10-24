//
//  AIProtocol.h
//  VOpenKey
//
//  How to talk to the AI services the assistant writes text with, without any platform code: which services there are, how
//  the address and the key typed by the user are checked, the request to send, the stream of an answer and the errors. The
//  platform only moves bytes (HTTPS) and shows text. Plain C++11, UTF-8, ASCII source: the sentences the user reads are made by
//  the platform from the codes and details given here.
//
//  Three ways of talking to a server are enough for all of them:
//  - OpenAI: POST <address>/chat/completions. OpenAI itself, DeepSeek, Qwen (Alibaba), OpenRouter, and the programs that run a
//    model on this computer or in the local network (Ollama, LM Studio, llama.cpp, vLLM...) speak it;
//  - Gemini: Google's own interface;
//  - Anthropic: the interface of Claude.
//
//  Care taken with what is sent and received (the platform must keep to it too): nothing is cached or stored by the transport,
//  a redirect is never followed (the key would go to another server), the key goes only in a header, never in the address, and
//  the messages of errors have the key and anything that looks like one taken out (redact).
//
#ifndef AIProtocol_h
#define AIProtocol_h

#include <string>
#include <utility>
#include <vector>

namespace vai {

enum class Protocol { OpenAI, Gemini, Anthropic };

struct Provider {
    std::string id;           //never changes, saved in the settings: "openai", "gemini", "ollama"...
    std::string name;         //as shown to the user, ASCII
    Protocol protocol;
    std::string baseUrl;      //without the final slash, empty for a provider the user has to fill in
    std::string model;        //used until the user chooses another one
    bool isLocal;             //runs on this computer or in the local network: nothing leaves it, no key needed
    bool needsKey;            //a request without a key is refused (for local servers and the custom one a key is optional)
    std::string keyPage;      //where the user gets a key, empty if there is none
};

/// All of them, in the order of the menu.
const std::vector<Provider>& providers();
/// nullptr when there is none with that id.
const Provider* findProvider(const std::string& id);
const Provider& defaultProvider();

enum class ErrorCode {
    None = 0,
    NoKey,            //a key is needed and there is none
    BadAddress,       //the address of the server cannot be used
    BadKey,           //the key has characters a key cannot have
    Authentication,   //the server does not accept the key (401, 403)
    RateLimit,        //too many requests or no credit left (429)
    Model,            //the model does not exist or is not allowed (404)
    Server,           //the server failed or answered something else (5xx, other)
    Network,          //no connection, no answer in time
    Cancelled,
    Empty,            //the answer had no text
    Rejected          //the service refused the content (safety filters)
};

struct Error {
    ErrorCode code;
    int status;             //the HTTP status when there was one
    std::string detail;     //what the server said (redacted, short), or the name of what was refused
    Error() : code(ErrorCode::None), status(0) {}
    Error(ErrorCode c, const std::string& d = std::string(), int s = 0) : code(c), status(s), detail(d) {}
    bool ok() const { return code == ErrorCode::None; }
};

// --- the address of the server ----------------------------------------------------------------------------------------

struct Url {
    bool valid = false;
    std::string scheme;       //lower case
    std::string host;         //lower case, without the brackets of an IPv6 address
    int port = 0;             //the default of the scheme when the address has none
    std::string pathAndQuery; //"/" at least
    bool hasUserInfo = false;
    bool hasQuery = false;
    bool hasFragment = false;
};

/// Splits http:// and https:// addresses.
Url parseUrl(const std::string& address);

/// This computer or something in the local network: localhost, 127.x, 10.x, 192.168.x, 172.16-31.x, 169.254.x, ::1, fe80::,
/// fc00::/fd00::, a name ending in .local or without a dot.
bool hostIsLocal(const std::string& host);

enum class AddressProblem { None, Empty, Invalid, HasCredentials, HasQueryOrFragment, InsecureRemote, BadScheme };

/// https, or http only for this computer and the local network, so that a key is never sent in the clear over the internet.
/// Returns the address without a final slash, or "" with the reason in `problem`.
std::string cleanBaseUrl(const std::string& address, AddressProblem& problem);

enum class KeyProblem { None, Empty, BadCharacters, TooLong };

/// The spaces and line breaks around a key are dropped; what is left must be printable ASCII (a space inside is a copy gone
/// wrong, and a line break would split an HTTP header). Returns "" with the reason in `problem` when it cannot be a key.
std::string cleanKey(const std::string& key, KeyProblem& problem);

/// Hides what must not be shown or logged in a message that came from a server or a library: the key itself if it is given,
/// and anything that looks like the key of a known service.
std::string redact(const std::string& message, const std::string& key);

// --- a request ----------------------------------------------------------------------------------------------------------

struct Config {
    Provider provider;
    std::string baseUrl;       //cleaned
    std::string model;
    std::string key;           //empty when the provider does not need one and the user gave none
    std::string systemPrompt;
};

struct HttpRequest {
    std::string method;        //"POST" or "GET"
    std::string url;
    std::vector<std::pair<std::string, std::string> > headers;
    std::string body;          //UTF-8 JSON
};

/// The request that asks for a text, streamed. Fails with BadAddress when the address is not allowed.
bool buildRequest(const Config& config, const std::string& prompt, HttpRequest& out, Error& error);

/// The request that lists the models of the service (it also tells whether the key and the address work).
bool buildModelsRequest(const Config& config, HttpRequest& out, Error& error);

/// The names of the models in the answer to buildModelsRequest, sorted, without the ones that cannot write text.
std::vector<std::string> modelNames(const std::string& body, const Config& config);

// --- an answer ----------------------------------------------------------------------------------------------------------

/// Some models (DeepSeek R1, Qwen 3 on some servers...) write their reasoning first, between <think> and </think>, in the text
/// of the answer. It is not the answer: this removes it as the text arrives, even when a tag is cut in two pieces. Only a block
/// at the very start of the answer counts as reasoning, so an answer that talks about the tag keeps it.
class ThinkFilter {
public:
    ThinkFilter();
    /// The part of `text` that belongs to the answer (may be empty: the text may still be the start of a tag).
    std::string feed(const std::string& text);
    /// The answer ended: whatever was held back in case it was a tag. Nothing when the reasoning never ended.
    std::string flush();
private:
    enum State { Undecided, Thinking, Passing } state_;
    std::string held_;
    bool trimStart_;
    std::string take(const std::string& text);
};

/// Reads the stream of an answer (server-sent events) as it arrives and says what text it carried.
class StreamParser {
public:
    explicit StreamParser(Protocol protocol);

    /// Gives bytes as they arrive, cut anywhere (a Vietnamese letter can be cut in two). Returns the pieces of text completed by
    /// them. When the stream carries an error or a refusal, `error` is set and nothing more is read.
    std::vector<std::string> feed(const std::string& bytes, Error& error);

    /// The stream ended: the text still held back (see ThinkFilter). Call once, after the last bytes.
    std::vector<std::string> flush();

    /// The service said it has finished.
    bool finished() const { return finished_; }

    /// Text of an answer that was not streamed (a server that ignores "stream"); "" when it has none.
    static std::string textOfCompleteAnswer(const std::string& body, Protocol protocol, Error& error);

private:
    Protocol protocol_;
    std::string buffer_;
    bool stopped_;
    bool finished_;
    ThinkFilter think_;
    std::string textOfLine(const std::string& line, Error& error);
};

/// The error for an HTTP status that is not a success. `body` is what the server sent with it.
Error errorForStatus(int status, const std::string& body, const Config& config);

/// What a server says in the body of an error, in whatever shape; "" when it says nothing.
std::string serverMessage(const std::string& body);

} // namespace vai

#endif /* AIProtocol_h */
