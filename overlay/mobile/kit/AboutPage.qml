import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Flickable {
    id: page
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: body.height
    property var about: ({available: false})
    property string message: ""
    function refresh() { if (!probe.running) probe.running = true; }
    function copyReport() {
        if (copy.running) return;
        copy.running = true;
    }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-about"]
        running: true
        stdout: StdioCollector {}
        onExited: {
            try { page.about = JSON.parse(stdout.text); }
            catch (e) { page.about = {available: false}; }
        }
    }
    Process {
        id: copy
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-about", "report"]
        stdout: StdioCollector {}
        onExited: {
            try {
                const result = JSON.parse(stdout.text);
                if (result.text) record.payload = JSON.stringify({text: result.text}) + "\n";
                record.running = true;
            } catch (e) { page.message = "Could not copy device report"; }
        }
    }
    Process {
        id: record
        stdinEnabled: true
        property string payload: ""
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-clipboard", "record"]
        stdout: StdioCollector {}
        onStarted: { write(record.payload); record.payload = ""; stdinEnabled = false; }
        onExited: code => {
            stdinEnabled = true;
            page.message = code === 0 ? "Copied a device report to the clipboard." : "Could not copy device report";
        }
    }
    Column {
        id: body
        width: page.width
        spacing: 12
        DetailRow { width: parent.width; label: "Host"; value: page.about.hostname || "—" }
        DetailRow { width: parent.width; label: "OS"; value: page.about.os || "—" }
        DetailRow { width: parent.width; label: "Kernel"; value: page.about.kernel || "—" }
        DetailRow { width: parent.width; label: "Slot"; value: page.about.slot || "—" }
        DetailRow { width: parent.width; visible: !!page.about.model; label: "Model"; value: page.about.model || "—" }
        DetailRow { width: parent.width; label: "Backups"; value: page.about.backups ? String(page.about.backups) : "—" }
        Text {
            width: parent.width
            wrapMode: Text.WrapAnywhere
            text: page.about.backup || "No installer backups yet."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 13
        }
        TouchButton {
            width: parent.width
            label: "Copy device report"
            onClicked: page.copyReport()
        }
        Text {
            width: parent.width
            visible: page.message.length > 0
            wrapMode: Text.WordWrap
            text: page.message
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 13
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "The report is hostname, OS, kernel, slot and backup path. It does not include serial numbers or USB addresses."
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 12
        }
    }
}
