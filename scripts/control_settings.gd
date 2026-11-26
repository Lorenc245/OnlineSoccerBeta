extends Control

## Reusable local-only control settings screen.
## Static values are shared by the main-menu and in-match instances.

signal closed

const SETTINGS_PATH: String = "user://touchforge_controls.cfg"
const DEVICE_KEYBOARD: String = "keyboard"
const DEVICE_CONTROLLER: String = "controller"

const DEFAULT_MOUSE_SENSITIVITY_SCALE: float = 1.0
const DEFAULT_CONTROLLER_SENSITIVITY_SCALE: float = 1.0
const DEFAULT_CONTROLLER_DEADZONE: float = 0.22
const DEFAULT_INVERT_VERTICAL: bool = false

const MIN_SENSITIVITY_SCALE: float = 0.35
const MAX_SENSITIVITY_SCALE: float = 2.50
const MIN_CONTROLLER_DEADZONE: float = 0.05
const MAX_CONTROLLER_DEADZONE: float = 0.45

const BINDABLE_ACTIONS = [
	{"action": "move_forward", "label": "Move forward"},
	{"action": "move_backward", "label": "Move backward"},
	{"action": "move_left", "label": "Move left"},
	{"action": "move_right", "label": "Move right"},
	{"action": "kick", "label": "Kick / pass / shoot"},
	{"action": "juggle", "label": "Juggle"},
	{"action": "control_ball", "label": "Control ball"},
	{"action": "sprint", "label": "Sprint"},
	{"action": "jump", "label": "Jump"},
	{"action": "tackle", "label": "Tackle / goalkeeper dive"},
	{"action": "pause", "label": "Match menu"}
]

const DEADZONE_ACTIONS = [
	"move_forward",
	"move_backward",
	"move_left",
	"move_right",
	"look_left",
	"look_right",
	"look_up",
	"look_down"
]

static var mouse_sensitivity_scale: float = (
	DEFAULT_MOUSE_SENSITIVITY_SCALE
)
static var controller_sensitivity_scale: float = (
	DEFAULT_CONTROLLER_SENSITIVITY_SCALE
)
static var controller_deadzone: float = DEFAULT_CONTROLLER_DEADZONE
static var invert_vertical: bool = DEFAULT_INVERT_VERTICAL
static var initialized: bool = false
static var default_bindings: Dictionary = {}

var mouse_slider: HSlider
var controller_slider: HSlider
var deadzone_slider: HSlider
var mouse_value_label: Label
var controller_value_label: Label
var deadzone_value_label: Label
var invert_checkbox: CheckBox
var status_label: Label
var reset_button: Button
var back_button: Button
var binding_buttons: Dictionary = {}
var capture_action: StringName = &""
var capture_device: String = ""
var capture_ignore_until_msec: int = 0
var updating_ui: bool = false


static func initialize() -> void:
	if initialized:
		return

	_capture_default_bindings()
	_load_settings()
	_apply_controller_deadzone()
	initialized = true


static func _capture_default_bindings() -> void:
	default_bindings.clear()

	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		var action: StringName = StringName(str(entry["action"]))
		var copies: Array = []

		if InputMap.has_action(action):
			for input_event in InputMap.action_get_events(action):
				var copied_event: InputEvent = (
					input_event.duplicate(true) as InputEvent
				)
				copies.append(copied_event)

		default_bindings[action] = copies


