class_name ZipMod
extends RefCounted


static func Inspect(zipPath: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(zipPath)
	if err != OK:
		return {"ok": false, "error": "Could not open zip (%s)" % error_string(err)}
	var files := reader.get_files()
	var manifestPath := _FindManifestPath(files)
	if manifestPath.is_empty():
		return {"ok": false, "error": "No manifest.json found in zip"}
	var raw := reader.read_file(manifestPath)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "manifest.json is not a JSON object"}
	var data: Dictionary = parsed
	var mod_namespace := str(data.get("namespace", "")).strip_edges()
	var mod_name := str(data.get("name", "")).strip_edges()
	if mod_namespace.is_empty() or mod_name.is_empty():
		return {"ok": false, "error": "manifest.json is missing namespace or name"}
	var info := {
		"mod_id": "%s-%s" % [mod_namespace, mod_name],
		"namespace": mod_namespace,
		"name": mod_name,
		"version": str(data.get("version_number", "")),
		"description": str(data.get("description", "")),
		"website_url": str(data.get("website_url", "")).strip_edges(),
		"authors": PackedStringArray(),
		"dependencies": PackedStringArray(),
		"load_before": PackedStringArray(),
		"compatible_game_version": PackedStringArray(),
		"manifest_path": manifestPath,
		"root_prefix": _RootPrefix(manifestPath),
	}
	var deps: Variant = data.get("dependencies", [])
	if typeof(deps) == TYPE_ARRAY:
		for dep in deps:
			info["dependencies"].append(str(dep))
	var extra: Variant = data.get("extra", {})
	if typeof(extra) == TYPE_DICTIONARY:
		var godot_details: Variant = extra.get("godot", {})
		if typeof(godot_details) == TYPE_DICTIONARY:
			var authors: Variant = godot_details.get("authors", [])
			if typeof(authors) == TYPE_ARRAY:
				for author in authors:
					var author_name := str(author).strip_edges()
					if not author_name.is_empty():
						info["authors"].append(author_name)
			var load_before: Variant = godot_details.get("load_before", [])
			if typeof(load_before) == TYPE_ARRAY:
				for item in load_before:
					info["load_before"].append(str(item))
			var compatible: Variant = godot_details.get("compatible_game_version", [])
			if typeof(compatible) == TYPE_ARRAY:
				for item in compatible:
					var version := str(item).strip_edges()
					if not version.is_empty():
						info["compatible_game_version"].append(version)
	var main_path: String = str(info["root_prefix"]).path_join("mod_main.gd").trim_prefix("/")
	if info["root_prefix"] == "":
		main_path = "mod_main.gd"
	if not files.has(main_path) and not files.has(str(info["root_prefix"]) + "/mod_main.gd"):
		# ZIPReader may omit or include a leading folder slash inconsistently.
		var found_main := false
		var prefix: String = info["root_prefix"]
		for path in files:
			if path.get_file() != "mod_main.gd":
				continue
			if prefix.is_empty() or path.begins_with(prefix + "/") or path.get_base_dir() == prefix:
				found_main = true
				break
		if not found_main:
			return {"ok": false, "error": "mod_main.gd is missing next to manifest.json"}
	info["icon_path"] = _ResolveIconPath(files, info, data)
	info["preview_path"] = _ResolvePreviewPath(files, info, data)
	var icon: Texture2D = null
	if not str(info["icon_path"]).is_empty():
		icon = _TextureFromBytes(reader.read_file(info["icon_path"]), str(info["icon_path"]))
	var preview: Texture2D = null
	if not str(info["preview_path"]).is_empty():
		preview = _TextureFromBytes(reader.read_file(info["preview_path"]), str(info["preview_path"]))
	var classified := _ClassifyFiles(files, info, reader)
	return {
		"ok": true,
		"info": info,
		"files": files,
		"icon": icon,
		"preview": preview,
		"added_files": classified["added"],
		"modified_files": classified["modified"],
	}


static func IsGmlPacked(info: Dictionary, files: PackedStringArray) -> bool:
	var expected := "mods-unpacked/%s/" % info["mod_id"]
	var has_manifest := false
	var has_main := false
	for path in files:
		if path.contains(".."):
			return false
		if path.begins_with("__MACOSX/") or path.begins_with(".git/"):
			continue
		if path.begins_with(expected):
			if path == expected + "manifest.json":
				has_manifest = true
			elif path == expected + "mod_main.gd":
				has_main = true
			continue
		if path.ends_with("/"):
			continue
		return false
	return has_manifest and has_main


