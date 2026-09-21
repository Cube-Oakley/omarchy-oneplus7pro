import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: page
    property var fonts: []
    property var themeCards: []
    property var wallpaperCards: []
    property string activePicker: ""
    property bool pickerShown: false
    property bool installerKeyboard: false
    readonly property var preloadUrls: {
        const urls = [];
        const seen = {};
        function add(url) {
            if (!url || seen[url])
                return;
            seen[url] = true;
            urls.push(url);
        }
        for (let i = 0; i < themeCards.length; i++)
            add(themeCards[i].url);
        for (let i = 0; i < wallpaperCards.length; i++)
            add(wallpaperCards[i].url);
        return urls;
    }
    function loadFonts() {
        if (fontList.running) return;
        fontList.running = true;
    }
    function themeItems() {
        const names = MobileTheme.state.themes || [];
        const previews = MobileTheme.state.themePreviews || {};
        const items = [];
        for (let i = 0; i < names.length; i++) {
            const name = names[i];
            items.push({id: name, url: previews[name] || "", label: name.replace(/-/g, " ")});
        }
        return items;
    }
    function wallpaperItems() {
        const choices = (MobileTheme.state.wallpaper && MobileTheme.state.wallpaper.choices) || [];
        const items = [];
        for (let i = 0; i < choices.length; i++) {
            const choice = choices[i];
            items.push({id: choice.name, url: choice.url || "", label: choice.name});
        }
        return items;
    }
    function sameCards(left, right) {
        if (left.length !== right.length)
            return false;
        for (let i = 0; i < left.length; i++) {
            if (left[i].id !== right[i].id || left[i].url !== right[i].url)
                return false;
        }
        return true;
    }
    function refreshCards() {
        const themes = themeItems();
        const walls = wallpaperItems();
        if (!sameCards(themeCards, themes))
            themeCards = themes;
        if (!sameCards(wallpaperCards, walls))
            wallpaperCards = walls;
    }
    function indexOfId(items, id) {
        for (let i = 0; i < items.length; i++) {
            if (items[i].id === id)
                return i;
        }
        return 0;
    }
    function openPicker(kind) {
        refreshCards();
        if (kind === "theme" || kind === "wallpaper") {
            const flow = kind === "theme" ? themeFlow : wallpaperFlow;
            const items = kind === "theme" ? themeCards : wallpaperCards;
            const selected = kind === "theme"
                ? MobileTheme.state.name
                : (MobileTheme.state.wallpaper ? MobileTheme.state.wallpaper.name : "");
            flow.selectIndex(indexOfId(items, selected), true);
        }
        activePicker = kind;
        pickerShown = true;
        if (kind !== "install")
            installerKeyboard = false;
    }
    function closePicker() {
        pickerShown = false;
        activePicker = "";
        installerKeyboard = false;
        themeInstall.reset();
    }
    onInstallerKeyboardChanged: {
        kb.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-keyboard", installerKeyboard ? "show" : "hide"];
        if (!kb.running) kb.running = true;
    }
    Process { id: kb }
    Component.onCompleted: {
        loadFonts();
        refreshCards();
    }
    Connections {
        target: MobileTheme
        function onStateChanged() { page.refreshCards(); }
    }
    Process {
        id: fontList
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-prefs", "fonts"]
        stdout: StdioCollector {}
        onExited: {
            try {
                const result = JSON.parse(stdout.text);
                page.fonts = result.fonts || [];
            } catch (e) { page.fonts = []; }
        }
    }
    Process {
        id: fontSet
        stdinEnabled: true
        property string payload: ""
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-prefs", "set"]
        stdout: StdioCollector {}
        onStarted: { write(fontSet.payload); fontSet.payload = ""; stdinEnabled = false; }
        onExited: {
            stdinEnabled = true;
            MobileTheme.request(["sync"]);
        }
    }
    ImagePreloader { urls: page.preloadUrls }
    Flickable {
        id: list
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: body.height
        Column {
            id: body
            width: list.width
            spacing: 18
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: MobileTheme.error || MobileTheme.wallpaperError || "Omarchy themes · " + (MobileTheme.state.name || "").replace(/-/g, " ")
                color: MobileTheme.secondary
                font.family: MobileTheme.fontFamily
                font.pixelSize: 15
            }
            Rectangle {
                width: parent.width
                height: 170
                radius: 18
                clip: true
                color: MobileTheme.surface
                Image {
                    anchors.fill: parent
                    source: MobileTheme.state.wallpaper ? MobileTheme.state.wallpaper.url : ""
                    sourceSize: Qt.size(864, 340)
                    asynchronous: true
                    retainWhileLoading: true
                    autoTransform: true
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: !MobileTheme.state.wallpaper || !MobileTheme.state.wallpaper.url
                    text: "Theme background color"
                    color: MobileTheme.foreground
                    font.family: MobileTheme.fontFamily
                }
                TapHandler { onTapped: page.openPicker("wallpaper") }
            }
            SettingsRow {
                width: parent.width
                label: "Theme"
                value: (MobileTheme.state.name || "").replace(/-/g, " ")
                onClicked: page.openPicker("theme")
            }
            SettingsRow {
                width: parent.width
                label: "Wallpaper"
                value: MobileTheme.state.wallpaper && MobileTheme.state.wallpaper.count
                       ? MobileTheme.state.wallpaper.index + " of " + MobileTheme.state.wallpaper.count
                       : "None"
                enabled: !!(MobileTheme.state.wallpaper && MobileTheme.state.wallpaper.count)
                onClicked: page.openPicker("wallpaper")
            }
            SettingsRow {
                width: parent.width
                label: "Font"
                value: MobileTheme.fontFamily
                onClicked: page.openPicker("font")
            }
            SettingsRow {
                width: parent.width
                label: "Install theme"
                value: "Catalog"
                onClicked: page.openPicker("install")
            }
        }
    }
    MenuOverlay {
        open: page.pickerShown
        scrim: Qt.rgba(MobileTheme.background.r, MobileTheme.background.g, MobileTheme.background.b, 0.88)
        onDismissed: Qt.callLater(() => page.closePicker())
        onClosed: if (!page.pickerShown) page.activePicker = ""
        Column {
            anchors.centerIn: parent
            width: parent.width - 24
            visible: page.activePicker !== "install"
            spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: ({theme: "Theme", wallpaper: "Wallpaper", font: "Font"})[page.activePicker] || ""
                color: MobileTheme.accent
                font.family: MobileTheme.fontFamily
                font.pixelSize: 12
                font.letterSpacing: 2.2
                font.bold: true
            }
            Item {
                visible: page.activePicker === "theme" || page.activePicker === "wallpaper"
                width: parent.width
                height: visible ? 260 : 0
                CoverFlowPicker {
                    id: themeFlow
                    anchors.fill: parent
                    opacity: page.activePicker === "theme" ? 1 : 0
                    enabled: page.activePicker === "theme"
                    items: page.themeCards
                    motionDuration: 200
                    accent: MobileTheme.accent
                    surface: MobileTheme.surface
                    foreground: MobileTheme.foreground
                    dim: MobileTheme.background
                    fontFamily: MobileTheme.fontFamily
                    onChosen: (id) => {
                        MobileTheme.select(id);
                        Qt.callLater(() => page.closePicker());
                    }
                    TapHandler {}
                }
                CoverFlowPicker {
                    id: wallpaperFlow
                    anchors.fill: parent
                    opacity: page.activePicker === "wallpaper" ? 1 : 0
                    enabled: page.activePicker === "wallpaper"
                    items: page.wallpaperCards
                    motionDuration: 200
                    accent: MobileTheme.accent
                    surface: MobileTheme.surface
                    foreground: MobileTheme.foreground
                    dim: MobileTheme.background
                    fontFamily: MobileTheme.fontFamily
                    onChosen: (id) => {
                        MobileTheme.selectWallpaper(id);
                        Qt.callLater(() => page.closePicker());
                    }
                    TapHandler {}
                }
            }
            ListView {
                id: fontListView
                visible: page.activePicker === "font"
                width: parent.width
                height: visible ? Math.min(page.height * 0.62, Math.max(page.fonts.length, 1) * 74) : 0
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds
                model: page.fonts
                delegate: Rectangle {
                    required property string modelData
                    width: fontListView.width
                    height: 64
                    radius: 16
                    color: MobileTheme.fontFamily === modelData ? MobileTheme.selection : MobileTheme.surface
                    border.width: MobileTheme.fontFamily === modelData ? 1 : 0
                    border.color: MobileTheme.accent
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        text: modelData
                        color: MobileTheme.foreground
                        font.family: modelData
                        font.pixelSize: 18
                    }
                    Text {
                        visible: MobileTheme.fontFamily === modelData
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        text: "Current"
                        color: MobileTheme.accent
                        font.family: MobileTheme.fontFamily
                        font.pixelSize: 13
                    }
                    TapHandler {
                        onTapped: {
                            fontSet.payload = JSON.stringify({fontFamily: modelData}) + "\n";
                            fontSet.running = true;
                            Qt.callLater(() => page.closePicker());
                        }
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.activePicker === "font"
                    ? "Tap a font to apply"
                    : "Swipe to browse · tap the center to apply"
                color: MobileTheme.secondary
                font.family: MobileTheme.fontFamily
                font.pixelSize: 13
            }
        }
        ThemeInstaller {
            id: themeInstall
            anchors.fill: parent
            anchors.margins: 16
            visible: page.activePicker === "install"
            onInstalled: {
                page.closePicker();
                MobileTheme.request(["sync"]);
            }
            onKeyboardRequested: wanted => page.installerKeyboard = wanted
        }
    }
}