static func _load_settings() -> void:
	var config := ConfigFile.new()
	var load_error: Error = config.load(SETTINGS_PATH)

	if load_error != OK:
		return

	mouse_sensitivity_scale = clampf(
		float(config.get_value(
			"camera",
			"mouse_sensitivity_scale",
			DEFAULT_MOUSE_SENSITIVITY_SCALE
		)),
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE
	)
	controller_sensitivity_scale = clampf(
		float(config.get_value(
			"camera",
			"controller_sensitivity_scale",
			DEFAULT_CONTROLLER_SENSITIVITY_SCALE
		)),
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE
	)
	controller_deadzone = clampf(
		float(config.get_value(
			"controller",
			"deadzone",
			DEFAULT_CONTROLLER_DEADZONE
		)),
		MIN_CONTROLLER_DEADZONE,
		MAX_CONTROLLER_DEADZONE
	)
	invert_vertical = bool(config.get_value(
		"camera",
		"invert_vertical",
		DEFAULT_INVERT_VERTICAL
	))

	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		var action: StringName = StringName(str(entry["action"]))
		var key: String = String(action)

		if not config.has_section_key("bindings", key):
			continue

		var stored_value: Variant = config.get_value(
			"bindings",
			key,
			[]
		)

		if not stored_value is Array:
			continue

		if not InputMap.has_action(action):
			InputMap.add_action(action)

		InputMap.action_erase_events(action)

		var stored_events: Array = stored_value
		for event_data_value in stored_events:
			if not event_data_value is Dictionary:
				continue

			var event_data: Dictionary = event_data_value
			var restored_event: InputEvent = _data_to_event(event_data)

			if restored_event != null:
				InputMap.action_add_event(action, restored_event)


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(
		"camera",
		"mouse_sensitivity_scale",
		mouse_sensitivity_scale
	)
	config.set_value(
		"camera",
		"controller_sensitivity_scale",
		controller_sensitivity_scale
	)
	config.set_value(
		"camera",
		"invert_vertical",
		invert_vertical
	)
	config.set_value(
		"controller",
		"deadzone",
		controller_deadzone
	)

	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		var action: StringName = StringName(str(entry["action"]))
		var encoded_events: Array = []

		if InputMap.has_action(action):
			for input_event in InputMap.action_get_events(action):
				var encoded_event: Dictionary = _event_to_data(
					input_event
				)

				if not encoded_event.is_empty():
					encoded_events.append(encoded_event)

		config.set_value(
			"bindings",
			String(action),
			encoded_events
		)

	var save_error: Error = config.save(SETTINGS_PATH)

	if save_error != OK:
		push_warning(
			"Could not save TOUCHFORGE controls: %d"
			% save_error
		)


static func set_mouse_sensitivity_scale(value: float) -> void:
	mouse_sensitivity_scale = clampf(
		value,
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE
	)
	save_settings()


static func set_controller_sensitivity_scale(value: float) -> void:
	controller_sensitivity_scale = clampf(
		value,
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE
	)
	save_settings()


static func set_controller_deadzone(value: float) -> void:
	controller_deadzone = clampf(
		value,
		MIN_CONTROLLER_DEADZONE,
		MAX_CONTROLLER_DEADZONE
	)
	_apply_controller_deadzone()
	save_settings()


static func set_invert_vertical(value: bool) -> void:
	invert_vertical = value
	save_settings()


static func _apply_controller_deadzone() -> void:
	for action_name_value in DEADZONE_ACTIONS:
		var action: StringName = StringName(str(action_name_value))

		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, controller_deadzone)


static func reset_to_defaults() -> void:
	mouse_sensitivity_scale = DEFAULT_MOUSE_SENSITIVITY_SCALE
	controller_sensitivity_scale = (
		DEFAULT_CONTROLLER_SENSITIVITY_SCALE
	)
	controller_deadzone = DEFAULT_CONTROLLER_DEADZONE
	invert_vertical = DEFAULT_INVERT_VERTICAL

	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		var action: StringName = StringName(str(entry["action"]))

		if not InputMap.has_action(action):
			InputMap.add_action(action)

		InputMap.action_erase_events(action)

		var copies: Array = default_bindings.get(action, [])
		for copied_event_value in copies:
			var copied_event: InputEvent = (
				copied_event_value.duplicate(true) as InputEvent
			)
			InputMap.action_add_event(action, copied_event)

	_apply_controller_deadzone()
	save_settings()


