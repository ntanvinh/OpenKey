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

static BOOL HasAnyPrefix(NSString* text, NSArray<NSString*>* prefixes) {
    for (NSString* prefix in prefixes) {
        if ([text hasPrefix:prefix])
            return YES;
    }
    return NO;
}

static BOOL ContainsAny(NSString* text, NSArray<NSString*>* words) {
    for (NSString* word in words) {
        if ([text containsString:word])
            return YES;
    }
    return NO;
}

//Terminals that have a "Secure Keyboard Entry" switch of their own, and where its state is kept
static NSString* SecureKeyboardEntryKey(NSString* bundleIdentifier) {
    if ([bundleIdentifier isEqualToString:@"com.apple.Terminal"])
        return @"SecureKeyboardEntry";
    if ([bundleIdentifier isEqualToString:@"com.googlecode.iterm2"])
        return @"Secure Input";
    return nil;
}

static NSArray<NSDictionary*>* (^sApplicationsProvider)(void);

@implementation SecureInputSuspect

+(NSString*)reasonForBundleIdentifier:(NSString*)bundleIdentifier name:(NSString*)name secureKeyboardEntry:(BOOL)secureKeyboardEntry {
    NSString* bundle = bundleIdentifier.lowercaseString ?: @"";
    NSString* title = name.lowercaseString ?: @"";
    if (SecureKeyboardEntryKey(bundleIdentifier) != nil)
        return secureKeyboardEntry ? @"Secure Keyboard Entry đang bật" : nil;
    if (HasAnyPrefix(bundle, @[@"com.devolutions.", @"com.microsoft.rdc", @"com.apple.remotedesktop", @"com.apple.screensharing", @"com.teamviewer.",
                               @"com.philandro.anydesk", @"com.anydesk.", @"tv.parsec.", @"com.p5sys.jump", @"com.realvnc.", @"com.lemonmojo.royaltsx",
                               @"com.royalapps.", @"com.edovia.screens", @"com.citrix.", @"com.rustdesk.", @"com.splashtop.", @"com.nomachine",
                               @"com.vmware.horizon"]))
        return @"điều khiển từ xa";
    if (HasAnyPrefix(bundle, @[@"com.vmware.fusion", @"com.parallels.", @"org.virtualbox.", @"com.utmapp.utm"]))
        return @"máy ảo";
    if (HasAnyPrefix(bundle, @[@"com.1password.", @"com.agilebits.", @"com.bitwarden.", @"org.keepassxc.", @"com.hicknhacksoftware.macpass",
                               @"com.dashlane.", @"com.lastpass.", @"com.apple.passwords", @"com.enpass.", @"com.keepersecurity."]))
        return @"trình quản lý mật khẩu";
    //nobody listed it, but its name says what it is
    if (ContainsAny(title, @[@"remote desktop", @"anydesk", @"teamviewer", @"vnc viewer", @"rustdesk", @"splashtop"]))
        return @"điều khiển từ xa";
    return nil;
}

+(NSArray<SecureInputSuspect*>*)suspectsAmongApplications:(NSArray<NSDictionary*>*)applications excludingPIDs:(NSArray<NSNumber*>*)pids {
    NSMutableArray* suspects = [NSMutableArray array];
    for (NSDictionary* app in applications) {
        pid_t pid = (pid_t)[app[@"pid"] intValue];
        if (pid <= 0 || [pids containsObject:@(pid)])
            continue;
        NSString* reason = [self reasonForBundleIdentifier:NonEmpty(app[@"bundleID"]) name:app[@"name"]
                                       secureKeyboardEntry:[app[@"secureKeyboardEntry"] boolValue]];
        if (reason != nil)
            [suspects addObject:[[SecureInputSuspect alloc] initWithPID:pid name:app[@"name"] bundleIdentifier:NonEmpty(app[@"bundleID"]) reason:reason]];
    }
    return suspects;
}

//Is the Secure Keyboard Entry switch of that terminal on? NO for an application that has no such switch.
static BOOL SecureKeyboardEntryIsOn(NSString* bundleIdentifier) {
    NSString* key = SecureKeyboardEntryKey(bundleIdentifier);
    if (key == nil)
        return NO;
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)bundleIdentifier);
    BOOL on = value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
    if (value != NULL)
        CFRelease(value);
    return on;
}

