extends Node3D

signal leave_requested

const PlayerScript = preload("res://scripts/player.gd")
const BallScript = preload("res://scripts/ball.gd")
const GoalScript = preload("res://scripts/goal.gd")
const HudScript = preload("res://scripts/hud.gd")

const FIELD_HALF_WIDTH := 15.0
const FIELD_HALF_LENGTH := 22.0
const GOAL_HALF_WIDTH := 4.0
const MATCH_DURATION := 180.0
const SNAPSHOT_INTERVAL := 1.0 / 60.0
const MATCH_SYNC_INTERVAL := 0.25
const DRIBBLE_CONTACT_DISTANCE := 1.0
const DRIBBLE_TOUCH_COOLDOWN_MS := 20
const DRIBBLE_STRENGTH := 0.34
const BALL_CONTROL_DISTANCE := 1.55
const BALL_CONTROL_MIN_HEIGHT := -0.25
const BALL_CONTROL_MAX_HEIGHT := 1.35
const BALL_CONTROL_COOLDOWN_MS := 250
const BALL_CONTROL_KICK_PRIORITY_MS := 250
const BALL_CONTROL_PLAYER_VELOCITY_SHARE := 0.25
const BALL_CONTROL_DAMPING := 1.5
const BALL_CONTROL_VERTICAL_DAMPING := 1
const BALL_CONTROL_MAX_SPEED_CHANGE := 25
const BALL_CONTROL_MAX_VERTICAL_CHANGE := 1.25
const BODY_BLOCK_RESTITUTION := 0.32
const BODY_BLOCK_TELEPORT_DISTANCE := 3.0
const BODY_BLOCK_PUSH_OUT := 0.025
const REPLAY_SAMPLE_INTERVAL := 1.0 / 60.0
const REPLAY_MAX_SAMPLES := 270
const REPLAY_PLAYBACK_SPEED := 0.82
const TEAM_AUTO: int = -1
const TEAM_BLUE: int = 0
const TEAM_RED: int = 1
const MAX_TEAM_PLAYERS: int = 3
const MAX_PLAYERS: int = 6

var local_nickname: String = "Player"
var player_nicknames: Dictionary = {}
var lobby_teams: Dictionary = {}
var player_slots: Dictionary = {}
var local_lobby_registered := false
var team_selection_active := false
var match_started := false
var client_join_retry_timer := 0.0
var replay_camera: Camera3D
var replay_buffer: Array = []
var replay_frames: Array = []
var replay_sample_timer := 0.0
var replay_elapsed := 0.0
var replay_active := false
var replay_goal_sign := 1.0
var replay_camera_anchor := Vector3.ZERO
var last_dribble_touch_msec: Dictionary = {}
var players: Dictionary = {}
var active_goalkeeper_dives: Dictionary = {}
var last_goalkeeper_dive_msec: Dictionary = {}
var ball
var hud
var spectator_camera: Camera3D

var blue_score := 0
var red_score := 0
var match_time := MATCH_DURATION
var round_active := false
var match_over := false
var waiting_for_opponent := false
var round_reset_timer := -1.0
var snapshot_timer := 0.0
var match_sync_timer := 0.0
var pause_open := false
var last_kick_msec: Dictionary = {}
var last_ball_control_msec: Dictionary = {}
var last_authority_kick_msec: int = -1000000
var ready_peers: Dictionary = {}
var last_juggle_msec: Dictionary = {}
var previous_authority_ball_position := Vector3.ZERO
var ball_sweep_ready := false
var world_snapshot_sequence := 0
var last_world_snapshot_sequence := -1

func _ready() -> void:
	local_nickname = _sanitize_nickname(local_nickname)
	_build_environment()
	_build_arena()
	_build_spectator_camera()
	_build_replay_camera()
	_spawn_ball()
	_build_goals()
	_build_hud()
	_connect_network_signals()

	if NetworkManager.is_server_authority():
		if NetworkManager.mode == NetworkManager.SessionMode.OFFLINE:
			player_nicknames[1] = local_nickname
			lobby_teams[1] = TEAM_BLUE
			ready_peers[1] = true
			local_lobby_registered = true
			_spawn_player_local(1, TEAM_BLUE, local_nickname)
			match_started = true
			round_active = true
			waiting_for_opponent = false
			hud.set_status("TRAINING • Attack the red goal")
			hud.show_message("TRAINING KICKOFF", 1.8)
		elif NetworkManager.mode == NetworkManager.SessionMode.HOST:
			player_nicknames[1] = local_nickname
			lobby_teams[1] = TEAM_AUTO
			ready_peers[1] = true
			local_lobby_registered = true
			match_started = false
			waiting_for_opponent = true
			round_active = false
			hud.set_status(
				"HOST • Select a team • UDP %d"
				% NetworkManager.active_port
			)
			_broadcast_lobby_state()
		else:
			match_started = false
			waiting_for_opponent = true
			round_active = false
			hud.set_status(
				"DEDICATED SERVER • Waiting for players • UDP %d"
				% NetworkManager.active_port
			)
	else:
		match_started = false
		waiting_for_opponent = true
		round_active = false
		hud.set_status("CLIENT • Connecting...")
		var peer := multiplayer.multiplayer_peer
		if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			call_deferred("_announce_client_ready")

	hud.set_match_state(blue_score, red_score, match_time)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _team_player_count(team: int) -> int:
	var count: int = 0

	for team_value in lobby_teams.values():
		if int(team_value) == team:
			count += 1

	return count

func _sanitize_nickname(value: String) -> String:
	var clean_name: String = value.strip_edges()
	clean_name = clean_name.replace("\n", " ")
	clean_name = clean_name.replace("\r", " ")
	clean_name = clean_name.replace("\t", " ")

	while clean_name.contains("  "):
		clean_name = clean_name.replace("  ", " ")

	if clean_name.is_empty():
		clean_name = "Player"

	return clean_name.left(18)

func _resolve_team_request(player_id: int, requested_team: int) -> int:
	var current_team: int = int(
		lobby_teams.get(player_id, TEAM_AUTO)
	)
	var blue_count: int = _team_player_count(TEAM_BLUE)
	var red_count: int = _team_player_count(TEAM_RED)

	# Do not count the requesting player's old slot while evaluating a switch.
	if current_team == TEAM_BLUE:
		blue_count -= 1
	elif current_team == TEAM_RED:
		red_count -= 1

	if requested_team == TEAM_BLUE:
		if blue_count < MAX_TEAM_PLAYERS:
			return TEAM_BLUE
		return TEAM_AUTO

	if requested_team == TEAM_RED:
		if red_count < MAX_TEAM_PLAYERS:
			return TEAM_RED
		return TEAM_AUTO

	if requested_team != TEAM_AUTO:
		return TEAM_AUTO

	var blue_has_space: bool = blue_count < MAX_TEAM_PLAYERS
	var red_has_space: bool = red_count < MAX_TEAM_PLAYERS

	if not blue_has_space and not red_has_space:
		return TEAM_AUTO
	if not blue_has_space:
		return TEAM_RED
	if not red_has_space:
		return TEAM_BLUE

	return TEAM_BLUE if blue_count <= red_count else TEAM_RED


func _next_team_slot(team: int) -> int:
	var used_slots: Dictionary = {}

	for id in player_slots.keys():
		if players.has(id) and players[id].team_id == team:
			used_slots[int(player_slots[id])] = true

	for slot in range(MAX_TEAM_PLAYERS):
		if not used_slots.has(slot):
			return slot

	return MAX_TEAM_PLAYERS - 1

func _connect_network_signals() -> void:
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.peer_left.connect(_on_peer_left)

func _build_replay_camera() -> void:
	replay_camera = Camera3D.new()
	replay_camera.name = "ReplayCamera"
	replay_camera.fov = 100.0
	add_child(replay_camera)

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("5d96bd")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7ecff")
	environment.ambient_light_energy = 0.74
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("fff2d2")
	sun.light_energy = 1.18
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _build_spectator_camera() -> void:
	spectator_camera = Camera3D.new()
	spectator_camera.name = "SpectatorCamera"
	spectator_camera.position = Vector3(0, 24, 29)
	spectator_camera.fov = 66.0
	spectator_camera.current = true
	add_child(spectator_camera)
	spectator_camera.look_at(Vector3(0, 0, 0), Vector3.UP)


