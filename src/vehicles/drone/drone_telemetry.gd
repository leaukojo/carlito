class_name DroneTelemetry
extends VehicleTelemetry
## Drone telemetry (DroneCAN flavor). Field names match the contract exactly so Bridge marshaling
## and dashboard t.get(name) work unchanged.
##
## ESC/node arrays: element-wise writes, skipped on offline nodes so dropped entries hold last
## values. Never reassign a fresh array. `battery` is VehicleTelemetry's shared field, overwritten
## with the LiPo model (not a second name).

var rotor_rpm := 0      ## rev/min, contract 'rotor_rpm' (mean of the four esc_rpm values)
var armed := false      ## contract 'armed' (latched arm state — see drone_arming.gd)
## Sized from the start rather than grown on the first tick, so a to_bridge_dict() before flight
## has the right shape.
var esc_rpm: Array = [0, 0, 0, 0]         ## rev/min per ESC, contract 'esc_rpm' (esc_index order)
var esc_current: Array = [0.0, 0.0, 0.0, 0.0]  ## A per ESC, contract 'esc_current' (modeled)
var esc_temp: Array = [0.0, 0.0, 0.0, 0.0]     ## degC per ESC, contract 'esc_temp' (modeled)
var esc_fault := 0           ## contract 'esc_fault' bitfield, bit i = esc_index i faulted
## Bus arrays: sized/seeded from roster (not literals) so grown NODES don't break pre-tick shape.
var node_health: Array = DroneBus.all_ok()      ## per-node health, DroneBus.NODES order
var node_online := DroneBus.online_bits(0)      ## bitfield, bit i = roster index i publishing
## Pack (battery is the shared VehicleTelemetry field, not redeclared). DroneCAN BatteryInfo fields.
var pack_current := 0.0  ## A, contract 'pack_current' (sum of esc_current + avionics)
var soc := 100.0         ## %, contract 'soc' (coulomb-counted; published rounded, like fuel)
var pack_temp := 0.0     ## degC, contract 'pack_temp' (modeled I^2 R rise)
## Sensors (measured vs level collision; defaults are "unmeasured"). Respawn state.
var sats := 0                                ## count, contract 'sats' (unobstructed sky rays)
var fix_type: int = DroneSensors.FIX_NONE        ## contract 'fix_type' (Fix2.status enum, from sats)
var hdop := DroneSensors.HDOP_MAX            ## contract 'hdop' (angular spread; top = no fix)
var agl := DroneSensors.RANGE_INVALID        ## m, contract 'agl' (-1 = no return / node offline)
## IMU triples and pitch/roll/altitude/vspeed: shared VehicleTelemetry fields.
## Modes: mode_actual is the resolved state after refusals and overrides, never an echo of the
## input flight_mode, so a disagreement between them is the reading. Defaults are disarmed,
## STABILIZE, at home.
var mode_actual: int = DroneModes.STABILIZE  ## contract 'mode_actual' (the ladder, resolved)
var home_dist := 0.0                     ## m, contract 'home_dist' (horizontal, from the arming point)
## Arming (state/refusal/failsafe). Respawn state.
var arming_state: int = DroneArming.DISARMED  ## contract 'arming_state' (DISARMED/BLOCKED/ARMED)
var prearm_fail := 0                      ## contract 'prearm_fail' bitfield (0 while armed)
var failsafe: int = DroneArming.FS_NONE       ## contract 'failsafe' (most severe active condition)
## Hook (payload_weight in newtons: mass times gravity). Respawn state.
var hardpoint_state := false  ## contract 'hardpoint_state' (the latch actually closed)
var payload_weight := 0.0     ## N, contract 'payload_weight' (0 while the hook is open)
## Gimbal: mount's slewed-to angle (not an echo of command). Respawn state.
var gimbal_pitch_actual := DroneGimbal.REST_PITCH  ## deg, contract 'gimbal_pitch_actual' (+ = up)
var gimbal_yaw_actual := DroneGimbal.REST_YAW      ## deg, contract 'gimbal_yaw_actual' (+ = right)
## Barometer: it deliberately disagrees with altitude and agl, which are two labelled models.
## Defaults to a sea-level standard day.
var baro_alt := 0.0                              ## m, contract 'baro_alt' (pressure altitude)
var static_press := DroneAirData.QNH_STANDARD    ## Pa, contract 'static_press' (what baro_alt is solved from)
var oat := DroneAirData.oat_c(0.0)               ## degC, contract 'oat' (ISA lapse, nothing more)
