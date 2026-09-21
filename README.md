# CG Mod Manager

Windows manager for [Chrono Gear (CG)](https://store.steampowered.com/app/3081840) mods. It patches the game with [Godot Mod Loader (GML)](https://wiki.godotmodding.com) 7, then installs, orders, and disables mods as zip files the loader can read.

## Requirements

- Windows
- Any install of CG (1.1.18+)
- An internet connection for first-time patching, GitHub installs, and update checks

Patches come from GitHub Releases on [tryptech/cg-mod-manager-patches](https://github.com/tryptech/cg-mod-manager-patches), matched to the game’s file version. There is no patch unless that version has a published `modloader.xdelta`.

## Setup

On first launch (or whenever the game is not configured and patched), the setup wizard:

1. Locates CG via Steam, or lets you browse to the install folder
2. Finds and downloads the xdelta patch for that game version.
3. Backs up the current PCK and EXE as versioned copies next to the game (`ChronoGear-{version}.pck`, `ChronoGear-{version}.exe`)
4. Applies the patch

The wizard can be run again from **Settings → Run wizard**. It is skipped on later launches only if the install path is valid and the live PCK matches a versioned patched backup.

Any launch of CG afterword contains GML and will attempt to load any mods in a `mods/` folder next to the exe.

## Mods

A documented example mod is in [`sample_mod/`](sample_mod/). Field-by-field notes for mod developers are in [`sample_mod/README.md`](sample_mod/README.md).

Mods are Thunderstore-style GML zips (`manifest.json` + `mod_main.gd`). They are identified in the manager by the `{namespace}` and `{name}` in `manifest.json`. Enabled zips live in the game’s `mods/` folder. Disabled zips are moved to `mods-disabled/` so the loader does not see them. Load order is stored in `mods/mod_manager.json`.

Mods can be installed in one of two ways: via a local zip, or via GitHub `owner/repo` (full GitHub URLs are also accepted). New mods are inserted at the top, then ordered so dependencies load first.

- GitHub installs walk `owner/repo` (and GitHub URLs) listed in `dependencies` and install those mods too.
- A zip with the same namespace, name, and authors but a higher `version_number` is treated as an in-place update and keeps the existing source (GitHub or local).
- GitHub mods can be checked for a newer **Releases** tag. The manager does not install updates by itself; use the details **Update** button when the tag is newer and `compatible_game_version` includes the installed CG version.
- A mod cannot be removed while an enabled mod depends on it.
- Disabling a mod that other mods require also disables those dependents.

The details column shows the selected mod’s preview, author, description, enable state, dependencies and dependents, GitHub source/issues links when applicable, and the files the zip adds or overwrites.

## License

This software is licenesed under [GPL-3.0](LICENSE). The packaged xdelta3 is bundled under its own license; see `bin/xdelta3-README.md`.