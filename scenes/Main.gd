extends Control

const ModRowScene := preload("res://scenes/mod_row.tscn")
const GITHUB_REPO_URL := "https://github.com/tryptech/cg-mod-manager"

@onready var status: Label = %Status
@onready var versionLabel: Label = %Version
@onready var pathLabel: Label = %PathLabel
@onready var progress: ProgressBar = %Progress
@onready var emptyLabel: Label = %EmptyLabel
@onready var topButton: Button = %TopButton
@onready var upButton: Button = %UpButton
@onready var downButton: Button = %DownButton
@onready var addButton: Button = %AddButton
@onready var removeButton: Button = %RemoveButton
@onready var modList: VBoxContainer = %ModList
@onready var warning: Label = %Warning
@onready var browseDialog: FileDialog = %BrowseDialog
@onready var zipDialog: FileDialog = %ZipDialog
@onready var confirmDialog: ConfirmationDialog = %ConfirmDialog
@onready var wizard: SetupWizard = %SetupWizard
@onready var installMod: InstallModDialog = %InstallModDialog
@onready var modsMenu: PopupMenu = %Mods
@onready var settingsMenu: PopupMenu = %Settings
@onready var gameMenu: PopupMenu = %Game
@onready var infoMenu: PopupMenu = %Info
@onready var detailsEmpty: Label = %DetailsEmpty
@onready var detailsScroll: ScrollContainer = %DetailsScroll
@onready var detailsPreview: TextureRect = %DetailsPreview
@onready var detailsName: Label = %DetailsName
@onready var detailsMeta: RichTextLabel = %DetailsMeta
@onready var detailsSource: Label = %DetailsSource
@onready var detailsStatus: Label = %DetailsStatus
@onready var detailsUpdate: Button = %DetailsUpdate
@onready var detailsDescription: Label = %DetailsDescription
@onready var detailsSourceCode: LinkButton = %DetailsSourceCode
@onready var detailsReport: LinkButton = %DetailsReport
@onready var detailsDeps: Label = %DetailsDeps
@onready var detailsWebsite: Label = %DetailsWebsite
@onready var detailsFilesToggle: Button = %DetailsFilesToggle
@onready var detailsFiles: VBoxContainer = %DetailsFiles
@onready var detailsAddedHeader: Label = %DetailsAddedHeader
@onready var detailsAdded: Label = %DetailsAdded
@onready var detailsModifiedHeader: Label = %DetailsModifiedHeader
@onready var detailsModified: Label = %DetailsModified

var config: AppConfig
var http: HttpFetcher
var inventory := ModInventory.new()
var github := GithubModInstaller.new()

var selectedModId := ""
var busy := false
var patched := false
var confirmResult := false
var confirmDone := false
var identified: Dictionary = {}
var checkingUpdates := false
var pendingUpdateError := ""


func _ready() -> void:
	pendingUpdateError = AppUpdater.ConsumeUpdateError()
	config = AppConfig.LoadConfig()
	http = HttpFetcher.new()
	add_child(http)
	http.download_progressed.connect(_OnDownloadProgress)
	infoMenu.set_item_text(0, "Version %s" % _ManagerVersion())
	get_window().title = "CG Mod Manager %s" % _ManagerVersion()
	_ApplyMenuAccelerators()
	_ApplyStartupUpdateItem()
	if PatchService.IsValidInstall(config) and PatchService.LooksPatched(config):
		if not config.setupComplete:
			config.setupComplete = true
			config.SaveSettings()
		_SetGameDir(config.gameDir)
	else:
		_UpdatePathLabel()
		_UpdateButtons()
		_StartWizard()
	detailsPreview.resized.connect(_FitDetailsPreview)
	_StartupUpdateCheck()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if not _MainShortcutsEnabled():
		return
	var handled := false
	if key.keycode == KEY_INSERT and _PlainKey(key):
		_OnAddPressed()
		handled = true
	elif key.keycode == KEY_O and key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
		_OpenModsFolder()
		handled = true
	elif key.keycode == KEY_DELETE and _PlainKey(key):
		_OnRemovePressed()
		handled = true
	elif key.keycode == KEY_UP and key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed:
		_OnMoveUpPressed()
		handled = true
	elif key.keycode == KEY_DOWN and key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed:
		_OnMoveDownPressed()
		handled = true
	elif key.keycode == KEY_F4 and key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed:
		get_tree().quit()
		handled = true
	elif key.keycode == KEY_F5 and _PlainKey(key):
		_LaunchGame()
		handled = true
	elif key.keycode == KEY_W and key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed:
		_StartWizard()
		handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _PlainKey(key: InputEventKey) -> bool:
	return not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed and not key.shift_pressed


func _MainShortcutsEnabled() -> bool:
	if not is_inside_tree():
		return false
	var win := get_window()
	if win == null or not win.has_focus():
		return false
	if wizard.visible or installMod.visible:
		return false
	if zipDialog.visible or browseDialog.visible or confirmDialog.visible:
		return false
	return true


func _ApplyMenuAccelerators() -> void:
	modsMenu.set_item_accelerator(0, KEY_INSERT)
	modsMenu.set_item_accelerator(2, KEY_DELETE)
	modsMenu.set_item_accelerator(3, KEY_UP | KEY_MASK_ALT)
	modsMenu.set_item_accelerator(4, KEY_DOWN | KEY_MASK_ALT)
	modsMenu.set_item_accelerator(6, KEY_O | KEY_MASK_CTRL)
	modsMenu.set_item_accelerator(8, KEY_F4 | KEY_MASK_ALT)
	gameMenu.set_item_accelerator(0, KEY_F5)
	settingsMenu.set_item_accelerator(0, KEY_W | KEY_MASK_ALT)


func _StartWizard() -> void:
	wizard.OpenWindow()


func _OnModsMenu(id: int) -> void:
	match id:
		0:
			_OnAddPressed()
		1:
			_OnRemovePressed()
		2:
			_OpenModsFolder()
		3:
			_OnMoveUpPressed()
		4:
			_OnMoveDownPressed()
		5:
			get_tree().quit()


