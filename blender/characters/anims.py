"""Animation library for the shared humanoid skeleton.

Durations marked [ölçüldü] are tuned values (60 fps frame measurements);
everything else is an estimate and is listed under "Tasarım varsayımları" in docs/api/characters.md.
Upper-body animations key only UPPER_BODY bones so they can be layered over locomotion.
"""
import math
import os
from mathutils import Vector

import rig
from rig import rot, mir, I3, fk, ik_limb, frame_from, B_REST, UPPER_BODY, NAMES

FPS = 60
ALL_BONES = [n for n in NAMES if not n.startswith("Socket")]
FULL = ALL_BONES
UB = list(UPPER_BODY)

SHOULDER = {"R": Vector((0.235, 0, 1.40)), "L": Vector((-0.235, 0, 1.40))}


def side_sign(side):
    return 1.0 if side == "R" else -1.0


class Pose:
    def __init__(self, d=None, loc=None):
        self.d = dict(d or {})
        self.loc = dict(loc or {})

    def copy(self):
        return Pose(self.d, self.loc)

    def e(self, bone, x=0.0, y=0.0, z=0.0):
        self.d[bone] = rot(x, y, z)
        return self

    def sym(self, bone, x=0.0, y=0.0, z=0.0):
        """Right-side Euler, mirrored to the left."""
        self.d[bone + "_R"] = rot(x, y, z)
        self.d[bone + "_L"] = mir(rot(x, y, z))
        return self

    def hips(self, dx=0.0, dy=0.0, dz=0.0):
        self.loc["Hips"] = Vector((dx, dy, dz))
        return self

    def arm(self, side, palm, f=(0, 1, 0), up=(0, 0, 1), hint=None, reach_wrist=False):
        sx = side_sign(side)
        fv = Vector(f).normalized()
        wrist = Vector(palm) if reach_wrist else Vector(palm) - fv * 0.05
        if hint is None:
            hint = (0.45 * sx, -0.35, -1.0)
        ik_limb(self.d, self.loc, "UpperArm_" + side, "LowerArm_" + side, "Hand_" + side,
                wrist, hint, 1.0, frame_from(fv, up))
        return self

    def leg(self, side, ankle, hint=(0, 1, 0.1), foot_pitch=0.0, foot_yaw=0.0):
        ik_limb(self.d, self.loc, "UpperLeg_" + side, "LowerLeg_" + side, "Foot_" + side,
                ankle, hint, -1.0, None)
        pos, acc = fk(self.d, self.loc)
        world = rot(foot_pitch, 0, foot_yaw)
        self.d["Foot_" + side] = acc["LowerLeg_" + side].inverted() @ world
        return self

    def frames(self):
        """World frame helpers for chaining a support hand: returns (palm pos, fwd, up)."""
        pos, acc = fk(self.d, self.loc)
        b = acc["Hand_R"] @ B_REST["Hand_R"]
        return pos["Socket_Hand_R"], b @ Vector((0, 1, 0)), b @ Vector((0, 0, 1))

    def support(self, ahead=0.0, below=0.0, side=0.0, roll=(1, 0, 0.3)):
        """Left hand on the weapon held by the right hand, offsets in weapon axes (meters)."""
        palm, fwd, up = self.frames()
        right = fwd.cross(up)
        target = palm + fwd * ahead + up * (-below) + right * side
        self.arm("L", target, f=fwd, up=roll, hint=(-0.5, -0.3, -1.0))
        return self


def breathe(pose, amount=1.2):
    p = pose.copy()
    p.d["Chest"] = rot(-amount) @ pose.d.get("Chest", I3)
    p.d["Head"] = rot(amount * 0.6) @ pose.d.get("Head", I3)
    return p


class Anim:
    def __init__(self, name, length, bones, keys, loop=False):
        self.name, self.length, self.bones, self.keys, self.loop = name, length, bones, keys, loop


ANIMS = []


def add(name, length, bones, keys, loop=False):
    if loop and keys[-1][0] < length - 1e-6:
        keys = list(keys) + [(length, keys[0][1])]
    ANIMS.append(Anim(name, length, bones, keys, loop))


def hold(name, pose, bones=UB, length=2.0, amount=1.2):
    add(name, length, bones, [(0, pose), (length / 2, breathe(pose, amount)), (length, pose)], loop=True)


# --- base poses -----------------------------------------------------------------------------------
def relaxed():
    p = Pose()
    p.sym("LowerArm", 6)
    p.sym("UpperArm", 2, -3, 0)
    return p