+(BOOL)secureKeyboardEntryIsOnForPID:(pid_t)pid {
    if (pid <= 0)
        return NO;
    if (sApplicationsProvider != nil) {
        for (NSDictionary* app in sApplicationsProvider()) {
            if ((pid_t)[app[@"pid"] intValue] == pid)
                return SecureKeyboardEntryKey(app[@"bundleID"]) != nil && [app[@"secureKeyboardEntry"] boolValue];
        }
        return NO;
    }
    return SecureKeyboardEntryIsOn([NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier);
}

+(NSArray<SecureInputSuspect*>*)runningSuspectsExcludingPIDs:(NSArray<NSNumber*>*)pids {
    if (sApplicationsProvider != nil)
        return [self suspectsAmongApplications:sApplicationsProvider() excludingPIDs:pids];
    NSMutableArray* applications = [NSMutableArray array];
    for (NSRunningApplication* app in [NSWorkspace sharedWorkspace].runningApplications) {
        NSString* bundle = app.bundleIdentifier;
        //only a terminal that is running and has the switch on counts: the switch is read for the ones that are there
        [applications addObject:@{@"pid": @(app.processIdentifier), @"name": app.localizedName ?: @"", @"bundleID": bundle ?: @"",
                                  @"secureKeyboardEntry": @(SecureKeyboardEntryIsOn(bundle))}];
    }
    return [self suspectsAmongApplications:applications excludingPIDs:pids];
}

+(void)setApplicationsProvider:(NSArray<NSDictionary*>* (^)(void))provider {
    sApplicationsProvider = [provider copy];
}

-(instancetype)initWithPID:(pid_t)pid name:(NSString*)name bundleIdentifier:(NSString*)bundleIdentifier reason:(NSString*)reason {
    self = [super init];
    if (self) {
        _pid = pid;
        _name = [name copy];
        _bundleIdentifier = [bundleIdentifier copy];
        _reason = [reason copy];
    }
    return self;
}

@end

@implementation SecureInputHolder

//their getters answer an empty array rather than nil
@synthesize earlierReports = _earlierReports, suspects = _suspects;

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

-(instancetype)holderWithDoubt:(NSString*)doubt earlierReports:(NSArray<SecureInputHolder*>*)earlierReports
                      suspects:(NSArray<SecureInputSuspect*>*)suspects {
    SecureInputHolder* copy = [[SecureInputHolder alloc] initWithPID:_pid role:_role processExists:_processExists name:_name
                                                    bundleIdentifier:_bundleIdentifier version:_version path:_path startDate:_startDate
                                                           parentPID:_parentPID parentName:_parentName icon:_icon];
    copy->_doubt = NonEmpty(doubt);
    copy->_earlierReports = [earlierReports copy] ?: @[];
    copy->_suspects = [suspects copy] ?: @[];
    return copy;
}

-(NSArray<SecureInputHolder*>*)earlierReports {
    return _earlierReports ?: @[];
}

-(NSArray<SecureInputSuspect*>*)suspects {
    return _suspects ?: @[];
}

-(BOOL)isEqualToHolder:(SecureInputHolder*)other {
    if (other == self)
        return YES;
    if (other == nil)
        return NO;
    return _pid == other.pid && _role == other.role && _processExists == other.processExists && _parentPID == other.parentPID &&
        SameObject(_name, other.name) && SameObject(_bundleIdentifier, other.bundleIdentifier) &&
        SameObject(_version, other.version) && SameObject(_path, other.path) && SameObject(_parentName, other.parentName) &&
        SameObject(_doubt, other.doubt) &&
        [[self.earlierReports valueForKey:@"pid"] isEqualToArray:[other.earlierReports valueForKey:@"pid"]] &&
        [[self.suspects valueForKey:@"pid"] isEqualToArray:[other.suspects valueForKey:@"pid"]] &&
        [[self.suspects valueForKey:@"reason"] isEqualToArray:[other.suspects valueForKey:@"reason"]];
}

-(NSString*)displayName {
    if (_name.length > 0)
        return _name;
    if (_pid > 0)
        return [NSString stringWithFormat:@"tiến trình %d", _pid];
    return @"một ứng dụng khác";
}

@end
