//
//  OpenKeyManager.h
//  ModernKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#ifndef OpenKeyManager_h
#define OpenKeyManager_h

#import <Cocoa/Cocoa.h>

@interface OpenKeyManager : NSObject
+(BOOL)isInited;
+(BOOL)initEventTap;
+(BOOL)stopEventTap;
+(void)reenableEventTap;

+(NSArray*)getTableCodes;

+(NSString*)getBuildDate;
+(void)showMessage:(NSWindow*)window message:(NSString*)msg subMsg:(NSString*)subMsg;

+(BOOL)quickConvert;

//Updates, see AppUpdater. At launch: installs a downloaded update that was waiting, then looks for a new version and goes on looking
//every few hours (unless "Kiểm tra bản mới" is off); a new version is downloaded by itself when "Tự động tải và cài bản mới" is on.
+(void)startAutomaticUpdates;
//The user asked: looks, and tells the result in any case (a sheet of `parent`, or an alert when it is nil).
+(void)checkNewVersion:(NSWindow*)parent;
//What to say about the new version, by how far it has come: offer it, say it is downloading, or ask to restart.
+(void)showUpdateDialog:(NSWindow*)parent;
//The update is downloaded: restart into it now.
+(void)restartToUpdate:(NSWindow*)parent;
@end

#endif /* OpenKeyManager_h */
