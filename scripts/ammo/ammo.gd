extends Area

var player

func _ready():
	connect("body_entered", self, "_on_body_entered")
	pass

func _on_body_entered(body):
	player = body
	rpc("pick_ammo")

remotesync func pick_ammo():
	if player != null:
		if player is BaseCharacter:
			if player.equipped_weapon != null:
				player.equipped_weapon.get_node("audio/ammo").play()
				player.equipped_weapon.set_ammo_supply(player.equipped_weapon.ammo_supply + 32)
				get_parent().queue_free()
