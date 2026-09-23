#include "camerasession.h"
#include "stillwriter.h"

#include <QDir>
#include <QStandardPaths>
#include <QtConcurrent/QtConcurrentRun>

#include <linux/dma-buf.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

#include <algorithm>
#include <array>
#include <cmath>

using namespace libcamera;

namespace {

// A still skips at least this many frames while the lens settles after the
// stream restart...
constexpr int kStillMinFrames = 3;
// ...then waits for exposure, gain and white balance to repeat on this many,
// since an image processor may start them over on a new configuration...
constexpr int kStillStableFrames = 2;
// ...but never waits for more than this many.
constexpr int kStillMaxFrames = 15;
// Enough buffers that the viewfinder can hold three while the camera fills
// the rest.
constexpr unsigned int kPreviewBuffers = 6;
constexpr unsigned int kStillBuffers = 3;

QString focusName(int state)
{
    switch (state) {
    case controls::AfStateScanning:
        return QStringLiteral("scanning");
    case controls::AfStateFocused:
        return QStringLiteral("focused");
    case controls::AfStateFailed:
        return QStringLiteral("failed");
    default:
        return QStringLiteral("idle");
    }
}

QImage::Format imageFormat(quint32 fourcc)
{
    // DRM names list components from the most significant bit, so the
    // little-endian byte order is reversed: ABGR8888 is R, G, B, A in memory.
    if (fourcc == formats::ABGR8888.fourcc())
        return QImage::Format_RGBA8888;
    if (fourcc == formats::XBGR8888.fourcc())
        return QImage::Format_RGBX8888;
    if (fourcc == formats::ARGB8888.fourcc())
        return QImage::Format_ARGB32;
    if (fourcc == formats::XRGB8888.fourcc())
        return QImage::Format_RGB32;
    return QImage::Format_Invalid;
}

QImage copyFrame(const FrameBuffer *buffer, QSize size, unsigned int stride, quint32 fourcc)
{
    const QImage::Format format = imageFormat(fourcc);
    if (format == QImage::Format_Invalid || buffer->planes().empty())
        return {};

    const FrameBuffer::Plane &plane = buffer->planes()[0];
    const int fd = plane.fd.get();
    const size_t length = plane.offset + plane.length;
    void *map = mmap(nullptr, length, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED)
        return {};

    dma_buf_sync sync = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
    ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
    const QImage view(static_cast<const uchar *>(map) + plane.offset, size.width(),
                      size.height(), stride, format);
    QImage copy = view.copy();
    sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
    ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
    munmap(map, length);
    return copy;
}

bool supports(const std::shared_ptr<Camera> &camera, const ControlId &id)
{
    return camera->controls().find(&id) != camera->controls().end();
}

} // namespace

CameraSession::CameraSession(QObject *parent)
    : QObject(parent),
      frames_([this](const CameraFrame &frame) {
          // Any thread: the worker gives the buffer back to the camera.
          CameraWorker *worker = worker_;
          QMetaObject::invokeMethod(worker, [worker, frame] { worker->requeue(frame); },
                                    Qt::QueuedConnection);
      })
{
    photoFolder_ = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) +
                   QStringLiteral("/Camera");

    worker_ = new CameraWorker(&frames_);
    worker_->moveToThread(&thread_);
    connect(&thread_, &QThread::finished, worker_, &QObject::deleteLater);
    connect(worker_, &CameraWorker::opened, this,
            [this](const QString &name, int rotation, bool canFocus) {
                opened_ = true;
                cameraName_ = name;
                rotation_ = rotation;
                canFocus_ = canFocus;
                Q_EMIT cameraChanged();
            });
    connect(worker_, &CameraWorker::failed, this,
            [this](const QString &message) { setState(QStringLiteral("error"), message); });
    connect(worker_, &CameraWorker::streamingChanged, this, [this](const QString &mode) {
        if (mode == QLatin1String("preview"))
            setState(QStringLiteral("preview"));
        else if (mode == QLatin1String("still"))
            setState(QStringLiteral("capturing"));
        else if (state_ != QLatin1String("error"))
            setState(QStringLiteral("off"));
    });
    connect(worker_, &CameraWorker::frameReady, this, &CameraSession::frameReady);
    connect(worker_, &CameraWorker::focusStateChanged, this, [this](const QString &state) {
        focusState_ = state;
        Q_EMIT focusChanged();
    });
    connect(worker_, &CameraWorker::stillCaptured, this,
            [this](const QImage &image, int rotation, qint64 exposureUs, double gain,
                   const QString &model) {
                writeStill(image, StillInfo{ rotation, exposureUs, gain, model });
            });

    thread_.setObjectName(QStringLiteral("camera"));
    thread_.start();
}