static func rebind_action(
	action: StringName,
	input_event: InputEvent,
	device_group: String
) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	var normalized_event: InputEvent = _normalize_binding_event(
		input_event
	)

	if normalized_event == null:
		return

	var new_signature: String = _event_signature(normalized_event)

	# A physical control belongs to one gameplay action at a time. UI actions
	# are intentionally untouched so controller navigation always remains usable.
	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		var other_action: StringName = StringName(str(entry["action"]))

		if not InputMap.has_action(other_action):
			continue

		for existing_event in InputMap.action_get_events(other_action):
			if (
				_event_device_group(existing_event) == device_group
				and (
					other_action == action
					or _event_signature(existing_event) == new_signature
				)
			):
				InputMap.action_erase_event(
					other_action,
					existing_event
				)

	InputMap.action_add_event(action, normalized_event)
	save_settings()


static func action_has_key(action: StringName, keycode: int) -> bool:
	if not InputMap.has_action(action):
		return false

	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventKey:
			var key_event := input_event as InputEventKey

			if (
				int(key_event.keycode) == keycode
				or int(key_event.physical_keycode) == keycode
			):
				return true

	return false


static func action_has_joy_button(
	action: StringName,
	button_index: int
) -> bool:
	if not InputMap.has_action(action):
		return false

	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventJoypadButton:
			var button_event := input_event as InputEventJoypadButton

			if button_event.button_index == button_index:
				return true

	return false


static func get_binding_text(
	action: StringName,
	device_group: String
) -> String:
	if not InputMap.has_action(action):
		return "UNBOUND"

	var labels := PackedStringArray()

	for input_event in InputMap.action_get_events(action):
		if _event_device_group(input_event) != device_group:
			continue

		var label: String = _event_display_text(input_event)

		if not label.is_empty() and not labels.has(label):
			labels.append(label)

	if labels.is_empty():
		return "UNBOUND"

	return "  OR  ".join(labels)


static func _normalize_binding_event(
	input_event: InputEvent
) -> InputEvent:
	if input_event is InputEventKey:
		var source_key := input_event as InputEventKey
		var key_event := InputEventKey.new()
		key_event.keycode = source_key.keycode
		key_event.physical_keycode = source_key.physical_keycode
		key_event.device = -1
		return key_event

	if input_event is InputEventMouseButton:
		var source_mouse := input_event as InputEventMouseButton
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = source_mouse.button_index
		mouse_event.device = -1
		return mouse_event

	if input_event is InputEventJoypadButton:
		var source_button := input_event as InputEventJoypadButton
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = source_button.button_index
		button_event.device = -1
		return button_event

	if input_event is InputEventJoypadMotion:
		var source_motion := input_event as InputEventJoypadMotion
		var motion_event := InputEventJoypadMotion.new()
		motion_event.axis = source_motion.axis
		motion_event.axis_value = (
			-1.0 if source_motion.axis_value < 0.0 else 1.0
		)
		motion_event.device = -1
		return motion_event

	return null


static func _event_device_group(input_event: InputEvent) -> String:
	if (
		input_event is InputEventJoypadButton
		or input_event is InputEventJoypadMotion
	):
		return DEVICE_CONTROLLER

	if (
		input_event is InputEventKey
		or input_event is InputEventMouseButton
	):
		return DEVICE_KEYBOARD

	return ""


static func _event_signature(input_event: InputEvent) -> String:
	if input_event is InputEventKey:
		var key_event := input_event as InputEventKey
		var keycode: int = int(key_event.physical_keycode)

		if keycode == 0:
			keycode = int(key_event.keycode)

		return "key:%d" % keycode

	if input_event is InputEventMouseButton:
		var mouse_event := input_event as InputEventMouseButton
		return "mouse:%d" % mouse_event.button_index

	if input_event is InputEventJoypadButton:
		var button_event := input_event as InputEventJoypadButton
		return "joy_button:%d" % button_event.button_index

	if input_event is InputEventJoypadMotion:
		var motion_event := input_event as InputEventJoypadMotion
		var direction: int = -1 if motion_event.axis_value < 0.0 else 1
		return "joy_axis:%d:%d" % [motion_event.axis, direction]

	return ""