func _build_arena() -> void:
	# Playing surface and alternating mowing stripes.
	_create_box("PitchBase", Vector3(0, -0.22, 0), Vector3(30.6, 0.44, 45.0), Color("176b43"), true)
	for stripe_index in range(10):
		var stripe_z := -19.8 + stripe_index * 4.4
		var stripe_color := Color("218152") if stripe_index % 2 == 0 else Color("1d774b")
		_create_box("GrassStripe_%d" % stripe_index, Vector3(0, 0.008, stripe_z), Vector3(29.8, 0.018, 4.38), stripe_color, false)

	var line_color := Color("e9f3eb")
	_create_box("LeftTouchline", Vector3(-FIELD_HALF_WIDTH, 0.035, 0), Vector3(0.10, 0.025, 44.0), line_color, false)
	_create_box("RightTouchline", Vector3(FIELD_HALF_WIDTH, 0.035, 0), Vector3(0.10, 0.025, 44.0), line_color, false)
	_create_box("NorthGoalLine", Vector3(0, 0.035, -FIELD_HALF_LENGTH), Vector3(30.0, 0.025, 0.10), line_color, false)
	_create_box("SouthGoalLine", Vector3(0, 0.035, FIELD_HALF_LENGTH), Vector3(30.0, 0.025, 0.10), line_color, false)
	_create_box("HalfwayLine", Vector3(0, 0.038, 0), Vector3(30.0, 0.026, 0.10), line_color, false)
	_create_circle_lines(5.0, line_color)
	_create_box("CenterSpot", Vector3(0, 0.045, 0), Vector3(0.30, 0.03, 0.30), line_color, false)
	_create_penalty_markings(-1.0, line_color)
	_create_penalty_markings(1.0, line_color)

	# Sideline boards. End boards are split so the goal mouth remains open.
	# Tall blue collision walls
	var board_color: Color = Color("202a33")
	var wall_height: float = 4.6
	var wall_y: float = wall_height * 0.5

	# Walls along both sidelines
	_create_box(
		"LeftBoard",
		Vector3(-15.55, wall_y, 0.0),
		Vector3(0.30, wall_height, 50.4),
		board_color,
		true
	)

	_create_box(
		"RightBoard",
		Vector3(15.55, wall_y, 0.0),
		Vector3(0.30, wall_height, 50.4),
		board_color,
		true
	)

	for side in [-1.0, 1.0]:
		var goal_line_z: float = float(side) * 22.45

		# Walls beside the goal openings
		_create_box(
			"EndBoardL_%s" % side,
			Vector3(-9.55, wall_y, goal_line_z),
			Vector3(11.0, wall_height, 0.30),
			board_color,
			true
		)

		_create_box(
			"EndBoardR_%s" % side,
			Vector3(9.55, wall_y, goal_line_z),
			Vector3(11.0, wall_height, 0.30),
			board_color,
			true
		)
		# Blue wall above the goal crossbar
		var above_goal_height: float = wall_height - 3.10

		_create_box(
			"AboveGoalWall_%s" % side,
			Vector3(
				0.0,
				3.10 + above_goal_height * 0.5,
				goal_line_z
			),
			Vector3(
				8.1,
				above_goal_height,
				0.30
			),
			board_color,
			true
		)
		# Full wall behind each goal
		var back_wall_z: float = float(side) * 25.05

		_create_box(
			"BackWall_%s" % side,
			Vector3(0.0, wall_y, back_wall_z),
			Vector3(31.4, wall_height, 0.30),
			board_color,
			true
		)
	# Low-poly stands give depth without external models.
	var stand_color := Color("253b50")
	_create_box("WestStand", Vector3(-20.0, 2.3, 0), Vector3(7.2, 4.6, 52.0), stand_color, false)
	_create_box("EastStand", Vector3(20.0, 2.3, 0), Vector3(7.2, 4.6, 52.0), stand_color, false)
	_create_box("NorthStand", Vector3(0, 2.0, -29.0), Vector3(33.0, 4.0, 7.0), stand_color.darkened(0.08), false)
	_create_box("SouthStand", Vector3(0, 2.0, 29.0), Vector3(33.0, 4.0, 7.0), stand_color.darkened(0.08), false)

	# Stadium light pylons.
	for x in [-18.0, 18.0]:
		for z in [-24.0, 24.0]:
			_create_box("Pylon", Vector3(x, 6.0, z), Vector3(0.28, 12.0, 0.28), Color("8190a0"), false)
			_create_box("Lamp", Vector3(x, 11.7, z), Vector3(2.5, 0.5, 0.8), Color("dcecff"), false, true)


func _create_circle_lines(radius: float, color: Color) -> void:
	var segments := 40
	for index in range(segments):
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var point_a := Vector3(cos(angle_a) * radius, 0.042, sin(angle_a) * radius)
		var point_b := Vector3(cos(angle_b) * radius, 0.042, sin(angle_b) * radius)
		var midpoint := (point_a + point_b) * 0.5
		var direction := point_b - point_a
		var segment := _create_box("CenterCircle", midpoint, Vector3(direction.length() + 0.03, 0.026, 0.10), color, false)
		segment.rotation.y = -atan2(direction.z, direction.x)


func _create_penalty_markings(side: float, color: Color) -> void:
	var end_z := side * FIELD_HALF_LENGTH
	var box_depth := 6.0
	var box_center_z := end_z - side * box_depth
	_create_box("PenaltySideL", Vector3(-7.0, 0.04, box_center_z), Vector3(0.10, 0.026, box_depth * 2.0), color, false)
	_create_box("PenaltySideR", Vector3(7.0, 0.04, box_center_z), Vector3(0.10, 0.026, box_depth * 2.0), color, false)
	_create_box("PenaltyTop", Vector3(0, 0.04, end_z - side * box_depth * 2.0), Vector3(14.0, 0.026, 0.10), color, false)
	_create_box("PenaltySpot", Vector3(0, 0.045, end_z - side * 7.5), Vector3(0.28, 0.03, 0.28), color, false)


func _spawn_ball() -> void:
	ball = BallScript.new()
	ball.name = "Ball"
	ball.configure(NetworkManager.is_server_authority())
	add_child(ball)
	ball.add_to_group("match_ball")
	ball.reset_ball(Vector3(0, 0.62, 0))
	_reset_ball_sweep()


func _build_goals() -> void:
	_create_goal(-1.0, 1) # Red scores in Blue's goal.
	_create_goal(1.0, 0)  # Blue scores in Red's goal.


func _create_goal(side: float, scoring_team: int) -> void:
	var line_z := side * FIELD_HALF_LENGTH
	var post_z := line_z + side * 0.15
	var goal_color := Color("f2f5f7")
	_create_box(
		"GoalFloor_%s" % side,
		Vector3(
			0.0,
			-0.22,
			line_z + side * 1.25
		),
		Vector3(8.4, 0.44, 2.5),
		Color("176b43"),
		true
	)
	_create_box("GoalPostL", Vector3(-GOAL_HALF_WIDTH, 1.5, post_z), Vector3(0.20, 3.0, 0.20), goal_color, true)
	_create_box("GoalPostR", Vector3(GOAL_HALF_WIDTH, 1.5, post_z), Vector3(0.20, 3.0, 0.20), goal_color, true)
	_create_box("GoalCrossbar", Vector3(0, 3.0, post_z), Vector3(8.2, 0.20, 0.20), goal_color, true)

	var net_z := line_z + side * 2.4
	var net_color: Color = (
		Color(0.14, 0.55, 1.0, 0.38)
		if scoring_team == TEAM_RED
		else Color(1.0, 0.18, 0.26, 0.38)
	)
	_create_box("GoalBack", Vector3(0, 1.5, net_z), Vector3(8.2, 3.0, 0.12), net_color, true)
	_create_box("GoalSideL", Vector3(-4.1, 1.5, line_z + side * 1.28), Vector3(0.12, 3.0, 2.5), net_color, true)
	_create_box("GoalSideR", Vector3(4.1, 1.5, line_z + side * 1.28), Vector3(0.12, 3.0, 2.5), net_color, true)
	_create_box("GoalRoof", Vector3(0, 3.05, line_z + side * 1.28), Vector3(8.2, 0.10, 2.5), net_color, true)

	# Decorative net strands.
	for index in range(-3, 4):
		_create_box("NetVertical", Vector3(index, 1.5, net_z - side * 0.04), Vector3(0.035, 2.8, 0.035), Color(1, 1, 1, 0.55), false)
	for height in [0.55, 1.2, 1.85, 2.5]:
		_create_box("NetHorizontal", Vector3(0, height, net_z - side * 0.04), Vector3(8.0, 0.035, 0.035), Color(1, 1, 1, 0.55), false)

	var goal := GoalScript.new()
	goal.name = "GoalArea_%s" % side
	goal.configure(
		scoring_team,
		Vector3(7.7, 2.75, 1.65),
		line_z,
		side,
		BallScript.RADIUS
	)
	goal.position = Vector3(0, 1.42, line_z + side * 1.10)
	goal.ball_scored.connect(_on_goal_scored)
	add_child(goal)

