class_name PlaneTelemetry
extends VehicleTelemetry
## Plane telemetry: the one field the base has no equivalent for. The base `rpm` is overwritten by
## PlaneVehicle with the modeled prop rpm (a labelled honest model): undriven wheels would leave a
## wheel-derived rpm idling forever.

var flaps_actual := 0    ## %, contract 'flaps_actual' (flap position slewed toward request)
