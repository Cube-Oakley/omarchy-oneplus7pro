import QtQuick
import QtQuick.Layouts

// First-run explanation of the permissions an app's manifest requested.
ColumnLayout {
    id: page
    property var requests: []
    signal allowed()
    signal denied()
    spacing: 16
    Text {
        Layout.fillWidth: true
        text: "This app asks to use:"
        color: MobileTheme.foreground
        font.family: MobileTheme.fontFamily
        font.pixelSize: 18
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: page.requests
        delegate: Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: copy.height + 28
            radius: MobileTheme.radius(16)
            color: MobileTheme.surface
            Column {
                id: copy
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 16
                spacing: 4
                Text {
                    width: parent.width
                    text: modelData.title
                    color: MobileTheme.foreground
                    font.family: MobileTheme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: modelData.detail
                    color: MobileTheme.secondary
                    font.family: MobileTheme.fontFamily
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
    Item { Layout.fillHeight: true }
    TouchButton {
        Layout.fillWidth: true
        label: "Allow"
        selected: true
        onClicked: page.allowed()
    }
    TouchButton {
        Layout.fillWidth: true
        label: "Don't allow"
        onClicked: page.denied()
    }
}
