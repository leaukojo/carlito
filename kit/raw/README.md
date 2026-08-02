# kit/raw — CC0 source models

Kenney asset kits (https://kenney.nl), all **CC0** — see `License.txt` in each folder.
Copied from the upstream kit zips with the folder layout flattened; the `Textures/`
subfolder (and the racing kit's loose banner/net PNGs) must stay next to the `.glb`
files — the models reference them by relative path.

| folder | upstream kit | GLBs |
|---|---|---|
| `roads/` | City Kit: Roads | 72 |
| `racing/` | Racing Kit | 112 |
| `suburban/` | City Kit: Suburban | 40 |
| `watercraft/` | Watercraft Pack | 46 |
| `commercial/` | City Kit: Commercial | 41 |
| `industrial/` | City Kit: Industrial | 25 |

These are **authoring-time inputs only**: palettes and prefabs are generated from them
(`tools/gen_kit_assets.gd` + `kit/import/*.json`), and level bakes merge the geometry.
The `.glb` files are excluded from the web export (`export_presets.cfg`); the shared
`colormap.png` textures do ship, because baked materials keep referencing them.
