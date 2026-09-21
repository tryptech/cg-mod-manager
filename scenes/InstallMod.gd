class_name InstallModDialog
extends Window

signal github_install_requested(spec: String)
signal zip_install_requested

@onready var githubEdit: LineEdit = %GithubEdit


func OpenWindow() -> void:
	githubEdit.text = ""
	popup_centered()
	githubEdit.grab_focus()


func CloseWindow() -> void:
	hide()


func _OnCloseRequested() -> void:
	hide()


func _OnInstallPressed() -> void:
	github_install_requested.emit(githubEdit.text.strip_edges())


func _OnZipPressed() -> void:
	zip_install_requested.emit()


func _OnGithubEditTextSubmitted(_text: String) -> void:
	_OnInstallPressed()
