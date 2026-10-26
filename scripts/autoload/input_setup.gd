extends Node
## Registers input actions in code so project.godot stays readable.
## Keys that are our own choice are marked TODO.

const KEYS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"reload": KEY_R,             # "hold R reload"; R is also "order them to drop it" / "request PIT"
	"draw_weapon": KEY_5,        # "5 to draw"
	"weapon_1": KEY_1,           # TODO(tahmin): direct slot keys
	"weapon_2": KEY_2,
	"weapon_3": KEY_3,
	"interact": KEY_E,           # "E  Get in", "E to process them and book the charges"
	"request_backup": KEY_B,     # "B again to clear them"
	"join_chase": KEY_C,         # "C join"
	"call_off": KEY_Z,           # "Z call off"
	"close_menu": KEY_ESCAPE,    # MDT footer: "Tab or Esc to close"
	"toggle_mdt": KEY_TAB,       # TODO(tahmin): opening key
	"debug_emergency": KEY_F1,
	"debug_dispatch": KEY_F2,
	"debug_footchase": KEY_F3,
	"debug_weapon": KEY_F4,
}

const MOUSE := {
	"fire": MOUSE_BUTTON_LEFT,   # "LMB fire"
	"aim": MOUSE_BUTTON_RIGHT,   # "RMB aim"
}


func _ready() -> void:
	for action: String in KEYS:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = KEYS[action] as Key
		_add(action, key_event)
	for action: String in MOUSE:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = MOUSE[action] as MouseButton
		_add(action, mouse_event)


func _add(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)
