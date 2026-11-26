extends CharacterBody3D

## Responsive third-person footballer with procedural visuals.
## Local players predict their own movement; remote players interpolate snapshots.
const ControlSettingsScript = preload("res://scripts/control_settings.gd")
const BICYCLE_KICK_ENABLED: bool = false
const WALK_SPEED := 8.5
const SPRINT_SPEED := 12.4
const GROUND_ACCELERATION := 34.0
const AIR_ACCELERATION := 10.0
const JUMP_VELOCITY := 7.4
const TURN_SPEED := 13.0
const MAX_KICK_CHARGE_TIME := 0.65
const NETWORK_SEND_INTERVAL := 1.0 / 60.0
const NETWORK_MAX_EXTRAPOLATION := 0.10
const NETWORK_POSITION_RESPONSE := 40.0
const NETWORK_ROTATION_RESPONSE := 32.0
const MOUSE_SENSITIVITY := 0.0028
const CONTROLLER_YAW_SPEED: float = 2.45
const CONTROLLER_PITCH_SPEED: float = 1.9
const CONTROLLER_GESTURE_PIXELS_PER_SECOND: float = 420.0
const KICK_GESTURE_WINDOW_MS: int = 300
const CURVE_DEADZONE_PIXELS: float = 14.0
const CURVE_FULL_SWIPE_PIXELS: float = 95.0
const KNUCKLE_MIN_TRAVEL_PIXELS: float = 115.0
const KNUCKLE_MIN_REVERSALS: int = 3
const GESTURE_STEP_PIXELS: float = 2.5
const KICK_ANIMATION_DURATION: float = 0.42
const BALL_CONTROL_ANIMATION_DURATION: float = 0.24
const BICYCLE_ANIMATION_DURATION: float = 0.72
const GOALKEEPER_DIVE_DURATION: float = 0.48
const GOALKEEPER_DIVE_SPEED: float = 8.8

var display_name: String = "Player"
var goalkeeper_dive_time: float = 0.0
var goalkeeper_dive_cooldown: float = 0.0
var goalkeeper_dive_direction: Vector3 = Vector3.ZERO
var bicycle_animation_time: float = 0.0
var bicycle_cooldown: float = 0.0
var kick_animation_time: float = 0.0
var ball_control_animation_time: float = 0.0
var last_ball_control_input_msec: int = -1000000
var ball_control_was_down: bool = false
var kick_mouse_history: Array = []
var peer_id := 1
var team_id := 0
var is_local_player := false
var game_world

var gravity := 18.0
var camera_yaw := 0.0
var camera_pitch := -0.22
var camera_rig: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D

var visual_root: Node3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var player_label: Label3D
var team_color := Color("29a4ff")

var target_position := Vector3.ZERO
var target_yaw := 0.0
var target_velocity := Vector3.ZERO
var network_send_timer := 0.0
var network_snapshot_age := 0.0
var has_network_snapshot := false

var kick_charging := false
var kick_charge_time := 0.0
var tackle_time := 0.0
var tackle_cooldown := 0.0
var animation_time := 0.0


func configure(
	id: int,
	team: int,
	local_control: bool,
	world: Node,
	spawn_yaw: float,
	nickname: String
) -> void:
	peer_id = id
	team_id = team
	is_local_player = local_control
	game_world = world
	display_name = nickname
	team_color = Color("29a4ff") if team_id == 0 else Color("ff4e5d")
	camera_yaw = spawn_yaw
	target_yaw = spawn_yaw
	rotation.y = spawn_yaw


