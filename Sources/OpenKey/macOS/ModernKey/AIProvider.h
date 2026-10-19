//
//  AIProvider.h
//  VOpenKey
//
//  The AI services VOpenKey can write text with, and the rules for the two things the user types in to reach one: the
//  address of the server and the API key.
//
//  Three ways of talking to a server are enough for all of them:
//  - OpenAI: POST <address>/chat/completions. OpenAI itself, DeepSeek, Qwen (Alibaba), OpenRouter, and the programs that run a
//    model on this Mac or in the local network (Ollama, LM Studio, llama.cpp, vLLM...) speak it;
//  - Gemini: Google's own interface;
//  - Anthropic: the interface of Claude.
//
//  A fourth way needs no key and no address: an AI agent that is already installed and signed in on this Mac (Codex, Claude Code,
//  Antigravity) is run as a program for each request (AIAgentCLI, AIAgentRunner). The agent keeps its own account: VOpenKey AI
//  never sees its login.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AIProtocol) {
    AIProtocolOpenAI,
    AIProtocolGemini,
    AIProtocolAnthropic,
    AIProtocolAgentCLI      //a command line program that is signed in by itself: no address, no key
};

@interface AIProvider : NSObject

/// Never changes, saved in the settings: "openai", "gemini", "ollama"...
@property (nonatomic, readonly, copy) NSString* identifier;
/// As shown to the user: "OpenAI (ChatGPT)".
@property (nonatomic, readonly, copy) NSString* name;
@property (nonatomic, readonly) AIProtocol protocol;
/// Where the server is, without the final slash. Empty for a provider the user has to fill in.
@property (nonatomic, readonly, copy) NSString* defaultBaseURL;
/// The model used until the user chooses another one. Model names change often, so it is always editable. Empty for an agent
/// program that picks its own (see AIAgentCLI).
@property (nonatomic, readonly, copy) NSString* defaultModel;
/// A program on this Mac (AIProtocolAgentCLI): what the user sees as the address and the key does not exist for it.
@property (nonatomic, readonly) BOOL isAgentCLI;
/// Runs on this Mac or in the local network: nothing leaves it, a key is not needed.
@property (nonatomic, readonly) BOOL isLocal;
/// A request without key is refused by the service. For local servers and the custom one a key is optional.
@property (nonatomic, readonly) BOOL needsKey;
/// A page where the user gets a key, nil for the ones that have none.
@property (nonatomic, readonly, copy) NSString* keyPageURL;
/// One line under the name in the settings, nil when there is nothing to add.
@property (nonatomic, readonly, copy) NSString* note;

/// All of them, in the order of the menu.
+(NSArray<AIProvider*>*)allProviders;
+(AIProvider*)providerWithIdentifier:(NSString*)identifier;
/// The one used when the user has not chosen.
+(AIProvider*)defaultProvider;

@end

#ifdef __cplusplus
extern "C" {
#endif

extern NSString* const VOKAIErrorDomain;

typedef NS_ENUM(NSInteger, VOKAIErrorCode) {
    VOKAIErrorNoKey = 1,        //a key is needed and there is none
    VOKAIErrorBadAddress,       //the address of the server cannot be used
    VOKAIErrorBadKey,           //the key has characters a key cannot have
    VOKAIErrorAuthentication,   //the server does not accept the key (401, 403)
    VOKAIErrorRateLimit,        //too many requests or no credit left (429)
    VOKAIErrorModel,            //the model does not exist or is not allowed (404)
    VOKAIErrorServer,           //the server failed or answered something else (5xx, other)
    VOKAIErrorNetwork,          //no connection, no answer in time
    VOKAIErrorCancelled,
    VOKAIErrorEmpty,            //the answer had no text
    VOKAIErrorRejected,         //the service refused the content (safety filters)
    VOKAIErrorNoProgram,        //the agent program is not on this Mac, or cannot be started
    VOKAIErrorLogin             //the agent program is not signed in: it has to be done in the Terminal, not in these settings
};

/// Checks and cleans the address of a server: https, or http only for this Mac and the local network, so that a key is never
/// sent in the clear over the internet. Returns the address without a final slash, or nil with the reason (in Vietnamese,
/// ready to show) in *reason.
NSString* VOKAICleanBaseURL(NSString* address, NSString** reason);

/// Whether a host name or address is this Mac or something in the local network.
BOOL VOKAIHostIsLocal(NSString* host);

/// Checks and cleans an API key typed or pasted by the user: the spaces and line breaks around it are dropped, and what is left
/// must be printable ASCII (a key with a space inside is a copy gone wrong, and a line break would split an HTTP header).
/// Returns nil with the reason in *reason when it cannot be a key.
NSString* VOKAICleanKey(NSString* key, NSString** reason);

/// Hides what must not be shown or logged in a message that came from a server or a library: the key itself if it is given,
/// and anything that looks like the key of a known service.
NSString* VOKAIRedact(NSString* message, NSString* key);

#ifdef __cplusplus
}
#endif
