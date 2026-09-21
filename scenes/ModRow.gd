extends PanelContainer

signal dropped_on_row(fromId: String, ontoId: String)
signal enabled_changed(modId: String, enabled: bool)
signal row_selected(modId: String)

var modId := ""

@onready var enabledBox: CheckBox = %Enabled
@onready var titleLabel: Label = %Title
@onready var metaLabel: Label = %Meta
@onready var iconRect: TextureRect = %Icon
@onready var iconPlaceholder: ColorRect = %Placeholder


func Setup(entry: Dictionary) -> void:
	modId = entry["mod_id"]
	enabledBox.set_pressed_no_signal(entry["enabled"])
	titleLabel.text = "%s  %s" % [entry["name"], entry["version"]]
	var source: Dictionary = entry.get("source", {})
	var source_label := "local"
	if str(source.get("type", "local")) == "github":
		source_label = "github:%s/%s" % [source.get("owner", ""), source.get("repo", "")]
	metaLabel.text = "%s  ·  %s" % [_AuthorLabel(entry), source_label]
	if bool(entry.get("update_available", false)):
		var latest := str(entry.get("latest_version", "")).strip_edges()
		if latest.is_empty():
			metaLabel.text += "  ·  update available"
		else:
			metaLabel.text += "  ·  update %s" % latest
	var icon: Variant = entry.get("icon", null)
	if icon is Texture2D:
		iconRect.texture = icon
		iconPlaceholder.visible = false
	else:
		iconRect.texture = null
		iconPlaceholder.visible = true


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


func SetSelected(selected: bool) -> void:
	var box := StyleBoxFlat.new()
	box.content_margin_left = 10
	box.content_margin_top = 6
	box.content_margin_right = 8
	box.content_margin_bottom = 6
	box.border_width_left = 4
	if selected:
		box.bg_color = Color(0.16, 0.42, 0.82, 1)
		box.border_color = Color(0.75, 0.9, 1, 1)
		titleLabel.modulate = Color.WHITE
		metaLabel.modulate = Color(0.85, 0.92, 1, 1)
	else:
		box.bg_color = Color(1, 1, 1, 0.04)
		box.border_color = Color(0, 0, 0, 0)
		titleLabel.modulate = Color.WHITE
		metaLabel.modulate = Color(0.7, 0.7, 0.7, 1)
	add_theme_stylebox_override("panel", box)


func _ready() -> void:
	enabledBox.toggled.connect(func(pressed: bool) -> void: enabled_changed.emit(modId, pressed))
	gui_input.connect(_OnGuiInput)
	SetSelected(false)


func _OnGuiInput(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		row_selected.emit(modId)


func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = modId
	set_drag_preview(preview)
	row_selected.emit(modId)
	return {"mod_id": modId}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("mod_id") and str(data["mod_id"]) != modId


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped_on_row.emit(str(data["mod_id"]), modId)
