// Tests of the donation data that the Windows program shows (portable C++): DonationInfo.h against marketing/pricing/pricing.json, and
// the shape of the picture of the QR code (engine/donation/donation-qr.bmp). That the picture says what the macOS code says is checked by
// tests/donation_test.m, which can read a QR code.
//
//   clang++ -std=c++11 -I.. donation_info_test.cpp ../MiniJson.cpp -o /tmp/donation_info_test && /tmp/donation_info_test
#include "DonationInfo.h"
#include "MiniJson.h"
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static std::string readAll(const char* path) {
    std::ifstream f(path, std::ios::binary);
    std::stringstream ss; ss << f.rdbuf();
    return ss.str();
}

static unsigned le(const std::string& b, size_t at, int bytes) {
    unsigned v = 0;
    for (int i = bytes - 1; i >= 0; i--)
        v = (v << 8) | (unsigned char)b[at + (size_t)i];
    return v;
}

int main() {
    // the payee of the JSON is the payee of the header
    vjson::Value pricing;
    CHECK(vjson::parse(readAll("../../../../marketing/pricing/pricing.json"), pricing));
    const vjson::Value& trusted = pricing["payments"]["trusted"];
    CHECK(trusted["domestic"]["bankId"].asString() == VOK_DONATION_BANK_NAME);
    CHECK(trusted["domestic"]["accountNo"].asString() == VOK_DONATION_ACCOUNT_NO);
    CHECK(trusted["domestic"]["accountName"].asString() == VOK_DONATION_ACCOUNT_NAME);
    CHECK(trusted["international"]["provider"].asString() == "paypal");
    CHECK(trusted["international"]["url"].asString() == VOK_DONATION_PAYPAL_URL);
    CHECK(trusted["international"]["accountName"].asString() == VOK_DONATION_PAYPAL_NAME);

    // what a QR field and a link may hold
    std::string note = VOK_DONATION_NOTE, account = VOK_DONATION_ACCOUNT_NO, bin = VOK_DONATION_BANK_BIN;
    CHECK(!note.empty() && note.size() <= 99);
    for (size_t i = 0; i < note.size(); i++) CHECK(note[i] >= 0x20 && note[i] < 0x7f);
    CHECK(!account.empty() && account.size() <= 19 && account.find_first_not_of("0123456789") == std::string::npos);
    CHECK(bin == "970432" && std::string(VOK_DONATION_BANK_NAME) == "VPBank");           // the number of the bank the code is made for
    CHECK(std::string(VOK_DONATION_PAYPAL_URL).compare(0, 8, "https://") == 0);

    // the picture: a 24-bit BMP, square, one pixel per module, every pixel black or white, a white margin, a finder square at the corner
    std::string bmp = readAll("../donation/donation-qr.bmp");
    CHECK(bmp.size() > 54 && bmp[0] == 'B' && bmp[1] == 'M');
    if (bmp.size() > 54) {
        unsigned fileSize = le(bmp, 2, 4), offset = le(bmp, 10, 4), header = le(bmp, 14, 4);
        int width = (int)le(bmp, 18, 4), height = (int)le(bmp, 22, 4);
        unsigned planes = le(bmp, 26, 2), bits = le(bmp, 28, 2), compression = le(bmp, 30, 4);
        CHECK(fileSize == bmp.size() && offset == 54 && header == 40);         // the plain header that every resource compiler reads
        CHECK(planes == 1 && bits == 24 && compression == 0);
        CHECK(width == height && width >= 29 + 8 && width <= 177 + 8);         // version 1 to 40 and a margin
        unsigned rowBytes = (unsigned)((width * 3 + 3) & ~3);
        CHECK(bmp.size() == 54 + (size_t)rowBytes * (size_t)height);
        int blackModules = 0, wrong = 0;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                const unsigned char* p = (const unsigned char*)bmp.data() + 54 + (size_t)(height - 1 - y) * rowBytes + (size_t)x * 3;
                if (!(p[0] == p[1] && p[1] == p[2] && (p[0] == 0 || p[0] == 255))) wrong++;
                if (p[0] == 0) blackModules++;
            }
        }
        CHECK(wrong == 0);
        CHECK(blackModules > width * width / 5 && blackModules < width * width * 3 / 4);   // neither blank nor solid
        // the code itself is a square of 17 + 4 x version modules (version 1 to 40) with the same white margin, at least 4 modules, all round
        int minX = width, maxX = -1, minY = height, maxY = -1;
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                const unsigned char* p = (const unsigned char*)bmp.data() + 54 + (size_t)(height - 1 - y) * rowBytes + (size_t)x * 3;
                if (p[0] != 0) continue;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        int side = maxX - minX + 1;
        CHECK(side == maxY - minY + 1 && side >= 21 && side <= 177 && (side - 17) % 4 == 0);
        CHECK(minX >= 4 && minY >= 4 && minX == width - 1 - maxX && minY == height - 1 - maxY && minX == minY);
        // a finder square: the corner module of the code is black, the module after the 7 of its ring is white
        const unsigned char* corner = (const unsigned char*)bmp.data() + 54 + (size_t)(height - 1 - minY) * rowBytes + (size_t)minX * 3;
        const unsigned char* after = (const unsigned char*)bmp.data() + 54 + (size_t)(height - 1 - minY) * rowBytes + (size_t)(minX + 7) * 3;
        CHECK(corner[0] == 0 && after[0] == 255);
    }

    if (failures == 0)
        printf("donation_info_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
