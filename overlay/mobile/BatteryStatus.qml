import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

Item {
    id: battery
    property var state: MobileStatus.battery
    visible: state.available === true
    implicitWidth: visible ? content.width : 0
    implicitHeight: 24

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Item {
            width: 13; height: 22
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { x: 4; width: 5; height: 2; radius: 1; color: MobileTheme.secondary }
            Rectangle {
                y: 3; width: 13; height: 19; radius: 3
                color: "transparent"; border.width: 1; border.color: MobileTheme.secondary
                Rectangle {
                    x: 2; y: 17 - height; width: 9; radius: 1
                    height: 15 * Math.max(0, Math.min(100, battery.state.capacity || 0)) / 100
                    color: battery.state.charging ? MobileTheme.accent : MobileTheme.foreground
                }
            }
            Shape {
                anchors.fill: parent
                visible: battery.state.charging === true
                ShapePath {
                    strokeColor: MobileTheme.background; strokeWidth: 0.9
                    fillColor: MobileTheme.foreground
                    startX: 8; startY: 6
                    PathLine { x: 4; y: 13 }
                    PathLine { x: 7; y: 13 }
                    PathLine { x: 5; y: 19 }
                    PathLine { x: 10; y: 11 }
                    PathLine { x: 7; y: 11 }
                    PathLine { x: 8; y: 6 }
                }
            }
        }
        Text { font.family: MobileTheme.fontFamily;
            anchors.verticalCenter: parent.verticalCenter
            text: (battery.state.capacity ?? "") + "%"
            color: MobileTheme.foreground; font.pixelSize: 14
        }
    }
}