CameraSession::~CameraSession()
{
    CameraWorker *worker = worker_;
    QMetaObject::invokeMethod(worker, [worker] { worker->close(); },
                              Qt::BlockingQueuedConnection);
    thread_.quit();
    thread_.wait();
}

void CameraSession::setActive(bool active)
{
    if (active == active_)
        return;
    active_ = active;
    Q_EMIT activeChanged();

    CameraWorker *worker = worker_;
    if (active) {
        setState(QStringLiteral("starting"));
        const QSize size = previewSize_;
        QMetaObject::invokeMethod(worker, [worker, size] {
            worker->open();
            worker->startPreview(size);
        });
    } else {
        QMetaObject::invokeMethod(worker, [worker] { worker->stopPreview(); });
    }
}

void CameraSession::setPreviewSize(const QSize &size)
{
    if (size == previewSize_ || !size.isValid())
        return;
    previewSize_ = size;
    Q_EMIT previewSizeChanged();
}

void CameraSession::setPhotoFolder(const QString &folder)
{
    if (folder == photoFolder_)
        return;
    photoFolder_ = folder;
    Q_EMIT photoFolderChanged();
}

void CameraSession::focusAt(qreal x, qreal y)
{
    if (!canFocus_)
        return;
    x = std::clamp(x, 0.0, 1.0);
    y = std::clamp(y, 0.0, 1.0);

    // The preview shows the frame turned clockwise by rotation_; undo that
    // to find the point in the frame.
    QPointF frame;
    switch (((rotation_ % 360) + 360) % 360) {
    case 90:
        frame = { y, 1.0 - x };
        break;
    case 180:
        frame = { 1.0 - x, 1.0 - y };
        break;
    case 270:
        frame = { 1.0 - y, x };
        break;
    default:
        frame = { x, y };
        break;
    }

    focusPoint_ = { x, y };
    Q_EMIT focusChanged();
    CameraWorker *worker = worker_;
    QMetaObject::invokeMethod(worker, [worker, frame] { worker->setFocusWindow(frame, true); });
}

void CameraSession::resetFocus()
{
    focusPoint_ = { -1, -1 };
    Q_EMIT focusChanged();
    CameraWorker *worker = worker_;
    QMetaObject::invokeMethod(worker, [worker] { worker->setFocusWindow({}, false); });
}

void CameraSession::capture()
{
    if (state_ != QLatin1String("preview"))
        return;
    setState(QStringLiteral("capturing"));
    CameraWorker *worker = worker_;
    QMetaObject::invokeMethod(worker, [worker] { worker->capture(); });
}

void CameraSession::setState(const QString &state, const QString &error)
{
    if (state == state_ && error == error_)
        return;
    state_ = state;
    error_ = error;
    Q_EMIT stateChanged();
}

void CameraSession::writeStill(QImage image, StillInfo info)
{
    const QString folder = photoFolder_;
    QtConcurrent::run([image = std::move(image), info, folder]() {
        QString error;
        const QString path = StillWriter::write(image, info, folder, &error);
        return path.isEmpty() ? QStringLiteral("!") + error : path;
    }).then(this, [this](const QString &result) {
        if (result.startsWith(QLatin1Char('!'))) {
            Q_EMIT photoFailed(result.mid(1));
            return;
        }
        lastPhoto_ = result;
        Q_EMIT lastPhotoChanged();
        Q_EMIT photoSaved(result);
    });
}