func _OnSettingsMenu(id: int) -> void:
	if id == 0:
		_StartWizard()


func _OnGameMenu(id: int) -> void:
	if id == 0:
		_LaunchGame()


func _OnInfoMenu(id: int) -> void:
	match id:
		1:
			OS.shell_open(GITHUB_REPO_URL)
		2:
			OS.shell_open(GITHUB_REPO_URL + "/issues")
		3:
			_CheckManagerUpdate()
		4:
			config.checkUpdatesOnStartup = not config.checkUpdatesOnStartup
			_ApplyStartupUpdateItem()
			config.SaveSettings()


func _ManagerVersion() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _OpenModsFolder() -> void:
	if config.gameDir.is_empty():
		_SetStatus("Game folder not set.")
		return
	inventory.EnsureModsDir()
	var folder := inventory.ModsDir()
	if not DirAccess.dir_exists_absolute(folder):
		_SetStatus("Mods folder was not found.")
		return
	OS.shell_open(folder)


func _OnAddPressed() -> void:
	if busy:
		return
	installMod.OpenWindow()


func _OnInstallZip() -> void:
	installMod.CloseWindow()
	zipDialog.popup_centered_ratio(0.6)


func _OnInstallGithub(specText: String) -> void:
	var spec := GithubModInstaller.ParseSpec(specText)
	if spec.has("error"):
		_SetStatus(str(spec["error"]))
		return
	installMod.CloseWindow()
	_AddGithubAsync(specText)


func _SetGameDir(dirPath: String, refresh: bool = true) -> void:
	config.gameDir = dirPath
	config.SaveSettings()
	inventory.gameDir = dirPath
	inventory.Scan()
	_RebuildModList()
	_UpdatePathLabel()
	if refresh:
		_RefreshPatchStatus()
	_CheckModUpdates()


func _UpdatePathLabel() -> void:
	if config.gameDir.is_empty():
		pathLabel.text = "Game folder not set"
	else:
		pathLabel.text = config.gameDir


func _OnBrowsePressed() -> void:
	if not config.gameDir.is_empty():
		browseDialog.current_dir = config.gameDir
	browseDialog.popup_centered_ratio(0.7)


func _OnGameDirSelected(dirPath: String) -> void:
	if wizard.visible:
		_VerifyWizardPath(dirPath)
	elif PatchService.IsValidInstall(config, dirPath):
		_SetGameDir(dirPath)
	else:
		_SetStatus("That folder does not contain both %s and %s." % [config.gameExeName, config.pckName])


func _OnWizardDetect() -> void:
	if busy:
		return
	wizard.SetWorking(true)
	wizard.SetWorkingText("Searching Steam libraries...")
	await get_tree().process_frame
	var steam: Dictionary = SteamLocator.FindGame(
		config.gameExeName, config.pckName, config.steamAppId
	)
	if not steam.get("ok", false):
		wizard.SetWorking(false)
		wizard.SetGamePath("")
		wizard.SetLocationStatus(
			"No Chrono Gear installation was found in Steam libraries. Browse to the folder that contains ChronoGear.exe.",
			"",
			false
		)
		return
	wizard.SetGamePath(str(steam["path"]))
	await _VerifyWizardPath(str(steam["path"]))


func _VerifyWizardPath(dirPath: String) -> void:
	wizard.SetGamePath(dirPath)
	wizard.SetWorking(true)
	if not PatchService.IsValidInstall(config, dirPath):
		wizard.SetWorking(false)
		wizard.SetLocationStatus(
			"That folder does not contain both %s and %s." % [config.gameExeName, config.pckName],
			"",
			false
		)
		return
	identified = {}
	_SetGameDir(dirPath, false)
	wizard.SetWorkingText("Checking version...")
	_SetBusy(true)
	var _result: Dictionary = await _IdentifyInstall()
	_ApplyIdentifyToMain(_result)
	_SetBusy(false)
	wizard.SetWorking(false)
	var tag := str(_result.get("tag", ""))
	if _result.get("ok", false):
		wizard.SetLocationStatus(
			"Version %s detected." % tag,
			"This version is supported.",
			true
		)
		return
	if _result.get("unsupported", false) and not tag.is_empty():
		wizard.SetLocationStatus(
			"Version %s detected." % tag,
			"This version is not supported.",
			false
		)
		return
	if not tag.is_empty():
		wizard.SetLocationStatus(
			"Version %s detected." % tag,
			str(_result.get("error", "Could not check if this version is supported.")),
			false
		)
		return
	wizard.SetLocationStatus(str(_result.get("error", "Could not check this folder.")), "", false)


func _OnWizardPageChanged(page: int) -> void:
	if page != 2:
		return
	if not PatchService.IsValidInstall(config):
		wizard.SetLoaderStatus("Select a Chrono Gear folder first.", false)
		return
	if not identified.is_empty():
		if identified.get("ok", false):
			_SyncWizardLoader(identified)
		else:
			wizard.SetLoaderStatus(str(identified.get("error", "Could not identify game version.")), false)
		return
	wizard.SetWorking(true)
	wizard.SetWorkingText("Looking up the loader release...")
	_SetBusy(true)
	var _result: Dictionary = await _IdentifyInstall()
	_ApplyIdentifyToMain(_result)
	_SetBusy(false)
	wizard.SetWorking(false)
	if _result.get("ok", false):
		_SyncWizardLoader(_result)
	else:
		wizard.SetLoaderStatus(str(_result.get("error", "Could not identify game version.")), false)


func _SyncWizardLoader(identified: Dictionary) -> void:
	if identified.get("patched", false):
		wizard.SetLoaderStatus("The mod loader is installed.", true)
	else:
		wizard.SetLoaderStatus("The mod loader is not installed.", false)


