class_name AimModifier
extends SkeletonModifier3D
## Pitches the spine/chest/head by the camera pitch so a held weapon follows the aim direction.
## `pitch` is in radians, positive = looking up.

const SPINE_SHARE := {&"Spine": 0.45, &"Chest": 0.45, &"Head": 0.10}

var pitch: float = 0.0
var weight: float = 0.0   # 0 = off (unarmed), 1 = full follow


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or absf(pitch * weight) < 0.0005:
		return
	for bone_name: StringName in SPINE_SHARE:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var global_rest := skeleton.get_bone_global_rest(idx).basis.orthonormalized()
		var delta := Basis(Vector3.RIGHT, pitch * weight * float(SPINE_SHARE[bone_name]))
		var q := (global_rest.inverse() * delta * global_rest).get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * q)
