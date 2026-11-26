extends CanvasLayer

const ControlSettingsScript = preload("res://scripts/control_settings.gd")

signal resume_requested
signal leave_requested
signal restart_requested
signal team_requested(team: int)

var blue_score_label: Label
var red_score_label: Label
var timer_label: Label
var status_label: Label
var notification_label: Label
var charge_panel: PanelContainer
var charge_bar: ProgressBar
var pause_overlay: Control
var controls_overlay: Control
var control_settings_menu
var game_over_overlay: Control
var team_select_overlay: Control
var result_label: Label
var restart_button: Button
var pause_resume_button: Button
var pause_controls_button: Button
var controls_back_button: Button
var controls_customize_button: Button
var game_over_leave_button: Button
var blue_team_button: Button
var red_team_button: Button
var auto_team_button: Button
var blue_roster_label: Label
var red_roster_label: Label
var waiting_players_label: Label
var team_select_status_label: Label
var message_timer: Timer


func _ready() -> void:
	layer = 10
	_build_hud()


func _build_hud() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var scoreboard := PanelContainer.new()
	scoreboard.anchor_left = 0.5
	scoreboard.anchor_right = 0.5
	scoreboard.offset_left = -225
	scoreboard.offset_right = 225
	scoreboard.offset_top = 18
	scoreboard.offset_bottom = 82
	scoreboard.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.09, 0.94), 14, Color(1, 1, 1, 0.14)))
	root.add_child(scoreboard)

	var score_margin := MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 18)
	score_margin.add_theme_constant_override("margin_right", 18)
	score_margin.add_theme_constant_override("margin_top", 8)
	score_margin.add_theme_constant_override("margin_bottom", 8)
	scoreboard.add_child(score_margin)

	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 18)
	score_margin.add_child(score_row)

	var blue_name := _score_text("BLUE", Color("52bdff"), 18)
	blue_name.custom_minimum_size.x = 72
	score_row.add_child(blue_name)

	blue_score_label = _score_text("0", Color.WHITE, 29)
	blue_score_label.custom_minimum_size.x = 35
	score_row.add_child(blue_score_label)

	timer_label = _score_text("03:00", Color("f4f7fb"), 25)
	timer_label.custom_minimum_size.x = 100
	timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(timer_label)

	red_score_label = _score_text("0", Color.WHITE, 29)
	red_score_label.custom_minimum_size.x = 35
	score_row.add_child(red_score_label)

	var red_name := _score_text("RED", Color("ff7481"), 18)
	red_name.custom_minimum_size.x = 72
	score_row.add_child(red_name)

	status_label = Label.new()
	status_label.position = Vector2(20, 18)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color("bfd0e3"))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(status_label)

	notification_label = Label.new()
	notification_label.anchor_left = 0.5
	notification_label.anchor_right = 0.5
	notification_label.anchor_top = 0.22
	notification_label.anchor_bottom = 0.22
	notification_label.offset_left = -340
	notification_label.offset_right = 340
	notification_label.offset_top = -32
	notification_label.offset_bottom = 32
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification_label.add_theme_font_size_override("font_size", 30)
	notification_label.add_theme_color_override("font_color", Color.WHITE)
	notification_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	notification_label.add_theme_constant_override("shadow_offset_x", 2)
	notification_label.add_theme_constant_override("shadow_offset_y", 3)
	root.add_child(notification_label)

	var crosshair := Label.new()
	crosshair.text = "•"
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -10
	crosshair.offset_right = 10
	crosshair.offset_top = -14
	crosshair.offset_bottom = 14
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.64))
	root.add_child(crosshair)

	charge_panel = PanelContainer.new()
	charge_panel.anchor_left = 0.5
	charge_panel.anchor_right = 0.5
	charge_panel.anchor_top = 1.0
	charge_panel.anchor_bottom = 1.0
	charge_panel.offset_left = -150
	charge_panel.offset_right = 150
	charge_panel.offset_top = -66
	charge_panel.offset_bottom = -24
	charge_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.045, 0.075, 0.86), 9))
	charge_panel.visible = false
	root.add_child(charge_panel)

	var charge_margin := MarginContainer.new()
	charge_margin.add_theme_constant_override("margin_left", 10)
	charge_margin.add_theme_constant_override("margin_right", 10)
	charge_margin.add_theme_constant_override("margin_top", 8)
	charge_margin.add_theme_constant_override("margin_bottom", 8)
	charge_panel.add_child(charge_margin)

	charge_bar = ProgressBar.new()
	charge_bar.min_value = 0
	charge_bar.max_value = 100
	charge_bar.value = 0
	charge_bar.show_percentage = false
	charge_bar.add_theme_stylebox_override("background", _panel_style(Color("15263a"), 6))
	charge_bar.add_theme_stylebox_override("fill", _panel_style(Color("40d89b"), 6))
	charge_margin.add_child(charge_bar)

	pause_overlay = _build_pause_overlay(root)
	controls_overlay = _build_controls_overlay(root)
	game_over_overlay = _build_game_over_overlay(root)
	team_select_overlay = _build_team_select_overlay(root)
	control_settings_menu = ControlSettingsScript.new()
	control_settings_menu.name = "ControlSettingsMenu"
	control_settings_menu.visible = false
	control_settings_menu.closed.connect(_on_control_settings_closed)
	root.add_child(control_settings_menu)

	message_timer = Timer.new()
	message_timer.one_shot = true
	message_timer.timeout.connect(_hide_message)
	add_child(message_timer)