CameraWorker::CameraWorker(FrameQueue *frames)
    : frames_(frames)
{
}

CameraWorker::~CameraWorker()
{
    close();
}

void CameraWorker::open()
{
    if (camera_)
        return;

    manager_ = std::make_unique<CameraManager>();
    if (manager_->start()) {
        manager_.reset();
        Q_EMIT failed(QStringLiteral("The camera system did not start"));
        return;
    }

    const auto cameras = manager_->cameras();
    if (cameras.empty()) {
        Q_EMIT failed(QStringLiteral("No camera found"));
        return;
    }

    std::shared_ptr<Camera> chosen = cameras.front();
    for (const auto &camera : cameras) {
        const auto location = camera->properties().get(properties::Location);
        if (location && *location == properties::CameraLocationBack) {
            chosen = camera;
            break;
        }
    }
    if (chosen->acquire()) {
        Q_EMIT failed(QStringLiteral("Another app is using the camera"));
        return;
    }

    camera_ = chosen;
    camera_->requestCompleted.connect(this, &CameraWorker::onRequestCompleted);

    const ControlList &props = camera_->properties();
    // libcamera states the mounting rotation counter-clockwise; the preview
    // and photos turn the frame clockwise by the rest of a full turn.
    rotation_ = (360 - props.get(properties::Rotation).value_or(0) % 360) % 360;
    const auto model = props.get(properties::Model);
    model_ = model ? QString::fromUtf8(model->data(), qsizetype(model->size()))
                   : QString::fromStdString(camera_->id());
    if (const auto areas = props.get(properties::PixelArrayActiveAreas); areas && !areas->empty())
        activeArea_ = (*areas)[0];
    else if (const auto size = props.get(properties::PixelArraySize))
        activeArea_ = Rectangle(*size);
    canFocus_ = supports(camera_, controls::AfMode);
    pending_ = ControlList(camera_->controls());

    Q_EMIT opened(model_, rotation_, canFocus_);
}

void CameraWorker::close()
{
    if (!camera_)
        return;
    stopPreview();
    camera_->requestCompleted.disconnect(this);
    camera_->release();
    camera_.reset();
    manager_.reset();
}

bool CameraWorker::configure(StreamRole role, QSize size, unsigned int buffers)
{
    config_ = camera_->generateConfiguration({ role });
    if (!config_ || config_->empty())
        return false;

    StreamConfiguration &cfg = config_->at(0);
    // 32-bit RGB, which the viewfinder can hand to the GPU as it is.
    const std::vector<PixelFormat> offered = cfg.formats().pixelformats();
    for (const PixelFormat &format : { formats::ABGR8888, formats::XBGR8888,
                                       formats::ARGB8888, formats::XRGB8888 }) {
        if (std::find(offered.begin(), offered.end(), format) != offered.end()) {
            cfg.pixelFormat = format;
            break;
        }
    }
    if (size.isValid())
        cfg.size = Size(size.width(), size.height());
    cfg.bufferCount = buffers;

    if (config_->validate() == CameraConfiguration::Invalid ||
        camera_->configure(config_.get()))
        return false;

    stream_ = cfg.stream();
    streamSize_ = QSize(cfg.size.width, cfg.size.height);
    stride_ = cfg.stride;
    fourcc_ = cfg.pixelFormat.fourcc();

    allocator_ = std::make_unique<FrameBufferAllocator>(camera_);
    if (allocator_->allocate(stream_) < 0)
        return false;

    requests_.clear();
    for (const std::unique_ptr<FrameBuffer> &buffer : allocator_->buffers(stream_)) {
        std::unique_ptr<Request> request = camera_->createRequest();
        if (!request || request->addBuffer(stream_, buffer.get()))
            return false;
        requests_.push_back(std::move(request));
    }
    return true;
}

