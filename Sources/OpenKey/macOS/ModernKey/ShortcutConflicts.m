//
//  ShortcutConflicts.m
//  VOpenKey
//

#import "ShortcutConflicts.h"
#import "ShortcutRecorder.h"
#import "SnippetPalette.h"
#import "WordRestore.h"

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
    return nil;
}