def gait(phase, A, K, arm_swing, elbow, lean, bob, yaw, sway):
    p = Pose()
    for side, off in (("R", 0.0), ("L", math.pi)):
        ph = phase + off
        th = A * math.cos(ph)
        k = K * max(0.0, -math.sin(ph)) + 5.0
        push = -20.0 * max(0.0, math.sin(ph)) * max(0.0, -math.cos(ph)) * 2.0
        p.d["UpperLeg_" + side] = rot(th, 0, 0)
        p.d["LowerLeg_" + side] = rot(-k, 0, 0)
        p.d["Foot_" + side] = rot(-(th - k) + push, 0, 0)
        swing = -arm_swing * math.cos(ph)
        flex = elbow + (0.35 * elbow) * max(0.0, math.sin(ph + math.pi * 0.0)) * 0.0 + 0.2 * elbow * max(0.0, swing / arm_swing if arm_swing else 0)
        sx = side_sign(side)
        p.d["UpperArm_" + side] = rot(swing, -4 * sx, 0)
        p.d["LowerArm_" + side] = rot(flex, 0, 0)
    p.d["Hips"] = rot(0, 0, yaw * math.cos(phase))
    p.d["Spine"] = rot(lean * 0.6, 0, -yaw * 0.6 * math.cos(phase))
    p.d["Chest"] = rot(lean * 0.4, 0, -yaw * 0.7 * math.cos(phase))
    p.d["Head"] = rot(-lean * 0.8, 0, 0)
    p.hips(sway * math.sin(phase), 0, -bob * math.cos(2 * phase))
    return p


def cycle(name, length, steps, **kw):
    keys = []
    for i in range(steps + 1):
        t = length * i / steps
        keys.append((t, gait(2 * math.pi * i / steps, **kw)))
    add(name, length, FULL, keys, loop=True)


def strafe_variant(src_name, name, direction):
    """Legs walk sideways, torso keeps facing forward (hips yawed by -/+90)."""
    src = next(a for a in ANIMS if a.name == src_name)
    keys = []
    for t, pose in src.keys:
        p = pose.copy()
        yaw = -90.0 * direction
        p.d["Hips"] = rot(0, 0, yaw) @ pose.d.get("Hips", I3)
        p.d["Spine"] = rot(0, 0, -yaw / 2) @ pose.d.get("Spine", I3)
        p.d["Chest"] = rot(0, 0, -yaw / 2) @ pose.d.get("Chest", I3)
        loc = Vector(p.loc.get("Hips", Vector()))
        p.loc["Hips"] = Vector((loc.y * direction, loc.x, loc.z))
        keys.append((t, p))
    add(name, src.length, FULL, keys, loop=True)


def idle_keys():
    a = relaxed()
    b = relaxed()
    b.e("Chest", -1.4).e("Head", 1.0).e("Spine", -0.6)
    b.sym("UpperArm", 3, -3.5, 0)
    b.hips(0.004, 0, -0.006)
    b.e("Hips", 0, 1.0, 0.0)
    c = relaxed()
    c.e("Hips", 0, -0.8, 0.0).hips(-0.004, 0, 0.0)
    return [(0, a), (0.8, b), (1.6, c), (2.4, a)]


def build_locomotion():
    add("idle", 2.4, FULL, idle_keys(), loop=True)
    cycle("walk", 1.0, 16, A=27, K=62, arm_swing=22, elbow=14, lean=-2.0, bob=0.014, yaw=5.0, sway=0.012)
    cycle("run", 0.62, 16, A=50, K=104, arm_swing=58, elbow=92, lean=-9.0, bob=0.034, yaw=8.0, sway=0.016)
    strafe_variant("walk", "strafe_r", 1)
    strafe_variant("walk", "strafe_l", -1)
    strafe_variant("run", "run_strafe_r", 1)
    strafe_variant("run", "run_strafe_l", -1)


# --- weapon stances ---------------------------------------------------------------------------------
GUN_UP = (0, 0, 1)


def pistol_aim():
    p = Pose()
    p.e("Spine", -1, 0, -4).e("Chest", -1, 0, -4).e("Head", 3, 0, 8).e("Neck", 1, 0, 4)
    p.arm("R", (0.085, 0.40, 1.60), f=(-0.02, 1, 0.02), up=GUN_UP, hint=(0.5, -0.2, -1))
    p.support(ahead=0.0, below=0.03, side=-0.040, roll=(1, 0, 0.5))
    return p


def pistol_ready():
    p = Pose()
    p.e("Spine", -4, 0, -3).e("Chest", -3, 0, -3).e("Head", 4, 0, 4)
    p.arm("R", (0.10, 0.32, 1.17), f=(0, 1, -0.45), up=(0, 0.45, 1), hint=(0.5, -0.4, -1))
    p.support(ahead=0.0, below=0.03, side=-0.040, roll=(1, 0, 0.5))
    return p


def pistol_chest():
    """Intermediate of the raise: hands at chest height, elbows bent."""
    p = Pose()
    p.e("Spine", -3, 0, -3).e("Chest", -3, 0, -3).e("Head", 3, 0, 6)
    p.arm("R", (0.09, 0.22, 1.38), f=(0, 1, 0.45), up=(0, -0.45, 1), hint=(0.5, -0.4, -1))
    p.support(ahead=0.0, below=0.03, side=-0.040, roll=(1, 0, 0.5))
    return p


