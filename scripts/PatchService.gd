class_name PatchService
extends RefCounted

enum PckStatus { MISSING, VANILLA, PATCHED, DIRTY, UNKNOWN }

const XDELTA_RES := "res://bin/xdelta3.exe"
const PATCH_ASSET := "modloader.xdelta"


static func PckPath(cfg: AppConfig) -> String:
	return cfg.gameDir.path_join(cfg.pckName)


static func ExePath(cfg: AppConfig, dirPath: String = "") -> String:
	var dir := cfg.gameDir if dirPath.is_empty() else dirPath
	return dir.path_join(cfg.gameExeName)


static func ExeFileVersion(_exePath: String) -> String:
	if _exePath.is_empty() or not FileAccess.file_exists(_exePath):
		return ""
	var escaped := _exePath.replace("'", "''")
	var script := "$v = (Get-Item -LiteralPath '%s').VersionInfo; if ($v.ProductVersion) { $v.ProductVersion } else { $v.FileVersion }" % escaped
	var output: Array = []
	var code := OS.execute(
		"powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", script]),
		output,
		false
	)
	if code != 0:
		return ""
	return "\n".join(output).strip_edges()


static func ReleaseTag(fileVersion: String) -> String:
	var parts := fileVersion.strip_edges().split(".")
	while parts.size() > 3 and parts[parts.size() - 1] == "0":
		parts.remove_at(parts.size() - 1)
	return ".".join(parts)


static func ReleaseApiUrl(repo: String, tag: String) -> String:
	return "https://api.github.com/repos/%s/releases/tags/%s" % [repo, tag]


static func PatchDownloadUrl(repo: String, tag: String) -> String:
	return "https://github.com/%s/releases/download/%s/%s" % [repo, tag, PATCH_ASSET]


static func AssetUrlFromRelease(release: Dictionary, repo: String, tag: String) -> String:
	var assets: Variant = release.get("assets", [])
	if typeof(assets) == TYPE_ARRAY:
		for item in assets:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if str(item.get("name", "")) == PATCH_ASSET:
				var url := str(item.get("browser_download_url", ""))
				if not url.is_empty():
					return url
	return PatchDownloadUrl(repo, tag)


static func FileLength(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()


static func VersionedBackupName(originalFilename: String, tag: String) -> String:
	return "%s-%s.%s" % [originalFilename.get_basename(), tag, originalFilename.get_extension()]


static func PckBackupPath(cfg: AppConfig, tag: String) -> String:
	return cfg.gameDir.path_join(VersionedBackupName(cfg.pckName, tag))


static func ExeBackupPath(cfg: AppConfig, tag: String) -> String:
	return cfg.gameDir.path_join(VersionedBackupName(cfg.gameExeName, tag))


static func LegacyPckBackupPath(cfg: AppConfig) -> String:
	return cfg.gameDir.path_join(cfg.vanillaBackupName)


static func ResolvePckBackup(cfg: AppConfig, tag: String) -> String:
	if not tag.is_empty():
		var versioned := PckBackupPath(cfg, tag)
		if FileAccess.file_exists(versioned):
			return versioned
	var legacy := LegacyPckBackupPath(cfg)
	if FileAccess.file_exists(legacy):
		return legacy
	if tag.is_empty():
		return ""
	return PckBackupPath(cfg, tag)


static func RelabelPckBackup(cfg: AppConfig, tag: String) -> void:
	if tag.is_empty() or cfg.gameDir.is_empty():
		return
	var versioned := PckBackupPath(cfg, tag)
	var legacy := LegacyPckBackupPath(cfg)
	if FileAccess.file_exists(legacy) and not FileAccess.file_exists(versioned):
		DirAccess.rename_absolute(legacy, versioned)


static func EnsureExeBackup(cfg: AppConfig, tag: String) -> void:
	if tag.is_empty() or cfg.gameDir.is_empty():
		return
	var dest := ExeBackupPath(cfg, tag)
	if FileAccess.file_exists(dest):
		return
	var src := ExePath(cfg)
	if FileAccess.file_exists(src):
		CopyFile(src, dest)


static func IsValidInstall(cfg: AppConfig, dirPath: String = "") -> bool:
	var dir := cfg.gameDir if dirPath.is_empty() else dirPath
	if dir.is_empty():
		return false
	return (
		FileAccess.file_exists(dir.path_join(cfg.gameExeName))
		and FileAccess.file_exists(dir.path_join(cfg.pckName))
	)


static func LooksPatched(cfg: AppConfig) -> bool:
	if not IsValidInstall(cfg):
		return false
	var tag := ReleaseTag(ExeFileVersion(ExePath(cfg)))
	var backup := ResolvePckBackup(cfg, tag)
	if backup.is_empty() or not FileAccess.file_exists(backup):
		return false
	return FileLength(PckPath(cfg)) != FileLength(backup)


static func FindGameDir(cfg: AppConfig) -> String:
	var candidates: Array[String] = []
	if not cfg.gameDir.is_empty():
		candidates.append(cfg.gameDir)
	candidates.append(OS.get_executable_path().get_base_dir())
	candidates.append(OS.get_environment("PWD"))
	candidates.append(".")
	for dirPath in candidates:
		if dirPath.is_empty():
			continue
		var abs_dir := ProjectSettings.globalize_path(dirPath)
		if FileAccess.file_exists(abs_dir.path_join(cfg.pckName)):
			return abs_dir
	return ""


static func DirFromPickedFile(path: String) -> String:
	if path.to_lower().ends_with(".pck") or path.to_lower().ends_with(".exe"):
		return path.get_base_dir()
	return path


static func XdeltaExe() -> String:
	var beside := OS.get_executable_path().get_base_dir().path_join("xdelta3.exe")
	if FileAccess.file_exists(beside) and not beside.begins_with("res://"):
		return beside
	if not FileAccess.file_exists(XDELTA_RES):
		return ""
	var bytes := FileAccess.get_file_as_bytes(XDELTA_RES)
	if bytes.is_empty():
		return ""
	var extracted := OS.get_user_data_dir().path_join("xdelta3.exe")
	DirAccess.make_dir_recursive_absolute(extracted.get_base_dir())
	var file := FileAccess.open(extracted, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return extracted


static func CopyFile(src: String, dest: String) -> Error:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	return DirAccess.copy_absolute(src, dest)


static func XdeltaTempPath(destPck: String) -> String:
	return destPck + ".new"


static func StartXdelta(sourcePck: String, patchFile: String, destPck: String) -> Dictionary:
	var exe := XdeltaExe()
	if exe.is_empty():
		return {"ok": false, "error": "xdelta3.exe was not found"}
	var tmp := XdeltaTempPath(destPck)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var pid := OS.create_process(
		exe, PackedStringArray(["-d", "-f", "-s", sourcePck, patchFile, tmp])
	)
	if pid < 0:
		return {"ok": false, "error": "Could not start xdelta3"}
	return {"ok": true, "pid": pid, "temp_path": tmp}


static func ReplaceWithTemp(tempPath: String, destPck: String) -> Dictionary:
	if FileAccess.file_exists(destPck):
		var rm := DirAccess.remove_absolute(destPck)
		if rm != OK:
			DirAccess.remove_absolute(tempPath)
			return {"ok": false, "error": "Could not replace %s" % destPck.get_file()}
	var renamed := DirAccess.rename_absolute(tempPath, destPck)
	if renamed != OK:
		DirAccess.remove_absolute(tempPath)
		return {"ok": false, "error": "Could not move patched PCK into place"}
	return {"ok": true}
