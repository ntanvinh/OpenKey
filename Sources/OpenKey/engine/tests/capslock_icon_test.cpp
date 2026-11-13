//
//  The pixels of the red tray icon of the time Caps Lock is on. ASCII-only source.
//
#include "../CapsLockIcon.h"
#include <cstdio>
#include <vector>

using namespace vcaps;

static int failures;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int A(uint32_t p) { return (int)(p >> 24); }
static int R(uint32_t p) { return (int)((p >> 16) & 255); }
static int G(uint32_t p) { return (int)((p >> 8) & 255); }
static int B(uint32_t p) { return (int)(p & 255); }

//a "V" like letter: a diagonal stroke from the top left to the bottom middle and one to the top right
static std::vector<uint32_t> letter(int size, uint32_t pixel) {
    std::vector<uint32_t> source((size_t)size * size, 0);
    for (int j = 2; j < size - 2; j++) {
        int left = 2 + (j - 2) * (size / 2 - 3) / (size - 5);
        int right = size - 1 - left;
        source[(size_t)j * size + left] = pixel;
        source[(size_t)j * size + left + 1] = pixel;
        source[(size_t)j * size + right] = pixel;
        source[(size_t)j * size + right - 1] = pixel;
    }
    return source;
}

static void check(int size) {
    std::vector<uint32_t> source = letter(size, 0xFFFF6464u);     //the light red of the usual icon, opaque
    std::vector<uint32_t> result((size_t)size * size, 0xDEADBEEFu);
    redTileIcon(source.data(), size, size, result.data());

    //the corner is outside the rounded tile: nothing there
    CHECK(result[0] == 0);
    CHECK(result[(size_t)size - 1] == 0);
    CHECK(result[(size_t)(size - 1) * size] == 0);
    CHECK(result[(size_t)size * size - 1] == 0);

    //the middle of the left edge is in the tile: solid red
    uint32_t edge = result[(size_t)(size / 2) * size];
    CHECK(A(edge) == 255 && R(edge) == kTileRed && G(edge) == kTileGreen && B(edge) == kTileBlue);

    //a pixel that is not the letter: the red of the tile; the pixel of the letter: white, whatever the colour it had
    uint32_t plain = result[(size_t)(size / 2) * size + size / 2];       //between the strokes at the middle row
    CHECK(A(plain) == 255 && R(plain) == kTileRed && G(plain) == kTileGreen && B(plain) == kTileBlue);
    int j = size / 2;
    int left = 2 + (j - 2) * (size / 2 - 3) / (size - 5);
    uint32_t stroke = result[(size_t)j * size + left];
    CHECK(A(stroke) == 255 && R(stroke) == 255 && G(stroke) == 255 && B(stroke) == 255);

    //every pixel is premultiplied: no colour above the alpha; a pixel at the rounded edge is between nothing and solid
    bool premultiplied = true, partial = false;
    for (size_t k = 0; k < result.size(); k++) {
        if (R(result[k]) > A(result[k]) || G(result[k]) > A(result[k]) || B(result[k]) > A(result[k]))
            premultiplied = false;
        if (A(result[k]) > 0 && A(result[k]) < 255)
            partial = true;
    }
    CHECK(premultiplied);
    CHECK(partial);                                                    //the corners are smoothed

    //the same letter in another colour gives the same icon: only the shape counts
    std::vector<uint32_t> blue = letter(size, 0xFF29ABE2u);
    std::vector<uint32_t> other((size_t)size * size, 0);
    redTileIcon(blue.data(), size, size, other.data());
    CHECK(other == result);

    //a half transparent letter pixel is half way between the tile and white (not premultiplied in the source)
    std::vector<uint32_t> faint = letter(size, 0x80FFFFFFu);
    redTileIcon(faint.data(), size, size, other.data());
    uint32_t half = other[(size_t)j * size + left];
    CHECK(A(half) == 255);
    CHECK(R(half) > kTileRed && R(half) < 255);
    CHECK(G(half) > kTileGreen + 80 && G(half) < 255 - 40);
}

static void checkFlag(int size) {
    std::vector<uint32_t> flag((size_t)size * size, 0xDEADBEEFu);
    vietnamFlagIcon(size, size, flag.data());
    CHECK(flag[0] == 0 && flag[(size_t)size * size - 1] == 0);                 //rounded corners
    uint32_t edge = flag[(size_t)(size / 2) * size];
    CHECK(A(edge) == 255 && R(edge) == 218 && G(edge) == 37 && B(edge) == 29);  //red
    uint32_t middle = flag[(size_t)(size / 2) * size + size / 2];
    CHECK(A(middle) == 255 && R(middle) == 255 && G(middle) == 230 && B(middle) == 0);   //yellow star in the middle
    //the star has five points: the top one is yellow, the row just under the top corners of the tile is red
    uint32_t top = flag[(size_t)(size * 0.30) * size + size / 2];
    uint32_t topLeft = flag[(size_t)(size * 0.30) * size + size / 2 - 1];
    CHECK(G(top) > 80 || G(topLeft) > 80);   // the tip of the star: much more green than the red tile (37)
    uint32_t cornerSide = flag[(size_t)(size * 0.25) * size + size / 5];
    CHECK(R(cornerSide) == 218 && G(cornerSide) == 37);
    int yellow = 0;
    for (size_t k = 0; k < flag.size(); k++) if (G(flag[k]) > 200 && A(flag[k]) == 255) yellow++;
    CHECK(yellow > size * size / 25 && yellow < size * size / 3);
}

int main() {
    checkFlag(16);
    checkFlag(24);
    checkFlag(32);
    checkFlag(48);
    {
        std::vector<uint32_t> untouched(16 * 16, 0x12345678u);
        vietnamFlagIcon(16, 3, untouched.data());
        vietnamFlagIcon(16, 16, 0);
        CHECK(untouched[0] == 0x12345678u);
    }
    check(16);
    check(20);
    check(24);
    check(32);
    check(48);

    //a source with nothing in it: the plain red tile
    std::vector<uint32_t> empty(16 * 16, 0), result(16 * 16, 0);
    redTileIcon(empty.data(), 16, 16, result.data());
    CHECK(R(result[8 * 16 + 8]) == kTileRed && A(result[8 * 16 + 8]) == 255);

    //what is not an icon is left alone
    std::vector<uint32_t> untouched(16 * 16, 0x12345678u);
    redTileIcon(0, 16, 16, untouched.data());
    redTileIcon(empty.data(), 16, 16, 0);
    redTileIcon(empty.data(), 3, 16, untouched.data());
    redTileIcon(empty.data(), 16, 3, untouched.data());
    redTileIcon(empty.data(), 600, 16, untouched.data());
    CHECK(untouched[0] == 0x12345678u && untouched[255] == 0x12345678u);

    //not square
    std::vector<uint32_t> wide(32 * 16, 0), wideResult(32 * 16, 1);
    redTileIcon(wide.data(), 32, 16, wideResult.data());
    CHECK(wideResult[0] == 0 && A(wideResult[8 * 32 + 16]) == 255);

    std::printf(failures ? "FAILED: %d\n" : "ALL OK\n", failures);
    return failures ? 1 : 0;
}
