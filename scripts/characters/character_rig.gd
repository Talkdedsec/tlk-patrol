class_name CharacterRig
extends Node3D
## Skinned humanoid model + layered animation tree shared by Officer and Npc.
##
## Layers (bottom -> top):  locomotion (idle/walk/run/strafe)  <-  upper-body stance/overlay (weapon, hands up...)
##                          <-  full-body action (death, kneel, cuffed, vehicle seat...).
## Weapon logic lives in the Weapons autoload; this class only plays poses and moves the prop between hand and home socket.

signal weapon_state_changed(state: StringName)
signal full_finished(anim: StringName)

const ANIM_GLB := "res://assets/models/characters/animations.glb"
const ANIM_META := "res://assets/models/characters/animations.json"
const PROPS_GLB := "res://assets/models/characters/props.glb"
const SKELETON_PATH := "Armature/Skeleton3D"

const WALK_REF_SPEED := 1.7      # m/s the walk cycle was authored for
const RUN_REF_SPEED := 4.57      # 15 ft/s, FOOT CHASE series
const RUN_THRESHOLD := 3.1

const UPPER_BONES: Array[StringName] = [
	&"Spine", &"Chest", &"Neck", &"Head",
	&"Shoulder_R", &"UpperArm_R", &"LowerArm_R", &"Hand_R",
	&"Shoulder_L", &"UpperArm_L", &"LowerArm_L", &"Hand_L",
]
const LOCO_ANIMS: Array[StringName] = [
	&"idle", &"walk", &"run", &"walk_back", &"strafe_l", &"strafe_r", &"run_strafe_l", &"run_strafe_r",
]
# weapon id -> stance prefix, prop node (props.glb), home socket, seconds into draw/holster when the prop changes hands, muzzle distance
const WEAPONS := {
	&"pistol": {"prefix": "pistol", "prop": "Pistol", "home": "Socket_Holster_R", "grab": 0.27, "release": 0.52, "holster": "holster", "muzzle": 0.19},
	&"taser": {"prefix": "pistol", "prop": "Taser", "home": "Socket_Holster_R", "grab": 0.27, "release": 0.52, "holster": "holster", "muzzle": 0.21},
	&"rifle": {"prefix": "rifle", "prop": "PatrolRifle", "home": "Socket_Back", "grab": 0.10, "release": 0.75, "holster": "sling", "muzzle": 0.70},
	&"shotgun": {"prefix": "shotgun", "prop": "Shotgun", "home": "Socket_Back", "grab": 0.10, "release": 0.75, "holster": "sling", "muzzle": 0.73},
}
const PROP_HOME_FLASHLIGHT := "Socket_Belt_L"
# Props are authored with forward = bone Y, up = bone Z (Blender axes); the imported bone frames need this +90 degree X turn.
const PROP_TO_BONE := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)

static var _library: AnimationLibrary
static var _meta: Dictionary = {}
static var _props_scene: PackedScene

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree
var aim_modifier: AimModifier

var weapon: StringName = &""                  # currently drawn / carried-in-hand weapon id
var weapon_state: StringName = &"unarmed"     # unarmed drawing ready raising aiming lowering holstering reloading
var loadout: Array[StringName] = []           # weapons shown on the body (holster / back)

var _token: int = 0
var _mix: float = 0.0
var _mix_target: float = 0.0
var _props: Dictionary = {}                   # prop node name -> Node3D
var _attachments: Dictionary = {}             # bone name -> BoneAttachment3D
var _prop_in_hand: Node3D
var _full_active := false
var _full_token: int = 0
var _overlay: StringName = &""


