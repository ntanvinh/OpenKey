//
//  SuggestAppearance.h
//  VOpenKey AI, portable
//
//  How see-through the suggestion bar is: the rules of the two sliders of Settings > Suggestions, the same on macOS
//  (SuggestionPanel.m keeps the same numbers) and Windows. A percentage of transparency is what the user sees; the bar is
//  drawn with an opacity of 100 minus it. ASCII-only source.
//
#pragma once

namespace vsuggest {
namespace appearance {

const int kMaxTransparency = 80;          //the normal level: never so faint that the bar cannot be read
const int kMaxHoverTransparency = 95;
const int kDefaultTransparency = 0;
const int kDefaultHoverTransparency = 85;

/** The normal level, kept between 0 and kMaxTransparency. */
int clampTransparency(int percent);

/**
 * The level while the pointer is on the bar: between 1 and kMaxHoverTransparency, and always at least one point more
 * transparent than `normal`, or hovering would change nothing. `normal` is a level already clamped.
 */
int clampHoverTransparency(int hover, int normal);

/**
 * The hover level to keep after the normal level was changed to `normal`: unchanged, unless the bar would no longer fade
 * on hover, then one point above the normal level.
 */
int hoverAfterTransparencyChange(int hover, int normal);

/** The opacity, 0 to 255 (the alpha of a layered window), of a bar that is `percent` transparent. */
int alphaForTransparency(int percent);

} // namespace appearance
} // namespace vsuggest
