---
name: review-continue
description: Continue the ongoing project review ("continue reviewing"): pick the next item from .claude/review_journal/summary.md for the session's model, then diagnose it and write its brief (Fable), or fix it from its brief (Opus, Sonnet).
---

The journal is `.claude/review_journal/`: `summary.md` (unit map, queue, things for the user to
verify), `proposals.md` (changes that need the user's decision), `suggestions.md` (feature
ideas), `sessions/` (one short file per session). Read `summary.md` first; read nothing else in
the journal unless the picked item points there.

The project wants no new features: the review trims, fixes and simplifies.

## One session

1. **Pick one item**, among those tagged for the session's own model (a Fable session:
   § Diagnose only). The top of the Queue if it holds a ready item (approved proposal, or a
   deferred fix); otherwise the first unit in the map whose `Reviewed at` is empty; otherwise
   the unit with the most commits since its `Reviewed at`
   (`git log --oneline <hash>..HEAD -- <paths> | wc -l`). BETA units (boat, drone, plane,
   train) only when no land unit qualifies. One item per session; a unit too large to read in
   one session is split in the map first, and one part is reviewed.
2. **Review it** for: bloat (dead code, unreferenced files, duplicated logic), an implementation
   more complicated than its job, bad design, covers over a fault (§ Covers), false `COMPROMISE`
   labels, useless tests, stale docs, and wrong comments or explanations. A unit's tests and
   its `docs/` pages are reviewed with it.
3. **Prove each finding before acting on it.**
   - Dead code: no reference in `.gd`, `.tscn`, `.tres`, `project.godot`, tools or CI.
   - Useless test: break the code it covers and the test still passes (undo the break at
     once), or another test asserts the same thing. A long test is not a useless test.
   - Wrong comment or doc: checked against the code it describes, quoted in the session file.
   - Bad design: name the concrete cost (a bug it caused, a duplicate it forces, a rule it
     breaks), not a preference.
   - Simpler implementation: the session file names what goes (lines, a branch, an argument, a
     piece of state, a special case, a second copy) and why the behaviour stays the same. A
     rewrite of the same size and shape, a rename for taste and moved code are not findings.
4. **Size each finding, then fix cheapest-first.**
   - S (minutes, one file) and M (under about an hour, tests cover it): fix now.
   - A simplification is S or M only when its results are the same to the bit, or the unit's
     tests cover every path it touches. One that changes float arithmetic inside the physics
     tick (wheel, drivetrain, towing) can move measured figures: queue it with the before and
     after run it needs.
   - L (crosses units, or needs a design choice): do not start. Add a Queue line with a
     three-line brief so a later session can do it alone.
   - Every Queue line ends with what it wants, in brackets: effort, mode and model, e.g.
     `[medium, auto, Sonnet]`, `[high, plan, Opus]` or `[diagnose, high, Fable]` (§ Recommending
     the next session).
   - Whatever is left when the session runs low goes to the Queue. An unfinished fix is
     reverted, never left half-done.
   - The session file is created before the first fix and gains each finding and each commit
     as it happens, so a session that is cut short loses nothing.
5. **Propose instead of doing** (`proposals.md`, one entry each: what, evidence, cost, risk)
   when the change: alters how a vehicle drives or anything else the player sees or hears;
   changes the contract; removes a real `COMPROMISE`; deletes a whole file of tests or more
   than about 300 lines of non-test code; or reverses a standing rule in a `CLAUDE.md`.
   A new player-visible feature is never built here: it goes to `suggestions.md`.
6. **Verify.** Run the unit's tests after each fix; run the full suite (about a minute) before
   the last commit: `node tools/godot_run.mjs --tests -- -a tests`, judged by its output. A
   session that changed only docs, the journal or a `.mjs` tool runs that file's guard instead
   (`node tools/check_docs.mjs`). A change the user must check by driving is listed under "Please verify" in `summary.md`.
7. **Commit to `dev`, never push.** One purpose per commit, message prefixed `review:`. Stage
   by path, never `git add -A`: files already modified when the session starts are the user's
   and stay out of every commit. The pre-commit hook is never skipped. The journal update is
   the session's last commit.
8. **Update the journal.** In `summary.md`: the unit's `Result` (one line), the Queue, "Please
   verify", and the `COMPROMISE` count. `Reviewed at` (HEAD's short hash) is set only when the
   whole unit was read; otherwise the Queue's top line says where to resume. `summary.md`
   takes no paragraph about the session: every session reads it whole. The session file
   is `sessions/<YYYY-MM-DD>-<unit>.md`: findings with their evidence, what was fixed (commit
   hashes), what was deferred and why. Keep the ten newest session files and any that
   `summary.md` or `proposals.md` names; delete the others.
9. **Report to the user** in a few lines: what changed, what needs their decision, what to
   verify. The report ends with the next session's item and how to run it (§ Recommending the
   next session). `summary.md` holds no copy of it: the Queue's order and tags are the record.

## Diagnose only

A Fable session finds causes and writes briefs; it fixes nothing, so that a cheaper model can.

- **Pick.** The top Queue item tagged `diagnose`; with none, the first vehicle-physics unit
  (map units 2 to 7) whose `Reviewed at` is empty, read for findings only. An item tagged for
  Opus or Sonnet is left for a session on that model, which picks the top item tagged for it.
- **Do.** Read the code, trace the fault to what produces it, and prove it with the one run or
  the one test that shows it (a failing test is not committed: its fixture goes in the session
  file). No fix, not even an S one; no full suite, no before-and-after matrix, no doc sync.
