class_name Outfits
extends RefCounted
## Civilian / suspect clothing table. The civilian model has material slots top, sleeve, bottom, legs, skin, hair, cap, visor;
## an outfit recolours them (short sleeves/shorts = sleeve/legs use the skin colour).

const SKIN_TONES: Array[Color] = [
	Color("D6A583"), Color("E8BE9C"), Color("B98263"), Color("8D5A3F"), Color("EAC8A8"),
]

# top, bottom: clothing colours; long_sleeves / shorts: bool; hair: "short"/"long"/"none"; cap: "" or colour
const TABLE := {
	&"purple_sweater": {"top": "7A4A9A", "bottom": "17181B", "long_sleeves": true, "shorts": true, "hair": "short", "hair_color": "2A211C", "cap": ""},
	&"red_shirt_blue_shorts": {"top": "B8302A", "bottom": "2F5FA8", "long_sleeves": false, "shorts": true, "hair": "short", "hair_color": "4A3324", "cap": ""},
	&"maroon_runner": {"top": "7A2430", "bottom": "202226", "long_sleeves": true, "shorts": false, "hair": "short", "hair_color": "1A1512", "cap": ""},
	&"orange_driver": {"top": "E8962A", "bottom": "3B4A5E", "long_sleeves": false, "shorts": false, "hair": "short", "hair_color": "5A4630", "cap": ""},
	&"white_shirt": {"top": "E4E2DA", "bottom": "2A2D33", "long_sleeves": false, "shorts": false, "hair": "short", "hair_color": "8A8A8A", "cap": ""},
	&"green_hoodie": {"top": "3E6B4A", "bottom": "3C5A86", "long_sleeves": true, "shorts": false, "hair": "none", "hair_color": "2A211C", "cap": "2B2B30"},
	&"grey_tee_cap": {"top": "8A8D93", "bottom": "9C8A63", "long_sleeves": false, "shorts": false, "hair": "none", "hair_color": "2A211C", "cap": "3A4A6B"},
	&"yellow_top": {"top": "E3C13B", "bottom": "3C5A86", "long_sleeves": false, "shorts": false, "hair": "long", "hair_color": "6B4226", "cap": ""},
	&"teal_jacket": {"top": "2F7F86", "bottom": "1B1C20", "long_sleeves": true, "shorts": false, "hair": "long", "hair_color": "1A1512", "cap": ""},
	&"denim_plaid": {"top": "A04A3A", "bottom": "46689A", "long_sleeves": true, "shorts": false, "hair": "short", "hair_color": "3A2A1E", "cap": ""},
}

const SUSPECTS: Array[StringName] = [&"purple_sweater", &"red_shirt_blue_shorts", &"maroon_runner", &"orange_driver"]


static func names() -> Array:
	return TABLE.keys()


static func apply(model: Node, outfit: StringName, skin_index: int = 0) -> void:
	var data: Dictionary = TABLE.get(outfit, TABLE[&"white_shirt"])
	var skin: Color = SKIN_TONES[skin_index % SKIN_TONES.size()]
	var top := Color(String(data["top"]))
	var bottom := Color(String(data["bottom"]))
	var colors := {
		&"skin": skin,
		&"top": top,
		&"sleeve": top if bool(data["long_sleeves"]) else skin,
		&"bottom": bottom,
		&"legs": skin if bool(data["shorts"]) else bottom,
		&"hair": Color(String(data["hair_color"])),
	}
	if String(data["cap"]) != "":
		colors[&"cap"] = Color(String(data["cap"]))
		colors[&"visor"] = Color(String(data["cap"])).darkened(0.35)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null or not colors.has(StringName(source.resource_name)):
				continue
			var material := source.duplicate() as StandardMaterial3D
			material.albedo_color = colors[StringName(source.resource_name)]
			mesh_instance.set_surface_override_material(i, material)
	_set_visible(model, "Hair_Short", data["hair"] == "short")
	_set_visible(model, "Hair_Long", data["hair"] == "long")
	_set_visible(model, "Cap", String(data["cap"]) != "")


static func _set_visible(model: Node, node_name: String, value: bool) -> void:
	var node := model.find_child(node_name, true, false) as Node3D
	if node != null:
		node.visible = value
