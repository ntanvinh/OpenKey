//
//  CapsLockIcon.h
//  VOpenKey AI, portable
//
//  The pixels of the tray icon of the time Caps Lock is on (Windows): a red rounded tile with the letter of the usual icon (the "V" or the
//  "E") in white on it, so that the icon reads as "red" whichever colour the usual one has (the Vietnamese one is already a light red).
//  Only the arithmetic is here, so that it is tested on any machine; the Windows side reads the pixels of the icon and makes an icon of
//  the result. ASCII-only source.
//
#pragma once
#include <stdint.h>

namespace vcaps {

/** The red of the tile: R, G, B. White letters on it have a contrast of about 4.8 to 1. */
const uint8_t kTileRed = 220;
const uint8_t kTileGreen = 38;
const uint8_t kTileBlue = 38;

/**
 * `source` is width x height pixels of 0xAARRGGBB with straight (not premultiplied) alpha, the usual icon with the transparent parts
 * transparent; only its alpha is looked at (the shape of the letter). `result` gets the same number of pixels, 0xAARRGGBB with
 * PREMULTIPLIED alpha: the corners outside the rounded tile transparent (smoothed at the edge), the tile red, the letter white, the
 * edge of the letter blended. Does nothing for a null pointer or a size under 4 x 4 or over 512 x 512.
 */
void redTileIcon(const uint32_t* source, int width, int height, uint32_t* result);

/**
 * The Vietnamese icon of the same time: the flag of Vietnam, a red tile (218, 37, 29) with a yellow five pointed star (255, 230, 0)
 * in the middle. Same output format and limits as redTileIcon; no source is needed.
 */
void vietnamFlagIcon(int width, int height, uint32_t* result);

} // namespace vcaps
