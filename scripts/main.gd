extends Node

const GameWorldScript = preload("res://scripts/game_world.gd")
const ControlSettingsScript = preload("res://scripts/control_settings.gd")
const READY_STATUS := "READY • MATCHES UP TO 3v3"

var menu_layer: CanvasLayer
var status_label: Label
var address_input: LineEdit
var port_input: SpinBox
var game_world
var training_button: Button
var main_controls_button: Button
var controls_overlay: Control
var controls_back_button: Button
var controls_customize_button: Button
var control_settings_menu
var nickname_input: LineEdit

func _ready() -> void:
	if (
		OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
	):
		_start_dedicated_server()
		return

	# Your existing menu setup continues here.
	_ensure_input_actions()
	ControlSettingsScript.initialize()
	_build_menu()
	NetworkManager.connection_failed.connect(_on_network_error)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _start_dedicated_server() -> void:
	var error := NetworkManager.start_dedicated_server(7000)

	if error != OK:
		push_error("Could not start dedicated server: %d" % error)
		get_tree().quit(1)
		return

	game_world = GameWorldScript.new()
	game_world.name = "GameWorld"
	add_child(game_world)

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 20
	add_child(menu_layer)

	var background := ColorRect.new()
	background.color = Color("06111f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(background)

	# Soft club-color lighting and pitch markings keep the menu attractive
	# without requiring an external background image.
	var glow_a := ColorRect.new()
	glow_a.color = Color(0.02, 0.48, 0.31, 0.22)
	glow_a.position = Vector2(-110, -100)
	glow_a.size = Vector2(610, 290)
	glow_a.rotation = -0.10
	glow_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(glow_a)

	var glow_b := ColorRect.new()
	glow_b.color = Color(0.07, 0.31, 0.72, 0.22)
	glow_b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	glow_b.position = Vector2(-500, -210)
	glow_b.size = Vector2(620, 300)
	glow_b.rotation = -0.12
	glow_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(glow_b)
	_add_menu_pitch_details(background)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_bottom", 34)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(margin)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 64)
	margin.add_child(layout)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.alignment = BoxContainer.ALIGNMENT_CENTER
	title_column.add_theme_constant_override("separation", 14)
	layout.add_child(title_column)

	var eyebrow := Label.new()
	eyebrow.text = "FAST  •  PHYSICS-BASED  •  ONLINE"
	eyebrow.add_theme_color_override("font_color", Color("5ee6af"))
	eyebrow.add_theme_font_size_override("font_size", 15)
	title_column.add_child(eyebrow)

	var title := Label.new()
	title.text = "TOUCHFORGE"
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 68)
	title_column.add_child(title)

	var accent_line := ColorRect.new()
	accent_line.color = Color("1fd48f")
	accent_line.custom_minimum_size = Vector2(150, 4)
	accent_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_column.add_child(accent_line)


	var subtitle := Label.new()
	subtitle.text = (
		"Host or join competitive online matches.\n"
		+ "Build a team, read the bounce, and create goals."
	)
	subtitle.add_theme_color_override("font_color", Color("a8b7ca"))
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_constant_override("line_spacing", 5)
	title_column.add_child(subtitle)

	var mode_badge := PanelContainer.new()
	mode_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var badge_style := _panel_style(
		Color(0.06, 0.28, 0.23, 0.92),
		18,
		Color("2dcc91")
	)
	badge_style.content_margin_left = 16
	badge_style.content_margin_right = 16
	badge_style.content_margin_top = 7
	badge_style.content_margin_bottom = 7
	mode_badge.add_theme_stylebox_override("panel", badge_style)
	title_column.add_child(mode_badge)

	var mode_label := Label.new()
	mode_label.text = "1v1  •  2v2  •  3v3"
	mode_label.add_theme_color_override("font_color", Color("8ff0c8"))
	mode_label.add_theme_font_size_override("font_size", 15)
	mode_badge.add_child(mode_label)

	var feature_label := Label.new()
	feature_label.text = "DIRECT-IP MULTIPLAYER  •  CONTROLLER READY"
	feature_label.add_theme_color_override("font_color", Color("6f849c"))
	feature_label.add_theme_font_size_override("font_size", 12)
	title_column.add_child(feature_label)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)
	var card_style := _panel_style(
		Color(0.045, 0.105, 0.17, 0.98),
		20,
		Color("27445f")
	)
	card_style.shadow_color = Color(0, 0, 0, 0.42)
	card_style.shadow_size = 18
	card_style.shadow_offset = Vector2(0, 8)
	card.add_theme_stylebox_override("panel", card_style)
	layout.add_child(card)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 30)
	card_margin.add_theme_constant_override("margin_top", 26)
	card_margin.add_theme_constant_override("margin_right", 30)
	card_margin.add_theme_constant_override("margin_bottom", 26)
	card.add_child(card_margin)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	card_margin.add_child(controls)

	var play_label := Label.new()
	play_label.text = "PLAY ONLINE"
	play_label.add_theme_font_size_override("font_size", 26)
	play_label.add_theme_color_override("font_color", Color.WHITE)
	controls.add_child(play_label)

	var play_subtitle := Label.new()
	play_subtitle.text = "Choose a name, then host or join a match."
	play_subtitle.add_theme_font_size_override("font_size", 13)
	play_subtitle.add_theme_color_override("font_color", Color("7f95ad"))
	controls.add_child(play_subtitle)

	var nickname_label := Label.new()
	nickname_label.text = "NICKNAME"
	nickname_label.add_theme_color_override("font_color", Color("a8b7ca"))
	nickname_label.add_theme_font_size_override("font_size", 13)
	controls.add_child(nickname_label)

	nickname_input = LineEdit.new()
	nickname_input.placeholder_text = "Enter your nickname"
	nickname_input.text = "Player"
	nickname_input.max_length = 18
	nickname_input.custom_minimum_size.y = 44
	_style_text_input(nickname_input)
	controls.add_child(nickname_input)

	training_button = _menu_button("PRACTICE ARENA", Color("1fbf83"))
	training_button.tooltip_text = "Offline pitch: practice movement, shots, and ball control."
	training_button.pressed.connect(_start_training)
	controls.add_child(training_button)

	var host_button := _menu_button("HOST ONLINE MATCH", Color("2677d9"))
	host_button.tooltip_text = "Open a direct-IP match for up to six players."
	host_button.pressed.connect(_host_match)
	controls.add_child(host_button)

	main_controls_button = _menu_button("CONTROLS", Color("3a759f"))
	main_controls_button.tooltip_text = "View or customize this PC's controls."
	main_controls_button.pressed.connect(_show_controls)
	controls.add_child(main_controls_button)

	var separator := HSeparator.new()
	separator.modulate = Color(1, 1, 1, 0.14)
	controls.add_child(separator)

	var join_label := Label.new()
	join_label.text = "JOIN ONLINE MATCH"
	join_label.add_theme_color_override("font_color", Color("a8b7ca"))
	join_label.add_theme_font_size_override("font_size", 13)
	controls.add_child(join_label)

	address_input = LineEdit.new()
	address_input.placeholder_text = "Host IP address"
	address_input.text = "127.0.0.1"
	address_input.custom_minimum_size.y = 44
	address_input.tooltip_text = "Enter the host's local, public, or Tailscale IP address."
	_style_text_input(address_input)
	controls.add_child(address_input)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 10)
	controls.add_child(port_row)

	port_input = SpinBox.new()
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = NetworkManager.DEFAULT_PORT
	port_input.custom_minimum_size = Vector2(135, 44)
	port_input.tooltip_text = "The host and joiner must use the same UDP port."
	_style_text_input(port_input.get_line_edit())
	port_row.add_child(port_input)

	var join_button := _menu_button("JOIN MATCH", Color("8a4fe0"))
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(_join_match)
	port_row.add_child(join_button)

	var status_panel := PanelContainer.new()
	var status_style := _panel_style(
		Color(0.025, 0.07, 0.115, 0.88),
		10,
		Color("1d3851")
	)
	status_style.content_margin_left = 12
	status_style.content_margin_right = 12
	status_style.content_margin_top = 8
	status_style.content_margin_bottom = 8
	status_panel.add_theme_stylebox_override("panel", status_style)
	controls.add_child(status_panel)

	status_label = Label.new()
	status_label.text = READY_STATUS
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("78a9c9"))
	status_panel.add_child(status_label)
	var quit_button: Button = _menu_button(
		"QUIT GAME",
		Color("b74455")
	)
	quit_button.tooltip_text = "Close TOUCHFORGE."
	quit_button.pressed.connect(_quit_game)
	controls.add_child(quit_button)
	controls_overlay = _build_controls_overlay()
	control_settings_menu = ControlSettingsScript.new()
	control_settings_menu.name = "ControlSettingsMenu"
	control_settings_menu.visible = false
	control_settings_menu.closed.connect(_on_control_settings_closed)
	menu_layer.add_child(control_settings_menu)