func _RefreshPatchStatus() -> void:
	if not PatchService.IsValidInstall(config):
		patched = false
		identified = {}
		_SetStatus("Run Settings → Run wizard to locate Chrono Gear.")
		versionLabel.text = ""
		_UpdateButtons()
		_ShowPendingUpdateError()
		return
	_SetStatus("Checking game files...")
	_SetBusy(true)
	_RefreshPatchStatusAsync()


func _RefreshPatchStatusAsync() -> void:
	var _result: Dictionary = await _IdentifyInstall()
	_ApplyIdentifyToMain(_result)
	_SetBusy(false)


func _IdentifyInstall() -> Dictionary:
	var pck := PatchService.PckPath(config)
	if not FileAccess.file_exists(pck):
		return {"ok": false, "error": "ChronoGear.pck was not found."}
	var fileVersion := PatchService.ExeFileVersion(PatchService.ExePath(config))
	var tag := PatchService.ReleaseTag(fileVersion)
	if tag.is_empty() or tag == "unknown":
		return {"ok": false, "error": "Could not read the Chrono Gear version."}
	var remote: Dictionary = await http.RequestJson(
		PatchService.ReleaseApiUrl(config.patchesRepo, tag)
	)
	progress.value = 0
	if wizard != null:
		wizard.SetProgress(0)
	if not remote.get("ok", false):
		if int(remote.get("status", 0)) == 404:
			return {
				"ok": false,
				"unsupported": true,
				"error": "No mod loader release is published for game version %s." % tag,
				"tag": tag,
			}
		return {
			"ok": false,
			"error": str(remote.get("error", "Could not look up the loader release.")),
			"tag": tag,
		}
	var release: Dictionary = remote.get("data", {})
	if typeof(release) != TYPE_DICTIONARY:
		return {"ok": false, "error": "GitHub release response was not valid.", "tag": tag}
	var patch_url := PatchService.AssetUrlFromRelease(release, config.patchesRepo, tag)
	PatchService.RelabelPckBackup(config, tag)
	var backup := PatchService.ResolvePckBackup(config, tag)
	var has_backup := not backup.is_empty() and FileAccess.file_exists(backup)
	var _isPatched := has_backup and PatchService.FileLength(pck) != PatchService.FileLength(backup)
	if _isPatched:
		PatchService.EnsureExeBackup(config, tag)
	return {
		"ok": true,
		"tag": tag,
		"patch_url": patch_url,
		"patched": _isPatched,
		"vanilla": not _isPatched,
		"has_backup": has_backup,
	}


func _ApplyIdentifyToMain(_result: Dictionary) -> void:
	identified = _result
	if not identified.get("ok", false):
		patched = false
		_SetStatus(str(identified.get("error", "Could not identify game version.")))
		versionLabel.text = ""
		_ShowPendingUpdateError()
		return
	var tag := str(identified.get("tag", "?"))
	versionLabel.text = "Game %s" % tag
	if identified.get("patched", false):
		patched = true
		_SetStatus("Mod loader is installed.")
	else:
		patched = false
		_SetStatus("Vanilla game detected. Install the mod loader from the setup wizard.")
	_ShowPendingUpdateError()


func _OnWizardInstall() -> void:
	if busy:
		return
	wizard.SetWorking(true)
	var ok := await _InstallAsync()
	wizard.SetWorking(false)
	if ok:
		wizard.SetLoaderStatus("The mod loader is installed.", true)
	else:
		wizard.SetLoaderStatus(status.text, false)


func _OnWizardUninstall() -> void:
	if busy:
		return
	await _UninstallLoader()
	if wizard.visible:
		wizard.SetWorking(false)
		if patched:
			wizard.SetLoaderStatus("The mod loader is installed.", true)
		else:
			wizard.SetLoaderStatus("The mod loader is not installed.", false)


func _OnWizardFinished() -> void:
	config.setupComplete = true
	config.SaveSettings()
	wizard.CloseWindow()
	if PatchService.IsValidInstall(config):
		_RefreshPatchStatus()
	else:
		_UpdateButtons()


func _OnWizardDismissed() -> void:
	if busy:
		return
	wizard.CloseWindow()
	_ShowPendingUpdateError()


func _AnnounceInstallStep(text: String) -> void:
	status.text = text
	progress.value = 0
	progress.visible = true
	if wizard != null and wizard.visible:
		wizard.SetWorkingText(text)
		wizard.SetProgress(0)
		wizard.SetProgressVisible(true)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame


func _SetStepProgress(current: int, total: int) -> void:
	if total <= 0:
		return
	var value := clampf(float(current) / float(total), 0.0, 1.0)
	progress.value = value
	progress.visible = true
	if wizard != null and wizard.visible:
		wizard.SetProgress(value)
		wizard.SetProgressVisible(true)


func _CopyWithProgress(src: String, dest: String) -> Error:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	var input := FileAccess.open(src, FileAccess.READ)
	if input == null:
		return ERR_CANT_OPEN
	var output := FileAccess.open(dest, FileAccess.WRITE)
	if output == null:
		return ERR_CANT_CREATE
	var total := input.get_length()
	var copied := 0
	var chunk := 8 * 1024 * 1024
	while copied < total:
		var take: int = mini(chunk, total - copied)
		output.store_buffer(input.get_buffer(take))
		copied += take
		_SetStepProgress(copied, total)
		await get_tree().process_frame
	return OK


func _ApplyXdeltaWithProgress(sourcePck: String, patchFile: String, destPck: String) -> Dictionary:
	var started := PatchService.StartXdelta(sourcePck, patchFile, destPck)
	if not started.get("ok", false):
		return started
	var pid: int = started["pid"]
	var tmp: String = started["temp_path"]
	var expected := PatchService.FileLength(sourcePck)
	while OS.is_process_running(pid):
		var written := PatchService.FileLength(tmp)
		if written > 0:
			_SetStepProgress(written, expected)
		await get_tree().process_frame
	if not FileAccess.file_exists(tmp):
		return {"ok": false, "error": "xdelta3 failed. Vanilla files were left unchanged."}
	_SetStepProgress(expected, expected)
	return {"ok": true, "temp_path": tmp}


