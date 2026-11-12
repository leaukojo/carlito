---
name: review-continue
description: Continue the ongoing project review ("continue reviewing"): pick the next unit from .claude/review_journal/summary.md, review it, fix what is cheap and proven, queue the rest.
---

The journal is `.claude/review_journal/`: `summary.md` (unit map, queue, things for the user to
verify), `proposals.md` (changes that need the user's decision), `suggestions.md` (feature
ideas), `sessions/` (one short file per session). Read `summary.md` first; read nothing else in
the journal unless the picked item points there.

## One session

1. **Pick one item.** The top of the Queue if it holds a ready item (approved proposal, or a
   deferred fix); otherwise the first unit in the map whose `Reviewed at` is empty; otherwise
   the unit with the most commits since its `Reviewed at`
   (`git log --oneline <hash>..HEAD -- <paths> | wc -l`). BETA units (boat, drone, plane,
   train) only when no land unit qualifies. One item per session; a unit too large to read in
   one session is split in the map first, and one part is reviewed.
2. **Review it** for: bloat (dead code, unreferenced files, duplicated logic), bad design,
   false `COMPROMISE` labels, useless tests, stale docs, and wrong comments or explanations. A
   unit's tests and its `docs/` pages are reviewed with it.
3. **Prove each finding before acting on it.**
   - Dead code: no reference in `.gd`, `.tscn`, `.tres`, `project.godot`, tools or CI.
   - Useless test: break the code it covers and the test still passes (undo the break at
     once), or another test asserts the same thing. A long test is not a useless test.
   - Wrong comment or doc: checked against the code it describes, quoted in the session file.
   - Bad design: name the concrete cost (a bug it caused, a duplicate it forces, a rule it
     breaks), not a preference.
4. **Size each finding, then fix cheapest-first.**
   - S (minutes, one file) and M (under about an hour, tests cover it): fix now.
   - L (crosses units, or needs a design choice): do not start. Add a Queue line with a
     three-line brief so a later session can do it alone.
   - Every Queue line ends with the effort level it wants, in brackets: `[medium]` for
     mechanical work (deletions, relabels, doc sync), `[high]` for a unit review or a fix that
     needs judgement, `[xhigh]` for a design change in the drivetrain, wheels or towing.
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
   change the user must check by driving is listed under "Please verify" in `summary.md`.
7. **Commit to `dev`, never push.** One purpose per commit, message prefixed `review:`. Stage
   by path, never `git add -A`: files already modified when the session starts are the user's
   and stay out of every commit. The pre-commit hook is never skipped. The journal update is
   the session's last commit.
8. **Update the journal.** In `summary.md`: the unit's `Result` (one line), the Queue, "Please
   verify", and the `COMPROMISE` count. `Reviewed at` (HEAD's short hash) is set only when the
   whole unit was read; otherwise the Queue's top line says where to resume. The session file
   is `sessions/<YYYY-MM-DD>-<unit>.md`: findings with their evidence, what was fixed (commit
   hashes), what was deferred and why. Keep the ten newest session files; delete older ones.
9. **Report to the user** in a few lines: what changed, what needs their decision, what to
   verify. The last line names the next session's item and its effort level (a map unit is
   `high`); the same goes on the `Next session:` line of `summary.md`.

## COMPROMISE triage

The label means: the sim is knowingly wrong or weaker than intended, and fixing it is costly.
Each one found is sorted into:

- **Design choice** (the behaviour is wanted, e.g. the car still drives with an empty tank so
  the player is not stranded): keep the behaviour, drop the label, say plainly that it is a
  choice and why. The matching `docs/` text follows.
- **Code debt** (better code would remove it): fix it under the S/M/L rule, or queue it.
- **Real compromise** (a modelling limit or a non-goal): the label stays, and states what is
  true and what undoing it costs.

## Limits

- No refactor for taste: every change traces to a proven finding.
- `addons/gdUnit4/` is third-party and is not reviewed.
- The existing skills still apply: `contract-edit`, `level-edit`, `vehicle-feel`.
- A bake-hashed file (`LevelBaker.BAKE_CODE_INPUTS`) edited beyond whole-line comments re-stales
  every level: re-bake in the same session or queue the change.
- At most three subagents (Haiku or Sonnet) for searching; the reviewing agent reads the code
  it judges.