func _quit_game() -> void:
	get_tree().quit()

func _add_menu_pitch_details(background: Control) -> void:
	var marking_color := Color(0.42, 0.88, 0.70, 0.085)

	var halfway_line := ColorRect.new()
	halfway_line.color = marking_color
	halfway_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(halfway_line)
	halfway_line.anchor_left = 0.42
	halfway_line.anchor_right = 0.42
	halfway_line.anchor_top = 0.0
	halfway_line.anchor_bottom = 1.0
	halfway_line.offset_left = -1
	halfway_line.offset_right = 1

	var center_circle := Panel.new()
	center_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_circle.add_theme_stylebox_override(
		"panel",
		_panel_style(Color.TRANSPARENT, 125, marking_color)
	)
	background.add_child(center_circle)
	center_circle.anchor_left = 0.42
	center_circle.anchor_right = 0.42
	center_circle.anchor_top = 0.5
	center_circle.anchor_bottom = 0.5
	center_circle.offset_left = -125
	center_circle.offset_right = 125
	center_circle.offset_top = -125
	center_circle.offset_bottom = 125

	var center_dot := Panel.new()
	center_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_dot.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.42, 0.88, 0.70, 0.16), 7)
	)
	background.add_child(center_dot)
	center_dot.anchor_left = 0.42
	center_dot.anchor_right = 0.42
	center_dot.anchor_top = 0.5
	center_dot.anchor_bottom = 0.5
	center_dot.offset_left = -7
	center_dot.offset_right = 7
	center_dot.offset_top = -7
	center_dot.offset_bottom = 7


