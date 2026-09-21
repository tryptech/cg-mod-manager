class_name SetupWizard
extends Window

signal detect_pressed
signal browse_pressed
signal install_loader_pressed
signal uninstall_loader_pressed
signal page_changed(page: int)
signal finished
signal dismissed

@onready var pages: TabContainer = %Pages
@onready var backButton: Button = %BackButton
@onready var nextButton: Button = %NextButton
@onready var pathEdit: LineEdit = %GamePathEdit
@onready var locationStatus: Label = %LocationStatus
@onready var locationSupport: Label = %LocationSupport
@onready var locationProgress: ProgressBar = %LocationProgress
@onready var detectButton: Button = %DetectButton
@onready var browseButton: Button = %BrowseButton
@onready var loaderStatus: Label = %LoaderStatus
@onready var loaderProgress: ProgressBar = %LoaderProgress
@onready var installButton: Button = %InstallLoaderButton

var page := 0
var locationReady := false
var working := false
var loaderInstalled := false


func OpenWindow() -> void:
	working = false
	locationReady = false
	pathEdit.text = ""
	locationStatus.text = ""
	locationSupport.text = ""
	locationSupport.modulate = Color.WHITE
	loaderStatus.text = "The mod loader is not installed."
	loaderStatus.modulate = Color.WHITE
	loaderInstalled = false
	installButton.text = "Install"
	installButton.visible = true
	locationProgress.visible = false
	loaderProgress.visible = false
	_ShowPage(0)
	popup_centered()


func CloseWindow() -> void:
	hide()


func SetGamePath(path: String) -> void:
	pathEdit.text = path


func SetLocationStatus(version_text: String, support_text: String, ready: bool) -> void:
	locationStatus.text = version_text
	locationSupport.text = support_text
	if support_text.is_empty():
		locationSupport.modulate = Color.WHITE
	elif ready:
		locationSupport.modulate = Color(0.4, 0.85, 0.45)
	else:
		locationSupport.modulate = Color(0.95, 0.4, 0.4)
	locationReady = ready
	locationProgress.visible = false
	_UpdateNav()


func SetLoaderStatus(text: String, installed: bool) -> void:
	loaderInstalled = installed
	loaderStatus.text = text
	if installed:
		loaderStatus.modulate = Color(0.4, 0.85, 0.45)
		installButton.text = "Uninstall"
	else:
		loaderStatus.modulate = Color(0.95, 0.4, 0.4)
		installButton.text = "Install"
	installButton.visible = true
	loaderProgress.visible = false


func SetProgress(value: float) -> void:
	locationProgress.value = value
	loaderProgress.value = value


func SetProgressVisible(show: bool) -> void:
	if page == 1:
		locationProgress.visible = show
	elif page == 2:
		loaderProgress.visible = show


func SetWorking(value: bool) -> void:
	working = value
	detectButton.disabled = value
	browseButton.disabled = value
	installButton.disabled = value
	if page == 1:
		locationProgress.visible = value
	elif page == 2:
		loaderProgress.visible = value
	_UpdateNav()


func SetWorkingText(text: String) -> void:
	if page == 1:
		locationStatus.text = text
		locationSupport.text = ""
		locationSupport.modulate = Color.WHITE
	elif page == 2:
		loaderStatus.text = text
		loaderStatus.modulate = Color.WHITE


func _OnCloseRequested() -> void:
	if working:
		return
	dismissed.emit()


func _OnBackPressed() -> void:
	if page > 0:
		_ShowPage(page - 1)


func _OnNextPressed() -> void:
	if page >= 3:
		finished.emit()
		return
	_ShowPage(page + 1)


func _OnDetectPressed() -> void:
	detect_pressed.emit()


func _OnBrowsePressed() -> void:
	browse_pressed.emit()


func _OnInstallLoaderPressed() -> void:
	if loaderInstalled:
		uninstall_loader_pressed.emit()
	else:
		install_loader_pressed.emit()


func _ShowPage(index: int) -> void:
	page = index
	pages.current_tab = index
	title = "CG Setup"
	_UpdateNav()
	page_changed.emit(index)


func _UpdateNav() -> void:
	backButton.visible = page > 0
	backButton.disabled = working
	nextButton.disabled = working or (page == 1 and not locationReady)
	if page >= 3:
		nextButton.text = "Finish"
	else:
		nextButton.text = "Next"
