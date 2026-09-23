#pragma once

#include <QMutex>
#include <QSize>

#include <array>
#include <functional>
#include <optional>

namespace libcamera {
class Request;
}

// One processed frame as the viewfinder needs it: a dma-buf and its layout.
// The request pointer is only a token for giving the buffer back.
struct CameraFrame {
    libcamera::Request *request = nullptr;
    quint64 generation = 0;
    int fd = -1;
    quint32 offset = 0;
    quint32 length = 0;
    QSize size;
    quint32 stride = 0;
    quint32 fourcc = 0; // DRM fourcc of the buffer
    quint64 sequence = 0;
};

// Hands the newest frame from the camera thread to the render thread, and
// frames the viewfinder no longer needs back to the camera. A frame stays
// out for two more frames after it was shown, so the GPU has finished reading
// it before the image processor writes into it again.
class FrameQueue
{
public:
    using Release = std::function<void(const CameraFrame &)>;

    explicit FrameQueue(Release release) : release_(std::move(release)) {}

    // Camera thread: offer a new frame. One not yet shown is given back.
    void publish(const CameraFrame &frame)
    {
        std::optional<CameraFrame> dropped;
        {
            QMutexLocker lock(&mutex_);
            dropped = pending_;
            pending_ = frame;
        }
        if (dropped)
            release_(*dropped);
    }

    // Render thread: take the newest frame, if a new one arrived.
    std::optional<CameraFrame> take()
    {
        std::optional<CameraFrame> frame, retired;
        {
            QMutexLocker lock(&mutex_);
            if (!pending_)
                return {};
            frame = pending_;
            pending_.reset();
            retired = shown_[1];
            shown_[1] = shown_[0];
            shown_[0] = frame;
        }
        if (retired)
            release_(*retired);
        return frame;
    }

    // Camera thread, when the camera stops: forget every frame. Their
    // requests go away with the stream, so nothing is given back.
    void clear()
    {
        QMutexLocker lock(&mutex_);
        pending_.reset();
        shown_ = {};
    }

private:
    QMutex mutex_;
    std::optional<CameraFrame> pending_;
    std::array<std::optional<CameraFrame>, 2> shown_;
    Release release_;
};