func _InstallAsync() -> bool:
	_SetBusy(true)
	_SetStatus("Looking up the loader release...")
	if not identified.get("ok", false):
		var _result: Dictionary = await _IdentifyInstall()
		_ApplyIdentifyToMain(_result)
	if not identified.get("ok", false):
		_SetStatus(str(identified.get("error", "Could not look up the loader release.")))
		_SetBusy(false)
		return false
	if identified.get("patched", false):
		patched = true
		_SetStatus("Mod loader is already installed.")
		_SetBusy(false)
		return true
	var tag := str(identified.get("tag", ""))
	var patch_url := str(identified.get("patch_url", ""))
	if patch_url.is_empty():
		patch_url = PatchService.PatchDownloadUrl(config.patchesRepo, tag)
	_SetStatus("Downloading patch...")
	var patch_path := OS.get_user_data_dir().path_join("patches").path_join(tag).path_join(
		PatchService.PATCH_ASSET
	)
	var downloaded: Dictionary = await http.DownloadFile(patch_url, patch_path)
	if not downloaded.get("ok", false):
		_SetStatus("Download failed: %s" % downloaded.get("error", "unknown error"))
		_SetBusy(false)
		return false
	var pck := PatchService.PckPath(config)
	var pck_backup := PatchService.PckBackupPath(config, tag)
	var legacy_pck := PatchService.LegacyPckBackupPath(config)
	if FileAccess.file_exists(legacy_pck) and not FileAccess.file_exists(pck_backup):
		DirAccess.rename_absolute(legacy_pck, pck_backup)
	var vanilla_source := pck
	if FileAccess.file_exists(pck_backup):
		vanilla_source = pck_backup
	else:
		await _AnnounceInstallStep("Backing up %s..." % pck_backup.get_file())
		var copied: Error = await _CopyWithProgress(pck, pck_backup)
		if copied != OK:
			_SetStatus("Could not create %s backup." % pck_backup.get_file())
			_SetBusy(false)
			return false
		vanilla_source = pck_backup
	var exe := PatchService.ExePath(config)
	var exe_backup := PatchService.ExeBackupPath(config, tag)
	if not FileAccess.file_exists(exe_backup):
		await _AnnounceInstallStep("Backing up %s..." % exe_backup.get_file())
		var exe_copied: Error = await _CopyWithProgress(exe, exe_backup)
		if exe_copied != OK:
			_SetStatus("Could not create %s backup." % exe_backup.get_file())
			_SetBusy(false)
			return false
	await _AnnounceInstallStep("Applying patch...")
	var applied: Dictionary = await _ApplyXdeltaWithProgress(vanilla_source, patch_path, pck)
	if not applied.get("ok", false):
		_SetStatus(str(applied.get("error", "Patch failed")))
		_SetBusy(false)
		return false
	var replaced := PatchService.ReplaceWithTemp(applied["temp_path"], pck)
	if not replaced.get("ok", false):
		_SetStatus(str(replaced.get("error", "Could not replace PCK")))
		_SetBusy(false)
		return false
	DirAccess.make_dir_recursive_absolute(inventory.ModsDir())
	patched = true
	identified["patched"] = true
	identified["vanilla"] = false
	identified["has_backup"] = true
	config.setupComplete = true
	config.SaveSettings()
	versionLabel.text = "Game %s" % tag
	_SetStatus("Mod loader installed.")
	inventory.Scan()
	_RebuildModList()
	_SetBusy(false)
	return true


func _UninstallLoader() -> void:
	var tag := PatchService.ReleaseTag(PatchService.ExeFileVersion(PatchService.ExePath(config)))
	var pck_backup := PatchService.ResolvePckBackup(config, tag)
	if pck_backup.is_empty() or not FileAccess.file_exists(pck_backup):
		_SetStatus("No versioned PCK backup was found.")
		return
	if not await _Ask("Restore the vanilla PCK and EXE from the versioned backups, then remove those backups? The mods folder will be left as-is."):
		return
	_SetBusy(true)
	var pck := PatchService.PckPath(config)
	var copied := PatchService.CopyFile(pck_backup, pck)
	if copied != OK:
		_SetStatus("Could not restore %s." % pck.get_file())
		_SetBusy(false)
		return
	var exe_backup := ""
	if not tag.is_empty():
		exe_backup = PatchService.ExeBackupPath(config, tag)
	if not exe_backup.is_empty() and FileAccess.file_exists(exe_backup):
		var exe_copied := PatchService.CopyFile(exe_backup, PatchService.ExePath(config))
		if exe_copied != OK:
			_SetStatus("Restored the PCK, but could not restore %s." % PatchService.ExePath(config).get_file())
			_SetBusy(false)
			return
		DirAccess.remove_absolute(exe_backup)
	DirAccess.remove_absolute(pck_backup)
	patched = false
	_SetStatus("Mod loader uninstalled. Vanilla files restored.")
	_SetBusy(false)


func _LaunchGame() -> void:
	var exe := config.gameDir.path_join(config.gameExeName)
	if not FileAccess.file_exists(exe):
		_SetStatus("ChronoGear.exe was not found. Run the setup wizard first.")
		return
	var pid := OS.create_process(exe, PackedStringArray())
	if pid < 0:
		_SetStatus("Could not launch Chrono Gear.")
		return
	_SetStatus("Launched Chrono Gear.")


func _OnZipSelected(path: String) -> void:
	_AddZipAsync(path)


