#!/usr/bin/env python3
"""Census of the sensor DSP's registered sensors (docs/sensors-20260924.md).

Asks the Snapdragon Sensor Core (QMI service 400 over QRTR) which sensors
provide each data type, through its fixed SUID lookup sensor, and prints one
line per type. Read-only: lookups without update registration. Python's
standard library only. Run on the phone:
    bash scripts/phone-ssh.sh 'python3 - [--json] [type ...]' < scripts/phone-ssc-census.py
    bash scripts/phone-ssh.sh 'python3 - --stream SUID SECONDS [RATE_HZ]' < scripts/phone-ssc-census.py
The stream mode subscribes to one sensor (on-change without a rate, else at
RATE_HZ), prints each event with its floats, and disconnects.

The wire format follows the OnePlus 7T Pro port's ssc-client.py: a QMI
envelope whose TLV 0x01 carries a counted protobuf sns_client_request_msg.
"""
import json
import socket
import struct
import sys
import time

SERVICE = 400
QRTR_PORT_CTRL = 0xFFFFFFFE
QRTR_TYPE_NEW_SERVER, QRTR_TYPE_NEW_LOOKUP = 4, 10
REQ, IND_SMALL, IND_LARGE = 0x20, 0x21, 0x22
SUID_LOOKUP = (0xABABABABABABABAB, 0xABABABABABABABAB)
MSG_SUID_REQ, EVENT_SUID = 512, 768
MSG_STD_CONFIG, MSG_ON_CHANGE_CONFIG = 513, 514
PROCESSOR_APSS = 1

TYPES = [
    # framework
    "suid", "registry", "timer", "interrupt", "async_com_port", "resampler",
    "diag_sensor", "sensor_logger", "data_acquisition_engine", "remote_proc_state",
    # physical
    "accel", "gyro", "mag", "pressure", "ambient_light", "proximity",
    "humidity", "ambient_temperature", "sensor_temperature", "rgb",
    "ultra_violet", "hall", "sar", "sars", "ct_c", "wise_light",
    # derived and algorithms
    "gravity", "linear_acceleration", "rotv", "game_rv", "geomag_rv",
    "gyro_cal", "mag_cal", "motion_detect", "stationary_detect", "amd", "rmd",
    "device_orient", "tilt", "sig_motion", "pedometer", "step_detect",
    "basic_gestures", "facing", "multishake", "bring_to_ear", "ccd_walk",
    "ccd_ttw", "cmc", "fmv", "psmd", "dpc", "distance_bound", "tilt_to_wake",
    "aont", "oem1",
    # OnePlus, from persist's sensors_list.txt
    "pick_up_motion", "pedometer_minute", "oplus_activity_recognition",
    "lux_aod", "free_fall", "amd_oplus", "camera_protect",
]


def varint(n):
    out = bytearray()
    while True:
        b, n = n & 0x7F, n >> 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def pb(num, wire, payload):
    return varint(num << 3 | wire) + payload


def pb_bytes(num, raw):
    return pb(num, 2, varint(len(raw)) + raw)


def read_varint(raw, i):
    shift = res = 0
    while i < len(raw):
        b = raw[i]
        i += 1
        res |= (b & 0x7F) << shift
        if not b & 0x80:
            break
        shift += 7
    return res, i


