import QtQuick

// Input is confined to a small handle above the keys by the containing window.
Item {
    id: handle
    property real distance: 0
    signal dismissed()
    DrawerPull {
        anchors.fill: parent
        onStarted: handle.distance = 0
        onMoved: distance => handle.distance = distance
        onReleased: { if (handle.distance >= 44) handle.dismissed(); handle.distance = 0; }
        onCanceled: handle.distance = 0
    }
}
