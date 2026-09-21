# CGSample-Example

Sample Chrono Gear mod for **CG Mod Manager**. It is a valid [Godot Mod Loader](https://wiki.godotmodding.com) mod and documents every field the manager reads when it builds a list entry.

Modding API, script extensions, and packing rules come from Godot Mod Loader. Start here: **https://wiki.godotmodding.com**

Install this folder as a zip (Add local mod). The manager repacks loose layouts into `mods-unpacked/CGSample-Example/`.

## Required files

| File | Role |
| --- | --- |
| `manifest.json` | Thunderstore-style manifest. `namespace` and `name` are required. |
| `mod_main.gd` | Must sit next to `manifest.json`. Without it the zip is rejected. |

The manager id is always `{namespace}-{name}` (here `CGSample-Example`).

## Files the manager shows in details

| Location | Listed as |
| --- | --- |
| Everything else in the mod (scripts, scenes, `icon.png`, `preview.png`, …) | **Added** |
| `extensions/**` | **Modified** (`res://` path after `extensions/`, or the script’s `extends "res://..."` target) |
| `overwrite/**` | **Modified** as `res://` plus the path after `overwrite/` |

`manifest.json`, `.uid`, and `.import` files are omitted from those lists.

## `manifest.json` fields the manager uses

| Field | Used for |
| --- | --- |
| `name` | Title in the list and details. Part of the mod id. |
| `namespace` | Author fallback and part of the mod id. Compared when a local zip is treated as an update. |
| `version_number` | Shown on the row and details. Compared to GitHub release tags and to a newer local zip. |
| `description` | Details panel. |
| `website_url` | Link in details. If this is a `github.com/owner/repo` URL, the manager can also check that repo for updates. This sample points at the Mod Loader wiki instead. |
| `dependencies` | Load order, remove/disable rules, and GitHub install. Each entry may be `Namespace-Name`, `Namespace-Name-1.2.3`, or GitHub `owner/repo` (including `https://github.com/owner/repo`). `owner/repo` deps are fetched when installing from GitHub. |

JSON cannot hold comments; keep the real values in `manifest.json` and use this table as the spec.

## `extra.godot` fields the manager uses

| Field | Used for |
| --- | --- |
| `authors` | Meta line (`author · source`). If the mod was installed from GitHub, the author text links to `https://github.com/{owner}`. Matching authors plus name/namespace is how a newer local zip is recognized as an update. |
| `icon` | Path inside the zip for the 64×64 list icon. Falls back to `image`, then `icon.png` / `.jpg` / `.jpeg` / `.webp` next to the manifest. |
| `image` | Alternate icon path if `icon` is empty (GML alias). |
| `preview` | Details preview (column width, max 160px). Falls back to `preview.png` / `.jpg` / `.jpeg` / `.webp`. |
| `load_before` | Stored on the entry for Godot Mod Loader. The manager does not reorder from this list; dependency order uses `dependencies`. |
| `compatible_game_version` | GitHub and local updates apply only if the new zip lists the installed Chrono Gear version (or the list is empty). This sample lists `1.1.18`. |

## Other `extra.godot` fields (GML, not used by the manager UI)

Keep these for Godot Mod Loader even though the manager ignores them today:

- `optional_dependencies`
- `incompatibilities`
- `compatible_mod_loader_version` (this project targets **7.0.1**)
- `config_schema`

See the wiki for their meaning: https://wiki.godotmodding.com

## GitHub install and updates

If you publish this mod as a GitHub repo and install it with `owner/repo`:

- The list source becomes `github:owner/repo`.
- Details gain **Mod source code** and **Report bug** (`https://github.com/owner/repo` and `/issues`).
- The author name links to `https://github.com/owner`.
- Latest **Releases** tags are compared to `version_number` (a leading `v` is ignored). An **Update** button appears when the tag is newer and `compatible_game_version` includes the current game.

A local zip with the same `namespace`, `name`, and `authors` but a higher `version_number` is installed as an update the same way, without switching the stored GitHub source.

## Minimal `mod_main.gd`

Godot Mod Loader instantiates this node. Hook game scripts with `ModLoaderMod.install_script_extension` as described on the wiki. This sample only logs so it is safe to enable.
