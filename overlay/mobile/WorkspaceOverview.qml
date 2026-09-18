import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: overview
    property int selectedWorkspace: 1
    property bool active: false
    property var windows: Hyprland.toplevels.values.filter(w => w.workspace && w.workspace.id === selectedWorkspace)
    property var heldWindow: null
    property var heldCard: null
    property point pickupPoint: Qt.point(0, 0)
    property point cardOrigin: Qt.point(0, 0)
    readonly property real dragDistance: Math.hypot(heldPoint.x - pickupPoint.x, heldPoint.y - pickupPoint.y)
    property point heldPoint: Qt.point(0, 0)
    property string dropKind: ""
    property int dropWorkspace: 0
    property var dropWindow: null
    readonly property bool arranging: heldWindow !== null
    readonly property var swapTargets: windows.filter(w => w !== heldWindow)
    signal swapWindows(var source, var target)
    function cancelArrangement() { heldWindow = null; heldCard = null; dropKind = ""; dropWindow = null; }
    function beginArrangement(card, window, scenePosition) {
        heldCard = card;
        cardOrigin = card.mapToItem(overview, 0, 0);
        pickupPoint = mapFromItem(null, scenePosition.x, scenePosition.y);
        heldPoint = pickupPoint;
        heldWindow = window;
        findTarget();
    }
    function containsPoint(item, p) {
        if (!item) return false;
        const local = item.mapFromItem(overview, p.x, p.y);
        return local.x >= 0 && local.y >= 0 && local.x < item.width && local.y < item.height;
    }
    function updateArrangement(scenePosition) {
        if (!arranging) return;
        heldPoint = mapFromItem(null, scenePosition.x, scenePosition.y);
        findTarget();
    }
    function findTarget() {
        dropKind = ""; dropWindow = null;
        if (!arranging || dragDistance < 18) return;
        if (containsPoint(closeTarget, heldPoint)) { dropKind = "close"; return; }
        for (let i = 0; i < workspaceTargets.count; ++i) {
            if (containsPoint(workspaceTargets.itemAt(i), heldPoint)) {
                dropKind = "workspace"; dropWorkspace = i + 1; return;
            }
        }
        if (!containsPoint(swapArea, heldPoint)) return;
        for (let i = 0; i < windowTargets.count; ++i) {
            if (containsPoint(windowTargets.itemAt(i), heldPoint)) {
                dropKind = "swap"; dropWindow = swapTargets[i]; return;
            }
        }
    }
    function finishArrangement(position) {
        updateArrangement(position);
        const source = heldWindow, target = dropWindow, kind = dropKind, workspace = dropWorkspace;
        cancelArrangement();
        if (!source || !Hyprland.toplevels.values.includes(source)) return;
        if (kind === "close") closeWindow(source);
        else if (kind === "workspace") moveWindow(source, workspace);
        else if (kind === "swap" && target && Hyprland.toplevels.values.includes(target)) swapWindows(source, target);
    }
    onActiveChanged: if (!active) cancelArrangement()
    onWindowsChanged: if (heldWindow && !Hyprland.toplevels.values.includes(heldWindow)) cancelArrangement()
    signal enterWorkspace(int number)
    signal focusWindow(var window)
    signal moveWindow(var window, int number)
    signal maximizeWindow(var window)
    signal closeWindow(var window)
    signal launchTerminal()
    ColumnLayout {
    anchors.fill: parent
    spacing: 22
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        Repeater {
            id: workspaceTargets
            model: MobileTheme.state.device.workspaceCount || 4
            Rectangle {
                id: space
                required property int index
                readonly property var members: Hyprland.toplevels.values.filter(w => w.workspace && w.workspace.id === index + 1)
                readonly property bool targeted: overview.arranging && overview.dropKind === "workspace" && overview.dropWorkspace === index + 1
                readonly property bool selected: overview.selectedWorkspace === index + 1
                Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 92
                radius: 16; color: targeted || selected ? MobileTheme.selection : MobileTheme.surface
                border.width: targeted ? 3 : selected ? 2 : 0; border.color: MobileTheme.accent
                Behavior on color { ColorAnimation { duration: 150 } }
                Text { font.family: MobileTheme.fontFamily; x: 12; y: 10; text: String(space.index + 1).padStart(2, "0"); color: space.selected ? MobileTheme.accent : MobileTheme.secondary; font.pixelSize: 18; font.bold: true }
                Row {
                    x: 12; y: 42; spacing: 3
                    Repeater { model: Math.min(space.members.length, 4); Rectangle { width: 9; height: 14; radius: 2; color: space.selected ? MobileTheme.accent : MobileTheme.muted } }
                }
                Text { font.family: MobileTheme.fontFamily; x: 12; y: 67; text: space.members.length + (space.members.length === 1 ? " app" : " apps"); color: MobileTheme.secondary; font.pixelSize: 11 }
                TapHandler {
                    enabled: !overview.arranging
                    onTapped: {
                        if (space.selected) overview.enterWorkspace(space.index + 1);
                        else overview.selectedWorkspace = space.index + 1;
                    }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text { font.family: MobileTheme.fontFamily; text: overview.arranging ? "Move window" : "Workspace " + overview.selectedWorkspace; color: MobileTheme.foreground; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
        Text { font.family: MobileTheme.fontFamily; text: overview.arranging ? "Drop on a space or app" : "Tap selected space to enter"; color: MobileTheme.secondary; font.pixelSize: 11 }
    }
    ListView {
        id: cards
        Layout.fillWidth: true; Layout.fillHeight: true
        interactive: !overview.arranging
        orientation: ListView.Horizontal; spacing: 14; clip: true
        snapMode: ListView.SnapOneItem; boundsBehavior: Flickable.StopAtBounds
        model: overview.windows
        onModelChanged: positionViewAtBeginning()
        delegate: WindowCard {
            id: preview
            required property var modelData
            width: cards.width - (overview.windows.length > 1 ? 30 : 0); height: cards.height
            window: modelData; captureEnabled: overview.active
            onArrangeStarted: position => overview.beginArrangement(preview, modelData, position)
            onArrangeMoved: position => overview.updateArrangement(position)
            onArrangeFinished: position => overview.finishArrangement(position)
            onArrangeCanceled: overview.cancelArrangement()
            onFocusWindow: overview.focusWindow(modelData)
            onMoveWindow: number => overview.moveWindow(modelData, number)
            onMaximizeWindow: overview.maximizeWindow(modelData)
            onCloseWindow: overview.closeWindow(modelData)
        }
        Column {
            visible: overview.windows.length === 0
            anchors.centerIn: parent; spacing: 18; width: parent.width
            Text { font.family: MobileTheme.fontFamily; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "A little room to think."; color: MobileTheme.foreground; font.pixelSize: 24; font.bold: true }
            Text { font.family: MobileTheme.fontFamily; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Start something in workspace " + overview.selectedWorkspace; color: MobileTheme.secondary; font.pixelSize: 14 }
            TouchButton { anchors.horizontalCenter: parent.horizontalCenter; width: 180; label: "Open terminal"; selected: true; onClicked: { overview.enterWorkspace(overview.selectedWorkspace); overview.launchTerminal(); } }
        }
    }
    Row {
        Layout.alignment: Qt.AlignHCenter; spacing: 6
        Repeater {
            model: overview.windows.length
            Rectangle { required property int index; width: 6; height: 6; radius: 3; color: MobileTheme.accent; opacity: index === Math.round(cards.contentX / (cards.width - 16)) ? 1 : 0.25 }
        }
    }
    }
    Rectangle {
        x: cards.x; y: cards.y; width: cards.width; height: cards.height
        visible: overview.arranging
        color: MobileTheme.background
        // The workspace row stays in place. No handlers here: the preview
        // retains the original touch grab while this layer reveals targets.
        ColumnLayout {
            anchors.fill: parent; spacing: 16
            Flickable {
                id: swapArea
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: targetGrid.height; clip: true; interactive: false
                GridLayout {
                    id: targetGrid; width: parent.width; columns: 2; columnSpacing: 12; rowSpacing: 12
                    Repeater {
                        id: windowTargets
                        model: overview.swapTargets
                        Rectangle {
                            required property var modelData
                            readonly property bool targeted: overview.dropKind === "swap" && overview.dropWindow === modelData
                            Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 114
                            radius: 16; color: targeted ? MobileTheme.selection : MobileTheme.surface
                            border.width: targeted ? 2 : 1; border.color: targeted ? MobileTheme.accent : MobileTheme.muted
                            Column {
                                anchors.fill: parent; anchors.margins: 16; spacing: 10
                                Text { font.family: MobileTheme.fontFamily; width: parent.width; text: modelData.lastIpcObject.class || "App"; textFormat: Text.PlainText; elide: Text.ElideRight; color: MobileTheme.accent; font.pixelSize: 17; font.bold: true }
                                Text { font.family: MobileTheme.fontFamily; width: parent.width; text: modelData.title; textFormat: Text.PlainText; elide: Text.ElideRight; color: MobileTheme.secondary; font.pixelSize: 12 }
                                Text { font.family: MobileTheme.fontFamily; text: "Swap positions"; color: MobileTheme.foreground; font.pixelSize: 12 }
                            }
                        }
                    }
                }
                Text { font.family: MobileTheme.fontFamily; visible: overview.swapTargets.length === 0; anchors.centerIn: parent; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "No other windows in this space.\nDrop onto a workspace above to move."; color: MobileTheme.secondary; font.pixelSize: 14 }
            }
            Rectangle {
                id: closeTarget
                Layout.fillWidth: true; implicitHeight: 80; radius: 20
                color: overview.dropKind === "close" ? MobileTheme.selection : MobileTheme.surface
                border.width: overview.dropKind === "close" ? 2 : 1
                border.color: overview.dropKind === "close" ? MobileTheme.accent : MobileTheme.muted
                Text { font.family: MobileTheme.fontFamily; anchors.centerIn: parent; text: overview.dropKind === "close" ? "Release to close" : "×   Drop here to close"; color: MobileTheme.foreground; font.pixelSize: 17 }
            }
        }
    }
    Timer {
        interval: 16; repeat: true; running: overview.arranging
        onTriggered: {
            const p = swapArea.mapFromItem(overview, overview.heldPoint.x, overview.heldPoint.y);
            if (p.x < 0 || p.x > swapArea.width || p.y < 0 || p.y > swapArea.height) return;
            const direction = p.y < 42 ? -1 : p.y > swapArea.height - 42 ? 1 : 0;
            swapArea.contentY = Math.max(0, Math.min(Math.max(0, swapArea.contentHeight - swapArea.height), swapArea.contentY + direction * 5));
            overview.findTarget();
        }
    }
    HeldPreview {
        active: overview.arranging
        sourceCard: overview.heldCard
        originPoint: overview.cardOrigin
        pickupPoint: overview.pickupPoint
        currentPoint: overview.heldPoint
    }
}
