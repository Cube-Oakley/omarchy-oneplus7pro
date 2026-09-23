#pragma once

#include <QImage>
#include <QString>

struct StillInfo;

namespace StillWriter {

// Turns the frame upright, saves it as a JPEG in folder and returns the
// path, or an empty string with *error set. Runs off the GUI thread.
QString write(const QImage &frame, const StillInfo &info, const QString &folder,
              QString *error);

} // namespace StillWriter
