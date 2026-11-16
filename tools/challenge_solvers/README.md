# Challenge solvers

One Python script per car challenge, which solves it over CAN. They test that a challenge can
be passed by a script, end to end. The number in a script's name is the challenge's place in the
car list (`ChallengeRegistry.DEFS`). `carlito_can.py` is the shared helper; its header lists
every command and telemetry value.

## The scripts

| Script | How it solves |
|---|---|
| `car_001_start_up.py` | D, 40 % accel, steer to the Finish line (you turn the key). |
| `car_002_easy_turns.py` | Follows the four touching r=35 arcs round the `Cut0..3` centres at 25 km/h. |
| `car_003_lights.py` | Low beam, then follows the causeway's three r=70 arcs at 30 km/h. |
| `car_004_manual_gearbox.py` | Gear 1, full accel, shifts up past 6300 rpm; 200 m inside 11.5 s. |
| `car_005_reverse_park.py` | Turns onto x=-125 facing south, then reverses north at 3 km/h into the bay (GPS-held: ±0.42 m to spare). |
| `car_006_turn_signals.py` | Follows the corners road, each lamp steady on in the 30 m before its corner. |
| `car_007_hazards.py` | Stands still with both turn lamps on until it passes. |
| `car_008_speed_trap.py` | Cruises at 60 km/h on the start heading. |
| `car_009_corner_budget.py` | The same road as `car_002`, at 36 km/h. |
| `car_010_box_stop.py` | 55 km/h to just past the gate (GPS x > 20.5), full brake, handbrake. |
| `car_011_box_blind.py` | The same stop, the gate from the odometer (+171 m). |
| `car_012_blind_stadium.py` | Follows the stadium centre line (two r=15 left semicircles) at 20 km/h. |

## Run one (sloppyCAN)

1. Start the relay from the sloppyCAN repo: `python scripting/sloppycan_relay.py`.
2. In sloppyCAN, click **Script**, then **Connect** (a bus or Demo mode must be live).
3. Run the solver: `python tools/challenge_solvers/car_001_start_up.py`.

The script asks sloppyCAN to open the challenge: a running game switches to it at once, and a
shut Carlito window opens straight into it. The script drives as soon as it starts, and prints
`PASSED in ... s` or `FAILED ...`. With `--no-open` it waits for you to start the challenge in
the game instead.

Python 3.8+ and nothing to install.

## Real hardware

`python car_001_start_up.py --can slcan COM5` (any python-can interface and channel;
`--bitrate`, default 500000). Needs `pip install python-can`. The script first silences RAMN's
ECUs B and C (UDS `31 01 02 00` to 0x7E1 and 0x7E2), so their own pedal, steering and light
frames stop competing, and gives them back at exit (`31 02 02 00`). ECU D stays on: it lights the
LEDs from the script's light commands (0x150, 0x1A7), flashes the turn lamps, and reports them
on 0x1BB. Its engine key (0x1B8) is not sent either: turn the RAMN's key to Ignition.
sloppyCAN's demo plays the same routine, and silences B and C itself when a challenge starts.
sloppyCAN must put the telemetry on the bus (a bus that is not listen-only). Hardware carries no
challenge info lines and no open request: start the challenge yourself, press Enter when it has
started, and Ctrl+C to stop.