func _score_text(value: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_pause_overlay(parent: Control) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.005, 0.012, 0.022, 0.76)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	parent.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(390, 340)
	card.add_theme_stylebox_override("panel", _panel_style(Color("102238"), 18, Color("2c4c6e")))
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "MATCH MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 29)
	column.add_child(title)

	var hint := Label.new()
	hint.text = "The online match continues while this menu is open."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("91a5bd"))
	column.add_child(hint)

	pause_resume_button = _button("RESUME", Color("1fbf83"))
	pause_resume_button.pressed.connect(func(): resume_requested.emit())
	column.add_child(pause_resume_button)

	pause_controls_button = _button("CONTROLS", Color("2677d9"))
	pause_controls_button.pressed.connect(_show_pause_controls)
	column.add_child(pause_controls_button)

	var leave := _button("LEAVE MATCH", Color("ca4053"))
	leave.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave)
	return overlay


func _build_controls_overlay(parent: Control) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.005, 0.012, 0.022, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	parent.add_child(overlay)

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
	subtitle.text = "View the default guide or customize your local controls."
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

	controls_customize_button = _button(
		"CUSTOMIZE CONTROLS",
		Color("1fbf83")
	)
	controls_customize_button.custom_minimum_size.x = 300
	controls_customize_button.pressed.connect(_show_control_settings)
	controls_action_row.add_child(controls_customize_button)

	controls_back_button = _button("BACK", Color("2677d9"))
	controls_back_button.custom_minimum_size.x = 220
	controls_back_button.pressed.connect(_hide_pause_controls)
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


func _show_pause_controls() -> void:
	pause_overlay.visible = false
	controls_overlay.visible = true
	controls_customize_button.call_deferred("grab_focus")


func _hide_pause_controls() -> void:
	controls_overlay.visible = false
	pause_overlay.visible = true
	pause_controls_button.call_deferred("grab_focus")


func _show_control_settings() -> void:
	controls_overlay.visible = false
	control_settings_menu.open_menu()


