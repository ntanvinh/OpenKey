//
//  AIAgentProcess.m
//  VOpenKey
//
//  The program is started with posix_spawn and not with NSTask on purpose: NSTask turns every argument into the decomposed form of
//  Unicode (NFD, "à" becomes "a" and a combining accent), and Vietnamese text must reach the program, and come back, the way it was
//  written.
//

#import "AIAgentProcess.h"
#import "AIProvider.h"
#import <crt_externs.h>
#import <fcntl.h>
#import <libproc.h>
#import <signal.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

static const NSUInteger kErrorTailLimit = 24 * 1024;       //what a program says when it fails is at the end
static const NSTimeInterval kGracePeriod = 1.5;            //between asking a program to stop and forcing it

#pragma mark - The processes of a tree

//When a process started: tells the process that was meant from another one that got the same number later
static BOOL StartTimeOfProcess(pid_t pid, uint64_t* start) {
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) != (int)sizeof info)
        return NO;
    *start = (uint64_t)info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec;
    return YES;
}

//the process and all it started, directly or not, with the time each started
static NSDictionary<NSNumber*, NSNumber*>* ProcessTree(pid_t root) {
    NSMutableDictionary<NSNumber*, NSNumber*>* tree = [NSMutableDictionary dictionary];
    NSMutableArray<NSNumber*>* queue = [NSMutableArray arrayWithObject:@(root)];
    while (queue.count > 0 && tree.count < 256) {
        pid_t pid = queue.firstObject.intValue;
        [queue removeObjectAtIndex:0];
        uint64_t start = 0;
        if (tree[@(pid)] != nil || !StartTimeOfProcess(pid, &start))
            continue;
        tree[@(pid)] = @(start);
        pid_t children[256];
        int count = proc_listchildpids(pid, children, sizeof children);
        for (int i = 0; i < count && i < 256; i++)
            [queue addObject:@(children[i])];
    }
    return tree;
}

#pragma mark - Building the call

//a NULL-ended list of C strings that is freed with the object; the strings are the UTF-8 of the originals, as they are
@interface AIAgentStringList : NSObject
-(instancetype)initWithStrings:(NSArray<NSString*>*)strings;
@property (nonatomic, readonly) char* const* list;
@end

@implementation AIAgentStringList {
    char** _list;
    NSUInteger _count;
}

-(instancetype)initWithStrings:(NSArray<NSString*>*)strings {
    self = [super init];
    if (self) {
        _count = strings.count;
        _list = calloc(_count + 1, sizeof(char*));
        for (NSUInteger i = 0; i < _count; i++)
            _list[i] = strdup(strings[i].UTF8String ?: "");
    }
    return self;
}

-(char* const*)list {
    return _list;
}

-(void)dealloc {
    for (NSUInteger i = 0; i < _count; i++)
        free(_list[i]);
    free(_list);
}
@end

static NSError* SpawnError(int code, NSString* what) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %s", what, strerror(code)]}];
}

#pragma mark - The process

@implementation AIAgentProcess {
    pid_t _pid;
    int _inputFd;                           //where the input goes, closed by the writer when it is all written
    int _outputFd, _errorFd;
    dispatch_queue_t _queue;                //every field below is touched only on it
    dispatch_source_t _outputSource;
    dispatch_source_t _errorSource;
    dispatch_source_t _exitSource;
    BOOL _outputDone, _errorDone, _finished, _terminating;
    BOOL _exited;                           //also read from other threads: -running
    int _status;
    BOOL _signaled;
    NSMutableData* _errorTail;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("vn.io.lssoft.vopenkey.agent-process", DISPATCH_QUEUE_SERIAL);
        _drainTimeout = 0.5;
        _errorTail = [NSMutableData data];
        _inputFd = _outputFd = _errorFd = -1;
    }
    return self;
}

-(BOOL)running {
    return _pid > 0 && !__atomic_load_n(&_exited, __ATOMIC_ACQUIRE);
}

