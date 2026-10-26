extends "res://scripts/dev/scenario_base.gd"
## Pipeline smoke test: drives the HUD through a few states.


func _init() -> void:
	duration = 3.2
	shots = [0.4, 1.5, 2.6]


func setup(main_scene: Node) -> void:
	super(main_scene)
	at(0.5, func() -> void: hud().set_weapon_line("Pistol", 17, 34))
	at(1.0, func() -> void: hud().set_emergency(true))
	at(2.0, func() -> void: hud().set_foot_chase(61.0))
