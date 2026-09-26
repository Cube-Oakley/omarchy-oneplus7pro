import Quickshell
import QtQuick

ShellRoot {
    PanelWindow {
        id: panel
        color: "#15151e"
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        property int contacts: 0
        Column {
            anchors.centerIn: parent
            spacing: 32
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Touchscreen test"; color: "#eeeeff"; font.pixelSize: 64 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Tap and drag with one or two fingers"; color: "#b8b8cc"; font.pixelSize: 36 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Touches: " + panel.contacts; color: "#bb99ff"; font.pixelSize: 52 }
        }
        MultiPointTouchArea {
            anchors.fill: parent
            mouseEnabled: false
            touchPoints: [
                TouchPoint { id: p1 }, TouchPoint { id: p2 },
                TouchPoint { id: p3 }, TouchPoint { id: p4 }, TouchPoint { id: p5 }
            ]
            onPressed: (points) => {
                panel.contacts += points.length
                for (const p of points) console.log("TOUCH_UI press id=" + p.pointId + " x=" + p.x + " y=" + p.y)
            }
            onReleased: (points) => console.log("TOUCH_UI released=" + points.length)
        }
        Repeater {
            model: [p1, p2, p3, p4, p5]
            Rectangle {
                required property var modelData
                required property int index
                width: 140; height: 140; radius: 70
                color: ["#bb99ff", "#77ddbb", "#ffaa77", "#77bbff", "#ff77bb"][index]
                opacity: 0.8
                visible: modelData.pressed
                x: modelData.x - width / 2
                y: modelData.y - height / 2
            }
        }
    }
}
