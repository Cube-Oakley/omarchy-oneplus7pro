import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    property var volume: ({available: false, percent: 0, muted: false})
    function refresh() { if (!probe.running) probe.running = true; }
    function run(action) {
        if (probe.running) return;
        probe.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-volume"].concat(action);
        probe.running = true;
    }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-volume"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { page.volume = JSON.parse(stdout.text); }
            catch (e) { page.volume = {available: false, percent: 0, muted: false}; }
        }
    }
    Column {
        id: body
        width: page.width
        spacing: 16
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.volume.available ? "Default PipeWire output. Speaker routing and protection stay below this layer." : "No audio output is available yet."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 13
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: !page.volume.available ? "—" : page.volume.muted ? "Muted" : page.volume.percent + "%"
            color: MobileTheme.accent
            font.family: MobileTheme.fontFamily
            font.pixelSize: 42
            font.bold: true
        }
        Slider {
            id: slider
            width: parent.width
            from: 0; to: 100; stepSize: 1
            enabled: page.volume.available === true && !page.volume.muted
            value: page.volume.muted ? 0 : page.volume.percent
            onMoved: page.run(["set", String(Math.round(value))])
            background: Rectangle {
                x: slider.leftPadding; y: (slider.height - height) / 2
                width: slider.availableWidth; height: 10; radius: 5
                color: MobileTheme.muted
                Rectangle {
                    width: parent.width * slider.visualPosition; height: parent.height; radius: 5
                    color: MobileTheme.accent
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: (slider.height - height) / 2
                width: 28; height: 28; radius: 14
                color: MobileTheme.foreground
            }
        }
        SettingsRow {
            width: parent.width
            label: "Mute"
            value: page.volume.muted ? "On" : "Off"
            selected: page.volume.muted === true
            enabled: page.volume.available === true
            onClicked: page.run(["mute"])
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Volume keys and the on-screen overlay use the same helper. Per-app routing is not available."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 13
        }
    }
}
