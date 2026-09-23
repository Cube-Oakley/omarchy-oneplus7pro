import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    property string label: ""
    property string value: ""
    property bool selected: false
    property bool enabled: true
    signal clicked()
    implicitHeight: 64
    radius: MobileTheme.radius(16)
    opacity: enabled ? 1 : 0.45
    color: tap.pressed ? MobileTheme.muted : selected ? MobileTheme.selection : MobileTheme.surface
    border.width: selected ? 1 : 0
    border.color: MobileTheme.accent
    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        Text {
            Layout.fillWidth: true
            text: row.label
            textFormat: Text.PlainText
            color: MobileTheme.foreground
            font.family: MobileTheme.fontFamily
            font.pixelSize: 16
            elide: Text.ElideRight
        }
        Text {
            visible: row.value.length > 0
            text: row.value
            textFormat: Text.PlainText
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        Text {
            text: "›"
            color: MobileTheme.secondary
            font.family: MobileTheme.fontFamily
            font.pixelSize: 22
        }
    }
    TapHandler { id: tap; enabled: row.enabled; onTapped: row.clicked() }
}