-(pid_t)processIdentifier {
    return _pid;
}

static void CloseDescriptor(int* fd) {
    if (*fd >= 0) {
        close(*fd);
        *fd = -1;
    }
}

-(BOOL)launchExecutable:(NSString*)executable arguments:(NSArray<NSString*>*)arguments environment:(NSDictionary<NSString*, NSString*>*)environment
              directory:(NSString*)directory input:(NSData*)input error:(NSError**)error {
    //the three pipes; every end is close-on-exec, so that no other program started meanwhile gets one of them
    int toChild[2] = {-1, -1}, fromChild[2] = {-1, -1}, errorsFromChild[2] = {-1, -1};
    int* ends[6] = {&toChild[0], &toChild[1], &fromChild[0], &fromChild[1], &errorsFromChild[0], &errorsFromChild[1]};
    if (pipe(toChild) != 0 || pipe(fromChild) != 0 || pipe(errorsFromChild) != 0) {
        int code = errno;
        for (int i = 0; i < 6; i++)
            CloseDescriptor(ends[i]);
        if (error != NULL)
            *error = SpawnError(code, @"Không tạo được đường ống");
        return NO;
    }
    for (int i = 0; i < 6; i++)
        fcntl(*ends[i], F_SETFD, FD_CLOEXEC);

    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);
    posix_spawn_file_actions_adddup2(&actions, toChild[0], 0);          //dup2 gives the new descriptor without close-on-exec
    posix_spawn_file_actions_adddup2(&actions, fromChild[1], 1);
    posix_spawn_file_actions_adddup2(&actions, errorsFromChild[1], 2);
    if (directory.length > 0)
        posix_spawn_file_actions_addchdir_np(&actions, directory.fileSystemRepresentation);
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attributes, &none);                     //not what this application had blocked or ignored (SIGPIPE...)
    posix_spawnattr_setsigdefault(&attributes, &all);
    posix_spawnattr_setpgroup(&attributes, 0);                          //a group of its own: stopping it stops what it started
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);

    NSMutableArray<NSString*>* argv = [NSMutableArray arrayWithObject:executable];
    [argv addObjectsFromArray:arguments ?: @[]];
    NSMutableArray<NSString*>* variables = [NSMutableArray array];
    if (environment != nil) {
        for (NSString* name in environment)
            [variables addObject:[NSString stringWithFormat:@"%@=%@", name, environment[name]]];
    }
    AIAgentStringList* argumentList = [[AIAgentStringList alloc] initWithStrings:argv];
    AIAgentStringList* environmentList = environment != nil ? [[AIAgentStringList alloc] initWithStrings:variables] : nil;

    pid_t pid = 0;
    int code = posix_spawn(&pid, executable.fileSystemRepresentation, &actions, &attributes, argumentList.list,
                           environmentList != nil ? environmentList.list : *_NSGetEnviron());
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    CloseDescriptor(&toChild[0]);                                       //the ends that belong to the program: if they stayed open here,
    CloseDescriptor(&fromChild[1]);                                     //its end would never be seen as the end of its output
    CloseDescriptor(&errorsFromChild[1]);
    if (code != 0) {
        CloseDescriptor(&toChild[1]);
        CloseDescriptor(&fromChild[0]);
        CloseDescriptor(&errorsFromChild[0]);
        if (error != NULL)
            *error = SpawnError(code, @"Không khởi động được");
        return NO;
    }
    _pid = pid;
    _inputFd = toChild[1];
    _outputFd = fromChild[0];
    _errorFd = errorsFromChild[0];
    _outputSource = [self readSourceForDescriptor:_outputFd isOutput:YES];
    _errorSource = [self readSourceForDescriptor:_errorFd isOutput:NO];
    [self watchExit];
    [self writeInput:input];
    return YES;
}