def pistol_high():
    """Peak of the raise: gun at head height, forearms upright."""
    p = Pose()
    p.e("Spine", -2, 0, -4).e("Chest", -2, 0, -4).e("Head", 3, 0, 7)
    p.arm("R", (0.08, 0.26, 1.70), f=(0, 1, 0.25), up=(0, -0.25, 1), hint=(0.5, -0.2, -1))
    p.support(ahead=0.0, below=0.03, side=-0.040, roll=(1, 0, 0.5))
    return p


def recoil(pose, kick, rise):
    p = pose.copy()
    p.d["Spine"] = rot(kick * 0.5) @ pose.d.get("Spine", I3)
    p.d["Chest"] = rot(kick * 0.6) @ pose.d.get("Chest", I3)
    p.d["UpperArm_R"] = rot(rise) @ pose.d["UpperArm_R"]
    p.d["UpperArm_L"] = rot(rise) @ pose.d["UpperArm_L"]
    p.d["Head"] = rot(-kick * 0.3) @ pose.d.get("Head", I3)
    return p


def rifle_pose(aim):
    p = Pose()
    if aim:
        p.e("Spine", -2, 0, -12).e("Chest", -1, 0, -14).e("Head", 3, 0, 16).e("Neck", 1, 0, 6)
        p.arm("R", (0.150, 0.300, 1.465), f=(0, 1, 0), up=GUN_UP, hint=(0.6, -0.3, -1))
        p.support(ahead=0.27, below=0.02, side=0.0, roll=(0, 0, 1))
    else:
        p.e("Spine", -5, 0, -10).e("Chest", -3, 0, -10).e("Head", 5, 0, 10)
        p.arm("R", (0.13, 0.20, 1.13), f=(0, 1, -0.6), up=(0, 0.6, 1), hint=(0.6, -0.4, -1))
        p.support(ahead=0.27, below=0.02, side=0.0, roll=(0, 0, 1))
    return p


def shotgun_pose(aim):
    p = Pose()
    if aim:
        p.e("Spine", -2, 0, -12).e("Chest", -1, 0, -14).e("Head", 3, 0, 16).e("Neck", 1, 0, 6)
        p.arm("R", (0.150, 0.280, 1.445), f=(0, 1, 0), up=GUN_UP, hint=(0.6, -0.3, -1))
        p.support(ahead=0.40, below=0.04, side=0.0, roll=(0, 0, 1))
    else:
        p.e("Spine", -5, 0, -10).e("Chest", -3, 0, -10).e("Head", 5, 0, 10)
        p.arm("R", (0.13, 0.20, 1.12), f=(0, 1, -0.6), up=(0, 0.6, 1), hint=(0.6, -0.4, -1))
        p.support(ahead=0.40, below=0.04, side=0.0, roll=(0, 0, 1))
    return p


def sling_pose():
    """Unarmed, long gun on the back sling: right hand hangs near the hip."""
    p = relaxed()
    p.sym("UpperArm", 8, -4, 0)
    p.sym("LowerArm", 20)
    return p


def reach_back_pose(side_ref):
    p = relaxed()
    p.e("Chest", 0, 0, 14).e("Spine", 0, 0, 6)
    p.arm("R", (0.22, -0.20, 1.22), f=(0, -0.5, 1), up=(0, 1, 0.3), hint=(0.6, -0.8, -0.3))
    return p


