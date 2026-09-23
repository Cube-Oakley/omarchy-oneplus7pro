#include "viewfinder.h"
#include "camerasession.h"

#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQuickWindow>
#include <QRunnable>
#include <QSGSimpleTextureNode>
#include <QtQuick/qsgtexture_platform.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <linux/dma-buf.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

#include <vector>

namespace {

struct EglFunctions {
    PFNEGLCREATEIMAGEKHRPROC createImage = nullptr;
    PFNEGLDESTROYIMAGEKHRPROC destroyImage = nullptr;
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC targetTexture = nullptr;

    static const EglFunctions &get()
    {
        static const EglFunctions functions = [] {
            EglFunctions f;
            f.createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
                eglGetProcAddress("eglCreateImageKHR"));
            f.destroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
                eglGetProcAddress("eglDestroyImageKHR"));
            f.targetTexture = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
                eglGetProcAddress("glEGLImageTargetTexture2DOES"));
            return f;
        }();
        return functions;
    }

    bool usable() const { return createImage && destroyImage && targetTexture; }
};

QRectF fitted(const QRectF &bounds, const QSizeF &frame)
{
    if (frame.isEmpty() || bounds.isEmpty())
        return bounds;
    const QSizeF size = frame.scaled(bounds.size(), Qt::KeepAspectRatio);
    return QRectF(bounds.x() + (bounds.width() - size.width()) / 2,
                  bounds.y() + (bounds.height() - size.height()) / 2, size.width(),
                  size.height());
}

} // namespace

// Textures for the frames on screen. Lives on the render thread.
class ViewfinderTextures
{
public:
    ~ViewfinderTextures()
    {
        clearImported();
        delete copied_;
    }

    // Returns the texture showing frame, or nullptr if it cannot be shown.
    QSGTexture *show(QQuickWindow *window, const CameraFrame &frame)
    {
        if (frame.generation != generation_) {
            // A new configuration: every old buffer is gone.
            clearImported();
            generation_ = frame.generation;
        }
        size_ = frame.size;
        if (zeroCopy) {
            if (QSGTexture *texture = imported(window, frame))
                return texture;
            zeroCopy = false;
        }
        return copy(window, frame);
    }

    QSize size() const { return size_; }
    bool zeroCopy = true;

private:
    struct Entry {
        int fd;
        EGLImageKHR image;
        GLuint texture;
        QSGTexture *sgTexture;
    };

    QSGTexture *imported(QQuickWindow *window, const CameraFrame &frame)
    {
        for (const Entry &entry : entries_)
            if (entry.fd == frame.fd)
                return entry.sgTexture;

        const EglFunctions &egl = EglFunctions::get();
        QOpenGLContext *context = QOpenGLContext::currentContext();
        const EGLDisplay display = eglGetCurrentDisplay();
        if (!egl.usable() || !context || display == EGL_NO_DISPLAY)
            return nullptr;

        const EGLint attributes[] = {
            EGL_WIDTH, frame.size.width(),
            EGL_HEIGHT, frame.size.height(),
            EGL_LINUX_DRM_FOURCC_EXT, static_cast<EGLint>(frame.fourcc),
            EGL_DMA_BUF_PLANE0_FD_EXT, frame.fd,
            EGL_DMA_BUF_PLANE0_OFFSET_EXT, static_cast<EGLint>(frame.offset),
            EGL_DMA_BUF_PLANE0_PITCH_EXT, static_cast<EGLint>(frame.stride),
            EGL_NONE,
        };
        const EGLImageKHR image = egl.createImage(display, EGL_NO_CONTEXT,
                                                  EGL_LINUX_DMA_BUF_EXT, nullptr, attributes);
        if (image == EGL_NO_IMAGE_KHR)
            return nullptr;

        QOpenGLFunctions *gl = context->functions();
        GLuint texture = 0;
        gl->glGenTextures(1, &texture);
        gl->glBindTexture(GL_TEXTURE_2D, texture);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        egl.targetTexture(GL_TEXTURE_2D, image);
        gl->glBindTexture(GL_TEXTURE_2D, 0);

        QSGTexture *sgTexture = QNativeInterface::QSGOpenGLTexture::fromNative(
            texture, window, frame.size, QQuickWindow::TextureIsOpaque);
        entries_.push_back({ frame.fd, image, texture, sgTexture });
        return sgTexture;
    }

