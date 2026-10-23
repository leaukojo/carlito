class_name VehicleInput
extends RefCounted
## Normalized per-tick input produced by InputRouter.arbitrate_local/bridge. A class_name in
## its own file so vehicles' static types don't depend on the autoload's name. Fields are flat
## except lamps (fourteen bits share one rule). arbitrate_* build a fresh struct each tick, so
## a stashed reference reads stale, not live. Read-only by convention — a hand-written field
## mirror is a field that goes missing silently.


## Lamp and warning bits, mirrored verbatim from sloppyCAN. Absent bit = off; no local source
## except `brake_lamp` (follows the local foot brake), and no local blink timer anywhere: a lamp
## flashes because sloppyCAN toggles its bit (`tests/test_lamps.gd`). `lights` is InputRouter's.
class LampInput extends RefCounted:
	var turn_left := false
	var turn_right := false
	var brake_lamp := false   ## rear STOP state (0x1BB brake bit / local foot brake)
	var check_engine := false ## warning LED; defaults off when the bridge doesn't send it
	var battery_warn := false ## battery warning LED (distinct from the 'out' voltage)
	# Aircraft flashing lamps (plane only).
	var beacon := false       ## anti-collision beacon lit this instant
	var strobe := false       ## wing-tip strobes lit this instant
	# DroneCAN indication (drone only), bridge-only: an LED colour is not a control you fly with.
	var led := 0              ## LightsCommand packed RGB565 arm-tip colour (0 = off; LampSet.led_color)
	var beep := false         ## BeepCommand airframe buzzer (audible side unmodelled)
	# J1939-73 DM1 lamp status byte (truck); `check_engine` is DM1's MIL. Flash rates arrive as
	# bit toggles, like the turn lamps.
	var red_stop := false      ## DM1 Red Stop Lamp — stop the vehicle
	var amber_warn := false    ## DM1 Amber Warning Lamp — needs attention, keep going
	var protect_lamp := false  ## DM1 Protect Lamp — a non-electronic fault (fluid out of range)
	# ISO 11992 trailer bus (truck): the towed unit's counterpart of the DM1 bits above.
	var trailer_ebs_fault := false  ## trailer EBS fault reported over the trailer bus
	# SAE J2497 / PLC4TRUCKS (truck, North America): trailer ABS rides the power line as one bit.
	var trailer_abs_lamp := false   ## trailer ABS telltale off the power line (SAE J2497)


var throttle := 0.0    ## -1..1, signed by direction (never from the brake)
var brake := 0.0       ## 0..1 foot brake
var steer := 0.0       ## -1..1, negative = left
var handbrake := 0.0   ## 0..1
var gear_request := 0  ## RAMN gear byte: 0=N, 1..24=D1-D24, 255=R, 254=P
var gear_auto := true  ## true: byte is a direction intent, gearbox auto-shifts in D;
                       ## false (bridge, manual gearbox): byte is exact and owns direction
var key := 1           ## 1=Lock, 2=On, 3=Ignition
var horn := false
var lights := 1        ## 1=OFF, 2=CLEARANCE, 3=LOW, 4=HIGH
## Every lamp and warning bit, mirrored verbatim from the source — see LampInput above.
var lamps := LampInput.new()
# Driveline requests (WheelDrive), inert unless the spec declares the hardware.
var diff_lock := false    ## rear differential lock request
var fwd_drive := false    ## MFWD front-axle engage request
var tcs_off := false      ## traction control off request (bridge-only: local drives with TC on)
var retarder := 0.0       ## 0..1 truck driveline brake request (bridge-only)
# ISOBUS implement request (tractor; the semi reads hitch_request in its transport sense).
var hitch_request := 1.0  ## 0..1 requested hitch height (1 = raised/transport)
var pto := false          ## PTO engage request
var pto_mode := 0         ## PTO speed selection: 0 = 540, 1 = 1000 (contract 'pto_mode' enum)
var scv_flow := 0.0       ## 0..1 hydraulic remote (SCV) valve opening (local key: the SCV toggle)
## 0..1 hand throttle: the all-speed governor's second lever (`PedalMap.demand`), contract
## 'hand_throttle'. Sets engine speed only; the pull-away still takes `throttle`.
var hand_throttle := 0.0
# Flight controls (plane: elevator/flaps; drone: climb/arm).
var elevator := 0.0       ## -1..1, + = nose up (plane elevator)
var climb := 0.0          ## -1..1, + = ascend (drone vertical rate)
var arm := false          ## drone motor arm (rotors spin only when armed)
var flaps := 0.0          ## 0..1 requested flap extension (plane only)
# Drone requests below are mirrored verbatim (absent = the default); results come back on
# their own `*_actual` / `*_state` signals, never echoed here.
var node_fail := 0        ## bit i takes DroneBus.NODES[i] off the bus (contract 'node_fail')
var flight_mode := 0      ## DroneModes ladder: 0 STABILIZE, 1 ALT_HOLD, 2 LOITER, 3 RTL, 4 LAND
var hardpoint_cmd := false ## cargo hook: true = HOLD the load, false = RELEASE it
# Camera gimbal, contract degrees, bridge-only; the mount slews (drone_gimbal.gd).
var gimbal_pitch := 0.0   ## deg, + = up (contract 'gimbal_pitch')
var gimbal_yaw := 0.0     ## deg, + = right (contract 'gimbal_yaw')
# Boat autopilot (flavor "nmea2000"). Presence rule, like `rudder`: every [0,360] is a legal
# bearing, so "the bus sent nothing" is this internal marker; absent = hold the engage heading.
const HEADING_CMD_NONE := -1.0
# Tractor ISOBUS guidance (PGN 44288), same presence rule (0 = dead straight). Also folded into
# `steer`; this raw curvature lets WheelDrive steer the commanded radius at any speed.
const GUIDANCE_CURVATURE_NONE := 1000.0  ## not a legal curvature (wire max +-127 1/km)
## Boat sheet (`boat-sail-a` only): 0 = hauled in hard, 1 = fully eased. A limit on the boom's
## travel, not a position; the boom reports on `sail_angle`.
var sheet := 0.0
var nav_mode := 0         ## BoatAutopilot ladder: 0 STANDBY, 1 HEADING_HOLD (contract 'nav_mode')
var heading_cmd := HEADING_CMD_NONE  ## deg [0,360] commanded course, or HEADING_CMD_NONE
## 1/km, signed like `steer` (+ = right), or GUIDANCE_CURVATURE_NONE with no hand on the ISOBUS
## guidance wheel this tick.
var guidance_curvature := GUIDANCE_CURVATURE_NONE
# Train controls (flavor "train").
var pantograph := false   ## pantograph raise request (traction is cut while lowered)
var doors := false        ## passenger door open request (honored at standstill only)
# CiA 422 body network (flavor "cleanopen", garbage truck), across a gateway.
var body_cmd := 0          ## RefuseBody.Cmd: 0 Idle, 1 Lift, 2 Dump, 3 Lower