def build_weapons():
    # --- pistol
    ready = pistol_ready()
    aim = pistol_aim()
    hold("pistol_ready", ready)
    hold("pistol_aim", aim, amount=0.6)
    add("pistol_raise", 0.44, UB, [(0, ready), (0.17, pistol_chest()), (0.30, pistol_high()), (0.44, aim)])   # [ölçüldü] 440 ms
    add("pistol_lower", 0.22, UB, [(0, aim), (0.10, pistol_chest()), (0.22, ready)])                          # tahmin (çıkış 220 ms kamera)
    add("pistol_fire", 0.25, UB, [(0, aim), (0.03, recoil(aim, -4.0, 5.0)), (0.12, recoil(aim, -1.5, 1.5)), (0.25, aim)])
    add("pistol_fire_hip", 0.25, UB, [(0, ready), (0.03, recoil(ready, -3.0, 6.0)), (0.12, recoil(ready, -1.0, 1.5)), (0.25, ready)])
    belt = Pose().e("Chest", 0, 0, 3)
    belt.arm("R", (0.21, 0.02, 0.93), f=(0, 0.2, -1), up=(0, 1, 0.2), hint=(0.8, -0.5, -0.3))
    low = relaxed()
    # draw: hand to holster (0.2), pull (0.35), bring to ready (0.6)
    pull = belt.copy()
    pull.arm("R", (0.21, 0.04, 1.00), f=(0, 0.3, -1), up=(0, 1, 0.3), hint=(0.8, -0.5, -0.3))
    add("pistol_draw", 0.6, UB, [(0, low), (0.18, belt), (0.27, pull), (0.45, pistol_chest()), (0.6, ready)])
    add("pistol_holster", 0.7, UB, [(0, ready), (0.15, belt), (0.45, pull), (0.52, belt), (0.7, low)])      # [ölçüldü] kol ≈150 ms, kılıf ≈0,6 sn
    rel = ready.copy()
    mag = Pose().e("Spine", -4, 0, -3).e("Chest", -3, 0, -3)
    mag.arm("R", (0.10, 0.28, 1.22), f=(0, 1, 0.3), up=(0, -0.3, 1), hint=(0.5, -0.4, -1))
    mag.arm("L", (-0.07, 0.10, 1.03), f=(0, 1, -0.3), up=(1, 0, 0.5), hint=(-0.6, -0.4, -1))
    seat = mag.copy()
    seat.arm("L", (0.08, 0.28, 1.18), f=(0, 1, 0.2), up=(1, 0, 0.5), hint=(-0.6, -0.4, -1))
    add("pistol_reload", 1.7, UB, [(0, ready), (0.25, mag), (0.55, seat), (0.80, seat), (1.1, mag), (1.4, mag), (1.7, ready)])
    # --- rifle
    for w, fn, lens in (("rifle", rifle_pose, dict(raise_t=0.32, lower_t=0.167, draw_t=0.85, fire_t=0.2)),
                        ("shotgun", shotgun_pose, dict(raise_t=0.30, lower_t=0.20, draw_t=0.85, fire_t=0.3))):
        ready = fn(False)
        aim = fn(True)
        hold(w + "_ready", ready)
        hold(w + "_aim", aim, amount=0.5)
        mid = Pose()
        # blend through a lifted intermediate by averaging poses at key time (bezier does the rest)
        add(w + "_raise", lens["raise_t"], UB, [(0, ready), (lens["raise_t"], aim)])
        add(w + "_lower", lens["lower_t"], UB, [(0, aim), (lens["lower_t"], ready)])
        kick = -3.5 if w == "rifle" else -5.0
        add(w + "_fire", lens["fire_t"], UB, [(0, aim), (0.03, recoil(aim, kick, 4.0)), (0.10, recoil(aim, kick * 0.3, 1.0)), (lens["fire_t"], aim)])
        add(w + "_fire_hip", lens["fire_t"], UB, [(0, ready), (0.03, recoil(ready, kick, 5.0)), (0.10, recoil(ready, kick * 0.3, 1.0)), (lens["fire_t"], ready)])
        # draw: sling -> hand grabs (0.1) -> gun at hip (0.35) -> low ready (0.85)    [ölçüldü] 600 + 250 ms
        reach = reach_back_pose(0)
        hip = Pose().e("Chest", 0, 0, -4)
        hip.arm("R", (0.20, 0.10, 1.00), f=(0, 1, -0.8), up=(0, 0.8, 1), hint=(0.8, -0.5, -0.3))
        hip.support(ahead=0.27 if w == "rifle" else 0.40, below=0.02, side=0.0, roll=(0, 0, 1))
        sl = sling_pose()
        add(w + "_draw", 0.85, UB, [(0, sl), (0.10, reach), (0.35, hip), (0.60, hip), (0.85, ready)])
        add(w + "_sling", 0.85, UB, [(0, ready), (0.25, hip), (0.55, hip), (0.75, reach), (0.85, sl)])
    pump_aim = shotgun_pose(True)
    p1 = pump_aim.copy()
    p1.support(ahead=0.30, below=0.04, side=0.0, roll=(0, 0, 1))
    p2 = pump_aim.copy()
    p2.support(ahead=0.46, below=0.04, side=0.0, roll=(0, 0, 1))
    add("shotgun_pump", 0.55, UB, [(0, pump_aim), (0.18, p2), (0.36, p1), (0.55, pump_aim)])
    r_ready = rifle_pose(False)
    r_mag = r_ready.copy()
    r_mag.arm("L", (-0.07, 0.12, 1.05), f=(0, 1, -0.4), up=(1, 0, 0.5), hint=(-0.6, -0.4, -1))
    add("rifle_reload", 2.3, UB, [(0, r_ready), (0.4, r_mag), (0.9, r_mag), (1.4, r_ready), (1.8, r_ready), (2.3, r_ready)])
    s_ready = shotgun_pose(False)
    s_load = s_ready.copy()
    s_load.arm("L", (-0.02, 0.12, 1.08), f=(0, 1, -0.4), up=(1, 0, 0.5), hint=(-0.6, -0.4, -1))
    add("shotgun_reload", 1.0, UB, [(0, s_ready), (0.3, s_load), (0.6, s_load), (1.0, s_ready)])


