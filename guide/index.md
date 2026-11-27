# About this guide

## Carlito

Carlito is a driving simulator that runs in a web browser.
This guide is here to teach about the mechanics that it implements.

A simulator could move a car by sliding it across the screen, but Carlito does not do that.
Each wheel touches the ground, each tyre grips or slides, each engine turns at a real speed through a real gearbox.
When a tyre slips in the simulation, it is because the forces on it were more than its grip could hold (as in a real car).

## Examples of questions this guide answers

- [Why does a tyre need to slip to grip at all?](slip.md#a-tyre-needs-slip-to-grip)
- [How does ABS keep a wheel turning when you brake hard?](driver-aids.md#abs)
- [Why does a hot brake stop less well?](brakes.md#heat-and-fade)
- [Why do the two wheels on an axle need to turn at different speeds?](differentials.md#why-wheels-need-to-turn-at-different-speeds)
- [Why does the tractor's engine labour when the plough goes in?](implements.md#draft-pulling-through-the-soil)
- [What makes an articulated truck jackknife?](towing.md#jackknife)
- [Why does an automatic car creep forward when you let go of the brake?](coupling.md#creep)
- [What tips a vehicle over in a tight turn?](weight-transfer.md#wheel-lift-and-rollover)
- [Which end of a car lets go first in a corner?](understeer.md#which-end-lets-go-first)

## CAN bus signals

Real vehicles pass messages between their parts over a wiring network called a
[CAN bus](glossary.md#can-bus). The engine reports its speed, the brakes report their
temperature, etc. This data is then used by other components (for example, to display the vehicle speed on the dashboard).

The simulator talks to a second program, [sloppyCAN](https://github.com/leaukojo/sloppycan), a CAN bus
simulator and analysis tool that also runs in a web browser. Carlito sends sloppyCAN the same kind
of messages, called [signals](glossary.md#signal), and sloppyCAN turns most of them into CAN
traffic you can observe and interact with. sloppyCAN can also send commands back, such as "press the accelerator".
