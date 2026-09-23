#pragma once

#include "framequeue.h"

#include <QImage>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QRectF>
#include <QSize>
#include <QString>
#include <QThread>
#include <QtQml/qqmlregistration.h>

#include <array>
#include <atomic>
#include <memory>
#include <vector>

#include <libcamera/libcamera.h>

// What the photo writer needs to know about a still.
struct StillInfo {
    int rotation = 0;           // degrees clockwise to turn the frame upright
    qint64 exposureUs = 0;
    double analogueGain = 0.0;
    QString model;              // sensor model, from libcamera
};

class CameraWorker;

// The camera as QML sees it: a preview for a Viewfinder, tap to focus, and
// full-resolution stills. It uses libcamera's public API only, so it works
// on any phone libcamera supports; board specifics live below libcamera.
class CameraSession : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QString cameraName READ cameraName NOTIFY cameraChanged)
    Q_PROPERTY(int rotation READ rotation NOTIFY cameraChanged)
    Q_PROPERTY(bool canFocus READ canFocus NOTIFY cameraChanged)
    Q_PROPERTY(QSize previewSize READ previewSize WRITE setPreviewSize NOTIFY previewSizeChanged)
    Q_PROPERTY(QString focusState READ focusState NOTIFY focusChanged)
    Q_PROPERTY(QPointF focusPoint READ focusPoint NOTIFY focusChanged)
    Q_PROPERTY(QString photoFolder READ photoFolder WRITE setPhotoFolder NOTIFY photoFolderChanged)
    Q_PROPERTY(QString lastPhoto READ lastPhoto NOTIFY lastPhotoChanged)

public:
    explicit CameraSession(QObject *parent = nullptr);
    ~CameraSession() override;

    bool active() const { return active_; }
    void setActive(bool active);
    QString state() const { return state_; }
    QString error() const { return error_; }
    QString cameraName() const { return cameraName_; }
    int rotation() const { return rotation_; }
    bool canFocus() const { return canFocus_; }
    QSize previewSize() const { return previewSize_; }
    void setPreviewSize(const QSize &size);
    QString focusState() const { return focusState_; }
    QPointF focusPoint() const { return focusPoint_; }
    QString photoFolder() const { return photoFolder_; }
    void setPhotoFolder(const QString &folder);
    QString lastPhoto() const { return lastPhoto_; }

    FrameQueue *frames() { return &frames_; }

    // x and y are 0..1 across the upright preview, as the user sees it.
    Q_INVOKABLE void focusAt(qreal x, qreal y);
    Q_INVOKABLE void resetFocus();
    Q_INVOKABLE void capture();

Q_SIGNALS:
    void activeChanged();
    void stateChanged();
    void cameraChanged();
    void previewSizeChanged();
    void focusChanged();
    void photoFolderChanged();
    void lastPhotoChanged();
    void frameReady();
    void photoSaved(const QString &path);
    void photoFailed(const QString &reason);

private:
    void setState(const QString &state, const QString &error = {});
    void writeStill(QImage image, StillInfo info);

    FrameQueue frames_;
    QThread thread_;
    CameraWorker *worker_ = nullptr;
    bool active_ = false;
    bool opened_ = false;
    QString state_ = QStringLiteral("off");
    QString error_;
    QString cameraName_;
    int rotation_ = 0;
    bool canFocus_ = false;
    QSize previewSize_{1440, 1080};
    QString focusState_ = QStringLiteral("idle");
    QPointF focusPoint_{-1, -1};
    QString photoFolder_;
    QString lastPhoto_;
};

// Owns libcamera. Every libcamera call except queueRequest() happens on this
// object's thread; completed requests arrive on libcamera's own thread.
class CameraWorker : public QObject
{
    Q_OBJECT

public:
    explicit CameraWorker(FrameQueue *frames);
    ~CameraWorker() override;

    void open();
    void close();
    void startPreview(QSize size);
    void stopPreview();
    void setFocusWindow(QPointF framePoint, bool enabled);
    void capture();
    void requeue(const CameraFrame &frame);

Q_SIGNALS:
    void opened(const QString &name, int rotation, bool canFocus);
    void failed(const QString &message);
    void streamingChanged(const QString &mode);
    void frameReady();
    void focusStateChanged(const QString &state);
    void stillCaptured(const QImage &image, int rotation, qint64 exposureUs,
                       double gain, const QString &model);

private:
    enum Mode { Off, Preview, Still };

    bool configure(libcamera::StreamRole role, QSize size, unsigned int buffers);
    bool startStream(const libcamera::ControlList &initial);
    void stopStream();
    void queue(libcamera::Request *request);
    void onRequestCompleted(libcamera::Request *request);
    void handleStill(libcamera::Request *request, const libcamera::FrameBuffer *buffer);
    void finishStill(const QImage &image, qint64 exposureUs, double gain);
    libcamera::ControlList focusControls() const;

    FrameQueue *frames_;
    std::unique_ptr<libcamera::CameraManager> manager_;
    std::shared_ptr<libcamera::Camera> camera_;
    std::unique_ptr<libcamera::CameraConfiguration> config_;
    std::unique_ptr<libcamera::FrameBufferAllocator> allocator_;
    std::vector<std::unique_ptr<libcamera::Request>> requests_;
    libcamera::Stream *stream_ = nullptr;
    libcamera::ControlList pending_;
    bool pendingSet_ = false;

    std::atomic<quint64> generation_{0};
    std::atomic<int> mode_{Off};
    std::atomic<bool> stillTaken_{false};
    std::atomic<float> lensPosition_{-1.0f};
    std::atomic<int> focusState_{-1};

    // Still capture, touched only from libcamera's thread while streaming.
    int stillFrames_ = 0;
    qint64 lastExposure_ = -1;
    double lastGain_ = -1.0;
    std::array<float, 2> lastColour_{ -1.0f, -1.0f };
    int stableFrames_ = 0;

    QSize previewSize_;
    QSize streamSize_;
    unsigned int stride_ = 0;
    quint32 fourcc_ = 0;
    libcamera::Rectangle activeArea_;
    int rotation_ = 0;
    bool canFocus_ = false;
    QString model_;
    bool focusWindow_ = false;
    QPointF focusPoint_;
};