func setup(model_path: String) -> void:
	_load_shared()
	model = (load(model_path) as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.get_node(SKELETON_PATH) as Skeleton3D
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	model.add_child(player)
	player.add_animation_library(&"", _library)
	aim_modifier = AimModifier.new()
	aim_modifier.name = "AimModifier"
	skeleton.add_child(aim_modifier)
	_build_tree()
	_spawn_props()


static func _load_shared() -> void:
	if _library != null:
		return
	var file := FileAccess.open(ANIM_META, FileAccess.READ)
	_meta = JSON.parse_string(file.get_as_text()) as Dictionary
	var source := (load(ANIM_GLB) as PackedScene).instantiate()
	var source_player := source.get_node("AnimationPlayer") as AnimationPlayer
	_library = AnimationLibrary.new()
	for anim_name in source_player.get_animation_list():
		var animation := source_player.get_animation(anim_name).duplicate() as Animation
		var info: Dictionary = _meta.get(String(anim_name), {})
		if info.has("length"):
			animation.length = float(info["length"])
		animation.loop_mode = Animation.LOOP_LINEAR if bool(info.get("loop", false)) else Animation.LOOP_NONE
		_library.add_animation(anim_name, animation)
	source.free()
	_props_scene = load(PROPS_GLB) as PackedScene


static func anim_length(anim_name: StringName) -> float:
	_load_shared()
	return _library.get_animation(anim_name).length if _library.has_animation(anim_name) else 0.0


static func anim_names(group: String) -> Array[StringName]:
	_load_shared()
	var out: Array[StringName] = []
	for key: String in _meta:
		if _meta[key]["group"] == group:
			out.append(StringName(key))
	out.sort()
	return out


# --- animation tree -------------------------------------------------------------------------------------
func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()

	var loco := AnimationNodeTransition.new()
	loco.xfade_time = 0.18
	loco.input_count = LOCO_ANIMS.size()
	for i in LOCO_ANIMS.size():
		var anim_name := LOCO_ANIMS[i]
		loco.set_input_name(i, String(anim_name))
		var node := AnimationNodeAnimation.new()
		if anim_name == &"walk_back":
			node.animation = &"walk"
			node.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
		else:
			node.animation = anim_name
		root.add_node("loco_" + anim_name, node)
	root.add_node("loco", loco)
	for i in LOCO_ANIMS.size():
		root.connect_node("loco", i, "loco_" + LOCO_ANIMS[i])
	var scale_node := AnimationNodeTimeScale.new()
	root.add_node("loco_scale", scale_node)
	root.connect_node("loco_scale", 0, "loco")

	var upper_names := anim_names("upper")
	var upper := AnimationNodeTransition.new()
	upper.xfade_time = 0.12
	upper.allow_transition_to_self = true
	upper.input_count = upper_names.size()
	root.add_node("upper", upper)
	for i in upper_names.size():
		upper.set_input_name(i, String(upper_names[i]))
		var node := AnimationNodeAnimation.new()
		node.animation = upper_names[i]
		root.add_node("up_" + upper_names[i], node)
		root.connect_node("upper", i, "up_" + upper_names[i])

	var mix := AnimationNodeBlend2.new()
	mix.filter_enabled = true
	for bone in UPPER_BONES:
		mix.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)
	root.add_node("upper_mix", mix)
	root.connect_node("upper_mix", 0, "loco_scale")
	root.connect_node("upper_mix", 1, "upper")

	var full_names := anim_names("full")
	var full := AnimationNodeTransition.new()
	full.xfade_time = 0.15
	full.allow_transition_to_self = true
	full.input_count = full_names.size() + 1
	root.add_node("full", full)
	full.set_input_name(0, "layered")
	root.connect_node("full", 0, "upper_mix")
	for i in full_names.size():
		full.set_input_name(i + 1, String(full_names[i]))
		var node := AnimationNodeAnimation.new()
		node.animation = full_names[i]
		root.add_node("fb_" + full_names[i], node)
		root.connect_node("full", i + 1, "fb_" + full_names[i])
	root.connect_node("output", 0, "full")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.tree_root = root
	model.add_child(tree)
	tree.active = true
	_set_param("upper/transition_request", String(upper_names[0]))


func _set_param(path: String, value: Variant) -> void:
	tree.set("parameters/" + path, value)


func _process(delta: float) -> void:
	if tree == null:
		return
	_mix = move_toward(_mix, _mix_target, delta * 9.0)
	_set_param("upper_mix/blend_amount", _mix)
	aim_modifier.weight = _mix if weapon_state in [&"ready", &"raising", &"aiming", &"lowering", &"reloading"] else 0.0


# --- locomotion -------------------------------------------------------------------------------------------
## local_velocity: velocity in the character's own frame (Godot: forward = -Z, right = +X). strafe: allow side/back gaits.
func set_motion(local_velocity: Vector3, strafe: bool = false) -> void:
	var forward := -local_velocity.z
	var lateral := local_velocity.x
	var speed := Vector2(forward, lateral).length()
	var request := &"idle"
	var reference := WALK_REF_SPEED
	if speed > 0.15:
		var run := speed > RUN_THRESHOLD
		reference = RUN_REF_SPEED if run else WALK_REF_SPEED
		if not strafe or (forward > 0.0 and forward >= absf(lateral) * 0.7):
			request = &"run" if run else &"walk"
		elif forward < 0.0 and -forward >= absf(lateral) * 0.7:
			request = &"walk_back"
			reference = WALK_REF_SPEED
		elif lateral > 0.0:
			request = &"run_strafe_r" if run else &"strafe_r"
		else:
			request = &"run_strafe_l" if run else &"strafe_l"
	_set_param("loco/transition_request", String(request))
	_set_param("loco_scale/scale", clampf(speed / reference, 0.4, 1.8) if request != &"idle" else 1.0)


