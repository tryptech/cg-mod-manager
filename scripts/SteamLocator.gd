class_name SteamLocator
extends RefCounted

## Locates CG in Steam libraries via registry + libraryfolders.vdf,
## then appmanifest_<id>.acf for the install folder name.


static func FindGame(exeName: String, pckName: String, appId: int) -> Dictionary:
	var libraries := _LibraryRoots()
	for lib in libraries:
		var from_acf := _FromAppmanifest(lib, exeName, pckName, appId)
		if not from_acf.is_empty():
			return {"ok": true, "path": from_acf, "source": "steam"}
		var from_scan := _ScanCommon(lib, exeName, pckName)
		if not from_scan.is_empty():
			return {"ok": true, "path": from_scan, "source": "steam"}
	return {"ok": false, "error": "CG was not found in Steam libraries"}


static func IsGameDir(dirPath: String, exeName: String, pckName: String) -> bool:
	if dirPath.is_empty():
		return false
	return FileAccess.file_exists(dirPath.path_join(exeName)) and FileAccess.file_exists(dirPath.path_join(pckName))


static func _LibraryRoots() -> PackedStringArray:
	var roots := PackedStringArray()
	var steam := _SteamInstallDir()
	if not steam.is_empty():
		_AddUnique(roots, steam)
		_AddVdfLibraries(roots, steam.path_join("steamapps").path_join("libraryfolders.vdf"))
		_AddVdfLibraries(roots, steam.path_join("config").path_join("libraryfolders.vdf"))
	for fallback in _FallbackSteamDirs():
		if DirAccess.dir_exists_absolute(fallback):
			_AddUnique(roots, fallback)
			_AddVdfLibraries(roots, fallback.path_join("steamapps").path_join("libraryfolders.vdf"))
	return roots


static func _SteamInstallDir() -> String:
	var from_reg := _RegValue("HKCU\\Software\\Valve\\Steam", "SteamPath")
	if from_reg.is_empty():
		from_reg = _RegValue("HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath")
	if from_reg.is_empty():
		from_reg = _RegValue("HKLM\\SOFTWARE\\Valve\\Steam", "InstallPath")
	return _NormalizeDir(from_reg)


static func _FallbackSteamDirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	var x86 := OS.get_environment("ProgramFiles(x86)")
	var pf := OS.get_environment("ProgramFiles")
	if not x86.is_empty():
		dirs.append(x86.path_join("Steam"))
	if not pf.is_empty():
		dirs.append(pf.path_join("Steam"))
	dirs.append("C:/Program Files (x86)/Steam")
	dirs.append("C:/Program Files/Steam")
	return dirs


static func _FromAppmanifest(library: String, exeName: String, pckName: String, appId: int) -> String:
	var acf := library.path_join("steamapps").path_join("appmanifest_%s.acf" % appId)
	if not FileAccess.file_exists(acf):
		return ""
	var installdir := _QuotedValue(FileAccess.get_file_as_string(acf), "installdir")
	if installdir.is_empty():
		return ""
	var game := library.path_join("steamapps").path_join("common").path_join(installdir)
	if IsGameDir(game, exeName, pckName):
		return game
	return ""


static func _ScanCommon(library: String, exeName: String, pckName: String) -> String:
	var common := library.path_join("steamapps").path_join("common")
	if not DirAccess.dir_exists_absolute(common):
		return ""
	for folder in DirAccess.get_directories_at(common):
		var game := common.path_join(folder)
		if IsGameDir(game, exeName, pckName):
			return game
	return ""


static func _AddVdfLibraries(roots: PackedStringArray, vdfPath: String) -> void:
	if not FileAccess.file_exists(vdfPath):
		return
	var regex := RegEx.new()
	regex.compile("\"path\"\\s+\"([^\"]+)\"")
	for match in regex.search_all(FileAccess.get_file_as_string(vdfPath)):
		var lib := _NormalizeDir(match.get_string(1))
		if not lib.is_empty() and DirAccess.dir_exists_absolute(lib):
			_AddUnique(roots, lib)


static func _QuotedValue(text: String, key: String) -> String:
	var regex := RegEx.new()
	regex.compile("\"%s\"\\s+\"([^\"]+)\"" % key)
	var match := regex.search(text)
	if match == null:
		return ""
	return match.get_string(1).replace("\\\\", "\\")


static func _RegValue(key: String, valueName: String) -> String:
	if OS.get_name() != "Windows":
		return ""
	var output: Array = []
	var code := OS.execute("reg", PackedStringArray(["query", key, "/v", valueName]), output, true)
	if code != 0:
		return ""
	var blob := "\n".join(PackedStringArray(output))
	var regex := RegEx.new()
	regex.compile("%s\\s+REG_SZ\\s+(.+)" % valueName)
	var match := regex.search(blob)
	if match == null:
		return ""
	return match.get_string(1).strip_edges()


static func _NormalizeDir(path: String) -> String:
	var cleaned := path.strip_edges().replace("\\\\", "/").replace("\\", "/")
	if cleaned.ends_with("/"):
		cleaned = cleaned.left(cleaned.length() - 1)
	return cleaned


static func _AddUnique(roots: PackedStringArray, path: String) -> void:
	var normalized := _NormalizeDir(path)
	if normalized.is_empty():
		return
	for existing in roots:
		if existing.to_lower() == normalized.to_lower():
			return
	roots.append(normalized)