func _AddZipAsync(path: String) -> void:
	_SetBusy(true)
	var inspected := ZipMod.Inspect(path)
	if not inspected.get("ok", false):
		_SetStatus(str(inspected.get("error", "Could not add zip")))
		_SetBusy(false)
		return
	var info: Dictionary = inspected["info"]
	var existing := inventory.EntryById(str(info.get("mod_id", "")))
	if not existing.is_empty() and inventory.MetadataMatches(existing, info):
		if GithubModInstaller.VersionIsNewer(str(info.get("version", "")), str(existing.get("version", ""))):
			if not _ModSupportsGame(info):
				_SetStatus(
					"Cannot update %s: it does not support game version %s." % [
						info["mod_id"],
						_CurrentGameTag(),
					]
				)
				_SetBusy(false)
				return
			_SetBusy(false)
			if not await _Ask(
				"Update %s from %s to %s?" % [
					info["mod_id"],
					existing.get("version", "?"),
					info.get("version", "?"),
				]
			):
				return
			_SetBusy(true)
			var updated := inventory.UpdateFromZip(path, existing.get("source", {"type": "local"}))
			if not updated.get("ok", false):
				_SetStatus(str(updated.get("error", "Could not update mod")))
				_SetBusy(false)
				return
			selectedModId = str(info["mod_id"])
			_RebuildModList()
			_SetStatus("Updated %s to %s." % [selectedModId, info.get("version", "")])
			_SetBusy(false)
			_CheckModUpdates()
			return
	var added := inventory.AddFromZip(path, {"type": "local"}, false)
	if added.get("exists", false):
		_SetBusy(false)
		if await _Ask("Replace the existing %s?" % added.get("info", {}).get("mod_id", "mod")):
			_SetBusy(true)
			added = inventory.AddFromZip(path, {"type": "local"}, true)
	if not added.get("ok", false):
		_SetStatus(str(added.get("error", "Could not add zip")))
		_SetBusy(false)
		return
	selectedModId = str(added["info"]["mod_id"])
	_RebuildModList()
	_SetStatus("Added %s." % selectedModId)
	_SetBusy(false)
	_CheckModUpdates()


func _AddGithubAsync(specText: String) -> void:
	var spec := GithubModInstaller.ParseSpec(specText)
	if spec.has("error"):
		_SetStatus(str(spec["error"]))
		return
	_SetBusy(true)
	var visiting := {}
	var installed_ids: Array = []
	var missing: Array = []
	var result := await _InstallGithubTree(spec, visiting, installed_ids, missing, true)
	if not result.get("ok", false):
		_SetStatus(str(result.get("error", "GitHub install failed")))
		_SetBusy(false)
		return
	var still_missing: PackedStringArray = PackedStringArray()
	for dep in missing:
		if not inventory.IsDependencyInstalled(str(dep)):
			still_missing.append(str(dep))
	var installed_names: PackedStringArray = PackedStringArray()
	for modId in installed_ids:
		installed_names.append(str(modId))
	if not installed_names.is_empty():
		selectedModId = installed_names[installed_names.size() - 1]
	_RebuildModList()
	var _statusText := "Installed and enabled %s." % ", ".join(installed_names)
	if not still_missing.is_empty():
		_statusText += " Missing dependencies: %s." % ", ".join(still_missing)
	_SetStatus(_statusText)
	_SetBusy(false)
	_CheckModUpdates()


func _InstallGithubTree(
	spec: Dictionary,
	visiting: Dictionary,
	installed_ids: Array,
	missing: Array,
	is_root: bool
) -> Dictionary:
	var owner: String = spec["owner"]
	var repo: String = spec["repo"]
	var key := "%s/%s" % [owner.to_lower(), repo.to_lower()]
	if visiting.has(key):
		return {"ok": true}
	visiting[key] = true
	if not is_root and inventory.FindByGithub(owner, repo) >= 0:
		return {"ok": true}
	_SetStatus("Fetching %s/%s from GitHub..." % [owner, repo])
	var tmp := OS.get_user_data_dir().path_join("tmp").path_join("github-%s-%s.zip" % [owner, repo])
	var installed: Dictionary = await github.Install(http, spec, tmp)
	if not installed.get("ok", false):
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		return installed
	var info: Dictionary = installed.get("info", {})
	for dep in inventory.RawDependencies(info):
		var dep_spec := GithubModInstaller.ParseSpec(dep)
		if dep_spec.has("error"):
			if not inventory.IsDependencyInstalled(dep) and not missing.has(dep):
				missing.append(dep)
			continue
		var dep_result := await _InstallGithubTree(dep_spec, visiting, installed_ids, missing, false)
		if not dep_result.get("ok", false):
			if FileAccess.file_exists(tmp):
				DirAccess.remove_absolute(tmp)
			return dep_result
	var added := inventory.AddFromZip(tmp, installed["source"], false)
	if added.get("exists", false):
		if not is_root:
			if FileAccess.file_exists(tmp):
				DirAccess.remove_absolute(tmp)
			return {"ok": true}
		if await _Ask("Replace the existing %s?" % added.get("info", {}).get("mod_id", "mod")):
			added = inventory.AddFromZip(tmp, installed["source"], true)
		else:
			if FileAccess.file_exists(tmp):
				DirAccess.remove_absolute(tmp)
			return {"ok": false, "error": "Install cancelled."}
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if not added.get("ok", false):
		return added
	installed_ids.append(str(added["info"]["mod_id"]))
	return {"ok": true}


func _OnRemovePressed() -> void:
	if busy or selectedModId.is_empty():
		_SetStatus("Select a mod to remove.")
		return
	var blockers := inventory.EnabledDependentsOf(selectedModId)
	if not blockers.is_empty():
		_SetStatus("Cannot remove %s while enabled mods depend on it: %s." % [selectedModId, ", ".join(blockers)])
		return
	if not await _Ask("Delete %s from the mods folder?" % selectedModId):
		return
	var removed := inventory.RemoveMod(selectedModId)
	if not removed.get("ok", false):
		_SetStatus(str(removed.get("error", "Could not remove mod")))
		return
	selectedModId = ""
	_RebuildModList()
	_SetStatus("Removed mod.")


func _OnMoveTopPressed() -> void:
	_MoveSelected(-inventory.entries.size())


func _OnMoveUpPressed() -> void:
	_MoveSelected(-1)


func _OnMoveDownPressed() -> void:
	_MoveSelected(1)


func _MoveSelected(delta: int) -> void:
	if selectedModId.is_empty():
		return
	var moved := inventory.MoveMod(selectedModId, delta)
	if not moved.get("ok", false):
		_SetStatus(str(moved.get("error", "Could not move mod")))
		return
	_RebuildModList()


