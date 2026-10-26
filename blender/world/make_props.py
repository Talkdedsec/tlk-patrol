"""Generates the low-poly street props used by the world builder.

Run: blender -b --factory-startup --python blender/world/make_props.py
Output: assets/models/world/<name>.glb (Y-up, metres). Original geometry, flat shaded.
Front of every prop faces +Z in the exported glTF (Blender -Y).
"""
import math
import os

import bmesh
import bpy

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "world"))
os.makedirs(OUT, exist_ok=True)

_mats = {}


def mat(name, color, rough=0.9, emit=None):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    _mats[name] = m
    return m


def hexc(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # sRGB -> linear
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)
    _mats.clear()


def finish(obj_list, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obj_list:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj_list[0]
    if len(obj_list) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")  # keep the model origin at the ground point
    obj.name = name
    for p in obj.data.polygons:
        p.use_smooth = False
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print("WROTE", path, len(obj.data.vertices), "verts")


def box(center, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(material)
    return o


def cyl(center, radius, depth, material, verts=8, rot=(0, 0, 0), r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=center, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=r2, depth=depth, location=center, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(material)
    return o


def ico(center, radius, material, subdiv=1, squash=1.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=center)
    o = bpy.context.active_object
    o.scale = (1, 1, squash)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(material)
    return o


def street_lamp():
    reset()
    steel = mat("lamp_steel", hexc("#4A4D52"))
    head = mat("lamp_head", hexc("#2E3035"))
    glow = mat("lamp_glow", hexc("#E8E4DA"), emit=hexc("#F2EEE4"))
    parts = [cyl((0, 0, 4.25), 0.11, 8.5, steel, 8, r2=0.075)]
    # Arm points +X: two angled segments, flat head at the end (bent arm, flat luminaire).
    parts.append(cyl((0.55, 0, 8.72), 0.05, 1.3, steel, 6, rot=(0, math.radians(90 - 12), 0)))
    parts.append(cyl((1.55, 0, 8.98), 0.05, 1.0, steel, 6, rot=(0, math.radians(90), 0)))
    parts.append(box((2.0, 0, 8.92), (1.0, 0.38, 0.14), head))
    parts.append(box((2.0, 0, 8.84), (0.84, 0.3, 0.03), glow))
    finish(parts, "street_lamp")


def jitter(obj, amount, seed):
    """Perturb vertices a little so low-poly foliage looks hand made instead of perfectly regular."""
    import random
    rnd = random.Random(seed)
    for v in obj.data.vertices:
        v.co.x += rnd.uniform(-amount, amount)
        v.co.y += rnd.uniform(-amount, amount)
        v.co.z += rnd.uniform(-amount, amount) * 0.6
    return obj


def pine_tree():
    reset()
    bark = mat("bark", hexc("#5A4636"))
    dark = mat("pine_dark", hexc("#3E6B3A"))
    light = mat("pine_light", hexc("#52844A"))
    parts = [cyl((0, 0, 1.0), 0.2, 2.0, bark, 6)]
    tiers = ((2.2, 2.7, 3.4), (4.2, 2.3, 3.2), (6.1, 1.9, 3.0), (7.9, 1.45, 2.8), (9.5, 1.0, 2.6), (10.9, 0.55, 2.0))
    for i, (z, r, h) in enumerate(tiers):
        parts.append(jitter(cyl((0, 0, z + h / 2 - 0.3), r, h, light if i % 2 else dark, 8, r2=0.03), 0.18, 10 + i))
    finish(parts, "pine_tree")


def round_tree():
    reset()
    bark = mat("bark", hexc("#5A4636"))
    dark = mat("leaf_dark", hexc("#3C6A30"))
    light = mat("leaf_light", hexc("#5A8E40"))
    parts = [cyl((0, 0, 1.7), 0.24, 3.4, bark, 6, r2=0.17),
             cyl((0.5, 0.2, 4.2), 0.1, 2.4, bark, 5, rot=(0.3, 0.5, 0))]
    blobs = ((0.0, 0.0, 5.6, 2.7, dark), (1.9, 0.6, 5.9, 2.0, dark), (-1.8, -0.5, 6.0, 2.1, dark),
             (0.3, -1.8, 5.8, 2.0, dark), (0.2, 0.3, 7.2, 2.2, light), (1.4, 0.8, 7.0, 1.6, light),
             (-1.3, -0.2, 6.9, 1.7, light))
    for i, (x, y, z, r, m) in enumerate(blobs):
        parts.append(jitter(ico((x, y, z), r, m, 1, 0.82), 0.2, 30 + i))
    finish(parts, "round_tree")


def hydrant():
    reset()
    red = mat("hydrant_red", hexc("#B4231E"))
    cap = mat("hydrant_cap", hexc("#8E1A16"))
    parts = [cyl((0, 0, 0.35), 0.15, 0.7, red, 8), cyl((0, 0, 0.74), 0.17, 0.1, cap, 8),
             cyl((0, 0, 0.82), 0.1, 0.12, red, 8, r2=0.05),
             cyl((0.15, 0, 0.5), 0.06, 0.2, cap, 6, rot=(0, math.radians(90), 0)),
             cyl((-0.15, 0, 0.5), 0.06, 0.2, cap, 6, rot=(0, math.radians(90), 0)),
             cyl((0, -0.15, 0.45), 0.07, 0.16, cap, 6, rot=(math.radians(90), 0, 0))]
    finish(parts, "hydrant")


def stop_sign():
    reset()
    steel = mat("sign_post", hexc("#8A8D92"))
    white = mat("sign_white", hexc("#F2F2F2"))
    red = mat("sign_red", hexc("#C8161D"))
    parts = [cyl((0, 0, 1.3), 0.03, 2.6, steel, 6)]
    # octagon plates face -Y in Blender (+Z in glTF)
    parts.append(cyl((0, -0.035, 2.35), 0.4, 0.02, white, 8, rot=(math.radians(90), 0, math.radians(22.5))))
    parts.append(cyl((0, -0.05, 2.35), 0.36, 0.02, red, 8, rot=(math.radians(90), 0, math.radians(22.5))))
    finish(parts, "stop_sign")


def signal_mast():
    reset()
    steel = mat("signal_steel", hexc("#3E4146"))
    housing = mat("signal_housing", hexc("#1B1C1F"))
    # Arm extends towards -X (to the driver's left when the heads face +Z).
    parts = [cyl((0, 0, 3.0), 0.13, 6.0, steel, 8, r2=0.1),
             box((-3.6, 0, 6.0), (7.2, 0.14, 0.14), steel)]
    for x in (-2.6, -5.8):
        parts.append(box((x, 0, 5.45), (0.42, 0.3, 1.2), housing))
        parts.append(box((x, -0.0, 6.0), (0.06, 0.06, 0.3), steel))
    finish(parts, "signal_mast")


def guardrail():
    reset()
    steel = mat("rail_steel", hexc("#A7ABB0"))
    post = mat("rail_post", hexc("#5A5D62"))
    parts = [box((0, 0, 0.55), (4.0, 0.06, 0.32), steel)]
    for x in (-2.0, 0.0, 2.0):
        parts.append(box((x, 0.1, 0.4), (0.1, 0.1, 0.8), post))
    finish(parts, "guardrail")


def mailbox():
    reset()
    steel = mat("mail_post", hexc("#5B5E63"))
    blue = mat("mail_blue", hexc("#2E4A7A"))
    parts = [cyl((0, 0, 0.55), 0.04, 1.1, steel, 6), box((0, 0, 1.2), (0.2, 0.42, 0.22), blue)]
    finish(parts, "mailbox")


for fn in (street_lamp, pine_tree, round_tree, hydrant, stop_sign, signal_mast, guardrail, mailbox):
    fn()
