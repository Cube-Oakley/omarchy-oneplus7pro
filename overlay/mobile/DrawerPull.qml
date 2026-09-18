import QtQuick

// Observe first, then claim only a downward drag that began at the list top.
// Upward and sideways gestures keep their original owner for the whole touch.
Item {
    id: pull
    property bool available: true
    property bool atTop: true
    property bool blocked: false
    property real headerBottom: 0
    property int directionSign: 1 // +1 pulls down, -1 pulls up
    property int direction: 0 // 0 pending, 1 downward, 2 owned by content
    property bool eligible: false
    property bool beganAtTop: true
    property bool tracking: false
    property bool pendingRelease: false
    property int sequence: 0
    signal started()
    signal moved(real distance, real velocity)
    signal released()
    signal canceled()
    function abort() {
        const owned = tracking || pendingRelease;
        tracking = false; pendingRelease = false; direction = 2;
        if (owned) canceled();
    }
    onEnabledChanged: if (!enabled) abort()
    onVisibleChanged: if (!visible) abort()
    onBlockedChanged: if (blocked && !tracking) direction = 2
    PointHandler {
        id: observer
        acceptedButtons: Qt.NoButton
        onActiveChanged: {
            if (active) {
                pull.direction = 0;
                pull.eligible = pull.available && !pull.blocked;
                pull.beganAtTop = pull.atTop;
            }
        }
        onPointChanged: {
            if (!active || !pull.eligible || pull.direction !== 0) return;
            // Use the press location and initial scroll state, so reaching
            // the top later in a scrolling gesture never changes ownership.
            if (!pull.beganAtTop && point.pressPosition.y >= pull.headerBottom) {
                pull.direction = 2; return;
            }
            const dy = pull.directionSign * (point.scenePosition.y - point.scenePressPosition.y);
            const dx = Math.abs(point.scenePosition.x - point.scenePressPosition.x);
            if (dy > 14 && dy > dx * 1.2) pull.direction = 1;
            else if (dy < -14 || dx > 14) pull.direction = 2;
        }
    }
    DragHandler {
        id: drag
        yAxis.enabled: pull.tracking || (pull.eligible && pull.direction === 1 && !pull.blocked)
        target: null; xAxis.enabled: false; dragThreshold: 0
        minimumPointCount: 1; maximumPointCount: 1
        onActiveChanged: {
            if (active) {
                pull.sequence++; pull.pendingRelease = false;
                pull.tracking = true; pull.started();
            } else if (pull.tracking) {
                pull.tracking = false; pull.direction = 2; pull.pendingRelease = true;
                const sequence = pull.sequence;
                // A canceled grab can deactivate first; allow canceled to
                // suppress release before asking the drawer to settle.
                Qt.callLater(() => {
                    if (pull.pendingRelease && pull.sequence === sequence) {
                        pull.pendingRelease = false; pull.released();
                    }
                });
            }
        }
        onActiveTranslationChanged: if (active) pull.moved(centroid.scenePosition.y - centroid.scenePressPosition.y, centroid.velocity.y)
        onCanceled: pull.abort()
    }
}