func can_player_goalkeeper_dive(id: int) -> bool:
	if not players.has(id):
		return false

	var player = players[id]
	var position: Vector3 = player.global_position

	if absf(position.x) > 7.0:
		return false

	# Blue/team 0 owns the north goal.
	if player.team_id == 0:
		return position.z >= -22.8 and position.z <= -10.0

	# Red/team 1 owns the south goal.
	return position.z >= 10.0 and position.z <= 22.8

func request_goalkeeper_dive(
	id: int,
	direction: Vector3
) -> void:
	if NetworkManager.is_server_authority():
		_perform_goalkeeper_dive(id, direction)
	else:
		request_goalkeeper_dive_remote.rpc_id(
			1,
			direction
		)


@rpc("any_peer", "call_remote", "reliable")
func request_goalkeeper_dive_remote(
	direction: Vector3
) -> void:
	if not multiplayer.is_server():
		return

	_perform_goalkeeper_dive(
		multiplayer.get_remote_sender_id(),
		direction
	)


func _perform_goalkeeper_dive(
	id: int,
	direction: Vector3
) -> void:
	if not can_player_goalkeeper_dive(id):
		return

	var now: int = Time.get_ticks_msec()
	var previous: int = int(
		last_goalkeeper_dive_msec.get(id, 0)
	)

	if now - previous < 900:
		return

	var safe_direction: Vector3 = Vector3(
		direction.x,
		0.0,
		direction.z
	).normalized()

	if safe_direction.length_squared() < 0.5:
		return

	last_goalkeeper_dive_msec[id] = now

	active_goalkeeper_dives[id] = {
		"direction": safe_direction,
		"expires": now + 560
	}

	_broadcast_goalkeeper_dive(id, safe_direction)


func _apply_goalkeeper_dives() -> void:
	var now: int = Time.get_ticks_msec()

	for id_value in active_goalkeeper_dives.keys():
		var id: int = int(id_value)
		var dive: Dictionary = active_goalkeeper_dives[id]

		if now > int(dive["expires"]):
			active_goalkeeper_dives.erase(id)
			continue

		if not players.has(id):
			active_goalkeeper_dives.erase(id)
			continue

		var player = players[id]
		var direction: Vector3 = dive["direction"]

		var segment_start: Vector3 = (
			player.global_position
			+ Vector3(0.0, 0.95, 0.0)
		)

		var segment_end: Vector3 = (
			segment_start + direction * 1.7
		)

		var segment: Vector3 = (
			segment_end - segment_start
		)

		var closest_amount: float = clampf(
			(
				ball.global_position - segment_start
			).dot(segment) / segment.length_squared(),
			0.0,
			1.0
		)

		var closest_point: Vector3 = (
			segment_start
			+ segment * closest_amount
		)

		if ball.global_position.distance_to(
			closest_point
		) <= 0.95:
			var goal_side: float = (
				-1.0 if player.team_id == 0 else 1.0
			)

			var away_from_goal: Vector3 = Vector3(
				0.0,
				0.24,
				-goal_side
			)

			var save_direction: Vector3 = (
				away_from_goal * 0.8
				+ direction * 0.35
			).normalized()

			ball.goalkeeper_save(save_direction)
			_broadcast_immediate_snapshot()
			active_goalkeeper_dives.erase(id)

func _create_box(node_name: String, position_value: Vector3, size: Vector3, color: Color, with_collision: bool, emission := false) -> Node3D:
	var root: Node3D
	if with_collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 2 | 4
		root = body
	else:
		root = Node3D.new()
	root.name = node_name
	root.position = position_value
	add_child(root)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color, emission)
	root.add_child(mesh_instance)

	if with_collision:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		root.add_child(collision)
	return root


