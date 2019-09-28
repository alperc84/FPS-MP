extends KinematicBody
class_name BaseCharacter

const GRAVITY = -24.8
const MAX_SPEED = 6
const MAX_SPRINT_SPEED = 10
const MAX_CROUCH_SPEED = 4
const JUMP_SPEED = 10
const ACCEL = 6
const SPRINT_ACCEL = 10
const DEACCEL = 6
const MAX_SLOPE_ANGLE = 40
const MAX_STAIR_SLOPE = 20
const STAIR_JUMP_HEIGHT = 5

onready var health setget set_health
signal health_changed

var cmd = {
	forward = 0,
	right = 0,
	sprint = false,
	jump = false,
	kill = false,
	fire = false,
	reload = false,
	drop = false
}

var velocity = Vector3()
var direction = Vector3()
var movement_vector = Vector2()

# States
var is_dead = false
var is_sprinting = false
var is_crouching = false
var is_landing = false
var is_on_stairs = false

# Jumping
var can_jump = true

# Sprinting
var can_sprint = true

# Footsteps
const TIME_BETWEEN_FOOTSTEP = 0.5
var footstep_timer = 0
const footsteps = [
	preload("res://sounds/footsteps/concrete/footstep_1.wav"),
	preload("res://sounds/footsteps/concrete/footstep_2.wav"),
	preload("res://sounds/footsteps/concrete/footstep_3.wav"),
	preload("res://sounds/footsteps/concrete/footstep_4.wav"),
	preload("res://sounds/footsteps/concrete/footstep_5.wav")
]
const footstep_jump = preload("res://sounds/footsteps/concrete/jump.wav")
const footstep_land = preload("res://sounds/footsteps/concrete/land.wav")

# Landing
var time_in_air = 0

# Gibs
onready var scn_gib_1 = preload("res://models/suzanne/gibs/gib_1.tscn")
onready var scn_gib_2 = preload("res://models/suzanne/gibs/gib_2.tscn")

var equipped_weapon = null

func _ready():
	connect("health_changed", self, "_on_health_changed")
	
	get_node("timer_respawn").connect("timeout", self, "_on_timer_respawn_timeout")
	
	set_health(100)

func _physics_process(delta):
	if(is_network_master() and !is_dead):
		process_cmds()
		process_movement(delta)
		process_collisions()
		process_stairs()
		process_landing(delta)
		process_footsteps(delta)
		rpc("check_weapons")

func process_cmds():
	# Walking
	direction = Vector3()
	movement_vector = Vector2()
	if cmd.forward == 1:
		movement_vector.y = 1
	if cmd.forward == -1:
		movement_vector.y = -1
	if cmd.right == 1:
		movement_vector.x = 1
	if cmd.right == -1:
		movement_vector.x = -1
	movement_vector = movement_vector.normalized()
	direction += -global_transform.basis.z.normalized() * movement_vector.y
	direction += global_transform.basis.x.normalized() * movement_vector.x

	# Sprinting
	if cmd.sprint and can_sprint:
		is_sprinting = true
		if has_node("audio/sprint"):
			get_node("audio/sprint").play()
	else:
		is_sprinting = false

	# Jumping
	if cmd.jump and is_on_floor() and can_jump:
		velocity.y = JUMP_SPEED

	# Kill
	if cmd.kill:
		rpc("die")
	
	# Dealing with weapons
	if equipped_weapon != null:
		if cmd.fire:
			equipped_weapon.rpc("fire")
		if cmd.reload:
			equipped_weapon.rpc("reload")
		if cmd.drop:
			equipped_weapon.rpc("drop")