func _style_text_input(input: LineEdit) -> void:
	input.add_theme_font_size_override("font_size", 15)
	input.add_theme_color_override("font_color", Color("e8f1fa"))
	input.add_theme_color_override("font_placeholder_color", Color("637991"))
	input.add_theme_color_override("caret_color", Color("5ee6af"))
	input.add_theme_color_override(
		"selection_color",
		Color(0.12, 0.45, 0.72, 0.55)
	)

	var normal_style := _panel_style(
		Color("09192a"),
		9,
		Color("29435d")
	)
	var focus_style := _panel_style(
		Color("0b1f33"),
		9,
		Color("51d9a4")
	)

	normal_style.content_margin_left = 13
	normal_style.content_margin_right = 13
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	focus_style.content_margin_left = 13
	focus_style.content_margin_right = 13
	focus_style.content_margin_top = 8
	focus_style.content_margin_bottom = 8

	input.add_theme_stylebox_override("normal", normal_style)
	input.add_theme_stylebox_override("focus", focus_style)
	input.add_theme_stylebox_override("read_only", normal_style)


func _build_controls_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.005, 0.012, 0.022, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	menu_layer.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(860, 570)
	card.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("102238"), 18, Color("355878"))
	)
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "View the default guide or customize this PC's controls."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("91a5bd"))
	column.add_child(subtitle)

	var input_columns := HBoxContainer.new()
	input_columns.add_theme_constant_override("separation", 18)
	input_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(input_columns)

	input_columns.add_child(
		_controls_panel(
			"KEYBOARD & MOUSE",
			"WASD   Move\n"
			+ "MOUSE   Camera / aim\n"
			+ "HOLD LMB   Kick, pass, or shoot\n"
			+ "SWIPE MOUSE   Curve while charging\n"
			+ "SHAKE MOUSE   Knuckleball\n"
			+ "RMB   Juggle\n"
			+ "CTRL   Cushion / control the ball\n"
			+ "SHIFT   Sprint\n"
			+ "SPACE   Jump\n"
			+ "F + A/D   Tackle or goalkeeper dive\n"
			+ "ESC   Match menu",
			Color("5ee6af")
		)
	)

	input_columns.add_child(
		_controls_panel(
			"CONTROLLER",
			"LEFT STICK   Move\n"
			+ "RIGHT STICK   Camera / aim\n"
			+ "HOLD RT / R2 or X / SQUARE   Kick\n"
			+ "MOVE RIGHT STICK   Curve while charging\n"
			+ "SHAKE RIGHT STICK   Knuckleball\n"
			+ "RB / R1   Juggle\n"
			+ "LB / L1   Cushion / control the ball\n"
			+ "L3   Sprint\n"
			+ "A / CROSS   Jump\n"
			+ "B / CIRCLE + LEFT STICK   Tackle or dive\n"
			+ "MENU / OPTIONS   Match menu",
			Color("6eb6ff")
		)
	)

	var controls_action_row := HBoxContainer.new()
	controls_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	controls_action_row.add_theme_constant_override("separation", 12)
	column.add_child(controls_action_row)

	controls_customize_button = _menu_button(
		"CUSTOMIZE CONTROLS",
		Color("1fbf83")
	)
	controls_customize_button.custom_minimum_size.x = 300
	controls_customize_button.pressed.connect(_show_control_settings)
	controls_action_row.add_child(controls_customize_button)

	controls_back_button = _menu_button("BACK", Color("2677d9"))
	controls_back_button.custom_minimum_size.x = 220
	controls_back_button.pressed.connect(_hide_controls)
	controls_action_row.add_child(controls_back_button)

	return overlay


