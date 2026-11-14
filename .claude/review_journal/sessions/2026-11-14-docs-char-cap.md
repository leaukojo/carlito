# 2026-11-14: the docs cap counts characters

A Fable session on the user's word; the item was tagged for Sonnet. The user's "go ahead"
followed the question about `docs/plans/realism_gaps.md:85` and is read as its OK.

- 7f9f63e: `tools/check_docs.mjs` sums characters over the capped `docs/*.md`
  (`DOCS_CHAR_CAP = 269723`, the total at that commit; the CLAUDE.md budgets stay in lines). The
  plan's step reads "Lower `DOCS_CHAR_CAP` by the characters removed".
- The next commit re-wraps `docs/vehicles.md` § Contact and the paragraph after it at 100
  columns: `git diff --word-diff` shows no word changed, and the total stays 269723.

Left as found: other capped docs hold lines over 200 characters (`docs/vehicles.md` 43 to 53,
`boat.md`, `flight.md`, `drivetrain.md:226`); some are tables. Not re-wrapped: the cap no longer
rewards them.
