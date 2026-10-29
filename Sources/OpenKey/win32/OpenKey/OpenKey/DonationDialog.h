//
//  DonationDialog.h
//  VOpenKey AI, Windows
//
//  The "Ủng hộ VOpenKey AI" window, the same screen as the one of the macOS program and of VMonitor AI:
//  - "Việt Nam": the VietQR code of the bank account (the donor types the amount in the banking app) and the account details, each
//    with a "Sao chép" button. "Quốc tế": the PayPal address, copied or opened in the browser.
//  - "Tôi đã ủng hộ" is the user's own word, nothing is checked: the window thanks them and the "Ủng hộ" item of the tray menu goes
//    away. "Bấm nhầm? Hoàn tác" takes it back. The window of the features keeps a way in whatever was said.
//  - Esc closes it. It opens on "Việt Nam" when the language of the user's Windows is Vietnamese, on "Quốc tế" otherwise.
//
//  The payee is in engine/DonationInfo.h; the QR code is the picture engine/donation/donation-qr.bmp (a resource of the program),
//  made by scripts/make-donation-qr.sh from the same code as the macOS window, because Windows has no QR encoder of its own.
//
#pragma once
#include "stdafx.h"

extern int vDonationAcknowledged;   //saved in the registry like the other settings of OpenKey

namespace DonationDialog {

/// Opens the window in front of the others. Call from the message loop (FeatureActions::OpenDonation).
void show();
bool isVisible();

/// What the user said. Setting it saves it; the tray menu looks at it every time it is opened.
bool acknowledged();
void setAcknowledged(bool value);

} // namespace DonationDialog
