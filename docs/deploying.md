# Deploying Carlito

Two channels, one repo, no manual uploads.

## The two channels

| | URL | Moves when |
|---|---|---|
| **dev** | <https://leaukojo.github.io/carlito/dev/> | every push to `dev` (CI publishes it) |
| **stable** | <https://leaukojo.github.io/carlito/> → `/carlito/stable/` | only on the manual promote workflow |

`dev` is the default branch. `main` records what is currently stable; never commit to it
directly — the promote workflow fast-forwards it.

Both channels live on `gh-pages` as sibling directories under a redirect-only root page:

```
gh-pages/
  index.html   <- redirect to ./stable/, registers no service worker
  .nojekyll
  stable/
  dev/
```

Siblings because Godot's PWA worker scopes to its own directory — a stable build at
`/carlito/` would scope a worker over `/carlito/dev/` too. The redirect page registers no
worker. `.nojekyll` matters too — Jekyll eats Godot's `_`-prefixed files.

## The web export

CI does the real export; `& $GODOT --headless --path . --export-release "Web" build/web/index.html`
reproduces it locally. Everything below only shows up in an exported build — none of it is
caught by a local `--headless` run.

### export_presets.cfg

The editor rewrites this file on any UI export; CLI export reads it as-is. Three load-bearing
settings:

- **`variant/thread_support` stays `false`.** A threaded build needs SharedArrayBuffer, which
  needs cross-origin isolation inherited from the top-level document. sloppyCAN is plain
  GitHub Pages (no COOP/COEP), so the frame never qualifies and Godot shows "Cross-Origin
  Isolation / SharedArrayBuffer missing" instead of starting. Our PWA worker only fixes the
  standalone case. Test inside an iframe from a non-isolated origin, not standalone.
- **PWA stays enabled** — offline caching plus cross-origin-isolation headers standalone.
  With threads off, the shell's COI self-heal branch never runs; kept in place for if
  threads return.
- **Never exclude a whole `kit/raw/<pack>/` folder.** Baked levels inline materials that
  point at the pack's source textures. Excluding the folder drops those from the `.pck`;
  symptom: `ERROR: No loader found for resource: res://kit/raw/.../colormap.png (expected
  type: Texture2D)`. The exclude filter must only drop source meshes (`kit/raw/*.glb`);
  textures always ship. `kit/prefabs/*` is safe to exclude (verify with
  `grep -ao "kit/[A-Za-z0-9_/.-]*" src/levels/**/*.baked.scn | sort -u`, after
  `tools/bake_levels.tscn`).

### Head Include

Installs the JS bridge shim, pasted into `export_presets.cfg`; source is
`src/bridge/web/head_include.html`. Edit the source and re-paste into the preset — they must
match. `node tools/check_head_include.mjs` guards this from preflight and the pre-commit
hook.

### The custom HTML shell

`html/custom_html_shell` → `src/bridge/web/shell.html`, a vendored copy of Godot's
`godot.html` with one patch: where stock rejects with "Service worker already exists", ours
reloads until the new worker actually controls the page (budget 3, in
`sessionStorage.carlitoCoiReloads`, cleared on success) — a freshly installed worker doesn't
control the page that installed it, so one reload isn't always enough.

On a Godot upgrade: re-extract `godot.html` from the export template and re-apply this
patch, keeping the `$GODOT_*` placeholders (especially `$GODOT_HEAD_INCLUDE`).

### Debugging web-only breakage

Reproduce on the actual web build, read the devtools console. A runtime-only bug usually
shows up as `SCRIPT ERROR: Parse Error: Could not find type "…"` — typically an editor-only
class used as a type annotation in a runtime-loaded `@tool` script (see `kit/CLAUDE.md`).

## Publishing to dev

Push to `dev`. `.github/workflows/ci.yml` runs `build` (editor-type gate → import → gdUnit4
→ headless smoke → stale-bake check → baked-level smoke → web export) beside a parallel
`tracking` job, then `publish-dev` copies `build/web/` into `gh-pages:/dev/`. Head-include and
contract sync are pre-commit/preflight gates, not CI.

Pushes to `main` run the same gates but publish nothing.

Export basename embeds the commit SHA (`c2-<sha>.html`), so every deploy gets unique
`.pck`/`.wasm`/`.js`/service-worker filenames.

## Promoting dev → stable

**Actions → *Promote dev → stable* → Run workflow.** That's it.

Does not rebuild: fast-forwards `main` to `dev`'s tip, then copies the already-published
`gh-pages:/dev/` bytes over `gh-pages:/stable/`. Byte-for-byte what visitors get.

Both workflows call `.github/scripts/publish-pages.sh`, rewriting `gh-pages` as a single
force-pushed orphan commit; source history stays on `dev`/`main`. Both share
`concurrency: gh-pages` so two racing force-pushes can't drop one channel's update.

First visit after a deploy may need one reload while the new worker takes over — expected,
self-heals (see *The custom HTML shell*).

## When a promote turns out to be bad

Stable is only a copy of dev: fix or revert on `dev`, let CI publish, confirm on
`…/carlito/dev/`, promote again. No separate stable rollback path exists — a hand-edited
`gh-pages:/stable/` wouldn't correspond to any commit, and `git revert` + promote is the
same number of clicks.

A promote failing at *fast-forward main* means `main` has commits `dev` doesn't — it fails
there on purpose, before touching the live site, and is re-runnable once merged into `dev`.

## Contract changes are a paired deploy

Game and sloppyCAN agree by contract version number, so a contract edit lands on `dev` in
both [`carlito`](https://github.com/leaukojo/carlito) and
[`sloppycan`](https://github.com/leaukojo/sloppycan) and both promote together. Promoting one
alone puts a live stable pair on mismatched versions — the runtime warning fires and signals
are misread. Two promote buttons, back to back.

Run `node tools/gen_js_contract.mjs` before pushing — it regenerates the synced sloppyCAN
copy; the pre-commit hook blocks a stale one.

sloppyCAN mirrors this (`main` + `dev`, `gh-pages`, a matching promote workflow) but ships
no service worker: stable is the bare root `https://leaukojo.github.io/sloppycan/`, dev is
`/sloppycan/dev/`, no redirect page.

## Before you push

`powershell -File tools/preflight.ps1` runs every CI gate locally; the pre-commit hook
covers the cheap ones. Stale bakes are the most common failure.
