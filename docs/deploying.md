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
  type: Texture2D)`. The exclude filter drops source meshes (`kit/raw/*.glb`) and names
  individual textures no baked level reaches (six `kit/raw/racing/` ones, ~255 KB — the
  export's `all_resources` mode ships every texture regardless of reachability).
  `kit/prefabs/*` is safe to exclude. `tests/test_export_filter.gd` walks every baked
  level's dependencies against the filter and fails naming the level and file, so placing
  one of the excluded pieces fails CI instead of the deployed build — drop its texture
  from the list then.

### Level packs

Every island (`src/levels/island/`, `LevelPacks.PACK_ROOT`) ships in its own
`c2-<sha>.<id>.pck` beside the main pack, so the boot download carries none of them (the boot
default, `flatland`, has no bake). The first time one opens, `src/shell/level_packs.gd`
downloads it behind the loading screen, keeps it in `user://level_packs/` (IndexedDB: it survives
reloads and plays offline afterwards) and mounts it with `ProjectSettings.load_resource_pack`;
packs of any other build are deleted on the next fetch (dev and stable share one origin, so
while they run different builds a visit to one deletes the other's). They are not in the service
worker's cache list: that list is Godot-generated, and any entry missing from its cache sends an
offline navigation to the offline page. Off the web every island is on disk and nothing is fetched.

CI exports one per `Web <id>` preset right after the main export:
`--export-patch "Web <id>" c2-<sha>.<id>.pck --patches c2-<sha>.pck`. Load-bearing, and pinned
by `tests/test_export_filter.gd` unless noted:

- **A level preset exports everything the main one does**: `all_resources`, the main filters,
  only the *other* islands excluded. A patch records every base-pack file its own preset would
  not export as deleted, so a preset listing just the level's files built a pack that took ~700
  files out of the running game when mounted.
- **`patch_delta_encoding=true`.** ~30 scenes (vehicles, `boot`, `level`) get freshly generated
  node ids on every export, so their bytes never match the main pack's; delta encoding carries
  them at a few bytes each (~5 KB a pack) instead of as full copies (~365 KB). Godot's own
  `uid_cache.bin` and `global_script_class_cache.cfg` stay out of it
  (`patch_delta_exclude_filters`): delta-encoded, their read comes up short on mount ("Reading
  less data than requested"); whole, they cost ~33 KB raw a pack.
- **A pack mounts only over the main pack of the same run**, since its deltas apply to that
  pack's bytes. Hence the shared `c2-<sha>` stem, which the game reads from
  `GODOT_CONFIG.executable`. (Not a test: the CI loop names them.)
- **`HTTPRequest.accept_gzip = false`.** GitHub Pages gzips `.pck` in transit; the browser has
  already decompressed it, but `Content-Encoding` stays visible and HTTPRequest gunzips it a
  second time (`RESULT_BODY_DECOMPRESS_FAILED`). A plain local server doesn't gzip, so this
  fails only deployed. And no `download_file`: on the web it reports success and writes
  nothing, so the body is written to `user://` on completion. (Neither is a test.)
- **An island's level-select size** comes from `res://src/shell/level_weights.json`, which the
  kit's export plugin writes into every pack (`LevelRegistry.SHIPPED_WEIGHTS`): the bake itself
  is not on disk until its pack is mounted.
- 4.7.1 occasionally segfaults on exit after writing a patch, so CI judges each run by its
  `savepack` DONE line, not its exit code.

A new island needs a `Web <id>` preset: copy a sibling's two sections and let the test name the
exclude list. To reproduce locally (the stem is `index` there), export as below and serve
`build/web/`; a server that gzips `.pck` the way Pages does is the faithful test.

```powershell
& $GODOT --headless --path . --export-release "Web" build/web/index.html
foreach ($id in 'level_1','level_2','level_3','level_4','level_5','level_6','car_arena') {
  & $GODOT --headless --path . --export-patch "Web $id" "build/web/index.$id.pck" --patches build/web/index.pck }
```

### Download size

Measure what the player downloads: gzipped, on the deployed build. Raw and transferred size can
move opposite ways (compressing baked-mesh attributes cut the pck 6.2 MB raw but grew it 0.24 MB
gzipped, because quantized attributes carry more entropy than gzip was exploiting; kept for parse
and vertex bandwidth), so compare gzipped before and after, one change at a time. First load
(2026-09-11, local export): wasm 10.1 MB + main pck 3.5 MB + js 0.07 MB gzipped, and later visits
come from the service worker. Level packs (2026-09-12): 0.1-0.6 MB each, `level_3` 3.3 MB, 5.1 MB
for all seven.
The wasm is now most of it (`TODO.md` § Custom web export template).

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
→ headless smoke → stale-bake check → baked-level smoke → web export + level packs) beside a parallel
`tracking` job, then `publish-dev` copies `build/web/` into `gh-pages:/dev/`. Head-include and
contract sync are pre-commit/preflight gates, not CI.

Pushes to `main` run the same gates but publish nothing.

Export basename embeds the commit SHA (`c2-<sha>.html`), so every deploy gets unique
`.pck`/`.wasm`/`.js`/service-worker filenames, level packs (`c2-<sha>.<id>.pck`) included.

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
