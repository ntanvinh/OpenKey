//
//  AboutPanel.m
//  VOpenKey
//

#import "AboutPanel.h"
#import "AppInfo.h"

@implementation AboutPanel

+(NSAttributedString*)credits {
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.paragraphSpacing = 4;
    NSDictionary* plain = @{NSFontAttributeName: [NSFont systemFontOfSize:11],
                            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                            NSParagraphStyleAttributeName: paragraph};
    NSMutableAttributedString* credits = [[NSMutableAttributedString alloc] init];
    void (^addText)(NSString*) = ^(NSString* text) {
        [credits appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:plain]];
    };
    void (^addLink)(NSString*, NSString*) = ^(NSString* text, NSString* url) {
        NSMutableDictionary* attributes = [plain mutableCopy];
        attributes[NSLinkAttributeName] = [NSURL URLWithString:url];
        [credits appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    };
    addText([NSString stringWithFormat:@"Bộ gõ tiếng Việt cho macOS.\nPhát triển bởi %@.\n\n", VOK_COMPANY]);
    addText([NSString stringWithFormat:@"Fork từ OpenKey của %@,\nphát hành theo giấy phép GPL-3.0.\n\n", VOK_UPSTREAM_AUTHOR]);
    addLink(@"Mã nguồn VOpenKey", VOK_REPO_URL);
    addText(@"  ·  ");
    addLink(@"OpenKey gốc", VOK_UPSTREAM_URL);
    return credits;
}

+(void)show {
    //a menu bar app is not active when its menu item is clicked, and the panel would open behind other windows
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: [self credits]}];
}

@end
