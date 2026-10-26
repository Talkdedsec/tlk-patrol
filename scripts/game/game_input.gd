extends RefCounted
## Input actions that only the integration layer uses (registered in code so project.godot stays untouched).
## Keys that are our own choice are marked TODO(tahmin); the full control list is in docs/api/game.md.

const KEYS := {
	"handbrake": KEY_SPACE,      # hand brake while driving
	"exit_vehicle": KEY_F,       # get out (TrafficStop registers the same action for the traffic stop flow)
	"els_lights": KEY_Q,         # TODO(tahmin): emergency lights on/off
	"els_siren": KEY_X,          # TODO(tahmin): next siren tone (wail, yelp, ... then off)
	"horn": KEY_H,               # TODO(tahmin): hold = A/H horn
	"headlights": KEY_L,         # TODO(tahmin): headlights on/off
	"debug_alpr": KEY_F9,        # debug: ALPR hit on the car ahead (starts a pursuit or a stop)
	"radar_toggle": KEY_V,       # TODO(tahmin): speed gun on/off
	"radar_lock": KEY_G,         # TODO(tahmin): lock the front radar reading
	"alpr_toggle": KEY_P,        # TODO(tahmin): plate reader on/off ("Plate reader off" toast)
}

## Alt frees / re-captures the mouse so the ELS panel can be clicked (checked by key code, not as an action).
const FREE_MOUSE_KEY := KEY_ALT


static func register() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[action] as Key
		InputMap.action_add_event(action, event)
