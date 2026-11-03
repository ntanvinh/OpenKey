//
//  SecureInputHolder.m
//  VOpenKey
//
//  See SecureInputHolder.h
//

#import "SecureInputHolder.h"
#import <libproc.h>
#import <errno.h>
#import <signal.h>

static BOOL SameObject(id a, id b) {
    return a == b || [a isEqual:b];
}

//Programs that belong to macOS itself, which an "app" that is not an ordinary one (login window, SecurityAgent...) is
static BOOL IsSystemProgramPath(NSString* path) {
    for (NSString* prefix in @[@"/System/", @"/usr/", @"/bin/", @"/sbin/"]) {
        if ([path hasPrefix:prefix])
            return YES;
    }
    return NO;
}

//proc_name() and proc_pidpath() give nothing for a process of another user or one that is gone
static NSString* ProcessName(pid_t pid) {
    char buffer[2 * MAXCOMLEN + 1] = {0};
    if (proc_name(pid, buffer, sizeof(buffer)) <= 0)
        return nil;
    return [NSString stringWithUTF8String:buffer];
}

static NSString* ProcessPath(pid_t pid) {
    char buffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(pid, buffer, sizeof(buffer)) <= 0)
        return nil;
    return [NSString stringWithUTF8String:buffer];
}

static NSString* NonEmpty(NSString* text) {
    return text.length > 0 ? text : nil;
}

@implementation SecureInputHolder

+(SecureInputHolderRole)roleForSessionInFront:(BOOL)sessionInFront holderPID:(pid_t)holderPID processExists:(BOOL)processExists
                                   regularApp:(BOOL)regularApp systemProgram:(BOOL)systemProgram frontmostPID:(pid_t)frontmostPID {
    if (!sessionInFront)
        return SecureInputHolderRoleLockedSession;
    if (holderPID <= 0 || !processExists)
        return SecureInputHolderRoleUnknown;
    if (regularApp)
        return holderPID == frontmostPID ? SecureInputHolderRoleFrontApp : SecureInputHolderRoleBackgroundApp;
    return systemProgram ? SecureInputHolderRoleSystem : SecureInputHolderRoleHelper;
}

+(instancetype)holderForPID:(pid_t)pid sessionInFront:(BOOL)sessionInFront frontmostPID:(pid_t)frontmostPID {
    if (pid <= 0) {
        SecureInputHolderRole role = [self roleForSessionInFront:sessionInFront holderPID:0 processExists:NO regularApp:NO
                                                   systemProgram:NO frontmostPID:frontmostPID];
        return [[SecureInputHolder alloc] initWithPID:0 role:role processExists:NO name:nil bundleIdentifier:nil version:nil path:nil
                                            startDate:nil parentPID:0 parentName:nil icon:nil];
    }

    BOOL exists = kill(pid, 0) == 0 || errno == EPERM;
    NSRunningApplication* app = exists ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid] : nil;

    NSString* name = NonEmpty(app.localizedName) ?: NonEmpty(ProcessName(pid));
    NSString* programPath = ProcessPath(pid);
    NSString* path = NonEmpty(app.bundleURL.path) ?: programPath;

    NSString* version = nil;
    if (app.bundleURL != nil) {
        NSDictionary* info = [NSBundle bundleWithURL:app.bundleURL].infoDictionary;
        NSString* shortVersion = NonEmpty(info[@"CFBundleShortVersionString"]);
        NSString* build = NonEmpty(info[@"CFBundleVersion"]);
        if (shortVersion != nil && build != nil && ![shortVersion isEqualToString:build])
            version = [NSString stringWithFormat:@"%@ (%@)", shortVersion, build];
        else
            version = shortVersion ?: build;
    }

    NSDate* started = app.launchDate;
    pid_t parentPID = 0;
    struct proc_bsdinfo bsd;
    if (exists && proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, PROC_PIDTBSDINFO_SIZE) == PROC_PIDTBSDINFO_SIZE) {
        if (bsd.pbi_start_tvsec > 0)
            started = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)bsd.pbi_start_tvsec];
        //launchd (1) starts everything that was opened from the Dock or Finder: not worth a line
        if (bsd.pbi_ppid > 1)
            parentPID = (pid_t)bsd.pbi_ppid;
    }
    NSString* parentName = nil;
    if (parentPID > 0)
        parentName = NonEmpty([NSRunningApplication runningApplicationWithProcessIdentifier:parentPID].localizedName) ?: NonEmpty(ProcessName(parentPID));

    //NSApplicationActivationPolicyRegular is an ordinary app with a Dock icon
    BOOL regular = app != nil && app.activationPolicy == NSApplicationActivationPolicyRegular;
    SecureInputHolderRole role = [self roleForSessionInFront:sessionInFront holderPID:pid processExists:exists regularApp:regular
                                               systemProgram:IsSystemProgramPath(programPath ?: path) frontmostPID:frontmostPID];

    return [[SecureInputHolder alloc] initWithPID:pid role:role processExists:exists name:name bundleIdentifier:NonEmpty(app.bundleIdentifier)
                                          version:version path:path startDate:started parentPID:parentPID parentName:parentName icon:app.icon];
}

-(instancetype)initWithPID:(pid_t)pid role:(SecureInputHolderRole)role processExists:(BOOL)processExists name:(NSString*)name
          bundleIdentifier:(NSString*)bundleIdentifier version:(NSString*)version path:(NSString*)path startDate:(NSDate*)startDate
                 parentPID:(pid_t)parentPID parentName:(NSString*)parentName icon:(NSImage*)icon {
    self = [super init];
    if (self) {
        _pid = pid;
        _role = role;
        _processExists = processExists;
        _name = [name copy];
        _bundleIdentifier = [bundleIdentifier copy];
        _version = [version copy];
        _path = [path copy];
        _startDate = [startDate copy];
        _parentPID = parentPID;
        _parentName = [parentName copy];
        _icon = icon;
    }
    return self;
}

-(BOOL)isEqualToHolder:(SecureInputHolder*)other {
    if (other == self)
        return YES;
    if (other == nil)
        return NO;
    return _pid == other.pid && _role == other.role && _processExists == other.processExists && _parentPID == other.parentPID &&
        SameObject(_name, other.name) && SameObject(_bundleIdentifier, other.bundleIdentifier) &&
        SameObject(_version, other.version) && SameObject(_path, other.path) && SameObject(_parentName, other.parentName);
}

-(NSString*)displayName {
    if (_name.length > 0)
        return _name;
    if (_pid > 0)
        return [NSString stringWithFormat:@"tiến trình %d", _pid];
    return @"một ứng dụng khác";
}

@end