static func _event_to_data(input_event: InputEvent) -> Dictionary:
	if input_event is InputEventKey:
		var key_event := input_event as InputEventKey
		return {
			"type": "key",
			"keycode": int(key_event.keycode),
			"physical_keycode": int(key_event.physical_keycode)
		}

	if input_event is InputEventMouseButton:
		var mouse_event := input_event as InputEventMouseButton
		return {
			"type": "mouse_button",
			"button_index": mouse_event.button_index
		}

	if input_event is InputEventJoypadButton:
		var button_event := input_event as InputEventJoypadButton
		return {
			"type": "joy_button",
			"button_index": button_event.button_index
		}

	if input_event is InputEventJoypadMotion:
		var motion_event := input_event as InputEventJoypadMotion
		return {
			"type": "joy_axis",
			"axis": motion_event.axis,
			"axis_value": (
				-1.0 if motion_event.axis_value < 0.0 else 1.0
			)
		}

	return {}


static func _data_to_event(event_data: Dictionary) -> InputEvent:
	var event_type: String = str(event_data.get("type", ""))

	match event_type:
		"key":
			var key_event := InputEventKey.new()
			key_event.keycode = int(event_data.get("keycode", 0))
			key_event.physical_keycode = int(
				event_data.get("physical_keycode", 0)
			)
			key_event.device = -1
			return key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(
				event_data.get("button_index", MOUSE_BUTTON_LEFT)
			)
			mouse_event.device = -1
			return mouse_event
		"joy_button":
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = int(
				event_data.get("button_index", JOY_BUTTON_A)
			)
			button_event.device = -1
			return button_event
		"joy_axis":
			var motion_event := InputEventJoypadMotion.new()
			motion_event.axis = int(event_data.get("axis", 0))
			motion_event.axis_value = float(
				event_data.get("axis_value", 1.0)
			)
			motion_event.device = -1
			return motion_event

	return null


