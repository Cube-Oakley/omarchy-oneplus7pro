import QtQuick
import Quickshell
import Quickshell.Wayland

// Short-lived diagnostic only. A tiny changing pixel marker lets the host
// distinguish animation ticks from updates reaching the retained framebuffer.
ShellRoot {
    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: 140
        exclusionMode: ExclusionMode.Ignore
        color: "#202536"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "mobile-frame-test"
        property int frames: 0
        FrameAnimation { running: true; onTriggered: panel.frames++ }
        Rectangle { x: 6; y: 6; width: 8; height: 8; color: Qt.rgba((panel.frames % 251) / 255, ((panel.frames * 17) % 251) / 255, 0.5, 1) }
        Text { x: 24; y: 28; text: "Measuring display updates…"; font.pixelSize: 20; color: "#dbe1ff" }
        Rectangle { y: 82; width: 40; height: 16; radius: 8; color: "#7aa2f7"; x: 20 + (panel.frames % 180) / 180 * (panel.width - 80) }
        Timer { interval: 16000; running: true; onTriggered: { console.log("FRAME_TEST animation_ticks=" + panel.frames); Qt.quit(); } }
    }
}