# --- utility upper-body stances / gestures -----------------------------------------------------------
def build_upper():
    # hands up (surrender), hands on head, hands behind (cuffed), hands on belt, flashlight
    up = Pose().e("Head", 4, 0, 0)
    up.arm("R", (0.20, 0.10, 1.82), f=(0, 0.15, 1), up=(0, -1, 0.15), hint=(0.6, -0.2, -0.6))
    up.arm("L", (-0.20, 0.10, 1.82), f=(0, 0.15, 1), up=(0, -1, 0.15), hint=(-0.6, -0.2, -0.6))
    hold("hands_up", up, amount=0.8)
    head = Pose().e("Head", 6, 0, 0).e("Spine", -2)
    head.arm("R", (0.08, -0.04, 1.72), f=(-0.3, 0.4, 0.5), up=(0, 0, 1), hint=(0.9, -0.4, -0.2))
    head.arm("L", (-0.08, -0.04, 1.72), f=(0.3, 0.4, 0.5), up=(0, 0, 1), hint=(-0.9, -0.4, -0.2))
    hold("hands_head", head, amount=0.8)
    behind = Pose().e("Spine", 0).e("Chest", 3)
    behind.arm("R", (0.035, -0.130, 0.99), f=(-0.2, -0.5, -1), up=(0, 1, -0.3), hint=(0.4, 0.2, -1))
    behind.arm("L", (-0.035, -0.130, 0.99), f=(0.2, -0.5, -1), up=(0, 1, -0.3), hint=(-0.4, 0.2, -1))
    hold("hands_behind", behind, amount=0.8)
    akimbo = Pose()
    akimbo.arm("R", (0.19, 0.075, 1.00), f=(-0.2, 0.2, -1), up=(0, 1, 0), hint=(0.9, -0.3, -0.1))
    akimbo.arm("L", (-0.19, 0.075, 1.00), f=(0.2, 0.2, -1), up=(0, 1, 0), hint=(-0.9, -0.3, -0.1))
    hold("hands_belt", akimbo, amount=0.8)
    # flashlight: light in the right hand at chest height, left hand near the belt
    fl = Pose().e("Spine", -2, 0, -6).e("Chest", -2, 0, -6).e("Head", 3, 0, 8)
    fl.arm("R", (0.16, 0.30, 1.28), f=(0, 1, 0.08), up=GUN_UP, hint=(0.6, -0.4, -1))
    fl.arm("L", (-0.19, 0.075, 1.00), f=(0.2, 0.2, -1), up=(0, 1, 0), hint=(-0.9, -0.3, -0.1))
    hold("flashlight_hold", fl, amount=0.8)
    scan_a, scan_b = fl.copy(), fl.copy()
    scan_a.arm("R", (0.06, 0.32, 1.30), f=(-0.35, 1, 0.08), up=GUN_UP, hint=(0.6, -0.4, -1))
    scan_a.e("Head", 3, 0, 22)
    scan_b.arm("R", (0.24, 0.30, 1.30), f=(0.35, 1, 0.08), up=GUN_UP, hint=(0.6, -0.4, -1))
    scan_b.e("Head", 3, 0, -8)
    add("flashlight_scan", 3.0, UB, [(0, fl), (0.75, scan_a), (1.5, fl), (2.25, scan_b), (3.0, fl)], loop=True)
    # talking gestures
    base = relaxed().copy()
    t0 = Pose().e("Head", 2, 0, 4).e("Chest", 0, 0, 2)
    t0.arm("R", (0.18, 0.28, 1.22), f=(0, 1, 0.3), up=(0, -0.3, 1), hint=(0.8, -0.3, -0.6))
    t0.arm("L", (-0.19, 0.075, 1.00), f=(0.2, 0.2, -1), up=(0, 1, 0), hint=(-0.9, -0.3, -0.1))
    t1 = t0.copy()
    t1.arm("R", (0.22, 0.32, 1.32), f=(0, 1, 0.6), up=(0, -0.6, 1), hint=(0.8, -0.3, -0.6))
    t1.e("Head", 0, 0, -3)
    t2 = t0.copy()
    t2.arm("R", (0.12, 0.30, 1.16), f=(0, 1, 0.0), up=(1, 0, 0.2), hint=(0.8, -0.3, -0.6))
    add("talk_a", 2.4, UB, [(0, t0), (0.6, t1), (1.2, t2), (1.8, t1), (2.4, t0)], loop=True)
    u0 = Pose().e("Head", 2, 0, 0)
    u0.arm("R", (0.20, 0.30, 1.24), f=(0, 1, 0.3), up=(-1, 0, 0.3), hint=(0.8, -0.3, -0.6))
    u0.arm("L", (-0.20, 0.30, 1.24), f=(0, 1, 0.3), up=(1, 0, 0.3), hint=(-0.8, -0.3, -0.6))
    u1 = u0.copy()
    u1.arm("R", (0.26, 0.34, 1.32), f=(0.3, 1, 0.3), up=(-1, 0, 0.3), hint=(0.8, -0.3, -0.6))
    u1.arm("L", (-0.26, 0.34, 1.32), f=(-0.3, 1, 0.3), up=(1, 0, 0.3), hint=(-0.8, -0.3, -0.6))
    add("talk_b", 2.0, UB, [(0, u0), (0.7, u1), (1.4, u0), (2.0, u0)], loop=True)
    pt = Pose().e("Chest", 0, 0, -6).e("Head", 2, 0, -6)
    pt.arm("R", (0.12, 0.50, 1.38), f=(-0.1, 1, 0.05), up=(0, 0, 1), hint=(0.6, -0.3, -1))
    pt.arm("L", (-0.19, 0.075, 1.00), f=(0.2, 0.2, -1), up=(0, 1, 0), hint=(-0.9, -0.3, -0.1))
    add("point", 1.2, UB, [(0, relaxed()), (0.3, pt), (1.2, pt)])
    hold("listen", akimbo, amount=0.6)


