extends BaseCharacter

const MOUSE_SENSITIVITY = 0.05

onready var head = get_node("head")
onready var camera = get_node("head/camera")

# Headbob
const BOB_SPEED = 7
const BOB_SPEED_SPRINT = 14
const BOB_SPEED_CROUCH = 4
var transition_speed = 20
var bob_amount = 0.05
var bob_timer = PI / 2
var rest_pos = Vector3()
var cam_pos = Vector3()

# FOV
onready var INITIAL_FOV = camera.fov
const SPRINT_FOV = 90

func _ready():
	if(is_network_master()):
		camera.current = true
		get_node("hud/health").visible = true
		get_node("hud/cross").visible = true
		get_node("hud/displace").visible = true
		for m in get_node("suzanne").get_children():
			m.set_layer_mask_bit(0, false)
			m.set_layer_mask_bit(10, true)
			
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	if(is_network_master()):
		process_input(delta)
		process_headbob(delta)
		process_fov(delta)
		process_screen_glitch(delta)

func process_input(delta):
	# Capturing the cursor
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Walking
	if Input.is_action_pressed("move_forward"):
		cmd.forward = 1
	if Input.is_action_just_released("move_forward"):
		cmd.forward = 0
	if Input.is_action_pressed("move_backward"):
		cmd.forward = -1
	if Input.is_action_just_released("move_backward"):
		cmd.forward = 0
	if Input.is_action_pressed("move_left"):
		cmd.right = -1
	if Input.is_action_just_released("move_left"):
		cmd.right = 0
	if Input.is_action_pressed("move_right"):
		cmd.right = 1
	if Input.is_action_just_released("move_right"):
		cmd.right = 0

	# Jumping
	if Input.is_action_pressed("jump"):
		cmd.jump = true
	if Input.is_action_just_released("jump"):
		cmd.jump = false

	# Sprinting
	if Input.is_action_pressed("sprint"):
		cmd.sprint = true
	if Input.is_action_just_released("sprint"):
		cmd.sprint = false

	if Input.is_action_pressed("kill"):
		cmd.kill = true
	if Input.is_action_just_released("kill"):
		cmd.kill = false
	
	# Dealing with weapons
	if equipped_weapon != null:
		if Input.is_action_pressed("lmb"):
			cmd.fire = true
		if Input.is_action_just_released("lmb"):
			cmd.fire = false
		if Input.is_action_pressed("reload"):
			cmd.reload = true
		if Input.is_action_just_released("reload"):
			cmd.reload = false
		if Input.is_action_pressed("drop"):
			cmd.drop = true
		if Input.is_action_just_released("drop"):
			cmd.drop = false
	else:
		cmd.fire = false
		cmd.reload = false
		cmd.drop = false

# FOV
func process_fov(delta):
	camera.fov += (INITIAL_FOV - camera.fov) * 5 * delta
	if is_sprinting and direction.dot(velocity) > 0:
		camera.fov += (SPRINT_FOV - camera.fov) * 5 * delta

# Headbob
func process_headbob(delta):
	if is_on_floor() and direction.dot(velocity) > 0:
		var bob_speed = BOB_SPEED
		if is_sprinting:
			bob_speed = BOB_SPEED_SPRINT
		bob_timer += bob_speed * delta
		var new_pos = Vector3(cos(bob_timer) * bob_amount, rest_pos.y + abs((sin(bob_timer) * bob_amount)), rest_pos.z)
		cam_pos = new_pos
	else:
		bob_timer = PI / 2
		var new_pos = Vector3(lerp(cam_pos.x, rest_pos.x, transition_speed * delta), lerp(cam_pos.y, rest_pos.y, transition_speed * delta), lerp(cam_pos.z, rest_pos.z, transition_speed * delta))
		cam_pos = new_pos
	if bob_timer > PI * 2:
		bob_timer = 0
	camera.transform.origin += (cam_pos - camera.transform.origin) * 5 * delta

# Screen glitch effect
func process_screen_glitch(delta):
	if get_node("col_eye_L").disabled or get_node("col_eye_R").disabled:
		get_node("hud/displace").get_material().set_shader_param('dispAmt', 0.0025)
		get_node("hud/displace").get_material().set_shader_param('abberationAmtX', 0.005)
		get_node("hud/displace").get_material().set_shader_param('abberationAmtY', 0.005)
	else:
		get_node("hud/displace").get_material().set_shader_param('dispAmt', 0)
		get_node("hud/displace").get_material().set_shader_param('abberationAmtX', 0)
		get_node("hud/displace").get_material().set_shader_param('abberationAmtY', 0)

# Landing camera shake
func process_landing(delta):
	.process_landing(delta)
	if is_landing and is_on_floor():
		if time_in_air > 2:
			camera.shake(time_in_air / 50, 0.25)

# Hit
remotesync func hit(damage, knockback):
	.hit(damage, knockback)
	if(is_network_master()):
		if has_node("audio/hurt"):
			get_node("audio/hurt").play()
		# Displace effect
		get_node("hud/displace").get_material().set_shader_param('dispAmt', knockback.x / 250)
		get_node("hud/displace").get_material().set_shader_param('abberationAmtX', knockback.x / 250)
		get_node("hud/displace").get_material().set_shader_param('abberationAmtY', knockback.y / 250)

# Input events
func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and is_network_master():
		head.rotate_x(deg2rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		self.rotate_y(deg2rad(event.relative.x * MOUSE_SENSITIVITY * -1))
		var camera_rot = head.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, -70, 70)
		head.rotation_degrees = camera_rot