func _ready() -> void:
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	_build_collision()
	_build_visuals()
	if is_local_player:
		ControlSettingsScript.initialize()
		_build_camera()
		set_process_input(true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		set_process_input(false)
	target_position = global_position
	add_to_group("players")


func _build_collision() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	safe_margin = 0.06

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()

	capsule.radius = 0.43
	capsule.height = 1.72

	collider.shape = capsule
	collider.position.y = 0.88
	add_child(collider)


func _build_visuals() -> void:
	visual_root = Node3D.new()
	visual_root.name = "Visuals"
	add_child(visual_root)

	var jersey := MeshInstance3D.new()
	var jersey_mesh := CapsuleMesh.new()
	jersey_mesh.radius = 0.43
	jersey_mesh.height = 1.10
	jersey.mesh = jersey_mesh
	jersey.position.y = 1.20
	jersey.material_override = _material(team_color, 0.62)
	visual_root.add_child(jersey)

	var chest_band := MeshInstance3D.new()
	var chest_mesh := CylinderMesh.new()
	chest_mesh.top_radius = 0.445
	chest_mesh.bottom_radius = 0.445
	chest_mesh.height = 0.14
	chest_band.mesh = chest_mesh
	chest_band.position.y = 1.35
	chest_band.material_override = _material(Color.WHITE, 0.58)
	visual_root.add_child(chest_band)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.28
	head_mesh.height = 0.56
	head.mesh = head_mesh
	head.position.y = 2.02
	head.material_override = _material(Color("d9a27d"), 0.72)
	visual_root.add_child(head)

	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.285
	hair_mesh.height = 0.26
	hair.mesh = hair_mesh
	hair.position.y = 2.17
	hair.material_override = _material(Color("25212a"), 0.85)
	visual_root.add_child(hair)

	left_leg = _make_leg(-0.18)
	right_leg = _make_leg(0.18)
	visual_root.add_child(left_leg)
	visual_root.add_child(right_leg)

	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring.visible = false
	ring_mesh.top_radius = 0.68
	ring_mesh.bottom_radius = 0.68
	ring_mesh.height = 0.025
	ring.mesh = ring_mesh
	ring.position.y = 0.025
	ring.material_override = _material(team_color.lightened(0.2), 0.45, true)
	visual_root.add_child(ring)

	player_label = Label3D.new()
	player_label.text = ("YOU • " if is_local_player else "") + display_name
	player_label.modulate = team_color.lightened(0.35)
	player_label.position = Vector3(0, 2.55, 0)
	player_label.font_size = 34
	player_label.outline_size = 8
	player_label.modulate = Color.WHITE
	player_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	visual_root.add_child(player_label)

func set_display_name(value: String) -> void:
	display_name = value

	if player_label != null:
		player_label.text = (
			("YOU • " if is_local_player else "")
			+ display_name
		)

func _make_leg(x_offset: float) -> MeshInstance3D:
	var leg := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.66, 0.24)
	leg.mesh = mesh
	leg.position = Vector3(x_offset, 0.45, 0)
	leg.material_override = _material(Color("18243a"), 0.78)
	return leg

func start_kick_animation() -> void:
	ball_control_animation_time = 0.0
	kick_animation_time = KICK_ANIMATION_DURATION


func start_ball_control_animation() -> void:
	if kick_animation_time <= 0.0:
		ball_control_animation_time = BALL_CONTROL_ANIMATION_DURATION

