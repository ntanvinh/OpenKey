#!/bin/zsh
# Makes engine/donation/donation-qr.bmp, the QR code that the Windows donate window shows, from the same Donation.m as the macOS window.
# Run it again after the payee changes (AppInfo.h, engine/DonationInfo.h, marketing/pricing/pricing.json); tests/donation_test.m reads the
# picture back and fails when it no longer says what the macOS code says.
set -e
HERE=${0:A:h}
ROOT=${HERE:h}
MAC=$ROOT/Sources/OpenKey/macOS/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -Wall -I"$MAC" -c "$MAC/Donation.m" -o "$WORK/Donation.o"
clang -fobjc-arc -Wall -I"$MAC" -c "$HERE/make-donation-qr.m" -o "$WORK/tool.o"
clang -framework Cocoa -framework CoreImage "$WORK/Donation.o" "$WORK/tool.o" -o "$WORK/make-donation-qr"
"$WORK/make-donation-qr" "$ROOT/Sources/OpenKey/engine/donation/donation-qr.bmp"
