class_name Drawbar
extends TowHost
## The tractor's rear drawbar: tractor anatomy like ThreePointHitch, and the coupler for whatever
## is hitched to it. A drawbar only pulls, so there is no rockshaft, lift rod or four-bar solve,
## and the pin is fixed rather than swinging, so the joint's articulation matches what is drawn.
##
## The joint, gates and two-body housekeeping are all TowHost's. This class is only the pin's
## geometry and the numbers that make a drawbar a drawbar rather than a fifth wheel.

## Where the pin sits in the chassis frame. The documented default only: TowHost._ready reads the
## `Pin` marker off the scene, so this cannot disagree with the modeled hole.
##
## Measured against the Kenney tractor body, the pin sits at 0.40 m, a real drawbar height, clear
## of the lowered lower-link balls at y 0.21. It must never be the semi's -1.05, a fifth-wheel
## plate height, because the trailer is authored with its origin at the drawbar eye and ground at
## y = -0.40 against this.
const PIN_LOCAL := Vector3(0.0, 0.40, 1.60)

## Yaw stop, degrees each side. Not Articulation.JACKKNIFE_MAX_DEG, whose 75 deg models a
## semi-trailer against a cab, a different shape. 90 deg is derived: up to it nothing behind the
## eye reaches forward of the pin's z-plane, and the shipped body's front corners arrive at
## ~108 deg. test_drawbar_trailer sweeps every BoxMesh corner at this angle.
const SWING_MAX_DEG := 90.0

## Pitch stop, degrees each side. It must cover the steepest grade the tractor can pull the
## trailer up rather than bound it: at the stop the two bodies go rigid, and a level trailer at a
## break of slope levers the climbing drive axle off the ground. 20 deg gives headroom over the
## semi's measured 15 for a tractor's steeper climb and shorter bar.
const PITCH_LIMIT_DEG := 20.0

## Roll stop, degrees each side, and the number that makes a drawbar a drawbar. A fifth wheel
## holds trailer roll to the tractor's within ~1.5 deg, while a drawbar eye on a pin lets a farm
## trailer roll on its own wheels, so a rut under one wheel does not lever the tractor. Wide rather
## than unlimited, since an unbounded 6DOF axis has nothing to catch a body past upright.
const ROLL_LIMIT_DEG := 25.0

## Shown when E asks for a trailer while still rolling. It gates only the towed cycle entries: an
## implement can be swapped anywhere, but a trailer is laid at a pose the tractor already left.
const HITCH_SPEED_NOTICE := "STOP WHERE THERE IS ROOM TO HITCH"
const NO_ROOM_NOTICE := "NO ROOM FOR A TRAILER - PULL FORWARD"
## Why the SCV did nothing, in the raise direction only. It names no PTO, because a farm trailer's
## ram runs off the tractor's own pump and there is no shaft to engage.
const TIP_INTERLOCK_NOTICE := "SET THE HANDBRAKE FIRST"

static var _profile: CouplingProfile = null


func _ready() -> void:
	super._ready()
	# Hanger/Bar/StayL/StayR/PinShank/PinHead: nothing here moves on its own, so one merged mesh
	# replaces all six. Pin (the coupling datum TowHost._ready just read) is a Marker3D, never a
	# merge candidate.
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


## The pin in the chassis frame: the coupling datum, and where a trailer's origin is laid.
## TowHost.marker_local() under this machine's own name for it.
func pin_local() -> Vector3:
	return marker_local()