//The input is written away from the main thread: a program that does not read it for a while would block the writer. A program that
//ended before reading all of it must not kill this process (SIGPIPE): the write just fails.
-(void)writeInput:(NSData*)input {
    int fd = _inputFd;
    _inputFd = -1;                                                      //the writer owns it now
    fcntl(fd, F_SETNOSIGPIPE, 1);
    NSData* data = [input copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const uint8_t* bytes = data.bytes;
        size_t left = data.length;
        while (left > 0) {
            ssize_t written = write(fd, bytes, left);
            if (written < 0) {
                if (errno == EINTR)
                    continue;
                break;
            }
            bytes += written;
            left -= (size_t)written;
        }
        close(fd);
    });
}

#pragma mark Reading

-(dispatch_source_t)readSourceForDescriptor:(int)fd isOutput:(BOOL)isOutput {
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _queue);
    dispatch_source_set_event_handler(source, ^{ [self readAvailableFrom:fd isOutput:isOutput]; });
    //a descriptor must not be closed before the source that watches it is cancelled
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);
    return source;
}

//everything that can be read now
-(void)readAvailableFrom:(int)fd isOutput:(BOOL)isOutput {
    uint8_t buffer[65536];
    for (;;) {
        ssize_t count = read(fd, buffer, sizeof buffer);
        if (count > 0) {
            [self received:[NSData dataWithBytes:buffer length:(NSUInteger)count] isOutput:isOutput];
            continue;
        }
        if (count < 0 && errno == EINTR)
            continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            return;                                             //nothing more for now
        break;                                                  //0: the end of the output (or an error, which is the same)
    }
    if (isOutput) {
        if (!_outputDone && _outputSource != nil)
            dispatch_source_cancel(_outputSource);
        _outputDone = YES;
    } else {
        if (!_errorDone && _errorSource != nil)
            dispatch_source_cancel(_errorSource);
        _errorDone = YES;
    }
    [self finishIfDone];
}

-(void)received:(NSData*)data isOutput:(BOOL)isOutput {
    if (_finished)
        return;
    if (isOutput) {
        if (self.onOutput != nil)
            self.onOutput(data);
        return;
    }
    [_errorTail appendData:data];
    if (_errorTail.length > kErrorTailLimit * 2)
        [_errorTail replaceBytesInRange:NSMakeRange(0, _errorTail.length - kErrorTailLimit) withBytes:NULL length:0];
}

#pragma mark Ending

//Told when the program ends, and its end collected (a zombie is left until then). The check made at once catches a program that
//ended before the watch was set.
-(void)watchExit {
    _exitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)_pid, DISPATCH_PROC_EXIT, _queue);
    dispatch_source_set_event_handler(_exitSource, ^{ [self collectExitBlocking:YES]; });
    dispatch_resume(_exitSource);
    dispatch_async(_queue, ^{ [self collectExitBlocking:NO]; });
}

-(void)collectExitBlocking:(BOOL)blocking {
    if (_exited)
        return;
    int status = 0;
    pid_t result;
    do {
        result = waitpid(_pid, &status, blocking ? 0 : WNOHANG);
    } while (result < 0 && errno == EINTR);
    if (result == 0)
        return;                                                 //still running
    if (result == _pid && WIFEXITED(status)) {
        _status = WEXITSTATUS(status);
    } else if (result == _pid && WIFSIGNALED(status)) {
        _status = WTERMSIG(status);
        _signaled = YES;
    } else {
        _status = 1;                                            //somebody else collected it: the end is known, the status is not
    }
    __atomic_store_n(&_exited, YES, __ATOMIC_RELEASE);
    if (_exitSource != nil) {
        dispatch_source_cancel(_exitSource);
        _exitSource = nil;
    }
    [self armDrainDeadline];
    [self finishIfDone];
}

//A child of the program may keep the output open after the program has ended (a server it started): the run does not wait for it.
-(void)armDrainDeadline {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.drainTimeout * NSEC_PER_SEC)), _queue, ^{
        if (self->_finished)
            return;
        if (!self->_outputDone)
            [self readAvailableFrom:self->_outputFd isOutput:YES];
        if (!self->_errorDone)
            [self readAvailableFrom:self->_errorFd isOutput:NO];
        [self finish];
    });
}

