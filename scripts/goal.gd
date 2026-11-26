extends Area3D

signal ball_scored(scoring_team: int)

var scoring_team: int = 0
var goal_side: float = 1.0
var goal_line_z: float = 0.0
var ball_radius: float = 0.54
var candidate_ball: Node3D = null


func configure(
	team_that_scores: int,
	size: Vector3,
	line_z_value: float,
	side_value: float,
	ball_radius_value: float
) -> void:
	scoring_team = team_that_scores
	goal_line_z = line_z_value
	goal_side = side_value
	ball_radius = ball_radius_value

	collision_layer = 8
	collision_mask = 4
	monitoring = true
	monitorable = false

	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	add_child(shape_node)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if candidate_ball == null:
		return

	if not is_instance_valid(candidate_ball):
		candidate_ball = null
		return

	var ball_z: float = candidate_ball.global_position.z
	var fully_crossed: bool

	if goal_side > 0.0:
		fully_crossed = ball_z - ball_radius >= goal_line_z
	else:
		fully_crossed = ball_z + ball_radius <= goal_line_z

	if fully_crossed:
		candidate_ball = null
		ball_scored.emit(scoring_team)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("match_ball"):
		candidate_ball = body


func _on_body_exited(body: Node3D) -> void:
	if body == candidate_ball:
		candidate_ball = null