func _material(color: Color, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color * 0.45
	return material


func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.top_level = true

	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = 6.7
	spring_arm.margin = 0.20
	spring_arm.collision_mask = 1
	camera_rig.add_child(spring_arm)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.fov = 72.0
	camera.current = true
	spring_arm.add_child(camera)
	spring_arm.add_excluded_object(get_rid())

func _record_kick_mouse_motion(mouse_delta: Vector2) -> void:
	var sample: Dictionary = {
		"time": Time.get_ticks_msec(),
		"motion": mouse_delta
	}

	kick_mouse_history.append(sample)
	_trim_kick_mouse_history()


func _trim_kick_mouse_history() -> void:
	var cutoff_time: int = (
		Time.get_ticks_msec() - KICK_GESTURE_WINDOW_MS
	)

	while kick_mouse_history.size() > 0:
		var oldest: Dictionary = kick_mouse_history[0]

		if int(oldest["time"]) >= cutoff_time:
			break

		kick_mouse_history.pop_front()


func _analyze_kick_mouse_gesture() -> Dictionary:
	_trim_kick_mouse_history()

	var net_motion: Vector2 = Vector2.ZERO
	var previous_direction: Vector2 = Vector2.ZERO
	var total_travel: float = 0.0
	var reversals: int = 0

	for i in range(kick_mouse_history.size()):
		var sample: Dictionary = kick_mouse_history[i]
		var mouse_delta: Vector2 = sample["motion"]
		var distance: float = mouse_delta.length()

		net_motion += mouse_delta
		total_travel += distance

		if distance >= GESTURE_STEP_PIXELS:
			var current_direction: Vector2 = mouse_delta / distance

			if (
				previous_direction.length_squared() > 0.0
				and previous_direction.dot(current_direction) < -0.25
			):
				reversals += 1

			previous_direction = current_direction

	var cancellation: float = 0.0

	if total_travel > 0.0:
		cancellation = 1.0 - clampf(
			net_motion.length() / total_travel,
			0.0,
			1.0
		)

	var is_knuckle: bool = (
		total_travel >= KNUCKLE_MIN_TRAVEL_PIXELS
		and reversals >= KNUCKLE_MIN_REVERSALS
		and cancellation >= 0.55
	)

	var curve: float = 0.0
	var horizontal_motion: float = net_motion.x

	if (
		not is_knuckle
		and absf(horizontal_motion) > CURVE_DEADZONE_PIXELS
	):
		var curve_size: float = clampf(
			(
				absf(horizontal_motion)
				- CURVE_DEADZONE_PIXELS
			) / (
				CURVE_FULL_SWIPE_PIXELS
				- CURVE_DEADZONE_PIXELS
			),
			0.0,
			1.0
		)

		curve = curve_size if horizontal_motion > 0.0 else -curve_size

	return {
		"curve": curve,
		"knuckle": is_knuckle
	}

func _input(event: InputEvent) -> void:
	if not is_local_player:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	# Keep the Windows Ctrl fallback only while Ctrl is the player's current
	# control-ball binding. Remapping the action removes this fallback too.
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var is_control_key: bool = (
			key_event.keycode == KEY_CTRL
			or key_event.physical_keycode == KEY_CTRL
			or key_event.key_label == KEY_CTRL
		)

		if (
			is_control_key
			and ControlSettingsScript.action_has_key(
				&"control_ball",
				KEY_CTRL
			)
			and key_event.pressed
			and not key_event.echo
		):
			_trigger_ball_control_input()
			return

	# Same rule for the default L1/LB controller binding.
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton

		if (
			button_event.button_index == JOY_BUTTON_LEFT_SHOULDER
			and ControlSettingsScript.action_has_joy_button(
				&"control_ball",
				JOY_BUTTON_LEFT_SHOULDER
			)
			and button_event.pressed
		):
			_trigger_ball_control_input()
			return

	if event is InputEventMouseMotion:
		var mouse_delta: Vector2 = event.relative
		var mouse_scale: float = (
			ControlSettingsScript.mouse_sensitivity_scale
		)
		var vertical_sign: float = (
			1.0 if ControlSettingsScript.invert_vertical else -1.0
		)

		camera_yaw = wrapf(
			camera_yaw
			- mouse_delta.x
			* MOUSE_SENSITIVITY
			* mouse_scale,
			-PI,
			PI
		)

		camera_pitch = clampf(
			camera_pitch
			+ mouse_delta.y
			* MOUSE_SENSITIVITY
			* mouse_scale
			* vertical_sign,
			-0.82,
			0.34
		)

		if kick_charging:
			_record_kick_mouse_motion(mouse_delta)

func _physics_process(delta: float) -> void:
	tackle_cooldown = maxf(0.0, tackle_cooldown - delta)
	bicycle_cooldown = maxf(
		0.0,
		bicycle_cooldown - delta
	)
	goalkeeper_dive_time = maxf(
		0.0,
		goalkeeper_dive_time - delta
	)

	goalkeeper_dive_cooldown = maxf(
		0.0,
		goalkeeper_dive_cooldown - delta
	)
	if is_local_player:
		_update_controller_look(delta)
		if game_world != null and game_world.can_local_player_move():
			_simulate_local_movement(delta)
			_process_actions(delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, GROUND_ACCELERATION * delta)
			velocity.z = move_toward(velocity.z, 0.0, GROUND_ACCELERATION * delta)
			if not is_on_floor():
				velocity.y -= gravity * delta
			move_and_slide()
			_cancel_charge()
		_send_network_state(delta)
	else:
		_interpolate_remote(delta)

	_update_camera()
	_update_visual_animation(delta)

func _simulate_goalkeeper_dive(delta: float) -> void:
	velocity.x = (
		goalkeeper_dive_direction.x
		* GOALKEEPER_DIVE_SPEED
	)

	velocity.z = (
		goalkeeper_dive_direction.z
		* GOALKEEPER_DIVE_SPEED
	)

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

	global_position.x = clampf(
		global_position.x, -14.55, 14.55
	)

	global_position.z = clampf(
		global_position.z, -25.0, 25.0
	)

func _simulate_local_movement(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var camera_basis := Basis(Vector3.UP, camera_yaw)
	var forward := -camera_basis.z
	var right := camera_basis.x
	var desired_direction := (right * input_vector.x + forward * -input_vector.y)
	desired_direction.y = 0.0
	if goalkeeper_dive_time > 0.0:
		_simulate_goalkeeper_dive(delta)
		return
	if desired_direction.length_squared() > 1.0:
		desired_direction = desired_direction.normalized()

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var acceleration := GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	var desired_velocity := desired_direction * speed

	if tackle_time > 0.0:
		tackle_time -= delta
		var tackle_forward := -global_transform.basis.z
		desired_velocity = tackle_forward * 13.5

	velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not Input.is_action_pressed("bicycle_modifier"):
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = -0.4
	else:
		velocity.y -= gravity * delta

	if desired_direction.length_squared() > 0.04:
		var desired_yaw := atan2(-desired_direction.x, -desired_direction.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, TURN_SPEED * delta))

	move_and_slide()
	global_position.x = clampf(global_position.x, -14.55, 14.55)
	global_position.z = clampf(global_position.z, -25.0, 25.0)

func _attempt_goalkeeper_dive(side: float) -> void:
	var camera_basis: Basis = Basis(
		Vector3.UP,
		camera_yaw
	)

	var direction: Vector3 = camera_basis.x

	if side < 0.0:
		direction = -direction

	direction.y = 0.0
	direction = direction.normalized()

	goalkeeper_dive_cooldown = 0.85
	start_goalkeeper_dive_animation(direction)

	velocity = direction * GOALKEEPER_DIVE_SPEED
	velocity.y = 3.3

	_cancel_charge()

	game_world.request_goalkeeper_dive(
		peer_id,
		direction
	)


func start_goalkeeper_dive_animation(
	direction: Vector3
) -> void:
	goalkeeper_dive_direction = direction.normalized()
	goalkeeper_dive_time = GOALKEEPER_DIVE_DURATION

func _process_actions(delta: float) -> void:
	# Polling makes Ctrl/L1 work even if Windows or a controller driver does not
	# emit the expected InputMap event. Trigger only on the down edge.
	var ball_control_down: bool = _is_ball_control_button_down()

	if ball_control_down and not ball_control_was_down:
		_trigger_ball_control_input()

	ball_control_was_down = ball_control_down

	if Input.is_action_just_pressed("kick"):
		kick_charging = true
		kick_charge_time = 0.0
		kick_mouse_history.clear()
	if (Input.is_action_just_pressed("juggle")):
		_attempt_juggle()
	if Input.is_action_just_pressed("control_ball"):
		_trigger_ball_control_input()
	if Input.is_action_just_pressed("test_goalkeeper_shot"):
		game_world.debug_goalkeeper_shot(peer_id)
	if (
		BICYCLE_KICK_ENABLED
		and Input.is_action_pressed("bicycle_modifier")
		and Input.is_action_just_pressed("jump")
		and bicycle_cooldown <= 0.0
	):
		_attempt_bicycle_kick()
	if kick_charging and Input.is_action_pressed("kick"):
		kick_charge_time = minf(
			MAX_KICK_CHARGE_TIME,
			kick_charge_time + delta
		)

		var charge_ratio: float = (
			kick_charge_time / MAX_KICK_CHARGE_TIME
		)

		if game_world != null:
			game_world.update_kick_charge(charge_ratio)

		# Face the direction in which the camera is looking.
		rotation.y = lerp_angle(
			rotation.y,
			camera_yaw,
			minf(1.0, 16.0 * delta)
		)

	if kick_charging and Input.is_action_just_released("kick"):
		_release_power_kick()

	# Tackling only moves the player. Ball movement comes from physical touch.
	if (
		Input.is_action_just_pressed("tackle")
		and is_on_floor()
	):
		var dive_side: float = Input.get_axis(
			"move_left",
			"move_right"
		)

		var can_dive: bool = (
			game_world != null
			and game_world.can_player_goalkeeper_dive(peer_id)
		)

		if (
			absf(dive_side) > 0.1
			and can_dive
			and goalkeeper_dive_cooldown <= 0.0
		):
			_attempt_goalkeeper_dive(dive_side)

		elif tackle_cooldown <= 0.0:
			tackle_time = 0.34
			tackle_cooldown = 1.65


func _release_power_kick() -> void:
	var charge: float = clampf(
		kick_charge_time / MAX_KICK_CHARGE_TIME,
		0.0,
		1.0
	)

	var power: float
	var lift: float

	if charge < 0.18:
		# Gentle touch: 0.5–3.2 power
		var touch_ratio: float = charge / 0.18
		touch_ratio = pow(touch_ratio, 1.4)

		power = lerpf(0.5, 3.2, touch_ratio)
		lift = lerpf(0.005, 0.015, touch_ratio)

	elif charge <= 0.50:
		# Pass: 3.2–8.0 power
		var pass_ratio: float = (
			(charge - 0.18) / 0.32
		)
		pass_ratio = pow(pass_ratio, 1.15)

		power = lerpf(3.2, 8.0, pass_ratio)
		lift = lerpf(0.015, 0.055, pass_ratio)

	else:
		# Above half bar: powerful shot range
		var shot_ratio: float = (
			(charge - 0.50) / 0.50
		)

		# Below 1.0 makes power rise quickly
		shot_ratio = pow(shot_ratio, 0.45)

		power = lerpf(15.0, 26.0, shot_ratio)
		lift = lerpf(0.10, 0.34, shot_ratio)

	var gesture: Dictionary = _analyze_kick_mouse_gesture()
	var curve: float = float(gesture["curve"])
	var knuckle: bool = bool(gesture["knuckle"])

	_kick_ball(power, lift, curve, knuckle)
	_cancel_charge()

func _kick_ball(
	power: float,
	lift: float,
	curve: float = 0.0,
	knuckle: bool = false
) -> void:
	if game_world == null:
		return

	start_kick_animation()
	var camera_basis: Basis = Basis(Vector3.UP, camera_yaw)
	var direction: Vector3 = -camera_basis.z
	direction.y = 0.0
	direction = direction.normalized()

	game_world.request_player_kick(
		peer_id,
		direction,
		power,
		lift,
		curve,
		knuckle
	)

func _get_aim_direction() -> Vector3:
	var camera_basis: Basis = Basis(Vector3.UP, camera_yaw)
	var direction: Vector3 = -camera_basis.z
	direction.y = 0.0
	return direction.normalized()


func _attempt_juggle() -> void:
	if game_world == null:
		return
	if not game_world.can_player_juggle(peer_id):
		return

	start_kick_animation()

	game_world.request_player_juggle(
		peer_id,
		_get_juggle_direction()
	)


func _attempt_ball_control() -> void:
	if game_world == null:
		return

	start_ball_control_animation()
	game_world.request_player_ball_control(peer_id)


func _trigger_ball_control_input() -> void:
	var now: int = Time.get_ticks_msec()

	# The direct event and InputMap fallback may both fire for one press.
	if now - last_ball_control_input_msec < 80:
		return

	last_ball_control_input_msec = now
	_attempt_ball_control()


func _is_ball_control_button_down() -> bool:
	if Input.is_action_pressed("control_ball"):
		return true

	if ControlSettingsScript.action_has_key(
		&"control_ball",
		KEY_CTRL
	):
		if (
			Input.is_key_pressed(KEY_CTRL)
			or Input.is_physical_key_pressed(KEY_CTRL)
		):
			return true

	if ControlSettingsScript.action_has_joy_button(
		&"control_ball",
		JOY_BUTTON_LEFT_SHOULDER
	):
		for device_id in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(
				device_id,
				JOY_BUTTON_LEFT_SHOULDER
			):
				return true

	return false

func _get_juggle_direction() -> Vector3:
	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	if input_vector.length_squared() < 0.01:
		return Vector3.ZERO

	var camera_forward: Vector3 = -Basis(
		Vector3.UP,
		camera_yaw
	).z

	var camera_right: Vector3 = Basis(
		Vector3.UP,
		camera_yaw
	).x

	var direction: Vector3 = (
		camera_right * input_vector.x
		+ camera_forward * -input_vector.y
	)

	direction.y = 0.0
	return direction.normalized()

func _attempt_bicycle_kick() -> void:
	if game_world == null:
		return
	if not game_world.can_player_bicycle(peer_id):
		return

	bicycle_cooldown = 1.0
	bicycle_animation_time = BICYCLE_ANIMATION_DURATION
	kick_animation_time = 0.0

	var direction: Vector3 = _get_aim_direction()

	# Lift and move backward during the bicycle kick.
	velocity.y = maxf(velocity.y, 4.8)
	velocity -= direction * 2.0

	game_world.request_player_bicycle(
		peer_id,
		direction
	)

func start_bicycle_animation() -> void:
	bicycle_animation_time = BICYCLE_ANIMATION_DURATION
	kick_animation_time = 0.0

func _cancel_charge() -> void:
	kick_charging = false
	kick_charge_time = 0.0
	if game_world != null:
		game_world.update_kick_charge(0.0)
	kick_mouse_history.clear()


func _update_controller_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var look: Vector2 = Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)

	if look.length_squared() <= 0.0001:
		return

	var controller_scale: float = (
		ControlSettingsScript.controller_sensitivity_scale
	)
	var vertical_sign: float = (
		1.0 if ControlSettingsScript.invert_vertical else -1.0
	)

	camera_yaw = wrapf(
		camera_yaw
		- look.x
		* CONTROLLER_YAW_SPEED
		* controller_scale
		* delta,
		-PI,
		PI
	)

	camera_pitch = clampf(
		camera_pitch
		+ look.y
		* CONTROLLER_PITCH_SPEED
		* controller_scale
		* vertical_sign
		* delta,
		-0.82,
		0.34
	)

	# Feed right-stick movement into the same recent-motion window used by
	# mouse swipes. This gives controllers identical curve and knuckle rules.
	if kick_charging:
		var gesture_motion: Vector2 = (
			look
			* CONTROLLER_GESTURE_PIXELS_PER_SECOND
			* delta
		)

		_record_kick_mouse_motion(gesture_motion)


