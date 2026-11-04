//
//  SuggestAppearance.cpp
//  VOpenKey AI, portable
//
#include "SuggestAppearance.h"

namespace vsuggest {
namespace appearance {

int clampTransparency(int percent) {
    if (percent < 0)
        return 0;
    return percent > kMaxTransparency ? kMaxTransparency : percent;
}

int clampHoverTransparency(int hover, int normal) {
    if (hover < 1)
        hover = 1;
    if (hover > kMaxHoverTransparency)
        hover = kMaxHoverTransparency;
    return hover < normal + 1 ? normal + 1 : hover;
}

int hoverAfterTransparencyChange(int hover, int normal) {
    return hover <= normal ? normal + 1 : hover;
}

int alphaForTransparency(int percent) {
    if (percent < 0)
        percent = 0;
    if (percent > 100)
        percent = 100;
    return ((100 - percent) * 255 + 50) / 100;  //rounded: 0% is 255, 85% is 38, 100% is 0
}

} // namespace appearance
} // namespace vsuggest
