import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root
    property string page: ""
    property string startupError: ""
    property string keyboardError: ""
    property var keyboardQueue: []
    property var keyboardLayer: null
    property var apps: DesktopEntries.applications.values.filter(app => !app.noDisplay && app.command.length > 0)
    readonly property int workspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    function windowAddress(window) {
        if (!window) return "";
        const address = String(window.address).replace(/^0x/, "");
        return /^[0-9a-fA-F]+$/.test(address) ? "0x" + address : "";
    }
    function windowAction(window, action, extra) {
        const address = windowAddress(window);
        if (!address) return;
        const selector = 'window = "address:' + address + '"';
        dispatch(action + '({' + selector + (extra ? ', ' + extra : '') + '})');
    }
    function focusWindow(window) {
        const address = windowAddress(window);
        if (!address || !window.workspace || focusRequest.running) return;
        focusRequest.command = ["hyprctl", "--batch",
            "dispatch hl.dsp.focus({workspace=" + window.workspace.id + "}); " +
            'dispatch hl.dsp.focus({window="address:' + address + '"})'];
        console.log("MOBILE_FOCUS " + address + " workspace=" + window.workspace.id);
        focusRequest.running = true;
    }
    Process {
        id: focusRequest
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (code === 0 && stdout.text.trim().split(/\s+/).every(word => word === "ok")) {
                root.startupError = "";
                root.closeDrawer();
            } else {
                root.startupError = "Could not focus that window";
                console.warn("MOBILE_FOCUS_FAILED " + stdout.text + stderr.text);
            }
        }
    }

    function dispatch(action) {
        Quickshell.execDetached(["hyprctl", "dispatch", action]);
    }
    function keyboard(action) {
        keyboardQueue = keyboardQueue.concat([action]);
        runKeyboardRequest();
    }
    function runKeyboardRequest() {
        if (keyboardRequest.running || keyboardQueue.length === 0) return;
        const action = keyboardQueue[0];
        keyboardQueue = keyboardQueue.slice(1);
        keyboardRequest.command = [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-keyboard", action];
        keyboardRequest.running = true;
    }
    Process {
        id: keyboardRequest
        stderr: StdioCollector {}
        onExited: (code, status) => {
            root.keyboardError = code === 0 ? "" : "Keyboard failed to start";
            if (code !== 0) console.warn("MOBILE_KEYBOARD_FAILED exit=" + code + " " + stderr.text.trim());
            Qt.callLater(root.runKeyboardRequest);
        }
    }
    DrawerMotion {
        id: motion
        travel: drawer.height
        onClosed: root.page = ""
    }
    function closeDrawer() { motion.animateTo(0); }
    function beginDrawer(name) {
        shade.close();
        if (page !== name) { motion.begin(); motion.progress = 0; page = name; }
        keyboard("hide"); motion.begin();
    }
    function edgeAction(action) {
        if (action === "keyboard") { closeDrawer(); keyboard("show"); }
        else showPage(action);
        console.log("MOBILE_EDGE " + action);
    }
    function showPage(name) {
        shade.close();
        if (page === name && motion.progress > 0) closeDrawer();
        else { page = name; keyboard("hide"); motion.animateTo(1); }
    }
    onPageChanged: if (page === "spaces") overview.selectedWorkspace = workspace
    function launch(app) {
        closeDrawer();
        const command = app.runInTerminal ? ["kitty", "--"].concat(app.command) : app.command;
        Quickshell.execDetached({ command: command, workingDirectory: app.workingDirectory || Quickshell.env("HOME") });
        console.log("MOBILE_LAUNCH " + app.id);
    }
    function terminal() {
        closeDrawer();
        Quickshell.execDetached(["kitty"]);
        keyboard("show");
    }
    function selectWorkspace(number) {
        dispatch("hl.dsp.focus({workspace = " + number + "})");
        closeDrawer();
        console.log("MOBILE_WORKSPACE " + number);
    }
    function openSettings(panel) {
        closeDrawer();
        keyboard("hide");
        const page = panel || "home";
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-settings", page]);
        console.log("MOBILE_SETTINGS " + page);
    }

    Process {
        id: setup
        command: [Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-session"]
        running: true
        stderr: StdioCollector { onStreamFinished: if (this.text.trim()) console.warn(this.text) }
        onExited: (code, status) => {
            if (code === 0) root.keyboard("start");
            else root.startupError = "Display setup needs attention";
        }
    }
    IpcHandler {
        target: "mobile"
        function apps(): void { root.showPage("apps"); }
        function launchApp(id: string): bool {
            const app = root.apps.find(entry => entry.id === id);
            if (!app) return false;
            root.launch(app);
            return true;
        }
        function spaces(): void { root.showPage("spaces"); }
        function themes(): void { root.openSettings("appearance"); }
        function settings(panel: string): void { root.openSettings(panel || "home"); }
        function dismiss(): void { root.closeDrawer(); shade.close(); }
        function controls(): void { shade.toggle(); }
        function controlState(): string { return JSON.stringify({open: shade.opened, detail: shade.detail, notifications: shade.notificationCount, wifi: shade.wifi.connected, networks: shade.networks.length}); }
        function detail(name: string): void { if (["wifi", "battery", "calendar", "weather", "stats", "clipboard", "speedtest"].indexOf(name) >= 0) shade.showDetail(name); }
        function terminal(): void { root.terminal(); }
        function keyboard(): void { root.keyboard("toggle"); }
        function volume(action: string): void { volumeOsd.adjust(action); }
        function crt(action: string, token: string): string {
            if (action === "cover") { crtPower.cover(token); return "covered"; }
            if (action === "off" || action === "on") { crtPower.play(action, token); return "playing"; }
            return "ignored";
        }
        function screenshotPrivacy(enabled: bool): void { shade.closeDetail(); shade.screenshotPrivacy = enabled; }
        function workspace(number: int): void { if (number > 0 && number < 100) root.selectWorkspace(number); }
        function windows(): string { return JSON.stringify(Hyprland.toplevels.values.map(w => ({address: w.address, title: w.title, workspace: w.workspace ? w.workspace.id : 0}))); }
        function focus(address: string): void {
            const window = Hyprland.toplevels.values.find(w => root.windowAddress(w) === "0x" + address.replace(/^0x/, ""));
            if (window) root.focusWindow(window);
        }
    }
    Variants {
        model: Quickshell.screens
        Wallpaper { required property var modelData; screen: modelData }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    VolumeOsd { id: volumeOsd }
    Process {
        id: clipboardWatch
        command: ["wl-paste", "--watch", Quickshell.env("HOME") + "/.local/bin/omarchy-mobile-clipboard", "ingest"]
        running: true
        onExited: clipboardWatchRetry.start()
    }
    Timer { id: clipboardWatchRetry; interval: 10000; onTriggered: clipboardWatch.running = true }
    NotificationToast {
        id: toast
        blocked: MobileStatus.dnd || shade.opened || shade.screenshotPrivacy
        onActivate: shade.open()
    }

    NotificationShade {
        id: shade
        topInset: statusBar.height
        onOpening: { root.closeDrawer(); root.keyboard("hide"); toast.dismiss(); }
        onArrived: notification => toast.offer(notification)
        onKeyboardRequested: action => root.keyboard(action)
        onVolumeRequested: action => { volumeOsd.adjust(action); MobileStatus.refresh(); }
        onSettingsRequested: panel => { shade.close(); root.openSettings(panel); }
    }
    PanelWindow {
        id: statusBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 36
        color: MobileTheme.background
        WlrLayershell.namespace: "omarchy-mobile-status"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
            Text { font.family: MobileTheme.fontFamily; text: "omarchy"; color: MobileTheme.accent; font.pixelSize: 17; font.bold: true }
            Text { font.family: MobileTheme.fontFamily; text: root.keyboardError || root.startupError || "Space " + root.workspace; color: MobileTheme.secondary; font.pixelSize: 13; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            StatsStatus { TapHandler { onTapped: shade.showDetail("stats") } }
            WifiStatus { TapHandler { onTapped: shade.showDetail("wifi") } }
            BatteryStatus { TapHandler { onTapped: shade.showDetail("battery") } }
            Text { font.family: MobileTheme.fontFamily; text: Qt.formatDateTime(clock.date, "h:mm"); color: MobileTheme.foreground; font.pixelSize: 16; TapHandler { onTapped: shade.showDetail("calendar") } }
        }
        DragHandler {
            id: topPull
            target: null; xAxis.enabled: false
            property bool tracking: false
            onActiveChanged: {
                if (active) tracking = false;
                else if (tracking) { tracking = false; shade.release(); }
            }
            onActiveTranslationChanged: {
                if (!active) return;
                if (!tracking && activeTranslation.y > 8) { tracking = true; shade.begin(); }
                if (tracking) shade.move(activeTranslation.y, centroid.velocity.y);
            }
            onCanceled: { if (tracking) { tracking = false; shade.cancel(); } }
        }
    }

    // Keep navigation above the on-screen keyboard without reserving a band.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if ((event.name === "openlayer" || event.name === "closelayer") && event.data === "wvkbd") {
                if (event.name === "openlayer") {
                    navigation.visible = false;
                    raiseNavigation.restart();
                }
                keyboardGeometryRefresh.restart();
            }
        }
    }
    Timer { id: raiseNavigation; interval: 50; onTriggered: navigation.visible = true }
    Timer {
        id: keyboardGeometryRefresh; interval: 70
        onTriggered: { if (keyboardGeometry.running) restart(); else keyboardGeometry.running = true; }
    }
    Process {
        id: keyboardGeometry
        command: ["hyprctl", "-j", "layers"]
        running: true
        stdout: StdioCollector {}
        onExited: (code, status) => {
            if (code !== 0) return;
            try {
                const monitors = JSON.parse(stdout.text);
                let found = null;
                for (const monitor of Object.values(monitors))
                    for (const level of Object.values(monitor.levels))
                        for (const layer of level)
                            if (layer.namespace === "wvkbd") found = layer;
                root.keyboardLayer = found;
            } catch (e) { console.warn("MOBILE_KEYBOARD_GEOMETRY " + e); }
        }
    }
    PanelWindow {
        id: keyboardHandle
        visible: root.keyboardLayer !== null
        anchors.bottom: true
        margins.bottom: root.keyboardLayer ? root.keyboardLayer.h : 0
        implicitWidth: 144; implicitHeight: 24
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "omarchy-mobile-keyboard-handle"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent; anchors.margins: 2; radius: 10
            color: MobileTheme.background; opacity: 0.95
            Rectangle { anchors.centerIn: parent; width: 54; height: 3; radius: 2; color: MobileTheme.foreground; opacity: 0.6 }
        }
        KeyboardDismiss {
            anchors.fill: parent
            onDismissed: {
                if (shade.keyboardOwned) shade.releaseKeyboard();
                else root.keyboard("hide");
            }
        }
    }
    PanelWindow {
        id: navigation
        anchors { bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitHeight: 24
        color: "transparent"
        // Keep drawer swipes but let the keyboard's Enter corner receive taps.
        mask: Region { width: root.keyboardLayer ? navigation.width * 2 / 3 : navigation.width; height: navigation.height }
        WlrLayershell.namespace: "omarchy-mobile-navigation"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        EdgeGestures {
            handleColor: MobileTheme.foreground
            anchors.fill: parent
            onInvoked: action => root.edgeAction(action)
            onDrawerStarted: name => root.beginDrawer(name)
            onDrawerMoved: (distance, velocity) => motion.update(distance, velocity)
            onDrawerReleased: motion.finish()
            onDrawerCanceled: if (motion.dragging) motion.cancel()
        }
    }

    PanelWindow {
        id: drawer
        // Keep the surface mapped: remapping can present its previous full
        // buffer before Qt paints the new finger-tracked position.
        visible: true
        mask: Region {
            width: root.page !== "" ? drawer.width : 0
            height: root.page !== "" ? drawer.height : 0
        }
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "omarchy-mobile-drawer"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // The input region is empty while closed and covers the drawer while open.
        Rectangle { anchors.fill: parent; color: "black"; opacity: motion.progress * 0.28 }
        TapHandler { onTapped: point => { if (point.position.y < sheet.y) root.closeDrawer(); } }
        Rectangle {
            id: sheet
            visible: root.page !== ""
            width: parent.width; height: parent.height
            y: (1 - motion.progress) * height
            radius: motion.progress < 0.99 ? 24 : 0
            color: MobileTheme.background
            clip: true
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 24; spacing: 24
                Item {
                    Layout.fillWidth: true; implicitHeight: 88
                    Text { font.family: MobileTheme.fontFamily; y: 0; text: root.page === "spaces" ? "YOUR SPACE" : "EXPLORE"; color: MobileTheme.accent; font.pixelSize: 11; font.letterSpacing: 2.4; font.bold: true }
                    Text { font.family: MobileTheme.fontFamily; y: 23; text: root.page === "spaces" ? "Overview" : "Applications"; color: MobileTheme.foreground; font.pixelSize: 34; font.bold: true }
                    TouchButton { anchors.right: parent.right; y: 21; implicitWidth: 48; implicitHeight: 48; radius: 24; label: "×"; textSize: 26; onClicked: root.closeDrawer() }
                }
                WorkspaceOverview {
                    id: overview
                    enabled: motion.settledOpen
                    visible: root.page === "spaces"; active: visible && motion.progress > 0.05
                    Layout.fillWidth: true; Layout.fillHeight: true
                    onEnterWorkspace: number => root.selectWorkspace(number)
                    onLaunchTerminal: root.terminal()
                    onFocusWindow: window => root.focusWindow(window)
                    onSwapWindows: (source, target) => {
                        const address = root.windowAddress(target);
                        if (address) root.windowAction(source, "hl.dsp.window.swap", 'target = "address:' + address + '"');
                    }
                    onMoveWindow: (window, number) => root.windowAction(window, "hl.dsp.window.move", "workspace = " + number + ", follow = false")
                    onMaximizeWindow: window => { root.windowAction(window, "hl.dsp.window.fullscreen", 'mode = "maximized"'); root.closeDrawer(); }
                    onCloseWindow: window => root.windowAction(window, "hl.dsp.window.close", "")
                }
                Flickable {
                    id: appList
                    enabled: motion.settledOpen
                    visible: root.page === "apps"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; contentHeight: contents.height; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: contents; width: parent.width; spacing: 22
                        RowLayout {
                            visible: root.page === "apps"; width: parent.width; spacing: 12
                            TouchButton { Layout.fillWidth: true; label: ">_  Terminal"; selected: true; onClicked: root.terminal() }
                            TouchButton { Layout.fillWidth: true; label: "Settings"; onClicked: root.openSettings("home") }
                        }
                        GridLayout {
                            width: parent.width; columns: 3; columnSpacing: 12; rowSpacing: 24
                            Repeater {
                                model: root.apps
                                Item {
                                    required property var modelData
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 116
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter; width: 70; height: 70; radius: 21; color: appTap.pressed ? MobileTheme.selection : MobileTheme.surface
                                        Image { id: appIcon; anchors.centerIn: parent; width: 40; height: 40; source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""; fillMode: Image.PreserveAspectFit }
                                        Text { font.family: MobileTheme.fontFamily; anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: modelData.name.substring(0, 1); color: MobileTheme.accent; font.pixelSize: 28; font.bold: true }
                                    }
                                    Text { font.family: MobileTheme.fontFamily; anchors { top: parent.top; topMargin: 80; left: parent.left; right: parent.right } text: modelData.name; textFormat: Text.PlainText; color: MobileTheme.foreground; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                                    TapHandler { id: appTap; onTapped: root.launch(modelData) }
                                }
                            }
                        }
                    }
                }
            }
            DrawerPull {
                anchors.fill: parent
                available: motion.progress > 0.05 && !motion.dragging
                atTop: root.page === "spaces" || appList.atYBeginning
                headerBottom: 24 + 88
                blocked: root.page === "spaces" && overview.arranging
                onStarted: motion.begin()
                onMoved: (distance, velocity) => motion.update(-Math.max(0, distance), -velocity)
                onReleased: motion.finishClose()
                onCanceled: if (motion.dragging) motion.cancel()
            }
        }
    }
    CrtPower { id: crtPower }
}
