import QtQuick
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    property var apps: []
    function refresh() { if (!probe.running) probe.running = true; }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-app", "apps"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { page.apps = JSON.parse(stdout.text).apps || []; }
            catch (e) { page.apps = []; }
        }
    }
    Process {
        id: revoke
        property var args: []
        stdout: StdioCollector {}
        onExited: page.refresh()
    }
    Column {
        id: body
        width: page.width
        spacing: 12
        Text {
            visible: page.apps.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No mobile apps are installed yet."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 16
        }
        Repeater {
            model: page.apps
            delegate: Column {
                id: appBlock
                required property var modelData
                width: body.width
                spacing: 8
                Text {
                    width: parent.width
                    text: appBlock.modelData.name
                    color: MobileTheme.foreground
                    font.family: MobileTheme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                }
                Repeater {
                    model: appBlock.modelData.permissions || []
                    delegate: SettingsRow {
                        required property var modelData
                        width: appBlock.width
                        label: modelData.title
                        value: modelData.granted ? "Allowed" : "Not allowed"
                        selected: modelData.granted
                        onClicked: {
                            if (!modelData.granted || revoke.running) return;
                            revoke.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-app", "revoke", appBlock.modelData.id, modelData.id];
                            revoke.running = true;
                        }
                    }
                }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            topPadding: 8
            text: "Tap an allowed permission to revoke it. The app asks again the next time it opens. This is not a process sandbox."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 14
        }
    }
}