static func InstallZip(srcZip: String, destZip: String, info: Dictionary, files: PackedStringArray) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(destZip.get_base_dir())
	if FileAccess.file_exists(destZip) and destZip != srcZip:
		DirAccess.remove_absolute(destZip)
	if IsGmlPacked(info, files):
		var copy_err := DirAccess.copy_absolute(srcZip, destZip)
		if copy_err != OK:
			return {"ok": false, "error": "Could not copy zip (%s)" % error_string(copy_err)}
		return {"ok": true}
	return Repack(srcZip, destZip, info)


static func Repack(srcZip: String, destZip: String, info: Dictionary) -> Dictionary:
	var reader := ZIPReader.new()
	var open_err := reader.open(srcZip)
	if open_err != OK:
		return {"ok": false, "error": "Could not open zip (%s)" % error_string(open_err)}
	if FileAccess.file_exists(destZip):
		DirAccess.remove_absolute(destZip)
	var packer := ZIPPacker.new()
	var pack_err := packer.open(destZip)
	if pack_err != OK:
		return {"ok": false, "error": "Could not write zip (%s)" % error_string(pack_err)}
	var prefix: String = str(info.get("root_prefix", ""))
	var dest_root := "mods-unpacked/%s" % info["mod_id"]
	for path in reader.get_files():
		if path.ends_with("/") or path.contains(".."):
			continue
		if path.begins_with("__MACOSX/") or path.contains("/.git/") or path.begins_with(".git/"):
			continue
		if path.get_file() == ".DS_Store":
			continue
		if not prefix.is_empty() and not path.begins_with(prefix + "/") and path != prefix:
			continue
		var relative := path
		if not prefix.is_empty():
			relative = path.substr(prefix.length()).trim_prefix("/")
		if relative.is_empty():
			continue
		var destPath := dest_root.path_join(relative)
		packer.start_file(destPath)
		packer.write_file(reader.read_file(path))
		packer.close_file()
	packer.close()
	return {"ok": true}