-(void)finishIfDone {
    if (!_finished && _exited && _outputDone && _errorDone)
        [self finish];
}

-(void)finish {
    if (_finished)
        return;
    _finished = YES;
    if (_outputSource != nil)
        dispatch_source_cancel(_outputSource);                  //the cancel handlers close the descriptors
    if (_errorSource != nil)
        dispatch_source_cancel(_errorSource);
    NSData* tail = _errorTail.length > kErrorTailLimit ? [_errorTail subdataWithRange:NSMakeRange(_errorTail.length - kErrorTailLimit, kErrorTailLimit)] : _errorTail;
    NSString* text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:tail encoding:NSISOLatin1StringEncoding] ?: @"";
    void (^onExit)(int, BOOL, NSString*) = self.onExit;
    self.onExit = nil;
    self.onOutput = nil;
    if (onExit != nil)
        onExit(_status, _signaled, text);
}

-(void)terminate {
    dispatch_async(_queue, ^{
        if (self->_terminating || self->_pid <= 0)
            return;
        self->_terminating = YES;
        pid_t pid = self->_pid;
        //what it started, even when it left the group of the program (a child that made a session of its own)
        NSDictionary<NSNumber*, NSNumber*>* tree = self->_exited ? @{} : ProcessTree(pid);
        BOOL leader = !self->_exited;                           //only while the program is not collected is its number its own
        if (leader)
            killpg(pid, SIGTERM);
        for (NSNumber* each in tree)
            kill(each.intValue, SIGTERM);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGracePeriod * NSEC_PER_SEC)), self->_queue, ^{
            if (leader && !self->_exited)
                killpg(pid, SIGKILL);
            for (NSNumber* each in tree) {
                uint64_t start = 0;
                if (StartTimeOfProcess(each.intValue, &start) && start == tree[each].unsignedLongLongValue)
                    kill(each.intValue, SIGKILL);
            }
        });
    });
}

#pragma mark Capturing

+(void)captureOutputOfExecutable:(NSString*)executable arguments:(NSArray<NSString*>*)arguments environment:(NSDictionary<NSString*, NSString*>*)environment
                         timeout:(NSTimeInterval)timeout limit:(NSUInteger)limit
                      completion:(void (^)(NSData*, NSString*, NSError*))completion {
    AIAgentProcess* process = [[AIAgentProcess alloc] init];
    NSMutableData* collected = [NSMutableData data];
    __block BOOL timedOut = NO;
    process.onOutput = ^(NSData* data) {
        if (collected.length < limit)
            [collected appendData:data];
    };
    process.onExit = ^(int status, BOOL signaled, NSString* errorOutput) {
        NSData* output = [collected copy];
        NSError* failure = nil;
        if (timedOut)
            failure = [NSError errorWithDomain:VOKAIErrorDomain code:VOKAIErrorServer userInfo:@{NSLocalizedDescriptionKey: @"Chương trình không trả lời kịp."}];
        else if (status != 0 || signaled)
            failure = [NSError errorWithDomain:VOKAIErrorDomain code:VOKAIErrorServer userInfo:@{NSLocalizedDescriptionKey:
                           [NSString stringWithFormat:@"Chương trình dừng với mã %d.", status]}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(output, errorOutput, failure); });
    };
    NSError* launchError = nil;
    NSString* directory = NSTemporaryDirectory();
    if (![process launchExecutable:executable arguments:arguments environment:environment directory:directory input:nil error:&launchError]) {
        NSError* failure = [NSError errorWithDomain:VOKAIErrorDomain code:VOKAIErrorNoProgram userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Không chạy được chương trình: %@", launchError.localizedDescription ?: @""]}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, failure); });
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (process.running) {
            timedOut = YES;
            [process terminate];
        }
    });
}

@end
