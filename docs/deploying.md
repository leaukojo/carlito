# Deploying Carlito

Two channels, one repo, no manual uploads. This page is the whole ritual.

## The two channels

| | URL | Moves when |
|---|---|---|
| **dev** | <https://leaukojo.github.io/carlito/dev/> | every push to `dev` (CI publishes it) |
| **stable** | <https://leaukojo.github.io/carlito/> → `/carlito/stable/` | only when you press the promote button |

`dev` is the default branch, so clones, PRs and everyday work land there. `main` is a
record of what is currently stable — you never commit to it directly; the promote workflow
fast-forwards it.

Both channels live on the `gh-pages` branch as **sibling directories**, under a root page
that is nothing but a redirect:

```
gh-pages/
  index.html   <- redirect to ./stable/, registers no service worker
  .nojekyll
  stable/
  dev/
```

They are siblings on purpose. Godot's PWA registers a service worker scoped to its own
directory; a stable build sitting at `/carlito/` would scope a worker over `/carlito/dev/`
too and could serve a cached stable page for a dev URL. The redirect page registers
nothing, so the two scopes never overlap. `.nojekyll` matters as well — Jekyll eats
Godot's `_`-prefixed files.

## The web export

CI does the real export; `& $GODOT --headless --path . --export-release "Web" build/web/index.html`
reproduces it locally. Everything below is a trap that only shows up in an exported build,
so none of it is caught by a local `--headless` run.

### export_presets.cfg

The editor **rewrites `export_presets.cfg`** whenever you export from the UI; CLI export
reads it as-is. Three things in it are load-bearing.

**`variant/thread_support` stays `false`.** The game exists to be embedded in sloppyCAN's
iframe, and a threaded build cannot boot there: it needs SharedArrayBuffer, which needs
cross-origin isolation, which is **inherited down the frame tree** — a frame is only
isolated if the TOP-level document is. sloppyCAN is plain GitHub Pages (no COOP/COEP, no
service worker), so the frame never qualifies and Godot shows "Cross-Origin Isolation /
SharedArrayBuffer missing" instead of starting. Our own PWA worker only fixes the
standalone case (open `/carlito/stable/` directly and it *is* isolated) — it cannot reach
up and isolate the embedder. **Testing the game standalone does not test the product;
check it inside an iframe from a non-isolated origin.**

**PWA stays enabled.** It still gets offline caching and the cross-origin-isolation headers
for standalone visits. With threads off, `getMissingFeatures()` comes back empty, so the
shell's COI self-heal branch is never entered — it stays in place, correct and inert, in
case threads ever come back.

**Never exclude a whole `kit/raw/<pack>/` folder.** Baked levels inline their *materials*,
and those materials still point at the pack's source textures
(`kit/raw/<pack>/Textures/colormap.png`, `kit/raw/racing/*_tankcoBanner.png`). Excluding
the folder drops those from the `.pck`, and the export-only symptom is

```
ERROR: No loader found for resource: res://kit/raw/.../colormap.png (expected type: Texture2D)
```

with untextured geometry. The exclude filter must only drop the source meshes
(`kit/raw/*.glb`); textures always ship. Same reason `kit/prefabs/*` *is* safe to exclude —
bakes reference no `.glb`/prefab paths (verify with
`grep -ao "kit/[A-Za-z0-9_/.-]*" src/levels/**/*.baked.scn | sort -u`).

### Head Include

The Head Include installs the JS bridge shim and is pasted into `export_presets.cfg`; the
reviewable source is `src/bridge/web/head_include.html`. **Edit the source and re-paste it
into the preset — they must match.** `node tools/check_head_include.mjs` guards this, and
runs from both preflight and the pre-commit hook.

### The custom HTML shell

`html/custom_html_shell` → `src/bridge/web/shell.html`, a vendored copy of Godot's
`godot.html` export template carrying one Carlito patch. Where the stock template rejects
with "Service worker already exists", ours waits for the worker to activate and then
reloads **until the worker actually controls the page** — a freshly installed worker does
not control the page that installed it, so one reload is not always enough. The reload
budget is 3, counted in `sessionStorage.carlitoCoiReloads` and cleared on a successful
load; the real failure only surfaces once the worker controls the page and the features are
*still* missing, or the budget runs out. That is how first-load cross-origin isolation on
GitHub Pages self-heals without a manual reload.

