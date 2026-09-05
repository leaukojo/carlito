class_name PlaneTelemetry
extends VehicleTelemetry
## Plane telemetry. Adds the one field the base has no equivalent for; name matches the
## contract signal (flaps_actual) exactly.
## altitude/vspeed/pitch/roll are shared VehicleTelemetry fields, written by the base off
## the body transform. The base `rpm` field is overwritten by PlaneVehicle with the modeled
## prop rpm (honest-model, labelled) since undriven wheels would leave wheel-derived rpm
## idling forever.

var flaps_actual := 0    ## %, contract 'flaps_actual' (flap position slewed toward request)
