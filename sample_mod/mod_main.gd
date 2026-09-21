extends Node

## Sample Chrono Gear mod for CG Mod Manager.
## Create mods with Godot Mod Loader: https://wiki.godotmodding.com
## This script is required next to manifest.json. The manager will refuse
## a zip that has a manifest but no mod_main.gd.

const MOD_ID := "CGSample-Example"
const LOG_NAME := "CGSample-Example:Main"


func _init() -> void:
	ModLoaderLog.info("Loaded %s. Modding wiki: https://wiki.godotmodding.com" % MOD_ID, LOG_NAME)


func _ready() -> void:
	ModLoaderLog.info("Ready. See sample_mod/README.md for manager fields.", LOG_NAME)
