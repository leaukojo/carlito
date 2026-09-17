# Plan: triage `docs/TODO.md` and `docs/challenge_ideas.md`

Fable, effort **low**, mode: execute directly, one Sonnet fact-checker. Delete this file
when done.

## Prompt

Read `docs/TODO.md` and `docs/challenge_ideas.md` against the current code (use a Sonnet
agent to verify each claim; read no code yourself). For each TODO item decide one of:
finished → delete; still open and actionable → rewrite as a plan prompt in `docs/plans/`
with effort and mode; a constraint rather than work → move one line into the nearest
`CLAUDE.md`. For `challenge_ideas.md`, delete every idea that already ships as a
`ChallengeDef` (list `src/challenges/defs/`), and keep the file present-state only. Both
files must end up shorter.
