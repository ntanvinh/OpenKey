//
//  CapsLockIcon.cpp
//  VOpenKey AI, portable. ASCII-only source.
//
#include "CapsLockIcon.h"

namespace vcaps {

namespace {

const int kSamples = 4;     //4 x 4 samples for each pixel at the edge of the tile

/** Is the point (x, y) (in pixels, the pixel (i, j) covers i..i+1) inside the rounded rectangle of the whole icon? */
bool inside(double x, double y, double width, double height, double radius) {
    if (x < 0 || y < 0 || x > width || y > height)
        return false;
    double cx = x < radius ? radius : (x > width - radius ? width - radius : x);
    double cy = y < radius ? radius : (y > height - radius ? height - radius : y);
    double dx = x - cx, dy = y - cy;
    return dx * dx + dy * dy <= radius * radius;
}

/** How much of the pixel (i, j) is in the tile: 0 to 255. */
int coverage(int i, int j, int width, int height, double radius) {
    int count = 0;
    for (int sy = 0; sy < kSamples; sy++)
        for (int sx = 0; sx < kSamples; sx++)
            if (inside(i + (sx + 0.5) / kSamples, j + (sy + 0.5) / kSamples, width, height, radius))
                count++;
    return (count * 255 + kSamples * kSamples / 2) / (kSamples * kSamples);
}

/** Is (x, y) inside the star with the centre (cx, cy) and the outer radius r (points up)? Even-odd rule over the 10 corners. */
bool inStar(double x, double y, double cx, double cy, double r) {
    double px[10], py[10];
    for (int i = 0; i < 10; i++) {
        double angle = (-90 + i * 36) * 3.14159265358979323846 / 180.0;
        double radius = i % 2 == 0 ? r : r * 0.381966;
        //cos and sin by Taylor series would be overkill: the table of a star is fixed
        static const double c[10] = {0.0, 0.587785, 0.951057, 0.951057, 0.587785, 0.0, -0.587785, -0.951057, -0.951057, -0.587785};
        static const double s[10] = {-1.0, -0.809017, -0.309017, 0.309017, 0.809017, 1.0, 0.809017, 0.309017, -0.309017, -0.809017};
        (void)angle;
        px[i] = cx + radius * c[i];
        py[i] = cy + radius * s[i];
    }
    bool in = false;
    for (int i = 0, j = 9; i < 10; j = i++) {
        if ((py[i] > y) != (py[j] > y) && x < (px[j] - px[i]) * (y - py[i]) / (py[j] - py[i]) + px[i])
            in = !in;
    }
    return in;
}

} // namespace

void vietnamFlagIcon(int width, int height, uint32_t* result) {
    if (result == 0 || width < 4 || height < 4 || width > 512 || height > 512)
        return;
    double radius = (width < height ? width : height) / 5.0;
    double side = width < height ? width : height;
    double cx = width / 2.0, cy = height / 2.0 + side * 0.03, r = side * 0.34;
    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int cover = coverage(i, j, width, height, radius);
            int count = 0;
            for (int sy = 0; sy < kSamples; sy++)
                for (int sx = 0; sx < kSamples; sx++)
                    if (inStar(i + (sx + 0.5) / kSamples, j + (sy + 0.5) / kSamples, cx, cy, r))
                        count++;
            int star = (count * 255 + kSamples * kSamples / 2) / (kSamples * kSamples);
            int red = (218 * (255 - star) + 255 * star + 127) / 255;
            int green = (37 * (255 - star) + 230 * star + 127) / 255;
            int blue = (29 * (255 - star) + 0 * star + 127) / 255;
            uint32_t pr = (uint32_t)((red * cover + 127) / 255);
            uint32_t pg = (uint32_t)((green * cover + 127) / 255);
            uint32_t pb = (uint32_t)((blue * cover + 127) / 255);
            result[j * width + i] = ((uint32_t)cover << 24) | (pr << 16) | (pg << 8) | pb;
        }
    }
}

void redTileIcon(const uint32_t* source, int width, int height, uint32_t* result) {
    if (source == 0 || result == 0 || width < 4 || height < 4 || width > 512 || height > 512)
        return;
    //the corners of the tile: a fifth of the short side, like the rounded flag of the menu bar icon of the Mac
    double radius = (width < height ? width : height) / 5.0;
    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int cover = coverage(i, j, width, height, radius);
            int letter = (int)(source[j * width + i] >> 24);      //0 to 255
            //tile colour towards white by the alpha of the letter
            int red = (kTileRed * (255 - letter) + 255 * letter + 127) / 255;
            int green = (kTileGreen * (255 - letter) + 255 * letter + 127) / 255;
            int blue = (kTileBlue * (255 - letter) + 255 * letter + 127) / 255;
            //premultiplied by the coverage of the tile
            uint32_t r = (uint32_t)((red * cover + 127) / 255);
            uint32_t g = (uint32_t)((green * cover + 127) / 255);
            uint32_t b = (uint32_t)((blue * cover + 127) / 255);
            result[j * width + i] = ((uint32_t)cover << 24) | (r << 16) | (g << 8) | b;
        }
    }
}

} // namespace vcaps
