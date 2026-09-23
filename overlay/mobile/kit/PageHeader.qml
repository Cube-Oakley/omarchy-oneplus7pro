import QtQuick
import QtQuick.Layouts

Item {
    id: header
    property string kicker: ""
    property string title: ""
    property bool backVisible: false
    property bool compact: false
    signal backClicked()
    signal closeClicked()
    implicitHeight: compact ? 52 : 88
    Text {
        y: 0
        visible: !header.compact && header.kicker !== ""
        text: header.kicker
        color: MobileTheme.accent
        font.family: MobileTheme.fontFamily
        font.pixelSize: 11
        font.letterSpacing: 2.4
        font.bold: true
    }
    Text {
        y: header.compact ? 8 : 23
        width: parent.width - (header.backVisible ? 64 : 0)
        text: header.title
        color: MobileTheme.foreground
        font.family: MobileTheme.fontFamily
        font.pixelSize: header.compact ? 22 : 34
        font.bold: true
        elide: Text.ElideRight
    }
    TouchButton {
        visible: header.backVisible
        anchors.right: parent.right
        y: header.compact ? 2 : 21
        implicitWidth: 48
        implicitHeight: 48
        radius: MobileTheme.radius(header.compact ? 12 : 24)
        label: "‹"
        textSize: 28
        onClicked: header.backClicked()
    }
}
