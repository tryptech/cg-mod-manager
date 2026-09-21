class_name GithubModInstaller
extends RefCounted


static func ParseSpec(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	if text.is_empty():
		return {"error": "Enter owner/repo"}
	if text.contains(".."):
		return {"error": "Invalid path"}
	text = text.trim_prefix("https://").trim_prefix("http://")
	text = text.trim_prefix("www.")
	var owner := ""
	var repo := ""
	var ref := ""
	if text.begins_with("github.com/"):
		var rest := text.trim_prefix("github.com/").split("?")[0].trim_suffix("/")
		if rest.ends_with(".git"):
			rest = rest.substr(0, rest.length() - 4)
		var parts := rest.split("/")
		if parts.size() < 2:
			return {"error": "Could not parse GitHub URL"}
		owner = parts[0]
		repo = parts[1]
		if parts.size() >= 4 and parts[2] == "tree":
			ref = "/".join(PackedStringArray(parts.slice(3)))
		elif parts.size() >= 4 and parts[2] == "commit":
			ref = parts[3]
		elif parts.size() >= 5 and parts[2] == "releases" and parts[3] == "tag":
			ref = parts[4]
		elif parts.size() >= 3 and parts[2] != "releases" and parts[2] != "issues" and parts[2] != "actions":
			ref = "/".join(PackedStringArray(parts.slice(2)))
	else:
		var parts := text.split("/")
		if parts.size() < 2:
			return {"error": "Use owner/repo"}
		owner = parts[0]
		repo = parts[1]
		if parts.size() > 2:
			ref = "/".join(PackedStringArray(parts.slice(2)))
	if not _IsGithubName(owner) or not _IsGithubName(repo):
		return {"error": "Invalid owner or repository name"}
	if not _IsSafeRef(ref):
		return {"error": "Invalid branch or tag"}
	return {"owner": owner, "repo": repo, "ref": ref}


func Install(http: HttpFetcher, spec: Dictionary, destZip: String) -> Dictionary:
	var owner: String = spec["owner"]
	var repo: String = spec["repo"]
	var ref: String = spec.get("ref", "")
	var repo_url := "https://api.github.com/repos/%s/%s" % [owner, repo]
	var repo_res: Dictionary = await http.RequestJson(repo_url)
	if not repo_res.get("ok", false):
		if int(repo_res.get("status", 0)) == 404:
			return {"ok": false, "error": "Repository not found"}
		return {"ok": false, "error": str(repo_res.get("error", "GitHub lookup failed"))}
	var repo_data: Dictionary = repo_res.get("data", {})
	if typeof(repo_data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Unexpected GitHub response"}
	if ref.is_empty():
		ref = str(repo_data.get("default_branch", "main"))
	var download := await _PickDownload(http, owner, repo, ref)
	if not download.get("ok", false):
		return download
	var tmp_dir := OS.get_user_data_dir().path_join("tmp")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tmp_zip := tmp_dir.path_join("github-download.zip")
	var downloaded: Dictionary = await http.DownloadFile(download["url"], tmp_zip)
	if not downloaded.get("ok", false):
		return {"ok": false, "error": str(downloaded.get("error", "Download failed"))}
	var inspected := ZipMod.Inspect(tmp_zip)
	if not inspected.get("ok", false):
		DirAccess.remove_absolute(tmp_zip)
		return inspected
	var packed := ZipMod.InstallZip(tmp_zip, destZip, inspected["info"], inspected["files"])
	DirAccess.remove_absolute(tmp_zip)
	if not packed.get("ok", false):
		return packed
	return {
		"ok": true,
		"info": inspected["info"],
		"source": {
			"type": "github",
			"owner": owner,
			"repo": repo,
			"ref": str(download.get("ref", ref)),
		},
	}


func _PickDownload(http: HttpFetcher, owner: String, repo: String, ref: String) -> Dictionary:
	var latest: Dictionary = await http.RequestJson(
		"https://api.github.com/repos/%s/%s/releases/latest" % [owner, repo]
	)
	if latest.get("ok", false) and typeof(latest.get("data", {})) == TYPE_DICTIONARY:
		var data: Dictionary = latest["data"]
		var zip_url := _PickReleaseZip(data.get("assets", []))
		if not zip_url.is_empty():
			return {
				"ok": true,
				"url": zip_url,
				"ref": str(data.get("tag_name", ref)),
			}
	var zipball := "https://api.github.com/repos/%s/%s/zipball/%s" % [owner, repo, ref]
	return {"ok": true, "url": zipball, "ref": ref}


func _PickReleaseZip(assets: Variant) -> String:
	if typeof(assets) != TYPE_ARRAY:
		return ""
	var fallback := ""
	for asset in assets:
		if typeof(asset) != TYPE_DICTIONARY:
			continue
		var asset_name := str(asset.get("name", "")).to_lower()
		if not asset_name.ends_with(".zip"):
			continue
		var url := str(asset.get("browser_download_url", ""))
		if url.is_empty():
			continue
		if asset_name.contains("source"):
			if fallback.is_empty():
				fallback = url
			continue
		return url
	return fallback


func LatestReleaseTag(http: HttpFetcher, owner: String, repo: String) -> Dictionary:
	var latest: Dictionary = await http.RequestJson(
		"https://api.github.com/repos/%s/%s/releases/latest" % [owner, repo]
	)
	if not latest.get("ok", false):
		if int(latest.get("status", 0)) == 404:
			return {"ok": true, "tag": ""}
		return {"ok": false, "error": str(latest.get("error", "GitHub lookup failed")), "status": int(latest.get("status", 0))}
	var data: Dictionary = latest.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Unexpected GitHub response"}
	return {"ok": true, "tag": str(data.get("tag_name", "")).strip_edges()}


static func StripVersionPrefix(value: String) -> String:
	var text := value.strip_edges()
	if text.begins_with("v") or text.begins_with("V"):
		text = text.substr(1)
	var cut := text.find("-")
	if cut >= 0:
		text = text.substr(0, cut)
	cut = text.find("+")
	if cut >= 0:
		text = text.substr(0, cut)
	return text


static func VersionIsNewer(remote: String, local: String) -> bool:
	var remote_parts := _VersionParts(remote)
	var local_parts := _VersionParts(local)
	if remote_parts.is_empty():
		return false
	if local_parts.is_empty():
		return true
	var count: int = maxi(remote_parts.size(), local_parts.size())
	for i in count:
		var remote_n: int = remote_parts[i] if i < remote_parts.size() else 0
		var local_n: int = local_parts[i] if i < local_parts.size() else 0
		if remote_n != local_n:
			return remote_n > local_n
	return false


static func _VersionParts(value: String) -> PackedInt32Array:
	var parts := PackedInt32Array()
	var text := StripVersionPrefix(value)
	if text.is_empty():
		return parts
	for piece in text.split("."):
		if not piece.is_valid_int():
			return PackedInt32Array()
		parts.append(int(piece))
	return parts


static func _IsGithubName(value: String) -> bool:
	if value.is_empty() or value == "." or value == "..":
		return false
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9._-]+$")
	return regex.search(value) != null


static func _IsSafeRef(value: String) -> bool:
	if value.is_empty():
		return true
	if value.contains("..") or value.begins_with("/") or value.contains("\\"):
		return false
	return true
