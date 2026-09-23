#pragma once

#include <QPointer>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class CameraSession;
class ViewfinderTextures;

// Shows a CameraSession's preview, fitted into the item with its aspect
// ratio kept. Frames reach the GPU as the image processor left them: each
// dma-buf is imported as an EGL image, so the CPU never copies a frame. If
// the scene graph is not OpenGL or the import fails, frames are copied.
class Viewfinder : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(CameraSession *session READ session WRITE setSession NOTIFY sessionChanged)
    Q_PROPERTY(bool zeroCopy READ zeroCopy NOTIFY zeroCopyChanged)

public:
    explicit Viewfinder(QQuickItem *parent = nullptr);
    ~Viewfinder() override;

    CameraSession *session() const { return session_; }
    void setSession(CameraSession *session);
    bool zeroCopy() const { return zeroCopy_; }

Q_SIGNALS:
    void sessionChanged();
    void zeroCopyChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void releaseResources() override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void invalidateSceneGraph();

    QPointer<CameraSession> session_;
    // Render-thread state, deleted there with the GL context current.
    ViewfinderTextures *textures_ = nullptr;
    bool zeroCopy_ = true;
};