# --- full-body states ---------------------------------------------------------------------------------
def prone_pose(arms="spread", head_turn=55.0):
    p = Pose()
    p.e("Hips", -90, 0, 0).hips(0, 0.22, -0.80)
    p.e("Spine", -1).e("Chest", 0).e("Head", 0, 0, head_turn)
    p.sym("UpperLeg", 0, -6, 0).sym("LowerLeg", -6).sym("Foot", 0)
    if arms == "spread":
        p.sym("UpperArm", 155, -35, 0).sym("LowerArm", 35)
    elif arms == "behind":
        pos, acc = fk(p.d, p.loc)
        back = pos["Spine"] + Vector((0, 0.04, 0.10))
        p.arm("R", (0.035, back.y - 0.02, back.z + 0.02), f=(0, -1, 0), up=(0, 0, 1), hint=(0.5, 0.0, 1.0))
        p.arm("L", (-0.035, back.y - 0.02, back.z + 0.02), f=(0, -1, 0), up=(0, 0, 1), hint=(-0.5, 0.0, 1.0))
    elif arms == "sides":
        p.sym("UpperArm", 20, -12, 0).sym("LowerArm", 15)
    return p


def kneel_pose(hands="head"):
    p = Pose()
    p.hips(0, 0.02, -0.46)
    p.sym("UpperLeg", -4, -4, 0).sym("LowerLeg", -98).sym("Foot", 0)
    p.e("Spine", -2).e("Head", 4)
    if hands == "head":
        p.arm("R", (0.08, -0.03, 1.38 + 0.0 - 0.46 + 0.46), f=(-0.3, 0.4, 0.5), up=(0, 0, 1), hint=(0.9, -0.4, -0.2))
        p.arm("L", (-0.08, -0.03, 1.38 + 0.0), f=(0.3, 0.4, 0.5), up=(0, 0, 1), hint=(-0.9, -0.4, -0.2))
        # hands on head: head top is at z = 1.78 - 0.46
        p.arm("R", (0.08, -0.04, 1.72 - 0.46), f=(-0.3, 0.4, 0.5), up=(0, 0, 1), hint=(0.9, -0.4, -0.2))
        p.arm("L", (-0.08, -0.04, 1.72 - 0.46), f=(0.3, 0.4, 0.5), up=(0, 0, 1), hint=(-0.9, -0.4, -0.2))
    elif hands == "behind":
        p.arm("R", (0.035, -0.130, 0.99 - 0.46), f=(-0.2, -0.5, -1), up=(0, 1, -0.3), hint=(0.4, 0.2, -1))
        p.arm("L", (-0.035, -0.130, 0.99 - 0.46), f=(0.2, -0.5, -1), up=(0, 1, -0.3), hint=(-0.4, 0.2, -1))
    elif hands == "up":
        p.arm("R", (0.20, 0.10, 1.82 - 0.46), f=(0, 0.15, 1), up=(0, -1, 0.15), hint=(0.6, -0.2, -0.6))
        p.arm("L", (-0.20, 0.10, 1.82 - 0.46), f=(0, 0.15, 1), up=(0, -1, 0.15), hint=(-0.6, -0.2, -0.6))
    return p


