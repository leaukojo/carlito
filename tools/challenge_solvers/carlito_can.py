"""carlito_can.py - drive the Carlito car over CAN from Python, to test the challenges.

Every solver script runs the same way:

    python car_001_start_up.py                    sloppyCAN's script relay on 127.0.0.1:29541
    python car_001_start_up.py --relay HOST:PORT  a relay somewhere else
    python car_001_start_up.py --no-open          don't open the challenge: start it yourself
    python car_001_start_up.py --can slcan COM5   real hardware through python-can
                                                  (--bitrate N, default 500000)

A solver looks like this:

    car = connect()                  # reads the command line above
    car.wait_start("car_start_up")   # asks Carlito to open the challenge, then waits for it
    car.key = IGNITION
    car.gear = D
    car.accel = 40
    while car.tick():                # every 50 ms, until the challenge ends
        car.steer_to(50, 0)
    car.finish()                     # prints the result, then parks the car

What the car is told (sent every 20 ms, or 10 ms on hardware, as RAMN frames):
    key      LOCK / ON / IGNITION                 0x1B8
    gear     P / R / N / D, or 1-6 in a manual    0x077
    accel    0..100 %                             0x039
    brake    0..100 %                             0x024
    steer    -100 (full left) .. 100 (full right) 0x062
    handbrake  True / False                       0x1D3
    lights   OFF / LOW / HIGH                     0x1BB (with the two turn lamps)
    turn_left, turn_right  True / False           0x1BB

What the car reports (the telemetry frames sloppyCAN puts on the bus):
    kmh, speed (m/s, negative in reverse), rpm, gear_now     0x520, 0x521
    acc_lat (m/s^2)                                          0x522
    heading (compass degrees: 0 north, 90 east)              0x524
    x, z (world metres, from GPS: centimetre precision)      0x525
    odo (metres)                                             0x526
    status (bitfield)                                        0x527

Challenge state comes from sloppyCAN's "#challenge start / pass / fail / exit" info lines, and
wait_start sends "#challenge open <id>", which makes sloppyCAN start the challenge in
Carlito (opening its window if shut). Real hardware has neither: there you start the challenge, press Enter once it has
started, and Ctrl+C when you are done.
"""

import argparse
import atexit
import math
import socket
import sys
import threading
import time

# Gear byte (0x077), key (0x1B8) and headlight values.
P, R, N, D = 0xFE, 0xFF, 0, 1
LOCK, ON, IGNITION = 1, 2, 3
OFF, LOW, HIGH = 1, 3, 4

# How cruise() holds a speed.
CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG = "PI", "bang-bang"
# How steer_to() and follow() steer.
STEER_PROPORTIONAL, STEER_BANGBANG = "proportional", "bang-bang"

# The game's GPS: world X/Z around a Paris origin (VehicleTelemetry.gps_lat / gps_lon).
GPS_LAT0, GPS_LON0, M_PER_DEG = 48.8566, 2.3522, 111320.0

# UDS RoutineControl 0x0200 ("Request Silence", RAMN firmware ramn_uds.c): start (31 01 02 00)
# makes a RAMN ECU stop sending its own periodic frames, so they don't fight ours; stop
# (31 02 02 00) brings them back. Sent to each ECU on connect and at exit. sloppyCAN's demo
# plays the same routine for its simulated RAMN traffic.
RAMN_SILENCE = [0x04, 0x31, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00]
RAMN_RESUME = [0x04, 0x31, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00]
RAMN_ECUS = (0x7E1, 0x7E2, 0x7E3)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def arc(cx, cz, radius, from_deg, to_deg, step=10):
    """Points (x, z) on a circle round (cx, cz), for follow(). The angles are compass bearings
    seen from the centre (0: the point north of it, 90: east of it). Going from a smaller to a
    larger bearing runs clockwise (a right turn); larger to smaller runs anticlockwise (left)."""
    n = max(1, round(abs(to_deg - from_deg) / step))
    points = []
    for i in range(n + 1):
        b = math.radians(from_deg + (to_deg - from_deg) * i / n)
        points.append((cx + radius * math.sin(b), cz - radius * math.cos(b)))
    return points