static func _FindManifestPath(files: PackedStringArray) -> String:
	var candidates: Array[String] = []
	for path in files:
		if path.get_file() == "manifest.json" and not path.begins_with("__MACOSX/"):
			candidates.append(path)
	if candidates.is_empty():
		return ""
	var scored: Array[Dictionary] = []
	for path in candidates:
		var score := 0
		if path.begins_with("mods-unpacked/"):
			score += 30
		var sibling := path.get_base_dir().path_join("mod_main.gd")
		if files.has(sibling):
			score += 20
		var depth := path.split("/").size()
		score -= depth
		scored.append({"path": path, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return scored[0]["path"]


static func _RootPrefix(manifestPath: String) -> String:
	if not manifestPath.contains("/"):
		return ""
	return manifestPath.get_base_dir()


static func _ClassifyFiles(files: PackedStringArray, info: Dictionary, reader: ZIPReader) -> Dictionary:
	var added := PackedStringArray()
	var modified := PackedStringArray()
	for path in files:
		if path.ends_with("/") or path.contains(".."):
			continue
		if path.begins_with("__MACOSX/") or path.begins_with(".git/") or path.contains("/.git/"):
			continue
		var file_name := path.get_file()
		if file_name == ".DS_Store" or file_name == "manifest.json":
			continue
		var ext := path.get_extension().to_lower()
		if ext == "uid" or ext == "import":
			continue
		var relative := _ModRelativePath(path, info)
		if relative.is_empty():
			continue
		var modified_path := _ModifiedSourcePath(relative, path, reader)
		if modified_path.is_empty():
			if not added.has(relative):
				added.append(relative)
		elif not modified.has(modified_path):
			modified.append(modified_path)
	added.sort()
	modified.sort()
	return {"added": added, "modified": modified}


static func _ModRelativePath(path: String, info: Dictionary) -> String:
	var relative := path.replace("\\", "/")
	var prefix := str(info.get("root_prefix", "")).replace("\\", "/")
	if not prefix.is_empty():
		if relative == prefix:
			return ""
		if relative.begins_with(prefix + "/"):
			relative = relative.substr(prefix.length() + 1)
	var packed_root := "mods-unpacked/%s/" % info["mod_id"]
	if relative.begins_with(packed_root):
		relative = relative.substr(packed_root.length())
	return relative.trim_prefix("/")


static func _ModifiedSourcePath(relative: String, zipPath: String, reader: ZIPReader) -> String:
	var rest := ""
	if relative.begins_with("extensions/"):
		rest = relative.substr(11)
	elif relative.begins_with("overwrite/"):
		return "res://%s" % relative.substr(10)
	else:
		return ""
	if rest.is_empty():
		return ""
	if relative.get_extension().to_lower() == "gd":
		var from_extends := _ExtendsPathFromScript(reader.read_file(zipPath).get_string_from_utf8())
		if not from_extends.is_empty():
			return from_extends
	return "res://%s" % rest


static func _ExtendsPathFromScript(source: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?m)^extends\\s+[\"'](res://[^\"']+)[\"']")
	var matched := regex.search(source)
	if matched == null:
		return ""
	return matched.get_string(1)


static func SupportsGameVersion(info: Dictionary, gameTag: String) -> bool:
	var supported := PackedStringArray()
	var raw: Variant = info.get("compatible_game_version", [])
	if typeof(raw) == TYPE_PACKED_STRING_ARRAY:
		supported = raw
	elif typeof(raw) == TYPE_ARRAY:
		for item in raw:
			var text := str(item).strip_edges()
			if not text.is_empty():
				supported.append(text)
	if supported.is_empty():
		return true
	var tag := GithubModInstaller.StripVersionPrefix(gameTag)
	if tag.is_empty():
		return true
	for listed in supported:
		var version := GithubModInstaller.StripVersionPrefix(listed)
		if version.is_empty() or version == "*":
			return true
		if version == tag or tag.begins_with(version + ".") or version.begins_with(tag + "."):
			return true
	return false


static func _ResolveIconPath(files: PackedStringArray, info: Dictionary, data: Dictionary) -> String:
	var prefix: String = str(info.get("root_prefix", ""))
	var configured := ""
	var extra: Variant = data.get("extra", {})
	if typeof(extra) == TYPE_DICTIONARY:
		var godot_details: Variant = extra.get("godot", {})
		if typeof(godot_details) == TYPE_DICTIONARY:
			configured = str(godot_details.get("icon", "")).strip_edges()
			if configured.is_empty():
				var image_field: Variant = godot_details.get("image", "")
				if typeof(image_field) == TYPE_STRING:
					configured = str(image_field).strip_edges()
	if not configured.is_empty():
		configured = configured.replace("\\", "/").trim_prefix("res://").trim_prefix("/")
		var configured_path := prefix.path_join(configured) if not prefix.is_empty() else configured
		if files.has(configured_path):
			return configured_path
		if files.has(configured):
			return configured
	for file_name in PackedStringArray(["icon.png", "icon.jpg", "icon.jpeg", "icon.webp"]):
		var candidate := prefix.path_join(file_name) if not prefix.is_empty() else file_name
		if files.has(candidate):
			return candidate
	return ""


static func _ResolvePreviewPath(files: PackedStringArray, info: Dictionary, data: Dictionary) -> String:
	var prefix: String = str(info.get("root_prefix", ""))
	var configured := ""
	var extra: Variant = data.get("extra", {})
	if typeof(extra) == TYPE_DICTIONARY:
		var godot_details: Variant = extra.get("godot", {})
		if typeof(godot_details) == TYPE_DICTIONARY:
			configured = str(godot_details.get("preview", "")).strip_edges()
	if not configured.is_empty():
		configured = configured.replace("\\", "/").trim_prefix("res://").trim_prefix("/")
		var configured_path := prefix.path_join(configured) if not prefix.is_empty() else configured
		if files.has(configured_path):
			return configured_path
		if files.has(configured):
			return configured
	for file_name in PackedStringArray(["preview.png", "preview.jpg", "preview.jpeg", "preview.webp"]):
		var candidate := prefix.path_join(file_name) if not prefix.is_empty() else file_name
		if files.has(candidate):
			return candidate
	return ""


static func _TextureFromBytes(bytes: PackedByteArray, path: String) -> Texture2D:
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_INVALID_DATA
	match path.get_extension().to_lower():
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
		_:
			return null
	if err != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
