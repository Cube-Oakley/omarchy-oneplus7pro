#pragma once

#include <QImage>
#include <QSize>
#include <QString>

#include <array>
#include <cstdint>
#include <vector>

// A raw Bayer frame as the sensor delivered it, with the image processor's
// settings for that frame, so the merged photo matches the preview.
struct RawFrame {
    std::vector<uint8_t> data;   // rows of stride bytes, packed as captured
    qint64 exposureUs = 0;
    double analogueGain = 1.0;
    double digitalGain = 1.0;
    std::array<float, 2> colourGains{ 1.0f, 1.0f };   // red, blue
    std::array<float, 9> ccm{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    float saturation = 1.0f;
    float contrast = 1.0f;
    float gamma = 2.2f;
    int blackLevel16 = 4096;     // on a 16-bit scale, as libcamera reports it
};

// How the raw bytes are laid out, from the libcamera pixel format name.
struct RawLayout {
    QSize size;
    unsigned int stride = 0;
    unsigned int bits = 10;
    bool csi2Packed = true;
    // Offsets of the red sample in the 2x2 Bayer pattern.
    int redX = 0;
    int redY = 0;

    // Parses names such as SRGGB10_CSI2P, SGRBG12 or SBGGR16.
    static bool fromName(const QString &name, QSize size, unsigned int stride, RawLayout *layout);
};

struct MergeReport {
    int frames = 0;
    int reference = 0;                         // index of the sharpest frame
    std::vector<double> sharpness;             // per captured frame
    std::vector<std::array<int, 2>> shifts;   // per merged frame, in pixels,
    std::vector<double> rejected;              // reference first: share left out
    qint64 milliseconds = 0;
};

namespace RawMerge {

// Aligns frames to the sharpest, averages what matches, and renders the
// result. Runs off the GUI thread.
QImage process(const std::vector<RawFrame> &frames, const RawLayout &layout,
               MergeReport *report);

// How many frames to merge for a scene at this total gain: one in good
// light, more as noise rises.
int framesForGain(double totalGain);

} // namespace RawMerge