func _update_camera() -> void:
	if camera_rig == null:
		return
	var focus := global_position + Vector3(0, 1.45, 0)
	camera_rig.global_position = camera_rig.global_position.lerp(focus, 0.34)
	camera_rig.rotation = Vector3(camera_pitch, camera_yaw, 0)


func _send_network_state(delta: float) -> void:
	if not NetworkManager.is_online() or NetworkManager.is_server_authority():
		return
	network_send_timer += delta
	if network_send_timer < NETWORK_SEND_INTERVAL:
		return
	network_send_timer -= NETWORK_SEND_INTERVAL
	if game_world != null:
		game_world.submit_local_player_state(global_position, rotation.y, velocity)


func receive_network_state(position_value: Vector3, yaw: float, velocity_value: Vector3) -> void:
	target_position = position_value
	target_yaw = yaw
	target_velocity = velocity_value
	network_snapshot_age = 0.0
	has_network_snapshot = true
	if is_local_player:
		var error := global_position.distance_to(position_value)
		if error > 3.5:
			global_position = position_value
			velocity = velocity_value


func force_network_state(position_value: Vector3, yaw: float, velocity_value: Vector3) -> void:
	global_position = position_value
	rotation.y = yaw
	velocity = velocity_value
	target_position = position_value
	target_yaw = yaw
	target_velocity = velocity_value
	network_snapshot_age = 0.0
	has_network_snapshot = true


