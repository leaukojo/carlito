class_name DroneTelemetry
extends VehicleTelemetry
## Drone telemetry (DroneCAN flavor). Adds the flight "out" fields on top of the
## shared VehicleTelemetry. Field names are EXACTLY the contract names (altitude/vspeed/
## rotor_rpm/armed and the shared pitch/roll) so the Bridge's name-keyed marshaling and
## the dashboard's t.get(name) reads work unchanged.
##
## altitude / vspeed / pitch / roll / armed are read straight out of the flight sim (real
## values: world Y, vertical velocity, the body basis, the arm gate). rotor_rpm is a
## modeled honest value (same latitude as the boat's trim / the tractor's engine_load):
## the rotors have no simulated shaft, so their speed is derived from thrust demand by the
## pure rotor_rpm model in drone.gd, and is labelled as modeled.
##
## The base to_bridge_dict still carries rpm/gear/fuel/coolant/ground; the drone declares
## none of those, so the Bridge (which walks the contract, not this dict) simply never
## reads them. Only the fields the drone actually declares are published.

var altitude := 0.0     ## m above sea level, contract 'altitude' (world Y; water is y=0)
var vspeed := 0.0       ## m/s, contract 'vspeed' (variometer, + = climbing)
var rotor_rpm := 0      ## rev/min, contract 'rotor_rpm' (mean rotor speed, modeled)
var armed := false      ## contract 'armed' (motors armed: arm request and key Ignition)
var pitch := 0.0        ## deg, contract 'pitch' (+ = nose up)
var roll := 0.0         ## deg, contract 'roll' (+ = starboard/right side down)


func to_bridge_dict() -> Dictionary:
	var d := super()
	d["altitude"] = altitude
	d["vspeed"] = vspeed
	d["rotor_rpm"] = rotor_rpm
	d["armed"] = armed
	d["pitch"] = pitch
	d["roll"] = roll
	return d