def connect():
    """Open the link named on the command line and start talking to the car."""
    ap = argparse.ArgumentParser(description="Solve a Carlito challenge over CAN.")
    ap.add_argument("--relay", default="127.0.0.1:29541", metavar="HOST:PORT",
                    help="sloppyCAN script relay (default 127.0.0.1:29541)")
    ap.add_argument("--can", nargs=2, metavar=("INTERFACE", "CHANNEL"),
                    help="real hardware via python-can, e.g. --can slcan COM5")
    ap.add_argument("--bitrate", type=int, default=500000)
    ap.add_argument("--no-open", action="store_true",
                    help="don't ask Carlito to open the challenge: start it yourself in the game")
    args = ap.parse_args()
    sys.excepthook = _quiet_ctrl_c
    if args.can:
        return Car(_CanLink(args.can[0], args.can[1], args.bitrate), period=0.01, open_it=False)
    host, _, port = args.relay.rpartition(":")
    return Car(_RelayLink(host or "127.0.0.1", int(port)), period=0.02, open_it=not args.no_open)


def _quiet_ctrl_c(kind, value, tb):
    if kind is KeyboardInterrupt:
        print("Stopped (Ctrl+C).")
    else:
        sys.__excepthook__(kind, value, tb)


class _RelayLink:
    """sloppyCAN's script relay: one cansend-style line per frame, '#' lines are info."""

    has_info = True

    def __init__(self, host, port):
        try:
            self.sock = socket.create_connection((host, port), timeout=2)
        except OSError:
            sys.exit("Can't reach the relay at %s:%d. Run sloppycan_relay.py, then click "
                     "Script -> Connect in sloppyCAN." % (host, port))
        self.sock.settimeout(None)
        self.lock = threading.Lock()

    def send(self, can_id, data):
        self.send_line("%03X#%s" % (can_id, bytes(data).hex().upper()))

    def send_line(self, line):
        with self.lock:
            self.sock.sendall((line + "\n").encode("ascii"))

    def receive(self, on_frame, on_info):
        buf = b""
        while True:
            chunk = self.sock.recv(65536)
            if not chunk:
                print("carlito_can: the relay closed the connection", file=sys.stderr)
                return
            buf += chunk
            *lines, buf = buf.split(b"\n")
            for raw in lines:
                line = raw.decode("ascii", "ignore").strip()
                if line.startswith("#"):
                    on_info(line)
                    continue
                ident, _, hexdata = line.partition("#")
                if len(ident) == 3 and not hexdata.startswith("R"):   # telemetry is all 11-bit
                    try:
                        on_frame(int(ident, 16), bytes.fromhex(hexdata.replace(".", "")))
                    except ValueError:
                        pass


class _CanLink:
    """A real CAN adapter through python-can (pip install python-can)."""

    has_info = False

    def __init__(self, interface, channel, bitrate):
        try:
            import can
        except ImportError:
            sys.exit("--can needs python-can: pip install python-can")
        self.can = can
        self.bus = can.Bus(interface=interface, channel=channel, bitrate=bitrate)

    def send(self, can_id, data):
        try:
            self.bus.send(self.can.Message(arbitration_id=can_id, data=bytes(data),
                                           is_extended_id=False))
        except self.can.CanError:
            pass   # a full transmit buffer drops one frame; the next period sends it again

    def receive(self, on_frame, on_info):
        while True:
            msg = self.bus.recv(0.5)
            if msg is not None and not msg.is_extended_id and not msg.is_remote_frame:
                on_frame(msg.arbitration_id, bytes(msg.data))


