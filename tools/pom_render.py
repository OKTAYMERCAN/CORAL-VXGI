"""POM / MATERIALS RENDER (since 4.59, shipped since 4.61): draws a floor of blocks through the
pack's real gbuffers_terrain program (vertex + fragment shader, world0 wrappers) on Mesa llvmpipe,
with a synthetic PBR atlas - albedo, _n with a height map in alpha, _s - and saves what the
G-buffer holds. It is how the parallax fixes of 4.59 - 4.61 were measured.

Needs Linux with Mesa (libEGL, libGL), numpy and Pillow, and tools/mesa_check.py next to this file.

  python3 tools/pom_render.py                         the pack as it is (POM is off by default!)
  SET="MATERIAL_POM !TAA POM_DISTANCE=128.0" OUT=pom python3 tools/pom_render.py

Env:
  TREE     folder holding shaders/ (default: the pack this tool belongs to)
  SET      settings to change for this run, in a temporary copy of the pack: NAME turns a switch
           on, !NAME off, NAME=value sets a number (e.g. "MATERIAL_POM !TAA LABPBR_VERSION=1")
  OUT      output prefix (default "pom"): OUT.png is the albedo the pass wrote (colortex0)
  W, H     image size (960 x 540);  RES  sprite size in texels (128)
  PITCH, YAW, CAMX, CAMZ   camera (degrees; -30 / 90; position in the first block)
  ENT      block ID of the floor (mc_Entity, default 0);  STAGE  renderStage (4 solid, 6 cutout)
  ROT      1: textures turned by a quarter on every face
  Height maps: default grooves a quarter block deep between four tiles per sprite;
    FLAT=1 no relief;  GROOVE=n groove height 0-255;  HMAP=random pixel-art heights in four
    levels;  HMAP=smooth round bumps with a matching normal map;  CUTOUT=1 holes in every tile
    (alpha 0, deep in the height map), like glass
  ORIGIN=x,y  place the sprite at that texel of the atlas instead of (0, 0) (not aligned to its
           size: what the measured sprite of 4.61 is for); the rest of the atlas is a striped
           neighbour, so a read outside the sprite shows orange
  HALF=1   draw every top face as two half quads, each with its own mc_midTexCoord (a stair top)
  SHADE=1  save N.L shading from the normal buffer (colortex1) times the albedo; SUN=x,y,z
  DUMP=f.npy  save all three render targets as float arrays
"""
import ctypes, os, sys, math
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
TREE = os.environ.get("TREE", os.path.dirname(HERE))
exec(open(os.path.join(HERE, "mesa_check.py")).read().split("def main():")[0])
if os.environ.get("SET"):
    # a temporary copy of the pack with the requested settings
    import shutil, tempfile, re as _re
    import atexit
    tmp = tempfile.mkdtemp(prefix="pom_render_")
    atexit.register(shutil.rmtree, tmp, True)
    shutil.copytree(os.path.join(TREE, "shaders"), os.path.join(tmp, "shaders"))
    sp = os.path.join(tmp, "shaders", "lib", "settings.glsl")
    txt = open(sp).read()
    for tok in os.environ["SET"].split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            txt, c = _re.subn(r"(?m)^#define %s [^ ]+" % k, "#define %s %s" % (k, v), txt, count=1)
        elif tok.startswith("!"):
            k = tok[1:]
            txt, c = _re.subn(r"(?m)^#define %s\b" % k, "//#define %s" % k, txt, count=1)
            if not c and _re.search(r"(?m)^//\s*#define %s\b" % k, txt): c = 1
        else:
            k = tok
            txt, c = _re.subn(r"(?m)^//\s*#define %s\b" % k, "#define %s" % k, txt, count=1)
            if not c and _re.search(r"(?m)^#define %s\b" % k, txt): c = 1
        if not c: sys.exit("SET: %s not found in settings.glsl" % tok)
    open(sp, "w").write(txt)
    TREE = tmp
