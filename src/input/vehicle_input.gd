class_name VehicleInput
extends RefCounted
## Normalized per-tick input produced by InputRouter.arbitrate_local/bridge. A class_name in
## its own file so vehicles' static types don't depend on the autoload's name. Fields are flat
## except lamps (fourteen bits share one rule). arbitrate_* build a fresh struct each tick, so
## a stashed reference reads stale, not live. Read-only by convention — a hand-written field
## mirror is a field that goes missing silently.


## Lamp and warning bits: sloppyCAN is the sole authority, mirrored verbatim. Absent bit = off,
## no local source (except `brake_lamp`, which follows the local foot brake), and no local blink
## timer anywhere — J1939-73 DM1 flash-1Hz/2Hz included. `tests/test_lamps.gd` fails if a clock
## comes back.
##
## Two read sites: `BaseVehicle._physics_process` (into LampSet) and `Dashboard._update_telltales`.
## `lights` is not here — it's a headlight level InputRouter owns and cycles.
class LampInput extends RefCounted:
	var turn_left := false
	var turn_right := false
	var brake_lamp := false   ## rear STOP state (0x1BB brake bit / local foot brake)
	var check_engine := false ## warning LED; defaults off when the bridge doesn't send it
	var battery_warn := false ## battery warning LED (distinct from the 'out' voltage)
	# Aircraft flashing lamps (plane only); flash because sloppyCAN toggles the bits.
	var beacon := false       ## anti-collision beacon lit this instant
	var strobe := false       ## wing-tip strobes lit this instant
	# DroneCAN indication (drone only), bridge-only with no local key — an LED colour is not a
	# control you fly with. `led` is uavcan.equipment.indication.LightsCommand's packed RGB565
	# (LampSet.led_color decodes it); `beep` is uavcan.equipment.indication.BeepCommand.
	var led := 0              ## packed RGB565 arm-tip LED colour (0 = off/black)
	var beep := false         ## airframe buzzer command (audible side unmodelled)
	# J1939-73 DM1 lamp status byte (truck). checkEngine already is DM1's Malfunction Indicator
	# Lamp. DM1's flash-1Hz/flash-2Hz distinguish active vs pending faults, and need no field or
	# timer here: sloppyCAN toggles these bits at the rate that states urgency, same mechanism
	# as the turn lamps.
	var red_stop := false      ## DM1 Red Stop Lamp — stop the vehicle
	var amber_warn := false    ## DM1 Amber Warning Lamp — needs attention, keep going
	var protect_lamp := false  ## DM1 Protect Lamp — a non-electronic fault (fluid out of range)
	# ISO 11992 trailer bus (truck): the towed unit's counterpart of the DM1 bits above.
	var trailer_ebs_fault := false  ## trailer EBS fault reported over the trailer bus
	# SAE J2497 / PLC4TRUCKS (truck), the North American trailer boundary: one bit because
	# trailer ABS status rides the power line as lamp on/off. Only meaningful with no ISO 11992 bus.
	var trailer_abs_lamp := false   ## trailer ABS telltale off the power line (SAE J2497)


var throttle := 0.0    ## -1..1, signed by direction (never from the brake)
var brake := 0.0       ## 0..1 foot brake
var steer := 0.0       ## -1..1, negative = left
var handbrake := 0.0   ## 0..1
var gear_request := 0  ## RAMN gear byte: 0=N, 1..6=D1-D6, 255=R
var gear_auto := true  ## true: byte is a direction intent, gearbox auto-shifts in D;
                       ## false (bridge): byte is exact and owns direction