# --- upper-body layer ---------------------------------------------------------------------------------------
func _play_upper(anim_name: StringName) -> float:
	_set_param("upper/transition_request", String(anim_name))
	return anim_length(anim_name)


func _later(delay: float, token: int, callback: Callable) -> void:
	await get_tree().create_timer(delay).timeout
	if token == _token and is_inside_tree():
		callback.call()


func _set_weapon_state(value: StringName) -> void:
	weapon_state = value
	weapon_state_changed.emit(value)


## Holds an upper-body animation (hands_up, hands_head, hands_behind, hands_belt, talk_a, point...) over locomotion.
func set_overlay(anim_name: StringName) -> void:
	_overlay = anim_name
	if weapon_state == &"unarmed":
		_play_upper(anim_name)
		_mix_target = 1.0


func clear_overlay() -> void:
	_overlay = &""
	if weapon_state == &"unarmed":
		_mix_target = 0.0


func is_armed() -> bool:
	return weapon_state != &"unarmed" and weapon_state != &"holstering"


func set_loadout(ids: Array) -> void:
	loadout.clear()
	for id in ids:
		loadout.append(StringName(id))
	for id: StringName in WEAPONS:
		var prop := _props.get(WEAPONS[id]["prop"]) as Node3D
		if prop == null:
			continue
		if id == weapon and _prop_in_hand == prop:
			continue
		if id in loadout:
			_attach(prop, WEAPONS[id]["home"])
		else:
			_detach(prop)


func draw(weapon_id: StringName) -> bool:
	if weapon_state != &"unarmed" or not WEAPONS.has(weapon_id):
		return false
	_token += 1
	var token := _token
	var info: Dictionary = WEAPONS[weapon_id]
	weapon = weapon_id
	_set_weapon_state(&"drawing")
	_mix_target = 1.0
	var length := _play_upper(StringName(info["prefix"] + "_draw"))
	var prop := _props.get(info["prop"]) as Node3D
	_later(float(info["grab"]), token, func() -> void: _to_hand(prop))
	_later(length, token, func() -> void:
		_set_weapon_state(&"ready")
		_play_upper(StringName(info["prefix"] + "_ready")))
	return true


func holster() -> bool:
	if not is_armed():
		return false
	_token += 1
	var token := _token
	var info: Dictionary = WEAPONS[weapon]
	_set_weapon_state(&"holstering")
	var length := _play_upper(StringName(info["prefix"] + "_" + info["holster"]))
	var prop := _props.get(info["prop"]) as Node3D
	_later(float(info["release"]), token, func() -> void:
		_attach(prop, info["home"])
		_prop_in_hand = null)
	_later(length, token, func() -> void:
		weapon = &""
		_set_weapon_state(&"unarmed")
		if _overlay != &"":
			_play_upper(_overlay)
		else:
			_mix_target = 0.0)
	return true


func set_aiming(on: bool) -> void:
	if weapon == &"" or not WEAPONS.has(weapon):
		return
	var prefix: String = WEAPONS[weapon]["prefix"]
	if on and weapon_state == &"ready":
		_token += 1
		var token := _token
		_set_weapon_state(&"raising")
		var length := _play_upper(StringName(prefix + "_raise"))
		_later(length, token, func() -> void:
			_set_weapon_state(&"aiming")
			_play_upper(StringName(prefix + "_aim")))
	elif not on and (weapon_state == &"aiming" or weapon_state == &"raising"):
		_token += 1
		var token := _token
		_set_weapon_state(&"lowering")
		var length := _play_upper(StringName(prefix + "_lower"))
		_later(length, token, func() -> void:
			_set_weapon_state(&"ready")
			_play_upper(StringName(prefix + "_ready")))


## Recoil animation. Returns false when the weapon is not ready/aiming. Pump/rack follows for the shotgun.
func fire() -> bool:
	if weapon_state != &"ready" and weapon_state != &"aiming":
		return false
	_token += 1
	var token := _token
	var prefix: String = WEAPONS[weapon]["prefix"]
	var aiming := weapon_state == &"aiming"
	var length := _play_upper(StringName(prefix + ("_fire" if aiming else "_fire_hip")))
	var rest := StringName(prefix + ("_aim" if aiming else "_ready"))
	_later(length, token, func() -> void: _play_upper(rest))
	return true


