import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Rectangle {
    id: card
    required property var window
    property bool captureEnabled: false
    property bool expanded: false
    readonly property string appClass: window && window.lastIpcObject ? window.lastIpcObject.class || "App" : "App"
    property real swipeOffset: 0
    property bool closing: false
    signal arrangeStarted(point position)
    signal arrangeMoved(point position)
    signal arrangeFinished(point position)
    signal arrangeCanceled()
    transform: Translate { y: card.swipeOffset }
    opacity: Math.max(0.15, 1 + swipeOffset / Math.max(1, height))
    function settleSwipe(close) {
        closing = close;
        slide.to = close ? -height : 0;
        slide.start();
    }
    NumberAnimation {
        id: slide; target: card; property: "swipeOffset"; duration: 210; easing.type: Easing.OutCubic
        onFinished: if (card.closing) { card.closeWindow(); restore.start(); }
    }
    // A normal close may open an unsaved-document prompt instead of removing
    // the window. Restore its preview if the client is still present.
    Timer { id: restore; interval: 400; onTriggered: { card.closing = false; card.swipeOffset = 0; } }
    signal focusWindow()
    signal moveWindow(int workspace)
    signal maximizeWindow()
    signal closeWindow()
    color: MobileTheme.surface
    radius: 24
    border.width: 1; border.color: MobileTheme.muted
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 14
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: 12; color: MobileTheme.selection
                Text { font.family: MobileTheme.fontFamily; anchors.centerIn: parent; text: card.appClass.substring(0, 1).toUpperCase(); color: MobileTheme.accent; font.pixelSize: 21; font.bold: true }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: card.appClass; textFormat: Text.PlainText; elide: Text.ElideRight; color: MobileTheme.foreground; font.pixelSize: 17; font.bold: true }
                Text { font.family: MobileTheme.fontFamily; Layout.fillWidth: true; text: card.window ? card.window.title : ""; textFormat: Text.PlainText; elide: Text.ElideRight; color: MobileTheme.secondary; font.pixelSize: 12 }
            }
            TouchButton { label: "···"; implicitWidth: 48; implicitHeight: 48; selected: card.expanded; textSize: 24; onClicked: card.expanded = !card.expanded }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 100
            radius: 14; color: MobileTheme.background; clip: true
            Text { font.family: MobileTheme.fontFamily; anchors.centerIn: parent; text: card.appClass; color: MobileTheme.muted; font.pixelSize: 24 }
            ScreencopyView {
                anchors.centerIn: parent
                captureSource: card.captureEnabled && card.window ? card.window.wayland : null
                constraintSize: Qt.size(parent.width, parent.height)
                live: false
            }
            PreviewGestures {
                anchors.fill: parent
                enabled: !card.closing && !slide.running
                closeDistance: Math.min(180, card.height * 0.24)
                onOpened: card.focusWindow()
                onSwipeMoved: distance => card.swipeOffset = -distance
                onSwipeFinished: close => card.settleSwipe(close)
                onHeld: position => card.arrangeStarted(position)
                onHoldMoved: position => card.arrangeMoved(position)
                onHoldFinished: position => card.arrangeFinished(position)
                onGestureCanceled: { card.settleSwipe(false); card.arrangeCanceled(); }
            }
        }
        ColumnLayout {
            visible: card.expanded; Layout.fillWidth: true; spacing: 10
            Text { font.family: MobileTheme.fontFamily; text: "MOVE TO WORKSPACE"; color: MobileTheme.secondary; font.pixelSize: 10; font.letterSpacing: 1.5 }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Repeater {
                    model: MobileTheme.state.device.workspaceCount || 4
                    TouchButton {
                        required property int index
                        Layout.fillWidth: true; implicitHeight: 44
                        label: String(index + 1)
                        selected: card.window && card.window.workspace && card.window.workspace.id === index + 1
                        onClicked: { card.moveWindow(index + 1); card.expanded = false; }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                TouchButton { Layout.fillWidth: true; label: "Maximize"; implicitHeight: 46; onClicked: card.maximizeWindow() }
                TouchButton { Layout.fillWidth: true; label: "Close window"; implicitHeight: 46; onClicked: card.closeWindow() }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text { font.family: MobileTheme.fontFamily; text: "WORKSPACE " + (card.window && card.window.workspace ? card.window.workspace.id : "—"); color: MobileTheme.secondary; font.pixelSize: 10; font.letterSpacing: 1.2; Layout.fillWidth: true }
            TouchButton { label: "Open  ↗"; implicitWidth: 110; implicitHeight: 46; selected: true; onClicked: card.focusWindow() }
        }
    }
}