**On a Godot upgrade, re-extract `godot.html` from the web export template and re-apply
this patch**, keeping the `$GODOT_*` placeholders (especially `$GODOT_HEAD_INCLUDE`).

### Debugging web-only breakage

Reproduce on the actual web build and read the browser devtools console. A runtime-only bug
that no local `--headless` run reproduces usually shows up there as
`SCRIPT ERROR: Parse Error: Could not find type "…"` — typically an editor-only class used
as a type annotation in a runtime-loaded `@tool` script (see `kit/CLAUDE.md`).

## Publishing to dev

Push to `dev`. `.github/workflows/ci.yml` runs the full gate stack (editor-type gate →
import → gdUnit4 → stale-bake check → both headless smokes → head-include and contract
sync → web export), then `publish-dev` copies `build/web/` into `gh-pages:/dev/`.

Pushes to `main` run the same gates but publish nothing — those bytes are already live.

The export basename embeds the commit SHA (`c2-<sha>.html`), so every deploy gets unique
`.pck`/`.wasm`/`.js`/service-worker filenames and no browser serves you a half-old build.
`index.html` is just a copy of it.

## Promoting dev → stable

**Actions → *Promote dev → stable* → Run workflow.** That is it.

It does **not** rebuild. It fast-forwards `main` to the tip of `dev`, then copies the
already-published `gh-pages:/dev/` bytes over `gh-pages:/stable/`. The build you approved
by driving dev is byte-for-byte the one anonymous visitors get, and the promote takes
seconds instead of a full Godot export.

Both workflows call `.github/scripts/publish-pages.sh`, which rewrites `gh-pages` as a
single orphan commit and force-pushes it — a web build is ~50 MB, and keeping history
would accumulate every superseded copy forever. Nothing is lost: the source history lives
on `dev`/`main` and every published build is reproducible from it. Both hold the same
`concurrency: gh-pages` group, because two force-pushes racing would silently drop one
channel's update.

First visit after any deploy may need one reload while the new service worker takes over.
That is expected and self-heals (see *The custom HTML shell* above).

## When a promote turns out to be bad

Stable is only ever a copy of dev, so the fix is always "make dev right, promote again":

1. Fix or revert on `dev`, let CI publish, drive `…/carlito/dev/` to confirm.
2. Promote again.

There is no separate stable rollback path and there deliberately isn't one — a hand-edited
`gh-pages:/stable/` would no longer correspond to any commit. If you need the old bytes
back fast, `git revert` on `dev` and promote is the same number of clicks.

If a promote fails at the *fast-forward main* step, that means `main` has commits `dev`
does not. The workflow fails there on purpose, before touching the live site, so it is
safely re-runnable once you have merged those commits into `dev`.

## Contract changes are a paired deploy

The game and sloppyCAN agree by contract **version number**. A contract edit therefore
lands on the `dev` branch of **both** [`carlito`](https://github.com/leaukojo/carlito) and
[`sloppycan`](https://github.com/leaukojo/sloppycan), and both get promoted together.

Promoting one alone puts a live stable pair on mismatched versions: the runtime warning
fires and signals are misread. Two promote buttons, pressed back to back.

After any contract edit, run `node tools/gen_js_contract.mjs` before pushing — it
regenerates the synced sloppyCAN copy, and the pre-commit hook blocks a stale one.

sloppyCAN's own channels mirror this (`main` + `dev`, `gh-pages`, a matching promote
workflow) with one difference: it ships no service worker, so its stable stays at the bare
root URL `https://leaukojo.github.io/sloppycan/` and dev is `/sloppycan/dev/` — no
redirect page needed.

## Before you push

`powershell -File tools/preflight.ps1` runs every CI gate locally. The pre-commit hook
covers the cheap ones (editor-type annotations, contract sync, head-include drift, stale
bakes); stale bakes are the failure that comes back most often, so re-bake and run
`check_bakes` before ending any authoring change.
