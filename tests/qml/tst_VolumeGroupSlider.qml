import QtQuick
import QtTest

Item {
    id: root
    width: 200
    height: 400

    Component {
        id: groupComponent
        VolumeGroupSlider {
            width: 60
            height: 320
            modelData: ({id: "ring", label: "Ring", icon: "R"})
            level: ({available: true, percent: 80, muted: false})
        }
    }

    // Stands in for the volume backend, which confirms a change about 0.4 s later.
    Timer {
        id: backend
        property var group
        property real percent
        interval: 400
        onTriggered: group.level = {available: true, percent: Math.round(percent), muted: false}
    }

    TestCase {
        name: "VolumeGroupSlider"
        when: windowShown

        function handleY(slider) {
            return slider.topPadding + slider.visualPosition * (slider.availableHeight - slider.handle.height)
                + slider.handle.height / 2;
        }

        function test_touch_drag_beside_the_track_moves_the_volume() {
            const group = createTemporaryObject(groupComponent, root);
            const moves = [];
            group.volumeMoved.connect((id, percent) => moves.push([id, percent]));
            const slider = group.slider;
            tryVerify(() => slider.height > 100);
            verify(slider.width >= 48, "slider touch width is " + slider.width);
            compare(Math.round(slider.value), 80);
            // Inside the drawn handle but 16 px beside the track's centre line.
            const x = slider.width / 2 + 16, y = handleY(slider);
            const touch = touchEvent(slider);
            touch.press(0, slider, x, y).commit();
            for (let i = 1; i <= 10; ++i)
                touch.move(0, slider, x, y + i * 10).commit();
            touch.release(0, slider, x, y + 100).commit();
            verify(moves.length > 0, "no volume change was reported");
            compare(moves[moves.length - 1][0], "ring");
            verify(moves[moves.length - 1][1] < 70, "volume only reached " + moves[moves.length - 1][1]);
        }

        function test_backend_answers_do_not_pull_the_handle_mid_drag() {
            const group = createTemporaryObject(groupComponent, root);
            const slider = group.slider;
            tryVerify(() => slider.height > 100);
            const x = slider.width / 2, y = handleY(slider);
            const touch = touchEvent(slider);
            touch.press(0, slider, x, y).commit();
            for (let i = 1; i <= 8; ++i)
                touch.move(0, slider, x, y + i * 12).commit();
            verify(slider.pressed);
            const dragged = slider.value;
            group.level = {available: true, percent: 80, muted: false};
            compare(slider.value, dragged);
            touch.release(0, slider, x, y + 96).commit();
            group.level = {available: true, percent: 42, muted: false};
            compare(Math.round(slider.value), 42);
        }

        function test_release_keeps_the_new_position_until_the_backend_confirms() {
            const group = createTemporaryObject(groupComponent, root);
            group.volumeMoved.connect((id, percent) => {
                backend.group = group; backend.percent = percent; backend.restart();
            });
            const slider = group.slider;
            tryVerify(() => slider.height > 100);
            const x = slider.width / 2, y = handleY(slider);
            const touch = touchEvent(slider);
            touch.press(0, slider, x, y).commit();
            for (let i = 1; i <= 8; ++i)
                touch.move(0, slider, x, y + i * 12).commit();
            touch.release(0, slider, x, y + 96).commit();
            const released = slider.value;
            verify(released < 70, "drag only reached " + released);
            // The backend has not answered yet: the handle must stay where it was let go.
            compare(slider.value, released);
            wait(100);
            compare(slider.value, released);
            tryVerify(() => Math.round(group.level.percent) === Math.round(released), 2000);
            compare(Math.round(slider.value), Math.round(released));
            // Once confirmed, later backend changes (a key press) move it again.
            group.level = {available: true, percent: 90, muted: false};
            compare(Math.round(slider.value), 90);
        }

        function test_unconfirmed_change_falls_back_to_the_real_level() {
            const group = createTemporaryObject(groupComponent, root);
            const slider = group.slider;
            tryVerify(() => slider.height > 100);
            const x = slider.width / 2, y = handleY(slider);
            const touch = touchEvent(slider);
            touch.press(0, slider, x, y).commit();
            for (let i = 1; i <= 8; ++i)
                touch.move(0, slider, x, y + i * 12).commit();
            touch.release(0, slider, x, y + 96).commit();
            verify(slider.value < 70);
            // No answer ever arrives; the real level (80) returns after the timeout.
            tryVerify(() => Math.round(slider.value) === 80, 5000);
        }

        function test_mute_shows_zero_and_unavailable_group_is_disabled() {
            const group = createTemporaryObject(groupComponent, root);
            group.level = {available: true, percent: 60, muted: true};
            compare(group.slider.value, 0);
            group.level = {available: false, percent: 0, muted: false};
            verify(!group.slider.enabled);
        }
    }
}
