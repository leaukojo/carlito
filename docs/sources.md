# Sources

The sourced figures behind the vehicle specs and the references they cite. Reference data, read
on demand: the tours and derivations are `docs/vehicles.md` (its header lists the rest).

## Sourced figures

Each figure is graded:
- **sourced**: a primary document, read;
- **secondary**: a search summary or forum quoting a primary, not opened;
- **estimate**: reasoned from the sourced ones.

The bracketed numbers, here and in the vehicle docs, are § Reference list.

*Crank inertia* (`engine_inertia`), measured at the crank. It includes the flywheel or flexplate
and, on a converter body, the impeller side:

| Class | Bodies | J (kg·m²) | Basis |
| --- | --- | --- | --- |
| Car petrol 1.2-2.0 L, converter | `CAR_BASE` | 0.20 | sourced anchor: a 2013 Malibu's 2.5 L I4 with its converter's impeller side measures 0.20 by spin-down (engine 0.161, converter 0.0585) [33], a larger engine than the class, so 0.20 sits at its top. A whole engine measures 0.149 at 1.0 L and 0.125 at 1.2 L, the crankshaft 0.014-0.015 of it [1]; a car converter's impeller is 0.092 [2]. Generic car engines at 0.35 [3] and a 2.5 L I4 at 0.373 [4, secondary] disagree with the measurement |
| Sports, converter | `sedan-sports`, `hatchback-sports` | 0.18 | estimate: a lighter rotating assembly, the same impeller |
| Race, sequential and clutch | `race`, `race-future` | 0.06 | estimate: a crankshaft alone is 0.014-0.027 [1], plus a light flywheel and a small multi-plate clutch |
| Van diesel 3.2 L, converter | `VAN_BASE` | 0.40 | estimate, band 0.35-0.45: twice a 2.5 L petrol I4's measured 0.20 with its impeller side (spin-down; engine 0.161, converter 0.0585) [33], for a five-cylinder diesel's heavier crank and flywheel. No 3-4 L diesel figure found |
| Medium diesel 6-9 L, Allison-class | `TRUCK_BASE` | 1.5 | sourced anchor: Volvo Penta TD640VE (5.48 L), total mass moment of inertia 1.50 [5]. A 7 L genset lists 2.60 [6, secondary] |
| Heavy diesel 11-13 L, AMT | both semis | 3.0 | estimate, between 1.50 at 5.5 L [5] and 4.20 for the 16.1 L TAD1641GE [7] |
| Tractor diesel 4.5-7 L, powershift | `TRACTOR_BASE` | 1.5 | sourced anchor: the same 5.5 L, 1.50 [5] |

*The gear-1 mass factor while locked* (computed; r = 0.36 m, the tractor's driven 0.66 m rear; G1
is first gear times the final drive, D3 on the tractor). It is `J G1²` over the body's `m r²`:

| Body | G1 | J G1² (kg·m²) | Driven wheels' own I | Body m r² | Added |
| --- | --- | --- | --- | --- | --- |
| `sedan` | 17.55 | 62 | 2.4 | 149 | +41 % |
| `race` | 13.44 | 11 | 2.4 | 117 | +9 % |
| `delivery` | 15.56 | 97 | 6.0 | 544 | +18 % |
| `garbage-truck` | 14.00 | 294 | 6.0 | 1037 | +28 % |
| `semi` + 24 t | 19.01 | 1084 | 6.0 | 4147 | +26 % |
| `tractor-kenney` | 39.32 | 2319 | 180 | 3049 | +76 % |

In top gear it is small (+1.7 % on the `sedan`). A slipping coupling decouples the crank. A real
vehicle has the same term, so a
body behind its reference is fixed from its own data (curve, gearing), never by shaving inertia.

*The converter:*
- **Stall torque ratio:** about 2.0 on cars, ~2.5 on 1990s four-speeds [8], with a typical model
  default of 2.23 [9]. Allison 3000 trucks: 1.98-2.20 [10, secondary]. It ships at 1.0
  (`docs/drivetrain.md` § Converter).
- **Coupling point:** at a speed ratio of ~0.9. The ratio is 1.07 at 0.87, 1.02 at 0.92 and 1.00
  at 0.94 [9].
- **Capacity:** K = speed / √torque. It is nearly flat to a speed ratio of 0.8 (12.3 to 14.6),
  then climbs: 16.3 at 0.87, 22.1 at 0.94, 50 at 0.97 [9]. The truck shape is assumed the same.
- **Overrun:** it runs on its own K curve [11]. No figure was found, so `OVERRUN_CAPACITY` 0.5 is
  an estimate.
- **Lock-up:**
  - 6+ speeds open the converter only for the launch [8]; 1st-range lock-up is an Allison option
    [14, secondary].
  - It releases as the throttle closes and on braking, so a locked engine cannot stall [12]. The
    ZF 8HP decouples at a standstill in D [13].
- **Stall speed:** typically 1800-2800 rpm [15]. An unverified AT545 owner report puts a truck at
  1300-1400 rpm [16], near the derived 1250 on the Kenney trucks.

*The friction clutch:*
- **Capacity:** about 1.5x the engine's peak on cars and 2x on trucks [17]; OE ratings carry a
  20 % margin [18]. A wet powershift pack takes the truck's 2.0 (estimate).
