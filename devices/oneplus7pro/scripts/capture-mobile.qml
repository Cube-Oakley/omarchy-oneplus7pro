import QtQuick
import Quickshell
import Quickshell.Wayland

// Run inside the phone's Wayland session. This captures real compositor output.
// Set MOBILE_CAPTURE_PATH to an absolute output filename. For publication, use
// the shell's screenshotPrivacy IPC and inspect every image before committing.
ShellRoot {
    PanelWindow {
        implicitWidth: 1; implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "mobile-readme-capture"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
        ScreencopyView {
            id: capture
            width: 480; height: 1040
            captureSource: Quickshell.screens[0]
            constraintSize: Qt.size(480, 1040)
            live: false
            onHasContentChanged: if (hasContent) delay.start()
        }
    }
    Timer {
        id: delay; interval: 300
        onTriggered: capture.grabToImage(result => {
            const path = Quickshell.env("MOBILE_CAPTURE_PATH") || "/tmp/mobile-capture.png";
            console.log("CAPTURE_SAVED " + result.saveToFile(path));
            Qt.quit();
        }, Qt.size(480, 1040))
    }
    Timer { running: true; interval: 15000; onTriggered: Qt.quit() }
}
