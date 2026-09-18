import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ShellRoot {
    FloatingWindow {
        title: "Keyboard protocol check"
        color: "#1a1b26"
        implicitWidth: 400; implicitHeight: 400
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 24
            Text { text: "Keyboard check"; color: "#c0caf5"; font.pixelSize: 24 }
            Text { text: "Testing text-field focus.\nThis window closes shortly."; color: "#c0caf5"; font.pixelSize: 16 }
            TextField { id: field; Layout.fillWidth: true; placeholderText: "Automatic keyboard test" }
            Button { id: other; text: "Non-text control" }
            Item { Layout.fillHeight: true }
        }
        Timer { interval: 500; running: true; onTriggered: { field.forceActiveFocus(); console.log("PROBE_TEXT_FOCUS"); } }
        Timer { interval: 4500; running: true; onTriggered: { field.enabled = false; other.forceActiveFocus(); console.log("PROBE_TEXT_BLUR"); } }
        Timer { interval: 7500; running: true; onTriggered: Qt.quit() }
    }
}
