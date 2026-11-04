//
//  The rules of the two transparency sliders of the suggestion bar. The numbers are the ones of macOS' SuggestionPanel.m
//  (normal 0 to 80 percent, on hover 1 to 95 percent and always above the normal level, hover default 85). ASCII-only source.
//
#include "../SuggestAppearance.h"
#include <cstdio>

using namespace vsuggest::appearance;

static int failures;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main() {
    //the normal level
    CHECK(clampTransparency(-5) == 0 && clampTransparency(0) == 0 && clampTransparency(40) == 40);
    CHECK(clampTransparency(80) == 80 && clampTransparency(81) == 80 && clampTransparency(1000) == 80);

    //the hover level: 1 to 95, and one point above the normal level at least
    CHECK(clampHoverTransparency(85, 0) == 85);
    CHECK(clampHoverTransparency(0, 0) == 1);           //never "no change"
    CHECK(clampHoverTransparency(-3, 0) == 1);
    CHECK(clampHoverTransparency(200, 0) == 95);
    CHECK(clampHoverTransparency(10, 40) == 41);        //below the normal level: lifted to just above it
    CHECK(clampHoverTransparency(40, 40) == 41);
    CHECK(clampHoverTransparency(41, 40) == 41);
    CHECK(clampHoverTransparency(95, 80) == 95);        //the highest normal level still leaves room to fade
    CHECK(clampHoverTransparency(50, 80) == 81);

    //the normal level moved: the hover level follows only when it would otherwise stop fading
    CHECK(hoverAfterTransparencyChange(85, 0) == 85);
    CHECK(hoverAfterTransparencyChange(85, 84) == 85);
    CHECK(hoverAfterTransparencyChange(85, 85) == 86);
    CHECK(hoverAfterTransparencyChange(30, 50) == 51);

    //every pair the sliders can make fades on hover
    for (int normal = 0; normal <= kMaxTransparency; normal++) {
        for (int hover = -2; hover <= 102; hover++) {
            int h = clampHoverTransparency(hover, normal);
            CHECK(h > normal && h <= kMaxHoverTransparency);
            CHECK(alphaForTransparency(h) < alphaForTransparency(normal));
        }
    }

    //opacity of a layered window
    CHECK(alphaForTransparency(0) == 255);
    CHECK(alphaForTransparency(85) == 38);              //what Windows used as its fixed hover value before the sliders
    CHECK(alphaForTransparency(80) == 51);
    CHECK(alphaForTransparency(50) == 128);
    CHECK(alphaForTransparency(100) == 0 && alphaForTransparency(150) == 0 && alphaForTransparency(-10) == 255);
    CHECK(kDefaultTransparency == 0 && kDefaultHoverTransparency == 85);

    std::printf(failures == 0 ? "suggest_appearance_test: all passed\n" : "suggest_appearance_test: %d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
