"""The drone-mk2 airframe, modelled from scratch and exported as GLB parts.

Run from anywhere (Blender 5.1, background):
  blender --background --factory-startup --python tools/gen_drone_model.py
then `godot --headless --path . --import`. Output lands in src/vehicles/drone/models/ and is
committed, so only REGENERATING the model needs Blender. Deterministic: no randomness, every
dimension is a literal below.

Everything is authored in GODOT's frame (x right, y up, -z forward, metres) and converted to
Blender's Z-up frame at the vertex, so the glTF exporter's Y-up conversion hands Godot back exactly
these numbers. Each moving part is its own GLB built around its own pivot; `drone_mk2.tscn` is the
rig that places them. The body GLB carries one empty per rig node, named `Pivot_<SceneNode>`, and
tests/test_drone_indicators.gd pins every one against the scene, so a number changed here and not
there (or the reverse) fails CI.

The flight numbers are drone.tscn's and not this file's to change: rotor centres at
(+-0.407, 0.15, +-0.407) (DroneProp.MOTORS, pinned by test_drone), a 0.44 m prop, and the whole
airframe inside the collision box both drones share, y in [-0.06, 0.18]; the feet stand on its
floor.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "src", "vehicles", "drone", "models")

# --- owned by the flight model --------------------------------------------------------------
ARM = 0.407       # rotor lever on x and z
ROTOR_Y = 0.15    # prop plane
FLOOR_Y = -0.06   # bottom of the shared HullShape box

# --- the airframe's own layout --------------------------------------------------------------
GIMBAL = (0.0, -0.012, -0.31)   # yaw and pitch axes cross here; the HOOD camera sits on it
# Where the payload hangs by its top face, under the centre of mass: 1 mm above the floor, so a
# carried crate (0.858 m, wider than the feet) clears them and one the craft stands on can latch.
HARDPOINT = (0.0, -0.059, 0.0)
JAW_X = 0.012                   # each jaw's hinge, either side of the hardpoint...
JAW_Y = -0.04                   # ...and above it, so the jaws close on the crate's top edge
ESC_R = 0.26                    # ESC pods along each arm, on both axes
LED_OUT = 0.0255                # arm-tip LED outboard of the motor axis, on both axes
BAR_X = (-0.033, -0.011, 0.011, 0.033)   # battery gauge, bar 0 on the left seen from behind

CORNERS = {"FL": (-1, -1), "FR": (1, -1), "RL": (-1, 1), "RR": (1, 1)}
ESC_ORDER = ("FL", "FR", "RL", "RR")   # esc_index order, DroneProp.MOTORS

# sRGB, metallic, roughness. Flat colours only: no textures to ship or stream on the web build.
MATS = {
    "Shell": ((0.87, 0.88, 0.86), 0.0, 0.55),
    "Accent": ((0.96, 0.45, 0.07), 0.0, 0.5),
    "Frame": ((0.12, 0.13, 0.15), 0.1, 0.6),
    "Metal": ((0.62, 0.64, 0.68), 0.7, 0.35),
    "Pack": ((0.17, 0.22, 0.31), 0.0, 0.5),
    "Rubber": ((0.05, 0.05, 0.055), 0.0, 0.9),
    "Glass": ((0.04, 0.07, 0.12), 0.2, 0.08),
    "Blade": ((0.14, 0.14, 0.15), 0.0, 0.5),
}


def _pivots() -> dict:
    out = {}
    for tag, (sx, sz) in CORNERS.items():
        out["Rotor" + tag] = (sx * ARM, ROTOR_Y, sz * ARM)
        out["Led" + tag] = (sx * (ARM + LED_OUT), 0.06, sz * (ARM + LED_OUT))
    for i, tag in enumerate(ESC_ORDER):
        sx, sz = CORNERS[tag]
        out["EscLed%d" % i] = (sx * ESC_R, 0.0905, sz * ESC_R)
    for i, x in enumerate(BAR_X):
        out["BattBar%d" % i] = (x, 0.125, 0.1535)
    out.update({
        "GimbalYaw": GIMBAL, "HoodCam": GIMBAL, "Hardpoint": HARDPOINT,
        "JawL": (-JAW_X, JAW_Y, 0.0), "JawR": (JAW_X, JAW_Y, 0.0),
        "HeadLight": (0.0, 0.064, -0.285), "HeadLens": (0.0, 0.064, -0.2775),
        "FcLed": (0.0, 0.121, -0.13), "GpsLed": (0.0, 0.178, 0.172),
        "RangeBeam": (0.0, -0.034, 0.11),
    })
    return out


PIVOTS = _pivots()

# Godot (x, y, z) -> Blender (x, -z, y): a proper rotation, so face winding survives it.
G2B = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0))).to_4x4()


def rot_x(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "X")


def rot_y(deg: float) -> Matrix:
    return Matrix.Rotation(math.radians(deg), 3, "Y")


AXIS = {"y": rot_x(-90.0), "z": Matrix.Identity(3), "x": rot_y(90.0)}   # bmesh builds along +Z


def place(pos, rot=None) -> Matrix:
    m = Matrix.Translation(Vector(pos))
    return m @ rot.to_4x4() if rot is not None else m


def _linear(c: float) -> float:
    return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92


def material(name: str):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    srgb, metallic, roughness = MATS[name]
    rgba = tuple(_linear(c) for c in srgb) + (1.0,)
    m = bpy.data.materials.new(name)
    if m.node_tree is None:   # Blender < 5 builds the node tree only on request
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    m.diffuse_color = rgba
    # Every part is a closed solid, so single-sided. Blender's default exports glTF doubleSided,
    # and Godot would then draw back faces too: overdraw, and the HOOD camera (inside the gimbal
    # camera's body) would see that body's inside wherever the near plane did not clip it.
    m.use_backface_culling = True
    return m


class Part:
    """One exported mesh object: closed primitives appended into one bmesh, a slot per material."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.mats: list = []

    def add(self, tmp, mat: str, xform: Matrix) -> None:
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
        if mat not in self.mats:
            self.mats.append(mat)
        slot = self.mats.index(mat)
        full = G2B @ xform
        vmap = {v: self.bm.verts.new(full @ v.co) for v in tmp.verts}
        for f in tmp.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = slot
            nf.smooth = False
        tmp.free()

    def finish(self):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(material(m))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def box(p: Part, pos, size, mat: str, bevel: float = 0.0, rot=None) -> None:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0.0:   # one chamfer segment: the low-poly edge, not a rounded one
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET",
                profile_type="SUPERELLIPSE", segments=1, profile=0.5, affect="EDGES",
                clamp_overlap=True)
    p.add(bm, mat, place(pos, rot))


