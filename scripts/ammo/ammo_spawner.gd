extends Position3D

var ammo_near = false
onready var scn_ammo = preload("res://scenes/ammo/ammo.tscn")
onready var regex = RegEx.new()	

func _ready():
	regex.compile("ammo")
	get_node("timer").connect("timeout", self, "_on_timeout")
	get_node("area").connect("body_entered", self, "_on_body_entered")
	get_node("area").connect("body_exited", self, "_on_body_exited")
	rpc("spawn")
	pass
	
remotesync func spawn():
	if !ammo_near:
		var ammo = scn_ammo.instance()
		ammo.global_transform.origin = global_transform.origin
		get_tree().root.add_child(ammo)
		get_node("spawn").play()
	get_node("timer").start()
	
func _on_timeout():
	rpc("spawn")
	pass

func _on_body_entered(body):
	if body is RigidBody:
		var result = regex.search(str(body.name))
		if result:
			ammo_near = true
	pass

func _on_body_exited(body):
	if body is RigidBody:
		var result = regex.search(str(body.name))
		if result:
			ammo_near = false
	pass
