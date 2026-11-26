[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# Inventory of modelled systems

<p class="lead">This page is the guide writers' checklist: each system the simulator models, which
vehicles have it, its code and its guide page.</p>

It was built by reading the vehicle and input code and the developer docs (drivetrain, handling,
vehicles, truck, tractor, systems).

The guide covers three of the seven families the signal contract knows: car, truck and tractor.
The boat, plane, drone and train pages wait in `docs/guide-drafts/`. "Car" includes the vans and the two racers; "truck" includes the garbage truck, the fire truck and
the two semi tractor units.

## The guide's pages

| Page | File | Covers |
| --- | --- | --- |
| Tyres and grip | [tyres.md](tyres.md) | contact patch, sources of grip, coefficient of friction, tyre types, inflation pressure |
| Slip and the grip curve | [slip.md](slip.md) | slip ratio, slip angle, grip curve, combined slip, load sensitivity |
| Steering and Ackermann | [steering.md](steering.md) | steering rate, lock and its speed taper, the bicycle angle, Ackermann, roll and compliance steer, auto-steer |
| Ground and tyre types | [surfaces.md](surfaces.md) | surfaces, tyre classes, rolling resistance on soft ground |
| Suspension | [suspension.md](suspension.md) | springs, dampers, anti-roll bars, anti-dive and anti-squat, the tractor's swinging front axle |
| Weight transfer and rollover | [weight-transfer.md](weight-transfer.md) | load moving between wheels, rollover thresholds |
| Understeer and oversteer | [understeer.md](understeer.md) | which end lets go first, what sets the balance, lift-off and power effects, stability control |
| The engine | [engine.md](engine.md) | torque curve, rpm, idle, limiter, governor, pedal map, engine braking, fuel burn |
| Clutch and torque converter | [coupling.md](coupling.md) | friction clutch, converter, creep, lock-up, launch |
| Gearbox and shifting | [gearbox.md](gearbox.md) | gear byte, automatic and manual, the shift policy, kickdown, AMT, powershift, CVT, park |
| Kinds of gearbox | [gearbox-kinds.md](gearbox-kinds.md) | gear pairs, dog clutches, manual, AMT, sequential, dual-clutch, planetary automatic, powershift, belt and power-split CVT |
| Differentials and four-wheel drive | [differentials.md](differentials.md) | open, limited-slip and Torsen diffs, diff lock, MFWD, centre diffs |
| Brakes | [brakes.md](brakes.md) | brake hardware, bias, handbrake, heat and fade, retarder, spring brakes, air |
| ABS, traction and stability control | [driver-aids.md](driver-aids.md) | ABS, TC/ASR, ESC, roll stability, their lamps |
| Holding still | [holding.md](holding.md) | hill-start assist, auto hold, the tractor's hill hold, park pawl, CVT standstill |
| Air and rolling resistance | [resistance.md](resistance.md) | drag, side force, downforce, rolling resistance |
| Towing | [towing.md](towing.md) | fifth wheel and drawbar, trailers, articulation, jackknife, trailer brakes, trailer bus |
| Implements and the PTO | [implements.md](implements.md) | three-point hitch, draft, PTO, hydraulic remote, ISOBUS |
| Wind and conditions | [conditions.md](conditions.md) | wind, gusts, wind direction, day and night |
| Fuel, coolant, battery and air | [auxiliary.md](auxiliary.md) | the simple labelled models |
| Position, heading and distance | [position.md](position.md) | GPS, heading, odometer, hour meter, acceleration and impact |
| Controls and who drives | [controls.md](controls.md) | key easing, gear selection, bridge or local input, lamps and horn, the settings and SANDBOX switches |
| How the simulation works | [simulation.md](simulation.md) | how the simulator computes each topic, and its values |
| Forces on a vehicle | [forces.md](forces.md) | every force on a body, together, in an interactive drawing |
| Vehicle pages | [car.md](car.md), [truck.md](truck.md), [tractor.md](tractor.md) | which systems each family has |
| What the simulator keeps simple | [simplifications.md](simplifications.md) | compromises and things not modelled |

## Wheels and tyres

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Wheel contact: a cylinder swept down the suspension travel | car, truck, tractor, trailers | `src/vehicles/base/wheel.gd` (`RayWheel`) | simulation |
| Slip ratio (wheel surface speed against road speed, floored at low speed) | car, truck, tractor, trailers | `wheel.gd` `tick` | slip |
| Side slip (slip angle as sideways over forward speed) | same | `wheel.gd` `tick` | slip |
| Grip curve: rises to a peak at 0.12 slip, falls to 0.8 when sliding | same; one curve on every shipped body | `GroundDriveSpec.grip_curve`, `VehicleSpec.sample_curve` | slip |
| Combined slip and the friction ellipse (braking or driving costs side grip) | same | `RayWheel.combined_slip_force`, `RayWheel.friction_ellipse` | slip |
| Load sensitivity (grip per newton falls as load rises) | car, truck, tractor, trailers | `RayWheel.load_scaled_mu`, `GroundDriveSpec.load_sensitivity` | slip |
| Cornering stiffness against load (where the side force peaks) | cars, vans, Kenney trucks, tractor (off on the semis) | `RayWheel.cornering_load_shape`, `RayWheel.lateral_peak_slip` | slip |
| Twin rear tyres (half load each) | heavy vans | `GroundDriveSpec.rear_twin_tyres` | slip |
| Static grip at rest (the contact patch spring) | every wheeled body | `RayWheel.stick_step` and neighbours | holding |
| Wheel spin from drive, brake and road torque (semi-implicit step) | every wheeled body | `RayWheel._integrate_spin`, `RayWheel.settle_spin` | forces |
| Wheel radius per axle | every wheeled body | `GroundDriveSpec.axle_radius` | tyres |
| Surfaces (grip and added drag per painted ground) | every wheeled body | `src/levels/base/surface.gd`, `HeightmapTerrain.grip_at` / `drag_at` | surfaces |
| Tyre classes (all-season, summer, winter, studded, mud, M+S drive, lug, slick, trailer) | car, truck, tractor, trailers | `src/vehicles/base/tyre_class.gd`, `src/vehicles/tyres/` | surfaces |
| Rolling resistance (tyre's own plus the ground's) | every wheeled body | `RayWheel.tick` (a moment on the wheel), `GroundDriveSpec.rolling_resistance` | resistance, surfaces |

## Steering

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Steering rate (how fast the wheels reach the request) | car, truck, tractor | `VehicleSpec.steer_speed`, `base_vehicle.gd` `_physics_process` | steering |
| Keyboard steering easing (slower at speed) | local keys only | `src/input/key_shaper.gd` | controls |
| Lock and its speed taper | car, truck, tractor | `WheelDrive.steer_lock_deg` | steering |
| Bicycle (mean) angle and turn radius | car, truck, tractor | `WheelDrive.mean_steer_angle` | steering |
| Ackermann split (inner wheel turns more) | car, truck, tractor (every one ships full Ackermann) | `WheelDrive.ackermann_angle` | steering |
| Parallel steer switch (SANDBOX ▸ STEERING) | car, truck, tractor | `WheelDrive.ackermann_fraction` | controls |
| Roll steer (body roll turns the wheels a little) | cars, vans, trucks, semis (0 on racers and tractor) | `RayWheel.roll_steer` | steering |
| Compliance steer (side force bends the rear a little) | the front-drive saloons' twist beam only | `RayWheel.compliance_steer` | steering |
| Auto-steer from a curvature command | tractor | `WheelDrive.steer_angle_from_curvature`, `guidance_steer_unit` | steering |
| Articulated (frame) steering | not modelled: every wheeled vehicle steers its front wheels | none | steering, simplifications |

## The body on its wheels

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Springs and dampers per axle, sized to a ride frequency | cars, vans; trucks hand-tuned; tractor's tyres are its suspension | `GroundDriveSpec`, `RayWheel.tick` | suspension |
| Anti-roll bars | most road bodies, every trailer axle | `RayWheel.bar_force`, `latch_bar` | suspension |
| Anti-dive and anti-squat (link geometry) | cars, vans; anti-squat only on trucks | `GroundDriveSpec.anti_dive_slope`, `anti_squat_slope` | suspension |
| Swinging front axle (beam on a pivot) | tractor | `GroundDriveSpec.front_axle_swing_deg`, `RayWheel.swing_step` | suspension |
| Body inertia (yaw declared, roll and pitch from the shapes) | every wheeled body | `VehicleMath`, `yaw_dynamic_index` | weight-transfer |
| Weight transfer (braking, accelerating, cornering) | every wheeled body | emergent from the suspension forces | weight-transfer |
| Understeer and oversteer balance | every wheeled body | `src/vehicles/base/balance_model.gd` (prediction), the tyres (behaviour) | understeer |
| Rollover and wheel lift; overturn detection | every wheeled body | emergent; `BaseVehicle.is_overturned` | weight-transfer, simulation |

## Engine, coupling and gearbox

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Torque curve and the crank as a spinning mass | car, truck, tractor | `src/vehicles/base/drivetrain.gd` | engine |
| Idle control, rev limiter | car, truck, tractor | `Drivetrain` | engine |
| Engine friction and engine braking (motoring) | car, truck, tractor | `Drivetrain.motoring_torque` | engine |
| Pedal maps: petrol torque request, linear diesel, all-speed governor | petrol cars; diesel vans and trucks; tractor | `src/vehicles/base/pedal_map.gd` | engine |
| Road-speed governor | vans, trucks, semis | `VehicleSpec.speed_limit_kmh`, `Drivetrain` | engine |
| Hand throttle | tractor | `PedalMap.demand` | engine, implements |
| Stall | not modelled: the controller opens the clutch first | `drivetrain.gd` header | engine |
| Friction clutch, launch slip | racers, semis (AMT), tractor (powershift) | `Drivetrain.coupling_step` | coupling |
| Torque converter, creep, lock-up | cars, vans, garbage truck, fire truck | `src/vehicles/base/torque_converter.gd` | coupling |
| Gear byte, P/R/N/D, automatic or manual | car, truck, tractor | `Drivetrain`, `InputRouter.arbitrate_bridge` | gearbox, controls |
| Shift policy (shift points, kickdown, skip shifts, grade logic, start gear) | car, truck, tractor | `src/vehicles/base/shift_policy.gd` | gearbox |
| Shift handover (clutch-to-clutch, AMT cut, powershift, sequential cut) | car, truck, tractor | `Drivetrain.handover_rate`, `handover_fuel` | gearbox |
| Continuously variable transmission | tractor-cvt | `Drivetrain.cvt_ratio_step`, `_solve_cvt` | gearbox |
| Park pawl | cars, vans, tractor powershift | `WheelDrive.pawl_torque` | holding, gearbox |

## Differentials and four-wheel drive

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Open differential (and one-wheel peel) | most bodies | `src/vehicles/base/differential.gd` | differentials |
| Limited-slip and Torsen-type diffs | `race`, `race-future`, `hatchback-sports`; centre on `suv`, `suv-luxury`, `race-future` | `Differential.bias_capacity` | differentials |
| Rear diff lock | tractor (also SANDBOX ▸ DIFFERENTIALS on any driven axle) | `WheelDrive._couple_differentials` | differentials |
| Front-wheel drive engagement (MFWD) | tractor | `GroundDriveSpec.front_axle_engageable` | differentials |

## Brakes and driver aids

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Brake hardware per body, front/rear split | every wheeled body | `GroundDriveSpec.brake_torque`, `brake_bias_front` | brakes |
| Brake sizing checks | every wheeled body | `src/vehicles/base/brake_sizing.gd` | brakes |
| Pedal feel anchored per body | every wheeled body | `WheelDrive.brake_application` | brakes |
| Handbrake (rear lock, drift, J-turn) | car, truck, tractor | `GroundDriveSpec.handbrake_torque` | brakes |
| Brake heat and fade | every wheeled body (trailers heat unpublished) | `src/vehicles/base/brake_thermal.gd` | brakes |
| Retarder | trucks, semis | `Drivetrain.retarder_rating`, `GroundDriveSpec.retarder_equipped` | brakes |
| Air reservoirs and spring brakes | trucks, semis | `src/vehicles/truck/truck_telemetry.gd`, `WheelDrive.spring_brake` | brakes, aux |
| ABS (ideal: holds the slip at the grip peak) | every road body but the racers; trailers | `RayWheel.ABS_SLIP`, `WheelDrive.anti_lock_on` | driver-aids |
| Traction control / ASR | cars but `race-future`; trucks, semis | `RayWheel.TCS_SLIP`, `GroundDriveSpec.tcs_equipped` | driver-aids |
| Stability control (yaw) | every road body with ABS | `src/vehicles/base/stability_control.gd` | driver-aids |
| Roll stability (rig and trailer) | semis and their semi-trailers | `StabilityControl.trailer_roll_step` | driver-aids, towing |
| Dashboard lamps for the aids (ESC, TC, ABS OFF, trailer ABS, VDC) | as fitted | `src/ui/dashboard.gd` | controls |
| Hill-start assist | every ABS body | `src/vehicles/base/hill_hold.gd` | holding |
| Tractor powershift hill hold | tractor-kenney | `HillHold.Kind` STANDSTILL | holding |
| Auto hold (setting) | wheel-driving bodies, keys, touch and gamepad | `InputRouter.auto_hold` | holding |
| Active standstill | tractor-cvt | `Drivetrain.standstill_hold` | holding |
| Cruise control | not modelled on any road vehicle | none | simplifications |

## Resistance and air

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Aerodynamic drag and side force against the level's wind | car, truck, tractor, trailers | `VehicleMath.air_force` | resistance |
| Downforce | the two racers | `VehicleMath.aero_downforce` | resistance |
| Crosswind | car, truck, tractor | `WindField.at`, `VehicleMath.air_force` | resistance, conditions |

## Towing and implements

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Tow host, coupling profiles (fifth wheel, drawbar) | semis; tractor | `src/vehicles/base/tow_host.gd`, `coupling_profile.gd`, `src/vehicles/truck/fifth_wheel.gd`, `src/vehicles/tractor/drawbar.gd` | towing |
| Towed body on its own wheels, articulation, jackknife stop | semi-trailers, farm tipper | `src/vehicles/base/towed_body.gd`, `articulation.gd` | towing |
| Trailer brakes (demand, lag, own ABS, spring brakes) | semi-trailers, farm tipper | `TowedBody` | towing |
| Trailer bus (ISO 11992) and its absence (J2497) | `semi` has it, `semi-conventional` does not | `semi.gd` | towing |
| Trailer loads: tipper body, tanker surge | tipper and tanker trailers | `src/vehicles/truck/trailers/` | towing |
| Three-point hitch and its four-bar linkage | tractor | `three_point_hitch.gd`, `hitch_linkage.gd` | implements |
| Draft force in soil | tractor with plough or harrow | `TractorVehicle._apply_draft`, `ImplementBase.draft_rating` | implements |
| PTO as engine load | tractor; garbage truck body pump | `Drivetrain.accessory_torque`, `src/vehicles/truck/refuse_body.gd` | implements, truck |
| Hydraulic remote (SCV) | tractor | `ThreePointHitch.set_scv`, `Drawbar.set_scv` | implements |
| Implement weight on the axles | tractor | `TractorVehicle._apply_implement_mass` | implements |
| ISOBUS implement claim | tractor | `src/vehicles/tractor/implement_base.gd` | implements |
| Refuse body over a gateway (CANopen) | garbage truck | `refuse_body.gd` | truck |

## Aux models, position and conditions

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Fuel burn from the crank, scaled-down tank | car, truck, tractor | `VehicleTelemetry.fuel_rate_lph` | aux |
| Coolant temperature | car, truck, tractor | `VehicleTelemetry.coolant_target` | aux |
| Battery voltage and alternator | car, truck, tractor | `VehicleTelemetry.battery_volts` | aux |
| Engine load | tractor, truck | `VehicleTelemetry.engine_load_pct` | engine, aux |
| GPS from world position, heading | every family | `VehicleTelemetry.gps_lat`, `gps_lon`, `heading_from_forward` | position |
| Odometer and hour meter | every family (hours published on truck and tractor) | `VehicleTelemetry.odo_step`, `hours_step` | position |
| Acceleration, yaw rate, impact | every family | `BaseVehicle._update_telemetry` | position |
| Axle load read off the springs | truck, tractor | `VehicleTelemetry.axle_load_kg` | truck, implements |
| Water surface (flat) and drown respawn | every level with sea | `src/water/water_surface.gd` | how-its-built |
| Wind field with gusts | car, truck, tractor | `src/levels/base/wind_field.gd` | conditions |
| SANDBOX ▸ WORLD presets (wind, direction, time of day) | session-wide | `src/levels/base/world_conditions.gd` | controls |
| Rain or weather | not modelled; a painted "Wet" ground exists | `Surface` | surfaces, simplifications |

## Input

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| One input per tick from keyboard, touch, gamepad or sloppyCAN | every family | `src/input/input_router.gd`, `vehicle_input.gd` | controls |
| Key easing (KEY RESPONSE) | local keys | `src/input/key_shaper.gd` | controls |
| Ignition gates the throttle; brake then reverse at a stop | every family | `InputRouter` | controls |
| SANDBOX ▸ VEHICLE switches (ABS off, diffs, parallel steer) | wheeled bodies with the hardware | `InputRouter.lab_raw` | controls |
| Lamps mirrored from the bridge, horn | every family | `src/vehicles/base/lamp_set.gd`, `horn.gd` | controls |