ROOT = os.path.join(TREE, "shaders")
c_uint, c_int, c_void_p, c_float = ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_float
def g(n, r, *a): return fn(n, r, *a)
glGenTextures = g("glGenTextures", None, c_int, ctypes.POINTER(c_uint)); glBindTexture = g("glBindTexture", None, c_uint, c_uint)
glTexImage2D = g("glTexImage2D", None, c_uint, c_int, c_int, c_int, c_int, c_int, c_uint, c_uint, c_void_p)
glTexParameteri = g("glTexParameteri", None, c_uint, c_uint, c_int); glActiveTexture = g("glActiveTexture", None, c_uint)
glGenerateMipmap = g("glGenerateMipmap", None, c_uint)
glUseProgram = g("glUseProgram", None, c_uint); glGetUniformLocation = g("glGetUniformLocation", c_int, c_uint, ctypes.c_char_p)
glUniform1i = g("glUniform1i", None, c_int, c_int); glUniform1f = g("glUniform1f", None, c_int, c_float)
glUniform3f = g("glUniform3f", None, c_int, c_float, c_float, c_float); glUniform4f = g("glUniform4f", None, c_int, c_float, c_float, c_float, c_float)
glUniform2i = g("glUniform2i", None, c_int, c_int, c_int)
glUniformMatrix4fv = g("glUniformMatrix4fv", None, c_int, c_int, ctypes.c_ubyte, ctypes.POINTER(c_float))
glGenFramebuffers = g("glGenFramebuffers", None, c_int, ctypes.POINTER(c_uint)); glBindFramebuffer = g("glBindFramebuffer", None, c_uint, c_uint)
glFramebufferTexture2D = g("glFramebufferTexture2D", None, c_uint, c_uint, c_uint, c_uint, c_int)
glGenRenderbuffers = g("glGenRenderbuffers", None, c_int, ctypes.POINTER(c_uint)); glBindRenderbuffer = g("glBindRenderbuffer", None, c_uint, c_uint)
glRenderbufferStorage = g("glRenderbufferStorage", None, c_uint, c_uint, c_int, c_int)
glFramebufferRenderbuffer = g("glFramebufferRenderbuffer", None, c_uint, c_uint, c_uint, c_uint)
glDrawBuffers = g("glDrawBuffers", None, c_int, ctypes.POINTER(c_uint)); glViewport = g("glViewport", None, c_int, c_int, c_int, c_int)
glClearColor = g("glClearColor", None, c_float, c_float, c_float, c_float); glClear = g("glClear", None, c_uint)
glEnable = g("glEnable", None, c_uint); glDisable = g("glDisable", None, c_uint)
glBegin = g("glBegin", None, c_uint); glEnd = g("glEnd", None)
glVertex3f = g("glVertex3f", None, c_float, c_float, c_float); glNormal3f = g("glNormal3f", None, c_float, c_float, c_float)
glColor4f = g("glColor4f", None, c_float, c_float, c_float, c_float); glMultiTexCoord2f = g("glMultiTexCoord2f", None, c_uint, c_float, c_float)
glVertexAttrib4f = g("glVertexAttrib4f", None, c_uint, c_float, c_float, c_float, c_float)
glBindAttribLocation = g("glBindAttribLocation", None, c_uint, c_uint, ctypes.c_char_p)
glCreateProgram = g("glCreateProgram", c_uint); glAttachShader = g("glAttachShader", None, c_uint, c_uint)
glLinkProgram = g("glLinkProgram", None, c_uint); glGetProgramiv2 = g("glGetProgramiv", None, c_uint, c_uint, ctypes.POINTER(c_int))
glGetProgramInfoLog2 = g("glGetProgramInfoLog", None, c_uint, c_int, ctypes.POINTER(c_int), ctypes.c_char_p)
glMatrixMode = g("glMatrixMode", None, c_uint); glLoadMatrixf = g("glLoadMatrixf", None, ctypes.POINTER(c_float))
glGetTexImage = g("glGetTexImage", None, c_uint, c_int, c_uint, c_uint, c_void_p); glFinish = g("glFinish", None)
glDepthFunc = g("glDepthFunc", None, c_uint)
glGetActiveUniform = g("glGetActiveUniform", None, c_uint, c_uint, c_int, ctypes.POINTER(c_int), ctypes.POINTER(c_int), ctypes.POINTER(c_uint), ctypes.c_char_p)
T2D = 0x0DE1
W, H = int(os.environ.get("W", "960")), int(os.environ.get("H", "540"))
RES = int(os.environ.get("RES", "128"))

