"""Builds the character models, props and the shared animation set.

Run:  blender.exe -b --factory-startup --python blender/characters/build_characters.py [-- models|props|anims|all]
Outputs (assets/models/characters/): officer_police.glb, officer_sheriff.glb, civilian.glb, props.glb, animations.glb
All character glbs share the same skeleton, so one AnimationLibrary (animations.glb) drives every model.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "characters")

import rig  # noqa: E402
import meshes as M  # noqa: E402

M.set_bpy(bpy)

PALETTE = {
    "skin": "#D6A583", "hair": "#2A211C", "eye": "#15110F",
    "gear": "#14161A", "plate": "#0F1218", "text": "#ECECEC", "badge": "#D4AF37",
    "shoes": "#0E0F12",
}
POLICE = {"shirt": "#222B47", "pants": "#1C2338", "vest": "#1F2844", "cap": "#1B2238", "visor": "#0F1320"}
SHERIFF = {"shirt": "#7A7452", "pants": "#4A4733", "vest": "#26291F", "cap": "#2D3A2A", "visor": "#1B2417"}
CIVILIAN = {"top": "#7A4A9A", "sleeve": "#7A4A9A", "bottom": "#1A1A1C", "legs": "#1A1A1C", "cap": "#4A5A8A", "visor": "#2A3556"}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rig.B_REST.clear()
    sc = bpy.context.scene
    sc.render.fps = 60
    sc.unit_settings.system = "METRIC"


def make_materials(table):
    for name, col in table.items():
        M.make_material(bpy, name, col)


def finish_skinned(builder, name, arm_obj, materials):
    obj = builder.to_object(bpy, name, materials, rig.DEFORM)
    obj.parent = arm_obj
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    return obj


def export(path, selected=None, animations=False):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in selected if selected is not None else bpy.data.objects:
        ob.select_set(True)
    kwargs = dict(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False,
        export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
    )
    if animations:
        kwargs.update(export_animations=True, export_animation_mode="NLA_TRACKS",
                      export_force_sampling=True, export_optimize_animation_size=True)
    else:
        kwargs.update(export_animations=False)
    bpy.ops.export_scene.gltf(**kwargs)
    print("EXPORTED", path)


# --- model variants ----------------------------------------------------------------------------------
def build_officer(kind):
    reset()
    colors = POLICE if kind == "police" else SHERIFF
    text = "POLICE" if kind == "police" else "SHERIFF"
    table = dict(PALETTE)
    table.update(colors)
    make_materials(table)
    arm = rig.create_armature(bpy)
    b = M.Builder()
    M.build_torso(b, "pants", "shirt")
    M.build_neck_head(b, "skin", "eye")
    M.build_legs(b, "pants", "pants", "shoes", split_z=0.5)
    M.build_arms(b, "shirt", "shirt", "skin", split_z=1.19)
    M.build_vest(b, "vest", "plate", "text", text, "badge")
    M.build_belt_gear(b, "gear", "badge")
    M.build_cap(b, "cap", "visor")
    mats = ["skin", "eye", "shirt", "pants", "shoes", "vest", "plate", "text", "badge", "gear", "cap", "visor"]
    obj = finish_skinned(b, "Body", arm, mats)
    export(os.path.join(OUT, "officer_%s.glb" % kind), [arm, obj])


def build_civilian():
    reset()
    table = dict(PALETTE)
    table.update(CIVILIAN)
    make_materials(table)
    arm = rig.create_armature(bpy)
    b = M.Builder()
    M.build_torso(b, "bottom", "top")
    M.build_neck_head(b, "skin", "eye")
    M.build_legs(b, "bottom", "legs", "shoes", split_z=0.68)
    M.build_arms(b, "top", "sleeve", "skin", split_z=1.19)
    mats = ["skin", "eye", "top", "bottom", "legs", "sleeve", "shoes"]
    body = finish_skinned(b, "Body", arm, mats)
    objs = [arm, body]
    for name, fn, mat in (("Hair_Short", M.build_hair_short, "hair"), ("Hair_Long", M.build_hair_long, "hair")):
        hb = M.Builder()
        fn(hb, mat)
        objs.append(finish_skinned(hb, name, arm, [mat]))
    cb = M.Builder()
    M.build_cap(cb, "cap", "visor", brim=0.07)
    objs.append(finish_skinned(cb, "Cap", arm, ["cap", "visor"]))
    export(os.path.join(OUT, "civilian.glb"), objs)


def main():
    what = "all"
    if "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1:]
        if rest:
            what = rest[0]
    os.makedirs(OUT, exist_ok=True)
    if what in ("all", "models"):
        build_officer("police")
        build_officer("sheriff")
        build_civilian()
    if what in ("all", "props"):
        import props
        props.build(bpy, OUT, export, reset, make_materials)
    if what in ("all", "anims"):
        import anims
        anims.build(bpy, OUT, export, reset, rig)


main()
