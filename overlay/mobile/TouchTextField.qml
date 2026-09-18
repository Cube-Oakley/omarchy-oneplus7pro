import QtQuick
import QtQuick.Controls

// A popup becoming visible or regaining focus is not a request to type.
TextField {
    id: field
    property bool editing: false
    signal editingRequested()
    readOnly: !editing
    focusPolicy: Qt.NoFocus
    activeFocusOnPress: false
    onEditingChanged: if (!editing) focus = false
    TapHandler { onTapped: field.editingRequested() }
}
