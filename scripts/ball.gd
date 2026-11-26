extends RigidBody3D

## The host/offline instance simulates the ball. Clients interpolate snapshots.

const RADIUS := 0.25
const BALL_ALBEDO = preload(
	"res://assets/ball/ball_albedo.png"
)
const MAX_SPEED := 40.0
const AERO_MIN_SPEED: float = 3.0
const CURVE_ACCELERATION: float = 20.0
const CURVE_DECAY: float = 0.30
const KNUCKLE_SIDE_ACCELERATION: float = 20.0
const KNUCKLE_VERTICAL_ACCELERATION: float = 20.0
const KNUCKLE_DECAY: float = 0.55
const NETWORK_MAX_EXTRAPOLATION: float = 0.10
const NETWORK_POSITION_RESPONSE: float = 40.0
const NETWORK_ROTATION_RESPONSE: float = 32.0

var curve_amount: float = 0.0
var knuckle_amount: float = 0.0
var knuckle_time: float = 0.0
var knuckle_phase: float = 0.0
var authority_simulation := true
var target_position := Vector3.ZERO
var target_rotation: Quaternion = Quaternion.IDENTITY
var target_velocity := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO
var network_snapshot_age: float = 0.0
var has_network_snapshot: bool = false
var visual: MeshInstance3D


func configure(is_authority: bool) -> void:
	authority_simulation = is_authority


func _ready() -> void:
	mass = 0.20
	linear_damp = 0.75
	angular_damp = 0.35
	continuous_cd = true
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = 4 if authority_simulation else 0
	collision_mask = 1 if authority_simulation else 0
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 1.00
	physics_material.bounce = 0.55
	physics_material_override = physics_material

	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	collider.shape = shape
	add_child(collider)

	visual = MeshInstance3D.new()
	visual.name = "BallVisual"

	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0

	# Smoother visual mesh; dimensions remain unchanged.
	sphere.radial_segments = 64
	sphere.rings = 32

	visual.mesh = sphere
	visual.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)

	var material := StandardMaterial3D.new()

	# Soccer-ball pattern.
	material.albedo_color = Color.WHITE
	material.albedo_texture = BALL_ALBEDO

	# Leather/rubber appearance.
	material.metallic = 0.0
	material.metallic_specular = 0.45
	material.roughness = 0.62

	# Subtle outer coating.
	material.clearcoat_enabled = true
	material.clearcoat = 0.12
	material.clearcoat_roughness = 0.48

	# Keeps the texture clear at different angles and distances.
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	)

	visual.material_override = material
	add_child(visual)

	freeze = not authority_simulation
	target_position = global_position
	target_rotation = quaternion

func keep_up(direction: Vector3) -> void:
	if not authority_simulation:
		return

	var flat_direction: Vector3 = Vector3(
		direction.x,
		0.0,
		direction.z
	).normalized()

	var target_horizontal: Vector3 = flat_direction * 5

	sleeping = false
	curve_amount = 0.0
	knuckle_amount = 0.0

	linear_velocity = Vector3(
		target_horizontal.x,
		5.2,
		target_horizontal.z
	)

	angular_velocity = Vector3(
		flat_direction.z,
		0.0,
		-flat_direction.x
	) * 5.0


func bicycle_kick(direction: Vector3) -> void:
	kick(
		direction,
		23.0,
		0.20,
		0.0,
		false
	)

func _add_patch(local_position: Vector3, local_rotation: Vector3) -> void:
	var patch := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.15
	mesh.height = 0.025
	patch.mesh = mesh
	patch.position = local_position
	patch.rotation = local_rotation
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("172033")
	material.roughness = 0.58
	patch.material_override = material
	add_child(patch)

func goalkeeper_save(direction: Vector3) -> void:
	if not authority_simulation:
		return

	var save_direction: Vector3 = direction.normalized()
	var save_speed: float = clampf(
		maxf(linear_velocity.length(), 9.0),
		9.0,
		18.0
	)

	var saved_velocity: Vector3 = (
		save_direction * save_speed
	)

	saved_velocity.y = maxf(
		saved_velocity.y,
		3.2
	)

	sleeping = false
	curve_amount = 0.0
	knuckle_amount = 0.0
	linear_velocity = saved_velocity

	angular_velocity = Vector3(
		save_direction.z,
		0.0,
		-save_direction.x
	) * 7.0

