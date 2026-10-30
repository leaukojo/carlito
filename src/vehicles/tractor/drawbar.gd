class_name Drawbar
extends TowHost
## The tractor's rear drawbar: a fixed pin, the coupler for whatever is hitched to it. The joint,
## gates and housekeeping are TowHost's; this class is the pin and its limits.

## Pin in the chassis frame: the Drawbar node's +0.81 mount plus `Pin`'s 1.60 (keep in step;
## test_drawbar_trailer sweeps about it). Its 0.40 m height is farm_tipper's authoring datum.
const PIN_LOCAL := Vector3(0.0, 0.40, 2.41)

## Yaw stop, deg each side: the tipper body's corners (|x| 0.90, 1.09 m aft of the pin) meet the
## drawn 0.805 m rear tyres at ~61 on the 1.79 m track (test_drawbar_trailer sweeps it); 57 holds
## ~4 deg back from contact for the joint's overshoot under load. Not Articulation's cab model.
const SWING_MAX_DEG := 57.0

## Pitch stop, deg each side: covers the steepest grade break (the stop levers the drive axle up).
const PITCH_LIMIT_DEG := 20.0

## Roll stop, deg each side: a drawbar eye lets a trailer roll on its own wheels; wide, but a
## bounded 6DOF axis is what catches a body past upright.
const ROLL_LIMIT_DEG := 25.0

## Shown when E asks for a trailer while still rolling.
const HITCH_SPEED_NOTICE := "STOP WHERE THERE IS ROOM TO HITCH"
const NO_ROOM_NOTICE := "NO ROOM FOR A TRAILER - PULL FORWARD"
## Why the SCV did nothing (raise direction only; the ram runs off the tractor's own pump).
const TIP_INTERLOCK_NOTICE := "SET THE HANDBRAKE FIRST"

static var _profile: CouplingProfile = null


func _ready() -> void:
	super._ready()
	# Nothing here moves, so the six meshes merge into one; Pin is a Marker3D.
	StaticMeshMerge.merge_subtree(self)


func profile() -> CouplingProfile:
	if _profile == null:
		_profile = CouplingProfile.new()
		_profile.pitch_deg = PITCH_LIMIT_DEG
		_profile.yaw_deg = SWING_MAX_DEG
		_profile.roll_deg = ROLL_LIMIT_DEG
		_profile.joint_name = &"DrawbarPin"
		_profile.marker_path = ^"Pin"
		_profile.speed_notice = HITCH_SPEED_NOTICE
		_profile.no_room_notice = NO_ROOM_NOTICE
		_profile.tip_notice = TIP_INTERLOCK_NOTICE
	return _profile


func default_marker_local() -> Vector3:
	return PIN_LOCAL