static func _event_display_text(input_event: InputEvent) -> String:
	if input_event is InputEventKey:
		var key_event := input_event as InputEventKey
		var keycode: int = int(key_event.physical_keycode)

		if keycode == 0:
			keycode = int(key_event.keycode)

		return OS.get_keycode_string(keycode).to_upper()

	if input_event is InputEventMouseButton:
		var mouse_event := input_event as InputEventMouseButton

		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_XBUTTON1:
				return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2:
				return "MOUSE 5"

		return "MOUSE %d" % mouse_event.button_index

	if input_event is InputEventJoypadButton:
		var button_event := input_event as InputEventJoypadButton

		match button_event.button_index:
			JOY_BUTTON_A:
				return "A / CROSS"
			JOY_BUTTON_B:
				return "B / CIRCLE"
			JOY_BUTTON_X:
				return "X / SQUARE"
			JOY_BUTTON_Y:
				return "Y / TRIANGLE"
			JOY_BUTTON_LEFT_SHOULDER:
				return "LB / L1"
			JOY_BUTTON_RIGHT_SHOULDER:
				return "RB / R1"
			JOY_BUTTON_LEFT_STICK:
				return "L3"
			JOY_BUTTON_RIGHT_STICK:
				return "R3"
			JOY_BUTTON_BACK:
				return "BACK / SHARE"
			JOY_BUTTON_START:
				return "MENU / OPTIONS"
			JOY_BUTTON_DPAD_UP:
				return "DPAD UP"
			JOY_BUTTON_DPAD_DOWN:
				return "DPAD DOWN"
			JOY_BUTTON_DPAD_LEFT:
				return "DPAD LEFT"
			JOY_BUTTON_DPAD_RIGHT:
				return "DPAD RIGHT"

		return "BUTTON %d" % button_event.button_index

	if input_event is InputEventJoypadMotion:
		var motion_event := input_event as InputEventJoypadMotion
		var negative: bool = motion_event.axis_value < 0.0

		match motion_event.axis:
			JOY_AXIS_LEFT_X:
				return "LEFT STICK LEFT" if negative else "LEFT STICK RIGHT"
			JOY_AXIS_LEFT_Y:
				return "LEFT STICK UP" if negative else "LEFT STICK DOWN"
			JOY_AXIS_RIGHT_X:
				return "RIGHT STICK LEFT" if negative else "RIGHT STICK RIGHT"
			JOY_AXIS_RIGHT_Y:
				return "RIGHT STICK UP" if negative else "RIGHT STICK DOWN"
			JOY_AXIS_TRIGGER_LEFT:
				return "LT / L2"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT / R2"

		return "AXIS %d" % motion_event.axis

	return ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initialize()
	_build_interface()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color(0.004, 0.011, 0.021, 0.97)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(980, 620)
	card.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("0d2035"), 20, Color("315575"))
	)
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var title := Label.new()
	title.text = "CONTROL SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 31)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = (
		"Saved only on this PC • changes apply immediately • click a binding to replace it"
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("91a5bd"))
	column.add_child(subtitle)

	var tuning_panel := PanelContainer.new()
	tuning_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("091a2b"), 12, Color("244966"))
	)
	column.add_child(tuning_panel)

	var tuning_margin := MarginContainer.new()
	tuning_margin.add_theme_constant_override("margin_left", 18)
	tuning_margin.add_theme_constant_override("margin_right", 18)
	tuning_margin.add_theme_constant_override("margin_top", 10)
	tuning_margin.add_theme_constant_override("margin_bottom", 10)
	tuning_panel.add_child(tuning_margin)

	var tuning_grid := GridContainer.new()
	tuning_grid.columns = 4
	tuning_grid.add_theme_constant_override("h_separation", 14)
	tuning_grid.add_theme_constant_override("v_separation", 7)
	tuning_margin.add_child(tuning_grid)

	_add_slider_setting(
		tuning_grid,
		"MOUSE LOOK",
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE,
		0.05,
		"mouse"
	)
	_add_slider_setting(
		tuning_grid,
		"CONTROLLER LOOK",
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE,
		0.05,
		"controller"
	)
	_add_slider_setting(
		tuning_grid,
		"STICK DEADZONE",
		MIN_CONTROLLER_DEADZONE,
		MAX_CONTROLLER_DEADZONE,
		0.01,
		"deadzone"
	)

	var invert_spacer := Control.new()
	invert_spacer.custom_minimum_size.x = 145
	tuning_grid.add_child(invert_spacer)

	invert_checkbox = CheckBox.new()
	invert_checkbox.text = "INVERT VERTICAL CAMERA"
	invert_checkbox.focus_mode = Control.FOCUS_ALL
	invert_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invert_checkbox.toggled.connect(_on_invert_toggled)
	tuning_grid.add_child(invert_checkbox)

	var invert_hint := Label.new()
	invert_hint.text = "Mouse + right stick"
	invert_hint.add_theme_color_override("font_color", Color("71869d"))
	tuning_grid.add_child(invert_hint)

	var invert_value_spacer := Control.new()
	invert_value_spacer.custom_minimum_size.x = 58
	tuning_grid.add_child(invert_value_spacer)

	var bindings_title := Label.new()
	bindings_title.text = "CUSTOM BINDINGS"
	bindings_title.add_theme_font_size_override("font_size", 17)
	bindings_title.add_theme_color_override("font_color", Color("68ddb0"))
	column.add_child(bindings_title)

	var binding_header := HBoxContainer.new()
	binding_header.add_theme_constant_override("separation", 10)
	column.add_child(binding_header)

	var action_header := _header_label("ACTION", 250)
	binding_header.add_child(action_header)
	var keyboard_header := _header_label("KEYBOARD / MOUSE", 310)
	binding_header.add_child(keyboard_header)
	var controller_header := _header_label("CONTROLLER", 310)
	binding_header.add_child(controller_header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 245
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var binding_column := VBoxContainer.new()
	binding_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binding_column.add_theme_constant_override("separation", 5)
	scroll.add_child(binding_column)

	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		_add_binding_row(
			binding_column,
			StringName(str(entry["action"])),
			str(entry["label"])
		)

	status_label = Label.new()
	status_label.text = "Select any binding, then press the new key or controller input."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("9eb3c8"))
	column.add_child(status_label)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 12)
	column.add_child(action_row)

	reset_button = _button("RESET DEFAULTS", Color("a97727"))
	reset_button.pressed.connect(_reset_requested)
	action_row.add_child(reset_button)

	back_button = _button("BACK", Color("2677d9"))
	back_button.pressed.connect(close_menu)
	action_row.add_child(back_button)

	_sync_interface()


