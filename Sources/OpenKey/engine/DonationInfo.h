//
//  DonationInfo.h
//  VOpenKey
//
//  Who donations go to, for the programs that cannot read marketing/pricing/pricing.json at run time (the Windows donate window). The
//  same payee as marketing/pricing/pricing.json and as VOK_DONATE_* of the macOS AppInfo.h: engine/tests/donation_info_test.cpp
//  compares this file with the JSON, and tests/donation_test.m compares it with AppInfo.h, so that a change made in one place and
//  forgotten in another fails a test. Plain C, ASCII.
//
//  The QR code of the bank account is a picture made from these values, engine/donation/donation-qr.bmp (scripts/make-donation-qr.sh):
//  after a change here it is made again, and tests/donation_test.m reads it back and compares what it says with the macOS payload.
//
#ifndef DonationInfo_h
#define DonationInfo_h

#define VOK_DONATION_BANK_NAME    "VPBank"
#define VOK_DONATION_BANK_BIN     "970432"
#define VOK_DONATION_ACCOUNT_NO   "0988181872"
#define VOK_DONATION_ACCOUNT_NAME "NGUYEN TAN VINH"
//what the bank shows as the note of the transfer: ASCII, a QR field holds 99 characters at most
#define VOK_DONATION_NOTE         "VOpenKey AI donate"
#define VOK_DONATION_PAYPAL_URL   "https://paypal.me/ntanvinh"
#define VOK_DONATION_PAYPAL_NAME  "Vinh Nguyen"

#endif /* DonationInfo_h */