def build_full():
    # death: hit -> stagger -> knees -> fall -> prone, 600 ms from the hit [ölçüldü: 70 / 130-200 / 200 ms]
    hit = Pose().e("Spine", -8).e("Chest", -4)
    hit.sym("UpperLeg", 8).sym("LowerLeg", -16).sym("Foot", -8 + 16)
    hit.arm("R", (0.07, 0.15, 1.28), f=(0, 0.3, 1), up=(0, -1, 0.3), hint=(0.8, -0.4, -0.6))
    hit.arm("L", (-0.07, 0.15, 1.28), f=(0, 0.3, 1), up=(0, -1, 0.3), hint=(-0.8, -0.4, -0.6))
    stag = hit.copy()
    stag.e("Spine", -20).e("Chest", -8).e("Head", -6)
    stag.sym("UpperLeg", 22).sym("LowerLeg", -52).sym("Foot", 30)
    stag.hips(0, 0.02, -0.08)
    kn = kneel_pose("up")
    kn.e("Spine", -20).e("Chest", -8).e("Head", -12)
    kn.sym("UpperArm", 30, -10, 0).sym("LowerArm", 20)
    kn.hips(0, 0.10, -0.46)
    fall = prone_pose("spread")
    fall.e("Hips", -50, 0, 0).hips(0, 0.28, -0.60)
    pr = prone_pose("spread")
    add("death_fall", 0.75, FULL, [(0, hit), (0.07, stag), (0.20, kn), (0.40, fall), (0.60, pr), (0.75, pr)])
    # taser: stiffen, tip over, end prone
    stiff = Pose().e("Spine", 8).e("Chest", 4).e("Head", 8)
    stiff.sym("UpperArm", 25, -50, 0).sym("LowerArm", 30).sym("UpperLeg", 0, -6, 0)
    tip = prone_pose("spread")
    tip.e("Hips", -35, 0, 0).hips(0, 0.12, -0.35)
    add("taser_fall", 0.6, FULL, [(0, relaxed()), (0.12, stiff), (0.35, tip), (0.6, prone_pose("spread"))])
    add("prone_hold", 1.0, FULL, [(0, prone_pose("spread"))], loop=True)
    add("cuffed_prone", 1.0, FULL, [(0, prone_pose("behind"))], loop=True)
    # kneel: from standing hands up to kneeling with hands on head
    sit_mid = kneel_pose("up")
    sit_mid.hips(0, 0.0, -0.22)
    sit_mid.sym("UpperLeg", 40).sym("LowerLeg", -85).sym("Foot", 40)
    add("kneel", 0.85, FULL, [(0, next(a for a in ANIMS if a.name == "hands_up").keys[0][1]), (0.40, sit_mid), (0.85, kneel_pose("head"))])
    add("kneel_hold", 2.0, FULL, [(0, kneel_pose("head")), (1.0, breathe(kneel_pose("head"), 1.0)), (2.0, kneel_pose("head"))], loop=True)
    add("kneel_cuffed", 2.0, FULL, [(0, kneel_pose("behind")), (1.0, breathe(kneel_pose("behind"), 1.0)), (2.0, kneel_pose("behind"))], loop=True)
    # officer cuffing a subject on the ground: crouch, hands working at wrist height (ends at 3.0 s)
    crouch = Pose().hips(0, 0.12, -0.34).e("Spine", -30).e("Chest", -10).e("Head", 18)
    crouch.sym("UpperLeg", 70).sym("LowerLeg", -105).sym("Foot", 30)
    c0, c1 = crouch.copy(), crouch.copy()
    c0.arm("R", (0.07, 0.42, 0.52), f=(0, 1, -0.4), up=(0, 0.4, 1), hint=(0.6, -0.3, -1))
    c0.arm("L", (-0.07, 0.38, 0.50), f=(0, 1, -0.4), up=(0, 0.4, 1), hint=(-0.6, -0.3, -1))
    c1.arm("R", (0.04, 0.46, 0.50), f=(0, 1, -0.4), up=(0, 0.4, 1), hint=(0.6, -0.3, -1))
    c1.arm("L", (-0.04, 0.40, 0.52), f=(0, 1, -0.4), up=(0, 0.4, 1), hint=(-0.6, -0.3, -1))
    add("cuffing", 3.0, FULL, [(0, relaxed()), (0.4, c0), (0.9, c1), (1.4, c0), (1.9, c1), (2.4, c0), (3.0, c1)])
    # pat-down: officer leans, hands sweeping along the subject's side
    pd = crouch.copy().hips(0, 0.08, -0.16).e("Spine", -22).e("Chest", -8)
    pd.sym("UpperLeg", 40).sym("LowerLeg", -60).sym("Foot", 20)
    pa, pb = pd.copy(), pd.copy()
    pa.arm("R", (0.10, 0.34, 1.05), f=(0, 1, -0.2), up=(0, 0.2, 1), hint=(0.6, -0.3, -1))
    pa.arm("L", (-0.10, 0.34, 0.85), f=(0, 1, -0.2), up=(0, 0.2, 1), hint=(-0.6, -0.3, -1))
    pb.arm("R", (0.10, 0.34, 0.80), f=(0, 1, -0.2), up=(0, 0.2, 1), hint=(0.6, -0.3, -1))
    pb.arm("L", (-0.10, 0.34, 1.05), f=(0, 1, -0.2), up=(0, 0.2, 1), hint=(-0.6, -0.3, -1))
    add("patdown", 3.2, FULL, [(0, pa), (0.8, pb), (1.6, pa), (2.4, pb), (3.2, pa)], loop=True)
    sp = Pose().e("Spine", -6).e("Chest", -4)
    sp.sym("UpperLeg", 2, -10, 0).sym("Foot", 0, 0, 0)
    sp.arm("R", (0.08, -0.04, 1.72), f=(-0.3, 0.4, 0.5), up=(0, 0, 1), hint=(0.9, -0.4, -0.2))
    sp.arm("L", (-0.08, -0.04, 1.72), f=(0.3, 0.4, 0.5), up=(0, 0, 1), hint=(-0.9, -0.4, -0.2))
    add("patdown_subject", 2.0, FULL, [(0, sp), (1.0, breathe(sp, 1.0)), (2.0, sp)], loop=True)
    # vehicle seats (origin = floor point below the hip point; hips at 0.43 m)
    def seated(hands):
        p = Pose().hips(0, -0.26, -0.50)
        p.e("Spine", 4).e("Chest", 3).e("Head", -4)
        p.leg("R", (0.10, 0.20, 0.14), hint=(0, 1, 0.3), foot_pitch=12)
        p.leg("L", (-0.10, 0.20, 0.10), hint=(0, 1, 0.3), foot_pitch=5)
        if hands == "wheel":
            p.arm("R", (0.19, 0.20, 0.82), f=(0, 1, 0.1), up=(1, 0, 0.3), hint=(0.6, -0.3, -1))
            p.arm("L", (-0.19, 0.20, 0.82), f=(0, 1, 0.1), up=(-1, 0, 0.3), hint=(-0.6, -0.3, -1))
        else:
            p.arm("R", (0.18, 0.12, 0.62), f=(0, 1, -0.1), up=(0, 0, 1), hint=(0.6, -0.3, -1))
            p.arm("L", (-0.18, 0.12, 0.62), f=(0, 1, -0.1), up=(0, 0, 1), hint=(-0.6, -0.3, -1))
        return p
    sd, sp2 = seated("wheel"), seated("lap")
    add("sit_drive", 2.0, FULL, [(0, sd), (1.0, breathe(sd, 0.6)), (2.0, sd)], loop=True)
    add("sit_passenger", 2.0, FULL, [(0, sp2), (1.0, breathe(sp2, 0.6)), (2.0, sp2)], loop=True)
    # enter: standing beside the seat -> lean in -> sit (est. 1.2 s); exit is the reverse (est. 0.9 s)
    lean = Pose().hips(0, -0.12, -0.20).e("Spine", -28).e("Chest", -10).e("Head", 20)
    lean.sym("UpperLeg", 38).sym("LowerLeg", -55).sym("Foot", 20)
    lean.arm("R", (0.20, 0.25, 0.88), f=(0, 1, 0), up=(0, 0, 1), hint=(0.6, -0.3, -1))
    lean.arm("L", (-0.20, 0.25, 0.88), f=(0, 1, 0), up=(0, 0, 1), hint=(-0.6, -0.3, -1))
    add("enter_vehicle", 1.2, FULL, [(0, relaxed()), (0.4, lean), (0.85, sd), (1.2, sd)])
    add("exit_vehicle", 0.9, FULL, [(0, sd), (0.3, lean), (0.9, relaxed())])


