//
//  MacroViewController.mm
//  OpenKey
//
//  Created by Tuyen on 8/4/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "VOKUI.h"
#import "MacroPresets.h"
#import "MacroViewController.h"
#include "Engine.h"

#define MACRO_ADD_TEXT @"Thêm"
#define MACRO_EDIT_TEXT @"Sửa"

@interface MacroViewController ()

@end

@implementation MacroViewController{
    vector<vector<Uint32>> keys;
    vector<string> macroText;
    vector<string> macroContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    
    self.macroName.delegate = self;
    self.macroContent.delegate = self;
    
    self.AutoCapsMacro.state = vAutoCapsMacro ? NSControlStateValueOn : NSControlStateValueOff;

    //Add is the main action of the window: the default button, answering to Return. Delete is red, and has no
    //shortcut of its own (a bare letter as a shortcut would be taken by the text fields)
    self.buttonAdd.keyEquivalent = @"\r";
    NSButton* deleteButton = VOKFindButton(self.view, @selector(onDeleteMacro:));
    deleteButton.keyEquivalent = @"";
    deleteButton.hasDestructiveAction = YES;
    
    //load data
    getAllMacro(keys, macroText, macroContent);

    //the common abbreviations can be added from here too, next to the other ways of filling the table
    NSButton* export_ = VOKFindButton(self.view, @selector(onExportToFile:));
    if (export_ != nil) {
        NSButton* presets = [NSButton buttonWithTitle:@"Gõ tắt mẫu…" target:self action:@selector(onAddPresets:)];
        presets.bezelStyle = NSBezelStyleRounded;
        presets.toolTip = @"Thêm các từ viết tắt thông dụng của tiếng Việt";
        presets.autoresizingMask = export_.autoresizingMask;
        [presets sizeToFit];
        NSRect frame = presets.frame;
        frame.origin = NSMakePoint(NSMaxX(export_.frame) + 12, export_.frame.origin.y + (NSHeight(export_.frame) - NSHeight(frame)) / 2);
        presets.frame = frame;
        NSRect check = self.AutoCapsMacro.frame;
        check.origin.x = NSMaxX(frame) + 16;
        self.AutoCapsMacro.frame = check;
        [self.view addSubview:presets];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(macrosChanged:)
                                                 name:VOKMacrosDidChangeNotification object:nil];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//the row of buttons at the bottom got one more, the window grows to keep the last control inside it
-(void)viewWillAppear {
    [super viewWillAppear];
    NSWindow* window = self.view.window;
    if (window == nil)
        return;
    CGFloat wanted = NSMaxX(self.AutoCapsMacro.frame) + 24;
    NSSize size = window.contentView.frame.size;
    if (size.width < wanted) {
        size.width = wanted;
        [window setContentSize:size];
    }
}

//the table was changed elsewhere (the Settings window added the common abbreviations)
-(void)macrosChanged:(NSNotification*)notification {
    getAllMacro(keys, macroText, macroContent);
    [self.tableView reloadData];
}

-(void)onAddPresets:(id)sender {
    NSUInteger total = 0, missing = 0;
    [MacroPresets countTotal:&total missing:&missing];
    NSAlert* alert = [[NSAlert alloc] init];
    if (missing == 0) {
        alert.messageText = @"Bạn đã có đủ gõ tắt phổ biến";
        alert.informativeText = [NSString stringWithFormat:@"Cả %lu gõ tắt trong bộ này đều đã có trong danh sách của bạn.", (unsigned long)total];
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }
    alert.messageText = @"Thêm gõ tắt phổ biến?";
    alert.informativeText = [NSString stringWithFormat:@"Thêm %lu gõ tắt thông dụng của tiếng Việt, ví dụ %@. Những gõ tắt bạn đã có được giữ nguyên.",
                             (unsigned long)missing, [MacroPresets examples]];
    [alert addButtonWithTitle:[NSString stringWithFormat:@"Thêm %lu gõ tắt", (unsigned long)missing]];
    [alert addButtonWithTitle:@"Hủy"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn)
            [MacroPresets addMissing]; //the notification reloads the table
    }];
}

-(void)saveAndReload {
    getAllMacro(keys, macroText, macroContent);
    [self.tableView reloadData];
    
    vector<Byte> macroData;
    getMacroSaveData(macroData);
    NSData* _data = [NSData dataWithBytes:macroData.data() length:macroData.size()];
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:_data forKey:@"macroData"];
    [self.buttonAdd setTitle:MACRO_ADD_TEXT];
}

