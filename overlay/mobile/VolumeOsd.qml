import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: osd
    property var state: ({available: false, percent: 0, muted: false})
    property var queue: []
    function adjust(action) {
        if (["up", "down", "mute", "status"].indexOf(action) < 0) return;
        queue = queue.concat([[action]]);
        runNext();
    }
    function setVolume(percent) {
        // Coalesce slider requests while retaining ordered hardware key presses.
        queue = queue.filter(request => request[0] !== "set").concat([["set", String(Math.round(percent))]]);
        runNext();
    }
    function runNext() {
        if (request.running || queue.length === 0) return;
        const args = queue[0]; queue = queue.slice(1);
        request.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-volume"].concat(args);
        request.running = true;
    }
    Process {
        id: request
        stdout: StdioCollector {}
        onExited: (code, status) => {
            try { osd.state = JSON.parse(stdout.text); }
            catch (e) { osd.state = {available: false, percent: 0, muted: false}; }
            hold.restart();
            Qt.callLater(osd.runNext);
        }
    }
    Timer { id: hold; interval: 2500 }
    visible: hold.running || slider.pressed
    anchors { top: true; right: true }
    margins { top: 70; right: 12 }
    implicitWidth: 84
    implicitHeight: 274
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-mobile-volume"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Rectangle {
        anchors.fill: parent
        radius: 24
        color: MobileTheme.surface
        border.color: MobileTheme.muted
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 10
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: !osd.state.available ? "—" : osd.state.muted ? "󰝟" : "󰕾"
                font.family: MobileTheme.fontFamily; font.pixelSize: 28
                color: MobileTheme.accent
                TapHandler { onTapped: osd.adjust("mute") }
            }
            Slider {
                id: slider
                Layout.fillHeight: true; Layout.alignment: Qt.AlignHCenter
                from: 0; to: 100; stepSize: 1
                orientation: Qt.Vertical
                enabled: osd.state.available
                value: osd.state.muted ? 0 : osd.state.percent
                onMoved: osd.setVolume(value)
                onPressedChanged: if (!pressed) hold.restart()
                background: Rectangle {
                    x: (slider.width - width) / 2; y: slider.topPadding
                    width: 12; height: slider.availableHeight; radius: 6
                    color: MobileTheme.muted
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width
                        height: parent.height * slider.position; radius: 6
                        color: MobileTheme.accent
                    }
                }
                handle: Rectangle {
                    x: (slider.width - width) / 2
                    y: slider.topPadding + slider.visualPosition * (slider.availableHeight - height)
                    width: 30; height: 20; radius: 10
                    color: MobileTheme.foreground
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: osd.state.available ? osd.state.percent + "%" : "Offline"
                font.family: MobileTheme.fontFamily; font.pixelSize: 13
                color: MobileTheme.foreground
            }
        }
    }
}
