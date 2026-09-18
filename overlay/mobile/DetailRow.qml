import QtQuick
import QtQuick.Layouts
RowLayout {
    id: row
    property string label: ""
    property string value: "—"
    spacing: 18
    Text { font.family: MobileTheme.fontFamily; text: row.label; color: MobileTheme.secondary; font.pixelSize: 14; Layout.preferredWidth: 124 }
    Text { font.family: MobileTheme.fontFamily; text: row.value; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: MobileTheme.foreground; font.pixelSize: 14; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
}
