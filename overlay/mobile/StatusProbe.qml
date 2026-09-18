import QtQuick
import Quickshell.Io

// Read cached status on system events, retaining polling if a monitor fails.
Item {
    id: probe
    property var sampleCommand: []
    property var eventCommand: []
    property int pollInterval: 30000
    property var state: ({ available: false })
    property bool pending: false

    function refresh() {
        if (sample.running) pending = true;
        else sample.running = true;
    }
    Process {
        id: sample
        command: probe.sampleCommand
        running: true
        stdout: StdioCollector {}
        onExited: (code, status) => {
            try { probe.state = code === 0 ? JSON.parse(stdout.text) : { available: false }; }
            catch (e) { probe.state = { available: false }; }
            if (probe.pending) {
                probe.pending = false;
                debounce.restart();
            }
        }
    }
    Process {
        id: events
        command: probe.eventCommand
        running: true
        stdout: SplitParser {
            onRead: data => { if (data.trim().length) debounce.restart(); }
        }
        onExited: retry.start()
    }
    Timer { id: debounce; interval: 150; onTriggered: probe.refresh() }
    Timer { id: retry; interval: 10000; onTriggered: events.running = true }
    Timer {
        interval: probe.pollInterval; running: true; repeat: true
        onTriggered: probe.refresh()
    }
}
