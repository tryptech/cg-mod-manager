class_name ModInventory
extends RefCounted

const STATE_FILE := "mod_manager.json"
const DISABLED_DIR_NAME := "mods-disabled"

var gameDir := ""
var entries: Array[Dictionary] = []
var loadOrder: PackedStringArray = []


func ModsDir() -> String:
	return gameDir.path_join("mods")


func DisabledDir() -> String:
	return gameDir.path_join(DISABLED_DIR_NAME)


func StatePath() -> String:
	return ModsDir().path_join(STATE_FILE)


func ZipPathFor(modId: String, enabled: bool = true) -> String:
	var folder := ModsDir() if enabled else DisabledDir()
	return folder.path_join("%s.zip" % modId)


func EnsureModsDir() -> void:
	DirAccess.make_dir_recursive_absolute(ModsDir())
	DirAccess.make_dir_recursive_absolute(DisabledDir())


func Scan() -> void:
	EnsureModsDir()
	var saved := _LoadState()
	var saved_mods: Dictionary = saved.get("mods", {})
	var saved_order: PackedStringArray = PackedStringArray()
	var raw_order: Variant = saved.get("load_order", [])
	if typeof(raw_order) == TYPE_ARRAY:
		for item in raw_order:
			saved_order.append(str(item))
	var found: Array[Dictionary] = []
	var found_ids: Dictionary = {}
	_CollectFromDir(ModsDir(), true, saved_mods, found, found_ids)
	_CollectFromDir(DisabledDir(), false, saved_mods, found, found_ids)
	var ordered: Array[Dictionary] = []
	var used: Dictionary = {}
	for modId in saved_order:
		for entry in found:
			if entry["mod_id"] == modId:
				ordered.append(entry)
				used[modId] = true
				break
	for entry in found:
		if not used.has(entry["mod_id"]):
			ordered.append(entry)
	ordered.reverse()
	entries = ordered
	for entry in entries:
		var saved_entry: Dictionary = saved_mods.get(entry["mod_id"], {})
		if typeof(saved_entry) != TYPE_DICTIONARY:
			continue
		# Migrate mods that were marked disabled but still sat in mods/.
		if entry["enabled"] and not bool(saved_entry.get("enabled", true)):
			_RelocateEntry(entry, false)
	_EnsureDependencyOrder()
	Save()


