import QtQuick
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    property var volumes: []
    function amount(bytes) {
        if (bytes === undefined || bytes === null) return "—";
        const units = ["B", "KB", "MB", "GB", "TB"];
        let size = Number(bytes);
        let unit = 0;
        while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit++; }
        return (unit === 0 ? size.toFixed(0) : size.toFixed(1)) + " " + units[unit];
    }
    function refresh() { if (!probe.running) probe.running = true; }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-storage"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { page.volumes = JSON.parse(stdout.text).volumes || []; }
            catch (e) { page.volumes = []; }
        }
    }
    Column {
        id: body
        width: page.width
        spacing: 12
        Repeater {
            model: page.volumes
            delegate: Column {
                required property var modelData
                width: body.width
                spacing: 12
                Text {
                    width: parent.width
                    text: modelData.label
                    color: MobileTheme.foreground
                    font.family: MobileTheme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: page.amount(modelData.free) + " free"
                    color: MobileTheme.accent
                    font.family: MobileTheme.fontFamily
                    font.pixelSize: 36
                    font.bold: true
                }
                DetailRow { width: parent.width; label: "Used"; value: page.amount(modelData.used) }
                DetailRow { width: parent.width; label: "Size"; value: page.amount(modelData.total) }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            topPadding: 8
            text: "This is the space on the phone. Choosing what to delete still happens in Files."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 14
        }
    }
}