func _RebuildModList() -> void:
	for child in modList.get_children():
		child.queue_free()
	for entry in inventory.entries:
		var row: Node = ModRowScene.instantiate()
		modList.add_child(row)
		row.Setup(entry)
		row.SetSelected(entry["mod_id"] == selectedModId)
		row.enabled_changed.connect(_OnModEnabled)
		row.row_selected.connect(_OnModSelected)
		row.dropped_on_row.connect(_OnModDrop)
	emptyLabel.visible = inventory.entries.is_empty()
	var warnings := inventory.OrderWarnings()
	warning.text = "\n".join(warnings)
	_UpdateButtons()


func _OnModEnabled(modId: String, enabled: bool) -> void:
	var saved := inventory.SetEnabled(modId, enabled)
	if not saved.get("ok", false):
		_SetStatus(str(saved.get("error", "Could not save")))
		_RebuildModList()
		return
	var changed: PackedStringArray = saved.get("changed", PackedStringArray())
	var names := ", ".join(changed) if not changed.is_empty() else modId
	if enabled:
		_SetStatus("Enabled %s." % names)
	else:
		_SetStatus("Disabled %s." % names)
	_RebuildModList()


func _OnModSelected(modId: String) -> void:
	selectedModId = modId
	_RebuildModList()


func _OnModDrop(fromId: String, ontoId: String) -> void:
	var moved := inventory.MoveModBefore(fromId, ontoId)
	if not moved.get("ok", false):
		_SetStatus(str(moved.get("error", "Could not move mod")))
		return
	selectedModId = fromId
	_RebuildModList()


func _Ask(text: String) -> bool:
	confirmDialog.dialog_text = text
	confirmResult = false
	confirmDone = false
	confirmDialog.popup_centered()
	while not confirmDone:
		await get_tree().process_frame
	return confirmResult


func _OnConfirmOk() -> void:
	confirmResult = true
	confirmDone = true


func _OnConfirmCancel() -> void:
	confirmResult = false
	confirmDone = true


func _OnHashProgress(read: int, total: int) -> void:
	if total <= 0:
		return
	var value := float(read) / float(total)
	progress.value = value
	if wizard != null and wizard.visible:
		wizard.SetProgress(value)


func _OnDownloadProgress(downloaded: int, total: int) -> void:
	if total <= 0:
		return
	var value := float(downloaded) / float(total)
	progress.value = value
	if wizard != null and wizard.visible:
		wizard.SetProgress(value)


func _SetStatus(text: String) -> void:
	status.text = text
	if wizard != null and wizard.visible and busy:
		wizard.SetWorkingText(text)


func _SetBusy(value: bool) -> void:
	busy = value
	_UpdateButtons()


func _SelectedIndex() -> int:
	for i in inventory.entries.size():
		if str(inventory.entries[i]["mod_id"]) == selectedModId:
			return i
	return -1


func _UpdateButtons() -> void:
	var has_game := PatchService.IsValidInstall(config)
	var index := _SelectedIndex()
	var last := inventory.entries.size() - 1
	addButton.disabled = busy or not has_game
	removeButton.disabled = busy or not has_game or index < 0 or not inventory.CanRemove(selectedModId)
	topButton.disabled = busy or index <= 0 or not inventory.CanMove(selectedModId, -index)
	upButton.disabled = busy or index <= 0 or not inventory.CanMove(selectedModId, -1)
	downButton.disabled = busy or index < 0 or index >= last or not inventory.CanMove(selectedModId, 1)
	progress.visible = busy and not wizard.visible
	if modsMenu.item_count >= 9:
		modsMenu.set_item_disabled(0, busy or not has_game)
		modsMenu.set_item_disabled(2, busy or not has_game or index < 0 or not inventory.CanRemove(selectedModId))
		modsMenu.set_item_disabled(3, busy or index <= 0 or not inventory.CanMove(selectedModId, -1))
		modsMenu.set_item_disabled(4, busy or index < 0 or index >= last or not inventory.CanMove(selectedModId, 1))
		modsMenu.set_item_disabled(6, not has_game)
	if gameMenu.item_count >= 1:
		gameMenu.set_item_disabled(0, busy or not FileAccess.file_exists(config.gameDir.path_join(config.gameExeName)))
	if settingsMenu.item_count >= 1:
		settingsMenu.set_item_disabled(0, busy)
	var updateIndex := infoMenu.get_item_index(3)
	if updateIndex >= 0:
		infoMenu.set_item_disabled(updateIndex, busy)
	_UpdateDetails()


