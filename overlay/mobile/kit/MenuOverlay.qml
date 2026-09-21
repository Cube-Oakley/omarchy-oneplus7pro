import QtQuick

Item {
    id: overlay
    property bool open: false
    property color scrim: Qt.rgba(0, 0, 0, 0.88)
    property int duration: 220
    property int enterOffset: 28
    property bool wasOpen: false
    default property alias content: body.data
    signal dismissed()
    signal closed()

    anchors.fill: parent
    visible: open || opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: overlay.duration; easing.type: Easing.OutCubic } }
    onOpenChanged: if (open) wasOpen = true
    onOpacityChanged: if (wasOpen && !open && opacity <= 0.01) { wasOpen = false; closed() }

    Rectangle {
        anchors.fill: parent
        color: overlay.scrim
        TapHandler { onTapped: overlay.dismissed() }
    }

    Item {
        id: body
        anchors.fill: parent
        scale: overlay.open ? 1 : 0.96
        transformOrigin: Item.Center
        opacity: overlay.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: overlay.duration; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: overlay.duration; easing.type: Easing.OutCubic } }
        TapHandler { onTapped: overlay.dismissed() }
    }
}
