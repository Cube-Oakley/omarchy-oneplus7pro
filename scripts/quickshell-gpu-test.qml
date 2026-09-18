import Quickshell
import QtQuick

// Temporary animation/load test, launched separately from the user's shell.
ShellRoot {
    PanelWindow {
        id: panel
        color: "#161622"
        implicitHeight: 240
        anchors { left: true; right: true; bottom: true }
        property int frames: 0
        property int intervals: 0
        FrameAnimation {
            running: true
            onTriggered: panel.frames++
        }
        Timer {
            interval: 5000
            repeat: true
            running: true
            onTriggered: {
                console.log("GPU_TEST frames_in_5s=" + panel.frames)
                panel.frames = 0
                panel.intervals++
                if (panel.intervals === 4) Qt.quit()
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            text: "Adreno animation test"
            color: "#eeeeff"
            font.pixelSize: 40
        }
        Rectangle {
            id: dot
            width: 64; height: 64; radius: 32
            y: 120
            color: "#bb99ff"
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { from: 24; to: panel.width - 88; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { from: panel.width - 88; to: 24; duration: 1500; easing.type: Easing.InOutSine }
            }
        }
    }
}
