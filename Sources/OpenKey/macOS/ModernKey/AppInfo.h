//
//  AppInfo.h
//  VOpenKey
//
//  Names, identifiers and links of the app in one place, so renaming the app or moving its repository
//  does not mean hunting through the code.
//

#ifndef AppInfo_h
#define AppInfo_h

//The name of the app is "VOpenKey AI", the owner's decision (confirmed 2026-10-16). Not "VOpenKey": do not shorten it in anything a person
//reads or launches. See CLAUDE.md for what stays plain "VOpenKey" on purpose.
#define VOK_APP_NAME            @"VOpenKey AI"
//the folder in ~/Library/Application Support: not the display name, so renaming the app does not orphan the user's data
#define VOK_DATA_DIR_NAME       @"VOpenKey"
#define VOK_BUNDLE_ID           @"vn.io.lssoft.vopenkey"
#define VOK_COMPANY             @"LSSoft"
#define VOK_COMPANY_EMAIL       @"lssoft.adm@gmail.com"

//the app this one is forked from, its settings are imported on first launch and it must not run at the same time
#define VOK_LEGACY_BUNDLE_ID    @"com.tuyenmai.openkey"
#define VOK_UPSTREAM_AUTHOR     @"Mai Vũ Tuyên"
#define VOK_UPSTREAM_URL        @"https://github.com/tuyenvm/OpenKey"

#define VOK_REPO_URL            @"https://github.com/ntanvinh/OpenKey"
#define VOK_RELEASES_URL        @"https://github.com/ntanvinh/OpenKey/releases/latest"

//Updates (AppUpdater): the newest release of the repository above is read from the GitHub API, its dmg (VOpenKey-<version>.dmg) is
//downloaded and installed over the running app. Only an app signed by this Apple Developer Team is ever installed.
#define VOK_RELEASE_API_URL     @"https://api.github.com/repos/ntanvinh/OpenKey/releases/latest"
//the start of the name of the files of a release, VOpenKey-<version>.dmg: APP_NAME of scripts/common.sh (no spaces, on purpose, see CLAUDE.md)
#define VOK_RELEASE_FILE_NAME   @"VOpenKey"
#define VOK_TEAM_ID             @"39SH232CQ4"

//Who donations go to (Donation, DonationWindow): the same payee as marketing/pricing/pricing.json, which tests/donation_test.m compares
//with these values. The QR code is a static VietQR for this account; PayPal is the way to pay from abroad.
#define VOK_DONATE_BANK_NAME    @"VPBank"
//the NAPAS code of that bank (api.vietqr.io/v2/banks): the QR code is only made while the bank above is the one this code belongs to
#define VOK_DONATE_BANK_BIN     @"970432"
#define VOK_DONATE_ACCOUNT_NO   @"0988181872"
#define VOK_DONATE_ACCOUNT_NAME @"NGUYEN TAN VINH"
//what the donor's bank shows as the transfer note: ASCII only, a QR field cannot hold more than 99 characters
#define VOK_DONATE_NOTE         @"VOpenKey AI donate"
#define VOK_DONATE_PAYPAL_URL   @"https://paypal.me/ntanvinh"
#define VOK_DONATE_PAYPAL_NAME  @"Vinh Nguyen"

#endif /* AppInfo_h */