func _controls_panel(
	title_text: String,
	body_text: String,
	accent: Color
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("0b1b2d"), 12, accent.darkened(0.35))
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", accent)
	column.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color("d7e2ee"))
	body.add_theme_constant_override("line_spacing", 7)
	column.add_child(body)

	return panel


func _show_controls() -> void:
	controls_overlay.visible = true
	controls_customize_button.call_deferred("grab_focus")


func _hide_controls() -> void:
	controls_overlay.visible = false
	main_controls_button.call_deferred("grab_focus")


func _show_control_settings() -> void:
	controls_overlay.visible = false
	control_settings_menu.open_menu()


func _on_control_settings_closed() -> void:
	if menu_layer == null or not menu_layer.visible:
		return

	controls_overlay.visible = true
	controls_customize_button.call_deferred("grab_focus")


func _focus_main_menu() -> void:
	if (
		menu_layer != null
		and menu_layer.visible
		and controls_overlay != null
		and not controls_overlay.visible
		and training_button != null
	):
		training_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if menu_layer == null or not menu_layer.visible:
		return
	if (
		control_settings_menu != null
		and control_settings_menu.is_open()
	):
		return

	if (
		controls_overlay != null
		and controls_overlay.visible
		and (
			event.is_action_pressed("ui_cancel")
			or event.is_action_pressed("pause")
		)
	):
		_hide_controls()
		get_viewport().set_input_as_handled()


func _menu_button(text_value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 50
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 16)

	var normal_style := _panel_style(
		accent.darkened(0.28),
		10,
		accent
	)
	normal_style.shadow_color = Color(0, 0, 0, 0.24)
	normal_style.shadow_size = 4
	normal_style.shadow_offset = Vector2(0, 2)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(
			accent.darkened(0.10),
			10,
			accent.lightened(0.12)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(accent.darkened(0.40), 10, accent)
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(accent.darkened(0.04), 10, Color.WHITE)
	)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	return button