bool CameraWorker::startStream(const ControlList &initial)
{
    ++generation_;
    stillFrames_ = 0;
    stableFrames_ = 0;
    lastExposure_ = -1;
    lastGain_ = -1.0;
    lastColour_ = { -1.0f, -1.0f };
    stillTaken_ = false;
    focusState_ = -1;

    if (camera_->start(initial.empty() ? nullptr : &initial))
        return false;
    for (const std::unique_ptr<Request> &request : requests_)
        queue(request.get());
    return true;
}

void CameraWorker::stopStream()
{
    if (!camera_ || !stream_)
        return;
    camera_->stop();
    ++generation_;
    frames_->clear();
    requests_.clear();
    allocator_.reset();
    config_.reset();
    stream_ = nullptr;
}

void CameraWorker::startPreview(QSize size)
{
    if (!camera_ || mode_ == Preview)
        return;
    previewSize_ = size;
    if (!configure(StreamRole::Viewfinder, size, kPreviewBuffers)) {
        Q_EMIT failed(QStringLiteral("The camera could not be set up"));
        return;
    }
    mode_ = Preview;
    // As for stills, the first request repeats the start controls: after a
    // still in manual focus, continuous focus must reach the image processor.
    const ControlList initial = focusControls();
    pending_ = initial;
    pendingSet_ = true;
    if (!startStream(initial)) {
        mode_ = Off;
        Q_EMIT failed(QStringLiteral("The camera did not start"));
        return;
    }
    Q_EMIT streamingChanged(QStringLiteral("preview"));
}

void CameraWorker::stopPreview()
{
    stopStream();
    mode_ = Off;
    Q_EMIT streamingChanged(QStringLiteral("off"));
}

ControlList CameraWorker::focusControls() const
{
    ControlList controls(camera_->controls());
    if (!canFocus_)
        return controls;

    controls.set(controls::AfMode, controls::AfModeContinuous);
    if (!supports(camera_, controls::AfMetering))
        return controls;

    if (focusWindow_ && supports(camera_, controls::AfWindows)) {
        // A window a fifth of the frame across, centred on the tap.
        const Rectangle &area = activeArea_;
        const int width = area.width / 5;
        const int height = area.height / 5;
        const int x = std::clamp(area.x + int(focusPoint_.x() * area.width) - width / 2,
                                 area.x, area.x + int(area.width) - width);
        const int y = std::clamp(area.y + int(focusPoint_.y() * area.height) - height / 2,
                                 area.y, area.y + int(area.height) - height);
        controls.set(controls::AfMetering, controls::AfMeteringWindows);
        controls.set(controls::AfWindows, { Rectangle(x, y, width, height) });
    } else {
        controls.set(controls::AfMetering, controls::AfMeteringAuto);
    }
    return controls;
}

void CameraWorker::setFocusWindow(QPointF framePoint, bool enabled)
{
    focusWindow_ = enabled;
    focusPoint_ = framePoint;
    if (!canFocus_ || mode_ != Preview)
        return;
    pending_ = focusControls();
    pendingSet_ = true;
}

void CameraWorker::queue(Request *request)
{
    if (pendingSet_) {
        request->controls().merge(pending_);
        pending_.clear();
        pendingSet_ = false;
    }
    camera_->queueRequest(request);
}

void CameraWorker::requeue(const CameraFrame &frame)
{
    if (frame.generation != generation_ || mode_ != Preview || !camera_)
        return;
    frame.request->reuse(Request::ReuseBuffers);
    queue(frame.request);
}

