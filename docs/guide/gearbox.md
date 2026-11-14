# Gearbox and shifting

<p class="lead">An engine is strong only in a narrow band of speeds, but a vehicle has to crawl
up a hill and also cruise on a motorway. The gearbox lets one engine do both, by changing how
many times the engine turns for each turn of the wheels.</p>

<div class="badges"><span class="label">Which vehicles have this</span>
<span class="badge yes" title="Six-speed automatics; the racing cars a six-speed sequential">Car</span>
<span class="badge yes" title="Six-speed automatics on the rigid trucks; twelve-speed automated gearboxes on the semis">Truck</span>
<span class="badge yes" title="A sixteen-speed powershift, or a stepless CVT">Tractor</span>
<span class="badge some" title="No gears, but it reads the same gear byte for forward, neutral and reverse thrust">Plane</span>
<span class="badge no" title="Its outdrive has forward and reverse, without gear changes">Boat</span>
<span class="badge no" title="Electric motors on the rotors">Drone</span>
<span class="badge some" title="No gears: the gear byte is its reverser">Train</span>
</div>

## What a gear does

On a bicycle, a small front sprocket and a big rear one make pedalling easy but slow: good for a
hill. A big front sprocket and a small rear one make it hard but fast. A gearbox does the same for
an engine.

