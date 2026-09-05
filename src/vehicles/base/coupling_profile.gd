class_name CouplingProfile
extends Resource
## What tells one TowHost from another, as data: the fifth wheel and the drawbar run the same
## TowHost code, and everything they disagree about is a field here. Pure data, read by
## TowHost._build_joint and the three notice sites.
##
## The three angular limits are physics, stated once on the owning host script (Drawbar,
## FifthWheel); this resource is built from those constants, never a retyped digit. The spawn
## countdown, fit-check window and couple speed stay TowHost constants, identical on both hosts.

## Pitch stop, degrees each side (local X).
@export var pitch_deg := 0.0
## Yaw stop, degrees each side (local Y, the articulation axis).
@export var yaw_deg := 0.0
## Roll stop, degrees each side (local Z).
@export var roll_deg := 0.0

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
