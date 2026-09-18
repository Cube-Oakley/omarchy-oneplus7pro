import QtQuick
import QtTest
import "."
TestCase {
    id: test; name: "DrawerPull"; when: windowShown; visible: true
    width: 480; height: 900
    property int opens: 0
    property bool holding: false
    property int swipeCloses: 0
    property real offset: 0
    Item {
        id: sheet; width: 480; height: 800; y: test.offset
        Flickable {
            id: apps; enabled: !pull.tracking; anchors.fill: parent; contentHeight: 1600; boundsBehavior: Flickable.StopAtBounds
            Rectangle { width: 400; height: 1600; color: "grey"; TapHandler { onTapped: test.opens++ } }
        }
        ListView {
            id: cards; enabled: !pull.tracking; anchors.fill: parent; visible: false
            orientation: ListView.Horizontal; model: 3; spacing: 14
            delegate: Item {
                width: 420; height: 800
                PreviewGestures {
                    anchors.fill: parent
                    onOpened: test.opens++
                    onHeld: test.holding = true
                    onHoldFinished: test.holding = false
                    onSwipeFinished: close => { if (close) test.swipeCloses++; }
                }
            }
        }
        DrawerPull {
            id: pull; anchors.fill: parent
            atTop: cards.visible || apps.atYBeginning
            blocked: test.holding
            onMoved: (distance, velocity) => test.offset = distance
        }
    }
    SignalSpy { id: started; target: pull; signalName: "started" }
    SignalSpy { id: released; target: pull; signalName: "released" }
    SignalSpy { id: canceled; target: pull; signalName: "canceled" }
    function init() {
        pull.enabled = true; pull.directionSign = 1;
        pull.atTop = Qt.binding(() => cards.visible || apps.atYBeginning); canceled.clear();
        pull.headerBottom = 0; offset = 0; opens = 0; holding = false; swipeCloses = 0;
        apps.anchors.topMargin = 0; apps.cancelFlick(); apps.contentY = 0; apps.visible = true; cards.visible = false;
        cards.cancelFlick(); cards.positionViewAtBeginning();
        started.clear(); released.clear(); wait(40);
    }
    function drag(x, from, to) {
        const t = touchEvent(sheet);
        t.press(0, test, x, from).commit(); wait(25);
        for (let n = 1; n <= 6; ++n) { t.move(0, test, x, from + (to-from)*n/6).commit(); wait(25); }
        t.release(0, test, x, to).commit(); wait(30);
    }
    function test_cancel_during_pull_does_not_release() {
        const t = touchEvent(sheet);
        t.press(0, test, 200, 300).commit(); wait(25);
        t.move(0, test, 200, 340).commit(); wait(25);
        t.move(0, test, 200, 400).commit(); wait(25);
        compare(started.count, 1);
        pull.enabled = false; wait(30);
        t.release(0, test, 200, 400).commit(); wait(30);
        compare(canceled.count, 1); compare(released.count, 0); verify(!pull.tracking);
    }
    function test_apps_top_down_closes_and_tracks() {
        drag(200, 300, 500);
        compare(started.count, 1); compare(released.count, 1); verify(offset > 150); compare(opens, 0);
    }
    function test_apps_scrolled_down_scrolls_only() {
        apps.contentY = 400;
        drag(200, 300, 500);
        compare(started.count, 0); verify(apps.contentY < 400); compare(offset, 0); compare(opens, 0);
    }
    function test_scroll_to_top_does_not_take_over_mid_touch() {
        apps.contentY = 90;
        drag(200, 300, 650);
        compare(started.count, 0); compare(apps.contentY, 0);
    }
    function test_header_can_close_while_scrolled() {
        apps.anchors.topMargin = 120; apps.contentY = 400; pull.headerBottom = 100;
        drag(200, 50, 300);
        compare(started.count, 1); compare(released.count, 1);
        pull.headerBottom = 0;
    }
    function test_shade_up_at_bottom_closes() {
        pull.directionSign = -1;
        pull.atTop = Qt.binding(() => apps.atYEnd);
        apps.contentY = 800; wait(30);
        drag(200, 600, 360);
        compare(started.count, 1); compare(released.count, 1);
        verify(offset < -150); compare(opens, 0);
    }
    function test_shade_up_with_more_notifications_scrolls() {
        pull.directionSign = -1;
        pull.atTop = Qt.binding(() => apps.atYEnd);
        apps.contentY = 300;
        drag(200, 600, 360);
        compare(started.count, 0); verify(apps.contentY > 300); compare(offset, 0);
    }
    function test_shade_down_does_not_close() {
        pull.directionSign = -1; pull.atTop = true;
        apps.contentY = 800;
        drag(200, 300, 540);
        compare(started.count, 0); compare(offset, 0);
    }
    function test_apps_up_scrolls_only() {
        drag(200, 500, 300);
        compare(started.count, 0); verify(apps.contentY > 0); compare(opens, 0);
    }
    function test_apps_tap_opens() {
        const t = touchEvent(sheet); t.press(0, sheet, 200, 300).commit(); wait(20); t.release(0, sheet, 200, 300).commit(); wait(20);
        compare(opens, 1); compare(started.count, 0);
    }
    function test_preview_down_closes_drawer() {
        apps.visible = false; cards.visible = true;
        drag(200, 300, 500);
        compare(started.count, 1); compare(released.count, 1); compare(opens, 0); compare(swipeCloses, 0);
    }
    function test_preview_up_closes_app() {
        apps.visible = false; cards.visible = true;
        drag(200, 500, 250);
        compare(started.count, 0); compare(swipeCloses, 1); compare(opens, 0);
    }
    function test_preview_hold_down_keeps_arranging() {
        apps.visible = false; cards.visible = true;
        const t = touchEvent(sheet); t.press(0, test, 200, 300).commit(); wait(520);
        verify(holding); t.move(0, test, 200, 500).commit(); wait(30);
        compare(started.count, 0); verify(holding);
        t.release(0, test, 200, 500).commit(); wait(30); verify(!holding); compare(opens, 0);
    }
    function test_preview_sideways_browses() {
        apps.visible = false; cards.visible = true;
        const t = touchEvent(sheet); t.press(0, test, 350, 300).commit(); wait(30);
        t.move(0, test, 300, 300).commit(); wait(30); t.move(0, test, 150, 300).commit(); wait(30);
        t.move(0, test, 60, 300).commit(); wait(30); t.release(0, test, 60, 300).commit(); wait(100);
        compare(started.count, 0); verify(cards.contentX > 100); compare(opens, 0);
    }
}