def build_all():
    ANIMS.clear()
    build_locomotion()
    build_upper()
    build_weapons()
    build_full()


# --- Blender side --------------------------------------------------------------------------------------
def build(bpy, out_dir, export, reset, rig_mod):
    reset()
    arm = rig_mod.create_armature(bpy)
    build_all()
    scene = bpy.context.scene
    scene.render.fps = FPS
    ad = arm.animation_data_create()
    bpy.context.view_layer.objects.active = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    count = 0
    for anim in ANIMS:
        act = bpy.data.actions.new(anim.name)
        ad.action = act
        start = 1
        end = start + int(round(anim.length * FPS))
        for t, pose in anim.keys:
            frame = start + t * FPS
            for bone in anim.bones:
                pb = arm.pose.bones[bone]
                pb.rotation_quaternion = rig_mod.basis_quaternion(bone, pose.d.get(bone, I3))
                pb.keyframe_insert("rotation_quaternion", frame=frame)
            if "Hips" in anim.bones:
                pb = arm.pose.bones["Hips"]
                pb.location = rig_mod.basis_location("Hips", pose.loc.get("Hips", Vector()))
                pb.keyframe_insert("location", frame=frame)
        ad.action = None
        track = ad.nla_tracks.new()
        track.name = anim.name
        strip = track.strips.new(anim.name, start, act)
        strip.action_frame_start = start
        strip.action_frame_end = end
        count += 1
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    scene.frame_start = 1
    scene.frame_end = 600
    export(os.path.join(out_dir, "animations.glb"), [arm], animations=True)
    import json
    loco = {"idle", "walk", "run", "strafe_r", "strafe_l", "run_strafe_r", "run_strafe_l"}
    meta = {}
    for a in ANIMS:
        group = "loco" if a.name in loco else ("upper" if a.bones is UB else "full")
        meta[a.name] = {"length": round(a.length, 4), "loop": a.loop, "group": group}
    with open(os.path.join(out_dir, "animations.json"), "w") as fh:
        json.dump(meta, fh, indent=1, sort_keys=True)
    print("ANIMATIONS", count)
