# Challenge solvers

One Python script per car challenge, which solves it over CAN. They test that a challenge can
be passed by a script, end to end. `carlito_can.py` is the shared helper; its header lists
every command and telemetry value.

## Run one (sloppyCAN)

1. Start the relay from the sloppyCAN repo: `python scripting/sloppycan_relay.py`.
2. In sloppyCAN, click **Script**, then **Connect**. Open Carlito (Demo mode is fine).
3. Run the solver: `python tools/challenge_solvers/car_start_up.py`.
4. Start the same challenge in the game. The script drives as soon as it starts, and prints
   `PASSED in ... s` or `FAILED ...`. RETRY in the game runs it again.

Python 3.8+ and nothing to install.

## Real hardware

`python car_start_up.py --can slcan COM5` (any python-can interface and channel; `--bitrate`,
default 500000). Needs `pip install python-can`. The script first silences the RAMN ECUs
(UDS `31 01 02 00` to 0x7E1-0x7E3), so their own pedal and steering frames stop competing.
sloppyCAN must put the telemetry on the bus (a bus that is not listen-only). There are no
challenge info lines on hardware: press Enter when the challenge has started, and Ctrl+C to stop.