# ---- program
wd = os.path.join(ROOT, "world0")
shs = []
for kind, f in ((GL_VERTEX_SHADER, "gbuffers_terrain.vsh"), (GL_FRAGMENT_SHADER, "gbuffers_terrain.fsh")):
    s, ok, log = compile_shader(kind, prepare(os.path.join(wd, f), False)); assert ok, log[:3000]; shs.append(s)
prog = glCreateProgram()
for s in shs: glAttachShader(prog, s)
for i, nm in ((1, b"mc_Entity"), (2, b"mc_midTexCoord"), (3, b"at_tangent"), (4, b"at_midBlock")): glBindAttribLocation(prog, i, nm)
glLinkProgram(prog); st = c_int(); glGetProgramiv2(prog, 0x8B82, ctypes.byref(st))
if not st.value:
    b = ctypes.create_string_buffer(4000); glGetProgramInfoLog2(prog, 4000, None, b); print(b.value.decode()); sys.exit(1)

# ---- atlas: the sprite at (0,0), RES x RES; the rest magenta (a read outside the sprite shows)
A = max(256, RES * 2)
OX, OY = [int(v) for v in os.environ.get("ORIGIN", "0,0").split(",")]
if OX + RES > A or OY + RES > A: A = 2 * A
alb = np.zeros((A, A, 4), np.uint8); alb[..., :3] = (255, 0, 255); alb[..., 3] = 255
nrm = np.zeros((A, A, 4), np.uint8); nrm[..., 0] = 128; nrm[..., 1] = 128; nrm[..., 2] = 255; nrm[..., 3] = 255
yy, xx = np.mgrid[0:RES, 0:RES]
tile = RES // 4; groove = max(RES // 16, 1)
gx = (xx % tile) < groove; gy = (yy % tile) < groove
isg = gx | gy
checker = ((xx // tile) + (yy // tile)) % 2
col = np.where(checker[..., None] == 0, np.array([200, 60, 60]), np.array([60, 170, 60]))
# a light diagonal stripe inside every tile, and a marker in the tile's upper-left corner
stripe = ((xx + yy) % (tile // 2)) < max(tile // 16, 1)
col = np.where(stripe[..., None], col + 50, col)
col = np.where(isg[..., None], np.array([40, 40, 120]), col)
# the neighbours: orange stripes with a rough height map (a read outside the sprite shows)
ay, ax = np.mgrid[0:A, 0:A]
alb[..., :3] = np.where(((ax // 3) % 2 == 0)[..., None], np.array([230, 140, 30]), np.array([120, 70, 20]))
nrm[..., 3] = ((np.sin(ax * 0.7) * np.sin(ay * 0.9) * 0.5 + 0.5) * 255).astype(np.uint8)
alb[:RES, :RES, :3] = np.clip(col, 0, 255)
nrm[:RES, :RES, 3] = np.where(isg, 0, 255)            # grooves a quarter block deep
if os.environ.get("FLAT"): nrm[..., 3] = 255
if os.environ.get("HMAP") == "random":
    # pixel art: every texel its own height in four levels, the albedo shows the level
    rng = np.random.default_rng(3); lv = rng.integers(0, 4, (RES, RES))
    nrm[:RES, :RES, 3] = 255 - lv * 70
    alb[:RES, :RES, :3] = np.stack([120 + lv * 30, 100 + lv * 20, 90 + lv * 10], -1)
if os.environ.get("HMAP") == "smooth":
    # a smooth high resolution map: round bumps, with the matching normal map
    fx = xx / RES * 2 * np.pi * 3; fy = yy / RES * 2 * np.pi * 3
    h = 0.5 + 0.5 * np.sin(fx) * np.sin(fy)
    nrm[:RES, :RES, 3] = (h * 255).astype(np.uint8)
    dz = 0.25 * RES / RES   # height units per block: a quarter block
    gx_ = 0.5 * np.cos(fx) * np.sin(fy) * 2 * np.pi * 3 * 0.25; gy_ = 0.5 * np.sin(fx) * np.cos(fy) * 2 * np.pi * 3 * 0.25
    n = np.stack([-gx_, -gy_, np.ones_like(gx_)], -1); n /= np.linalg.norm(n, axis=-1, keepdims=True)
    nrm[:RES, :RES, 0] = ((n[..., 0] * 0.5 + 0.5) * 255).astype(np.uint8); nrm[:RES, :RES, 1] = ((n[..., 1] * 0.5 + 0.5) * 255).astype(np.uint8)
    alb[:RES, :RES, :3] = 170
if os.environ.get("CUTOUT"):
    # glass-like: holes in the middle of every tile (alpha 0), and the height map deep there
    hole = ((xx % tile) > tile // 4) & ((xx % tile) < 3 * tile // 4) & ((yy % tile) > tile // 4) & ((yy % tile) < 3 * tile // 4)
    alb[:RES, :RES, 3] = np.where(hole, 0, 255); nrm[:RES, :RES, 3] = np.where(hole, 0, np.where(isg, 128, 255))
if os.environ.get("GROOVE"): nrm[:RES, :RES, 3] = np.where(isg, int(os.environ["GROOVE"]), 255)
spec = np.zeros((A, A, 4), np.uint8); spec[..., 3] = 255
def tex(data, mip=True):
    t = c_uint(); glGenTextures(1, ctypes.byref(t)); glBindTexture(T2D, t.value)
    glTexImage2D(T2D, 0, 0x8058, A, A, 0, 0x1908, 0x1401, np.ascontiguousarray(data).ctypes.data_as(c_void_p))
    glGenerateMipmap(T2D)
    glTexParameteri(T2D, 0x2801, 0x2702)   # NEAREST_MIPMAP_LINEAR (Minecraft)
    glTexParameteri(T2D, 0x2800, 0x2600)   # NEAREST
    return t.value
def place(arr):
    if OX == 0 and OY == 0: return arr
    blk = arr[:RES, :RES].copy(); out = arr.copy()
    out[:RES, :RES] = arr[RES:2 * RES, RES:2 * RES] if 2 * RES <= A else arr[A - RES:, A - RES:]
    out[OY:OY + RES, OX:OX + RES] = blk
    return out
alb, nrm = place(alb), place(nrm)
tA, tN, tS = tex(alb), tex(nrm), tex(spec)

# ---- camera
pitch = math.radians(float(os.environ.get("PITCH", "-30"))); yaw = math.radians(float(os.environ.get("YAW", "90")))
eye = np.array([float(os.environ.get("CAMX", "0.5")), 1.62, float(os.environ.get("CAMZ", "0.5"))])
fw = np.array([math.cos(pitch) * math.cos(yaw), math.sin(pitch), math.cos(pitch) * math.sin(yaw)])
rr = np.cross(fw, [0, 1, 0]); rr /= np.linalg.norm(rr); uu = np.cross(rr, fw)
V = np.eye(4); V[0, :3], V[1, :3], V[2, :3] = rr, uu, -fw; V[:3, 3] = -V[:3, :3] @ eye
fov, near, far = math.radians(70), 0.05, 256.0
P = np.zeros((4, 4)); t_ = 1 / math.tan(fov / 2); P[0, 0] = t_ / (W / H); P[1, 1] = t_
P[2, 2] = (far + near) / (near - far); P[2, 3] = 2 * far * near / (near - far); P[3, 2] = -1
# player space = world space with the camera at the origin: vertices are sent in player space
Vp = V.copy(); Vp[:3, 3] = 0.0; Vp[:3, 3] = -Vp[:3, :3] @ np.array([0.0, eye[1] - 1.62 + 1.62, 0.0]) * 0  # rotation only
Vp = np.eye(4); Vp[:3, :3] = V[:3, :3]
def loadm(mode, m):
    glMatrixMode(mode); a = np.ascontiguousarray(np.array(m, np.float32).T); glLoadMatrixf(a.ctypes.data_as(ctypes.POINTER(c_float)))
loadm(0x1700, Vp); loadm(0x1701, P); loadm(0x1702, np.eye(4))

glUseProgram(prog)
cnt = c_int(); glGetProgramiv2(prog, 0x8B86, ctypes.byref(cnt))
vals = {"gbufferModelView": Vp, "gbufferModelViewInverse": np.linalg.inv(Vp), "gbufferProjection": P, "gbufferProjectionInverse": np.linalg.inv(P),
        "gbufferPreviousModelView": Vp, "gbufferPreviousProjection": P, "cameraPosition": eye, "previousCameraPosition": eye,
        "viewWidth": W, "viewHeight": H, "frameCounter": 0, "frameTimeCounter": 0.0, "near": near, "far": far, "renderStage": int(os.environ.get("STAGE", "4"))}
unit = {"gtexture": (0, tA), "normals": (1, tN), "specular": (2, tS)}
for i in range(cnt.value):
    ln, sz, ty = c_int(), c_int(), c_uint(); nm = ctypes.create_string_buffer(256)
    glGetActiveUniform(prog, i, 256, ctypes.byref(ln), ctypes.byref(sz), ctypes.byref(ty), nm)
    name = nm.value.decode(); loc = glGetUniformLocation(prog, nm.value)
    if name in unit:
        u, t = unit[name]; glActiveTexture(0x84C0 + u); glBindTexture(T2D, t); glUniform1i(loc, u)
    elif name in vals:
        v = vals[name]
        if ty.value == 0x8B5C: a = np.ascontiguousarray(np.array(v, np.float32)); glUniformMatrix4fv(loc, 1, 1, a.ctypes.data_as(ctypes.POINTER(c_float)))
        elif ty.value == 0x8B51: glUniform3f(loc, *map(float, v))
        elif ty.value == 0x1406: glUniform1f(loc, float(v))
        elif ty.value == 0x1404: glUniform1i(loc, int(v))
    elif not name.startswith("gl_"):
        pass

# ---- framebuffer (on a texture unit the samplers do not use)
glActiveTexture(0x84C0 + 9)
fbo = c_uint(); glGenFramebuffers(1, ctypes.byref(fbo)); glBindFramebuffer(0x8D40, fbo.value)
outs = []
for i in range(3):
    t = c_uint(); glGenTextures(1, ctypes.byref(t)); glBindTexture(T2D, t.value)
    glTexImage2D(T2D, 0, 0x881A, W, H, 0, 0x1908, 0x1406, None)
    glTexParameteri(T2D, 0x2801, 0x2600); glTexParameteri(T2D, 0x2800, 0x2600)
    glFramebufferTexture2D(0x8D40, 0x8CE0 + i, T2D, t.value, 0); outs.append(t.value)
rb = c_uint(); glGenRenderbuffers(1, ctypes.byref(rb)); glBindRenderbuffer(0x8D41, rb.value)
glRenderbufferStorage(0x8D41, 0x81A6, W, H); glFramebufferRenderbuffer(0x8D40, 0x8D00, 0x8D41, rb.value)
bufs = (c_uint * 3)(0x8CE0, 0x8CE1, 0x8CE2); glDrawBuffers(3, bufs)
glViewport(0, 0, W, H); glClearColor(0.05, 0.05, 0.08, 0); glClear(0x4100)
glEnable(0x0B71); glDepthFunc(0x0203); glDisable(0x0B44)

# ---- a floor of blocks: top faces at y = 0 (player space: y - eye height)
ENT = float(os.environ.get("ENT", "0"))
su = RES / A; ou, ov = OX / A, OY / A
HALF = int(os.environ.get("HALF", "0"))
def face(x0, z0, y, rot=0):
    # corners in player space; uv (0..su) with u along +x, v along +z (rot 1: u along +z, v along -x)
    cs = [(x0, z0), (x0 + 1, z0), (x0 + 1, z0 + 1), (x0, z0 + 1)]
    uvs = [(0, 0), (su, 0), (su, su), (0, su)]
    if HALF:   # the face is two quads side by side along x, like a stair's top: each has its own middle
        for part in (0, 1):
            xa, xb = x0 + 0.5 * part, x0 + 0.5 * part + 0.5
            qs = [(xa, z0), (xb, z0), (xb, z0 + 1), (xa, z0 + 1)]
            quv = [(su * (xa - x0), 0), (su * (xb - x0), 0), (su * (xb - x0), su), (su * (xa - x0), su)]
            mu = sum(q[0] for q in quv) / 4; mv = sum(q[1] for q in quv) / 4
            for (x, z), (u, v) in zip(qs, quv):
                glVertexAttrib4f(1, ENT, 0, 0, 0); glVertexAttrib4f(2, ou + mu, ov + mv, 0, 0); glVertexAttrib4f(3, 1.0, 0.0, 0.0, 1.0)
                glVertexAttrib4f(4, (x0 + 0.5 - x) * 64, -0.5 * 64, (z0 + 0.5 - z) * 64, 0)
                glColor4f(1, 1, 1, 1); glNormal3f(0, 1, 0); glMultiTexCoord2f(0x84C0, ou + u, ov + v); glMultiTexCoord2f(0x84C1, 240, 240)
                glVertex3f(x - eye[0], y - eye[1], z - eye[2])
        return
    if rot == 1: uvs = [(0, su), (0, 0), (su, 0), (su, su)]   # u along +z, v along -x
    T = (1.0, 0.0, 0.0, 1.0) if rot == 0 else (0.0, 0.0, 1.0, -1.0)
    # handedness as Iris computes it: sign(dot(dP/dv, cross(T, N)))
    tv = np.array(T[:3]); nv = np.array([0.0, 1.0, 0.0])
    dpdv = np.array([0, 0, 1.0]) if rot == 0 else np.array([-1.0, 0, 0])
    w = 1.0 if np.dot(dpdv, np.cross(tv, nv)) >= 0 else -1.0
    for (x, z), (u, v) in zip(cs, uvs):
        glVertexAttrib4f(1, ENT, 0, 0, 0); glVertexAttrib4f(2, ou + su / 2, ov + su / 2, 0, 0); glVertexAttrib4f(3, T[0], T[1], T[2], w)
        glVertexAttrib4f(4, (x0 + 0.5 - x) * 64, -0.5 * 64, (z0 + 0.5 - z) * 64, 0)
        glColor4f(1, 1, 1, 1); glNormal3f(0, 1, 0); glMultiTexCoord2f(0x84C0, ou + u, ov + v); glMultiTexCoord2f(0x84C1, 240, 240)
        glVertex3f(x - eye[0], y - eye[1], z - eye[2])
glBegin(0x0007)
ROT = int(os.environ.get("ROT", "0"))
for bx in range(-6, 7):
    for bz in range(-2, 10):
        face(bx, bz, 0.0, ROT)
glEnd(); glFinish()
glBindTexture(T2D, outs[0]); a = np.zeros((H, W, 4), np.float32); glGetTexImage(T2D, 0, 0x1908, 0x1406, a.ctypes.data_as(c_void_p))
from PIL import Image
col = np.clip(a[::-1, :, :3], 0, 1)
if os.environ.get("SHADE"):
    glBindTexture(T2D, outs[1]); b = np.zeros((H, W, 4), np.float32); glGetTexImage(T2D, 0, 0x1908, 0x1406, b.ctypes.data_as(c_void_p))
    e = b[::-1, :, :2] * 2 - 1; n = np.dstack([e[..., 0], e[..., 1], 1 - np.abs(e[..., 0]) - np.abs(e[..., 1])])
    neg = n[..., 2] < 0
    sx = np.where(n[..., 0] >= 0, 1.0, -1.0); sy = np.where(n[..., 1] >= 0, 1.0, -1.0)
    nx = np.where(neg, (1 - np.abs(n[..., 1])) * sx, n[..., 0]); ny = np.where(neg, (1 - np.abs(n[..., 0])) * sy, n[..., 1])
    n = np.dstack([nx, ny, n[..., 2]]); n /= np.linalg.norm(n, axis=2, keepdims=True) + 1e-9
    L = np.array([float(v) for v in os.environ.get("SUN", "0.6,0.5,0.2").split(",")]); L /= np.linalg.norm(L)
    sh = 0.2 + 0.8 * np.clip(n @ L, 0, 1)
    col = col * sh[..., None] * (a[::-1, :, 3:4] > -1)
img = (np.clip(col, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)
if os.environ.get("DUMP"):
    arrs=[]
    for o in outs:
        glBindTexture(T2D, o); b = np.zeros((H, W, 4), np.float32); glGetTexImage(T2D, 0, 0x1908, 0x1406, b.ctypes.data_as(c_void_p)); arrs.append(b[::-1])
    np.save(os.environ["DUMP"], np.stack(arrs))
Image.fromarray(img).save(os.environ.get("OUT", "pom") + ".png"); print("saved", os.environ.get("OUT", "pom") + ".png")