def cyl(p: Part, pos, r: float, h: float, mat: str, axis: str = "y", segs: int = 12,
        r_top=None) -> None:
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
            radius2=r if r_top is None else r_top, depth=h)
    p.add(bm, mat, place(pos, AXIS[axis]))


def loft(p: Part, sections, mat: str, rot=None) -> None:
    """A capped tube through equal-length rings of points."""
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector(q)) for q in sec] for sec in sections]
    n = len(sections[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    p.add(bm, mat, place((0.0, 0.0, 0.0), rot))


def rect_z(z: float, half_w: float, y0: float, y1: float) -> list:
    return [(-half_w, y0, z), (half_w, y0, z), (half_w, y1, z), (-half_w, y1, z)]


def empty(name: str, pos):
    e = bpy.data.objects.new(name, None)
    e.location = (G2B @ Vector(pos).to_4d()).to_3d()
    bpy.context.scene.collection.objects.link(e)
    return e


# --- the parts ------------------------------------------------------------------------------

def build_body() -> list:
    """Every static piece, JOINED: one mesh instance with a surface per material."""
    p = Part("Airframe")
    # Fuselage pod, with the nose and canopy in the accent colour so the heading reads from above.
    box(p, (0.0, 0.04, -0.02), (0.24, 0.12, 0.40), "Shell", bevel=0.03)
    loft(p, [rect_z(-0.21, 0.10, 0.0, 0.09), rect_z(-0.275, 0.055, 0.02, 0.075)], "Accent")
    box(p, (0.0, 0.105, -0.13), (0.15, 0.02, 0.14), "Accent", bevel=0.008)
    cyl(p, (0.0, 0.118, -0.13), 0.012, 0.006, "Frame", segs=12)          # FC LED bezel
    box(p, (0.0, -0.022, -0.02), (0.18, 0.006, 0.30), "Frame")            # belly plate

    for tag, (sx, sz) in CORNERS.items():
        u = Vector((sx, 0.0, sz)).normalized()
        r0, r1 = 0.09, ARM * math.sqrt(2.0)
        yaw = math.degrees(math.atan2(-u.z, u.x))   # rot_y(yaw) turns local +x onto the arm
        mid = (r0 + r1) * 0.5
        box(p, (u.x * mid, 0.055, u.z * mid), (r1 - r0, 0.03, 0.042),
                "Accent" if sz < 0 else "Frame", bevel=0.008, rot=rot_y(yaw))
        box(p, (sx * ESC_R, 0.079, sz * ESC_R), (0.06, 0.018, 0.032), "Shell", bevel=0.004,
                rot=rot_y(yaw))
        mx, mz = sx * ARM, sz * ARM
        cyl(p, (mx, 0.06, mz), 0.034, 0.06, "Frame")                        # pod 0.03..0.09
        cyl(p, (mx, 0.1125, mz), 0.04, 0.045, "Metal", segs=14)             # bell to 0.135
        cyl(p, (mx, 0.14, mz), 0.006, 0.01, "Metal", segs=8)                # shaft
        cyl(p, (mx, -0.01, mz), 0.011, 0.08, "Frame", segs=8)               # leg
        cyl(p, (mx, FLOOR_Y + 0.006, mz), 0.024, 0.012, "Rubber", r_top=0.02)   # foot

    # Smart battery on top, strapped, with its gauge bezel on the rear face.
    box(p, (0.0, 0.125, 0.05), (0.13, 0.05, 0.20), "Pack", bevel=0.008)
    box(p, (0.0, 0.1505, 0.05), (0.11, 0.002, 0.06), "Accent")
    for z in (-0.01, 0.11):
        box(p, (0.0, 0.125, z), (0.134, 0.054, 0.012), "Frame")
    box(p, (0.0, 0.125, 0.1515), (0.092, 0.024, 0.003), "Frame")

    # GNSS puck on a mast behind the pack, clear of the props and of the pack itself.
    cyl(p, (0.0, 0.12, 0.172), 0.005, 0.08, "Frame", segs=8)
    cyl(p, (0.0, 0.167, 0.172), 0.032, 0.014, "Shell", segs=16)
    cyl(p, (0.0, 0.1755, 0.172), 0.026, 0.003, "Frame", segs=16)

    # Downward rangefinder, aft of the hook so a crate on the hook does not sit over the lens.
    box(p, (0.0, -0.026, 0.11), (0.032, 0.012, 0.03), "Frame", bevel=0.003)
    cyl(p, (0.0, -0.0325, 0.11), 0.008, 0.002, "Glass", segs=10)

    # Hook mount down to the jaw hinges; the jaws are their own part.
    box(p, (0.0, -0.0275, 0.0), (0.05, 0.017, 0.034), "Frame", bevel=0.002)

    # Gimbal bracket out of the nose, and the spotlight bezel above it on the nose face.
    box(p, (0.0, 0.05, -0.293), (0.036, 0.008, 0.075), "Frame", bevel=0.002)
    cyl(p, (0.0, PIVOTS["HeadLens"][1], -0.2755), 0.011, 0.002, "Frame", axis="z", segs=14)

    objs = [p.finish()]
    for name, pos in PIVOTS.items():
        objs.append(empty("Pivot_" + name, pos))
    return objs


def _blade_section(r: float, chord: float, pitch_deg: float, t: float = 0.005) -> list:
    rot = rot_x(pitch_deg)
    pts = [(0.0, -t / 2, -chord / 2), (0.0, -t / 2, chord / 2), (0.0, t / 2, chord / 2),
            (0.0, t / 2, -chord / 2)]
    return [tuple(rot @ Vector(q) + Vector((r, 0.0, 0.0))) for q in pts]


# Blade stations: radius, chord, pitch in degrees. Pitch washes out toward the tip.
STATIONS = ((0.012, 0.022, 24.0), (0.05, 0.034, 20.0), (0.12, 0.03, 14.0), (0.19, 0.022, 10.0),
        (0.22, 0.012, 8.0))


def build_prop(handed: int, name: str) -> list:
    """Two-blade 0.44 m prop. `handed` is MOTORS' spin: +1 turns counter-clockwise seen from
    above, so its leading edge is -z on the +x blade and pitching it up makes lift."""
    p = Part(name)
    cyl(p, (0.0, 0.0, 0.0), 0.017, 0.014, "Metal")
    cyl(p, (0.0, 0.013, 0.0), 0.012, 0.012, "Metal", r_top=0.003)
    for side in (0.0, 180.0):
        secs = [_blade_section(r, c, pitch * handed) for r, c, pitch in STATIONS]
        loft(p, secs[:4], "Blade", rot=rot_y(side))
        loft(p, secs[3:], "Shell", rot=rot_y(side))   # white tips make the spin readable
    return [p.finish()]


def build_gimbal_yaw() -> list:
    """The yoke: turns about the vertical through GIMBAL, carries the two pitch motors."""
    p = Part("Yoke")
    cyl(p, (0.0, 0.0545, 0.0), 0.014, 0.007, "Metal", segs=14)
    box(p, (0.0, 0.047, 0.0), (0.11, 0.008, 0.016), "Frame", bevel=0.002)
    for sx in (-1.0, 1.0):
        box(p, (sx * 0.05, 0.022, 0.0), (0.007, 0.05, 0.016), "Frame", bevel=0.002)
        cyl(p, (sx * 0.044, 0.0, 0.0), 0.011, 0.007, "Metal", axis="x")
    return [p.finish()]


def build_gimbal_pitch() -> list:
    """The camera: turns about the yoke's x axis. Every point stays within 0.041 m of the axis,
    under the yoke's crossbar, and above the collision floor at full down-tilt."""
    p = Part("Camera")
    box(p, (0.0, 0.0, 0.0), (0.064, 0.056, 0.06), "Shell", bevel=0.012)
    box(p, (0.0, 0.0285, 0.01), (0.03, 0.002, 0.02), "Accent")
    cyl(p, (0.0, 0.0, -0.035), 0.015, 0.018, "Frame", axis="z", segs=14)
    cyl(p, (0.0, 0.0, -0.0445), 0.012, 0.002, "Glass", axis="z", segs=14)
    return [p.finish()]


def build_jaw() -> list:
    """One hook jaw, hinged along z at its origin, tip turned toward +x. The right jaw is this one
    turned half round about y in the scene. Shut, the tips reach down to the hardpoint's height,
    the carried crate's top face, and stop above the collision floor."""
    p = Part("Jaw")
    cyl(p, (0.0, 0.0, 0.0), 0.004, 0.02, "Frame", axis="z", segs=8)
    box(p, (0.0, -0.008, 0.0), (0.005, 0.016, 0.018), "Metal")
    box(p, (0.005, -0.0175, 0.0), (0.012, 0.004, 0.018), "Metal")
    return [p.finish()]


def export(objs: list, filename: str) -> None:
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
            export_apply=True, export_yup=True, export_materials="EXPORT", export_normals=True,
            export_cameras=False, export_lights=False, export_animations=False,
            export_extras=False)
    print("[drone model] wrote " + path)


def main() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    os.makedirs(OUT_DIR, exist_ok=True)
    export(build_body(), "drone_mk2_body.glb")
    export(build_prop(1, "PropCCW"), "drone_mk2_prop_ccw.glb")
    export(build_prop(-1, "PropCW"), "drone_mk2_prop_cw.glb")
    export(build_gimbal_yaw(), "drone_mk2_gimbal_yaw.glb")
    export(build_gimbal_pitch(), "drone_mk2_gimbal_pitch.glb")
    export(build_jaw(), "drone_mk2_hook_jaw.glb")


main()