func _UpdateDetails() -> void:
	var index := _SelectedIndex()
	if index < 0:
		detailsEmpty.visible = true
		detailsScroll.visible = false
		return
	var entry: Dictionary = inventory.entries[index]
	detailsEmpty.visible = false
	detailsScroll.visible = true
	detailsName.text = str(entry.get("name", entry.get("mod_id", "")))
	var version := str(entry.get("version", "")).strip_edges()
	var author := _AuthorLabel(entry)
	var id := str(entry.get("mod_id", ""))
	var _githubSource := _GithubSource(entry)
	var meta_parts: PackedStringArray = PackedStringArray()
	if not version.is_empty():
		meta_parts.append(_BbcodeEscape(version))
	if not author.is_empty():
		if _githubSource.is_empty():
			meta_parts.append(_BbcodeEscape(author))
		else:
			meta_parts.append("[url=https://github.com/%s]%s[/url]" % [_githubSource["owner"], _BbcodeEscape(author)])
	if not id.is_empty():
		meta_parts.append(_BbcodeEscape(id))
	detailsMeta.text = " · ".join(meta_parts)
	var source: Dictionary = entry.get("source", {})
	if str(source.get("type", "local")) == "github":
		detailsSource.text = "Source: github:%s/%s" % [source.get("owner", ""), source.get("repo", "")]
	else:
		detailsSource.text = "Source: local"
	if bool(entry.get("update_available", false)):
		var latest := str(entry.get("latest_version", "")).strip_edges()
		if latest.is_empty():
			detailsSource.text += "\nUpdate available"
		else:
			detailsSource.text += "\nUpdate available: %s" % latest
	if bool(entry.get("enabled", true)):
		detailsStatus.text = "Enabled"
		detailsStatus.modulate = Color(0.4, 0.85, 0.45)
	else:
		detailsStatus.text = "Disabled"
		detailsStatus.modulate = Color(0.95, 0.4, 0.4)
	var can_update := bool(entry.get("update_available", false)) and not _githubSource.is_empty()
	detailsUpdate.visible = can_update
	detailsUpdate.disabled = busy
	if can_update:
		var latest := str(entry.get("latest_version", "")).strip_edges()
		detailsUpdate.text = "Update to %s" % latest if not latest.is_empty() else "Update mod"
	var description := str(entry.get("description", "")).strip_edges()
	detailsDescription.text = description if not description.is_empty() else "No description."
	if _githubSource.is_empty():
		detailsSourceCode.visible = false
		detailsSourceCode.uri = ""
		detailsReport.visible = false
		detailsReport.uri = ""
	else:
		var repo_url := "https://github.com/%s/%s" % [_githubSource["owner"], _githubSource["repo"]]
		detailsSourceCode.visible = true
		detailsSourceCode.uri = repo_url
		detailsReport.visible = true
		detailsReport.uri = repo_url + "/issues"
	var deps := inventory.RawDependencies(entry)
	var dependents := inventory.DependentsOf(id)
	var dep_lines: PackedStringArray = PackedStringArray()
	if not deps.is_empty():
		dep_lines.append("Depends on: %s" % ", ".join(deps))
	if not dependents.is_empty():
		dep_lines.append("Required by: %s" % ", ".join(dependents))
	detailsDeps.visible = not dep_lines.is_empty()
	detailsDeps.text = "\n".join(dep_lines)
	var website := str(entry.get("website_url", "")).strip_edges()
	detailsWebsite.visible = not website.is_empty()
	detailsWebsite.text = website
	_UpdateDetailsFiles(entry)
	var preview: Variant = entry.get("preview", null)
	if preview is Texture2D:
		detailsPreview.texture = preview
		detailsPreview.visible = true
		_FitDetailsPreview()
	else:
		detailsPreview.texture = null
		detailsPreview.visible = false
		detailsPreview.custom_minimum_size = Vector2(0, 0)


func _FitDetailsPreview() -> void:
	var tex := detailsPreview.texture
	if tex == null or not detailsPreview.visible:
		return
	var max_h := 160.0
	var width := detailsPreview.size.x
	if width <= 1.0:
		width = detailsScroll.size.x
	var tex_w := float(tex.get_width())
	var tex_h := float(tex.get_height())
	if width <= 1.0 or tex_w <= 0.0 or tex_h <= 0.0:
		detailsPreview.custom_minimum_size = Vector2(0, max_h)
		return
	var height := minf(max_h, width * tex_h / tex_w)
	detailsPreview.custom_minimum_size = Vector2(0, height)


