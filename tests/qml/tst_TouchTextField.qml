import QtQuick
import QtTest
import "."

TestCase {
    name: "TouchTextField"; when: windowShown; visible: true
    width: 480; height: 300
    TouchTextField {
        id: field; x: 20; y: 30; width: 400; height: 60
        onEditingRequested: { editing = true; forceActiveFocus(); }
    }
    SignalSpy { id: requested; target: field; signalName: "editingRequested" }
    function init() { field.editing = false; field.visible = true; field.text = ""; requested.clear(); }
    function test_visibility_and_focus_do_not_start_editing() {
        for (let i = 0; i < 5; i++) {
            field.visible = false; wait(10); field.visible = true;
            field.forceActiveFocus(); wait(10);
            verify(field.readOnly); compare(requested.count, 0);
        }
    }
    function test_tap_edits_and_release_prevents_reactivation() {
        touchEvent(field).press(0, field, 100, 30).commit();
        touchEvent(field).release(0, field, 100, 30).commit();
        tryCompare(requested, "count", 1);
        verify(!field.readOnly); verify(field.activeFocus);
        keyClick(Qt.Key_A); compare(field.text, "a");
        field.editing = false;
        field.forceActiveFocus(); keyClick(Qt.Key_B);
        compare(field.text, "a"); compare(requested.count, 1);
    }
}
