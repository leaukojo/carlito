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
`/carlito/` would scope a worker over `/carlito/dev/` too. `.nojekyll` matters too — Jekyll
eats Godot's `_`-prefixed files.

## The web export

CI does the real export; `& $GODOT --headless --path . --export-release "Web"
build/web/index.html` reproduces it locally. None of what follows shows up in a local
`--headless` run — only in an exported build.

### export_presets.cfg

The editor rewrites this file on any UI export; CLI export reads it as-is.

- `variant/thread_support` stays `false` — sloppyCAN is plain GitHub Pages (no COOP/COEP),
  so a threaded build never qualifies for SharedArrayBuffer; test inside a non-isolated
  iframe, not standalone.
- PWA stays enabled — offline caching plus cross-origin-isolation headers standalone.
- Never exclude a whole `kit/raw/<pack>/` folder — baked levels inline materials pointing at
  the pack's source textures. `kit/prefabs/*` is safe to exclude.
  `tests/test_export_filter.gd` walks every baked level's dependencies against the filter
  and fails naming the level and file.

### Level packs

- Every island (`src/levels/island/`, `LevelPacks.PACK_ROOT`) ships in its own
  `c2-<sha>.<id>.pck` — the boot default `flatland` has no bake, so the boot download
  carries none. First open, `src/shell/level_packs.gd` downloads it behind the loading
  screen, keeps it in `user://level_packs/` (IndexedDB), mounts with
  `ProjectSettings.load_resource_pack`. Packs of any other build are deleted on the next
  fetch.
- Not in the service worker's cache list — an entry missing from it sends an offline
  navigation to the offline page.
- A local export's build name is always `index`, so `LevelPacks` never reuses a cached pack
  under that name (`may_reuse_cache`) — a local re-export must re-export every pack, not
  only the main one.
- CI exports one per `Web <id>` preset right after the main export: `--export-patch "Web
  <id>" c2-<sha>.<id>.pck --patches c2-<sha>.pck`. Pinned by `tests/test_export_filter.gd`
  unless noted:
- A level preset exports everything the main one does (`all_resources`, the main filters,
    only the *other* islands excluded) — else a preset built a pack that took ~700 files out
    of the running game when mounted.
- `patch_delta_encoding=true` — ~30 scenes (vehicles, `boot`, `level`) get fresh node ids
    every export; delta encoding carries them at ~5 KB a pack instead of ~365 KB.
    `uid_cache.bin`/`global_script_class_cache.cfg` stay out of it
    (`patch_delta_exclude_filters`) — delta-encoded their read comes up short on mount;
    whole, they cost ~33 KB raw a pack.
- A pack mounts only over the main pack of the same run — shared `c2-<sha>` stem, read from
    `GODOT_CONFIG.executable`.
- `HTTPRequest.accept_gzip = false` — GitHub Pages gzips `.pck`; HTTPRequest would gunzip an
    already-decompressed body (`RESULT_BODY_DECOMPRESS_FAILED`). No `download_file` either —
    on web it reports success and writes nothing.
- An island's level-select size comes from `res://src/shell/level_weights.json`
    (`LevelRegistry.SHIPPED_WEIGHTS`).
- 4.7.1 occasionally segfaults on exit after writing a patch, so CI judges by the `savepack`
    DONE line, not exit code.
- A new island needs a `Web <id>` preset: copy a sibling's two sections, let the test name
  the exclude list. Reproduce locally (stem is `index` there) and serve `build/web/`; a
  gzipping server is the faithful test.

```powershell
& $GODOT --headless --path . --export-release "Web" build/web/index.html
foreach ($id in 'level_1','level_2','level_3','level_4','level_5','level_6','car_arena') {
  & $GODOT --headless --path . --export-patch "Web $id" "build/web/index.$id.pck" --patches build/web/index.pck }
```

### Download size

Measure gzipped, on the deployed build — raw and transferred size can move opposite ways
(compressing baked-mesh attributes cut the pck 6.2 MB raw but grew it 0.24 MB gzipped, since
quantized attributes carry more entropy than gzip was exploiting).