func _on_control_settings_closed() -> void:
	controls_overlay.visible = true
	controls_customize_button.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if is_team_selection_visible():
		return
	if (
		control_settings_menu != null
		and control_settings_menu.is_open()
	):
		return

	if event.is_action_pressed("ui_cancel"):
		if controls_overlay != null and controls_overlay.visible:
			_hide_pause_controls()
			get_viewport().set_input_as_handled()
		elif pause_overlay != null and pause_overlay.visible:
			resume_requested.emit()
			get_viewport().set_input_as_handled()


func _build_game_over_overlay(parent: Control) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.005, 0.012, 0.022, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	parent.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 320)
	card.add_theme_stylebox_override("panel", _panel_style(Color("102238"), 18, Color("355878")))
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "FULL TIME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("8ea5bc"))
	column.add_child(title)

	result_label = Label.new()
	result_label.text = "DRAW\n0 — 0"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 36)
	column.add_child(result_label)

	restart_button = _button("REMATCH", Color("1fbf83"))
	restart_button.pressed.connect(func(): restart_requested.emit())
	column.add_child(restart_button)

	game_over_leave_button = _button("RETURN TO MENU", Color("2677d9"))
	game_over_leave_button.pressed.connect(func(): leave_requested.emit())
	column.add_child(game_over_leave_button)
	return overlay


func _build_team_select_overlay(parent: Control) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.004, 0.012, 0.024, 0.94)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	parent.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(780, 590)
	card.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("0d2035"), 20, Color("315575"))
	)
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var brand := Label.new()
	brand.text = "TOUCHFORGE"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 17)
	brand.add_theme_color_override("font_color", Color("72e0b3"))
	column.add_child(brand)

	var title := Label.new()
	title.text = "SELECT YOUR TEAM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose a side before kickoff • up to three players per team"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("9db1c7"))
	column.add_child(subtitle)

	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 18)
	team_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(team_row)

	var blue_panel := PanelContainer.new()
	blue_panel.custom_minimum_size = Vector2(338, 245)
	blue_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blue_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("0a2842"), 14, Color("329ce8"))
	)
	team_row.add_child(blue_panel)

	var blue_margin := MarginContainer.new()
	blue_margin.add_theme_constant_override("margin_left", 18)
	blue_margin.add_theme_constant_override("margin_right", 18)
	blue_margin.add_theme_constant_override("margin_top", 18)
	blue_margin.add_theme_constant_override("margin_bottom", 18)
	blue_panel.add_child(blue_margin)

	var blue_column := VBoxContainer.new()
	blue_column.add_theme_constant_override("separation", 14)
	blue_margin.add_child(blue_column)

	blue_team_button = _button("BLUE TEAM  0/3", Color("258ed8"))
	blue_team_button.custom_minimum_size.x = 300
	blue_team_button.pressed.connect(func(): team_requested.emit(0))
	blue_column.add_child(blue_team_button)

	blue_roster_label = Label.new()
	blue_roster_label.text = "— OPEN SLOT —\n— OPEN SLOT —\n— OPEN SLOT —"
	blue_roster_label.custom_minimum_size.y = 130
	blue_roster_label.add_theme_font_size_override("font_size", 16)
	blue_roster_label.add_theme_color_override("font_color", Color("d9efff"))
	blue_roster_label.add_theme_constant_override("line_spacing", 8)
	blue_column.add_child(blue_roster_label)

	var red_panel := PanelContainer.new()
	red_panel.custom_minimum_size = Vector2(338, 245)
	red_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("3d1825"), 14, Color("e8566b"))
	)
	team_row.add_child(red_panel)

	var red_margin := MarginContainer.new()
	red_margin.add_theme_constant_override("margin_left", 18)
	red_margin.add_theme_constant_override("margin_right", 18)
	red_margin.add_theme_constant_override("margin_top", 18)
	red_margin.add_theme_constant_override("margin_bottom", 18)
	red_panel.add_child(red_margin)

	var red_column := VBoxContainer.new()
	red_column.add_theme_constant_override("separation", 14)
	red_margin.add_child(red_column)

	red_team_button = _button("RED TEAM  0/3", Color("d94a5f"))
	red_team_button.custom_minimum_size.x = 300
	red_team_button.pressed.connect(func(): team_requested.emit(1))
	red_column.add_child(red_team_button)

	red_roster_label = Label.new()
	red_roster_label.text = "— OPEN SLOT —\n— OPEN SLOT —\n— OPEN SLOT —"
	red_roster_label.custom_minimum_size.y = 130
	red_roster_label.add_theme_font_size_override("font_size", 16)
	red_roster_label.add_theme_color_override("font_color", Color("ffe0e5"))
	red_roster_label.add_theme_constant_override("line_spacing", 8)
	red_column.add_child(red_roster_label)

	waiting_players_label = Label.new()
	waiting_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_players_label.add_theme_font_size_override("font_size", 14)
	waiting_players_label.add_theme_color_override("font_color", Color("9db1c7"))
	column.add_child(waiting_players_label)

	team_select_status_label = Label.new()
	team_select_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_select_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	team_select_status_label.custom_minimum_size.y = 42
	team_select_status_label.add_theme_color_override("font_color", Color("dce8f4"))
	column.add_child(team_select_status_label)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 12)
	column.add_child(action_row)

	auto_team_button = _button("AUTO-ASSIGN", Color("1caf7b"))
	auto_team_button.custom_minimum_size = Vector2(250, 46)
	auto_team_button.pressed.connect(func(): team_requested.emit(-1))
	action_row.add_child(auto_team_button)

	var leave_button := _button("LEAVE", Color("a83d51"))
	leave_button.custom_minimum_size = Vector2(150, 46)
	leave_button.pressed.connect(func(): leave_requested.emit())
	action_row.add_child(leave_button)

	blue_team_button.focus_neighbor_right = red_team_button.get_path()
	blue_team_button.focus_neighbor_bottom = auto_team_button.get_path()
	red_team_button.focus_neighbor_left = blue_team_button.get_path()
	red_team_button.focus_neighbor_bottom = auto_team_button.get_path()
	auto_team_button.focus_neighbor_top = blue_team_button.get_path()
	auto_team_button.focus_neighbor_right = leave_button.get_path()
	leave_button.focus_neighbor_left = auto_team_button.get_path()
	leave_button.focus_neighbor_top = red_team_button.get_path()

	return overlay


