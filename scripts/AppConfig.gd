class_name AppConfig
extends RefCounted

const CONFIG_PATH := "res://config.json"
const SETTINGS_PATH := "user://settings.json"

var patchesRepo := "tryptech/cg-mod-manager-patches"
var pckName := "ChronoGear.pck"
var vanillaBackupName := "ChronoGear-vanilla.pck"
var gameExeName := "ChronoGear.exe"
var steamAppId := 3081840
var gameDir := ""
var setupComplete := false


static func LoadConfig() -> AppConfig:
	var cfg := AppConfig.new()
	var data := _ReadJson(CONFIG_PATH)
	if not data.is_empty():
		cfg.patchesRepo = str(data.get("patches_repo", cfg.patchesRepo))
		cfg.pckName = str(data.get("pck_name", cfg.pckName))
		cfg.vanillaBackupName = str(data.get("vanilla_backup_name", cfg.vanillaBackupName))
		cfg.gameExeName = str(data.get("game_exe_name", cfg.gameExeName))
		cfg.steamAppId = int(data.get("steam_app_id", cfg.steamAppId))
	var settings := _ReadJson(SETTINGS_PATH)
	if settings.has("game_dir"):
		cfg.gameDir = str(settings["game_dir"])
	cfg.setupComplete = bool(settings.get("setup_complete", false))
	return cfg


func SaveSettings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({
		"game_dir": gameDir,
		"setup_complete": setupComplete,
	}, "\t"))


static func _ReadJson(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