- **Write.** The session file (cause, evidence quoted), and one Queue line per finding that a
  session with no memory of this one can execute: the file and function, what is wrong and
  why, the fix in words, the test or run that fails now and passes after, the runs to compare,
  when to stop and hand back, and its tag. A fix that changes driving says "ends in a proposal".
- **Commit** the journal only. Effort `high` at most, auto mode: nothing is changed, so there
  is no plan to approve.

## Recommending the next session

Each report ends with four things for the next `/review-continue`, judged from the item it will
pick, never assumed. A queued item's tag was written by the session that understood it: the
report copies it, and a later session may raise a tag but never lowers one it did not write. A
session unsure how to rate an item it queues takes the higher level.

- **Effort.**
  - `low`: a relabel, a doc sync or a deletion whose every step the Queue line already spells
    out.
  - `medium`: mechanical work that needs checking, not judgement (a sweep, dead-code removal,
    duplicate tests), and a unit of docs, guide pages, agent instructions or CI and build tools.
  - `high`: a unit of code with logic in it, or a fix that needs judgement.
  - `xhigh`: only on the user's word. A design change or a restructuring in the drivetrain,
    wheels or towing is diagnosed first (§ Diagnose only), then fixed from its brief at `high`.
- **Mode.** Plan mode when the item restructures code, crosses units or will end in a proposal:
  the plan is what the user approves. Auto mode for a unit review and for mechanical fixes.
- **Model.** The session's own model (`/model`), never a subagent doing the item for Fable.
  Fable only for `diagnose` items (§ Diagnose only): its credits are scarce. A fix with a brief
  is Opus's where it touches the vehicle physics (map units 2 to 7) or needs judgement, Sonnet's
  where it is mechanical or in docs, tools and tests with no physics. Every tag names its model.
- **Context.** `/clear` first, as a rule: the journal carries everything. Keep the context only
  when the next item is a fix in a file this session read whole and the session was short.

## COMPROMISE triage

The label means: the sim is knowingly wrong or weaker than intended, and fixing it is costly.
Each one found is sorted into:

- **Design choice** (the behaviour is wanted, e.g. the car still drives with an empty tank so
  the player is not stranded): keep the behaviour, drop the label, say plainly that it is a
  choice and why. The matching `docs/` text follows.
- **Code debt** (better code would remove it): fix it under the S/M/L rule, or queue it.
- **Real compromise** (a modelling limit or a non-goal): the label stays, and states what is
  true and what undoing it costs.

## Covers

A cover is code that makes a fault stop showing instead of removing it: the fault is still
produced upstream, and the cover sits between it and whoever would notice. The model case: a
lag and a hysteresis on the dashboard's bars so the AXLE number does not flicker, while the truck
rocks every tick and the bridge carries it.

A review never checks that a cover is well made. It asks what the cover hides.

- **Where they sit.** Smoothing, lag, hysteresis, a deadband, a rate limit, rounding or a snap
  to zero on a readout, a signal or a state; a clamp, an epsilon or a `max(x, small)` guarding
  a value that should not get there; a special case for one body, one level or one frame
  ("skip the first tick"); a retry or a re-run; a test tolerance, settle time or skip widened
  until the test passed; a comment that says "avoids", "hides", "prevents flicker / jitter /
  a glitch", "workaround", "for stability" without saying what produces the thing avoided.
- **Tell a cover from a model.** It is a model when it stands for something in the real machine
  or the real driver and says so (`KeyShaper` is a hand on a wheel; a sender's filter with a
  sourced time constant; the 60 Hz clamps `src/vehicles/CLAUDE.md` forbids weakening). It is a
  cover when the only reason it gives, or the commit that added it gives (`git log -S`), is a
  symptom.
- **Prove it.** Take the cover out (undo at once) and measure what appears: which value, how
  large, in which state, on which bodies. The session file records that, and the source as far
  as the session traced it. A cover with nothing behind it any more is dead code: remove it.
- **Fix the source, then remove the cover.** Both are one finding, sized by the source's fix
  under the S/M/L rule and bound by step 5: a fix that changes driving is a proposal. Where the
  fix is queued or proposed, the cover's own removal is judged apart:
  - on a display, or in a test or a tool: it goes now, and the fault it showed is listed under
    "Please verify" as known (a visible fault gets fixed; a hidden one ships);
  - on a contract signal or in the sim: a proposal, recommending removal, with the measured
    fault as its evidence;
  - where removing it would break driving (a clamp holding a body together): it stays until
    the fix, with a comment naming the Queue item.
- **Add the guard.** A test that fails on the fault itself (the body's value is steady), and,
  where a whole class of cover can be forbidden, one that forbids it
  (`test_no_instrument_smooths_its_value`).
- **Never propose a new cover**, here or as the fix of another finding: a Queue line or proposal
  for a symptom names the source to find, and says "no filter on the display or the signal".

## Limits

- Every change traces to a proven finding. Simplifying is wanted, restyling is not.
- `addons/gdUnit4/` is third-party and is not reviewed.
- The existing skills still apply: `contract-edit`, `level-edit`, `vehicle-feel`.
- A bake-hashed file (`LevelBaker.BAKE_CODE_INPUTS`) edited beyond whole-line comments re-stales
  every level: re-bake in the same session or queue the change.
- At most three subagents (Haiku or Sonnet) for searching; the reviewing agent reads the code
  it judges.