First load (2026-09-11, local export): wasm 10.1 MB + main pck 3.5 MB + js 0.07 MB gzipped,
later visits from the service worker. Level packs (2026-09-12): 0.1-0.6 MB each, `level_3`
3.3 MB, 5.1 MB for all seven. The wasm is most of it; only a custom export template would
move that.

### Head Include

Installs the JS bridge shim, pasted into `export_presets.cfg`; source is
`src/bridge/web/head_include.html`. Edit the source and re-paste — they must match. `node
tools/check_head_include.mjs` guards this from preflight and the pre-commit hook.

### The custom HTML shell

`html/custom_html_shell` → `src/bridge/web/shell.html`, a vendored copy of Godot's
`godot.html`: where stock rejects with "Service worker already exists", ours reloads until
the new worker actually controls the page (budget 3, `sessionStorage.carlitoCoiReloads`).

On a Godot upgrade: re-extract `godot.html` from the export template and re-apply this
patch, keeping the `$GODOT_*` placeholders (especially `$GODOT_HEAD_INCLUDE`).

### Debugging web-only breakage

Reproduce on the actual web build, read the devtools console. Usually shows as `SCRIPT
ERROR: Parse Error: Could not find type "…"` — an editor-only class used as a type
annotation in a runtime-loaded `@tool` script (`kit/CLAUDE.md`).

## Publishing to dev

Push to `dev`. `.github/workflows/ci.yml` runs `build` (editor-type gate → head-include
check → import → stale-bake check → bake → gdUnit4 → headless smoke → baked-level smoke →
web export + level packs) beside a parallel `tracking` job, then `publish-dev` copies
`build/web/` into `gh-pages:/dev/`. Steps are judged by output, not exit code — headless
Godot can finish and still die in teardown. Contract sync is a pre-commit/preflight gate,
not CI.

Pushes to `main` run the same gates but publish nothing.

Export basename embeds the commit SHA (`c2-<sha>.html`), so every deploy gets unique
`.pck`/`.wasm`/`.js`/service-worker filenames, level packs (`c2-<sha>.<id>.pck`) included.

## Promoting dev → stable

**Actions → *Promote dev → stable* → Run workflow.** That's it.

Does not rebuild: fast-forwards `main` to `dev`'s tip, then copies the already-published
`gh-pages:/dev/` bytes over `gh-pages:/stable/`. Refuses to copy unless `dev/c2-<sha8>.html`
for that tip exists.

Both workflows call `.github/scripts/publish-pages.sh`, rewriting `gh-pages` as a single
force-pushed orphan commit; source history stays on `dev`/`main`. Both share `concurrency:
gh-pages` so two racing force-pushes can't drop one channel's update.

First visit after a deploy may need one reload while the new worker takes over — self-heals
(see *The custom HTML shell*).

## When a promote turns out to be bad

Stable is only a copy of dev: fix or revert on `dev`, let CI publish, confirm on
`…/carlito/dev/`, promote again. No separate stable rollback path exists.

A promote failing at *fast-forward main* means `main` has commits `dev` doesn't — it fails
there on purpose, before touching the live site.

## Contract changes are a paired deploy

Game and sloppyCAN agree by contract version number, so a contract edit lands on `dev` in
both [`carlito`](https://github.com/leaukojo/carlito) and
[`sloppycan`](https://github.com/leaukojo/sloppycan) and both promote together. Promoting
one alone puts a live stable pair on mismatched versions.

Run `node tools/gen_js_contract.mjs` before pushing — the pre-commit hook blocks a stale
sloppyCAN copy.

sloppyCAN mirrors this (`main` + `dev`, `gh-pages`, a matching promote workflow) but ships
no service worker: stable is `https://leaukojo.github.io/sloppycan/`, dev is
`/sloppycan/dev/`.

## Before you push

`powershell -File tools/preflight.ps1` runs every CI gate locally; the pre-commit hook
covers the cheap ones. Stale bakes are the most common failure.
