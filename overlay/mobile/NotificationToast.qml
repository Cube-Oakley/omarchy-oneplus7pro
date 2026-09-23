import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: toast
    property var current: null
    property var queue: []
    property bool blocked: false
    signal activate()
    function offer(notification) {
        if (blocked || !notification) return;
        if (current) {
            queue = queue.concat([notification]).slice(-2);
            return;
        }
        show(notification);
    }
    function show(notification) {
        current = notification;
        hideTimer.restart();
    }
    function hide() {
        current = null;
        if (queue.length) {
            const next = queue[0];
            queue = queue.slice(1);
            Qt.callLater(() => toast.show(next));
        }
    }
    function dismiss() {
        hideTimer.stop();
        hide();
    }
    onBlockedChanged: if (blocked) dismiss()
    visible: current !== null && !blocked
    anchors { top: true; left: true; right: true }
    margins { top: 44; left: 12; right: 12 }
    implicitHeight: 78
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omarchy-mobile-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Rectangle {
        anchors.fill: parent
        radius: MobileTheme.radius(18)
        color: MobileTheme.surface
        border.width: 1
        border.color: MobileTheme.muted
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: toast.current ? (toast.current.appName || "Notification") : ""
                textFormat: Text.PlainText
                color: MobileTheme.accent
                font.family: MobileTheme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: toast.current ? toast.current.summary : ""
                textFormat: Text.PlainText
                color: MobileTheme.foreground
                font.family: MobileTheme.fontFamily
                font.pixelSize: 16
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: toast.current && toast.current.body
                text: toast.current ? toast.current.body : ""
                textFormat: Text.PlainText
                color: MobileTheme.secondary
                font.family: MobileTheme.fontFamily
                font.pixelSize: 13
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
        TapHandler { onTapped: { toast.activate(); toast.dismiss(); } }
        DragHandler {
            id: swipe
            target: null
            xAxis.enabled: false
            onActiveChanged: if (!active && swipe.translation.y < -28) toast.dismiss()
        }
    }
    Timer { id: hideTimer; interval: 4500; onTriggered: toast.hide() }
}
