# About this guide

<div class="box note">

**To read this guide** as a website, run `npx serve docs/guide` from the top folder of the
repository and open the address it prints (usually http://localhost:3000). It needs a web server
because the pages are loaded as separate files. Without one, every page is still a plain
Markdown file in `docs/guide/`, readable in any editor.

</div>

<p class="lead">Carlito is a driving game in a web browser. You can drive a car, a truck, a
tractor, a boat, a drone, a plane or a train. Underneath each one is a model of how real machines
work. This guide explains those models in plain language.</p>

## What the game models

A game could move a car by sliding it across the screen. Carlito does not. Each wheel touches
the ground, each tyre grips or slides, each engine turns at a real speed through a real gearbox.
When a tyre slips in the game, it is because the forces on it were more than its grip could hold.

The guide has one page for each idea: tyres, steering, engines, brakes, boats, aircraft and so
on. Each page says what the idea means in the real world, how the game models it, which vehicles
have it, and how to see it for yourself.

The game also talks to a second program, **sloppyCAN**. sloppyCAN is a simulator of the
electronics inside a vehicle. Real vehicles pass messages between their parts over a wiring
network called a CAN bus. The engine reports its speed, the brakes report
their temperature, the dashboard listens. Carlito sends sloppyCAN the same kind of messages,
called signals, and sloppyCAN can send commands back, such as "press the
accelerator". Every page lists the signals that show its idea.

## How a page is laid out

Every idea page follows the same pattern (the page template describes it in full):

1. **A short summary**, then **which vehicles have this**, shown as badges:
   <span class="badge yes">has it</span> <span class="badge some">some of them</span>
   <span class="badge no">does not</span>
2. **The explanation**, one idea at a time, with drawings.
3. **What you see in sloppyCAN**: the signals that show the idea, with their names and units.
4. **Try it in the game**: a short experiment.

A word with a dotted underline is explained in the glossary. On a computer, hold
the pointer over it to read the explanation without leaving the page.

## Numbers in this guide

The guide uses few numbers, rounded, and only where they help. Each one comes from the game's own
settings or code, not from a real vehicle's brochure. Where the game's choice is a simplification,
the page says so.

## Where this guide comes from

The guide is written from the game's source code and its developer notes. It describes what the
code does today. Where the code and the notes disagree, or something looks wrong, the question is
recorded in [the open questions](open_questions.md) instead of being guessed at here.