func _button(text_value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(275, 48)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _panel_style(accent.darkened(0.28), 9, accent))
	button.add_theme_stylebox_override("hover", _panel_style(accent.darkened(0.10), 9, accent.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _panel_style(accent.darkened(0.42), 9, accent))
	button.add_theme_stylebox_override("focus", _panel_style(accent.darkened(0.04), 9, Color.WHITE))
	return button


func _panel_style(color: Color, radius: int, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border_color.a > 0.0:
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = border_color
	return style


func set_match_state(blue_score: int, red_score: int, seconds_left: float) -> void:
	blue_score_label.text = str(blue_score)
	red_score_label.text = str(red_score)
	var total_seconds := maxi(0, int(ceil(seconds_left)))
	var minutes := int(total_seconds / 60)
	var seconds := total_seconds % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	if seconds_left <= 30.0:
		timer_label.add_theme_color_override("font_color", Color("ffca68"))
	else:
		timer_label.add_theme_color_override("font_color", Color("f4f7fb"))


func set_status(value: String) -> void:
	status_label.text = value


func set_charge(normalized_value: float) -> void:
	var amount := clampf(normalized_value, 0.0, 1.0)
	charge_bar.value = amount * 100.0
	charge_panel.visible = amount > 0.001
	var color := Color("40d89b").lerp(Color("ffb84b"), amount)
	charge_bar.add_theme_stylebox_override("fill", _panel_style(color, 6))


func show_message(value: String, duration: float = 2.0) -> void:
	notification_label.text = value
	notification_label.visible = true
	message_timer.start(duration)


func _hide_message() -> void:
	notification_label.visible = false


func set_pause_visible(value: bool) -> void:
	if value and is_team_selection_visible():
		return

	controls_overlay.visible = false
	control_settings_menu.dismiss()
	pause_overlay.visible = value

	if value:
		pause_resume_button.call_deferred("grab_focus")


func show_game_over(blue_score: int, red_score: int, can_restart: bool) -> void:
	var outcome := "DRAW"
	if blue_score > red_score:
		outcome = "BLUE WINS"
	elif red_score > blue_score:
		outcome = "RED WINS"
	result_label.text = "%s\n%d — %d" % [outcome, blue_score, red_score]
	restart_button.visible = can_restart
	game_over_overlay.visible = true
	control_settings_menu.dismiss()
	team_select_overlay.visible = false
	pause_overlay.visible = false
	controls_overlay.visible = false

	if can_restart:
		restart_button.call_deferred("grab_focus")
	else:
		game_over_leave_button.call_deferred("grab_focus")


func hide_game_over() -> void:
	game_over_overlay.visible = false
	controls_overlay.visible = false


func show_team_selection(
	blue_names: Array,
	red_names: Array,
	waiting_names: Array,
	local_team: int,
	max_team_size: int,
	message: String
) -> void:
	var was_visible: bool = team_select_overlay.visible
	var blue_full: bool = blue_names.size() >= max_team_size
	var red_full: bool = red_names.size() >= max_team_size

	blue_team_button.text = "BLUE TEAM  %d/%d%s" % [
		blue_names.size(),
		max_team_size,
		"  • SELECTED" if local_team == 0 else ""
	]
	red_team_button.text = "RED TEAM  %d/%d%s" % [
		red_names.size(),
		max_team_size,
		"  • SELECTED" if local_team == 1 else ""
	]

	blue_team_button.disabled = blue_full and local_team != 0
	red_team_button.disabled = red_full and local_team != 1
	auto_team_button.disabled = blue_full and red_full

	blue_roster_label.text = _format_team_roster(
		blue_names,
		max_team_size
	)
	red_roster_label.text = _format_team_roster(
		red_names,
		max_team_size
	)

	if waiting_names.is_empty():
		waiting_players_label.text = ""
	else:
		var waiting_text := PackedStringArray()
		for player_name_value in waiting_names:
			waiting_text.append(str(player_name_value))
		waiting_players_label.text = (
			"WAITING TO CHOOSE: "
			+ ", ".join(waiting_text)
		)

	team_select_status_label.text = message
	control_settings_menu.dismiss()
	team_select_overlay.visible = true
	game_over_overlay.visible = false
	pause_overlay.visible = false
	controls_overlay.visible = false

	if not was_visible:
		if local_team == 0 and not blue_team_button.disabled:
			blue_team_button.call_deferred("grab_focus")
		elif local_team == 1 and not red_team_button.disabled:
			red_team_button.call_deferred("grab_focus")
		elif not auto_team_button.disabled:
			auto_team_button.call_deferred("grab_focus")
		elif not blue_team_button.disabled:
			blue_team_button.call_deferred("grab_focus")
		else:
			red_team_button.call_deferred("grab_focus")


func _format_team_roster(names: Array, max_team_size: int) -> String:
	var lines := PackedStringArray()

	for player_name_value in names:
		lines.append("• %s" % str(player_name_value))

	for _unused_slot in range(max_team_size - names.size()):
		lines.append("— OPEN SLOT —")

	return "\n".join(lines)


func hide_team_selection() -> void:
	if team_select_overlay != null:
		team_select_overlay.visible = false


func set_team_selection_message(value: String) -> void:
	if team_select_status_label != null:
		team_select_status_label.text = value


func is_team_selection_visible() -> bool:
	return (
		team_select_overlay != null
		and team_select_overlay.visible
	)
