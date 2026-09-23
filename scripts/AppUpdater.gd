class_name AppUpdater
extends RefCounted

const UPDATE_DIR_NAME := "update"
const STAGED_EXE_NAME := "CGMM.exe"
const APPLY_SCRIPT_NAME := "apply-update.ps1"
const ERROR_FILE_NAME := "update-error.txt"


## Reads and clears an error left by a previous update attempt.
static func ConsumeUpdateError() -> String:
	var path := _UpdateDir().path_join(ERROR_FILE_NAME)
	if not FileAccess.file_exists(path):
		return ""
	var text := FileAccess.get_file_as_string(path).trim_prefix("\uFEFF").strip_edges()
	DirAccess.remove_absolute(path)
	return text


## Downloads a release zip, extracts the executable, and starts a helper that
## replaces this program after it exits.
static func DownloadAndRelaunch(http: HttpFetcher, zipUrl: String) -> Dictionary:
	var ready := _Prepare()
	if not ready.get("ok", false):
		return ready
	var update_dir: String = ready["dir"]
	var dest_exe: String = ready["dest_exe"]
	var zip_path := update_dir.path_join("CGMM.zip")
	var downloaded: Dictionary = await http.DownloadFile(zipUrl, zip_path)
	if not downloaded.get("ok", false):
		return {"ok": false, "error": str(downloaded.get("error", "Could not download the update"))}
	var staged := update_dir.path_join(STAGED_EXE_NAME)
	var extracted := _ExtractExe(zip_path, staged, dest_exe.get_file())
	if FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)
	if not extracted.get("ok", false):
		return extracted
	return await _ScheduleRelaunch(http, update_dir, staged, dest_exe)


static func _Prepare() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Updates can only be installed on Windows."}
	if OS.has_feature("editor"):
		return {"ok": false, "error": "Updates can only be installed from the exported program."}
	var dest_exe := OS.get_executable_path()
	if dest_exe.is_empty() or not dest_exe.to_lower().ends_with(".exe"):
		return {"ok": false, "error": "Could not find the mod manager executable."}
	var update_dir := _UpdateDir()
	var made := DirAccess.make_dir_recursive_absolute(update_dir)
	if made != OK and not DirAccess.dir_exists_absolute(update_dir):
		return {"ok": false, "error": "Could not create the update folder."}
	var error_path := update_dir.path_join(ERROR_FILE_NAME)
	if FileAccess.file_exists(error_path):
		DirAccess.remove_absolute(error_path)
	return {"ok": true, "dir": update_dir, "dest_exe": dest_exe}


