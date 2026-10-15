//
//  ShortcutConflicts.m
//  VOpenKey
//

#import "ShortcutConflicts.h"
#import "ShortcutRecorder.h"
#import "AISettings.h"
#import "SnippetPalette.h"
#import "WordRestore.h"
#import "CaseBar.h"

extern int vSwitchKeyStatus;
extern int convertToolHotKey;

NSString* VOKShortcutConflict(int data, VOKShortcutOwner owner) {
    if (owner != VOKShortcutOwnerSwitch && VOKShortcutsEqual(data, vSwitchKeyStatus))
        return @"Chuyển chế độ gõ";
    if (owner != VOKShortcutOwnerConvert && VOKShortcutsEqual(data, convertToolHotKey))
        return @"Chuyển mã nhanh";
    if (owner != VOKShortcutOwnerSnippet && vSnippetsEnabled && VOKShortcutsEqual(data, vSnippetHotKey))
        return @"Mở snippet";
    if (owner != VOKShortcutOwnerRestore && VOKShortcutsEqual(data, vRestoreHotKey))
        return @"Khôi phục từ đang gõ";
    if (owner != VOKShortcutOwnerAI && vAIEnabled && VOKShortcutsEqual(data, vAIHotKey))
        return @"Mở trợ lý AI";
    if (owner != VOKShortcutOwnerCaseBar && VOKShortcutsEqual(data, vCaseBarHotKey))
        return @"Đổi chữ hoa/thường";
    return nil;
}
