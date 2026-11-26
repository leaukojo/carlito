class_name CouplingProfile
extends Resource
## What tells one TowHost from another, as data: the fifth wheel and the drawbar run the same
## TowHost code, and everything they disagree about is a field here. Data, read by
## TowHost._build_joint and the three notice sites, plus the plate friction's law over its fields.
##
## The three angular limits and the plate's friction figures are physics, stated once on the owning
## host script (Drawbar, FifthWheel); this resource is built from those constants, never a retyped
## digit. The spawn countdown, fit-check window and couple speed stay TowHost constants, identical
## on both hosts.

## Pitch stop, degrees each side (local X).
@export var pitch_deg := 0.0
## Yaw stop, degrees each side (local Y, the articulation axis).
@export var yaw_deg := 0.0
## Roll stop, degrees each side (local Z).
@export var roll_deg := 0.0

## Friction about the articulation axis, a greased plate's measured law (`yaw_friction_moment`):
## its four figures, all 0 = a free hinge (a drawbar pin rubs almost nothing, so it leaves them).
## Applied by TowHost as a torque pair against the RELATIVE yaw rate, never as a spring to zero
## angle.
## r: the plate's effective friction radius (m).
@export var friction_radius_m := 0.0
## mu: the saturated friction coefficient on the kingpin load.
@export var friction_mu := 0.0
## k: how fast the load's part saturates with the rate (s/rad).
@export var friction_k := 0.0
## b: the grease's viscous part (N*m*s/rad).
@export var friction_b := 0.0

## Name of the Generic6DOFJoint3D in the tree.
@export var joint_name: StringName = &"Coupling"

## Path to the coupling marker under the host node; its position is the coupling datum.
@export var marker_path: NodePath = ^""

## Notice when coupling is asked for with the rig still moving.
@export var speed_notice := ""
## Notice when the fit check takes a freshly coupled trailer away again.
@export var no_room_notice := ""
## Notice on a tip-up press refused by the raise interlock.
@export var tip_notice := ""


## The plate's friction moment (N*m, never negative) at the relative yaw rate `rate` (rad/s) under
## `kingpin_load_n` (N): `N r mu (1 - e^(-k |v|)) + b |v|` (docs/sources.md § Fifth-wheel plate
## friction). 0 with nothing pressing the faces together: neither part acts without contact.
func yaw_friction_moment(rate: float, kingpin_load_n: float) -> float:
	if kingpin_load_n <= 0.0:
		return 0.0
	var v := absf(rate)
	return kingpin_load_n * friction_radius_m * friction_mu * (1.0 - exp(-friction_k * v)) \
			+ friction_b * v
