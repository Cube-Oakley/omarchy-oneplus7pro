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
    SignalSpy { id: started; target: edge; signalName: "started" }
    SignalSpy { id: moved; target: edge; signalName: "moved" }
    SignalSpy { id: released; target: edge; signalName: "released" }
    SignalSpy { id: held; target: edge; signalName: "held" }
    function init() {
        started.clear(); moved.clear(); released.clear(); held.clear();
        holds = 0; holdFinishes = 0; taps = 0; swipes = 0;
        cards.cancelFlick(); cards.positionViewAtBeginning(); wait(50);
    }
    function test_swipe_starts_from_anywhere() {
        const touch = touchEvent(edge);
        touch.press(0, edge, 410, 12).commit(); wait(20);
        touch.move(0, edge, 410, -40).commit(); wait(20);
        touch.move(0, edge, 410, -180).commit(); wait(20);
        touch.release(0, edge, 410, -180).commit(); wait(30);
        compare(started.count, 1);
        verify(moved.count > 0);
        compare(released.count, 1);
        compare(released.signalArguments[0][2], false);
    }

    function test_pause_arms_the_switcher() {
        const touch = touchEvent(edge);
        touch.press(0, edge, 240, 12).commit(); wait(20);
        touch.move(0, edge, 240, -120).commit(); wait(40);
        compare(held.count, 0);
        touch.move(0, edge, 242, -118).commit(); wait(80);
        touch.move(0, edge, 239, -122).commit(); wait(160);
        compare(held.count, 1);
        touch.release(0, edge, 240, -120).commit(); wait(30);
        compare(released.count, 1);
        compare(released.signalArguments[0][2], true);
    }

    function test_bottom_tap_does_not_invoke_a_zone() {
        mouseClick(edge, 410, 12);
        compare(started.count, 0);
        compare(released.count, 0);
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