func Save() -> Dictionary:
	EnsureModsDir()
	var mods := {}
	for entry in entries:
		mods[entry["mod_id"]] = {
			"enabled": entry["enabled"],
			"zip": entry["zip"],
			"source": entry["source"],
		}
	var payload := {
		"mods": mods,
		"load_order": Array(loadOrder),
	}
	var file := FileAccess.open(StatePath(), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write %s" % STATE_FILE}
	file.store_string(JSON.stringify(payload, "\t"))
	return {"ok": true}


func AddFromZip(srcZip: String, source: Dictionary, overwrite: bool) -> Dictionary:
	var inspected := ZipMod.Inspect(srcZip)
	if not inspected.get("ok", false):
		return inspected
	var info: Dictionary = inspected["info"]
	var dest := ZipPathFor(info["mod_id"], true)
	var disabled_zip := ZipPathFor(info["mod_id"], false)
	if (FileAccess.file_exists(dest) or FileAccess.file_exists(disabled_zip)) and not overwrite:
		return {"ok": false, "exists": true, "info": info, "error": "Mod already installed"}
	EnsureModsDir()
	var packed := ZipMod.InstallZip(srcZip, dest, info, inspected["files"])
	if not packed.get("ok", false):
		return packed
	if FileAccess.file_exists(disabled_zip):
		DirAccess.remove_absolute(disabled_zip)
	_Upsert(
		info,
		dest.get_file(),
		source,
		true,
		inspected.get("icon"),
		inspected.get("preview"),
		inspected.get("added_files", PackedStringArray()),
		inspected.get("modified_files", PackedStringArray())
	)
	_EnsureDependencyOrder()
	var saved := Save()
	if not saved.get("ok", false):
		return saved
	return {"ok": true, "info": info}


func UpdateFromZip(srcZip: String, source: Dictionary) -> Dictionary:
	var inspected := ZipMod.Inspect(srcZip)
	if not inspected.get("ok", false):
		return inspected
	var info: Dictionary = inspected["info"]
	var existing := _IndexOf(info["mod_id"])
	if existing < 0:
		return AddFromZip(srcZip, source, true)
	var previous: Dictionary = entries[existing]
	var enabled := bool(previous.get("enabled", true))
	var keep_source: Dictionary = source
	if keep_source.is_empty() and typeof(previous.get("source", {})) == TYPE_DICTIONARY:
		keep_source = previous["source"]
	if keep_source.is_empty():
		keep_source = {"type": "local"}
	EnsureModsDir()
	var dest := ZipPathFor(info["mod_id"], enabled)
	var packed := ZipMod.InstallZip(srcZip, dest, info, inspected["files"])
	if not packed.get("ok", false):
		return packed
	var other := ZipPathFor(info["mod_id"], not enabled)
	if other != dest and FileAccess.file_exists(other):
		DirAccess.remove_absolute(other)
	_Upsert(
		info,
		dest.get_file(),
		keep_source,
		enabled,
		inspected.get("icon"),
		inspected.get("preview"),
		inspected.get("added_files", PackedStringArray()),
		inspected.get("modified_files", PackedStringArray())
	)
	_EnsureDependencyOrder()
	var saved := Save()
	if not saved.get("ok", false):
		return saved
	return {"ok": true, "info": info, "updated": true}


func EntryById(modId: String) -> Dictionary:
	var index := _IndexOf(modId)
	if index < 0:
		return {}
	return entries[index]


func MetadataMatches(entry: Dictionary, info: Dictionary) -> bool:
	if str(entry.get("mod_id", "")) != str(info.get("mod_id", "")):
		return false
	if str(entry.get("name", "")) != str(info.get("name", "")):
		return false
	if str(entry.get("namespace", "")) != str(info.get("namespace", "")):
		return false
	return _AuthorsMatch(entry.get("authors", []), info.get("authors", []))


func _AuthorsMatch(left: Variant, right: Variant) -> bool:
	var a := _NormalizedAuthors(left)
	var b := _NormalizedAuthors(right)
	if a.is_empty() or b.is_empty():
		return true
	if a.size() != b.size():
		return false
	for name in a:
		if not b.has(name):
			return false
	return true


func _NormalizedAuthors(value: Variant) -> PackedStringArray:
	var names := PackedStringArray()
	var raw: PackedStringArray = PackedStringArray()
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		raw = value
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			raw.append(str(item))
	for item in raw:
		var name := item.strip_edges().to_lower()
		if not name.is_empty() and not names.has(name):
			names.append(name)
	names.sort()
	return names


func RemoveMod(modId: String) -> Dictionary:
	var blockers := EnabledDependentsOf(modId)
	if not blockers.is_empty():
		return {
			"ok": false,
			"error": "Cannot remove %s while enabled mods depend on it: %s" % [modId, ", ".join(blockers)],
		}
	for enabled in [true, false]:
		var zip_file := ZipPathFor(modId, enabled)
		if FileAccess.file_exists(zip_file):
			var err := DirAccess.remove_absolute(zip_file)
			if err != OK:
				return {"ok": false, "error": "Could not delete %s.zip" % modId}
	var remaining: Array[Dictionary] = []
	for entry in entries:
		if entry["mod_id"] != modId:
			remaining.append(entry)
	entries = remaining
	_RebuildLoadOrder()
	return Save()


func SetEnabled(modId: String, enabled: bool) -> Dictionary:
	if _IndexOf(modId) < 0:
		return {"ok": false, "error": "Unknown mod"}
	var changed: PackedStringArray = PackedStringArray()
	if enabled:
		for dep_id in _CollectRequired(modId):
			if _SetOneEnabled(dep_id, true):
				changed.append(dep_id)
		if _SetOneEnabled(modId, true):
			changed.append(modId)
	else:
		if _SetOneEnabled(modId, false):
			changed.append(modId)
		for dep_id in _CollectDependents(modId):
			if _SetOneEnabled(dep_id, false):
				changed.append(dep_id)
	_EnsureDependencyOrder()
	var saved := Save()
	if not saved.get("ok", false):
		return saved
	return {"ok": true, "changed": changed}


func CanRemove(modId: String) -> bool:
	return EnabledDependentsOf(modId).is_empty()


func CanMove(modId: String, delta: int) -> bool:
	var index := _IndexOf(modId)
	if index < 0:
		return false
	var target: int = clampi(index + delta, 0, entries.size() - 1)
	if target == index:
		return false
	return _OrderValid(_Moved(index, target))


func CanMoveBefore(fromId: String, ontoId: String) -> bool:
	var from_index := _IndexOf(fromId)
	var onto_index := _IndexOf(ontoId)
	if from_index < 0 or onto_index < 0 or from_index == onto_index:
		return false
	var trial := entries.duplicate()
	var entry: Dictionary = trial[from_index]
	trial.remove_at(from_index)
	if from_index < onto_index:
		onto_index -= 1
	trial.insert(onto_index, entry)
	return _OrderValid(trial)


func MoveMod(modId: String, delta: int) -> Dictionary:
	var index := _IndexOf(modId)
	if index < 0:
		return {"ok": false, "error": "Unknown mod"}
	var target: int = clampi(index + delta, 0, entries.size() - 1)
	if target == index:
		return {"ok": true}
	if not _OrderValid(_Moved(index, target)):
		return {"ok": false, "error": "That move would break dependency order."}
	var entry: Dictionary = entries[index]
	entries.remove_at(index)
	entries.insert(target, entry)
	_RebuildLoadOrder()
	return Save()


func MoveModBefore(fromId: String, ontoId: String) -> Dictionary:
	if not CanMoveBefore(fromId, ontoId):
		return {"ok": false, "error": "That move would break dependency order."}
	var from_index := _IndexOf(fromId)
	var onto_index := _IndexOf(ontoId)
	var entry: Dictionary = entries[from_index]
	entries.remove_at(from_index)
	if from_index < onto_index:
		onto_index -= 1
	entries.insert(onto_index, entry)
	_RebuildLoadOrder()
	return Save()


func OrderWarnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for entry in entries:
		if not entry["enabled"]:
			continue
		for dep in RawDependencies(entry):
			var dep_id := _ResolveDepId(dep)
			if dep_id.is_empty():
				warnings.append("%s depends on %s, which is not installed." % [entry["mod_id"], dep])
				continue
			var dep_entry := _EntryById(dep_id)
			if not dep_entry.is_empty() and not bool(dep_entry.get("enabled", true)):
				warnings.append("%s depends on %s, which is disabled." % [entry["mod_id"], dep_id])
	return warnings


func RawDependencies(entry: Dictionary) -> PackedStringArray:
	var deps: PackedStringArray = PackedStringArray()
	var raw_deps: Variant = entry.get("dependencies", [])
	if typeof(raw_deps) == TYPE_PACKED_STRING_ARRAY:
		return raw_deps
	if typeof(raw_deps) == TYPE_ARRAY:
		for dep in raw_deps:
			var text := str(dep).strip_edges()
			if not text.is_empty():
				deps.append(text)
	return deps


func EntryDependsOn(entry: Dictionary, modId: String) -> bool:
	for dep in RawDependencies(entry):
		if _DepRefersTo(dep, _EntryById(modId)):
			return true
		if _ResolveDepId(dep) == modId:
			return true
	return false


func EnabledDependentsOf(modId: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in entries:
		if not bool(entry.get("enabled", true)):
			continue
		if str(entry.get("mod_id", "")) == modId:
			continue
		if EntryDependsOn(entry, modId):
			ids.append(str(entry["mod_id"]))
	return ids


func DependentsOf(modId: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in entries:
		if str(entry.get("mod_id", "")) == modId:
			continue
		if EntryDependsOn(entry, modId):
			ids.append(str(entry["mod_id"]))
	return ids


func FindByGithub(owner: String, repo: String) -> int:
	for i in entries.size():
		if _GithubMatches(entries[i], owner, repo):
			return i
	return -1


func IsDependencyInstalled(dep: String) -> bool:
	return not _ResolveDepId(dep).is_empty()


func _CollectFromDir(
	dirPath: String,
	enabled: bool,
	saved_mods: Dictionary,
	found: Array[Dictionary],
	found_ids: Dictionary
) -> void:
	if not DirAccess.dir_exists_absolute(dirPath):
		return
	for file_name in DirAccess.get_files_at(dirPath):
		if file_name.get_extension().to_lower() != "zip":
			continue
		var zipPath := dirPath.path_join(file_name)
		var inspected := ZipMod.Inspect(zipPath)
		if not inspected.get("ok", false):
			continue
		var info: Dictionary = inspected["info"]
		var modId: String = info["mod_id"]
		if found_ids.has(modId):
			continue
		var prev: Dictionary = saved_mods.get(modId, {})
		var source: Variant = prev.get("source", {"type": "local"})
		if typeof(source) != TYPE_DICTIONARY:
			source = {"type": "local"}
		found.append({
			"mod_id": modId,
			"zip": file_name,
			"enabled": enabled,
			"source": source,
			"name": info["name"],
			"version": info["version"],
			"description": info["description"],
			"website_url": info.get("website_url", ""),
			"namespace": info.get("namespace", ""),
			"authors": info.get("authors", PackedStringArray()),
			"dependencies": info["dependencies"],
			"load_before": info["load_before"],
			"compatible_game_version": info.get("compatible_game_version", PackedStringArray()),
			"icon": inspected.get("icon"),
			"preview": inspected.get("preview"),
			"added_files": inspected.get("added_files", PackedStringArray()),
			"modified_files": inspected.get("modified_files", PackedStringArray()),
			"update_available": false,
			"latest_version": "",
		})
		found_ids[modId] = true


func _Upsert(
	info: Dictionary,
	zip_name: String,
	source: Dictionary,
	enabled: bool,
	icon: Variant = null,
	preview: Variant = null,
	added_files: Variant = null,
	modified_files: Variant = null
) -> void:
	var existing := _IndexOf(info["mod_id"])
	var entry := {
		"mod_id": info["mod_id"],
		"zip": zip_name,
		"enabled": enabled,
		"source": source,
		"name": info["name"],
		"version": info["version"],
		"description": info["description"],
		"website_url": info.get("website_url", ""),
		"namespace": info.get("namespace", ""),
		"authors": info.get("authors", PackedStringArray()),
		"dependencies": info["dependencies"],
		"load_before": info["load_before"],
		"compatible_game_version": info.get("compatible_game_version", PackedStringArray()),
		"icon": icon,
		"preview": preview,
		"added_files": added_files if added_files != null else PackedStringArray(),
		"modified_files": modified_files if modified_files != null else PackedStringArray(),
		"update_available": false,
		"latest_version": "",
	}
	if existing >= 0:
		entries[existing] = entry
	else:
		entries.insert(0, entry)
	_RebuildLoadOrder()


func _SetOneEnabled(modId: String, enabled: bool) -> bool:
	var index := _IndexOf(modId)
	if index < 0:
		return false
	var entry: Dictionary = entries[index]
	if bool(entry.get("enabled", true)) == enabled and FileAccess.file_exists(ZipPathFor(modId, enabled)):
		return false
	_RelocateEntry(entry, enabled)
	return true


func _RelocateEntry(entry: Dictionary, enabled: bool) -> void:
	EnsureModsDir()
	var modId: String = entry["mod_id"]
	var src := ZipPathFor(modId, bool(entry.get("enabled", true)))
	if not FileAccess.file_exists(src):
		src = ZipPathFor(modId, not bool(entry.get("enabled", true)))
	var dest := ZipPathFor(modId, enabled)
	if src != dest and FileAccess.file_exists(src):
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		var err := DirAccess.rename_absolute(src, dest)
		if err != OK:
			var copy_err := DirAccess.copy_absolute(src, dest)
			if copy_err == OK:
				DirAccess.remove_absolute(src)
	entry["enabled"] = enabled
	entry["zip"] = dest.get_file()


func _CollectRequired(modId: String) -> PackedStringArray:
	var needed: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {modId: true}
	var stack: PackedStringArray = PackedStringArray([modId])
	while not stack.is_empty():
		var current := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var entry := _EntryById(current)
		if entry.is_empty():
			continue
		for dep in RawDependencies(entry):
			var dep_id := _ResolveDepId(dep)
			if dep_id.is_empty() or seen.has(dep_id):
				continue
			seen[dep_id] = true
			needed.append(dep_id)
			stack.append(dep_id)
	return needed


func _CollectDependents(modId: String) -> PackedStringArray:
	var closing: Dictionary = {modId: true}
	var changed := true
	while changed:
		changed = false
		var current_ids: Array = closing.keys()
		for entry in entries:
			var other_id: String = entry["mod_id"]
			if closing.has(other_id):
				continue
			for target in current_ids:
				if EntryDependsOn(entry, str(target)):
					closing[other_id] = true
					changed = true
					break
	var ids := PackedStringArray()
	for other_id in closing.keys():
		if str(other_id) != modId:
			ids.append(str(other_id))
	return ids


func _EnsureDependencyOrder() -> void:
	entries = _SortedByDependencies(entries)
	_RebuildLoadOrder()


func _SortedByDependencies(list: Array[Dictionary]) -> Array[Dictionary]:
	var n := list.size()
	var indegree := {}
	var edges := {}
	for entry in list:
		var modId: String = entry["mod_id"]
		indegree[modId] = 0
		edges[modId] = []
	for entry in list:
		var modId: String = entry["mod_id"]
		for dep_id in _ResolvedDepIds(entry):
			if dep_id == modId or not indegree.has(dep_id):
				continue
			edges[modId].append(dep_id)
			indegree[dep_id] = int(indegree[dep_id]) + 1
	var remaining: Dictionary = {}
	for i in n:
		remaining[i] = true
	var out: Array[Dictionary] = []
	while out.size() < n:
		var pick := -1
		for i in n:
			if not remaining.has(i):
				continue
			if int(indegree[list[i]["mod_id"]]) != 0:
				continue
			pick = i
			break
		if pick < 0:
			for i in n:
				if remaining.has(i):
					out.append(list[i])
			break
		remaining.erase(pick)
		var picked_id: String = list[pick]["mod_id"]
		out.append(list[pick])
		for nxt in edges[picked_id]:
			indegree[nxt] = int(indegree[nxt]) - 1
	return out


func _Moved(index: int, target: int) -> Array[Dictionary]:
	var trial := entries.duplicate()
	var entry: Dictionary = trial[index]
	trial.remove_at(index)
	trial.insert(target, entry)
	return trial


func _OrderValid(list: Array) -> bool:
	var ranks := {}
	for i in list.size():
		ranks[list[i]["mod_id"]] = i
	for i in list.size():
		for dep_id in _ResolvedDepIds(list[i]):
			if ranks.has(dep_id) and int(ranks[dep_id]) < i:
				return false
	return true


func _ResolvedDepIds(entry: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for dep in RawDependencies(entry):
		var dep_id := _ResolveDepId(dep)
		if not dep_id.is_empty() and not ids.has(dep_id):
			ids.append(dep_id)
	return ids


func _ResolveDepId(dep: String) -> String:
	for entry in entries:
		if _DepRefersTo(dep, entry):
			return str(entry["mod_id"])
	return ""


func _DepRefersTo(dep: String, entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	var text := dep.strip_edges()
	if text.is_empty():
		return false
	var spec := GithubModInstaller.ParseSpec(text)
	if not spec.has("error") and _GithubMatches(entry, str(spec["owner"]), str(spec["repo"])):
		return true
	var modId := str(entry.get("mod_id", ""))
	if text == modId:
		return true
	if text.begins_with(modId + "-") and _LooksLikeVersion(text.substr(modId.length() + 1)):
		return true
	return false


func _GithubMatches(entry: Dictionary, owner: String, repo: String) -> bool:
	var source: Dictionary = entry.get("source", {})
	if str(source.get("type", "")) == "github":
		if str(source.get("owner", "")).nocasecmp_to(owner) == 0 and str(source.get("repo", "")).nocasecmp_to(repo) == 0:
			return true
	var site := str(entry.get("website_url", "")).strip_edges()
	if site.is_empty():
		return false
	var spec := GithubModInstaller.ParseSpec(site)
	if spec.has("error"):
		return false
	return str(spec["owner"]).nocasecmp_to(owner) == 0 and str(spec["repo"]).nocasecmp_to(repo) == 0


func _LooksLikeVersion(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9]+(\\.[0-9]+)*$")
	return regex.search(value) != null


func _EntryById(modId: String) -> Dictionary:
	var index := _IndexOf(modId)
	if index < 0:
		return {}
	return entries[index]


func _RebuildLoadOrder() -> void:
	loadOrder = PackedStringArray()
	for i in range(entries.size() - 1, -1, -1):
		loadOrder.append(entries[i]["mod_id"])


func _IndexOf(modId: String) -> int:
	for i in entries.size():
		if entries[i]["mod_id"] == modId:
			return i
	return -1


func _LoadState() -> Dictionary:
	if not FileAccess.file_exists(StatePath()):
		return {"mods": {}, "load_order": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(StatePath()))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"mods": {}, "load_order": []}
	if typeof(parsed.get("mods", {})) != TYPE_DICTIONARY:
		parsed["mods"] = {}
	return parsed
