//
//  AppDelegate.h
//  ModernKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "AppInfo.h"

//this app's own id: a build with another id (a test build next to the real app) is a different app
#define OPENKEY_BUNDLE ([[NSBundle mainBundle] bundleIdentifier])

@interface AppDelegate : NSObject <NSApplicationDelegate>

-(void)onImputMethodChanged:(BOOL)willNotify;
-(void)onInputMethodSelected;

-(void)showPermissionWindow;

-(void)onInputTypeSelectedIndex:(int)index;
-(void)onCodeTableChanged:(int)index;

-(void)setRunOnStartup:(BOOL)val;
-(void)loadDefaultConfig;

-(void)setGrayIcon:(BOOL)val;

-(void)onMacroSelected;
-(void)onConvertTool;
-(void)onControlPanelSelected;
-(void)onAboutSelected;
-(void)onDonateSelected;
-(void)onAISettingsSelected;
-(void)refreshMenu;
-(void)onQuickConvert;
-(void)setQuickConvertString;

-(void)showIconOnDock:(BOOL)val;
@end

