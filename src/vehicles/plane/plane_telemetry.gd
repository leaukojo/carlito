class_name PlaneTelemetry
extends VehicleTelemetry
## Plane telemetry (CANaerospace flavor). Adds the flight "out" fields on top of the
## shared VehicleTelemetry. Field names are EXACTLY the contract names (altitude/vspeed/
## flaps_actual and the shared pitch/roll) so the Bridge's name-keyed marshaling and the
## dashboard's t.get(name) reads work unchanged.
##
## altitude / vspeed / pitch / roll / flaps_actual are read straight out of the flight
## sim (world Y, vertical velocity, the body basis, the slewed flap position). The base
## `rpm` field is overwritten by PlaneVehicle with its modeled prop rpm — the same
## honest-model latitude as the boat's trim / the drone's rotor_rpm — because with
## undriven wheels the drivetrain's wheel-derived rpm would idle forever; the published
## number is exactly the one the prop thrust is computed from (rule 3, labelled).
## gear/fuel/coolant/ground keep riding the base dict — the plane declares all of them.

var altitude := 0.0      ## m above sea level, contract 'altitude' (world Y; water is y=0)
var vspeed := 0.0        ## m/s, contract 'vspeed' (variometer, + = climbing)
var flaps_actual := 0    ## %, contract 'flaps_actual' (flap position slewed toward request)
var pitch := 0.0         ## deg, contract 'pitch' (+ = nose up)
var roll := 0.0          ## deg, contract 'roll' (+ = starboard/right side down)


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["altitude"] = altitude
	d["vspeed"] = vspeed
	d["flaps_actual"] = flaps_actual
	d["pitch"] = pitch
	d["roll"] = roll
	return d