    QSGTexture *copy(QQuickWindow *window, const CameraFrame &frame)
    {
        const size_t length = frame.offset + frame.length;
        void *map = mmap(nullptr, length, PROT_READ, MAP_SHARED, frame.fd, 0);
        if (map == MAP_FAILED)
            return copied_;

        dma_buf_sync sync = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
        ioctl(frame.fd, DMA_BUF_IOCTL_SYNC, &sync);
        // Byte order R, G, B, X: right for ABGR8888 and XBGR8888, which the
        // session asks for first. The ARGB fallbacks would show R and B swapped.
        const QImage view(static_cast<const uchar *>(map) + frame.offset, frame.size.width(),
                          frame.size.height(), frame.stride, QImage::Format_RGBX8888);
        const QImage image = view.copy();
        sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
        ioctl(frame.fd, DMA_BUF_IOCTL_SYNC, &sync);
        munmap(map, length);

        delete copied_;
        copied_ = window->createTextureFromImage(image);
        return copied_;
    }

    void clearImported()
    {
        QOpenGLContext *context = QOpenGLContext::currentContext();
        const EglFunctions &egl = EglFunctions::get();
        const EGLDisplay display = eglGetCurrentDisplay();
        for (const Entry &entry : entries_) {
            delete entry.sgTexture;
            if (context)
                context->functions()->glDeleteTextures(1, &entry.texture);
            if (egl.usable() && display != EGL_NO_DISPLAY)
                egl.destroyImage(display, entry.image);
        }
        entries_.clear();
    }

    std::vector<Entry> entries_;
    QSGTexture *copied_ = nullptr;
    quint64 generation_ = 0;
    QSize size_;
};

namespace {

class CleanupJob : public QRunnable
{
public:
    explicit CleanupJob(ViewfinderTextures *textures) : textures_(textures) {}
    void run() override { delete textures_; }

private:
    ViewfinderTextures *textures_;
};

} // namespace

Viewfinder::Viewfinder(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents);
}

Viewfinder::~Viewfinder() = default;

void Viewfinder::setSession(CameraSession *session)
{
    if (session == session_)
        return;
    if (session_)
        disconnect(session_, nullptr, this, nullptr);
    session_ = session;
    if (session_)
        connect(session_, &CameraSession::frameReady, this, &QQuickItem::update);
    Q_EMIT sessionChanged();
    update();
}

QSGNode *Viewfinder::updatePaintNode(QSGNode *old, UpdatePaintNodeData *)
{
    auto *node = static_cast<QSGSimpleTextureNode *>(old);
    if (!session_) {
        delete node;
        return nullptr;
    }

    if (!textures_)
        textures_ = new ViewfinderTextures;
    if (window()->rendererInterface()->graphicsApi() != QSGRendererInterface::OpenGL)
        textures_->zeroCopy = false;

    QSGTexture *texture = node ? node->texture() : nullptr;
    if (const std::optional<CameraFrame> frame = session_->frames()->take())
        texture = textures_->show(window(), *frame);

    if (textures_->zeroCopy != zeroCopy_) {
        zeroCopy_ = textures_->zeroCopy;
        QMetaObject::invokeMethod(this, &Viewfinder::zeroCopyChanged, Qt::QueuedConnection);
    }

    if (!texture) {
        delete node;
        return nullptr;
    }
    if (!node) {
        node = new QSGSimpleTextureNode;
        node->setOwnsTexture(false);
        node->setFiltering(QSGTexture::Linear);
    }
    node->setTexture(texture);
    node->setRect(fitted(boundingRect(), textures_->size()));
    return node;
}

void Viewfinder::releaseResources()
{
    if (textures_ && window()) {
        window()->scheduleRenderJob(new CleanupJob(textures_),
                                    QQuickWindow::BeforeSynchronizingStage);
        textures_ = nullptr;
    }
}

void Viewfinder::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == ItemSceneChange && value.window)
        connect(value.window, &QQuickWindow::sceneGraphInvalidated, this,
                &Viewfinder::invalidateSceneGraph, Qt::DirectConnection);
    QQuickItem::itemChange(change, value);
}

void Viewfinder::invalidateSceneGraph()
{
    // Render thread, GL context current.
    delete textures_;
    textures_ = nullptr;
}