func reload() -> bool:
	if weapon_state != &"ready" and weapon_state != &"aiming":
		return false
	var prefix: String = WEAPONS[weapon]["prefix"]
	var anim_name := StringName(prefix + "_reload")
	if anim_length(anim_name) <= 0.0:
		return false
	_token += 1
	var token := _token
	var previous := weapon_state
	_set_weapon_state(&"reloading")
	var length := _play_upper(anim_name)
	_later(length, token, func() -> void:
		_set_weapon_state(previous)
		_play_upper(StringName(prefix + ("_aim" if previous == &"aiming" else "_ready"))))
	return true


func pump() -> float:
	if weapon != &"shotgun":
		return 0.0
	_token += 1
	var token := _token
	var length := _play_upper(&"shotgun_pump")
	_later(length, token, func() -> void: _play_upper(&"shotgun_aim" if weapon_state == &"aiming" else &"shotgun_ready"))
	return length


## Flashlight in the right hand (no weapon logic); toggles with hands_belt-style stance.
func set_flashlight(on: bool) -> void:
	var prop := _props.get("Flashlight") as Node3D
	if prop == null:
		return
	if on:
		_to_hand(prop)
		_play_upper(&"flashlight_hold")
		_mix_target = 1.0
	else:
		_attach(prop, PROP_HOME_FLASHLIGHT)
		_prop_in_hand = null
		if weapon_state == &"unarmed":
			_mix_target = 0.0


func muzzle_transform() -> Transform3D:
	var hand := _attachments.get("Socket_Hand_R") as BoneAttachment3D
	if hand == null or weapon == &"" or not WEAPONS.has(weapon):
		return global_transform
	return hand.global_transform * PROP_TO_BONE * Transform3D(Basis(), Vector3(0.0, 0.0, -float(WEAPONS[weapon]["muzzle"])))


# --- full-body layer ------------------------------------------------------------------------------------------
## Plays a full-body action (death_fall, kneel, cuffed_prone, sit_drive...). The last pose is held for non-looping ones.
func play_full(anim_name: StringName) -> float:
	if not player.has_animation(anim_name):
		push_warning("CharacterRig: unknown animation %s" % anim_name)
		return 0.0
	_full_active = true
	_full_token += 1
	var token := _full_token
	_set_param("full/transition_request", String(anim_name))
	var length := anim_length(anim_name)
	if not player.get_animation(anim_name).loop_mode == Animation.LOOP_LINEAR:
		get_tree().create_timer(length).timeout.connect(func() -> void:
			if token == _full_token:
				full_finished.emit(anim_name))
	return length


func release_full() -> void:
	_full_active = false
	_full_token += 1
	_set_param("full/transition_request", "layered")


func is_full_active() -> bool:
	return _full_active


## Aim pitch (radians, up positive) applied to spine/chest/head while a weapon is held.
func set_aim_pitch(value: float) -> void:
	aim_modifier.pitch = value


# --- props ------------------------------------------------------------------------------------------------------
func _spawn_props() -> void:
	var source := _props_scene.instantiate()
	for child in source.get_children():
		var prop := child as Node3D
		source.remove_child(prop)
		prop.owner = null
		_props[String(prop.name)] = prop
	source.free()
	if loadout.is_empty():
		loadout = [&"pistol"]
	set_loadout(loadout)


func _attachment(bone: String) -> BoneAttachment3D:
	var attachment := _attachments.get(bone) as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = "Attach_" + bone
		attachment.bone_name = bone
		skeleton.add_child(attachment)
		_attachments[bone] = attachment
	return attachment


func _attach(prop: Node3D, bone: String) -> void:
	if prop == null:
		return
	if prop.get_parent() != null:
		prop.get_parent().remove_child(prop)
	_attachment(bone).add_child(prop)
	prop.transform = PROP_TO_BONE
	prop.visible = true


func _detach(prop: Node3D) -> void:
	if prop.get_parent() != null:
		prop.get_parent().remove_child(prop)


func _to_hand(prop: Node3D) -> void:
	_attach(prop, "Socket_Hand_R")
	_prop_in_hand = prop


## Debug/screenshot helper: freezes the rig on `anim_name` at `time` (bypasses the tree).
func preview(anim_name: StringName, time: float) -> void:
	tree.active = false
	player.play(anim_name)
	player.seek(time, true)
	player.pause()
