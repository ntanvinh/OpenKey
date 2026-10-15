//
//  AppInfo.h
//  VOpenKey
//
//  Names, identifiers and links of the app in one place, so renaming the app or moving its repository
//  does not mean hunting through the code.
//

#ifndef AppInfo_h
#define AppInfo_h

#define VOK_APP_NAME            @"VOpenKey AI"
//the folder in ~/Library/Application Support: not the display name, so renaming the app does not orphan the user's data
#define VOK_DATA_DIR_NAME       @"VOpenKey"
#define VOK_BUNDLE_ID           @"vn.io.lssoft.vopenkey"
#define VOK_COMPANY             @"LSSoft"

//the app this one is forked from, its settings are imported on first launch and it must not run at the same time
#define VOK_LEGACY_BUNDLE_ID    @"com.tuyenmai.openkey"
#define VOK_UPSTREAM_AUTHOR     @"Mai Vũ Tuyên"
#define VOK_UPSTREAM_URL        @"https://github.com/tuyenvm/OpenKey"

#define VOK_REPO_URL            @"https://github.com/ntanvinh/OpenKey"
#define VOK_RELEASES_URL        @"https://github.com/ntanvinh/OpenKey/releases/latest"
#define VOK_VERSION_JSON_URL    @"https://raw.githubusercontent.com/ntanvinh/OpenKey/master/version.json"

#endif /* AppInfo_h */