var key := 1           ## 1=Lock, 2=On, 3=Ignition
var horn := false
var lights := 1        ## 1=OFF, 2=CLEARANCE, 3=LOW, 4=HIGH
## Every lamp and warning bit, mirrored verbatim from the source — see LampInput above.
var lamps := LampInput.new()
# Driveline requests read by WheelDrive for every wheeled body, gated by a VehicleSpec flag
# that defaults off — inert on a machine whose spec doesn't declare the hardware.
var diff_lock := false    ## rear differential lock request
var fwd_drive := false    ## MFWD front-axle engage request
## Truck driveline brake, bridge-only, no local key: no keyboard analogue worth inventing.
var retarder := 0.0       ## 0..1 auxiliary driveline brake request
# ISOBUS implement request (tractor; the semi reads hitch_request in its transport sense).
# Default raised/off; other vehicles ignore it.
var hitch_request := 1.0  ## 0..1 requested hitch height (1 = raised/transport)
var pto := false          ## PTO engage request
var pto_mode := 0         ## PTO speed selection: 0 = 540, 1 = 1000 (contract 'pto_mode' enum)
var scv_flow := 0.0       ## 0..1 hydraulic remote (SCV) valve opening (local key: the SCV toggle)
# Flight controls, defaulted so ground vehicles ignore them: only PlaneVehicle reads
# elevator/flaps, only DroneVehicle reads climb/arm.
var elevator := 0.0       ## -1..1, + = nose up (plane elevator)
var climb := 0.0          ## -1..1, + = ascend (drone vertical rate)
var arm := false          ## drone motor arm (rotors spin only when armed)
var flaps := 0.0          ## 0..1 requested flap extension (plane only)
# DroneCAN bus failure injection (drone only). Mirrored verbatim from sloppyCAN, no local
# timer, absent = 0 = every node online; locally an InputRouter-owned cycle (Y key). Bit i =
# roster index i in DroneBus.NODES.
var node_fail := 0        ## bitfield: a set bit takes that node off the bus (contract 'node_fail')
# Drone flight-mode request. What the controller does with it comes back on 'mode_actual'
# rather than being echoed here. Mirrored verbatim, absent = 0 = STABILIZE (hand-flown);
# locally an InputRouter-owned cycle (Z key).
var flight_mode := 0      ## DroneModes ladder: 0 STABILIZE, 1 ALT_HOLD, 2 LOITER, 3 RTL, 4 LAND
# Cargo hook (drone only), uavcan.equipment.hardpoint.Command's binary case. What the latch
# did comes back as 'hardpoint_state' rather than echoed here. Mirrored verbatim, absent =
# false = released; locally an InputRouter-owned toggle.
var hardpoint_cmd := false ## true = HOLD the load, false = RELEASE it
# Camera gimbal (drone only), in contract degrees — the mount has real stops fitting i8 whole
# degrees. Bridge-only, no local key. Absent → rest pose; mount slews at its own rate
# (drone_gimbal.gd), so a step command is never a teleport.
var gimbal_pitch := 0.0   ## deg, + = up (contract 'gimbal_pitch')
var gimbal_yaw := 0.0     ## deg, + = right (contract 'gimbal_yaw')
# Boat autopilot (flavor "nmea2000"); only BoatVehicle reads them. Default: standing by, with no
# course commanded. HEADING_CMD_NONE is an INTERNAL "the bus sent nothing" marker and never
# reaches the wire: every value in the contract's [0,360] is a legal bearing, so the wire uses the
# `rudder` / `guidance_curvature` PRESENCE rule instead and bridge_source only writes the key when
# sloppyCAN sends it. With nothing commanded the pilot steers the heading it captured on engage,
# which is also the only thing the local key can ask for (no keyboard types a bearing).
const HEADING_CMD_NONE := -1.0
## The sheet (boat only, and only `boat-sail-a` answers it — a rig is anatomy, gated by
## BoatVehicle.vehicle_capabilities, the `body_cmd` shape). 0 = hauled in hard, 1 = fully eased. A
## LIMIT on the boom's travel rather than a position, so what the boom did comes back on
## `sail_angle` rather than being echoed here. Flat, not nested: it is one field on one rule.
var sheet := 0.0
var nav_mode := 0         ## BoatAutopilot ladder: 0 STANDBY, 1 HEADING_HOLD (contract 'nav_mode')
var heading_cmd := HEADING_CMD_NONE  ## deg [0,360] commanded course, or HEADING_CMD_NONE
# Train controls (flavor "train"); only TrainVehicle reads them. Default: pantograph down,
# doors shut.
var pantograph := false   ## pantograph raise request (traction is cut while lowered)
var doors := false        ## passenger door open request (honored at standstill only)
# CiA 422 body network (flavor "cleanopen", truck only), arriving from a second network
# across a gateway. Only the garbage truck reads it; 0 = Idle is the safe default.
var body_cmd := 0          ## RefuseBody.Cmd: 0 Idle, 1 Lift, 2 Dump, 3 Lower