- **AMT launch:** a heavy truck's AMT holds the crank about 300 rpm over idle [19].
- **Powershift modulation:** a fill, then a pressure ramp [20]. No duration was found, so
  `launch_engage_s` 0.8 is an estimate.

*Idle and holds:*
- **Loaded idle:** the ECU adds air when a drive range is selected, so idle stays put. Without that
  signal it falls under 800 rpm and recovers [21]. Owners report 50-100 rpm dips [22, secondary].
- **Hill-start assist:** it holds about 1 s on a car (Honda) [23] and 3 s on a truck (Volvo VN)
  [24]. It releases once the driver asks to drive and the engine torque passes what holds the grade
  [23, 24, 25].
- **Tractor:** Valtra's HillHold holds a powershift tractor until the drive pedal is pressed [26].

*Engine friction:* `docs/drivetrain.md` § Motoring and friction. It is Volvo Penta friction power: [5] and [7].

*The heavy vans' drivetrain* (`VAN_BASE`: `delivery`, `delivery-flat`, `ambulance`): a Ford
Transit 3.2 L five-cylinder diesel behind the 6R80 six-speed automatic, the class of a 4.7 t
Transit 350 HD. The ambulance is a van-based box ambulance on the same drivetrain.

| Figure | Value | Grade |
| --- | --- | --- |
| Engine, gearbox | 3.2 L five-cylinder diesel, every Transit engine behind the 6R80 [27] | sourced |
| Peak torque | 470 N·m [27]; held over 1750-2500 rpm [29], at least 90 % over 1500-2750 [30] | sourced; the band secondary |
| Rated power | 147 kW at 3000 rpm [29], which is 468 N·m: the plateau holds to rated speed | secondary; the N·m computed |
| Ford's "90 % from 1,700 to 3,500 rpm" [27] | not used: 423 N·m at 3500 rpm is 155 kW, past the rating | sourced |
| Idle, the curve's zero | 750 rpm at half the peak (`TRUCK_BASE`'s idle share), straight to 423 N·m at 1500; a governor droop from rated speed to nothing at 4000 rpm | estimate |
| Ratios | 4.171 / 2.340 / 1.521 / 1.143 / 0.867 / 0.691, reverse 3.403 [28] | secondary |
| Axle | 3.73 limited-slip, on a 4.7 t dual-rear-wheel Transit 350 HD with this engine [31]; 3.31 / 3.73 / 4.10 on other diesel Transits [32] | secondary |
| Overall | first 15.56:1; top 52.7 km/h per 1000 rpm at r 0.36 m, so the top speed is drag's, not the droop's | computed |
| Friction, clutch, lock-up | 0.10 of peak at idle (`TRUCK_BASE`'s, no van figure found); the car OE clutch margin 1.5 [17]; lock-up from D1, as on any 6+ speed [8] | estimate; estimate; sourced class rule |
| Stall speed | the derived 1562 rpm (`Drivetrain.stall_rpm`): `(idle / stall)²` 0.23, against 0.28 on `TRUCK_BASE`. No van figure found | computed |

`shift_up_rpm` 3300 sits past rated speed, where each step's next gear meets this gear's wheel
torque on the droop (D1 > D2 ~3440 rpm, D5 > D6 ~3200), and lands the 1.78 D1 > D2 step at 1850
rpm, in the band. `shift_down_rpm` 1400 sits under the band's 1500 edge.

*The Kenney trucks' drivetrain* (`TRUCK_BASE`), medium-duty for their 7.5-8 t: a Class 8 L9 (1695 N·m)
creeps harder on them (computed) than a 30 % pedal asks.

| Figure | Value | Grade |
| --- | --- | --- |
| Engine | Cummins B6.7 (2021) 325 hp, 750 lb-ft (1017 N·m) at 1800 rpm, governed 2600 ([brochure](https://mart.cummins.com/imagelibrary/data/assetfiles/0064235.pdf)): 890 N·m rated. Idle 700 at half the peak, 0.81 of it at 1200, rated speed to nothing at 2900 | sourced; computed; estimate |
| Ratios | Allison 3000 / 3200 close: 3.49 / 1.86 / 1.41 / 1.00 / 0.75 / 0.65, R 5.03 ([Allison](https://pprod.allisontransmission.com/en-gb/transmissions/models/3000-series)) | sourced |
| Axle, tyre | 5.57 on a Mack MD7 rear loader, 6.7 L and 3000 RDS ([listing](https://www.brucknertruck.com/inventory/2026-mack-md7-base-68364/)); 315/80R22.5 at 0.500 m loaded ([Michelin](https://business.michelin.ca/en/tires/michelin-x-multi-z-315)); `firetruck` takes the same | secondary, search summaries; estimate |
| At the drawn 0.36 m | `final_drive` 5.57 × 0.36 / 0.500 = 4.010, the same `G / r`: first 38.9 per metre, top 52.1 km/h per 1000 rpm. Creep at rest `T(stall) (idle / stall)² G η / r`, stall 1250 rpm: the creep of `docs/drivetrain.md` § Creep | computed |

| The tractor's wheels, `I = m (κ r)²` at the drawn radius (tyre and rim; ballast does not turn) | Value | Grade |
| --- | --- | --- |
| Tyres, MultiBib 650/65R38 / 540/65R28; rims 20 × 38 / 16 × 28 | 207 / 83 kg ([rear](https://onlineshop.bohnenkamp.de/en/tyre-michelin-multibib-650-65-r-38-13327680), [front](https://onlineshop.bohnenkamp-benelux.com/en/tyre-michelin-multibib-540-65-r-28-13327620): light, other makes 106-135 kg); 160 kg ([Deere AL205108](https://shop.deere.com/us/product/AL205108%3A-Rim%2C-20-X-38/p/AL205108)) / ~60 kg (off [Deere's 16 × 30](https://shop.deere.com/us/product/0250282713%3A-Rim%2C-16-X-30/p/0250282713), 64 kg) | secondary / sourced, one retailer; secondary / estimate |
| κ, then I rear / front | 0.75 (half the tyre at its tread, half over the sidewall annulus, the rim at 0.89 of its bead seat; no measured figure found); 367 kg × (0.75 × 0.66)² = 90, 143 kg × (0.75 × 0.44)² = 16 kg·m² | computed, estimate model |
| Rear tyre rate (`spring_rate_rear`), 650/65R38 157D at its rated 4127 kg, 1.6 bar | 72.8 in across, 32.6 in static loaded radius: 9.65 cm down, a secant 420 kN/m [62] | secondary, one retailer's data sheet; computed |
| Steering rate (`steer_speed`): a hydrostatic unit turns the wheels as fast as the hand winds | a Fendt 516 Vario takes 5 1/3 turns lock to lock [60]; a quick human hand ~720 deg/s, NHTSA's fishhook rate [61]; their ratio over the 960 deg centre to lock | sourced; secondary |
| Brakes inboard of the final reduction | [Case IH Puma](https://www.ultimatespecs.com/tractor-specs/caseih/caseih-puma-155-2008): "differential" wet discs; on the differential shaft, upstream of the planetary reduction ([Dana US 4,646,880](https://patents.google.com/patent/US4646880)) | secondary, no workshop manual |

| Implement draft (`ImplementBase.draft_rating` / `draft_shape`); speeds in km/h, forces in kN | Value | Grade |
| --- | --- | --- |
| Mouldboard plough, ASABE D497.7's row (plough.gd `DRAFT_SHAPE`) | A 652, B 0, C 5.1, in N per m width per cm depth; soil texture factor fine 1.0, medium 0.70, coarse 0.45 [45] | secondary |
| Its field speed range | 5.0-10.0, typical 7.0, the reference speed (`TractorTelemetry.DRAFT_S_REF_KMH`); held above the top [46] | sourced; the table read does not name D497 |
| Plough working depth | 25 cm, drawn, for the 4 × 14" (1.42 m) cut: furrow width over depth ~1.4, inside a design slide's 1.1-1.5 [47]; a 4-furrow plough measured in work ran 1.4 m at 28 cm [51] | estimate |
| Plough rating (plough.gd `RATED_DRAFT_N`, also `draft_max_force`) | medium soil × the row at 7 × 1.42 m × 25 cm, 22.41; g(0) 0.72 | computed |
| Power harrow | 3 m, 6-15 cm, speeds 3-12, rotors at 285 / 411 rpm off a 1000 rpm PTO; draught 4-13 over the trials [48]; 5.7 at 3 rising to 10.0 at 9 [49] | the trials sourced (abstract); both draught figures secondary, unverified against the paper's tables |
| Harrow rating (harrow.gd `DRAFT_SHAPE`, `RATED_DRAFT_N`) | the line through that pair, per m of width, held above 9; over the drawn 3.0 m, the trials' own width, 8.57; g(0) 0.41 | computed, estimate |

| Implement mass and ground support (`ImplementBase.mass_kg` / `ground_share`), Category 2 | Value | Grade |
| --- | --- | --- |
| Linkage (`headstock.tscn`) | lower pins 0.86 m apart at the ball centres (34 in [58]; 32 in between the link ends [59]); mast 0.533 m, inside the class's 15-24 in [59] | secondary |
| Plough, 4 × 14" conventional | 900 kg: Kverneland AD Variomat 85 at 4 furrows, 80-100 hp [50] | sourced |
| Its ground share | 0.35: the depth wheel carried about a third of a 2180 kg 4-furrow plough's weight, top link free, in work [51] | sourced, read off a graph |
| Power harrow, 3.0 m with packer | 1550 kg: Kverneland M 3.0 at 1550 (its summary table says 927) [52]; Amazone KE 3002 at 1530 with its roller, 1040 without [53]; Kuhn HR 3030 at 1679, Cat 2/3 [54] | sourced; secondary |
| Its ground share | 0.8: the roller sets the depth and carries the machine | estimate |
| Rotary cutter, 7 ft | 620 kg: Land Pride RCR2684 at 1370 lb with a single tail wheel, Cat II/III, 60-130 hp [55]; Woods BB84.40 at 1041-1132 lb [56] | sourced; secondary |
| Its ground share | the mass centre's lever over the tail wheel's (1.21 / 2.8 m behind the pins, off `mower.tscn`), the top link floating | computed; the float an estimate |
| Spreader, ~800 L single disc | 150 kg empty, Demir DMR SF 800 [57]; carried full of AN prill at 950 kg/m³ | sourced |
| Front-axle ballasting minimum (the `hitch` pass's guideline) | ≥ 20 % of total weight on the front axle to keep the tractor steerable: John Deere operator's manual, "Select Ballast Carefully" | sourced, no link recorded |

*Surfaces* (`Surface`, `src/levels/base/surface.gd`). Grip is the all-season tyre's peak over its
dry-asphalt peak (Wong's 0.8-0.9, read as 0.85 [63]); drag is rolling resistance added over a car
tyre's 0.013 on asphalt [68]. A class scales grip per surface; drag is tyre-blind.

| Surface | Grip | Drag | Basis | Grade |
| --- | --- | --- | --- | --- |
| WET | 0.55 | 0 | the bottom of Wong's wet asphalt, 0.5-0.7 [63]; between Car 15's 0.6 (a clear slip spike, still controllable) and 0.5 (spins the car out), so it has no par | secondary |
| PAD | 0.95 | 0 | dry concrete grips as asphalt [63], less the skyport's paint | estimate |
| GRAVEL | 0.71 | 0.01 | Wong's gravel 0.60 [63]; rolled gravel 0.02 [68] | secondary |
| DIRT | 0.80 | 0.04 | Wong's dry earth road 0.68 [63]; unpaved road 0.05 [68] | secondary |
| GRASS | 0.50 | 0.06 | a street tyre ~0.35 on dry grass against ~0.72 on asphalt [64]; clover verges brake at ~60 % of rye-grass [65]; drag Wong's car on medium-hard soil, 0.08 [63] | estimate |
| SAND | 0.60 | 0.05 | firm (damp, packed) beach sand: 0.04-0.08, loose 0.2-0.4 [69]; grip none found | drag secondary, grip estimate |
| ROCK | 0.70 | 0.01 | none found; drag as setts, 0.015 [68] | estimate |
| MUD | 0.45 | 0.10 | grip under Wong's wet earth road (0.55, so 0.65) [63], for deep soft mud; drag below | grip estimate, drag computed |
| FIELD | 0.50 | 0.06 | grip a road tread in tilled soil, none found; drag below | grip estimate, drag computed |
| SNOW | 0.45 | 0.02 | hard-packed: snow braking puts the winter references at 22.3-22.7 m (mu ~0.44) and the all-season tyres at 22.6-24.4 [66], a quarter behind with summer tyres at twice the winter's distance in a blog's comparison [67]; Wong's 0.20 [63] is that summer tyre; drag none found | secondary, [67] indicative (no method stated); drag estimate |
| ICE | 0.12 | 0 | Wong's 0.10 [63]; black ice at most 0.10 in Bosch [68] | secondary |

MUD and FIELD drag: Zoz and Grisso's radial motion resistance `1.2/Bn + 0.5 s/sqrt(Bn) + 0.03` [45]
at the curve's 0.12 peak slip, on a 205/55R16 at a 1.15 t car's corner load (deflection 0.15 of
its section, an estimate), cone index 450 (wet soft) and 900 kPa (tilled) [45]: 0.109 and 0.073 in
all, inside Bosch's field band 0.10-0.35 [68] and at its foot. `Bn = (CI b d / W)(1 + 5 δ/h) /
(1 + 3 b/d)` is D497's form, not read in a primary. COMPROMISE: tyre-blind, so a big tyre pays the
car's figure (the tractor's own law gives 0.087 and 0.061 in all, over its 0.02); a per-tyre figure
is a fitment law (the mobility number), a later `GroundDriveSpec` field.

*Tyre classes* (`src/vehicles/tyres/`, each derivation in its `.tres` comment):

| Figure | Basis | Grade |
| --- | --- | --- |
| Summer `dry` 1.10 | the best all-season 6.5 m behind the summer reference's 37.0 m dry, SUV size [70]; car sizes run closer | secondary; 1.10 an estimate |
| Summer and Winter on snow | as SNOW above [66, 67] | secondary |
| Winter and Summer on ice | ice braking: winter 17.7, all-season 26.2, summer 35.5 m [71] | secondary |
| Studded on ice | new studs about twice friction tyres on severe ice, worn studs as studless [72]; 1.6x a modern studless taken | secondary; the figure an estimate |
| Mud on wet asphalt | wet-tar braking on a Hilux: mud-terrains 38.7 m, ~9 m past highway-terrains [73] | secondary |
| Soil factors of every class (Mud, R-1W lug, slick ...) | no published lug-against-road-tread figure found; D497 carries no tread term | estimate |
| `crr_factor` | EU label C1 classes: A ≤ 6.5, B 6.6-7.7, C 7.8-9.0, D 9.1-10.5, E ≥ 10.6 N/kN [74]; summer B, all-season C, winter C's top, mud E's floor | sourced bands; each class's band an estimate |

*Aero balance* (`downforce_front`, `race` and `race-future`; `docs/vehicles.md` § Aero balance):

| Figure | Basis | Grade |
| --- | --- | --- |
| The centre of pressure sits just behind the CG | a race car is set up with the aero resultant behind its CG, so a mid-engined car wants more downforce at the rear; an F1 car carries ~45 % of its downforce at the front axle line [75]. The centre of pressure closely matches the CG, wants a slight rear bias in low and mid-speed turns, and can sit neutral to slightly forward at high speed [76] | secondary: engineering articles, read; Katz and Milliken not opened |
| `downforce_front` 0.40 against a 0.42 weight split | two points of rear bias, inside "closely matches" and on the stable side [75, 76] | estimate |

*Crosswind* (`side_area`, the side force's `aero_centre`; `VehicleMath.air_force`, `gen_kenney_vehicles.gd`
`CY_SIDE` / `SIDE_CP_FRAC`, each hand-built spec's header):

| Figure | Basis | Grade |
| --- | --- | --- |
| Side force linear in yaw, set mostly by height | it rises about linearly over a wide yaw range, its gradient alike within a class and size, height dominating as slender-wing theory gives with the car's ground image [77]. With the image, that theory's slope is `q π h²` per radian (computed) | secondary |
| `CY_SIDE` 1.2 broadside on the side area | a road vehicle's side-force coefficient on its projected side area rises to 1.17 (fitted) to 1.34 (CFD) and holds from ~75 to ~165 degrees of yaw; on the frontal area the same reads 6.5, which is why high-sided figures look large [78] | sourced (CFD) |
| One `side_area` for broadside and the small-yaw slope | the `sin(yaw)` form makes them one figure. On a sedan-sized 4.4 × 1.38 m box, 1.2 × 0.82 × L × H is 5.97 m² against `π h²` 5.98; the Kenney bodies, shorter, sit at 0.4-1.3 × `π h²` (`gen_kenney_vehicles` prints both) | computed |
| A trailer's side area is its full side | cab and trailer take side forces of about the same size at 0-16 degrees of yaw despite the trailer's length; the side force's line of action sits just below each body's mid-height [79] | sourced |
| The side force acts ahead of the COM | most road vehicles have their centre of pressure in the front half, typically ahead of the neutral steer point, so a crosswind yaws them downwind [80]. `SIDE_CP_FRAC` 0.25 of the wheelbase ahead of the axles' midpoint | sourced; the fraction an estimate |
| Tanker barrel 0.7 | a circular cylinder's drag coefficient climbs back to ~0.7 near Re 3.5e6 past the drag crisis and holds [81]; the barrel at a 13 m/s crosswind sits at Re 1.5e6, below that plateau, so 0.7 is the upper end | secondary; the figure an estimate |

*Roll steer* (`GroundDriveSpec.roll_steer_front` / `_rear`, `gen_kenney_vehicles.gd`): degrees of
wheel steer per degree of the axle's suspension roll, + = toward understeer on either axle (the
front out of the turn, the rear into it). Gillespie's ε (+ = toward the side the body rolls to)
converts as `ε_f = front`, `ε_r = −rear`; MRA's axle coefficient signs the rear the same as here
and the front opposite.

| Figure | Basis | Grade |
| --- | --- | --- |
| Roll is the axle's against the chassis, not the body's world roll | the axle roll steer coefficients are defined on axle roll relative to the chassis; a positive rear coefficient is understeer [82] | sourced |
| Twist-beam rear 0.036 | an OEM baseline twist beam (ADAMS, correlated with the physical K&C rig) steers both rear wheels 0.14 deg into the turn at 3.9 deg of body roll [83] | sourced |
| Strut / double-wishbone front 0.10 | "typical near design height", varying a lot between well-handling cars; one reply calls 0.1 a little high [85]. Inside the compilation's front band, +0.2 (understeer) to −0.1 [84] | secondary |
| Multi-link rear 0.05 | mid of the compilation's rear band, +0.13 (understeer) to −0.06 [84]; no per-type figure found | secondary band; the figure an estimate |
| Leaf-sprung solid rear 0.10 | upper half of that band: a live axle is laid out for roll understeer, the leaf's front eye set low so the wheel moves forward in jounce [87] | secondary band; the figure an estimate |
| The rear band's sign | the compilation names no turn or roll direction; the twist beam's measured understeer [83] and the live-axle layout [87] both read its + end as understeer | not confirmed in a primary |
| Open-wheelers, trucks, tractor 0 | no figure found; race kinematics are laid out for minimal toe change, and a truck's leaf axle is the candidate | estimate |

*Linear understeer* (the step pass's K at its slowest speed, `docs/vehicle_measurements.md` § Step steer):

| Figure | Basis | Grade |
| --- | --- | --- |
| K band 0.7-8.2 deg/g, mean 4.4 (FWD 4.2, RWD 4.7) | US vehicles at a lateral acceleration of 0.15 of g [84]; no band split by class was found | secondary |
| Roll steer's share | 1.0 of an illustrative 4.1 deg/g budget (front 0.6, rear −0.4 in the per-axle K convention, K = front − rear); roll camber 1.2, compliance steer 0.5 (side-force 0.4, aligning-torque 0.1) and aligning torque 0.4 more [86] | secondary |

## Reference list

1. Ubysz, "Problems of rotational mass in passenger vehicles", Transport Problems 5(1), 2010, Table 1: http://transportproblems.polsl.pl/pl/archiwum/2010/zeszyt1/2010t5z1_04.pdf
2. Honda CR-V converter impeller inertia, arXiv 2305.15216: https://arxiv.org/pdf/2305.15216
3. SimulationX automotive powertrain tutorial: https://doc.simulationx.com/4.3/1033/Content/Tutorials/AutomotivePowertrain.htm
4. "Impact of Engine Inertia on P2 Mild HEV Fuel Consumption", WEVJ 15(5) 220, 2024: https://doi.org/10.3390/wevj15050220
5. Volvo Penta TD640VE technical data (inertia 1.50 kg·m²; friction power 17-26 kW at 1800-2400 rpm): https://sra-moteur.com/uploads/catalogue/produits/documentations/td640ve-td640ve.pdf
6. Volvo Penta TAD734GE data sheet: https://www.scribd.com/document/457581321/TAD734GE
7. Volvo Penta TAD1641GE technical data (inertia 4.20 kg·m²; friction power 36 / 53 kW at 1500 / 1800 rpm): https://www.wincogen.com/wp-content/uploads/PD/Engines/VOLVO_TAD1641GE.pdf
8. Middelmann, "The Torque Converter as a System", Schaeffler (LuK) symposium: https://www.schaeffler.com/remotemedien/media/_shared_media/08_media_library/01_publications/schaeffler_2/symposia_1/downloads_11/6_Torque_Converter.pdf
9. MathWorks Powertrain Blockset, Torque Converter block: https://www.mathworks.com/help/autoblks/ref/torqueconverter.html
10. Allison 3000 stall torque ratios, quoted on a forum: https://www.skoolie.net/goto/post?id=7439134
11. ADVISOR automatic transmission model validation (NREL): https://adv-vehicle-sim.sourceforge.net/NewAutoTX.html
12. Lock-up release: US 4,618,041 (https://patents.google.com/patent/US4618041A/en) and US 7,238,142 (https://patents.google.com/patent/US7238142B2/en)
13. Audi technology portal, tiptronic (ZF 8HP): https://www.audi-technology-portal.de/en/drivetrain/transmission-technologies/tiptronic_en
14. Fleet Equipment, "Allison continues to optimize for 2011": https://www.fleetequipmentmag.com/?p=82312
15. Stall speed glossary: https://www.youcanic.com/glossary/stall-speed/
16. An AT545 owner report, seen only in a search summary (unverified).
17. Maki and Iwasaki, "On the transmitted torque of automotive friction clutches", Trans. JSME 18(70), 1952: https://ndlsearch.ndl.go.jp/books/R000000004-I10033763
18. Phoenix Friction, clutch torque capacity ratings: https://www.phoenixfriction.com/t-Clutch-Kit-Torque-Capacity-Ratings.aspx
19. Eaton, US 9,783,181 B2: https://patents.google.com/patent/US9783181B2/en
20. Caterpillar, US 5,467,854: https://patents.google.com/patent/US5467854A/en
21. Saab WIS, Motronic 2.8.1 idling compensation: https://saabwisonline.com/900/1994/2-engine/motronic-2-8-1/technical-description/idling-compensation
22. Ranger Station forum, D/P rpm drop: https://www.therangerstation.com/forums/threads/d-p-rpm-drop.164763
23. Honda Hill Start Assist: https://global.honda/en/tech/Hill_Start_Assist/
24. Volvo VN hill start assist: https://static.nhtsa.gov/odi/tsbs/2019/MC-10169013-9999.pdf
25. Robert Bosch, EP 2 203 334 B1: https://patents.google.com/patent/EP2203334B1/en
26. Valtra, "What exactly is the Powershift Revolution": https://valtra.co.uk/blog/technology/what-exactly-is-the-powershift-revolution.html
27. Ford Motor Company, press release, 2012-12-10, "Advanced, Fuel-Efficient 3.2-Liter Power Stroke Turbo Diesel Makes North American Debut in All-New 2014 Ford Transit", reproduced at https://www.firehouse.com/apparatus/press-release/10839682/ford-motor-media-advanced-fuel-efficient-32-liter-power-stroke-turbo-diesel-makes-north-american-debut-in-all-new-2014-ford-transit
28. Wikipedia, "Ford 6R transmission": https://en.wikipedia.org/wiki/Ford_6R_transmission
29. Wikipedia, "Ford Duratorq engine" (3.2 L Puma): https://en.wikipedia.org/wiki/Ford_Duratorq_engine
30. DieselHub, "3.2 Power Stroke": https://www.dieselhub.com/halfton/3.2-powerstroke.html
31. Dealer listing, 2019 Transit 350 HD DRW cutaway (3.73 limited-slip, 10,360 lb GVWR): https://www.comvoy.com/work-truck/kenosha-wi/used-2019-ford-transit-350-hd-service-utility-van-18061317
32. Parts and dealer listings for 3.31 / 3.73 / 4.10 diesel Transit axles, seen only in search summaries: https://allusedparts.com/ford/transit_350/2017/rear_axle_assembly/
33. Newman, Kargul, Barba (US EPA), "Benchmarking and Modeling of a Conventional Mid-Size Car Using ALPHA", SAE 2015-01-1140: https://19january2021snapshot.epa.gov/sites/static/files/2016-10/documents/2015-01-1140.pdf
34. Newman, Kargul, Barba (US EPA), "Development and Testing of an Automatic Transmission Shift Schedule Algorithm for Vehicle Simulation", SAE 2015-01-1142 (the Malibu's measured shift map, Fig. 11; ALPHA's suggested hold times and downshift ceiling): https://19january2021snapshot.epa.gov/sites/static/files/2016-10/documents/2015-01-1142.pdf
35. Wikipedia, "GM 6T40 transmission" (secondary): https://en.wikipedia.org/wiki/GM_6T40_transmission
36. Volvo Trucks, fact sheet "I-Shift drive modes", 2024: https://stpi.it.volvo.com/STPIFiles/Volvo/FactSheet/DRM-E,DRM-BE_Eng_06_331992824.pdf
37. Volvo Trucks North America, "Operator's manual, I-Shift transmission", PV776-20906026, 2007: https://hhrvresource.com/sites/default/files/dfiles/VolvoOperatorsManualI_Shift_PV77620906026.pdf
38. Volvo Trucks North America, D13 engine brochure (cruise 1250-1500 rpm, never above 1550): https://www.volvotrucks.us/media/vtna/files/shared/powertrain/revised4147-101-volvo-d13-engine-brochure-low-res.pdf
39. Massey Ferguson, "Innovation", AutoDrive (Power 2100 rpm, Eco 1500 rpm): https://www.masseyferguson.com/en_za/farming-technology/innovation.html
40. Farmers Weekly, "MF's new developments improve efficiency", 2001-02-16 (Dynashift AutoDrive): https://www.fwi.co.uk/news/mfs-new-developments-improve-efficiency
41. Jaguar Land Rover, US 11,724,688 B2 (torque and inertia phases ~0.15-0.5 s each): https://patents.google.com/patent/US11724688B2/en
42. Ford Global Technologies, US 10,343,690 B2 (inertia-phase output torque set by the oncoming clutch): https://patents.google.com/patent/US10343690B2/en
43. Zhang et al., "Study on Shifting Performance of Tractor Multi-Clutch under Different Engagement Rules", Agriculture 14(2) 254, 2024 (a simulation; abstract read): https://ideas.repec.org/a/gam/jagris/v14y2024i2p254-d1333372.html
44. GM Global Technology Operations, US 9,327,733 B2 (engine torque held reduced through the inertia phase): https://patents.google.com/patent/US9327733B2/en
45. Hefele and Oksanen, "EcoTIM: Fuel-saving multi-brand tillage with ISO 11783 TIM", arXiv 2604.17991, 2026 (its draft model and Table 2, quoting ASAE D497.7): https://arxiv.org/html/2604.17991
46. University of Arizona, "Table 3 – Field efficiency, field speed, and repair and maintenance cost parameters" (an archived copy read): https://web.archive.org/web/20240420133028/https://ag.arizona.edu/crop/equipment/agmgttable3.pdf
47. "Mouldboard plough" design slides (furrow width over depth 1.1-1.5): https://www.slideshare.net/slideshow/mb-ploughpptx/254915097
48. Balsari et al., "Performance analysis of a tractor - power harrow system under different working conditions", Biosystems Engineering 202, 28-41, 2021, doi:10.1016/j.biosystemseng.2020.11.009 (abstract read via OpenAlex; its highlights seen only in search results; the full text sits behind a bot check): https://www.sciencedirect.com/science/article/pii/S1537511020303147
49. Academia.edu's generated summary of [48], seen only in search results: https://www.academia.edu/83175306/Performance_analysis_of_a_tractor_power_harrow_system_under_different_working_conditions
50. Kverneland, "Kverneland AD", technical specifications (AD Variomat 85: 730 / 900 / 1090 kg at 3 / 4 / 5 furrows): https://ien.kverneland.com/ploughs/conventional-ploughs/kverneland-ad
51. Oberhaus, Biller, Keuper and Stachnik, "Load Transfer from the Fully-mounted Plough to the Tractor", Landtechnik 60(6) 330-331, 2005 (Fig. 2 at 0 MPa; read in full): https://www.agricultural-engineering.eu/landtechnik/article/download/2005-60-6-330-331/2005-60-6-330-331-en-pdf/2059
52. Kverneland, "M series" power harrows, technical data (with levelling bar, tooth packer roller and PTO shaft): https://uk.kverneland.com/tillage-tools/power-harrows/m-series
53. AllMachines, "Amazone KE 3002-150" (2293 lb without roller, 3373 lb with KW 580): https://www.allmachines.com/harrows/amazone-ke-3002-150
54. Kuhn North America, HR 1030 series (HR 3030: 3702 lb with MaxiPacker): https://kuhn-usa.com/node/14441
55. Land Pride, RCR2684 rotary cutter manual, form 312-785S, 2012-03-05: https://www.manualsdir.com/manuals/168383/land-pride-rotary-cutter-rcr2684.html
56. Woods BB84.40 dealer listings (1041 and 1132 lb), seen only in search results: https://www.parishtractor.com/product/bb84-40
57. Demir Machinery, single-disc fertilizer spreader (DMR SF 800: 800 L, 150 kg): https://www.demirmachinery.com/fertilizer-spreader-single-disc/
58. Wikipedia, "Three-point hitch" (category table: lower hitch spacing 28 / 34 / 40 in): https://en.wikipedia.org/wiki/Three-point_hitch
59. Koenig Equipment, "What are the Differences in 3-point Hitch Categories?" (lift arm spacing 26 / 32 / 38 in; Category 2 mast 15-24 in): https://blog.koenigequipment.com/what-are-differences-3-point-hitch-categories
60. top agrar, "Testprotokoll Fendt 516 Vario" ("Das Lenkrad ist mit 5 1/3 Umdrehungen lang übersetzt"; under 4 with VarioActive): https://www.topagrar.com/technik/aus-dem-heft/testprotokoll-fendt-516-vario-9670043.html
61. NHTSA rollover-resistance manoeuvres (fishhook at 720 deg/s handwheel rate; J-turn 1000 deg/s), seen only in search results: https://www.nhtsa.gov/sites/nhtsa.gov/files/forkenbrock_0.pdf
62. NTS Tire Supply, "650/65R38 Firestone Performer 65 R-1W 157D" (diameter 72.8, static load radius 32.6, 4127 kg, 23 psi): https://store.ntstiresupply.com/shop/003015-650-65r38-firestone-performer-65-r-1w-157d-100-34994
63. Wong, *Theory of Ground Vehicles*, 2nd ed., 1993, p. 26 (peak and sliding adhesion) and p. 17 (rolling resistance by tyre and surface), quoted by HPWizard (the book not opened): https://hpwizard.com/tire-friction-coefficient.html
64. An iRacing forum post (street tyres ~0.35 on dry grass, ~0.72 on asphalt), seen only in search results: https://www.iracing.com/?p=19604
65. Cenek, Jamieson and McLarin, "Frictional characteristics of roadside grass types", 2005 (abstract): https://trid.trb.org/View/783691
66. Tyre Reviews, "2025 AutoBild All Season Tyre Test" and "2024 AutoBild All Season Tyre Test" (snow braking), seen in search results: https://www.tyrereviews.com/Tyre-Tests/2025-AutoBild-All-Season-Tyre-Test.htm
67. TyreMap, "All-Season vs Winter Tyres" (snow braking: winter 31 m, all-season 38, summer 62; no method stated), seen in search results: https://tyremap.com/blog/all-season-vs-winter-tyres-comparison/
68. Robert Bosch GmbH, *Automotive Handbook*, 4th ed., 1996, p. 330 (rolling resistance by surface) and p. 335 (tyre friction by speed and water), quoted by HPWizard: https://hpwizard.com/tire-friction-coefficient.html
69. Engineering ToolBox, "Rolling Resistance" (car tyre on solid sand 0.04-0.08, on loose sand 0.2-0.4): https://engineeringtoolbox.com/rolling-friction-resistance-d_1303.html
70. Tyre Reviews, "2020 ADAC SUV All Season Tyre Test" (235/55 R17; summer reference 37.0 m dry, the best all-season 6.5 m more), seen in search results: https://www.tyrereviews.com/Article/2020-ADAC-SUV-All-Season-Tyre-Test.htm
71. Autonavigator, "What are the best tyres for this winter? We have tested 19 sets" (ice braking), seen in search results: https://www.autonavigator.hu/tippek_tanacsadok/what-are-the-best-tyres-for-this-winter-we-have-tested-19-sets
72. VTI, "Field test of studded and non-studded winter tires: subjective rating by taxi drivers", 1990 (abstract, seen in search results): https://trid.trb.org/view/361699
73. Leisure Wheels, highway-, all- and mud-terrain tyres on a Hilux (wet braking), seen in search results: https://www.leisurewheels.co.za/?p=1149944
74. Regulation (EU) 2020/740, Annex I Part A (rolling resistance classes): https://legislation.gov.uk/eur/2020/740/annex/I/part/1?view=plain
75. J. Paton, Total Simulation, "Secrets of Formula 1 Part 2 - Importance of Aerodynamics", 2016-06-14: https://www.totalsimulation.co.uk/secrets-formula-1-part-2-importance-aerodynamics/
76. Formula 1 Dictionary, "Aerodynamic balance or Centre of Pressure (CofP)": https://www.formula1-dictionary.net/aerodynamic_balance.html
77. J. Howell, S. Panigrahi, "Aerodynamic Side Forces on Passenger Cars at Yaw", SAE 2016-01-1620 (abstract): https://saemobilus.sae.org/content/2016-01-1620/
78. V. Malviya et al., University of Huddersfield, "Effect of cross wind on aerodynamic coefficients of ground vehicles": https://eprints.hud.ac.uk/6856/1/4_V_Malviya.pdf
79. M. Hammache, M. Michaelian, F. Browand, "Aerodynamic Forces on Truck Models, Including Two Trucks in Tandem", California PATH UCB-ITS-PRR-2001-27, 2001: https://escholarship.org/uc/item/6jr154q9
80. A. Brandt, "Driving stability of passenger vehicles under crosswinds", licentiate thesis, Chalmers, 2021: https://research.chalmers.se/publication/521674/file/521674_Fulltext.pdf
81. A. Roshko, "Experiments on the flow past a circular cylinder at very high Reynolds number", J. Fluid Mech. 10, 1961 (abstract): https://authors.library.caltech.edu/records/m8vtc-33e74
82. Milliken Research Associates, *MRA Moment Method User's Manual* v4.10, § 4.5.5 Axle Roll Steer, 2000: https://millikenresearch.com/MMM410man.pdf
83. Auto/Steel Partnership, *Lightweight Twist Beam Development — Final Report*, Fig. 35 (K&C: roll — roll steer): https://www.a-sp.org/wp-content/uploads/2020/08/Lightweight-Twist-Beam-Final-Report.pdf
84. "Summary of typical vehicle parameter measurements — compliance parameters", unattributed compilation (search summary; the page refuses fetching): https://www.researchgate.net/publication/329552571
85. Eng-Tips, "Understeer gradient of modern passenger cars" (forum): https://www.eng-tips.com/threads/understeer-gradient-of-modern-passenger-cars.190555/
86. Wikipedia, "Bundorf analysis" (after Bundorf & Leffert, SAE 760713; the example is illustrative): https://en.wikipedia.org/wiki/Bundorf_analysis
87. US 4,919,449, "Vehicle rear suspension" (search summary): https://patents.google.com/patent/US4919449