func _add_slider_setting(
	parent: GridContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	setting_name: String
) -> void:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 145
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("c7d5e3"))
	parent.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size.x = 250
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	parent.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 58
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", Color("67ddb0"))
	parent.add_child(value_label)

	var hint := Label.new()
	hint.custom_minimum_size.x = 310
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("71869d"))
	parent.add_child(hint)

	match setting_name:
		"mouse":
			mouse_slider = slider
			mouse_value_label = value_label
			hint.text = "Camera speed with mouse movement"
			slider.value_changed.connect(_on_mouse_sensitivity_changed)
		"controller":
			controller_slider = slider
			controller_value_label = value_label
			hint.text = "Camera speed with the right stick"
			slider.value_changed.connect(
				_on_controller_sensitivity_changed
			)
		"deadzone":
			deadzone_slider = slider
			deadzone_value_label = value_label
			hint.text = "Raise this if a stick moves by itself"
			slider.value_changed.connect(_on_deadzone_changed)


func _header_label(text_value: String, width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = width
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("71869d"))
	return label


func _add_binding_row(
	parent: VBoxContainer,
	action: StringName,
	label_text: String
) -> void:
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color("0a1929"), 7, Color(1, 1, 1, 0.055))
	)
	parent.add_child(row_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	row_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 230
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("d6e1ed"))
	row.add_child(label)

	var keyboard_button := _binding_button()
	keyboard_button.custom_minimum_size.x = 300
	keyboard_button.pressed.connect(
		_begin_rebind.bind(action, DEVICE_KEYBOARD)
	)
	row.add_child(keyboard_button)

	var controller_button := _binding_button()
	controller_button.custom_minimum_size.x = 300
	controller_button.pressed.connect(
		_begin_rebind.bind(action, DEVICE_CONTROLLER)
	)
	row.add_child(controller_button)

	binding_buttons[action] = {
		DEVICE_KEYBOARD: keyboard_button,
		DEVICE_CONTROLLER: controller_button
	}


func _button(text_value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(240, 43)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(accent.darkened(0.28), 8, accent)
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(
			accent.darkened(0.10),
			8,
			accent.lightened(0.12)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(accent.darkened(0.42), 8, accent)
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(accent.darkened(0.04), 8, Color.WHITE)
	)
	return button


func _binding_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 32
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("d9e8f6"))
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(Color("142a3e"), 6, Color("2c526e"))
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(Color("1b3850"), 6, Color("4a85aa"))
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(Color("0c1d2d"), 6, Color("5ee6af"))
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(Color("18384d"), 6, Color.WHITE)
	)
	return button