static func _ExtractExe(zipPath: String, destPath: String, preferredName: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(zipPath)
	if err != OK:
		return {"ok": false, "error": "Could not open the update zip (%s)." % error_string(err)}
	var chosen := _PickExe(reader.get_files(), preferredName)
	if chosen.is_empty():
		reader.close()
		return {"ok": false, "error": "The update zip does not contain CGMM.exe."}
	var bytes := reader.read_file(chosen)
	reader.close()
	if bytes.size() < 2 or bytes[0] != 0x4D or bytes[1] != 0x5A:
		return {"ok": false, "error": "The update zip did not contain a Windows executable."}
	DirAccess.make_dir_recursive_absolute(destPath.get_base_dir())
	if FileAccess.file_exists(destPath):
		DirAccess.remove_absolute(destPath)
	var file := FileAccess.open(destPath, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write the updated executable."}
	file.store_buffer(bytes)
	file.close()
	if not FileAccess.file_exists(destPath):
		return {"ok": false, "error": "Could not write the updated executable."}
	return {"ok": true}


static func _ScheduleRelaunch(http: HttpFetcher, updateDir: String, stagedExe: String, destExe: String) -> Dictionary:
	var script_path := updateDir.path_join(APPLY_SCRIPT_NAME)
	var error_path := updateDir.path_join(ERROR_FILE_NAME)
	var wrote := _WriteApplyScript(script_path, OS.get_process_id(), stagedExe, destExe, error_path)
	if wrote != OK:
		return {"ok": false, "error": "Could not prepare the update script."}
	var pid := _LaunchApplyScript(script_path)
	if pid < 0:
		return {"ok": false, "error": "Could not start the update script."}
	await http.get_tree().create_timer(0.6).timeout
	return {"ok": true}


static func _PickExe(files: PackedStringArray, preferredName: String) -> String:
	var preferred := preferredName.to_lower()
	var match_name := ""
	var match_depth := 9999
	var cgmm := ""
	var cgmm_depth := 9999
	var only := ""
	var exe_count := 0
	for path in files:
		if not _IsExeEntry(path):
			continue
		exe_count += 1
		only = path
		var depth := path.split("/").size()
		var file_name := path.get_file().to_lower()
		if file_name == preferred and depth < match_depth:
			match_name = path
			match_depth = depth
		if file_name == "cgmm.exe" and depth < cgmm_depth:
			cgmm = path
			cgmm_depth = depth
	if not match_name.is_empty():
		return match_name
	if not cgmm.is_empty():
		return cgmm
	if exe_count == 1:
		return only
	return ""


static func _IsExeEntry(path: String) -> bool:
	if path.ends_with("/") or path.contains(".."):
		return false
	if path.begins_with("__MACOSX/") or path.contains("/__MACOSX/"):
		return false
	return path.get_file().to_lower().ends_with(".exe")


static func _WriteApplyScript(scriptPath: String, pid: int, stagedExe: String, destExe: String, errorPath: String) -> Error:
	var work := destExe.get_base_dir()
	var staged_q := _PsQuote(stagedExe)
	var dest_q := _PsQuote(destExe)
	var work_q := _PsQuote(work)
	var error_q := _PsQuote(errorPath)
	var script_q := _PsQuote(scriptPath)
	var body := "\n".join(PackedStringArray([
		"$ErrorActionPreference = 'Stop'",
		"$targetPid = %d" % pid,
		"$stagedExe = %s" % staged_q,
		"$destExe = %s" % dest_q,
		"$workDir = %s" % work_q,
		"$errorFile = %s" % error_q,
		"$scriptFile = %s" % script_q,
		"$destNew = $destExe + '.new'",
		"$lastError = 'Could not replace the mod manager executable.'",
		"function Start-Manager {",
		"  for ($n = 0; $n -lt 20; $n++) {",
		"    try {",
		"      Start-Process -FilePath $destExe -WorkingDirectory $workDir",
		"      return",
		"    } catch {",
		"      $script:lastError = $_.Exception.Message",
		"      Start-Sleep -Milliseconds 300",
		"    }",
		"  }",
		"  throw $script:lastError",
		"}",
		"try {",
		"  $deadline = (Get-Date).AddSeconds(45)",
		"  while (Get-Process -Id $targetPid -ErrorAction SilentlyContinue) {",
		"    if ((Get-Date) -gt $deadline) { throw 'Timed out waiting for CG Mod Manager to close.' }",
		"    Start-Sleep -Milliseconds 200",
		"  }",
		"  Copy-Item -LiteralPath $stagedExe -Destination $destNew -Force",
		"  $replaced = $false",
		"  for ($i = 0; $i -lt 50; $i++) {",
		"    try {",
		"      $existing = Get-Item -LiteralPath $destExe -ErrorAction SilentlyContinue",
		"      if ($existing -and $existing.IsReadOnly) { $existing.IsReadOnly = $false }",
		"      [System.IO.File]::Replace($destNew, $destExe, [NullString]::Value)",
		"      $replaced = $true",
		"      break",
		"    } catch {",
		"      $lastError = $_.Exception.Message",
		"      Start-Sleep -Milliseconds 200",
		"    }",
		"  }",
		"  if (-not $replaced) {",
		"    Remove-Item -LiteralPath $destNew -Force -ErrorAction SilentlyContinue",
		"    throw $lastError",
		"  }",
		"  Remove-Item -LiteralPath $stagedExe -Force -ErrorAction SilentlyContinue",
		"  Start-Manager",
		"  Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue",
		"} catch {",
		"  Set-Content -LiteralPath $errorFile -Value $_.Exception.Message -Encoding utf8",
		"  if (-not (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)) {",
		"    if (Test-Path -LiteralPath $destExe) { Start-Manager }",
		"  }",
		"}",
		"",
	]))
	var file := FileAccess.open(scriptPath, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_8(0xEF)
	file.store_8(0xBB)
	file.store_8(0xBF)
	file.store_string(body)
	file.close()
	return OK


static func _LaunchApplyScript(scriptPath: String) -> int:
	var root := OS.get_environment("SystemRoot")
	var powershell := root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(powershell):
		powershell = "powershell.exe"
	return OS.create_process(powershell, PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", scriptPath,
	]))


static func _PsQuote(value: String) -> String:
	return "'" + value.replace("'", "''") + "'"


static func _UpdateDir() -> String:
	return OS.get_user_data_dir().path_join(UPDATE_DIR_NAME)