- (IBAction)onDeleteMacro:(id)sender {
    if ([[self.macroName stringValue] compare:@""] == 0) {
        [self showMessage:@"Bạn hãy chọn từ cần xoá!"];
        return;
    }
    string text = [[self.macroName stringValue] UTF8String];
    if (deleteMacro(text)) {
        [self saveAndReload];
        self.macroName.stringValue = @"";
        self.macroContent.stringValue = @"";
        [self.macroName becomeFirstResponder];
    }
}

- (IBAction)onAddMacro:(id)sender {
    if ([[self.macroName stringValue] compare:@""] == 0 || [[self.macroContent stringValue] compare:@""] == 0) {
        [self showMessage:@"Bạn hãy nhập từ cần gõ tắt!"];
        return;
    }
    
    string text = [[self.macroName stringValue] UTF8String];
    string content = [[self.macroContent stringValue] UTF8String];

    addMacro(text, content);
    self.macroName.stringValue = @"";
    self.macroContent.stringValue = @"";
    [self.macroName becomeFirstResponder];
    [self saveAndReload];
}

- (IBAction)onLoadFromFile:(id)sender {
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    [openPanel setMessage:@"Chọn file dữ liệu gõ tắt"];
    [openPanel setCanChooseFiles:YES];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowedFileTypes:[NSArray arrayWithObjects:@"txt", nil]];
    [openPanel setExtensionHidden:NO];
    [openPanel setNameFieldStringValue:@"OpenKeyMacro"];
    [openPanel makeKeyAndOrderFront:nil];
    [openPanel setLevel:NSStatusWindowLevel];
    if ([openPanel runModal] == NSModalResponseOK ) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Nạp danh sách gõ tắt từ file"];
        [alert setInformativeText:@"Giữ lại các gõ tắt hiện có và thêm các gõ tắt trong file, hay thay thế hết bằng file?"];
        [alert addButtonWithTitle:@"Giữ lại và thêm"];
        [alert addButtonWithTitle:@"Thay thế"].hasDestructiveAction = YES;
        [alert addButtonWithTitle:@"Hủy"].keyEquivalent = @"\033";
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertThirdButtonReturn)
                return;
            readFromFile(openPanel.URL.path.UTF8String, returnCode == NSAlertFirstButtonReturn);
            [self saveAndReload];
        }];
    }
}

- (IBAction)onExportToFile:(id)sender {
    NSSavePanel* savePanel = [NSSavePanel savePanel];
    savePanel.canCreateDirectories = YES;
    [savePanel setMessage:@"Chọn nơi lưu dữ liệu gõ tắt"];
    [savePanel setTitle:@"Chọn nơi lưu dữ liệu gõ tắt"];
    [savePanel setAllowedFileTypes:[NSArray arrayWithObjects:@"txt", nil]];
    [savePanel setExtensionHidden:NO];
    [savePanel setNameFieldStringValue:@"OpenKeyMacro"];
    if ([savePanel runModal] == NSModalResponseOK) {
        saveToFile(savePanel.URL.path.UTF8String);
    }
}

- (void)showMessage:(NSString*)msg {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setInformativeText:msg];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:@"Gõ tắt"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        
    }];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *textField = [notification object];
    if (textField == self.macroName) {
        string text = [[self.macroName stringValue] UTF8String];
        if (hasMacro(text)) {
            [self.buttonAdd setTitle:MACRO_EDIT_TEXT];
        } else {
            [self.buttonAdd setTitle:MACRO_ADD_TEXT];
        }
    }
}

- (IBAction)onAutoCapButton:(NSButton *)sender {
    NSInteger val = sender.state == NSControlStateValueOn ? 1 : 0;
    vAutoCapsMacro = (int)val;
    [[NSUserDefaults standardUserDefaults] setInteger:vAutoCapsMacro forKey:@"vAutoCapsMacro"];
}

#pragma mark TableView
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return keys.size();
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString* cellId;
    NSTableCellView* v = nil;
    if (tableColumn == tableView.tableColumns[0]) {
        cellId = @"MacroCell";
        v = [tableView makeViewWithIdentifier:cellId owner:self];
        [v.textField setStringValue:[NSString stringWithUTF8String:macroText[row].c_str()]];
    } else if (tableColumn == tableView.tableColumns[1]) {
        cellId = @"ContentCell";
        v = [tableView makeViewWithIdentifier:cellId owner:self];
        [v.textField setStringValue:[NSString stringWithUTF8String:macroContent[row].c_str()]];
    }
    return v;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    [self.macroName setStringValue:[NSString stringWithUTF8String:macroText[row].c_str()]];
    [self.macroContent setStringValue:[NSString stringWithUTF8String:macroContent[row].c_str()]];
    [self.buttonAdd setTitle:MACRO_EDIT_TEXT];
    return YES;
}

@end
