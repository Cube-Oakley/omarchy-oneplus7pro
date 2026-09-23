import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import OmarchyMobile

ShellRoot {
    id: root
    property bool ready: false
    property bool allowed: false
    property var requests: []
    property string homePath: ""
    property string folder: ""
    property string folderName: "Files"
    property string parentPath: ""
    property var places: []
    property var crumbs: []
    property var entries: []
    property var shown: []
    property string query: ""
    property string sort: "name"
    property bool hidden: false
    property string message: ""
    property string mode: "browse" // browse, detail, pick
    property var detail: null
    property bool confirming: false
    property bool naming: false
    property string namePurpose: "folder"
    property string pickAction: ""
    property string pickSource: ""
    property string pickParent: ""
    property string pickName: ""
    property var queued: []

    function bin(name) { return Quickshell.env("HOME") + "/.local/bin/" + name; }
    function flags() { return [sort, hidden ? "1" : "0"]; }
    function run(kind, args) {
        if (tool.running) { queued = [kind, args]; return; }
        tool.kind = kind;
        tool.command = args;
        tool.running = true;
    }
    function refresh(path) {
        const target = path || folder;
        run("list", [bin("omarchy-mobile-files"), "list", target].concat(flags()));
    }
    function applyFilter() {
        const q = query.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < entries.length; i++) {
            const name = String(entries[i].name || "");
            if (!q || name.toLowerCase().indexOf(q) >= 0) out.push(entries[i]);
        }
        shown = out;
    }
    function showFolder(result) {
        folder = result.path || folder;
        folderName = result.name || "Files";
        parentPath = result.parent || "";
        crumbs = result.crumbs || [];
        entries = result.entries || [];
        message = result.truncated ? "Showing the first 500 items" : "";
        naming = false;
        confirming = false;
        applyFilter();
    }
    function finishQueue() {
        if (!queued.length) return;
        const next = queued;
        queued = [];
        run(next[0], next[1]);
    }
    function goBack() {
        if (naming) { naming = false; keyboardDo("hide"); return; }
        if (mode === "detail") { mode = "browse"; confirming = false; return; }
        if (mode === "pick") {
            if (parentPath) refresh(parentPath);
            else mode = "detail";
            return;
        }
        if (parentPath) refresh(parentPath);
        else Qt.quit();
    }
    function openDetail(entry) {
        detail = entry;
        confirming = false;
        mode = "detail";
        run("preview", [bin("omarchy-mobile-files"), "preview", entry.path]);
    }
    function beginPick(action) {
        pickAction = action;
        pickSource = detail.path;
        pickParent = folder;
        pickName = detail.name;
        mode = "pick";
    }
    function commitName() {
        const name = nameField.text.trim();
        if (!name) return;
        if (namePurpose === "rename" && detail)
            run("rename", [bin("omarchy-mobile-files"), "rename", detail.path, name].concat(flags()));
        else
            run("mkdir", [bin("omarchy-mobile-files"), "mkdir", folder, name].concat(flags()));
        keyboardDo("hide");
    }
    function placeHere() {
        if (folder === pickParent) { message = "Already in this folder"; return; }
        run(pickAction, [bin("omarchy-mobile-files"), pickAction, pickSource, folder].concat(flags()));
    }
    function keyboardDo(action) {
        keyboard.command = [bin("omarchy-mobile-keyboard"), action];
        keyboard.running = true;
    }
    function mark(kind) {
        if (kind === "folder") return "F";
        if (kind === "image") return "I";
        if (kind === "text") return "T";
        if (kind === "audio") return "A";
        if (kind === "video") return "V";
        if (kind === "archive") return "Z";
        return "·";
    }
    function fileUrl(path) {
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }
    function sortLabel() {
        if (sort === "modified") return "Newest";
        if (sort === "size") return "Largest";
        return "Name";
    }
    function subtitle(entry) {
        if (entry.dir) return "Folder";
        return entry.modified ? entry.size + " · " + entry.modified : entry.size;
    }
    Component.onCompleted: run("status", [bin("omarchy-mobile-app"), "status", "files"])
    onQueryChanged: applyFilter()

    Process {
        id: tool
        property string kind: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: {
            let result = {};
            try { result = JSON.parse(stdout.text); }
            catch (e) {
                const err = (stderr.text || "").trim().split("\n").pop();
                root.message = err || "Could not read the file helper";
                root.finishQueue();
                return;
            }
            if (result.ok === false) {
                root.message = result.error || "Request failed";
                root.finishQueue();
                return;
            }
            if (tool.kind === "status") {
                const items = result.permissions || [];
                let granted = items.length > 0;
                for (let i = 0; i < items.length; i++) if (!items[i].granted) granted = false;
                root.requests = items;
                root.allowed = granted;
                root.ready = true;
                if (root.allowed) root.run("roots", [root.bin("omarchy-mobile-files"), "roots"]);
                return;
            }
            if (tool.kind === "grant") {
                root.allowed = true;
                root.run("roots", [root.bin("omarchy-mobile-files"), "roots"]);
                return;
            }
            if (tool.kind === "roots") {
                root.homePath = result.home || ((result.roots || [])[0] || "");
                root.places = result.places || [];
                if (root.homePath) root.refresh(root.homePath);
                return;
            }
            if (tool.kind === "preview") {
                if (root.mode === "detail") root.detail = result;
                root.finishQueue();
                return;
            }
            if (tool.kind === "open") {
                root.message = "Opened";
                root.finishQueue();
                return;
            }
            root.showFolder(result);
            if (tool.kind !== "list") root.mode = "browse";
            root.finishQueue();
        }
    }
    Process { id: keyboard }

    AppWindow {
        compact: true
        pageMargin: 16
        kicker: ""
        appTitle: "Files"
        heading: root.allowed ? root.folderName : "Files"
        backVisible: root.allowed && (root.mode !== "browse" || root.naming || root.parentPath !== "")
        onBackClicked: root.goBack()
        GrantPage {
            anchors.fill: parent
            visible: root.ready && !root.allowed
            requests: root.requests
            onAllowed: root.run("grant", [root.bin("omarchy-mobile-app"), "grant", "files", "files.home"])
            onDenied: Qt.quit()
        }
        ColumnLayout {
            anchors.fill: parent
            visible: root.allowed
            spacing: 8

            Rectangle {
                visible: root.mode === "pick"
                Layout.fillWidth: true
                implicitHeight: pickBox.implicitHeight + 16
                radius: MobileTheme.radius(16)
                color: MobileTheme.selection
                ColumnLayout {
                    id: pickBox
                    anchors.fill: parent
                    anchors.margins: 8
                    Text {
                        Layout.fillWidth: true
                        text: (root.pickAction === "copy" ? "Copy " : "Move ") + root.pickName + " into this folder"
                        color: MobileTheme.foreground
                        font.family: MobileTheme.fontFamily
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        TouchButton { Layout.fillWidth: true; label: "Place here"; selected: true; onClicked: root.placeHere() }
                        TouchButton { Layout.fillWidth: true; label: "Cancel"; onClicked: root.mode = "detail" }
                    }
                }
            }

            Flickable {
                visible: root.mode !== "detail"
                Layout.fillWidth: true
                implicitHeight: 40
                contentWidth: placeRow.width
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                Row {
                    id: placeRow
                    spacing: 8
                    Repeater {
                        model: root.places
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: placeText.implicitWidth + 22
                            height: 36
                            radius: MobileTheme.radius(18)
                            color: modelData.path === root.folder ? MobileTheme.selection : MobileTheme.surface
                            border.width: modelData.path === root.folder ? 1 : 0
                            border.color: MobileTheme.accent
                            Text {
                                id: placeText
                                anchors.centerIn: parent
                                text: modelData.name
                                color: MobileTheme.foreground
                                font.family: MobileTheme.fontFamily
                                font.pixelSize: 13
                            }
                            TapHandler { onTapped: root.refresh(modelData.path) }
                        }
                    }
                }
            }

            Flickable {
                visible: root.mode !== "detail" && root.crumbs.length > 1
                Layout.fillWidth: true
                implicitHeight: 24
                contentWidth: crumbRow.width
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                Row {
                    id: crumbRow
                    spacing: 4
                    Repeater {
                        model: root.crumbs
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: 4
                            Text {
                                text: index ? "›" : ""
                                color: MobileTheme.secondary
                                font.family: MobileTheme.fontFamily
                                font.pixelSize: 13
                            }
                            Text {
                                text: modelData.name
                                color: modelData.path === root.folder ? MobileTheme.foreground : MobileTheme.accent
                                font.family: MobileTheme.fontFamily
                                font.pixelSize: 13
                                TapHandler { onTapped: root.refresh(modelData.path) }
                            }
                        }
                    }
                }
            }

            TouchTextField {
                id: filterField
                visible: root.mode !== "detail" && !root.naming
                Layout.fillWidth: true
                placeholderText: "Filter this folder"
                onTextChanged: root.query = text
                onEditingRequested: root.keyboardDo("show")
                onEditingChanged: if (!editing) root.keyboardDo("hide")
            }

            RowLayout {
                visible: root.naming
                Layout.fillWidth: true
                TouchTextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: root.namePurpose === "rename" ? "New name" : "Folder name"
                    editing: root.naming
                    onEditingRequested: root.keyboardDo("show")
                    onAccepted: root.commitName()
                }
                TouchButton { label: root.namePurpose === "rename" ? "Rename" : "Create"; selected: true; onClicked: root.commitName() }
            }

            Text {
                visible: root.message !== ""
                Layout.fillWidth: true
                text: root.message
                color: MobileTheme.secondary
                font.family: MobileTheme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Flickable {
                visible: root.mode === "detail" && root.detail
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: detailBody.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: detailBody
                    width: parent.width
                    spacing: 12
                    Row {
                        spacing: 12
                        Rectangle {
                            width: 48; height: 48; radius: MobileTheme.radius(14)
                            color: MobileTheme.selection
                            Text {
                                anchors.centerIn: parent
                                text: root.mark(root.detail ? root.detail.kind : "")
                                color: MobileTheme.accent
                                font.family: MobileTheme.fontFamily
                                font.pixelSize: 18
                                font.bold: true
                            }
                        }
                        Column {
                            width: detailBody.width - 60
                            spacing: 2
                            Text {
                                width: parent.width
                                text: root.detail ? root.detail.name : ""
                                color: MobileTheme.foreground
                                font.family: MobileTheme.fontFamily
                                font.pixelSize: 18
                                font.bold: true
                                wrapMode: Text.Wrap
                            }
                            Text {
                                width: parent.width
                                text: root.detail ? root.subtitle(root.detail) : ""
                                color: MobileTheme.secondary
                                font.family: MobileTheme.fontFamily
                                font.pixelSize: 13
                            }
                        }
                    }
                    Image {
                        visible: root.detail && root.detail.kind === "image"
                        width: detailBody.width
                        height: 200
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize: Qt.size(800, 800)
                        source: visible ? root.fileUrl(root.detail.path) : ""
                    }
                    Text {
                        visible: root.detail && root.detail.text
                        width: detailBody.width
                        text: (root.detail && root.detail.text ? root.detail.text : "") + (root.detail && root.detail.text_truncated ? "\n…" : "")
                        color: MobileTheme.foreground
                        font.family: MobileTheme.fontFamily
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                    }
                    TouchButton {
                        width: parent.width
                        visible: root.detail && !root.detail.dir && !root.confirming
                        label: "Open"
                        selected: true
                        onClicked: root.run("open", [root.bin("omarchy-mobile-files"), "open", root.detail.path])
                    }
                    TouchButton {
                        width: parent.width
                        visible: !root.confirming
                        label: "Rename"
                        onClicked: { root.namePurpose = "rename"; root.naming = true; nameField.text = root.detail.name; }
                    }
                    TouchButton { width: parent.width; visible: !root.confirming; label: "Move"; onClicked: root.beginPick("move") }
                    TouchButton { width: parent.width; visible: !root.confirming; label: "Copy"; onClicked: root.beginPick("copy") }
                    TouchButton { width: parent.width; visible: !root.confirming; label: "Delete"; onClicked: root.confirming = true }
                    TouchButton {
                        width: parent.width
                        visible: root.confirming
                        label: "Delete " + (root.detail ? root.detail.name : "")
                        selected: true
                        onClicked: root.run("delete", [root.bin("omarchy-mobile-files"), "delete", root.detail.path].concat(root.flags()))
                    }
                    TouchButton { width: parent.width; visible: root.confirming; label: "Cancel"; onClicked: root.confirming = false }
                }
            }

            Flickable {
                visible: root.mode !== "detail"
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: list.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: list
                    width: parent.width
                    spacing: 8
                    Text {
                        visible: root.shown.length === 0 && root.folder !== ""
                        width: parent.width
                        text: root.query.trim() !== "" ? "Nothing with that name" : "This folder is empty"
                        color: MobileTheme.secondary
                        font.family: MobileTheme.fontFamily
                        font.pixelSize: 15
                    }
                    Repeater {
                        model: root.shown
                        delegate: Rectangle {
                            required property var modelData
                            width: list.width
                            implicitHeight: 64
                            radius: MobileTheme.radius(16)
                            color: rowTap.pressed ? MobileTheme.muted : MobileTheme.surface
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 10
                                Rectangle {
                                    width: 36; height: 36; radius: MobileTheme.radius(10)
                                    color: MobileTheme.selection
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.mark(modelData.kind)
                                        color: MobileTheme.accent
                                        font.family: MobileTheme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                }
                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: modelData.name
                                        color: MobileTheme.foreground
                                        font.family: MobileTheme.fontFamily
                                        font.pixelSize: 16
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: root.subtitle(modelData)
                                        color: MobileTheme.secondary
                                        font.family: MobileTheme.fontFamily
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    TapHandler {
                                        id: rowTap
                                        onTapped: {
                                            if (root.mode === "pick") {
                                                if (modelData.dir) root.refresh(modelData.path);
                                            } else if (modelData.dir) root.refresh(modelData.path);
                                            else root.openDetail(modelData);
                                        }
                                    }
                                }
                                TouchButton {
                                    implicitWidth: 44
                                    implicitHeight: 44
                                    label: "···"
                                    textSize: 16
                                    onClicked: root.openDetail(modelData)
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                visible: root.mode !== "detail"
                Layout.fillWidth: true
                TouchButton {
                    Layout.fillWidth: true
                    label: "New"
                    textSize: 14
                    onClicked: { root.namePurpose = "folder"; root.naming = true; nameField.text = ""; }
                }
                TouchButton {
                    Layout.fillWidth: true
                    label: root.sortLabel()
                    textSize: 14
                    onClicked: {
                        root.sort = root.sort === "name" ? "modified" : root.sort === "modified" ? "size" : "name";
                        root.refresh(root.folder);
                    }
                }
                TouchButton {
                    Layout.fillWidth: true
                    label: "Hidden"
                    textSize: 14
                    selected: root.hidden
                    onClicked: { root.hidden = !root.hidden; root.refresh(root.folder); }
                }
            }
        }
    }
}
