import QtQuick
import QtTest
import "."

TestCase {
    id: test
    name: "EdgeAndBrowse"
    when: windowShown
    visible: true
    width: 480; height: 800
    property int holds: 0
    property int holdFinishes: 0
    property int taps: 0
    property int swipes: 0
    ListView {
        id: cards; width: 480; height: 600
        orientation: ListView.Horizontal; model: 3; spacing: 14
        snapMode: ListView.SnapOneItem
        delegate: Item {
            width: 420; height: 600
            PreviewGestures {
                anchors.fill: parent
                onOpened: test.taps++
                onHeld: { test.holds++; cards.interactive = false; }
                onHoldFinished: { test.holdFinishes++; cards.interactive = true; }
                onSwipeFinished: test.swipes++
            }
        }
    }
    EdgeGestures { id: edge; y: 776; width: 480; height: 24 }
    SignalSpy { id: started; target: edge; signalName: "drawerStarted" }
    SignalSpy { id: moved; target: edge; signalName: "drawerMoved" }
    SignalSpy { id: released; target: edge; signalName: "drawerReleased" }
    SignalSpy { id: action; target: edge; signalName: "invoked" }
    function init() {
        started.clear(); moved.clear(); released.clear(); action.clear();
        holds = 0; holdFinishes = 0; taps = 0; swipes = 0;
        cards.cancelFlick(); cards.positionViewAtBeginning(); wait(50);
    }
    function test_edge_data() {
        return [{tag: "left", x: 70, page: "apps"}, {tag: "center", x: 240, page: "spaces"}, {tag: "right", x: 410, page: "keyboard"}];
    }
    function test_edge(data) {
        const touch = touchEvent(edge);
        touch.press(0, edge, data.x, 12).commit(); wait(30);
        touch.move(0, edge, data.x, -25).commit(); wait(30);
        touch.move(0, edge, data.x, -110).commit(); wait(30);
        touch.move(0, edge, data.x, -240).commit(); wait(30);
        touch.release(0, edge, data.x, -240).commit(); wait(30);
        if (data.page === "keyboard") {
            compare(action.count, 1); compare(action.signalArguments[0][0], "keyboard"); compare(started.count, 0);
        } else {
            compare(started.count, 1); compare(started.signalArguments[0][0], data.page);
            verify(moved.count > 0); compare(released.count, 1); compare(action.count, 0);
        }
    }
    function test_bottom_right_tap_does_not_hide() {
        mouseClick(edge, 410, 12); compare(action.count, 0);
    }
    function test_horizontal_browse_not_close() {
        const touch = touchEvent(cards);
        touch.press(0, cards, 350, 300).commit(); wait(30);
        touch.move(0, cards, 300, 300).commit(); wait(30);
        touch.move(0, cards, 200, 295).commit(); wait(30);
        touch.move(0, cards, 80, 295).commit(); wait(30);
        touch.release(0, cards, 80, 295).commit(); wait(300);
        console.log("browse", cards.contentX, cards.contentWidth, cards.interactive, holds, holdFinishes, taps, swipes);
        verify(cards.contentX > 100); compare(swipes, 0); compare(taps, 0); compare(holds, 0);
    }
    function test_hold_survives_disabling_browse() {
        const touch = touchEvent(cards);
        touch.press(0, cards, 200, 300).commit(); wait(520);
        compare(holds, 1);
        touch.move(0, cards, 220, 50).commit(); wait(30);
        touch.release(0, cards, 220, 50).commit(); wait(30);
        compare(holdFinishes, 1); compare(swipes, 0); compare(taps, 0);
    }
}