func _panel_style(
	color: Color,
	radius: int,
	border_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
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


func open_menu() -> void:
	initialize()
	capture_action = &""
	capture_device = ""
	_sync_interface()
	status_label.text = (
		"Select any binding, then press the new key or controller input."
	)
	status_label.add_theme_color_override(
		"font_color",
		Color("9eb3c8")
	)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_slider.call_deferred("grab_focus")


func close_menu() -> void:
	if not visible:
		return

	capture_action = &""
	capture_device = ""
	visible = false
	closed.emit()


func dismiss() -> void:
	capture_action = &""
	capture_device = ""
	visible = false


func is_open() -> bool:
	return visible


func _sync_interface() -> void:
	if mouse_slider == null:
		return

	updating_ui = true
	mouse_slider.value = mouse_sensitivity_scale
	controller_slider.value = controller_sensitivity_scale
	deadzone_slider.value = controller_deadzone
	invert_checkbox.button_pressed = invert_vertical
	_update_value_labels()

	for entry_value in BINDABLE_ACTIONS:
		var entry: Dictionary = entry_value
		var action: StringName = StringName(str(entry["action"]))

		if not binding_buttons.has(action):
			continue

		var row_buttons: Dictionary = binding_buttons[action]
		var keyboard_button := (
			row_buttons[DEVICE_KEYBOARD] as Button
		)
		var controller_button := (
			row_buttons[DEVICE_CONTROLLER] as Button
		)

		keyboard_button.text = get_binding_text(
			action,
			DEVICE_KEYBOARD
		)
		controller_button.text = get_binding_text(
			action,
			DEVICE_CONTROLLER
		)

	updating_ui = false


func _update_value_labels() -> void:
	mouse_value_label.text = "%d%%" % int(round(
		mouse_sensitivity_scale * 100.0
	))
	controller_value_label.text = "%d%%" % int(round(
		controller_sensitivity_scale * 100.0
	))
	deadzone_value_label.text = "%d%%" % int(round(
		controller_deadzone * 100.0
	))


func _on_mouse_sensitivity_changed(value: float) -> void:
	if updating_ui:
		return

	set_mouse_sensitivity_scale(value)
	_update_value_labels()


func _on_controller_sensitivity_changed(value: float) -> void:
	if updating_ui:
		return

	set_controller_sensitivity_scale(value)
	_update_value_labels()


func _on_deadzone_changed(value: float) -> void:
	if updating_ui:
		return

	set_controller_deadzone(value)
	_update_value_labels()


func _on_invert_toggled(value: bool) -> void:
	if updating_ui:
		return

	set_invert_vertical(value)


func _begin_rebind(action: StringName, device_group: String) -> void:
	capture_action = action
	capture_device = device_group
	capture_ignore_until_msec = Time.get_ticks_msec() + 180

	var input_name: String = (
		"a key or mouse button"
		if device_group == DEVICE_KEYBOARD
		else "a controller button, trigger, or stick direction"
	)

	status_label.text = (
		"Press %s now • Esc cancels."
		% input_name
	)
	status_label.add_theme_color_override(
		"font_color",
		Color("ffd166")
	)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if capture_action != &"":
		if Time.get_ticks_msec() < capture_ignore_until_msec:
			return

		if event is InputEventKey:
			var key_event := event as InputEventKey

			if not key_event.pressed or key_event.echo:
				return

			if (
				key_event.keycode == KEY_ESCAPE
				or key_event.physical_keycode == KEY_ESCAPE
			):
				_cancel_capture()
				get_viewport().set_input_as_handled()
				return

			if capture_device == DEVICE_KEYBOARD:
				_accept_binding(key_event)
				get_viewport().set_input_as_handled()
				return

		if (
			event is InputEventMouseButton
			and capture_device == DEVICE_KEYBOARD
		):
			var mouse_event := event as InputEventMouseButton

			if mouse_event.pressed:
				_accept_binding(mouse_event)
				get_viewport().set_input_as_handled()
			return

		if (
			event is InputEventJoypadButton
			and capture_device == DEVICE_CONTROLLER
		):
			var button_event := event as InputEventJoypadButton

			if button_event.pressed:
				_accept_binding(button_event)
				get_viewport().set_input_as_handled()
			return

		if (
			event is InputEventJoypadMotion
			and capture_device == DEVICE_CONTROLLER
		):
			var motion_event := event as InputEventJoypadMotion

			if absf(motion_event.axis_value) >= 0.72:
				_accept_binding(motion_event)
				get_viewport().set_input_as_handled()
			return

		return

	if (
		event.is_action_pressed("ui_cancel")
		or event.is_action_pressed("pause")
	):
		close_menu()
		get_viewport().set_input_as_handled()


func _accept_binding(input_event: InputEvent) -> void:
	var action: StringName = capture_action
	var device_group: String = capture_device
	rebind_action(action, input_event, device_group)
	capture_action = &""
	capture_device = ""
	_sync_interface()
	status_label.text = "Binding updated and saved on this PC."
	status_label.add_theme_color_override(
		"font_color",
		Color("68ddb0")
	)


func _cancel_capture() -> void:
	capture_action = &""
	capture_device = ""
	status_label.text = "Binding change cancelled."
	status_label.add_theme_color_override(
		"font_color",
		Color("9eb3c8")
	)


func _reset_requested() -> void:
	reset_to_defaults()
	_sync_interface()
	status_label.text = "Default controls restored and saved."
	status_label.add_theme_color_override(
		"font_color",
		Color("68ddb0")
	)