func _interpolate_remote(delta: float) -> void:
	if not has_network_snapshot:
		return

	network_snapshot_age = minf(
		network_snapshot_age + delta,
		NETWORK_MAX_EXTRAPOLATION
	)

	var latency_peer_id: int = peer_id

	if NetworkManager.mode == NetworkManager.SessionMode.CLIENT:
		latency_peer_id = 1

	var latency_lead: float = NetworkManager.one_way_latency_seconds(
		latency_peer_id
	)
	var prediction_time: float = minf(
		latency_lead + network_snapshot_age,
		NETWORK_MAX_EXTRAPOLATION
	)
	var predicted_position: Vector3 = (
		target_position + target_velocity * prediction_time
	)
	var position_error: float = global_position.distance_to(
		predicted_position
	)

	if position_error > 2.0:
		global_position = predicted_position
	else:
		var position_weight: float = (
			1.0 - exp(-NETWORK_POSITION_RESPONSE * delta)
		)
		global_position = global_position.lerp(
			predicted_position,
			position_weight
		)

	var rotation_weight: float = (
		1.0 - exp(-NETWORK_ROTATION_RESPONSE * delta)
	)
	rotation.y = lerp_angle(
		rotation.y,
		target_yaw,
		rotation_weight
	)
	velocity = target_velocity