func _integrate_forces(
	state: PhysicsDirectBodyState3D
) -> void:
	if not authority_simulation:
		return

	var delta: float = state.step
	var new_velocity: Vector3 = state.linear_velocity
	var planar_velocity: Vector3 = Vector3(
		new_velocity.x,
		0.0,
		new_velocity.z
	)

	var planar_speed: float = planar_velocity.length()

	if planar_speed > AERO_MIN_SPEED:
		var forward: Vector3 = planar_velocity / planar_speed
		var right: Vector3 = forward.cross(Vector3.UP)
		var speed_factor: float = clampf(
			planar_speed / 18.0,
			0.35,
			1.35
		)

		if absf(curve_amount) > 0.001:
			new_velocity += (
				right
				* curve_amount
				* CURVE_ACCELERATION
				* speed_factor
				* delta
			)

		if knuckle_amount > 0.001:
			knuckle_time += delta

			var side_wave: float = (
				sin(knuckle_time * 8.0 + knuckle_phase)
				+ 0.45 * sin(
					knuckle_time * 14.5
					+ knuckle_phase * 0.73
				)
			)

			var vertical_wave: float = sin(
				knuckle_time * 10.5
				+ knuckle_phase * 1.37
			)

			new_velocity += (
				right
					* side_wave
					* KNUCKLE_SIDE_ACCELERATION
				+ Vector3.UP
					* vertical_wave
					* KNUCKLE_VERTICAL_ACCELERATION
			) * knuckle_amount * speed_factor * delta

	curve_amount = move_toward(
		curve_amount,
		0.0,
		CURVE_DECAY * delta
	)

	knuckle_amount = move_toward(
		knuckle_amount,
		0.0,
		KNUCKLE_DECAY * delta
	)

	if new_velocity.length() > MAX_SPEED:
		new_velocity = new_velocity.normalized() * MAX_SPEED

	state.linear_velocity = new_velocity

func _physics_process(delta: float) -> void:
	if authority_simulation:
		if linear_velocity.length() > MAX_SPEED:
			linear_velocity = linear_velocity.normalized() * MAX_SPEED
	else:
		_update_network_replica(delta)


func _update_network_replica(delta: float) -> void:
	if not has_network_snapshot:
		return

	network_snapshot_age = minf(
		network_snapshot_age + delta,
		NETWORK_MAX_EXTRAPOLATION
	)

	var latency_lead: float = NetworkManager.one_way_latency_seconds(1)
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

	if position_error > 1.75:
		global_position = predicted_position
	else:
		var position_weight: float = (
			1.0 - exp(-NETWORK_POSITION_RESPONSE * delta)
		)
		global_position = global_position.lerp(
			predicted_position,
			position_weight
		)

	var predicted_rotation: Quaternion = target_rotation
	var spin_speed: float = target_angular_velocity.length()

	if spin_speed > 0.001:
		var spin_axis: Vector3 = (
			target_angular_velocity / spin_speed
		)
		var spin_delta := Quaternion(
			spin_axis,
			spin_speed * prediction_time
		)
		predicted_rotation = (
			spin_delta * target_rotation
		).normalized()

	var rotation_weight: float = (
		1.0 - exp(-NETWORK_ROTATION_RESPONSE * delta)
	)
	quaternion = quaternion.slerp(
		predicted_rotation,
		rotation_weight
	).normalized()

func receive_rotation_snapshot(
	rotation_value: Quaternion
) -> void:
	target_rotation = rotation_value.normalized()

func kick(
	direction: Vector3,
	power: float,
	lift: float,
	curve: float,
	knuckle: bool
) -> void:
	if not authority_simulation:
		return

	var impulse_direction: Vector3 = direction.normalized()
	impulse_direction.y = clampf(lift, 0.0, 0.55)
	impulse_direction = impulse_direction.normalized()

	curve_amount = (
		0.0 if knuckle
		else clampf(curve, -1.0, 1.0)
	)

	knuckle_amount = 1.0 if knuckle else 0.0
	knuckle_time = 0.0
	knuckle_phase = fmod(
		float(Time.get_ticks_msec()) * 0.019,
		TAU
	)

	sleeping = false

	apply_central_impulse(
		impulse_direction * power * 0.74
	)

	if knuckle:
		angular_velocity *= 0.12
	else:
		apply_torque_impulse(
			Vector3(direction.z, 0.15, -direction.x)
			* power
			* 0.045
		)

		apply_torque_impulse(
			Vector3.UP
			* curve_amount
			* power
			* 0.055
		)


func reset_ball(position_value: Vector3) -> void:
	target_position = position_value
	target_velocity = Vector3.ZERO
	global_position = position_value
	quaternion = Quaternion.IDENTITY
	target_rotation = Quaternion.IDENTITY
	target_angular_velocity = Vector3.ZERO
	network_snapshot_age = 0.0
	has_network_snapshot = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	curve_amount = 0.0
	knuckle_amount = 0.0
	knuckle_time = 0.0
	if authority_simulation:
		freeze = true
		set_deferred("freeze", false)



func receive_snapshot(position_value: Vector3, velocity_value: Vector3) -> void:
	target_position = position_value
	target_velocity = velocity_value
	network_snapshot_age = 0.0
	has_network_snapshot = true
	if global_position.distance_to(position_value) > 4.0:
		global_position = position_value


func receive_full_snapshot(
	position_value: Vector3,
	velocity_value: Vector3,
	rotation_value: Quaternion,
	angular_velocity_value: Vector3
) -> void:
	target_position = position_value
	target_velocity = velocity_value
	target_rotation = rotation_value.normalized()
	target_angular_velocity = angular_velocity_value
	network_snapshot_age = 0.0
	has_network_snapshot = true

	if global_position.distance_to(position_value) > 2.5:
		global_position = position_value
		quaternion = target_rotation
