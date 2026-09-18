"""Exercise real Quickshell event coalescing, in-flight refresh and fallback."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mobile-status-') as directory:
    work = Path(directory)
    shutil.copy(root / 'overlay/mobile/StatusProbe.qml', work)
    (work / 'fixture.py').write_text('''import json,sys,time
from pathlib import Path
if sys.argv[1] == 'events':
    time.sleep(.05)
    for _ in range(20): print('changed', flush=True)
    time.sleep(10)
elif sys.argv[1] == 'missing':
    sys.exit(1)
else:
    p=Path(sys.argv[2])
    n=int(p.read_text())+1 if p.exists() else 1
    p.write_text(str(n))
    time.sleep(.35)
    print(json.dumps({'available':True,'count':n}))
''')
    fixture = json.dumps(str(work / 'fixture.py'))
    event_count = json.dumps(str(work / 'events.count'))
    fallback_count = json.dumps(str(work / 'fallback.count'))
    (work / 'shell.qml').write_text('''import QtQuick
import Quickshell
Scope {
    StatusProbe {
        id: eventProbe
        sampleCommand: ["python3", FIXTURE, "sample", EVENT_COUNT]
        eventCommand: ["python3", FIXTURE, "events"]
        pollInterval: 60000
    }
    StatusProbe {
        id: fallback
        sampleCommand: ["python3", FIXTURE, "sample", FALLBACK_COUNT]
        eventCommand: ["python3", FIXTURE, "missing"]
        pollInterval: 500
    }
    Timer {
        interval: 2500; running: true
        onTriggered: {
            if (eventProbe.state.count === 2 && fallback.state.count >= 3)
                console.log("STATUS_PROBE_PASS");
            else console.error("STATUS_PROBE_FAIL", JSON.stringify(eventProbe.state), JSON.stringify(fallback.state));
            Qt.quit();
        }
    }
}
'''.replace('FIXTURE', fixture).replace('EVENT_COUNT', event_count)
       .replace('FALLBACK_COUNT', fallback_count))
    runtime = work / 'runtime'
    runtime.mkdir(mode=0o700)
    result = subprocess.run(['quickshell', '-p', str(work / 'shell.qml')],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                 QT_QPA_PLATFORMTHEME='basic', XDG_RUNTIME_DIR=str(runtime)),
        capture_output=True, text=True, timeout=8)
    output = result.stdout + result.stderr
    print(output)
    assert result.returncode == 0 and 'STATUS_PROBE_PASS' in output, output