def parse(raw):
    """Protobuf message to {field: [values]}; length-delimited values stay bytes."""
    out, i = {}, 0
    while i < len(raw):
        key, i = read_varint(raw, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, i = read_varint(raw, i)
        elif wire == 1:
            val, i = struct.unpack_from("<Q", raw, i)[0], i + 8
        elif wire == 2:
            ln, i = read_varint(raw, i)
            val, i = raw[i:i + ln], i + ln
        elif wire == 5:
            val, i = struct.unpack_from("<I", raw, i)[0], i + 4
        else:
            break
        out.setdefault(num, []).append(val)
    return out


def find_service(sock):
    """(node, port) of the sensor core, from the QRTR name service."""
    node = sock.getsockname()[0]
    sock.sendto(struct.pack("<5I", QRTR_TYPE_NEW_LOOKUP, SERVICE, 0, 0, 0), (node, QRTR_PORT_CTRL))
    end = time.time() + 5
    while time.time() < end:
        data, _ = sock.recvfrom(4096)
        if len(data) < 20:
            continue
        cmd, service, instance, s_node, s_port = struct.unpack_from("<5I", data)
        if cmd != QRTR_TYPE_NEW_SERVER:
            continue
        if not service:  # end of the listing
            break
        if service == SERVICE:
            return s_node, s_port
    sys.exit("service 400 (sensor core) is not registered")


def request(txn, data_type):
    suid_req = pb_bytes(1, data_type.encode()) + pb(2, 0, varint(0)) + pb(3, 0, varint(0))
    return client_request(txn, SUID_LOOKUP, MSG_SUID_REQ, suid_req)


def client_request(txn, suid, msg_id, payload):
    """sns_client_request_msg {suid, msg_id, susp_config {APSS, wakeup}, request {payload}}"""
    body = (pb_bytes(1, pb(1, 1, struct.pack("<Q", suid[0])) + pb(2, 1, struct.pack("<Q", suid[1])))
            + pb(2, 5, struct.pack("<I", msg_id))
            + pb_bytes(3, pb(1, 0, varint(PROCESSOR_APSS)) + pb(2, 0, varint(0)))
            + pb_bytes(4, pb_bytes(2, payload)))
    value = struct.pack("<H", len(body)) + body
    tlvs = b"\x10\x01\x00\x01" + b"\x01" + struct.pack("<H", len(value)) + value
    return struct.pack("<BHHH", 0, txn, REQ, len(tlvs)) + tlvs


def tlvs_of(data):
    _type, txn, msg_id, length = struct.unpack_from("<BHHH", data)
    body, out, i = data[7:7 + length], {}, 0
    while i + 3 <= len(body):
        t, ln = body[i], struct.unpack_from("<H", body, i + 1)[0]
        out[t] = body[i + 3:i + 3 + ln]
        i += 3 + ln
    return txn, msg_id, out


def suid_events(tlvs):
    """(data_type, [suid hex]) for each SUID event in an indication."""
    v = tlvs.get(0x02, b"")
    if len(v) < 2:
        return
    msg = parse(v[2:2 + struct.unpack_from("<H", v)[0]])
    for event in msg.get(2, []):
        ev = parse(event) if isinstance(event, bytes) else {}
        if ev.get(1, [None])[0] != EVENT_SUID:
            continue
        for payload in ev.get(3, []):
            p = parse(payload)
            name = p.get(1, [b""])[0]
            suids = []
            for raw in p.get(2, []):
                s = parse(raw)
                if 1 in s and 2 in s:
                    suids.append("%016x%016x" % (s[2][0], s[1][0]))
            yield name.decode(errors="replace") if isinstance(name, bytes) else str(name), suids


def stream(sock, node, port, suid_hex, seconds, rate):
    """Subscribe to one sensor and print its events: msg id, floats, other fields."""
    suid = (int(suid_hex[16:], 16), int(suid_hex[:16], 16))
    if rate:  # sns_std_sensor_config {float sample_rate = 1}
        msg_id, payload = MSG_STD_CONFIG, pb(1, 5, struct.pack("<f", rate))
    else:
        msg_id, payload = MSG_ON_CHANGE_CONFIG, b""
    sock.sendto(client_request(1, suid, msg_id, payload), (node, port))
    end, count = time.time() + seconds, 0
    while time.time() < end:
        try:
            data, _ = sock.recvfrom(65536)
        except socket.timeout:
            continue
        if len(data) < 7:
            continue
        _txn, qmi_id, tlvs = tlvs_of(data)
        if qmi_id == REQ and 0x02 in tlvs and len(tlvs[0x02]) >= 4:
            print("request result %d error %d" % struct.unpack_from("<HH", tlvs[0x02]), flush=True)
            continue
        v = tlvs.get(0x02, b"")
        if qmi_id not in (IND_SMALL, IND_LARGE) or len(v) < 2:
            continue
        for event in parse(v[2:2 + struct.unpack_from("<H", v)[0]]).get(2, []):
            ev = parse(event) if isinstance(event, bytes) else {}
            eid, stamp = ev.get(1, [None])[0], ev.get(2, [0])[0]
            fields = parse(ev.get(3, [b""])[0])
            floats = []
            for raw in fields.get(1, []):  # repeated float, packed or not
                if isinstance(raw, bytes):
                    floats += struct.unpack("<%df" % (len(raw) // 4), raw[:len(raw) // 4 * 4])
                elif isinstance(raw, int) and raw < 1 << 32:
                    floats.append(struct.unpack("<f", struct.pack("<I", raw))[0])
            other = {k: [x if not isinstance(x, bytes) else x.hex() for x in vals]
                     for k, vals in fields.items() if k != 1}
            print("t=%d event %s floats=%s %s" % (stamp, eid, ["%.3f" % f for f in floats], other or ""),
                  flush=True)
            count += 1
    # Closing the socket ends the subscription on the DSP's side.
    print("%d events in %d s" % (count, seconds))


def main():
    if "--stream" in sys.argv:
        i = sys.argv.index("--stream")
        suid_hex, seconds = sys.argv[i + 1], int(sys.argv[i + 2])
        rate = float(sys.argv[i + 3]) if len(sys.argv) > i + 3 else 0.0
        sock = socket.socket(socket.AF_QIPCRTR, socket.SOCK_DGRAM)
        sock.settimeout(1.0)
        node, port = find_service(sock)
        stream(sock, node, port, suid_hex, seconds, rate)
        return
    args = [a for a in sys.argv[1:] if a != "--json"]
    types = args or TYPES
    sock = socket.socket(socket.AF_QIPCRTR, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    # The socket reports the local node before binding and autobinds on its
    # first send, the name service lookup.
    try:
        node, port = find_service(sock)
    except socket.timeout:
        sys.exit("no answer from the QRTR name service")
    results = {}
    for txn, data_type in enumerate(types, 1):
        sock.sendto(request(txn, data_type), (node, port))
        found, result = None, None
        end = time.time() + 5
        while time.time() < end and found is None:
            try:
                data, _ = sock.recvfrom(65536)
            except socket.timeout:
                continue
            if len(data) < 7:
                continue
            _txn, msg_id, tlvs = tlvs_of(data)
            if msg_id == REQ and 0x02 in tlvs and len(tlvs[0x02]) >= 4:
                result = struct.unpack_from("<HH", tlvs[0x02])
                if result[0]:
                    found = []
            elif msg_id in (IND_SMALL, IND_LARGE):
                for name, suids in suid_events(tlvs):
                    if name == data_type:
                        found = suids
        results[data_type] = found
        if "--json" not in sys.argv:
            if found is None:
                state = "no answer"
            elif result and result[0]:
                state = "request failed (error %d)" % result[1]
            else:
                state = ", ".join(found) if found else "-"
            print("%-28s %s" % (data_type, state), flush=True)
    if "--json" in sys.argv:
        print(json.dumps({"node": node, "port": port, "types": results}, indent=1))
    else:
        present = [t for t, s in results.items() if s]
        print("\n%d of %d types have a sensor: %s" % (len(present), len(results), " ".join(present)))


if __name__ == "__main__":
    main()