func reset_player(position_value: Vector3, yaw: float) -> void:
	force_network_state(position_value, yaw, Vector3.ZERO)
	ball_control_animation_time = 0.0
	if is_local_player:
		camera_yaw = yaw


func _update_visual_animation(delta: float) -> void:
	if visual_root == null:
		return

	var horizontal_speed: float = Vector2(
		velocity.x,
		velocity.z
	).length()

	animation_time += delta * (
		3.0 + horizontal_speed * 1.35
	)

	var stride: float = sin(animation_time) * minf(
		0.62,
		horizontal_speed * 0.065
	)

	# Default running animation
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride

	left_leg.position.z = 0.0
	right_leg.position.z = 0.0

	visual_root.position.y = (
		absf(sin(animation_time * 0.5))
		* minf(0.045, horizontal_speed * 0.005)
	)

	visual_root.rotation.z = lerpf(
		visual_root.rotation.z,
		-velocity.x * 0.006,
		minf(1.0, delta * 7.0)
	)

	visual_root.rotation.x = lerpf(
		visual_root.rotation.x,
		-velocity.z * 0.004,
		minf(1.0, delta * 7.0)
	)

	# Move the leg backward while charging
	if kick_charging and kick_animation_time <= 0.0:
		var charge_pose: float = clampf(
			kick_charge_time / MAX_KICK_CHARGE_TIME,
			0.0,
			1.0
		)

		right_leg.rotation.x = lerpf(
			right_leg.rotation.x,
			-0.72,
			charge_pose
		)

		visual_root.rotation.x = lerpf(
			visual_root.rotation.x,
			-0.10,
			charge_pose * 0.5
		)

	# Kick release animation
	if kick_animation_time > 0.0:
		kick_animation_time = maxf(
			0.0,
			kick_animation_time - delta
		)

		var progress: float = (
			1.0
			- kick_animation_time / KICK_ANIMATION_DURATION
		)

		var kick_angle: float

		if progress < 0.25:
			# Wind-up
			var windup: float = smoothstep(
				0.0,
				1.0,
				progress / 0.25
			)

			kick_angle = lerpf(-0.60, -1.05, windup)

		elif progress < 0.72:
			# Fast forward strike
			var strike: float = smoothstep(
				0.0,
				1.0,
				(progress - 0.25) / 0.47
			)

			kick_angle = lerpf(-1.05, 1.35, strike)

		else:
			# Return leg to normal
			var recovery: float = smoothstep(
				0.0,
				1.0,
				(progress - 0.72) / 0.28
			)

			kick_angle = lerpf(1.35, 0.0, recovery)

		right_leg.rotation.x = kick_angle

		var leg_extension: float = maxf(
			0.0,
			sin(
				((progress - 0.20) / 0.80) * PI
			)
		)

		right_leg.position.z = -leg_extension * 0.18

		var body_motion: float = sin(progress * PI)

		left_leg.rotation.x = lerpf(
			left_leg.rotation.x,
			-0.18,
			body_motion
		)

		visual_root.rotation.x = lerpf(
			visual_root.rotation.x,
			-0.22,
			body_motion
		)
		if bicycle_animation_time > 0.0:
			bicycle_animation_time = maxf(
				0.0,
				bicycle_animation_time - delta
			)

			var bicycle_progress: float = (
				1.0
				- bicycle_animation_time
				/ BICYCLE_ANIMATION_DURATION
			)

			var flip_progress: float = smoothstep(
				0.0,
				1.0,
				bicycle_progress
			)

			visual_root.rotation.x = -TAU * flip_progress

			visual_root.position.y = (
				sin(bicycle_progress * PI) * 1.45
			)

			var leg_motion: float = sin(
				bicycle_progress * PI
			)

			right_leg.rotation.x = lerpf(
				-0.8,
				1.15,
				leg_motion
			)

			left_leg.rotation.x = lerpf(
				0.4,
				-0.75,
				leg_motion
			)

			return

	# A short cushioning motion for the physical ball-control impulse.
	if ball_control_animation_time > 0.0 and kick_animation_time <= 0.0:
		ball_control_animation_time = maxf(
			0.0,
			ball_control_animation_time - delta
		)

		var control_progress: float = (
			1.0
			- ball_control_animation_time
			/ BALL_CONTROL_ANIMATION_DURATION
		)
		var cushion: float = sin(control_progress * PI)

		right_leg.rotation.x = lerpf(
			right_leg.rotation.x,
			0.48,
			cushion
		)
		right_leg.position.z = -0.12 * cushion
		visual_root.rotation.x = lerpf(
			visual_root.rotation.x,
			-0.08,
			cushion
		)

	if goalkeeper_dive_time > 0.0:
		var progress: float = (
			1.0
			- goalkeeper_dive_time
			/ GOALKEEPER_DIVE_DURATION
		)

		var local_side: float = goalkeeper_dive_direction.dot(
			global_transform.basis.x
		)

		var dive_motion: float = sin(progress * PI)

		visual_root.rotation.z = (
			-local_side * 1.35 * dive_motion
		)

		visual_root.position.y += dive_motion * 0.35

		left_leg.rotation.x = -0.45 * dive_motion
		right_leg.rotation.x = 0.65 * dive_motion

		return
	# Tackle has final animation priority
	if tackle_time > 0.0:
		visual_root.rotation.x = lerpf(
			visual_root.rotation.x,
			-0.65,
			minf(1.0, delta * 14.0)
		)