# Movement
func process_movement(delta):
	direction.y = 0
	direction = direction.normalized()

	velocity.y += delta * GRAVITY

	var horizontal_velocity = velocity
	horizontal_velocity.y = 0

	var target = direction
	if is_sprinting:
		target *= MAX_SPRINT_SPEED
	else:
		target *= MAX_SPEED

	var acceleration
	if direction.dot(horizontal_velocity) > 0:
		if is_sprinting:
			acceleration = SPRINT_ACCEL
		else:
			acceleration = ACCEL
	else:
		acceleration = DEACCEL

	horizontal_velocity = horizontal_velocity.linear_interpolate(target, acceleration * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity = move_and_slide(velocity, Vector3(0, 1, 0), 0.05, 4, deg2rad(MAX_SLOPE_ANGLE))
	
	# Network
	rpc_unreliable("update_trans_rot", translation, rotation, get_node("head").rotation)

# Sync position and rotation in the network
puppet func update_trans_rot(pos, rot, head_rot):
	translation = pos
	rotation = rot
	get_node("head").rotation = head_rot

# Limited movement
func process_collisions():
	if get_node("col_mouth").disabled:
		can_sprint = false
		can_jump = false
		get_node("stair_catcher").enabled = false
	else:
		can_sprint = true
		can_jump = true
		get_node("stair_catcher").enabled = true

# Footstep sounds
func process_footsteps(delta):
	if has_node('audio/footsteps'):
		footstep_timer += delta
		if is_on_floor() and (abs(movement_vector.x) > 0 or abs(movement_vector.y) > 0):
			var time_between_footstep
			if is_sprinting:
				time_between_footstep = TIME_BETWEEN_FOOTSTEP / 2
			else:
				time_between_footstep = TIME_BETWEEN_FOOTSTEP
			if footstep_timer > time_between_footstep:
				get_node("audio/footsteps").stream = footsteps[randi() % footsteps.size()]
				get_node("audio/footsteps").play(0)
				footstep_timer = 0
			pass
		if is_on_floor() and cmd.jump:
			get_node("audio/footsteps").stream = footstep_land
			get_node("audio/footsteps").play(0)
		if is_on_floor() and velocity.y > 0 and !is_on_stairs:
			get_node("audio/footsteps").stream = footstep_jump
			get_node("audio/footsteps").play(0)

# Stairs
func process_stairs():
	if has_node("stair_catcher") and get_node("stair_catcher").enabled and !is_crouching:
		get_node("stair_catcher").translation.x = movement_vector.x
		get_node("stair_catcher").translation.z = -movement_vector.y
		if movement_vector.length() > 0 and get_node("stair_catcher").is_colliding():
			var stair_normal = get_node("stair_catcher").get_collision_normal()
			var stair_angle = rad2deg(acos(stair_normal.dot(Vector3.UP)))
			if stair_angle < MAX_STAIR_SLOPE:
				velocity.y = STAIR_JUMP_HEIGHT
				is_on_stairs = true
		else:
			is_on_stairs = false

# Landing
func process_landing(delta):
	if !is_on_floor():
		is_landing = true
		time_in_air += delta
	if is_landing and is_on_floor():
		if has_node("audio/land"):
			get_node("audio/land").play()
		if time_in_air > 2:
			hit(50, global_transform.origin.normalized())
		is_landing = false
		time_in_air = 0

# Check for weapons
remotesync func check_weapons():
	var weapons = get_node("head/holder/weapon").get_children()
	if weapons.size() > 0:
		equipped_weapon = weapons[0]

# Hit
remotesync func hit(damage, knockback):
	set_health(health - damage)
	velocity = knockback

# Death
remotesync func die():
	if !is_dead:
		# Sound
		if has_node("audio/hurt"):
			get_node("audio/hurt").play()
		
		if equipped_weapon != null:
			equipped_weapon.rpc("drop")
		
		# Gibs
		var gib_1 = scn_gib_1.instance()
		get_tree().root.add_child(gib_1)
		gib_1.global_transform.origin = global_transform.origin
		gib_1.rotation = rotation
		var gib_2 = scn_gib_2.instance()
		get_tree().root.add_child(gib_2)
		gib_2.global_transform.origin = global_transform.origin
		gib_2.rotation = rotation
		
		visible = false
		is_dead = true
		get_node("timer_respawn").start()

# Respawn
func _on_timer_respawn_timeout():
	rpc("respawn")

remotesync func respawn():
	is_dead = false
	set_health(100)
	velocity = Vector3()
	global_transform.origin = get_tree().root.get_node("world").get_node("spawn_points").get_child(randi() % get_tree().root.get_node("world").get_node("spawn_points").get_child_count()).global_transform.origin
	visible = true
	get_node("suzanne/ear_L").visible = true
	get_node("col_ear_L").disabled = false
	get_node("suzanne/eye_L").visible = true
	get_node("col_eye_L").disabled = false
	get_node("suzanne/eye_R").visible = true
	get_node("col_eye_R").disabled = false
	get_node("suzanne/ear_R").visible = true
	get_node("col_ear_R").disabled = false
	get_node("suzanne/mouth").visible = true
	get_node("col_mouth").disabled = false

# Set Health
func set_health(value):
	health = value
	emit_signal("health_changed", health)
	if health <= 0 and !is_dead:
		rpc("die")

# Health changed signal
func _on_health_changed(value):
	if has_node("hud/health"):
		get_node("hud/health").text = "HEALTH: " + str(value)