Each gear has a [gear ratio](glossary.md#gear-ratio): how many times the engine turns for one
turn of the gearbox's output. After the gearbox, a second fixed set of gears, the
[final drive](glossary.md#final-drive), turns the wheels. Multiply the two and you have how many
times the engine turns for each turn of the wheels. In the `sedan`'s first gear that is about 18;
in its sixth, about 3.6.
<!-- sedan_spec.tres gear_ratios 4.5 ... 0.925; final_drive 3.9 (CAR_BASE): 17.6 and 3.6 -->

The same ratio works on torque, the other way round. A low gear turns the engine many times per
wheel turn and multiplies its torque by as much, so the wheels push hard but the vehicle moves
slowly. A high gear multiplies less, so the push is weaker but the speed is higher. A little of
the power is lost in the gears on the way: the game takes a tenth.
<!-- VehicleSpec.efficiency 0.9 on every shipped body -->

<div class="widget" data-widget="gear-speed"></div>

The game's gearboxes:

| Vehicle | Gears | Kind |
| --- | --- | --- |
| Cars, vans, rigid trucks | 6 | Automatic |
| Racing cars | 6 | Sequential |
| Semis | 12 | AMT |
| `tractor-kenney` | 16 | Powershift |
| `tractor-cvt` | none | CVT |

Each kind is explained further down this page; [Kinds of gearbox](gearbox-kinds.md) shows what
is inside each.
<!-- gear_ratios lengths: sedan 6, race 6, semi_spec.tres 12, tractor-kenney_spec.tres 16; tractor-cvt cvt_range_tops -->

## The gear byte: P, R, N and D

Every gearbox in the game is set by one number, the [gear byte](glossary.md#gear-byte), the same
one a real vehicle network uses:

- **N**, neutral: no gear, the engine turns freely.
- **D1 to D24**: a forward gear. A gearbox with fewer gears treats a higher number as its top
  gear.
- **R**: reverse.
- **P**: park. On a vehicle with a [park pawl](glossary.md#park-pawl), a steel tooth locks the
  gearbox's output. The cars, vans and the powershift tractor have one. The trucks do not: they
  park on their spring brakes, and P reads as N.
<!-- Drivetrain GEAR_N 0x00, GEAR_R 0xFF, GEAR_P 0xFE, TOP_GEAR 24; contract gear: "it engages the gearbox's park pawl where one is fitted (cars, vans, the tractor's powershift)... reads as N on a gearbox without one (the trucks park on their spring brakes)" -->

### Driving forwards and backwards from the keyboard

With the AUTOMATIC gearbox there is no gear lever. Pressing the
accelerator from a standstill selects drive. Holding the brake at a standstill selects reverse:
the brake key then drives the vehicle backwards, and the accelerator key becomes the brake.
Pressing the accelerator again at a standstill selects drive.
<!-- InputRouter local arbitration: brake_reverse at a standstill (REVERSE_ENGAGE_SPEED) requests R with throttle -brake_rev and brake = accel; accel at a standstill in R requests D1 -->

### Shifting by hand

With MANUAL chosen in the GARAGE and sloppyCAN not connected, you change gear yourself: **,** and
**.** on the keyboard, D-pad down and up on a gamepad, GEAR - and GEAR + on the touch screen.
Each press moves one step along R, N, 1, 2 and up to the top gear. The vehicle starts in N after
a spawn or a respawn, and when MANUAL is picked while it stands still; picked on the move, it
keeps the gear it is in. The accelerator drives in whichever direction the gear points, and the
brake only brakes: holding it at a standstill never selects reverse. With the accelerator held
down in N, the message NEUTRAL GEAR SELECTED names the button to shift up.
<!-- InputRouter.shift_step (the ladder, no wrap), reset_vehicle_cycles (_local_gear = N), arbitrate_local's manual branch; neutral_warning (NEUTRAL_NOTICE_PEDAL 0.9), Boot.neutral_notice; Drivetrain.top_gear; keys project.godot shift_down Comma, shift_up Period; ActionRegistry row "shift" pad dpad_down / dpad_up -->

While sloppyCAN is connected, its gearbox wins: the shift buttons do nothing, and the gear is
sloppyCAN's byte when it drives, or automatic when it sends no driving controls.
<!-- InputRouter._local_tick: the local gear acts only with `_manual_gearbox` and no bridge live; ActionRegistry "shift" bridge_owned -->

### Manual gears from sloppyCAN

sloppyCAN sends the gear byte as its `gear` signal. The GARAGE has a GEARBOX row: AUTOMATIC or
MANUAL.

- **Automatic**: the byte works like an automatic's lever. P parks, R reverses, and any drive
  gear means "drive", with the gearbox choosing the gear itself. A byte of 0 means no opinion: the
  vehicle drives forward when the accelerator is pressed.
- **Manual**: the byte is taken exactly. D3 means third gear, 0 means neutral, and the gearbox
  never changes gear by itself. The clutch is still worked for you.
<!-- InputRouter.arbitrate_bridge (manual: the exact byte) -->

## How the automatic chooses a gear

The automatic's rules are its [shift policy](glossary.md#shift-policy). They follow how real
automatic gearboxes behave, from measurements of a 2013 family car's six-speed.
<!-- docs/drivetrain.md The shift policy: the Malibu map [34] -->

- **Light pedal, early shifts.** Driving gently, the `sedan` changes up at about 1800 to 2000 rpm,
  keeping the engine slow and quiet. With the pedal fully down it holds each gear until about
  5900 rpm. In between, the shift point slides between the two.
  <!-- CAR_BASE light pair 1800 / 1150 (raised to 1961 for D1>D2 by the landing floor); sedan_spec.tres shift_up_rpm 5900 -->
- **Never hunting.** Each upshift must land the engine at least a tenth above the speed at
  which the gearbox would change down again, so it cannot flick back and forth between two gears.
  After each change it waits a moment before it may change again.
  <!-- ShiftPolicy landing floor 1.1; VehicleSpec.shift_dwell_s -->
- **Kickdown.** Press the accelerator past about four fifths of its travel and the automatic
  drops one or more gears at once, to the lowest gear it can use without hitting the redline
  straight away. The semis kick down only past almost full travel; the tractor and the racing cars
  never do.
  <!-- VehicleSpec.kickdown_pedal: past 0.8 on the converter automatics, 0.95 on the AMT, none on the powershift and sequential (docs/drivetrain.md table); ShiftPolicy.kickdown_ceiling_rpm 85 % of the redline -->
- **Hills.** The gearbox keeps an estimate of how hard the vehicle is working against the slope.
  On a climb it will not change up into a gear that could not hold the speed. Braking down a long
  hill, it changes down so the engine helps to brake.
  <!-- ShiftPolicy.on_grade (a 2 % grade's pull), holds_grade, the braked descent -->
- **Starting gear.** A heavy truck or tractor does not always start in first. The semis' and the
  tractor's gearboxes pick the highest gear that can still pull away cleanly, judged by the weight
  they are pulling and the slope. A semi with no trailer starts in sixth on the flat, and with a
  full trailer in third.
  <!-- ShiftPolicy.start_gear, start_gear_max (semis 6, tractor 7); docs/drivetrain.md: bobtail semi D6, with the 24 t box D3, tractor D7 bare and D6 with the farm tipper -->
- **Skipping gears.** With twelve or sixteen close gears, stepping through them one by one would
  waste time. The semis and the tractor skip gears where the load allows, for example sixth
  straight to eighth.
  <!-- VehicleSpec.skip_shifts on the semis' AMT and the tractor's powershift; "the bobtail semi from its D6 start D6>D8" -->

## What happens during a change

A gear change cannot happen instantly: the engine has to change speed to suit the new gear. How
the gearbox handles that moment depends on its kind.

- **Automatic (cars, vans, rigid trucks).** Two clutches inside the gearbox hand the drive from one
  gear to the next, one letting go as the other takes up, so the drive never stops. The engine is
  briefly given less fuel so it can slow to its new speed.
- **Powershift (the tractor).** Also clutch to clutch, but with no cut in fuel. The tractor's drive
  goes on pushing through the change, and you can feel the jolt as each gear takes up.
- **Automated manual (the semis).** A computer works a clutch and an ordinary gearbox. It cuts the
  fuel, opens the clutch, changes gear, closes it, and brings the fuel back gradually. The drive
  stops for a moment on every change.
- **Sequential (the racing cars).** A short ignition cut, then the clutch snaps shut.
<!-- docs/drivetrain.md The shift's handover: Drivetrain.handover_rate, handover_fuel; shift_cut_s, shift_torque_ramp_s -->

## The stepless gearbox

The `tractor-cvt` has no fixed gears at all. Its [CVT](glossary.md#cvt) changes its ratio
smoothly, from zero up to its fastest, by splitting the engine's power between gears and an oil
pump. The accelerator does not ask for fuel: it asks for a road speed, and the gearbox sets the
ratio that gives it while the engine's governor holds the engine speed. A ratio of zero means
the wheels are held still with the engine running, which is how the CVT tractor stands still on a
slope. The gear byte it publishes is the mechanical range in use, D1 to D4.
<!-- docs/drivetrain.md The CVT; Drivetrain.is_cvt, cvt_ratio_step, standstill_hold; contract gear (out): "On a CVT ... a D byte is the mechanical range engaged, D1-D4" -->

## What the game leaves out

- **No gear lever or paddles**: shifting by hand is one step per button press, and there is no P
  on the manual ladder (the parking brake holds instead).
- **No clutch pedal**, so no stalling or slipping the clutch by hand.
- **No crunching gears or missed shifts.**
- **No range or splitter buttons** on the semis' twelve gears: the automated gearbox chooses.

## What you see in sloppyCAN

| Signal | Direction | Unit | What it shows |
| --- | --- | --- | --- |
| `gear` | in | enum | The gear byte: N, D1 to D24, R, or P. In AUTOMATIC it works as a lever; in MANUAL it is the exact gear. Car, truck, tractor, plane, train. |
| `gear` | out | enum | The gear actually engaged. P only where a park pawl is fitted; on the CVT, the range in use. |
| `gear_ratio` | out | ratio | Truck and tractor: the engaged gear's ratio, without the final drive. On the CVT it moves smoothly. 0 in N or P. |
| `rpm` | out | rev/min | Engine speed: watch it drop at each upshift. |
| `status` | out | bitfield | Bit 3 is reverse, bit 4 neutral. |
<!-- contract/carlito_contract.json: gear (in and out), gear_ratio, rpm, status bits 3 and 4 -->

## Try it in the game

<div class="box try">
<p class="box-title">Try it in the game: light pedal and full pedal</p>

1. Pick the `sedan` on **Flatland** with the dashboard showing (**F2**).
2. Pull away with a light, steady pedal. Watch the gear and the rev counter: it changes up early,
   below about 2000 rpm, and is in a high gear by 60 km/h.
3. Stop, then pull away with the pedal fully down. Each gear now runs to near 6000 rpm before the
   change.
4. Cruise at 60 km/h with a light pedal, then press it fully down: the automatic kicks down
   several gears at once and the revs jump.

</div>

## Related

- [Kinds of gearbox](gearbox-kinds.md): what is inside a manual, an automatic, a CVT and the
  others.
- [The engine](engine.md): the torque the gears multiply.
- [Clutch and torque converter](coupling.md): what slips while the gears change and the vehicle
  pulls away.
- [Glossary](glossary.md): every term on this page.
