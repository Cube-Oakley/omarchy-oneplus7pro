import QtQuick

Item {
    id: edge
    property color handleColor: "white"
    signal invoked(string action)
    signal drawerStarted(string page)
    signal drawerMoved(real distance, real velocity)
    signal drawerReleased()
    signal drawerCanceled()
    readonly property int zone: Math.min(2, Math.max(0, Math.floor(drag.centroid.pressPosition.x / (width / 3))))
    DragHandler {
        id: drag; target: null
        minimumPointCount: 1; maximumPointCount: 1
        property bool tracking: false
        property bool fired: false
        onActiveChanged: {
            if (active) { tracking = false; fired = false; }
            else if (tracking) { tracking = false; edge.drawerReleased(); }
        }
        onActiveTranslationChanged: {
            if (!active) return;
            const up = -activeTranslation.y;
            if (!tracking && !fired && up > 8 && up > Math.abs(activeTranslation.x) * 1.2) {
                if (edge.zone < 2) {
                    tracking = true;
                    edge.drawerStarted(edge.zone === 0 ? "apps" : "spaces");
                } else if (up >= 54) {
                    fired = true; edge.invoked("keyboard");
                }
            }
            if (tracking) edge.drawerMoved(up, -centroid.velocity.y);
        }
        onCanceled: { tracking = false; edge.drawerCanceled(); }
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
        width: drag.active ? 76 : 58; height: 3; radius: 2
        color: edge.handleColor; opacity: drag.active ? 0.8 : 0.22
        Behavior on width { NumberAnimation { duration: 130 } }
        Behavior on opacity { NumberAnimation { duration: 130 } }
    }
}