func _material(color: Color, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission:
		material.emission_enabled = true
		material.emission = color * 0.65
	return material


func _build_hud() -> void:
	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.resume_requested.connect(_resume_game)
	hud.leave_requested.connect(_leave_game)
	hud.restart_requested.connect(_restart_requested)
	hud.team_requested.connect(_on_team_requested)


func _physics_process(delta: float) -> void:
	_retry_client_join(delta)

	if (
		Input.is_action_just_pressed("pause")
		and not match_over
		and not team_selection_active
	):
		_set_pause_open(not pause_open)

	# Every computer records and plays its own smooth replay.
	if replay_active:
		_update_goal_replay(delta)
	elif round_active:
		_record_replay(delta)

	if NetworkManager.is_server_authority():
		_authority_tick(delta)
	else:
		if round_active and not match_over:
			match_time = maxf(0.0, match_time - delta)

	hud.set_match_state(blue_score, red_score, match_time)


func _authority_tick(delta: float) -> void:
	var ball_is_out: bool = (
		ball.global_position.y < -2.0
		or absf(ball.global_position.x) > 17.0
		or absf(ball.global_position.z) > 26.0
	)

	if ball_is_out:
		var missing_position: Vector3 = ball.global_position
		var half_side: float = (
			-1.0 if missing_position.z < 0.0 else 1.0
		)

		var recovery_position: Vector3 = Vector3(
			0.0,
			0.62,
			half_side * 19.0
		)

		_reset_ball_only(recovery_position)
		return
	_apply_goalkeeper_dives()
	if round_active or waiting_for_opponent:
		_apply_player_ball_touches()
		_apply_player_body_blocks()
	if round_active and not match_over and not waiting_for_opponent:
		match_time = maxf(0.0, match_time - delta)
		if match_time <= 0.0:
			_finish_match()

	if round_reset_timer >= 0.0:
		round_reset_timer -= delta
		if round_reset_timer <= 0.0:
			round_reset_timer = -1.0
			_broadcast_round_reset()

	if NetworkManager.is_online():
		snapshot_timer += delta
		match_sync_timer += delta
		if snapshot_timer >= SNAPSHOT_INTERVAL:
			snapshot_timer -= SNAPSHOT_INTERVAL
			_broadcast_snapshots()
		if match_sync_timer >= MATCH_SYNC_INTERVAL:
			match_sync_timer = 0.0
			receive_match_state.rpc(blue_score, red_score, match_time, round_active, match_over)


func _retry_client_join(delta: float) -> void:
	if NetworkManager.mode != NetworkManager.SessionMode.CLIENT:
		return

	var peer = multiplayer.multiplayer_peer

	if (
		peer == null
		or peer.get_connection_status()
		!= MultiplayerPeer.CONNECTION_CONNECTED
	):
		return

	var local_id: int = NetworkManager.local_peer_id()

	if (
		local_id <= 1
		or local_lobby_registered
		or players.has(local_id)
	):
		return

	client_join_retry_timer -= delta

	if client_join_retry_timer <= 0.0:
		client_join_retry_timer = 1.0
		client_ready.rpc_id(1, local_nickname)

func _broadcast_goalkeeper_dive(
	id: int,
	direction: Vector3
) -> void:
	if players.has(id):
		var player = players[id]

		if not player.is_local_player:
			player.start_goalkeeper_dive_animation(
				direction
			)

	if NetworkManager.is_online():
		receive_goalkeeper_dive.rpc(id, direction)


@rpc("authority", "call_remote", "reliable")
func receive_goalkeeper_dive(
	id: int,
	direction: Vector3
) -> void:
	if players.has(id):
		var player = players[id]

		if not player.is_local_player:
			player.start_goalkeeper_dive_animation(
				direction
			)


func _reset_ball_sweep() -> void:
	if ball == null:
		ball_sweep_ready = false
		return

	previous_authority_ball_position = ball.global_position
	ball_sweep_ready = true


func _apply_player_body_blocks() -> void:
	if ball == null:
		return

	var current_position: Vector3 = ball.global_position

	if replay_active:
		previous_authority_ball_position = current_position
		ball_sweep_ready = true
		return

	if not ball_sweep_ready:
		previous_authority_ball_position = current_position
		ball_sweep_ready = true
		return

	var start_position: Vector3 = previous_authority_ball_position
	var ball_motion: Vector3 = current_position - start_position

	# Ignore resets and teleports. A real shot cannot cover this distance in one
	# physics frame because ball.gd already limits its maximum speed.
	if ball_motion.length() > BODY_BLOCK_TELEPORT_DISTANCE:
		previous_authority_ball_position = current_position
		return

	if ball_motion.length_squared() < 0.000001:
		previous_authority_ball_position = current_position
		return

	# These expanded spheres approximate only the torso and head. The lowest
	# sphere leaves enough space for a ground ball to pass between the legs.
	var body_offsets := PackedVector3Array([
		Vector3(0.0, 1.25, 0.0),
		Vector3(0.0, 1.60, 0.0),
		Vector3(0.0, 2.02, 0.0)
	])
	var body_radii := PackedFloat32Array([
		0.40,
		0.38,
		0.29
	])

	var earliest_time: float = 2.0
	var impact_normal: Vector3 = Vector3.ZERO
	var blocking_player_velocity: Vector3 = Vector3.ZERO
	var found_block: bool = false

	for id in players.keys():
		var player = players[id]

		for sphere_index in range(body_offsets.size()):
			var sphere_center: Vector3 = (
				player.global_position
				+ body_offsets[sphere_index]
			)
			var expanded_radius: float = (
				body_radii[sphere_index]
				+ BallScript.RADIUS
			)
			var hit: Dictionary = _segment_sphere_hit(
				start_position,
				current_position,
				sphere_center,
				expanded_radius
			)

			if hit.is_empty():
				continue

			var hit_time: float = float(hit["time"])
			var hit_normal: Vector3 = hit["normal"]
			var relative_velocity: Vector3 = (
				ball.linear_velocity - player.velocity
			)

			# Only block motion entering the body. This prevents repeated
			# reflections while the ball is already moving away.
			if relative_velocity.dot(hit_normal) >= -0.05:
				continue

			if hit_time < earliest_time:
				earliest_time = hit_time
				impact_normal = hit_normal
				blocking_player_velocity = player.velocity
				found_block = true

	if not found_block:
		previous_authority_ball_position = current_position
		return

	var impact_position: Vector3 = start_position.lerp(
		current_position,
		earliest_time
	)
	ball.global_position = (
		impact_position + impact_normal * BODY_BLOCK_PUSH_OUT
	)
	ball.sleeping = false

	var relative_impact_velocity: Vector3 = (
		ball.linear_velocity - blocking_player_velocity
	)
	var inward_speed: float = relative_impact_velocity.dot(
		impact_normal
	)
	var blocking_impulse: Vector3 = (
		impact_normal
		* -(1.0 + BODY_BLOCK_RESTITUTION)
		* inward_speed
		* ball.mass
	)
	ball.apply_central_impulse(blocking_impulse)

	previous_authority_ball_position = ball.global_position
	_broadcast_immediate_snapshot()


func _segment_sphere_hit(
	start_position: Vector3,
	end_position: Vector3,
	sphere_center: Vector3,
	radius: float
) -> Dictionary:
	var segment: Vector3 = end_position - start_position
	var segment_length_squared: float = segment.length_squared()

	if segment_length_squared < 0.000001:
		return {}

	var relative_start: Vector3 = start_position - sphere_center
	var radius_squared: float = radius * radius
	var c_value: float = (
		relative_start.length_squared() - radius_squared
	)

	if c_value <= 0.0:
		var inside_normal: Vector3 = relative_start.normalized()

		if inside_normal.length_squared() < 0.001:
			inside_normal = -segment.normalized()

		return {
			"time": 0.0,
			"normal": inside_normal
		}

	var b_value: float = 2.0 * relative_start.dot(segment)

	if b_value >= 0.0:
		return {}

	var discriminant: float = (
		b_value * b_value
		- 4.0 * segment_length_squared * c_value
	)

	if discriminant < 0.0:
		return {}

	var hit_time: float = (
		(-b_value - sqrt(discriminant))
		/ (2.0 * segment_length_squared)
	)

	if hit_time < 0.0 or hit_time > 1.0:
		return {}

	var hit_position: Vector3 = start_position + segment * hit_time
	var hit_normal: Vector3 = (
		hit_position - sphere_center
	).normalized()

	return {
		"time": hit_time,
		"normal": hit_normal
	}

func _apply_player_ball_touches() -> void:
	var now: int = Time.get_ticks_msec()

	for id in players.keys():

		var player = players[id]
		var offset: Vector3 = ball.global_position - player.global_position

		# Only allow normal ground-level touches.
		if absf(offset.y) > 1.2:
			continue

		offset.y = 0.0
		var distance: float = offset.length()

		if distance <= 0.001 or distance > DRIBBLE_CONTACT_DISTANCE:
			continue

		var previous: int = int(last_dribble_touch_msec.get(id, 0))
		if now - previous < DRIBBLE_TOUCH_COOLDOWN_MS:
			continue

		var contact_normal: Vector3 = offset / distance
		var player_velocity := Vector3(
			player.velocity.x,
			0.0,
			player.velocity.z
		)
		var ball_velocity := Vector3(
			ball.linear_velocity.x,
			0.0,
			ball.linear_velocity.z
		)

		var approach_speed: float = (
			player_velocity - ball_velocity
		).dot(contact_normal)

		if approach_speed <= 0.15:
			continue

		var push_direction := contact_normal

		if player_velocity.length_squared() > 0.04:
			push_direction = (
				contact_normal * 0.75
				+ player_velocity.normalized() * 0.25
			).normalized()

		var added_speed: float = clampf(
			approach_speed * DRIBBLE_STRENGTH,
			0.18,
			3.0
		)

		ball.sleeping = false
		ball.apply_central_impulse(
			push_direction * added_speed * ball.mass
		)

		last_dribble_touch_msec[id] = now

func can_local_player_move() -> bool:
	return (
		not replay_active
		and not pause_open
		and not team_selection_active
		and not match_over
		and (round_active or waiting_for_opponent)
	)

func _record_replay(delta: float) -> void:
	replay_sample_timer += delta
	if replay_sample_timer < REPLAY_SAMPLE_INTERVAL:
		return

	replay_sample_timer -= REPLAY_SAMPLE_INTERVAL

	var player_states: Dictionary = {}

	for id in players.keys():
		var player = players[id]

		var replay_state: Dictionary = {
			"position": player.global_position,
			"yaw": player.rotation.y
		}

		if player.visual_root != null:
			replay_state["visual_transform"] = player.visual_root.transform

		if player.left_leg != null:
			replay_state["left_leg_transform"] = player.left_leg.transform

		if player.right_leg != null:
			replay_state["right_leg_transform"] = player.right_leg.transform

		player_states[id] = replay_state
	replay_buffer.append({
		"ball_position": ball.global_position,
		"ball_rotation": ball.global_transform.basis.get_rotation_quaternion(),
		"players": player_states
	})

	while replay_buffer.size() > REPLAY_MAX_SAMPLES:
		replay_buffer.pop_front()


func _start_goal_replay(scoring_team: int) -> bool:
	if replay_buffer.size() < 2:
		return false

	replay_frames = replay_buffer.duplicate(true)
	replay_elapsed = 0.0
	replay_active = true

	var final_frame: Dictionary = replay_frames.back()
	var final_ball_position: Vector3 = final_frame["ball_position"]
	replay_goal_sign = 1.0 if final_ball_position.z >= 0.0 else -1.0
	replay_camera_anchor = Vector3(
		10.5,
		5.5,
		replay_goal_sign * 14.0
	)
	for id in players.keys():
		players[id].set_physics_process(false)

	ball.set_physics_process(false)
	ball.freeze = true

	_apply_replay_frame(replay_frames[0], replay_frames[0], 0.0)
	_update_replay_camera(1.0, true)
	replay_camera.current = true

	var goal_text := "BLUE GOAL!" if scoring_team == 0 else "RED GOAL!"
	var duration := (
		float(replay_frames.size() - 1)
		* REPLAY_SAMPLE_INTERVAL
		/ REPLAY_PLAYBACK_SPEED
	)

	hud.show_message("%s\nREPLAY" % goal_text, duration)
	return true


func _update_goal_replay(delta: float) -> void:
	if replay_frames.size() < 2:
		return

	replay_elapsed += delta

	var frame_position := (
		replay_elapsed
		* REPLAY_PLAYBACK_SPEED
		/ REPLAY_SAMPLE_INTERVAL
	)

	var last_index := replay_frames.size() - 1

	if frame_position >= float(last_index):
		_apply_replay_frame(
			replay_frames[last_index],
			replay_frames[last_index],
			0.0
		)
		_update_replay_camera(delta)

		if NetworkManager.is_server_authority():
			_broadcast_round_reset()
		return

	var first_index := int(floor(frame_position))
	var second_index := mini(first_index + 1, last_index)
	var blend := frame_position - float(first_index)

	_apply_replay_frame(
		replay_frames[first_index],
		replay_frames[second_index],
		blend
	)

	_update_replay_camera(delta)


func _apply_replay_frame(
	frame_a: Dictionary,
	frame_b: Dictionary,
	blend: float
) -> void:
	# Replay ball position and spin.
	var ball_position_a: Vector3 = frame_a["ball_position"]
	var ball_position_b: Vector3 = frame_b["ball_position"]

	var ball_rotation_a: Quaternion = frame_a.get(
		"ball_rotation",
		Quaternion()
	)

	var ball_rotation_b: Quaternion = frame_b.get(
		"ball_rotation",
		Quaternion()
	)

	var replay_ball_transform: Transform3D = ball.global_transform

	replay_ball_transform.origin = ball_position_a.lerp(
		ball_position_b,
		blend
	)

	replay_ball_transform.basis = Basis(
		ball_rotation_a.slerp(ball_rotation_b, blend)
	)

	ball.global_transform = replay_ball_transform

	# Replay player movement.
	var players_a: Dictionary = frame_a["players"]
	var players_b: Dictionary = frame_b["players"]

	for id in players.keys():
		if not players_a.has(id) or not players_b.has(id):
			continue

		var state_a: Dictionary = players_a[id]
		var state_b: Dictionary = players_b[id]
		var player = players[id]

		var position_a: Vector3 = state_a["position"]
		var position_b: Vector3 = state_b["position"]
		var yaw_a: float = state_a["yaw"]
		var yaw_b: float = state_b["yaw"]

		player.global_position = position_a.lerp(
			position_b,
			blend
		)

		player.rotation.y = lerp_angle(
			yaw_a,
			yaw_b,
			blend
		)
		if (
			state_a.has("visual_transform")
			and state_b.has("visual_transform")
			and player.visual_root != null
		):
			var visual_a: Transform3D = state_a["visual_transform"]
			var visual_b: Transform3D = state_b["visual_transform"]

			player.visual_root.transform = visual_a.interpolate_with(
				visual_b,
				blend
			)


		if (
			state_a.has("left_leg_transform")
			and state_b.has("left_leg_transform")
			and player.left_leg != null
		):
			var left_leg_a: Transform3D = state_a["left_leg_transform"]
			var left_leg_b: Transform3D = state_b["left_leg_transform"]

			player.left_leg.transform = left_leg_a.interpolate_with(
				left_leg_b,
				blend
			)


		if (
			state_a.has("right_leg_transform")
			and state_b.has("right_leg_transform")
			and player.right_leg != null
		):
			var right_leg_a: Transform3D = state_a["right_leg_transform"]
			var right_leg_b: Transform3D = state_b["right_leg_transform"]

			player.right_leg.transform = right_leg_a.interpolate_with(
				right_leg_b,
				blend
			)

func _update_replay_camera(
	delta: float,
	snap: bool = false
) -> void:
	var replay_player = null

	# Use this computer's player.
	for id in players.keys():
		var candidate = players[id]

		if candidate.is_local_player:
			replay_player = candidate
			break

	# Offline/fallback player.
	if replay_player == null and not players.is_empty():
		var first_id = players.keys()[0]
		replay_player = players[first_id]

	if replay_player == null:
		return

	var player_basis: Basis = Basis(
		Vector3.UP,
		replay_player.rotation.y
	)

	var forward: Vector3 = -player_basis.z
	var right: Vector3 = player_basis.x

	# Over-the-shoulder position.
	var desired_position: Vector3 = (
		replay_player.global_position
		- forward * 4.5
		+ right * 0.55
		+ Vector3.UP * 4.2
	)

	# Look forward rather than directly at the ball.
	var look_target: Vector3 = (
		replay_player.global_position
		+ forward * 10.0
		+ Vector3.UP * 0.8
	)

	if snap:
		replay_camera.global_position = desired_position
	else:
		replay_camera.global_position = (
			replay_camera.global_position.lerp(
				desired_position,
				minf(1.0, delta * 8.0)
			)
		)

	replay_camera.look_at(look_target, Vector3.UP)


func _stop_goal_replay() -> void:
	replay_active = false
	replay_frames.clear()
	replay_elapsed = 0.0

	if replay_camera != null:
		replay_camera.current = false

	for id in players.keys():
		var player = players[id]
		player.set_physics_process(true)

	ball.set_physics_process(true)
	ball.freeze = not NetworkManager.is_server_authority()
	_reset_ball_sweep()

	var camera_restored := false

	for id in players.keys():
		var player = players[id]

		if player.is_local_player and player.camera != null:
			player.camera.current = true
			camera_restored = true
			break

	if not camera_restored:
		spectator_camera.current = true

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_kick_charge(value: float) -> void:
	if hud != null:
		hud.set_charge(value)


func _spawn_player_local(
	id: int,
	team: int,
	nickname: String = "Player"
) -> void:
	var clean_nickname: String = _sanitize_nickname(nickname)
	lobby_teams[id] = team

	if players.has(id):
		players[id].set_display_name(clean_nickname)
		player_nicknames[id] = clean_nickname
		return

	player_nicknames[id] = clean_nickname
	var team_slot: int = _next_team_slot(team)

	var player = PlayerScript.new()
	player.name = "Player_%d" % id

	var yaw: float = PI if team == 0 else 0.0
	var local_control: bool = (
		id == NetworkManager.local_peer_id()
	)

	player.configure(
		id,
		team,
		local_control,
		self,
		yaw,
		clean_nickname
	)

	add_child(player)
	if (
		id == 1
		and NetworkManager.mode == NetworkManager.SessionMode.HOST
	):
		ball.add_collision_exception_with(player)
		player.add_collision_exception_with(ball)
	players[id] = player
	player_slots[id] = team_slot

	player.reset_player(
		_spawn_position(team, team_slot),
		yaw
	)

	if local_control:
		spectator_camera.current = false


func _spawn_position(team: int, team_slot: int) -> Vector3:
	var slot := clampi(team_slot, 0, MAX_TEAM_PLAYERS - 1)
	var x_position := 0.0
	var depth := 9.0

	match slot:
		1:
			x_position = -5.0
			depth = 6.0
		2:
			x_position = 5.0
			depth = 6.0

	var z_position: float = -depth if team == 0 else depth

	return Vector3(x_position, 0.05, z_position)


func _on_connected_to_server() -> void:
	hud.set_status("CLIENT • Connected, joining match...")
	_announce_client_ready()


func _announce_client_ready() -> void:
	if NetworkManager.mode == NetworkManager.SessionMode.CLIENT:
		client_ready.rpc_id(1, local_nickname)


@rpc("any_peer", "call_remote", "reliable")
func client_ready(requested_nickname: String) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()

	if sender <= 1:
		return

	if (
		not player_nicknames.has(sender)
		and player_nicknames.size() >= MAX_PLAYERS
	):
		lobby_join_rejected.rpc_id(
			sender,
			"MATCH FULL • This server already has six players."
		)
		return

	var sender_nickname: String = _sanitize_nickname(requested_nickname)

	if player_nicknames.has(sender):
		sender_nickname = str(player_nicknames[sender])
	else:
		player_nicknames[sender] = sender_nickname

	if not lobby_teams.has(sender):
		lobby_teams[sender] = TEAM_AUTO

	# Send all existing players and their nicknames to the newcomer.
	for existing_id in players.keys():
		var existing_player = players[existing_id]
		var existing_nickname: String = str(
			player_nicknames.get(existing_id, "Player")
		)

		spawn_player_remote.rpc_id(
			sender,
			int(existing_id),
			int(existing_player.team_id),
			existing_nickname
		)

	ready_peers[sender] = true
	receive_match_state.rpc_id(
		sender,
		blue_score,
		red_score,
		match_time,
		round_active,
		match_over
	)
	_broadcast_lobby_state()


@rpc("authority", "call_remote", "reliable")
func lobby_join_rejected(message: String) -> void:
	local_lobby_registered = true
	team_selection_active = true
	hud.set_status("CLIENT • Unable to join")
	hud.show_message(message, 4.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_team_requested(requested_team: int) -> void:
	if NetworkManager.mode == NetworkManager.SessionMode.OFFLINE:
		return

	if NetworkManager.is_server_authority():
		if NetworkManager.mode == NetworkManager.SessionMode.DEDICATED:
			return
		_assign_player_team_authority(
			NetworkManager.local_peer_id(),
			requested_team
		)
	else:
		request_team_remote.rpc_id(1, requested_team)


@rpc("any_peer", "call_remote", "reliable")
func request_team_remote(requested_team: int) -> void:
	if not multiplayer.is_server():
		return

	_assign_player_team_authority(
		multiplayer.get_remote_sender_id(),
		requested_team
	)


func _assign_player_team_authority(
	player_id: int,
	requested_team: int
) -> void:
	if not NetworkManager.is_server_authority():
		return

	if not player_nicknames.has(player_id):
		_send_team_selection_message(
			player_id,
			"Still joining the lobby. Try again in a moment."
		)
		return

	if match_over:
		_send_team_selection_message(
			player_id,
			"The match has finished. Wait for the host to start a rematch."
		)
		return

	var current_team: int = int(
		lobby_teams.get(player_id, TEAM_AUTO)
	)

	if match_started and current_team != TEAM_AUTO:
		_send_team_selection_message(
			player_id,
			"Team changes are locked after kickoff."
		)
		return

	if (
		requested_team != TEAM_AUTO
		and requested_team != TEAM_BLUE
		and requested_team != TEAM_RED
	):
		_send_team_selection_message(player_id, "Invalid team choice.")
		return

	var resolved_team: int = _resolve_team_request(
		player_id,
		requested_team
	)

	if resolved_team == TEAM_AUTO:
		_send_team_selection_message(
			player_id,
			"That team is full. Choose the other side."
		)
		return

	if current_team == resolved_team and players.has(player_id):
		_send_team_selection_message(
			player_id,
			"%s TEAM selected."
			% _team_name(resolved_team)
		)
		_broadcast_lobby_state()
		_try_start_match_authority()
		return

	if players.has(player_id):
		if NetworkManager.is_online():
			remove_player_for_team_switch_remote.rpc(player_id)
		else:
			remove_player_for_team_switch_remote(player_id)

	lobby_teams[player_id] = resolved_team
	var nickname: String = str(
		player_nicknames.get(player_id, "Player")
	)

	if NetworkManager.is_online():
		spawn_player_remote.rpc(
			player_id,
			resolved_team,
			nickname
		)
	else:
		spawn_player_remote(player_id, resolved_team, nickname)

	_send_team_selection_message(
		player_id,
		"%s TEAM selected."
		% _team_name(resolved_team)
	)
	_broadcast_lobby_state()
	_try_start_match_authority()


func _team_name(team: int) -> String:
	return "BLUE" if team == TEAM_BLUE else "RED"


func _send_team_selection_message(
	player_id: int,
	message: String
) -> void:
	if (
		player_id == NetworkManager.local_peer_id()
		and NetworkManager.mode != NetworkManager.SessionMode.DEDICATED
	):
		hud.set_team_selection_message(message)
	elif NetworkManager.is_online():
		receive_team_selection_message.rpc_id(player_id, message)


@rpc("authority", "call_remote", "reliable")
func receive_team_selection_message(message: String) -> void:
	hud.set_team_selection_message(message)


func _broadcast_lobby_state() -> void:
	if not NetworkManager.is_server_authority():
		return

	var nicknames_snapshot: Dictionary = player_nicknames.duplicate(true)
	var teams_snapshot: Dictionary = lobby_teams.duplicate(true)
	var match_in_progress: bool = match_started

	if NetworkManager.mode != NetworkManager.SessionMode.DEDICATED:
		_apply_lobby_state(
			nicknames_snapshot,
			teams_snapshot,
			match_in_progress
		)

	if NetworkManager.is_online():
		receive_lobby_state.rpc(
			nicknames_snapshot,
			teams_snapshot,
			match_in_progress
		)


@rpc("authority", "call_remote", "reliable")
func receive_lobby_state(
	nicknames: Dictionary,
	teams: Dictionary,
	match_in_progress: bool
) -> void:
	_apply_lobby_state(nicknames, teams, match_in_progress)


func _apply_lobby_state(
	nicknames: Dictionary,
	teams: Dictionary,
	match_in_progress: bool
) -> void:
	player_nicknames = nicknames.duplicate(true)
	lobby_teams = teams.duplicate(true)
	match_started = match_in_progress

	if NetworkManager.mode == NetworkManager.SessionMode.DEDICATED:
		return

	var local_id: int = NetworkManager.local_peer_id()
	local_lobby_registered = player_nicknames.has(local_id)
	waiting_for_opponent = not match_started and not match_over

	var blue_names: Array = []
	var red_names: Array = []
	var waiting_names: Array = []
	var sorted_ids: Array = player_nicknames.keys()
	sorted_ids.sort()

	for id_value in sorted_ids:
		var player_id: int = int(id_value)
		var display_name: String = str(
			player_nicknames.get(player_id, "Player")
		)

		if player_id == local_id:
			display_name += "  • YOU"

		var team: int = int(
			lobby_teams.get(player_id, TEAM_AUTO)
		)

		if team == TEAM_BLUE:
			blue_names.append(display_name)
		elif team == TEAM_RED:
			red_names.append(display_name)
		else:
			waiting_names.append(display_name)

	var local_team: int = int(
		lobby_teams.get(local_id, TEAM_AUTO)
	)

	if (
		match_started
		and (local_team == TEAM_BLUE or local_team == TEAM_RED)
	):
		team_selection_active = false
		hud.hide_team_selection()
		_restore_local_player_camera()

		if not pause_open and not match_over and not replay_active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	team_selection_active = true
	pause_open = false
	hud.set_pause_visible(false)
	hud.set_charge(0.0)
	spectator_camera.current = true

	var selection_message: String

	if match_over:
		selection_message = "The match has finished. Wait for a rematch."
	elif local_team == TEAM_AUTO and match_started:
		selection_message = (
			"Match in progress • choose an open team to join now."
		)
	elif local_team == TEAM_AUTO:
		selection_message = (
			"Choose with the mouse or D-pad / stick • confirm with Enter / A."
		)
	else:
		selection_message = (
			"%s TEAM selected • kickoff begins when both teams have a player."
			% _team_name(local_team)
		)

	hud.set_status(
		"%s • TEAM LOBBY • UP TO 3v3"
		% NetworkManager.mode_label()
	)
	hud.show_team_selection(
		blue_names,
		red_names,
		waiting_names,
		local_team,
		MAX_TEAM_PLAYERS,
		selection_message
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


@rpc("authority", "call_local", "reliable")
func spawn_player_remote(
	id: int,
	team: int,
	nickname: String
) -> void:
	_spawn_player_local(id, team, nickname)


@rpc("authority", "call_local", "reliable")
func remove_player_remote(id: int) -> void:
	_despawn_player_local(id, true)


@rpc("authority", "call_local", "reliable")
func remove_player_for_team_switch_remote(id: int) -> void:
	_despawn_player_local(id, false)


func _despawn_player_local(id: int, erase_identity: bool) -> void:
	if players.has(id):
		var player: Node = players[id]
		players.erase(id)
		player.queue_free()

	player_slots.erase(id)
	last_dribble_touch_msec.erase(id)
	last_ball_control_msec.erase(id)
	last_kick_msec.erase(id)
	last_juggle_msec.erase(id)
	active_goalkeeper_dives.erase(id)
	last_goalkeeper_dive_msec.erase(id)

	if erase_identity:
		player_nicknames.erase(id)
		lobby_teams.erase(id)
		ready_peers.erase(id)


func _on_peer_left(id: int) -> void:
	if not NetworkManager.is_server_authority():
		return

	var departed_name: String = str(
		player_nicknames.get(id, "A player")
	)

	if NetworkManager.is_online():
		remove_player_remote.rpc(id)
	else:
		remove_player_remote(id)

	var team_is_empty: bool = (
		_team_player_count(TEAM_BLUE) == 0
		or _team_player_count(TEAM_RED) == 0
	)

	if team_is_empty:
		match_started = false
		waiting_for_opponent = true
		round_active = false
		match_over = false
		blue_score = 0
		red_score = 0
		match_time = MATCH_DURATION
		round_reset_timer = -1.0

		var lobby_message: String = (
			"%s left • choose teams for the next kickoff."
			% departed_name
		)

		if NetworkManager.is_online():
			return_to_team_lobby_remote.rpc(lobby_message)
		else:
			return_to_team_lobby_remote(lobby_message)
	else:
		waiting_for_opponent = false
		hud.show_message("%s LEFT • MATCH CONTINUES" % departed_name, 2.2)

	_broadcast_lobby_state()


@rpc("authority", "call_local", "reliable")
func return_to_team_lobby_remote(message: String) -> void:
	if replay_active:
		_stop_goal_replay()

	match_started = false
	waiting_for_opponent = true
	round_active = false
	match_over = false
	blue_score = 0
	red_score = 0
	match_time = MATCH_DURATION
	pause_open = false
	round_reset_timer = -1.0
	replay_buffer.clear()
	replay_sample_timer = 0.0
	hud.hide_game_over()
	hud.set_pause_visible(false)
	hud.show_message(message, 2.5)
	_reset_round_local()
	spectator_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _try_start_match_authority() -> void:
	if not NetworkManager.is_server_authority():
		return
	if match_started or match_over:
		return
	if _team_player_count(TEAM_BLUE) < 1:
		return
	if _team_player_count(TEAM_RED) < 1:
		return

	_begin_full_match_authority()


func _begin_full_match_authority() -> void:
	if not NetworkManager.is_server_authority():
		return
	if (
		NetworkManager.is_online()
		and (
			_team_player_count(TEAM_BLUE) < 1
			or _team_player_count(TEAM_RED) < 1
		)
	):
		return

	if NetworkManager.is_online():
		begin_match_remote.rpc()
	else:
		begin_match_remote()

	if NetworkManager.is_online():
		_broadcast_lobby_state()


@rpc("authority", "call_local", "reliable")
func begin_match_remote() -> void:
	blue_score = 0
	red_score = 0
	match_time = MATCH_DURATION
	match_started = true
	match_over = false
	waiting_for_opponent = false
	round_active = true
	round_reset_timer = -1.0
	team_selection_active = false
	hud.hide_game_over()
	hud.hide_team_selection()
	if NetworkManager.mode == NetworkManager.SessionMode.OFFLINE:
		hud.set_status("TRAINING • Attack the red goal")
	else:
		hud.set_status(
			"%s • ONLINE MATCH • UP TO 3v3"
			% NetworkManager.mode_label()
		)
	hud.show_message("KICKOFF", 1.5)
	_reset_round_local()
	_restore_local_player_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restore_local_player_camera() -> void:
	for id in players.keys():
		var player = players[id]

		if player.is_local_player and player.camera != null:
			spectator_camera.current = false
			player.camera.current = true
			return

	spectator_camera.current = true


func submit_local_player_state(position_value: Vector3, yaw: float, velocity_value: Vector3) -> void:
	if NetworkManager.mode == NetworkManager.SessionMode.CLIENT:
		submit_player_state.rpc_id(1, position_value, yaw, velocity_value)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func submit_player_state(position_value: Vector3, yaw: float, velocity_value: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	var player = players[sender]
	var safe_position := position_value
	safe_position.x = clampf(safe_position.x, -14.6, 14.6)
	safe_position.y = clampf(safe_position.y, -0.2, 6.5)
	safe_position.z = clampf(safe_position.z, -25.0, 25.0)
	var offset: Vector3 = safe_position - player.global_position
	if offset.length() > 2.2:
		safe_position = player.global_position + offset.normalized() * 2.2
	var safe_velocity := velocity_value.limit_length(15.5)
	player.receive_network_state(safe_position, yaw, safe_velocity)


func request_player_ball_control(id: int) -> void:
	if NetworkManager.is_server_authority():
		_perform_authority_ball_control(id)
	else:
		request_ball_control_remote.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func request_ball_control_remote() -> void:
	if not multiplayer.is_server():
		return

	_perform_authority_ball_control(
		multiplayer.get_remote_sender_id()
	)


func _perform_authority_ball_control(id: int) -> void:
	if replay_active or match_over:
		return
	if not round_active and not waiting_for_opponent:
		return
	if not players.has(id):
		return

	var now: int = Time.get_ticks_msec()

	# A kick that reaches the server first always defeats a control attempt.
	if now - last_authority_kick_msec < BALL_CONTROL_KICK_PRIORITY_MS:
		return

	var previous: int = int(last_ball_control_msec.get(id, 0))
	if now - previous < BALL_CONTROL_COOLDOWN_MS:
		return

	var player = players[id]
	var to_ball: Vector3 = ball.global_position - player.global_position

	if (
		to_ball.y < BALL_CONTROL_MIN_HEIGHT
		or to_ball.y > BALL_CONTROL_MAX_HEIGHT
	):
		return

	var flat_offset: Vector3 = Vector3(
		to_ball.x,
		0.0,
		to_ball.z
	)

	if flat_offset.length() > BALL_CONTROL_DISTANCE:
		return

	var player_velocity: Vector3 = Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var ball_velocity: Vector3 = Vector3(
		ball.linear_velocity.x,
		0.0,
		ball.linear_velocity.z
	)
	# A trap follows only a small part of the player's run. This prevents Ctrl
	# from behaving like a second dribble push while still cushioning on the move.
	var control_target_velocity: Vector3 = (
		player_velocity * BALL_CONTROL_PLAYER_VELOCITY_SHARE
	)
	var relative_velocity: Vector3 = (
		ball_velocity - control_target_velocity
	)
	var relative_speed: float = relative_velocity.length()
	var relative_vertical_speed: float = (
		ball.linear_velocity.y - player.velocity.y
	)

	if relative_speed < 0.05 and absf(relative_vertical_speed) < 0.05:
		return

	# Reduce relative motion instead of assigning a new velocity. The cap keeps
	# this weaker than a kick, especially against a fast shot.
	var control_impulse: Vector3 = Vector3.ZERO

	if relative_speed >= 0.05:
		var horizontal_speed_change: float = minf(
			relative_speed * BALL_CONTROL_DAMPING,
			BALL_CONTROL_MAX_SPEED_CHANGE
		)
		control_impulse = (
			-relative_velocity.normalized()
			* horizontal_speed_change
			* ball.mass
		)

	var vertical_speed_change: float = clampf(
		-relative_vertical_speed * BALL_CONTROL_VERTICAL_DAMPING,
		-BALL_CONTROL_MAX_VERTICAL_CHANGE,
		BALL_CONTROL_MAX_VERTICAL_CHANGE
	)
	control_impulse.y = vertical_speed_change * ball.mass

	last_ball_control_msec[id] = now
	ball.sleeping = false
	ball.apply_central_impulse(control_impulse)
	_broadcast_ball_control_animation(id)
	_broadcast_immediate_snapshot()


func request_player_kick(
	id: int,
	direction: Vector3,
	power: float,
	lift: float,
	curve: float,
	knuckle: bool
) -> void:
	if NetworkManager.is_server_authority():
		_perform_authority_kick(
			id, direction, power, lift, curve, knuckle
		)
	else:
		request_kick_remote.rpc_id(
			1, direction, power, lift, curve, knuckle
		)


@rpc("any_peer", "call_remote", "reliable")
func request_kick_remote(
	direction: Vector3,
	power: float,
	lift: float,
	curve: float,
	knuckle: bool
) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()

	_perform_authority_kick(
		sender, direction, power, lift, curve, knuckle
	)


func _perform_authority_kick(
	id: int,
	direction: Vector3,
	power: float,
	lift: float,
	curve: float,
	knuckle: bool
) -> void:
	if not round_active and not waiting_for_opponent:
		return
	if not players.has(id):
		return

	var now: int = Time.get_ticks_msec()
	var previous: int = int(last_kick_msec.get(id, 0))

	if now - previous < 115:
		return

	var player = players[id]
	var to_ball: Vector3 = ball.global_position - player.global_position

	var maximum_distance: float = 2.35

	if to_ball.y > 0.65:
		maximum_distance = 2.75

	if to_ball.length() > maximum_distance:
		return

	last_kick_msec[id] = now
	last_authority_kick_msec = now

	var flat_to_ball: Vector3 = Vector3(
		to_ball.x, 0.0, to_ball.z
	).normalized()

	var safe_direction: Vector3 = Vector3(
		direction.x, 0.0, direction.z
	).normalized()

	if safe_direction.length_squared() < 0.5:
		safe_direction = -player.global_transform.basis.z

	var final_direction: Vector3 = (
		safe_direction * 0.82
		+ flat_to_ball * 0.18
	).normalized()
	_broadcast_kick_animation(id)
	ball.kick(
		final_direction,
		clampf(power, 0.5, 30.0),
		clampf(lift, 0.0, 0.42),
		clampf(curve, -1.0, 1.0),
		knuckle
	)
	_broadcast_immediate_snapshot()

func can_player_juggle(id: int) -> bool:
	if not players.has(id):
		return false

	var player = players[id]
	var offset: Vector3 = (
		ball.global_position - player.global_position
	)

	return (
		offset.length() <= 2.05
		and offset.y >= -0.1
		and offset.y <= 1.9
	)


func can_player_bicycle(id: int) -> bool:
	if not players.has(id):
		return false

	var player = players[id]
	var offset: Vector3 = (
		ball.global_position - player.global_position
	)

	return (
		ball.global_position.y > 0.9
		and offset.y > 0.55
		and offset.y < 2.6
		and offset.length() <= 2.8
	)

func request_player_juggle(
	id: int,
	direction: Vector3
) -> void:
	if NetworkManager.is_server_authority():
		_perform_authority_juggle(id, direction)
	else:
		request_juggle_remote.rpc_id(1, direction)


@rpc("any_peer", "call_remote", "reliable")
func request_juggle_remote(direction: Vector3) -> void:
	if not multiplayer.is_server():
		return

	_perform_authority_juggle(
		multiplayer.get_remote_sender_id(),
		direction
	)


func _perform_authority_juggle(
	id: int,
	direction: Vector3
) -> void:
	if not can_player_juggle(id):
		return

	var now: int = Time.get_ticks_msec()
	var previous: int = int(last_juggle_msec.get(id, 0))

	if now - previous < 120:
		return

	last_juggle_msec[id] = now

	var safe_direction: Vector3 = Vector3(
		direction.x,
		0.0,
		direction.z
	).normalized()

	ball.keep_up(safe_direction)
	_broadcast_kick_animation(id)
	_broadcast_immediate_snapshot()

func request_player_bicycle(
	id: int,
	direction: Vector3
) -> void:
	if NetworkManager.is_server_authority():
		_perform_authority_bicycle(id, direction)
	else:
		request_bicycle_remote.rpc_id(1, direction)


@rpc("any_peer", "call_remote", "reliable")
func request_bicycle_remote(direction: Vector3) -> void:
	if not multiplayer.is_server():
		return

	_perform_authority_bicycle(
		multiplayer.get_remote_sender_id(),
		direction
	)

func _broadcast_bicycle_animation(id: int) -> void:
	if players.has(id):
		var player = players[id]

		if not player.is_local_player:
			player.start_bicycle_animation()

	if NetworkManager.is_online():
		receive_bicycle_animation.rpc(id)


@rpc("authority", "call_remote", "reliable")
func receive_bicycle_animation(id: int) -> void:
	if players.has(id):
		var player = players[id]

		if not player.is_local_player:
			player.start_bicycle_animation()

func _perform_authority_bicycle(
	id: int,
	direction: Vector3
) -> void:
	if not can_player_bicycle(id):
		return

	var now: int = Time.get_ticks_msec()
	var previous: int = int(last_kick_msec.get(id, 0))

	if now - previous < 650:
		return

	last_kick_msec[id] = now
	last_authority_kick_msec = now

	var safe_direction: Vector3 = Vector3(
		direction.x,
		0.0,
		direction.z
	).normalized()

	ball.bicycle_kick(safe_direction)
	_broadcast_bicycle_animation(id)
	_broadcast_immediate_snapshot()



func _broadcast_snapshots() -> void:
	world_snapshot_sequence += 1
	var player_states: Array = []

	for id in players.keys():
		var player = players[id]
		player_states.append([
			int(id),
			player.global_position,
			player.rotation.y,
			player.velocity
		])

	receive_world_snapshot.rpc(
		world_snapshot_sequence,
		player_states,
		ball.global_position,
		ball.linear_velocity,
		ball.quaternion,
		ball.angular_velocity
	)


func _broadcast_immediate_snapshot() -> void:
	if not NetworkManager.is_online():
		return

	snapshot_timer = 0.0
	_broadcast_snapshots()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func receive_world_snapshot(
	sequence: int,
	player_states: Array,
	ball_position: Vector3,
	ball_velocity: Vector3,
	ball_rotation: Quaternion,
	ball_angular_velocity: Vector3
) -> void:
	if replay_active or sequence <= last_world_snapshot_sequence:
		return

	last_world_snapshot_sequence = sequence

	for state_value in player_states:
		if not (state_value is Array):
			continue

		var player_state: Array = state_value

		if player_state.size() < 4:
			continue

		var id: int = int(player_state[0])

		if not players.has(id):
			continue

		var position_value: Vector3 = player_state[1]
		var yaw: float = float(player_state[2])
		var velocity_value: Vector3 = player_state[3]

		players[id].receive_network_state(
			position_value,
			yaw,
			velocity_value
		)

	ball.receive_full_snapshot(
		ball_position,
		ball_velocity,
		ball_rotation,
		ball_angular_velocity
	)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_ball_rotation_snapshot(
	rotation_value: Quaternion
) -> void:
	if replay_active:
		return

	ball.receive_rotation_snapshot(rotation_value)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_snapshot(
	id: int,
	position_value: Vector3,
	yaw: float,
	velocity_value: Vector3
) -> void:
	if replay_active:
		return

	if players.has(id):
		players[id].receive_network_state(
			position_value,
			yaw,
			velocity_value
		)


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_ball_snapshot(
	position_value: Vector3,
	velocity_value: Vector3
) -> void:
	if replay_active:
		return

	ball.receive_snapshot(position_value, velocity_value)


@rpc("authority", "call_remote", "reliable")
func receive_ball_reset(position_value: Vector3) -> void:
	ball.reset_ball(position_value)
	_reset_ball_sweep()


func _broadcast_kick_animation(id: int) -> void:
	if players.has(id):
		var kicking_player = players[id]

		if not kicking_player.is_local_player:
			kicking_player.start_kick_animation()

	if NetworkManager.is_online():
		receive_kick_animation.rpc(id)


func _broadcast_ball_control_animation(id: int) -> void:
	if players.has(id):
		var controlling_player = players[id]

		if not controlling_player.is_local_player:
			controlling_player.start_ball_control_animation()

	if NetworkManager.is_online():
		receive_ball_control_animation.rpc(id)


@rpc("authority", "call_remote", "reliable")
func receive_ball_control_animation(id: int) -> void:
	if not players.has(id):
		return

	var controlling_player = players[id]

	if not controlling_player.is_local_player:
		controlling_player.start_ball_control_animation()


@rpc("authority", "call_remote", "reliable")
func receive_kick_animation(id: int) -> void:
	if not players.has(id):
		return

	var kicking_player = players[id]

	# The local player already predicted the animation.
	if not kicking_player.is_local_player:
		kicking_player.start_kick_animation()


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_match_state(blue: int, red: int, seconds_left: float, is_round_active: bool, is_match_over: bool) -> void:
	if replay_active and is_round_active:
		_stop_goal_replay()
	blue_score = blue
	red_score = red
	match_time = seconds_left
	round_active = is_round_active
	match_over = is_match_over

	if is_round_active:
		waiting_for_opponent = false
	elif not match_started and not is_match_over:
		waiting_for_opponent = true


func _on_goal_scored(scoring_team: int) -> void:
	if not NetworkManager.is_server_authority() or match_over:
		return
	if waiting_for_opponent and not round_active:
		hud.show_message("WARM-UP GOAL", 1.2)
		_reset_ball_only()
		return
	if not round_active:
		return
	if scoring_team == 0:
		blue_score += 1
	else:
		red_score += 1
	round_active = false
	round_reset_timer = -1.0
	if NetworkManager.is_online():
		goal_scored_remote.rpc(scoring_team, blue_score, red_score)
	else:
		goal_scored_remote(scoring_team, blue_score, red_score)


@rpc("authority", "call_local", "reliable")
func goal_scored_remote(scoring_team: int, blue: int, red: int) -> void:
	blue_score = blue
	red_score = red
	round_active = false
	var started := _start_goal_replay(scoring_team)

	if not started:
		hud.show_message(
			"BLUE GOAL!" if scoring_team == 0 else "RED GOAL!",
			2.1
		)

		if NetworkManager.is_server_authority():
			round_reset_timer = 2.35

func debug_goalkeeper_shot(id: int) -> void:
	if not NetworkManager.is_server_authority():
		return
	if not players.has(id):
		return

	var player = players[id]
	var goal_side: float = (
		-1.0 if player.team_id == 0 else 1.0
	)

	ball.freeze = false
	ball.sleeping = false

	ball.global_position = Vector3(
		0.0,
		1.1,
		goal_side * 12.0
	)

	ball.linear_velocity = Vector3(
		0.0,
		1.2,
		goal_side * 14.0
	)

	ball.angular_velocity = Vector3.ZERO

func _broadcast_round_reset() -> void:
	if NetworkManager.is_online():
		reset_round_remote.rpc()
	else:
		reset_round_remote()


@rpc("authority", "call_local", "reliable")
func reset_round_remote() -> void:
	_stop_goal_replay()

	replay_buffer.clear()
	replay_sample_timer = 0.0

	_reset_round_local()
	round_active = true
	hud.show_message("KICKOFF", 1.0)


func _reset_round_local() -> void:
	last_ball_control_msec.clear()
	last_authority_kick_msec = -1000000
	ball.reset_ball(Vector3(0, 0.62, 0))
	_reset_ball_sweep()
	for id in players.keys():
		var player = players[id]
		var yaw := PI if player.team_id == 0 else 0.0
		var team_slot := int(player_slots.get(id, 0))

		player.reset_player(
			_spawn_position(player.team_id, team_slot),
			yaw
		)


func _reset_ball_only(
	position_value: Vector3 = Vector3(0.0, 0.62, 0.0)
) -> void:
	ball.reset_ball(position_value)
	_reset_ball_sweep()

	if NetworkManager.is_online():
		receive_ball_reset.rpc(position_value)


func _finish_match() -> void:
	if match_over:
		return
	match_over = true
	round_active = false
	if NetworkManager.is_online():
		finish_match_remote.rpc(blue_score, red_score)
	else:
		finish_match_remote(blue_score, red_score)


@rpc("authority", "call_local", "reliable")
func finish_match_remote(blue: int, red: int) -> void:
	blue_score = blue
	red_score = red
	match_over = true
	round_active = false
	waiting_for_opponent = false
	pause_open = false
	team_selection_active = false
	hud.show_game_over(blue_score, red_score, NetworkManager.is_server_authority())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restart_requested() -> void:
	if NetworkManager.is_server_authority():
		_begin_full_match_authority()


func _set_pause_open(value: bool) -> void:
	if value and team_selection_active:
		return

	pause_open = value
	hud.set_pause_visible(value)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED


func _resume_game() -> void:
	_set_pause_open(false)


func _leave_game() -> void:
	leave_requested.emit()