func _panel_style(color: Color, radius: int, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	return style


func _start_training() -> void:
	NetworkManager.start_offline()
	_start_world()


func _host_match() -> void:
	var port := int(port_input.value)
	var error := NetworkManager.host_game(port)

	if error != OK:
		return

	var address := NetworkManager.public_host_address

	if address.is_empty():
		OS.alert(
			"UPnP failed.\nYou must manually forward UDP port %d." % port,
			"Hosting Error"
		)
	else:
		DisplayServer.clipboard_set(address)

		OS.alert(
			"Share this address with the other players:\n\n%s:%d\n\nThe IP was copied." %
			[address, port],
			"Match Hosted"
		)

	_start_world()


func _join_match() -> void:
	var address := address_input.text.strip_edges()
	var port := int(port_input.value)
	var error := NetworkManager.join_game(address, port)
	if error == OK:
		_start_world()


func _start_world() -> void:
	if game_world != null and is_instance_valid(game_world):
		if game_world.get_parent() == self:
			remove_child(game_world)
		game_world.queue_free()
	var chosen_nickname: String = nickname_input.text.strip_edges()

	if chosen_nickname.is_empty():
		chosen_nickname = "Player"

	chosen_nickname = chosen_nickname.left(18)
	nickname_input.text = chosen_nickname

	game_world = GameWorldScript.new()
	game_world.local_nickname = chosen_nickname
	game_world.name = "GameWorld"
	game_world.leave_requested.connect(_return_to_menu)
	add_child(game_world)
	controls_overlay.visible = false
	control_settings_menu.dismiss()
	menu_layer.visible = false
	address_input.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_to_menu() -> void:
	NetworkManager.close_session()
	if game_world != null and is_instance_valid(game_world):
		if game_world.get_parent() == self:
			remove_child(game_world)
		game_world.queue_free()
	game_world = null
	menu_layer.visible = true
	controls_overlay.visible = false
	control_settings_menu.dismiss()
	status_label.text = READY_STATUS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_focus_main_menu")


func _on_network_error(message: String) -> void:
	status_label.text = message
	if game_world != null:
		_return_to_menu()
		status_label.text = message


func _on_server_disconnected() -> void:
	if game_world != null:
		_return_to_menu()
		status_label.text = "The host ended the match."


func _ensure_input_actions() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_backward", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("sprint", KEY_SHIFT)
	_add_key("jump", KEY_SPACE)
	_add_mouse_button("kick", MOUSE_BUTTON_LEFT)
	_add_mouse_button("juggle", MOUSE_BUTTON_RIGHT)
	_ensure_action("bicycle_modifier")
	_remove_key("bicycle_modifier", KEY_CTRL)
	_add_key("control_ball", KEY_CTRL)
	_add_keycode("control_ball", KEY_CTRL)
	_add_key("tackle", KEY_F)
	_add_key("pause", KEY_ESCAPE)
	_add_key("test_goalkeeper_shot", KEY_G)

	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_backward", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_axis("kick", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_button("kick", JOY_BUTTON_X)
	_add_joy_button("juggle", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_axis("bicycle_modifier", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_button("tackle", JOY_BUTTON_B)
	_remove_joy_button("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("control_ball", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_add_joy_button("pause", JOY_BUTTON_START)

	# Explicit UI actions make every menu usable without a mouse.
	_add_joy_button("ui_accept", JOY_BUTTON_A)
	_add_joy_button("ui_cancel", JOY_BUTTON_B)
	_add_joy_button("ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button("ui_focus_next", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("ui_focus_prev", JOY_BUTTON_LEFT_SHOULDER)


func _ensure_action(action: StringName, deadzone: float = 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)


func _add_key(action: StringName, keycode: int) -> void:
	_ensure_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_keycode(action: StringName, keycode: int) -> void:
	_ensure_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_mouse_button(action: StringName, button_index: int) -> void:
	_ensure_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joy_axis(action: StringName, axis: int, value: float) -> void:
	_ensure_action(action, 0.22)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joy_button(action: StringName, button_index: int) -> void:
	_ensure_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _remove_key(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		return

	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventKey:
			var key_event := input_event as InputEventKey

			if (
				key_event.physical_keycode == keycode
				or key_event.keycode == keycode
			):
				InputMap.action_erase_event(action, input_event)


func _remove_joy_button(action: StringName, button_index: int) -> void:
	if not InputMap.has_action(action):
		return

	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventJoypadButton:
			var button_event := input_event as InputEventJoypadButton

			if button_event.button_index == button_index:
				InputMap.action_erase_event(action, input_event)