func _AuthorLabel(entry: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	var authors: Variant = entry.get("authors", [])
	if typeof(authors) == TYPE_PACKED_STRING_ARRAY:
		names = authors
	elif typeof(authors) == TYPE_ARRAY:
		for author in authors:
			var author_name := str(author).strip_edges()
			if not author_name.is_empty():
				names.append(author_name)
	if names.is_empty():
		var fallback := str(entry.get("namespace", "")).strip_edges()
		if fallback.is_empty():
			fallback = str(entry.get("mod_id", "")).get_slice("-", 0)
		return fallback
	return ", ".join(names)


func _GithubSource(entry: Dictionary) -> Dictionary:
	var source: Dictionary = entry.get("source", {})
	if str(source.get("type", "")) != "github":
		return {}
	var owner := str(source.get("owner", "")).strip_edges()
	var repo := str(source.get("repo", "")).strip_edges()
	if owner.is_empty() or repo.is_empty():
		return {}
	return {"owner": owner, "repo": repo}


func _BbcodeEscape(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")


func _OnDetailsMetaClicked(meta: Variant) -> void:
	var url := str(meta).strip_edges()
	if url.begins_with("https://"):
		OS.shell_open(url)


func _UpdateDetailsFiles(entry: Dictionary) -> void:
	var added := _StringList(entry.get("added_files", []))
	var modified := _StringList(entry.get("modified_files", []))
	var has_files := not added.is_empty() or not modified.is_empty()
	detailsFilesToggle.visible = has_files
	detailsAddedHeader.visible = not added.is_empty()
	detailsAdded.visible = not added.is_empty()
	detailsAdded.text = "\n".join(added)
	detailsModifiedHeader.visible = not modified.is_empty()
	detailsModified.visible = not modified.is_empty()
	detailsModified.text = "\n".join(modified)
	detailsFiles.visible = has_files and detailsFilesToggle.button_pressed
	detailsFilesToggle.text = "Files ▾" if detailsFilesToggle.button_pressed else "Files ▸"


func _OnDetailsFilesToggled(pressed: bool) -> void:
	detailsFiles.visible = pressed and detailsFilesToggle.visible
	detailsFilesToggle.text = "Files ▾" if pressed else "Files ▸"


func _StringList(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		return value
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				out.append(text)
	return out


func _CheckModUpdates() -> void:
	if checkingUpdates or inventory.entries.is_empty():
		return
	checkingUpdates = true
	for entry in inventory.entries:
		var spec := _GithubSpecFor(entry)
		if spec.is_empty():
			continue
		var latest: Dictionary = await github.LatestReleaseTag(http, spec["owner"], spec["repo"])
		if not latest.get("ok", false):
			if int(latest.get("status", 0)) == 403:
				break
			continue
		var tag := str(latest.get("tag", "")).strip_edges()
		if tag.is_empty():
			continue
		var newer := GithubModInstaller.VersionIsNewer(tag, str(entry.get("version", "")))
		entry["update_available"] = newer
		entry["latest_version"] = GithubModInstaller.StripVersionPrefix(tag)
	checkingUpdates = false
	_RebuildModList()


func _GithubSpecFor(entry: Dictionary) -> Dictionary:
	var source: Dictionary = entry.get("source", {})
	if str(source.get("type", "")) == "github":
		var owner := str(source.get("owner", "")).strip_edges()
		var repo := str(source.get("repo", "")).strip_edges()
		if not owner.is_empty() and not repo.is_empty():
			return {"owner": owner, "repo": repo}
	var site := str(entry.get("website_url", "")).strip_edges()
	if site.is_empty() or not site.to_lower().contains("github.com"):
		return {}
	var parsed := GithubModInstaller.ParseSpec(site)
	if parsed.has("error"):
		return {}
	return parsed


func _OnDetailsUpdatePressed() -> void:
	if busy:
		return
	var index := _SelectedIndex()
	if index < 0:
		return
	_UpdateGithubModAsync(inventory.entries[index])


func _UpdateGithubModAsync(entry: Dictionary) -> void:
	var spec := _GithubSource(entry)
	if spec.is_empty():
		_SetStatus("This mod has no GitHub source.")
		return
	_SetBusy(true)
	_SetStatus("Updating %s..." % entry.get("mod_id", "mod"))
	var tmp := OS.get_user_data_dir().path_join("tmp").path_join(
		"github-update-%s-%s.zip" % [spec["owner"], spec["repo"]]
	)
	var installed: Dictionary = await github.Install(http, spec, tmp)
	if not installed.get("ok", false):
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		_SetStatus(str(installed.get("error", "Update failed")))
		_SetBusy(false)
		return
	var info: Dictionary = installed.get("info", {})
	if not _ModSupportsGame(info):
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		_SetStatus(
			"Cannot update %s: it does not support game version %s." % [
				entry.get("mod_id", "mod"),
				_CurrentGameTag(),
			]
		)
		_SetBusy(false)
		return
	if not GithubModInstaller.VersionIsNewer(str(info.get("version", "")), str(entry.get("version", ""))):
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		_SetStatus("%s is already up to date." % entry.get("mod_id", "mod"))
		_SetBusy(false)
		return
	var source: Dictionary = installed.get("source", {})
	if typeof(entry.get("source", {})) == TYPE_DICTIONARY and source.is_empty():
		source = entry["source"]
	var updated := inventory.UpdateFromZip(tmp, source)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if not updated.get("ok", false):
		_SetStatus(str(updated.get("error", "Could not update mod")))
		_SetBusy(false)
		return
	selectedModId = str(info.get("mod_id", entry.get("mod_id", "")))
	_RebuildModList()
	_SetStatus("Updated %s to %s." % [selectedModId, info.get("version", "")])
	_SetBusy(false)
	_CheckModUpdates()


func _CurrentGameTag() -> String:
	if not PatchService.IsValidInstall(config):
		return ""
	return PatchService.ReleaseTag(PatchService.ExeFileVersion(PatchService.ExePath(config)))


func _ModSupportsGame(info: Dictionary) -> bool:
	return ZipMod.SupportsGameVersion(info, _CurrentGameTag())


func _ApplyStartupUpdateItem() -> void:
	var index := infoMenu.get_item_index(4)
	if index < 0:
		return
	infoMenu.set_item_as_checkable(index, true)
	infoMenu.set_item_checked(index, config.checkUpdatesOnStartup)


func _StartupUpdateCheck() -> void:
	if not config.checkUpdatesOnStartup:
		return
	while is_inside_tree() and (wizard.visible or busy):
		await get_tree().process_frame
	if not is_inside_tree() or wizard.visible or busy or not config.checkUpdatesOnStartup:
		return
	await _CheckManagerUpdate(true)


func _CheckManagerUpdate(quiet := false) -> void:
	if busy:
		return
	var spec := GithubModInstaller.ParseSpec(GITHUB_REPO_URL)
	if spec.has("error"):
		if not quiet:
			_SetStatus(str(spec["error"]))
		return
	_SetBusy(true)
	if not quiet:
		_SetStatus("Checking for mod manager updates...")
	var latest: Dictionary = await github.LatestReleaseZip(http, spec["owner"], spec["repo"])
	_SetBusy(false)
	if not latest.get("ok", false):
		if not quiet:
			_SetStatus(str(latest.get("error", "Could not check for updates")))
		return
	var tag := str(latest.get("tag", "")).strip_edges()
	var current := _ManagerVersion()
	if tag.is_empty():
		if not quiet:
			_SetStatus("No mod manager releases were found.")
		return
	if not GithubModInstaller.VersionIsNewer(tag, current):
		if not quiet:
			_SetStatus("CG Mod Manager is up to date (%s)." % current)
		return
	var newest := GithubModInstaller.StripVersionPrefix(tag)
	var zip_url := str(latest.get("url", "")).strip_edges()
	if zip_url.is_empty():
		if not quiet:
			_SetStatus("Update %s has no zip to download." % newest)
		return
	if OS.has_feature("editor"):
		_SetStatus("Update available: %s (you have %s). Install it from the exported program." % [newest, current])
		return
	_SetStatus("Update available: %s (you have %s)." % [newest, current])
	if not await _Ask("Download and install CG Mod Manager %s? The app will close and reopen." % newest):
		return
	_SetBusy(true)
	progress.value = 0
	_SetStatus("Downloading CG Mod Manager %s..." % newest)
	var installed: Dictionary = await AppUpdater.DownloadAndRelaunch(http, zip_url)
	if not installed.get("ok", false):
		_SetStatus(str(installed.get("error", "Could not install the update")))
		_SetBusy(false)
		return
	_SetStatus("Restarting...")
	await get_tree().process_frame
	get_tree().quit()


func _ShowPendingUpdateError() -> void:
	if pendingUpdateError.is_empty():
		return
	_SetStatus("Update failed: %s" % pendingUpdateError)
	pendingUpdateError = ""