void CameraWorker::capture()
{
    if (mode_ != Preview)
        return;

    // Keep the focus the preview found: the still is a new configuration,
    // and continuous autofocus would otherwise scan again.
    const float lens = lensPosition_;
    stopStream();
    mode_ = Still;
    Q_EMIT streamingChanged(QStringLiteral("still"));

    if (!configure(StreamRole::StillCapture, QSize(), kStillBuffers)) {
        mode_ = Off;
        Q_EMIT failed(QStringLiteral("The camera could not take a photo"));
        startPreview(previewSize_);
        return;
    }
    // Start controls do not reach every pipeline's image processor, so the
    // first request carries the focus as well.
    ControlList initial(camera_->controls());
    if (canFocus_ && lens >= 0.0f && supports(camera_, controls::LensPosition)) {
        initial.set(controls::AfMode, controls::AfModeManual);
        initial.set(controls::LensPosition, lens);
        pending_ = initial;
        pendingSet_ = true;
    }
    if (!startStream(initial)) {
        mode_ = Off;
        Q_EMIT failed(QStringLiteral("The camera could not take a photo"));
        startPreview(previewSize_);
    }
}

void CameraWorker::onRequestCompleted(Request *request)
{
    // libcamera's thread.
    if (request->status() == Request::RequestCancelled)
        return;

    const ControlList &metadata = request->metadata();
    if (const auto state = metadata.get(controls::AfState)) {
        if (focusState_.exchange(*state) != *state && mode_ == Preview)
            Q_EMIT focusStateChanged(focusName(*state));
    }
    if (const auto lens = metadata.get(controls::LensPosition); lens && mode_ == Preview)
        lensPosition_ = *lens;

    if (request->buffers().empty())
        return;
    const FrameBuffer *buffer = request->buffers().begin()->second;

    if (mode_ == Still) {
        handleStill(request, buffer);
        return;
    }
    if (mode_ != Preview || buffer->planes().empty())
        return;

    const FrameBuffer::Plane &plane = buffer->planes()[0];
    CameraFrame frame;
    frame.request = request;
    frame.generation = generation_;
    frame.fd = plane.fd.get();
    frame.offset = plane.offset;
    frame.length = plane.length;
    frame.size = streamSize_;
    frame.stride = stride_;
    frame.fourcc = fourcc_;
    frame.sequence = buffer->metadata().sequence;
    frames_->publish(frame);
    Q_EMIT frameReady();
}

void CameraWorker::handleStill(Request *request, const FrameBuffer *buffer)
{
    // libcamera's thread.
    if (stillTaken_)
        return;

    const ControlList &metadata = request->metadata();
    const qint64 exposure = metadata.get(controls::ExposureTime).value_or(-1);
    const double gain = metadata.get(controls::AnalogueGain).value_or(-1.0f);
    std::array<float, 2> colour{ -1.0f, -1.0f };
    if (const auto gains = metadata.get(controls::ColourGains))
        colour = { (*gains)[0], (*gains)[1] };
    const auto near = [](float a, float b) { return std::abs(a - b) <= 0.01f * std::max(a, b); };

    ++stillFrames_;
    const bool same = exposure == lastExposure_ && gain == lastGain_ &&
                      near(colour[0], lastColour_[0]) && near(colour[1], lastColour_[1]);
    stableFrames_ = same ? stableFrames_ + 1 : 0;
    lastExposure_ = exposure;
    lastGain_ = gain;
    lastColour_ = colour;

    const bool settled = stillFrames_ > kStillMinFrames && stableFrames_ >= kStillStableFrames;
    if (!settled && stillFrames_ < kStillMaxFrames) {
        request->reuse(Request::ReuseBuffers);
        camera_->queueRequest(request);
        return;
    }

    stillTaken_ = true;
    const QImage image = copyFrame(buffer, streamSize_, stride_, fourcc_);
    QMetaObject::invokeMethod(this, [this, image, exposure, gain] {
        finishStill(image, exposure, gain);
    }, Qt::QueuedConnection);
}

void CameraWorker::finishStill(const QImage &image, qint64 exposureUs, double gain)
{
    stopStream();
    mode_ = Off;
    if (image.isNull())
        Q_EMIT failed(QStringLiteral("The photo could not be read from the camera"));
    else
        Q_EMIT stillCaptured(image, rotation_, exposureUs, gain, model_);
    startPreview(previewSize_);
}