class Car:
    def __init__(self, link, period, open_it):
        self.link = link
        self._open_it = open_it
        # Commands, sent every `period` seconds.
        self.key = IGNITION
        self.gear = P
        self.accel = 0.0
        self.brake = 0.0
        self.steer = 0.0
        self.handbrake = False
        self.lights = OFF
        self.turn_left = False
        self.turn_right = False
        # Telemetry, None until its frame has arrived.
        self.kmh = self.speed = self.rpm = self.gear_now = None
        self.acc_lat = self.heading = self.x = self.z = self.odo = self.status = None
        # Challenge state.
        self.running = False
        self.result = None
        self._started = threading.Event()
        self._challenge = None
        self._path = None
        self._cruise_i = 0.0
        self._cruise_t = None
        self._fresh_pos = self._fresh_heading = False

        for ecu in RAMN_ECUS:
            link.send(ecu, RAMN_SILENCE)
        threading.Thread(target=link.receive, args=(self._on_frame, self._on_info),
                         daemon=True).start()
        threading.Thread(target=self._send_loop, args=(period,), daemon=True).start()
        atexit.register(self._exit)

    # -- challenge ------------------------------------------------------------------------

    def wait_start(self, challenge_id):
        """Open the challenge (unless --no-open), wait for it to start, then for fresh telemetry."""
        self._challenge = challenge_id
        if self.link.has_info:
            if self._open_it:
                self.link.send_line("#challenge open " + challenge_id)
                print("Asked Carlito to open '%s'..." % challenge_id)
            else:
                print("Start '%s' in the game (or press RETRY)..." % challenge_id)
            hint_at = time.monotonic() + 20
            while not self._started.wait(0.2):   # a timeout keeps Ctrl+C working on Windows
                if self._open_it and time.monotonic() > hint_at:
                    hint_at = float("inf")
                    print("Still waiting: is sloppyCAN connected (Script -> Connect)? An older "
                          "Carlito build ignores the request: start the challenge by hand.")
        else:
            input("Start '%s' in the game, then press Enter here..." % challenge_id)
            self._restart()
        deadline = time.monotonic() + 3
        while not self._have_telemetry() and time.monotonic() < deadline:
            time.sleep(0.02)
        if not self._have_telemetry():
            sys.exit("No telemetry from the car: is Carlito open in sloppyCAN (and, on hardware, "
                     "sloppyCAN's bus not listen-only)?")
        print("Started.")

    def tick(self, seconds=0.05):
        """Sleep a little; True while the challenge is still running."""
        time.sleep(seconds)
        return self.running

    def finish(self):
        """Wait for the end of the challenge, print the result and park the car."""
        while self.running:
            time.sleep(0.05)
        self._park()
        print(self.result or "Stopped.")

    # -- driving helpers -------------------------------------------------------------------

    def distance_to(self, x, z):
        return math.hypot(x - self.x, z - self.z)

    def steer_to(self, x, z, method=None, gain=2.0):
        """Steer towards the world point (x, z). Returns the distance to it. STEER_PROPORTIONAL
        (the default) steers more the further off the point is; STEER_BANGBANG is the beginner's
        version: a fixed amount left or right, or straight."""
        bearing = math.degrees(math.atan2(x - self.x, self.z - z))   # compass: north is -z
        error = (bearing - self.heading + 540) % 360 - 180            # + means "to the right"
        if method == STEER_BANGBANG:
            if error > 3:
                self.steer = 15      # the point is on the right: steer right
            elif error < -3:
                self.steer = -15     # on the left: steer left
            else:
                self.steer = 0       # straight ahead
        else:
            self.steer = clamp(error * gain, -100, 100)
        return self.distance_to(x, z)

    def follow(self, path, method=None, lookahead=8.0):
        """Steer along a list of (x, z) points with steer_to (same `method`). True once the last
        one is close."""
        if self._path is not path:
            self._path, self._path_i = path, 0
        while self._path_i < len(path) - 1 and self.distance_to(*path[self._path_i]) < lookahead:
            self._path_i += 1
        return (self.steer_to(*path[self._path_i], method) < lookahead
                and self._path_i == len(path) - 1)

    def cruise(self, kmh, method=None):
        """Hold a speed with accel and brake. CRUISE_CONTROL_PI (the default) is a small PI
        controller; CRUISE_CONTROL_BANGBANG is the beginner's version, easier to read."""
        if method == CRUISE_CONTROL_BANGBANG:
            if self.kmh < kmh:
                self.accel = 50     # too slow: half throttle
            else:
                self.accel = 0      # fast enough: foot off, the car slows down by itself
            self.brake = 0
            return
        now = time.monotonic()
        dt = 0.0 if self._cruise_t is None else min(now - self._cruise_t, 0.2)
        self._cruise_t = now
        error = kmh - self.kmh
        out = 6 * error + self._cruise_i
        if 0 < out < 100:                      # only integrate while not saturated
            self._cruise_i = clamp(self._cruise_i + 3 * error * dt, 0, 60)
        self.accel = clamp(out, 0, 100)
        self.brake = clamp(-out, 0, 100)

    # -- internals --------------------------------------------------------------------------

    def _have_telemetry(self):
        return (self._fresh_pos and self._fresh_heading and self.kmh is not None
                and self.rpm is not None and self.odo is not None)

    def _restart(self):
        self._fresh_pos = self._fresh_heading = False   # a fresh car spawns: wait_start waits for it
        self._path = None
        self._cruise_i, self._cruise_t = 0.0, None
        self.result = None
        self.running = True
        self._started.set()

    def _on_info(self, line):
        words = line.split()
        if len(words) < 3 or words[0] != "#challenge" or words[2] != self._challenge:
            return
        if words[1] == "start":
            if self.running:
                print("Restarted (respawn or RETRY).")
            self._restart()
        elif words[1] in ("pass", "fail", "exit") and self.running:
            self.result = {"pass": "PASSED in %s s", "fail": "FAILED after %s s",
                           "exit": "Left the challenge%s"}[words[1]] % (
                               words[3] if len(words) > 3 else "")
            if words[1] == "fail" and len(words) > 4:
                self.result += ": " + " ".join(words[4:])
            self.running = False

    def _on_frame(self, can_id, d):
        def s16(i):
            v = d[i] << 8 | d[i + 1]
            return v - 0x10000 if v & 0x8000 else v

        def s32(i):
            v = int.from_bytes(d[i:i + 4], "big")
            return v - 0x100000000 if v & 0x80000000 else v

        if can_id == 0x520 and len(d) >= 4:
            self.speed = s16(0) / 100
            self.kmh = (d[2] << 8 | d[3]) / 10
        elif can_id == 0x521 and len(d) >= 3:
            self.rpm = d[0] << 8 | d[1]
            self.gear_now = d[2]
        elif can_id == 0x522 and len(d) >= 6:
            self.acc_lat = s16(4) / 100
        elif can_id == 0x524 and len(d) >= 6:
            self.heading = (d[4] << 8 | d[5]) / 10
            self._fresh_heading = True
        elif can_id == 0x525 and len(d) >= 8:
            lat, lon = s32(0) / 1e7, s32(4) / 1e7
            self.x = (lon - GPS_LON0) * M_PER_DEG * math.cos(math.radians(GPS_LAT0))
            self.z = -(lat - GPS_LAT0) * M_PER_DEG
            self._fresh_pos = True
        elif can_id == 0x526 and len(d) >= 4:
            self.odo = int.from_bytes(d[0:4], "big")
        elif can_id == 0x527 and len(d) >= 2:
            self.status = d[0] << 8 | d[1]

    def _frames(self):
        def pedal(pct):            # 12-bit big-endian, 0x000..0xFFF
            v = round(clamp(pct, 0, 100) / 100 * 0xFFF)
            return [v >> 8, v & 0xFF]

        s = clamp(self.steer, -100, 100)
        steer = round(0x7FF + s / 100 * (0x800 if s > 0 else 0x7FF))
        lamps = {LOW: 0x08 | 0x10, HIGH: 0x08 | 0x10 | 0x20}.get(self.lights, 0)
        lamps |= (0x40 if self.turn_left else 0) | (0x80 if self.turn_right else 0)
        return [
            (0x1B8, [self.key, 0]),
            (0x077, [self.gear, 1]),
            (0x039, pedal(self.accel)),
            (0x024, pedal(self.brake)),
            (0x062, [steer >> 8, steer & 0xFF]),
            (0x1D3, [1 if self.handbrake else 0, 0]),
            (0x1BB, [lamps, 0]),
        ]

    def _send_loop(self, period):
        try:
            while True:
                for can_id, data in self._frames():
                    self.link.send(can_id, data)
                time.sleep(period)
        except OSError as e:
            print("carlito_can: sending failed (%s); the car is no longer driven" % e,
                  file=sys.stderr)
            self.running = False

    def _park(self):
        """Foot off, brakes on: what sloppyCAN keeps (RAMN values latch) once we stop sending."""
        self.accel, self.brake, self.steer, self.handbrake = 0, 100, 0, True
        try:
            for can_id, data in self._frames():
                self.link.send(can_id, data)
        except OSError:
            pass

    def _exit(self):
        """At exit: park, then give the RAMN ECUs their periodic frames back."""
        self._park()
        try:
            for ecu in RAMN_ECUS:
                self.link.send(ecu, RAMN_RESUME)
        except OSError:
            pass
