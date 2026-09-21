class_name HttpFetcher
extends Node

signal download_progressed(downloaded: int, total: int)

const USER_AGENT := "ChronoGear-Mod-Manager/0.1"


func RequestJson(url: String, extraHeaders: PackedStringArray = PackedStringArray()) -> Dictionary:
	var req := _MakeRequest()
	req.timeout = 30
	var err := req.request(url, _Headers(extraHeaders))
	if err != OK:
		req.queue_free()
		return _Fail("Could not start request (%s)" % error_string(err))
	var completed: Array = await req.request_completed
	req.queue_free()
	return _ParseCompleted(completed, true)


func DownloadFile(url: String, destPath: String, extraHeaders: PackedStringArray = PackedStringArray()) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(destPath.get_base_dir())
	if FileAccess.file_exists(destPath):
		DirAccess.remove_absolute(destPath)
	var req := _MakeRequest()
	req.timeout = 0
	req.use_threads = false
	req.max_redirects = 8
	req.download_file = destPath
	var headers := PackedStringArray([
		"User-Agent: %s" % USER_AGENT,
		"Accept: application/octet-stream, */*",
	])
	headers.append_array(extraHeaders)
	var state := {"done": false, "result": 0, "code": 0, "headers": PackedStringArray(), "body": PackedByteArray()}
	req.request_completed.connect(func(result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
		state["result"] = result
		state["code"] = code
		state["headers"] = response_headers
		state["body"] = body
		state["done"] = true
	)
	var err := req.request(url, headers)
	if err != OK:
		req.queue_free()
		return _Fail("Could not start download (%s)" % error_string(err))
	while not state["done"]:
		var got := req.get_downloaded_bytes()
		var total := req.get_body_size()
		download_progressed.emit(got, total)
		if total > 0 and got >= total and _FileLength(destPath) >= total:
			state["done"] = true
			state["result"] = HTTPRequest.RESULT_SUCCESS
			state["code"] = 200
			break
		await get_tree().process_frame
	req.cancel_request()
	req.queue_free()
	var parsed := _ParseCompleted(
		[state["result"], state["code"], state["headers"], state["body"]],
		false
	)
	if not parsed.get("ok", false):
		if FileAccess.file_exists(destPath):
			DirAccess.remove_absolute(destPath)
		return parsed
	if not FileAccess.file_exists(destPath):
		return _Fail("Download finished but the patch file was missing.")
	return parsed


func _FileLength(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()


func _MakeRequest() -> HTTPRequest:
	var req := HTTPRequest.new()
	add_child(req)
	req.max_redirects = 8
	req.use_threads = true
	return req


func _Headers(extra: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray([
		"User-Agent: %s" % USER_AGENT,
		"Accept: application/vnd.github+json, application/json, */*",
	])
	out.append_array(extra)
	return out


func _ParseCompleted(completed: Array, parseJson: bool) -> Dictionary:
	if completed.size() < 4:
		return _Fail("Empty HTTP response")
	var result: int = completed[0]
	var code: int = completed[1]
	var headers: PackedStringArray = completed[2]
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _Fail("HTTP request failed (%s)" % result)
	if code == 404:
		return _Fail("Not found (404)", code)
	if code == 403:
		var msg := body.get_string_from_utf8()
		if msg.to_lower().contains("rate limit"):
			return _Fail("GitHub rate limit reached. Try again later.", code)
		return _Fail("Forbidden (403). %s" % msg.strip_edges(), code)
	if code != 0 and (code < 200 or code >= 300):
		return _Fail("HTTP %s" % code, code)
	if not parseJson:
		return {"ok": true, "status": code, "headers": headers}
	var text := body.get_string_from_utf8()
	if text.is_empty():
		return {"ok": true, "status": code, "data": {}}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return _Fail("Response was not valid JSON", code)
	return {"ok": true, "status": code, "data": parsed, "headers": headers}


func _Fail(message: String, status: int = 0) -> Dictionary:
	return {"ok": false, "error": message, "status": status}
