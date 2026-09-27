#!/usr/bin/env python3
"""FULL FRAME PROFILER (since 4.51, shipped since 4.61): the real deferred_a/b/c, deferred, deferred1-6, composite,
composite1, composite2 and final passes of a pack tree, run in Iris' order on Mesa llvmpipe,
with Iris' buffer flipping, in a synthetic village (terrain, houses with torches, trees,
a pool, polished and metal blocks, villagers in the entity grid, textured voxels).

Run from anywhere; needs Linux with Mesa (libEGL, libGL), numpy and Pillow, and tools/mesa_check.py
next to this file. Example, comparing an older tree with the current one at 320x180:
  TREES="old=../CORAL-4.60 new=." W=320 H=180 python3 tools/frame_prof.py

Env:
  TREES   "name=path name=path ..." (path = folder holding shaders/); default: the pack this
          tool belongs to ("pack=..")
  VIEWS   substring filter on view names
  W, H    resolution (640x360)
  FRAMES  frames per view (8; the first 3 are warm-up and not timed)
  (llvmpipe runs compute passes on ONE thread here but fragment passes on all cores: set
   LP_NUM_THREADS=1 when compute and fragment passes are compared with each other)
  OUT     prefix for the saved images (final output per view and tree) and the .npz with HDR
Prints per pass median milliseconds, and the difference of every tree's final HDR image
(colortex0 before final) against the first tree.
"""
import ctypes, os, sys, math, time, re
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
SKYONE = 1 << 20   # count unit of the sky volume (65536 before 4.54), set per tree
ROOT = os.path.dirname(HERE)
exec(open(os.path.join(HERE, "mesa_check.py")).read().split("def main():")[0])
WORK = os.environ.get("WORKDIR", os.path.join(os.getcwd(), "frame_prof_out"))
os.makedirs(WORK, exist_ok=True)

c_uint, c_int, c_void_p, c_float = ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_float
def g(n, r, *a): return fn(n, r, *a)
glGenTextures = g("glGenTextures", None, c_int, ctypes.POINTER(c_uint)); glBindTexture = g("glBindTexture", None, c_uint, c_uint)
glTexImage2D = g("glTexImage2D", None, c_uint, c_int, c_int, c_int, c_int, c_int, c_uint, c_uint, c_void_p)
glTexImage3D = g("glTexImage3D", None, c_uint, c_int, c_int, c_int, c_int, c_int, c_int, c_uint, c_uint, c_void_p)
glTexSubImage2D = g("glTexSubImage2D", None, c_uint, c_int, c_int, c_int, c_int, c_int, c_uint, c_uint, c_void_p)
glTexParameteri = g("glTexParameteri", None, c_uint, c_uint, c_int); glActiveTexture = g("glActiveTexture", None, c_uint)
glGenerateMipmap = g("glGenerateMipmap", None, c_uint)
glUseProgram = g("glUseProgram", None, c_uint); glGetUniformLocation = g("glGetUniformLocation", c_int, c_uint, ctypes.c_char_p)
glUniform1i = g("glUniform1i", None, c_int, c_int); glUniform2i = g("glUniform2i", None, c_int, c_int, c_int)
glUniform1f = g("glUniform1f", None, c_int, c_float); glUniform3f = g("glUniform3f", None, c_int, c_float, c_float, c_float)
glUniformMatrix4fv = g("glUniformMatrix4fv", None, c_int, c_int, ctypes.c_ubyte, ctypes.POINTER(c_float))
glDispatchCompute = g("glDispatchCompute", None, c_uint, c_uint, c_uint); glMemoryBarrier = g("glMemoryBarrier", None, c_uint)
glBindImageTexture = g("glBindImageTexture", None, c_uint, c_uint, c_int, ctypes.c_ubyte, c_int, c_uint, c_uint)
glGetTexImage = g("glGetTexImage", None, c_uint, c_int, c_uint, c_uint, c_void_p); glFinish = g("glFinish", None)
glGenFramebuffers = g("glGenFramebuffers", None, c_int, ctypes.POINTER(c_uint)); glBindFramebuffer = g("glBindFramebuffer", None, c_uint, c_uint)
glFramebufferTexture2D = g("glFramebufferTexture2D", None, c_uint, c_uint, c_uint, c_uint, c_int)
glDrawBuffers = g("glDrawBuffers", None, c_int, ctypes.POINTER(c_uint)); glViewport = g("glViewport", None, c_int, c_int, c_int, c_int)
glCheckFramebufferStatus = g("glCheckFramebufferStatus", c_uint, c_uint)
glClearColor = g("glClearColor", None, c_float, c_float, c_float, c_float); glClear = g("glClear", None, c_uint)
glBegin = g("glBegin", None, c_uint); glEnd = g("glEnd", None); glVertex2f = g("glVertex2f", None, c_float, c_float)
glVertex3f = g("glVertex3f", None, c_float, c_float, c_float); glColor4f = g("glColor4f", None, c_float, c_float, c_float, c_float)
glMultiTexCoord2f = g("glMultiTexCoord2f", None, c_uint, c_float, c_float); glDisable = g("glDisable", None, c_uint)
glMatrixMode = g("glMatrixMode", None, c_uint); glLoadMatrixf = g("glLoadMatrixf", None, ctypes.POINTER(c_float))
glGetActiveUniform = g("glGetActiveUniform", None, c_uint, c_uint, c_int, ctypes.POINTER(c_int), ctypes.POINTER(c_int), ctypes.POINTER(c_uint), ctypes.c_char_p)

T2D, T3D, ALLB, GL_RW, GL_WO = 0x0DE1, 0x806F, 0xFFFFFFFF, 0x88BA, 0x88B9
RGBA8, RGBA16, RGBA16F, R32F, R32UI = 0x8058, 0x805B, 0x881A, 0x822E, 0x8236
RGBA, RED, REDI, FLOAT, UBYTE, USHORT, UINT = 0x1908, 0x1903, 0x8D94, 0x1406, 0x1401, 0x1403, 0x1405
W, H = int(os.environ.get("W", "640")), int(os.environ.get("H", "360"))
FRAMES = int(os.environ.get("FRAMES", "8"))
REPS = int(os.environ.get("REPS", "1"))
OCCUPANCY = False
REP_PASSES = set(os.environ.get("REP_PASSES", "deferred deferred3 deferred4 deferred5 deferred6 composite").split())
VX, VY, VZ = 128, 96, 128

def tex2(ifmt, fmt, typ, w, h, data=None, mip=False):
    t = c_uint(); glGenTextures(1, ctypes.byref(t)); glBindTexture(T2D, t.value)
    glTexImage2D(T2D, 0, ifmt, w, h, 0, fmt, typ, data.ctypes.data_as(c_void_p) if data is not None else None)
    glTexParameteri(T2D, 0x2801, 0x2702 if mip else 0x2600); glTexParameteri(T2D, 0x2800, 0x2600)
    glTexParameteri(T2D, 0x2802, 0x812F); glTexParameteri(T2D, 0x2803, 0x812F)   # clamp to edge
    return t.value
def tex3(ifmt, fmt, typ, size, data=None):
    t = c_uint(); glGenTextures(1, ctypes.byref(t)); glBindTexture(T3D, t.value)
    glTexImage3D(T3D, 0, ifmt, *size, 0, fmt, typ, data.ctypes.data_as(c_void_p) if data is not None else None)
    glTexParameteri(T3D, 0x2801, 0x2600); glTexParameteri(T3D, 0x2800, 0x2600)
    return t.value
def up3(t, ifmt, fmt, typ, size, data):
    glBindTexture(T3D, t); glTexImage3D(T3D, 0, ifmt, *size, 0, fmt, typ, np.ascontiguousarray(data).ctypes.data_as(c_void_p))
def up2(t, ifmt, fmt, typ, w, h, data):
    glBindTexture(T2D, t); glTexImage2D(T2D, 0, ifmt, w, h, 0, fmt, typ, np.ascontiguousarray(data).ctypes.data_as(c_void_p))

# =============================================================== scene (voxel coordinates)
# The camera's block is voxel (64, 48, 64); world = voxel - (64, 48, 64) + floor(camera).
rng = np.random.default_rng(3)
vox = np.zeros((VZ, VY, VX, 4), np.uint8)
FULL = (1 << 16) | (1 << 23) | (1 << 24) | (1 << 31) | 1 | (1 << 15)
code = np.zeros((VZ, VY, VX), np.uint8)
def put(x, y, z, rgb, c=1):
    if 0 <= x < VX and 0 <= y < VY and 0 <= z < VZ:
        vox[z, y, x] = [*rgb, c]; code[z, y, x] = c
def clear(x, y, z):
    if 0 <= x < VX and 0 <= y < VY and 0 <= z < VZ:
        vox[z, y, x] = 0; code[z, y, x] = 0
GROUND = 44
xs, zs = np.meshgrid(np.arange(VX), np.arange(VZ))
hmap = GROUND + np.round(2.5 * np.sin(xs / 11.0) * np.cos(zs / 13.0) + 1.5 * np.sin((xs + zs) / 7.0)).astype(int)
hmap[40:90, 40:90] = GROUND                                   # a flat village square
for z in range(VZ):
    for x in range(VX):
        top = hmap[z, x]
        for y in range(max(top - 6, 0), top + 1):
            put(x, y, z, (95, 150, 60) if y == top else (120, 85, 55))
# pool 12 x 10, 4 deep, water surface at the ground level
POOL = (70, 82, 52, 62)
for x in range(POOL[0], POOL[1]):
    for z in range(POOL[2], POOL[3]):
        for y in range(GROUND - 3, GROUND + 1): clear(x, y, z)
        put(x, GROUND - 4, z, (200, 190, 150))
SURF_Y = GROUND + 0.89          # water surface (voxel y)
# houses: stone brick walls with a door and windows, plank roof, torches inside and at the door
def house(x0, z0, w, d, hgt):
    for x in range(x0, x0 + w):
        for z in range(z0, z0 + d):
            put(x, GROUND, z, (150, 110, 70))                       # plank floor
            put(x, GROUND + hgt + 1, z, (150, 110, 70))             # roof
            if x in (x0, x0 + w - 1) or z in (z0, z0 + d - 1):
                for y in range(GROUND + 1, GROUND + hgt + 1): put(x, y, z, (140, 140, 140))
    for y in (GROUND + 1, GROUND + 2): clear(x0 + w // 2, y, z0)       # door
    clear(x0, GROUND + 2, z0 + d // 2); clear(x0 + w - 1, GROUND + 2, z0 + d // 2)   # windows
    put(x0 + 1, GROUND + 2, z0 + 1, (255, 200, 120), 11)            # torches inside (fire category)
    put(x0 + w - 2, GROUND + 2, z0 + d - 2, (255, 200, 120), 11)
    put(x0 + w // 2 + 1, GROUND + 2, z0 - 1, (255, 200, 120), 11)   # at the door
house(48, 70, 9, 8, 4); house(60, 72, 7, 7, 4); house(86, 66, 8, 9, 5); house(44, 44, 8, 7, 4)
def tree(x, z):
    for y in range(GROUND + 1, GROUND + 5): put(x, y, z, (100, 75, 45))
    for dx in range(-2, 3):
        for dz in range(-2, 3):
            for y in range(GROUND + 4, GROUND + 7):
                if abs(dx) + abs(dz) + (y - GROUND - 4) < 4 and code[z + dz, y, x + dx] == 0: put(x + dx, y, z + dz, (60, 120, 40), 2)
for (tx, tz) in ((56, 56), (92, 50), (40, 60), (66, 88), (100, 80), (34, 90)): tree(tx, tz)
for x in range(58, 68):                                            # a polished stone plaza
    for z in range(54, 62): put(x, GROUND, z, (185, 185, 190), 3)
for y in range(GROUND + 1, GROUND + 4):                            # iron block pillar and a gold one
    put(64, y, 60, (215, 215, 215), 4); put(67, y, 57, (240, 200, 70), 4)
for (lx, lz) in ((58, 54), (68, 62), (76, 64), (84, 50)): put(lx, GROUND + 1, lz, (255, 230, 170), 13)   # lamps
# GLASS TEST CHAMBER (env GLASSTEST): a closed dark room (x 100-116, y 60-66, z 20-37) with four
# alcoves in its far wall.
#   1: a stained glass block flush with the wall and a lamp behind it (block light through glass)
#   2: the same without the glass
#   3: the alcoves are open shafts to the sky, capped with stained glass at the roof (sunlight
#      and sky light through glass into a dark room); 4: the same without the glass
# The glass colors are vanilla's (red, blue, lime, yellow; alpha 0.46); what goes into the grid
# is computed per tree with that tree's formula (glass_voxel below).
GLASSTEST = int(os.environ.get("GLASSTEST", "0"))
GLASS_CELLS = []   # (x, y, z, srgb 0..1, alpha)
GLASS_SRGB = [(0.6, 0.2, 0.2), (0.2, 0.298, 0.698), (0.498, 0.8, 0.098), (0.898, 0.898, 0.2)]
if GLASSTEST:
    for x in range(100, 117):
        for y in range(60, 67):
            for z in range(20, 38):
                if x in (100, 116) or y in (60, 66) or z in (20, 37): put(x, y, z, (170, 170, 170))
                else: clear(x, y, z)
    for x in range(101, 116):                                   # the far wall (z 35) and the lamp layer (z 36)
        for y in range(61, 66):
            put(x, y, 35, (170, 170, 170)); put(x, y, 36, (170, 170, 170))
    for k, ax in enumerate((103, 106, 109, 112)):
        if GLASSTEST in (1, 2):
            for y in range(61, 64):
                if GLASSTEST == 1:
                    put(ax, y, 35, (255, 255, 255), 5); GLASS_CELLS.append((ax, y, 35, GLASS_SRGB[k], 0.46))
                else: clear(ax, y, 35)
            put(ax, 62, 36, (255, 230, 170), 13)                # the lamp behind it
        elif GLASSTEST == 5:                                     # two blocks of glass, the lamp behind them
            for y in range(61, 64):
                for z in (35, 36):
                    put(ax, y, z, (255, 255, 255), 5); GLASS_CELLS.append((ax, y, z, GLASS_SRGB[k], 0.46))
            put(ax, 62, 37, (255, 230, 170), 13); put(ax, 62, 38, (170, 170, 170))
        elif GLASSTEST in (3, 4, 6):
            for y in range(61, 66):                              # a shaft 1 x 2 up to the roof
                clear(ax, y, 35); clear(ax, y, 36)
            for z in (35, 36):
                if GLASSTEST == 3:
                    put(ax, 66, z, (255, 255, 255), 5); GLASS_CELLS.append((ax, 66, z, GLASS_SRGB[k], 0.46))
                else: clear(ax, 66, z)
if GLASSTEST == 7:
    # a corridor roofed with stained glass in rows of colors (red, blue, lime, yellow, light
    # blue, pink), open to the sky above the glass: the second screenshot of the 4.55 report
    ROW = [(0.6, 0.2, 0.2), (0.2, 0.298, 0.698), (0.498, 0.8, 0.098), (0.898, 0.898, 0.2), (0.4, 0.6, 0.847), (0.95, 0.5, 0.65)]
    for x in range(103, 114):
        for z in range(18, 40):
            for y in range(60, 75): clear(x, y, z)
            put(x, 60, z, (225, 225, 225))                       # white floor
            if x in (103, 113) or z in (18, 39):
                for y in range(61, 67): put(x, y, z, (215, 205, 190))
            else:
                k = ((z - 19) // 3) % len(ROW)
                put(x, 67, z, (255, 255, 255), 5); GLASS_CELLS.append((x, 67, z, ROW[k], 0.46))
        for z in range(18, 40): put(x, 67, z, (215, 205, 190)) if x in (103, 113) else None
if GLASSTEST in (8, 9):
    # A HALL (4.56 "paintball" test): 28 x 10 x 28 stone room, four torches on the walls,
    # two pillars; 9 adds a slit in the ceiling that lets the sun in (like a skylight)
    for x in range(96, 125):
        for y in range(60, 71):
            for z in range(16, 45):
                if x in (96, 124) or y in (60, 70) or z in (16, 44):
                    put(x, y, z, (150, 110, 70) if y == 60 else (140, 140, 140))
                else: clear(x, y, z)
    for (px_, pz_) in ((104, 30), (116, 30)):
        for y in range(61, 70): put(px_, y, pz_, (170, 165, 150))
    for (tx, ty, tz) in ((97, 63, 24), (123, 63, 36), (110, 63, 43), (104, 63, 17)): put(tx, ty, tz, (255, 200, 120), 11)
    if GLASSTEST == 9:
        for z in range(22, 40): clear(110, 70, z)                 # the slit
if GLASSTEST in (10, 11):
    # LEAK TEST (4.58): two rooms side by side (A: x 96-108, B: x 108-120, shared wall x 108),
    # y 60-66, z 16-30. 10: a lamp in B's corner against the shared wall; A stays dark.
    # 11: A has a 2 x 6 hole in its roof (daylight); CHANGE_AT closes it.
    for x in range(96, 121):
        for y in range(60, 67):
            for z in range(16, 31):
                if x in (96, 108, 120) or y in (60, 66) or z in (16, 30): put(x, y, z, (150, 150, 150))
                else: clear(x, y, z)
    if GLASSTEST == 10:
        put(109, 61, 29, (255, 60, 40), 13)
    else:
        for x in (101, 102):
            for z in range(20, 26): clear(x, 66, z)
if GLASSTEST == 12:
    # GOLD FLOOR (4.58): a 12 x 12 room with a floor of metal blocks (the G-buffer gives them
    # a darker two-texel rim, like vanilla gold), yellow walls, a lamp; daylight from a hole
    for x in range(98, 114):
        for y in range(60, 68):
            for z in range(16, 32):
                if x in (98, 113) or y in (60, 67) or z in (16, 31):
                    put(x, y, z, (245, 204, 39), 4) if y == 60 else put(x, y, z, (230, 220, 150))
                else: clear(x, y, z)
    for x in range(104, 108):
        for z in range(22, 26): clear(x, 67, z)
    put(99, 63, 17, (255, 230, 170), 13)
DOOR_CELLS = []
if GLASSTEST == 13:
    # A CLOSED DOOR between two rooms (4.58): A x 96-108, B x 108-120, the door in the shared
    # wall (x 108, y 61-62, z 23) as a slab over the quarter of its cell on A's side; a lamp
    # in B next to it. A pixel of A that comes into view next to the door must not start
    # with B's light (world cache seed).
    for x in range(96, 121):
        for y in range(60, 67):
            for z in range(16, 31):
                if x in (96, 108, 120) or y in (60, 66) or z in (16, 30): put(x, y, z, (150, 150, 150))
                else: clear(x, y, z)
    for y in (61, 62):
        put(108, y, 23, (120, 90, 60)); DOOR_CELLS.append((108, y, 23))
    put(111, 61, 25, (255, 60, 40), 13)
def apply_change():
    if GLASSTEST == 11:
        for x in (101, 102):
            for z in range(20, 26): put(x, 66, z, (150, 150, 150))
def glass_voxel(srgb, a, newf):
    c = np.array(srgb, float)
    if newf:
        lin = c ** 2.2; hue = lin / max(lin.max(), 1e-4)
        f = 1.0 + (hue - 1.0) * 0.85 * min(a * 2.5, 1.0)
        return np.clip(f * (1.0 + (c.max() - 1.0) * 0.5) * (1.0 - 0.1 * a), 0.01, 1.0)
    t = 1.0 + (c - 1.0) * 0.85
    return np.clip(t * (1.0 - 0.55 * a), 0.01, 1.0)
def glass_shadow(srgb, a, newf):
    return glass_voxel(srgb, a, True) if newf else np.array(srgb, float)
def derive():
    global shape, LIGHTS, solid, above, skyopen, sky15, skyvol, sub, SKH, SK
    shape = np.where(code > 0, FULL, 0).astype(np.uint32)
    for (dx_, dy_, dz_) in DOOR_CELLS: shape[dz_, dy_, dx_] = (1 << 16) | (1 << 17) | 1 | (1 << 15) | (1 << 24) | (1 << 31)
    LIGHTS = [(x, y, z) for z, y, x in zip(*np.nonzero(code >= 11))]

    # sky light: 1 where nothing solid is above, else by how open the neighbourhood is
    solid = (code > 0) & (code != 5)          # stained glass lets sky light through, as in vanilla
    above = np.flip(np.cumsum(np.flip(solid, axis=1), axis=1), axis=1) - solid   # solids strictly above
    skyopen = (above == 0)
    # the vanilla-like lightmap of an air cell: open sky 15, under a roof but near an opening lower
    sky15 = skyopen.astype(np.float32)
    if GLASSTEST:
        # vanilla: one level less per block, in all six directions
        for _ in range(15):
            nb = np.maximum.reduce([np.roll(sky15, s_, a_) for a_ in (0, 1, 2) for s_ in (1, -1)]) - 1.0 / 15.0
            sky15 = np.where(solid, 0.0, np.maximum(sky15, nb))
        if GLASSTEST == 6:
            # the open shafts with the room itself as dark as a cave (sky light 0 outside the shafts):
            # does sunlight that lands in a shaft bounce into the room?
            sky15[20:35, 61:66, 101:116] = 0.0
    else:
        for _ in range(4):
            nb = np.maximum.reduce([np.roll(sky15, s__, a__) for a__ in (0, 2) for s__ in (1, -1)]) * 0.8
            sky15 = np.where(solid, 0.0, np.maximum(sky15, nb))
    SKH = 36; SK = 72
    skyvol = np.zeros((SK, SK, SK), np.uint32)
    sub = sky15[64 - SKH:64 + SKH, max(48 - SKH, 0):48 + SKH, 64 - SKH:64 + SKH]
    skyvol[:, SKH - 48 + max(48 - SKH, 0):SKH - 48 + max(48 - SKH, 0) + sub.shape[1], :] = (sub * 255 + 0.5).astype(np.uint32) + SKYONE

derive()
VOX0 = vox.copy(); CODE0 = code.copy()
skyLM = sky15   # read by the G-buffer below

# textured voxels: every face of every block points at a sprite of a 256x256 atlas
A = 256
atlas = np.zeros((A, A, 4), np.uint8); atlas[..., 3] = 255
for sid in range(16):
    ox, oy = (sid % 16) * 16, (sid // 16) * 16
    base = rng.integers(60, 200, 3)
    atlas[oy:oy + 16, ox:ox + 16, :3] = np.clip(base + rng.integers(-35, 35, (16, 16, 3)), 0, 255)
faceTex = np.zeros((VZ, VY * 2, VX * 4), np.uint32)
spr = (code.astype(np.uint32) * 7 + 3) % 16
word = np.where(code > 0, (spr * 1) | (0 << 12) | (1 << 24), 0).astype(np.uint32)
for w in range(6): faceTex[:, (w >> 2)::2, (w & 3)::4] = word

# water surface map (height (y + 256) * 64, relative to the camera's block y 48)
water = np.zeros((VZ, VX), np.uint32)
water[POOL[2]:POOL[3], POOL[0]:POOL[1]] = int((SURF_Y - 48 + 256) * 64)

# =============================================================== views
# name, eye (voxel), yaw, pitch, isEyeInWater, worldTime
VIEWS_ALL = [
    ("day square", (64.5, GROUND + 2.6, 46.0), 80, -8, 0, 6000),
    ("day pool", (76.0, GROUND + 3.2, 44.0), 90, -30, 0, 6000),
    ("night house", (52.5, GROUND + 2.6, 73.0), 60, -10, 0, 18000),
    ("under water", (76.0, GROUND - 1.5, 55.0), 90, 35, 1, 6000),
    ("lake close", (76.0, GROUND + 2.4, 51.5), 90, -38, 0, 6000),
    ("glass room", (108.5, 62.6, 23.5), 90, -12, 0, 18000),
    ("glass day", (108.5, 62.6, 23.5), 90, -2, 0, 6000),
    ("glass corridor", (108.5, 62.2, 20.5), 80, 8, 0, 4500),
    ("hall night", (110.5, 62.6, 19.5), 90, 12, 0, 18000),
    ("hall day", (110.5, 62.6, 19.5), 90, 12, 0, 6000),
    ("leak night", (100.5, 62.6, 18.5), 57, -8, 0, 18000),
    ("leak day", (100.5, 62.6, 18.5), 70, 10, 0, 6000),
    ("gold floor", (100.5, 63.6, 18.5), 55, -35, 0, 6000),
    ("door night", (103.5, 62.6, 23.5), 180, -30, 0, 18000),
]
VIEWS = [v for v in VIEWS_ALL if os.environ.get("VIEWS", "") in v[0]]

fov, near, far = math.radians(70.0), 0.05, 256.0
P = np.zeros((4, 4)); t_ = 1 / math.tan(fov / 2); P[0, 0] = t_ / (W / H); P[1, 1] = t_
P[2, 2] = (far + near) / (near - far); P[2, 3] = 2 * far * near / (near - far); P[3, 2] = -1
def view_matrix(yaw_deg, pitch_deg):
    yw, pt = math.radians(yaw_deg), math.radians(pitch_deg)
    fw = np.array([math.cos(pt) * math.cos(yw), math.sin(pt), math.cos(pt) * math.sin(yw)])
    rr = np.cross(fw, [0, 1, 0]); rr /= np.linalg.norm(rr); uu = np.cross(rr, fw)
    mv = np.eye(4); mv[0, :3], mv[1, :3], mv[2, :3] = rr, uu, -fw; return mv
def sun_dir(wt):
    ang = (wt - 6000) / 24000.0 * 2 * math.pi
    d = np.array([math.sin(ang) * 0.9, math.cos(ang), 0.25]); return d / np.linalg.norm(d)

# =============================================================== GL resources
fbo = c_uint(); glGenFramebuffers(1, ctypes.byref(fbo))
voxT = tex3(RGBA8, RGBA, UBYTE, (VX, VY, VZ), vox)
shapeT = tex3(R32UI, REDI, UINT, (VX, VY, VZ), shape)
solidT = tex3(R32UI, REDI, UINT, (VX, VY, VZ), np.zeros_like(shape))
maskT = tex3(R32UI, REDI, UINT, (1024, 96, 128), np.zeros((128, 96, 1024), np.uint32))
faceT = tex3(R32UI, REDI, UINT, (VX * 4, VY * 2, VZ), faceTex)
atlasT = tex2(RGBA8, RGBA, UBYTE, A, A, atlas, mip=True); glGenerateMipmap(T2D)
waterT = tex2(R32UI, REDI, UINT, VX, VZ, water)
skyT = tex3(R32UI, REDI, UINT, (SK, SK, SK), skyvol)
EW, EG = 388, 64
entT = tex3(R32UI, REDI, UINT, (EW, EG, EG), np.zeros((EG, EG, EW), np.uint32))
CS = 64
cacheT = tex3(RGBA16F, RGBA, FLOAT, (12 * CS, CS, CS))
metaT = tex3(R32UI, REDI, UINT, (6 * CS, CS, CS))
listT = tex2(R32UI, REDI, UINT, 512, 256, np.zeros((256, 512), np.uint32))
countT = tex2(R32UI, REDI, UINT, 4, 1, np.zeros((1, 4), np.uint32))
stateT = tex2(R32UI, REDI, UINT, 8, 1, np.zeros((1, 8), np.uint32))
SHN = 2048
shadowT = tex2(R32F, RED, FLOAT, SHN, SHN, np.ones((SHN, SHN), np.float32))
shadow0T = tex2(R32F, RED, FLOAT, SHN, SHN, np.ones((SHN, SHN), np.float32))
shcolT = tex2(RGBA8, RGBA, UBYTE, SHN, SHN, np.zeros((SHN, SHN, 4), np.uint8))
glassColT = tex3(RGBA8, RGBA, UBYTE, (VX, VY, VZ), np.zeros((VZ, VY, VX, 4), np.uint8))

# light grid (VOXEL_RANGE 128, LIGHT_GRID_CAP 64): home lists filled like the shadow pass does
LG_DIM = (16, 12, 16); LG_ROWS = 3072; LG_BLOCKS = 1; HOME_W = 19; SUP = (4, 3, 4)
GRID_W = 281
def build_home(lights, occ=None):
    home = np.zeros((LG_ROWS, GRID_W), np.uint32)
    if occ is not None and OCCUPANCY:
        # bit 31 of word 18: the region holds a block (4.51 shadow pass)
        for (rz, ry, rx) in zip(*np.nonzero(occ)):
            idx = rx + ry * LG_DIM[0] + rz * LG_DIM[0] * LG_DIM[1]
            home[idx % LG_ROWS, (idx // LG_ROWS) * HOME_W + 18] |= np.uint32(1 << 31)
    for (x, y, z) in lights:
        r = (x // 8, y // 8, z // 8)
        idx = r[0] + r[1] * LG_DIM[0] + r[2] * LG_DIM[0] * LG_DIM[1]
        row, col = idx % LG_ROWS, (idx // LG_ROWS) * HOME_W
        bit = (x % 8) + (y % 8) * 8 + (z % 8) * 64
        w = 1 + (bit >> 5)
        if (int(home[row, col + w]) >> (bit & 31)) & 1: continue
        home[row, col + w] |= np.uint32(1 << (bit & 31))
        before = int(home[row, col]); home[row, col] += 1
        home[row, col + 18] += np.uint32(int(2.0 * 256))
        if before == 0:
            s = (r[0] // 4, r[1] // 4, r[2] // 4); si = s[0] + s[1] * SUP[0] + s[2] * SUP[0] * SUP[1]
            if home[si, LG_BLOCKS * HOME_W] == 0:
                n = int(home[0, LG_BLOCKS * HOME_W + 1]); home[0, LG_BLOCKS * HOME_W + 1] += 1
                home[1 + n, LG_BLOCKS * HOME_W + 1] = si
            home[si, LG_BLOCKS * HOME_W] += 1
    return home
HOME = build_home(LIGHTS)
gridT = tex2(R32UI, REDI, UINT, GRID_W, LG_ROWS, HOME)

# screen buffers: two copies each (Iris flips them), formats of lib/pipeline.glsl
FMT = {0: (RGBA16F, FLOAT), 1: (RGBA16, USHORT), 2: (RGBA8, UBYTE), 3: (RGBA16F, FLOAT), 4: (RGBA16F, FLOAT), 5: (RGBA16, USHORT),
       6: (RGBA8, UBYTE), 7: (R32F, FLOAT), 8: (RGBA16F, FLOAT), 9: (RGBA16F, FLOAT), 10: (RGBA16F, FLOAT), 11: (RGBA16F, FLOAT)}
CLEARED = {0, 1, 2, 3, 5, 6, 8, 9}
def mk(n):
    ifmt, typ = FMT[n]
    t = tex2(ifmt, RED if ifmt == R32F else RGBA, typ, W, H)
    glTexParameteri(T2D, 0x2801, 0x2601); glTexParameteri(T2D, 0x2800, 0x2601)
    return t
CT = {n: [mk(n), mk(n)] for n in range(12)}
CUR = {n: 0 for n in range(12)}
depth0T = tex2(R32F, RED, FLOAT, W, H); depth1T = tex2(R32F, RED, FLOAT, W, H); depthOpT = tex2(R32F, RED, FLOAT, W, H)
screenT = tex2(RGBA8, RGBA, UBYTE, W, H)

# volumetric clouds (4.53): the screen (half or full resolution, set per tree) and the dome
cloudT = tex2(RGBA16F, RGBA, FLOAT, W, H)
glTexParameteri(T2D, 0x2801, 0x2601); glTexParameteri(T2D, 0x2800, 0x2601)
glTexParameteri(T2D, 0x2802, 0x812F); glTexParameteri(T2D, 0x2803, 0x812F)
cloudDomeT = tex2(RGBA16F, RGBA, FLOAT, 512, 512)
glTexParameteri(T2D, 0x2801, 0x2601); glTexParameteri(T2D, 0x2800, 0x2601)
reflT = tex2(RGBA16F, RGBA, FLOAT, (W + 1) // 2, (H + 1) // 2)
shHalfT = tex2(RGBA16F, RGBA, FLOAT, (W + 1) // 2, (H + 1) // 2)
clockT = tex2(R32F, RED, FLOAT, 2, 1, np.zeros((1, 2), np.float32))
glTexParameteri(T2D, 0x2801, 0x2600); glTexParameteri(T2D, 0x2800, 0x2600)
CLOUDRES = {}
def cloud_alloc(half):
    w, h = ((W + 1) // 2, (H + 1) // 2) if half else (W, H)
    up2(cloudT, RGBA16F, RGBA, FLOAT, w, h, np.zeros((h, w, 4), np.float32))
    up2(cloudDomeT, RGBA16F, RGBA, FLOAT, 512, 512, np.zeros((512, 512, 4), np.float32))
    CLOUDRES["wh"] = (w, h)
SAMPLERS = {"shadowHalfSampler": (T2D, shHalfT), "cloudSampler": (T2D, cloudT), "cloudDomeSampler": (T2D, cloudDomeT), "voxelSampler": (T3D, voxT), "shapeSampler": (T3D, shapeT), "solidSampler": (T3D, solidT), "maskSampler": (T3D, maskT),
            "faceTexSampler": (T3D, faceT), "blockAtlas": (T2D, atlasT), "waterSampler": (T2D, waterT), "giSkySampler": (T3D, skyT),
            "entitySampler": (T3D, entT), "giCacheSampler": (T3D, cacheT), "giCacheMetaSampler": (T3D, metaT), "giListSampler": (T2D, listT),
            "giListCountSampler": (T2D, countT), "giStateSampler": (T2D, stateT), "shadowtex0": (T2D, shadow0T), "shadowtex1": (T2D, shadowT), "glassColSampler": (T3D, glassColT),
            "shadowcolor0": (T2D, shcolT), "lightGridSampler": (T2D, gridT)}
IMAGES = {"lightGridImg": (gridT, R32UI, False), "giListImg": (listT, R32UI, False), "giListCountImg": (countT, R32UI, False),
          "giStateImg": (stateT, R32UI, False), "giCacheImg": (cacheT, RGBA16F, True), "giCacheMetaImg": (metaT, R32UI, True),
          "cloudImg": (cloudT, RGBA16F, False), "cloudDomeImg": (cloudDomeT, RGBA16F, False), "reflImg": (reflT, RGBA16F, False), "shadowHalfImg": (shHalfT, RGBA16F, False), "cloudClockImg": (clockT, R32F, False), "giSkyImg": (skyT, R32UI, True)}

def uniforms_of(p):
    cnt = ctypes.c_int(); glGetProgramiv(p, GL_ACTIVE_UNIFORMS, ctypes.byref(cnt)); out = {}
    for i in range(cnt.value):
        ln, sz, ty = c_int(), c_int(), c_uint(); nm = ctypes.create_string_buffer(256)
        glGetActiveUniform(p, i, 256, ctypes.byref(ln), ctypes.byref(sz), ctypes.byref(ty), nm)
        out[nm.value.decode()] = ty.value
    return out

STATE = {}
def set_uniforms(p, U, extra_samplers, strict=True):
    mv = STATE["mv"]; sd = STATE["sun"]
    night = sd[1] < 0
    sv = (mv[:3, :3] @ sd) * 100; lv = sv if not night else -sv
    vals = {"gbufferModelView": mv, "gbufferModelViewInverse": np.linalg.inv(mv), "gbufferProjection": P, "gbufferProjectionInverse": np.linalg.inv(P),
            "gbufferPreviousModelView": STATE.get("pmv", mv), "gbufferPreviousProjection": P, "shadowModelView": STATE["smv"], "shadowModelViewInverse": np.linalg.inv(STATE["smv"]),
            "shadowProjection": SPJ, "shadowProjectionInverse": np.linalg.inv(SPJ),
            "cameraPosition": STATE["cam"], "previousCameraPosition": STATE.get("pcam", STATE["cam"]), "sunPosition": sv, "moonPosition": -sv, "shadowLightPosition": lv,
            "fogColor": (0.6, 0.75, 0.95), "skyColor": (0.5, 0.7, 1.0), "viewWidth": W, "viewHeight": H, "near": near, "far": far,
            "frameTimeCounter": 10.0 + STATE["frame"] / 60.0, "frameTime": 1.0 / 60.0, "rainStrength": 0.0, "nightVision": 0.0, "blindness": 0.0,
            "frameCounter": STATE["frame"], "worldTime": STATE["wt"], "isEyeInWater": STATE["eye"], "heldBlockLightValue": 0, "heldBlockLightValue2": 0,
            "eyeBrightnessSmooth": (0, STATE["eyesky"])}
    unit = 0
    for name, ty in U.items():
        loc = glGetUniformLocation(p, name.encode())
        if loc < 0: continue
        if ty in (0x8B5E, 0x8B5F, 0x8DD2, 0x8DD3, 0x8B62, 0x8DCA, 0x8DCB):        # samplers
            src = extra_samplers.get(name) or SAMPLERS.get(name)
            if src is None:
                if strict: raise KeyError("no texture for sampler " + name)
                continue
            glActiveTexture(0x84C0 + unit); glBindTexture(*src); glUniform1i(loc, unit); unit += 1
        elif name in IMAGES:
            t, f, layered = IMAGES[name]
            iu = list(IMAGES).index(name)
            glBindImageTexture(iu, t, 0, 1 if layered else 0, 0, GL_RW, f); glUniform1i(loc, iu)
        elif name in vals:
            v = vals[name]
            if ty == 0x8B5C:
                a = np.ascontiguousarray(np.array(v, np.float32)); glUniformMatrix4fv(loc, 1, 1, a.ctypes.data_as(ctypes.POINTER(c_float)))
            elif ty == 0x8B51: glUniform3f(loc, *map(float, v))
            elif ty == 0x1406: glUniform1f(loc, float(v))
            elif ty == 0x1404: glUniform1i(loc, int(v))
            elif ty == 0x8B53: glUniform2i(loc, int(v[0]), int(v[1]))
        elif name.startswith("gl_") or not strict: pass
        else: raise KeyError("uniform without value: %s (%x)" % (name, ty))

# shadow camera
SPJ = np.diag([1 / 80.0, 1 / 80.0, -1 / 160.0, 1.0])
def shadow_mv(sd):
    z = sd if sd[1] > 0 else -sd
    r = np.cross([0.0, 1.0, 0.0], z); r /= np.linalg.norm(r); u = np.cross(z, r)
    m = np.eye(4); m[0, :3], m[1, :3], m[2, :3] = r, u, z; return m

def build_prog(work, name):
    root = os.path.join(work, "shaders"); wd = os.path.join(root, "world0")
    save = globals()["ROOT"]; globals()["ROOT"] = root
    try:
        if os.path.exists(os.path.join(wd, name + ".csh")):
            st = [(GL_COMPUTE_SHADER, name + ".csh", True)]
        elif os.path.exists(os.path.join(wd, name + ".gsh")):
            st = [(GL_VERTEX_SHADER, name + ".vsh", False), (GL_GEOMETRY_SHADER, name + ".gsh", False), (GL_FRAGMENT_SHADER, name + ".fsh", False)]
        else:
            st = [(GL_VERTEX_SHADER, name + ".vsh", False), (GL_FRAGMENT_SHADER, name + ".fsh", False)]
        sh = []
        for k, f, c in st:
            s, ok, log = compile_shader(k, prepare(os.path.join(wd, f), c)); assert ok, name + ": " + log[:3000]; sh.append(s)
        p, ok, log = link(sh); assert ok, log
        return p
    finally:
        globals()["ROOT"] = save
def build_cs_text(work, text, tag):
    root = os.path.join(work, "shaders"); save = globals()["ROOT"]; globals()["ROOT"] = root
    try:
        path = os.path.join(WORK, "_%s.glsl" % tag); open(path, "w").write(text)
        cs, ok, log = compile_shader(GL_COMPUTE_SHADER, expand(path)); assert ok, log[:3000]
        p, ok, log = link([cs]); assert ok, log; return p
    finally:
        globals()["ROOT"] = save

SHADOW_SRC = """#version 430 core
layout(local_size_x = 8, local_size_y = 8) in;
#define NO_ENTITY_TRACE
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/materials.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/voxel.glsl"
layout(r32f) writeonly uniform image2D outImg;
layout(r32f) writeonly uniform image2D out0Img;     // with the translucent blocks
layout(rgba8) writeonly uniform image2D colImg;     // shadowcolor0
uniform sampler3D glassColSampler;
void main() {
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);
    int N = imageSize(outImg).x;
    if (any(greaterThanEqual(t, ivec2(N)))) return;
    vec2 d = (vec2(t) + 0.5) / float(N) * 2.0 - 1.0;
    float D = SHADOW_DISTORTION;
    vec2 c = d * (1.0 - D) / max(1.0 - length(d) * D, 1e-4);
    vec3 sv = vec3(c.x / shadowProjection[0][0], c.y / shadowProjection[1][1], 150.0);
    vec3 start = mat3(shadowModelViewInverse) * sv;
    vec3 dir = -normalize(mat3(shadowModelViewInverse) * vec3(0.0, 0.0, 1.0));
    vec3 o = playerToVoxel(start);
    vec3 inv = 1.0 / dir;
    vec3 t1 = (vec3(0.01) - o) * inv, t2 = (vec3(VOXEL_VOLUME) - 0.01 - o) * inv;
    float tin = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z));
    float tout = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z));
    float depth = 1.0, depth0 = 1.0;
    vec4 col = vec4(0.0);
    if (tout > max(tin, 0.0)) {
        vec3 o2 = o + dir * (max(tin, 0.0) + 0.02);
        vec3 hp, hn; vec4 vd;
        float tHit = 1e9;
        if (traceVoxels(o2, dir, 600, 500.0, hp, hn, vd)) { depth = playerToShadowClip(voxelToPlayer(hp)).z * 0.5 + 0.5; tHit = distance(o2, hp); }
        // the first glass cell before it (a plain DDA over whole cells)
        ivec3 cell = ivec3(floor(o2)); ivec3 st = ivec3(sign(dir));
        vec3 tMax = ((vec3(cell) + max(vec3(st), 0.0)) - o2) * inv; vec3 tDel = abs(inv);
        float tc = 0.0;
        for (int i = 0; i < 700 && tc < tHit; i++) {
            if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, VOXEL_VOLUME))) break;
            vec4 g = texelFetch(glassColSampler, cell, 0);
            if (g.a > 0.5) {
                depth0 = playerToShadowClip(voxelToPlayer(o2 + dir * tc)).z * 0.5 + 0.5;
                col = vec4(g.rgb, 1.0);
                break;
            }
            if (tMax.x < tMax.y && tMax.x < tMax.z) { tc = tMax.x; tMax.x += tDel.x; cell.x += st.x; }
            else if (tMax.y < tMax.z) { tc = tMax.y; tMax.y += tDel.y; cell.y += st.y; }
            else { tc = tMax.z; tMax.z += tDel.z; cell.z += st.z; }
        }
    }
    if (depth0 > depth) depth0 = depth;
    imageStore(outImg, t, vec4(depth));
    imageStore(out0Img, t, vec4(depth0));
    imageStore(colImg, t, col);
}
"""
GBUF_SRC = """#version 430 core
layout(local_size_x = 8, local_size_y = 8) in;
#define NO_ENTITY_TRACE
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/materials.glsl"
#include "/lib/space.glsl"
#include "/lib/sky.glsl"
#include "/lib/voxel.glsl"
#include "/lib/water.glsl"
layout(rgba16f) writeonly uniform image2D c0Out;
layout(rgba16) writeonly uniform image2D c1Out;
layout(rgba8) writeonly uniform image2D c2Out;
layout(r32f) writeonly uniform image2D dOpOut;   // opaque depth
layout(r32f) writeonly uniform image2D dWatOut;  // depth with the water surface
layout(rgba16) writeonly uniform image2D c5Out;
layout(rgba16f) writeonly uniform image2D wColOut; // water color to blend (rgb, a opacity)
uniform usampler3D giSkySampler;
uniform vec4 pool;       // x0, x1, z0, z1 (voxel)
uniform float surfY;
float skyAt(ivec3 cell) {
    ivec3 r = cell - VOXEL_VOLUME / 2 + 36;
    if (any(lessThan(r, ivec3(0))) || any(greaterThanEqual(r, ivec3(72)))) return 1.0;
    uint w = texelFetch(giSkySampler, r, 0).r;
    uint n = w / SKYONE_U;
    return n == 0u ? 1.0 : float(w % SKYONE_U) / (255.0 * float(n));
}
void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (px.x >= int(viewWidth) || px.y >= int(viewHeight)) return;
    vec2 uv = (vec2(px) + 0.5) / vec2(viewWidth, viewHeight);
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * screenToView(uv, 1.0));
    vec3 o = playerToVoxel(vec3(0.0));
    vec3 hp, hn; vec4 vd;
    vec4 c0 = vec4(0.0), c1 = vec4(encodeNormal(vec3(0, 1, 0)), 0.0, 1.0), c2 = vec4(0.0);
    vec3 bevelN = vec3(0.0, 1.0, 0.0);
    float dOp = 1.0, tHit = 1e9;
    if (traceVoxels(o, dir, 400, 250.0, hp, hn, vd)) {
        tHit = distance(o, hp);
        dOp = viewToScreen(playerToView(voxelToPlayer(hp))).z;
        int c = int(vd.a * 255.0 + 0.5);
        // a little texture: the atlas-like noise of the block face
        vec3 tc = floor(hp * 16.0 - hn * 0.5);
        float n = hash33(uvec3(ivec3(tc) + 4096)).x * 0.25 + 0.875;
        c0 = vec4(vd.rgb * n, 1.0);
        if (c == VOXEL_METAL) {   // a darker rim two texels wide, like the vanilla gold block
            vec3 fr = fract(hp * 16.0 / 16.0);
            vec2 q = abs(hn.y) > 0.5 ? fr.xz : (abs(hn.x) > 0.5 ? fr.yz : fr.xy);
            if (any(lessThan(q, vec2(2.0 / 16.0))) || any(greaterThan(q, vec2(14.0 / 16.0)))) c0.rgb *= vec3(0.86, 0.74, 1.28);
        }
        bevelN = hn;
        if (BEVEL > 0.0 && (c == VOXEL_METAL || c == VOXEL_POLISHED)) {
            // a resource pack's bevelled edge at Normal Strength 4: the outer two texels of a
            // face lean outwards by BEVEL degrees
            vec3 fr = fract(hp - hn * 0.01);
            vec3 out3 = vec3(0.0);
            for (int a = 0; a < 3; a++) {
                if (abs(hn[a]) > 0.5) continue;
                if (fr[a] < 2.0 / 16.0) out3[a] = -1.0; else if (fr[a] > 14.0 / 16.0) out3[a] = 1.0;
            }
            if (dot(out3, out3) > 0.0) bevelN = normalize(hn * cos(radians(BEVEL)) + normalize(out3) * sin(radians(BEVEL)));
        }
        float lmSky = skyAt(ivec3(floor(hp + hn * 0.5)));
        c1 = vec4(encodeNormal(bevelN), 0.0, lmSky);
        int mat = MAT_LIT; float emis = 0.0, smooth_ = 0.0, f0 = 0.04;
        if (c == VOXEL_LEAVES) mat = MAT_LEAVES;
        if (c == VOXEL_POLISHED) { smooth_ = POLISHED_SMOOTHNESS; }
        if (c == VOXEL_METAL) { smooth_ = METAL_SMOOTHNESS; f0 = 1.0; }
        if (c >= 11 && c <= 19) { mat = MAT_EMISSIVE; emis = float(c - 10); c1.b = 1.0; }
        c2 = vec4(float(mat) / 255.0, emis / 255.0, smooth_, f0);
    }
    float dWat = dOp;
    vec4 c5 = vec4(0.0), wcol = vec4(0.0);
    float tS = (surfY - o.y) / dir.y;
    vec3 sp = o + dir * tS;
    if (tS > 0.0 && tS < tHit && sp.x >= pool.x && sp.x < pool.y && sp.z >= pool.z && sp.z < pool.w) {
        dWat = viewToScreen(playerToView(voxelToPlayer(sp))).z;
        vec3 wp = voxelToPlayer(sp) + cameraPosition;
        vec3 wn = (o.y < surfY) ? waterNormalBelow(wp.xz, tS * 2.0 / (gbufferProjection[1][1] * viewHeight)) : waterNormal(wp.xz);
        c5 = vec4(encodeNormal(wn), 1.0, 1.0);
        wcol = vec4(vec3(0.02, 0.05, 0.06), WATER_SURFACE_OPACITY);
    }
    imageStore(c0Out, px, c0); imageStore(c1Out, px, c1); imageStore(c2Out, px, c2);
    imageStore(dOpOut, px, vec4(dOp)); imageStore(dWatOut, px, vec4(dWat));
    imageStore(c5Out, px, c5); imageStore(wColOut, px, wcol);
}
"""
# gbuffers_water in miniature: the water color blended over the lit scene (after deferred6)
BLEND_SRC = """#version 430 core
layout(local_size_x = 8, local_size_y = 8) in;
layout(rgba16f) uniform image2D sceneImg;
uniform sampler2D wColSampler;
void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(px, imageSize(sceneImg)))) return;
    vec4 w = texelFetch(wColSampler, px, 0);
    if (w.a > 0.0) imageStore(sceneImg, px, vec4(mix(imageLoad(sceneImg, px).rgb, w.rgb, w.a), 1.0));
}
"""
wcolT = tex2(RGBA16F, RGBA, FLOAT, W, H)

def attach(outs, half=False):
    glBindFramebuffer(0x8D40, fbo.value)
    for i in range(4):
        glFramebufferTexture2D(0x8D40, 0x8CE0 + i, T2D, outs[i] if i < len(outs) else 0, 0)
    bufs = (c_uint * len(outs))(*[0x8CE0 + i for i in range(len(outs))]); glDrawBuffers(len(outs), bufs)
    assert glCheckFramebufferStatus(0x8D40) == 0x8CD5
    glViewport(0, 0, W // 2 if half else W, H // 2 if half else H)
HALFRES = {}
NEWGLASS = {"on": False}
SNAPRES = {}
def quad():
    glBegin(0x0007)
    for (x, y) in ((0, 0), (1, 0), (1, 1), (0, 1)):
        glMultiTexCoord2f(0x84C0, x, y); glVertex2f(x * 2 - 1, y * 2 - 1)
    glEnd()

PASSES = [("deferred_a", "cs", (16384, 1, 1)), ("deferred_b", "cs", (16, 16, 16)), ("deferred_c", "cs", (1024, 1, 1)),
          ("deferred", [3]), ("deferred1", [4, 7]), ("deferred2", [8]), ("deferred3", [9]), ("deferred4", [8]), ("deferred5", [9]),
          ("deferred6_a", "cs", None), ("deferred6_b", "cs", None), ("deferred6_c", "cs", None), ("deferred6", [0, 6]), ("waterblend", None), ("composite_a", "cs", None), ("composite", [0, 11]), ("composite1", [0, 10]), ("composite2", [0]), ("final", "screen")]

def run_pass(name, kind, progs, U, depth_mode):
    p = progs[name]; glUseProgram(p)
    extra = {"depthtex0": (T2D, depthOpT if depth_mode == "opaque" else depth0T), "depthtex1": (T2D, depth1T)}
    if kind == "cs" or isinstance(kind, tuple):
        pass
    for n in range(12): extra["colortex%d" % n] = (T2D, CT[n][CUR[n]])
    set_uniforms(p, U[name], extra)
    return p

def frame(progs, U, timing):
    # per frame: cleared buffers, the light grid as the shadow pass leaves it, the list counter
    for n in CLEARED - {0, 1, 2, 5}:
        for k in (0, 1):
            attach([CT[n][k]]); glClearColor(0, 0, 0, 0); glClear(0x4000)
    up2(gridT, R32UI, REDI, UINT, GRID_W, LG_ROWS, HOME)
    up2(countT, R32UI, REDI, UINT, 4, 1, np.zeros((1, 4), np.uint32))
    # G-buffer (colortex0-2, depth, colortex5) straight into the current copies
    p = progs["gbuf"]; glUseProgram(p); set_uniforms(p, U["gbuf"], {}, False)
    glUniform4f = g("glUniform4f", None, c_int, c_float, c_float, c_float, c_float)
    glUniform4f(glGetUniformLocation(p, b"pool"), float(POOL[0]), float(POOL[1]), float(POOL[2]), float(POOL[3]))
    glUniform1f(glGetUniformLocation(p, b"surfY"), float(SURF_Y))
    for i, (nm, t, f) in enumerate((("c0Out", CT[0][CUR[0]], RGBA16F), ("c1Out", CT[1][CUR[1]], RGBA16), ("c2Out", CT[2][CUR[2]], RGBA8),
                                    ("dOpOut", depthOpT, R32F), ("dWatOut", depth0T, R32F), ("c5Out", CT[5][CUR[5]], RGBA16), ("wColOut", wcolT, RGBA16F))):
        glBindImageTexture(i, t, 0, 0, 0, GL_WO, f); glUniform1i(glGetUniformLocation(p, nm.encode()), i)
    glDispatchCompute((W + 7) // 8, (H + 7) // 8, 1); glMemoryBarrier(ALLB); glFinish()
    # depthtex1 = opaque depth
    glBindTexture(T2D, depthOpT); a = np.zeros((H, W), np.float32); glGetTexImage(T2D, 0, RED, FLOAT, a.ctypes.data_as(c_void_p))
    up2(depth1T, R32F, RED, FLOAT, W, H, a)
    for entry in PASSES:
        name, kind = entry[0], entry[1]
        if name not in progs and name != "waterblend": continue
        reps = REPS if (name in REP_PASSES and kind not in ("cs",) and name not in ("waterblend", "final")) else 1
        best = 1e9
        for rep in range(reps):
            t0 = time.perf_counter()
            if isinstance(kind, list):
                depth_mode = "opaque" if name.startswith("deferred") else "water"
                p = run_pass(name, kind, progs, U, depth_mode)
                outs = [CT[n][1 - CUR[n]] for n in kind]
                attach(outs, name == "deferred" and HALFRES.get("on")); quad(); glFinish()
                best = min(best, (time.perf_counter() - t0) * 1000.0)
        if reps > 1:
            for n in kind: CUR[n] = 1 - CUR[n]
            timing.setdefault(name, []).append(best)
            continue
        t0 = time.perf_counter()
        if kind == "cs":
            p = run_pass(name, kind, progs, U, "opaque" if name.startswith("deferred") else "water")
            glDispatchCompute(*progs["wg_" + name]); glMemoryBarrier(ALLB)
        elif name == "waterblend":
            p = progs["blend"]; glUseProgram(p)
            glActiveTexture(0x84C0); glBindTexture(T2D, wcolT); glUniform1i(glGetUniformLocation(p, b"wColSampler"), 0)
            glBindImageTexture(0, CT[0][CUR[0]], 0, 0, 0, GL_RW, RGBA16F); glUniform1i(glGetUniformLocation(p, b"sceneImg"), 0)
            glDispatchCompute((W + 7) // 8, (H + 7) // 8, 1); glMemoryBarrier(ALLB)
        elif kind == "screen":
            glBindTexture(T2D, CT[0][CUR[0]]); glGenerateMipmap(T2D); glTexParameteri(T2D, 0x2801, 0x2703)
            p = run_pass(name, kind, progs, U, "water")
            attach([screenT]); quad()
        else:
            depth_mode = "opaque" if name.startswith("deferred") else "water"
            p = run_pass(name, kind, progs, U, depth_mode)
            outs = [CT[n][1 - CUR[n]] for n in kind]
            attach(outs, name == "deferred" and HALFRES.get("on")); quad()
            for n in kind: CUR[n] = 1 - CUR[n]
        glFinish()
        timing.setdefault(name, []).append((time.perf_counter() - t0) * 1000.0)
    glBindFramebuffer(0x8D40, 0)

def read_tex(t, fmt=RGBA, typ=FLOAT, ch=4):
    a = np.zeros((H, W, ch), np.float32 if typ == FLOAT else np.uint8); glBindTexture(T2D, t)
    glGetTexImage(T2D, 0, fmt, typ, a.ctypes.data_as(c_void_p)); return a

def draw_entities(work, cam, shift):
    """Villagers written into the entity grid by the real shadow_entities program."""
    z = np.zeros((EG, EG, EW), np.uint32); up3(entT, R32UI, REDI, UINT, (EW, EG, EG), z)
    pent = build_prog(work, "shadow_entities")
    smT = tex2(RGBA8, RGBA, UBYTE, 512, 512)
    glBindFramebuffer(0x8D40, fbo.value); glFramebufferTexture2D(0x8D40, 0x8CE0, T2D, smT, 0)
    for i in range(1, 4): glFramebufferTexture2D(0x8D40, 0x8CE0 + i, T2D, 0, 0)
    glViewport(0, 0, 512, 512); glClear(0x4000); glDisable(0x0B71); glDisable(0x0B44)
    def loadm(mode, m):
        glMatrixMode(mode); a = np.ascontiguousarray(np.array(m, np.float32).T); glLoadMatrixf(a.ctypes.data_as(ctypes.POINTER(c_float)))
    smv = shadow_mv(sun_dir(6000))
    loadm(0x1700, smv); loadm(0x1701, SPJ); loadm(0x1702, np.eye(4))
    glUseProgram(pent)
    for nm, v in (("cameraPosition", cam),):
        l = glGetUniformLocation(pent, nm.encode());  glUniform3f(l, *map(float, v)) if l >= 0 else None
    for nm, m in (("shadowModelViewInverse", np.linalg.inv(smv)), ("shadowModelView", smv), ("shadowProjection", SPJ)):
        l = glGetUniformLocation(pent, nm.encode())
        if l >= 0:
            a = np.ascontiguousarray(m.astype(np.float32)); glUniformMatrix4fv(l, 1, 1, a.ctypes.data_as(ctypes.POINTER(c_float)))
    etex = np.zeros((64, 64, 4), np.uint8); etex[..., 3] = 255
    for k, rgb in enumerate(((190, 140, 105), (120, 80, 50), (70, 50, 40), (60, 120, 60))): etex[:, k * 16:(k + 1) * 16, :3] = rgb
    et = tex2(RGBA8, RGBA, UBYTE, 64, 64, etex)
    glActiveTexture(0x84C0); glBindTexture(T2D, et); glUniform1i(glGetUniformLocation(pent, b"gtexture"), 0)
    glBindImageTexture(1, entT, 0, 1, 0, GL_RW, R32UI); glUniform1i(glGetUniformLocation(pent, b"entityImg"), 1)
    def cuboid(lo, hi, k):
        lo = np.array(lo) - cam; hi = np.array(hi) - cam
        c = [np.array([x, y, zz]) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for zz in (lo[2], hi[2])]
        faces = [(0, 1, 3, 2), (5, 4, 6, 7), (0, 4, 5, 1), (3, 7, 6, 2), (4, 0, 2, 6), (1, 5, 7, 3)]
        glColor4f(1, 1, 1, 1); glBegin(0x0004)
        u0 = k * 0.25
        uv = [(u0, 1.0), (u0 + 0.25, 1.0), (u0 + 0.25, 0.0), (u0, 0.0)]
        for f in faces:
            for tri in ((0, 1, 2), (0, 2, 3)):
                for q in tri: glMultiTexCoord2f(0x84C0, *uv[q]); glVertex3f(*map(float, c[f[q]]))
        glEnd()
    S = 1 / 16.0
    for (vx, vz) in ((62.0, 52.0), (66.5, 49.0), (74.0, 58.5), (54.0, 76.0)):
        # scene voxel s sits at grid cell s - shift, which is world (cell - (64, 48, 64)) + floor(cam)
        wx, wy, wz = (vx - shift[0] - 64 + math.floor(cam[0]), GROUND + 1 - shift[1] - 48 + math.floor(cam[1]), vz - shift[2] - 64 + math.floor(cam[2]))
        cuboid((wx, wy, wz + S), (wx + 8 * S, wy + 12 * S, wz + 5 * S), 2)
        cuboid((wx, wy + 12 * S, wz), (wx + 8 * S, wy + 24 * S, wz + 6 * S), 1)
        cuboid((wx - 1 * S, wy + 16 * S, wz - 3 * S), (wx + 9 * S, wy + 21 * S, wz + 1 * S), 0)
        cuboid((wx, wy + 24 * S, wz + 0.5 * S), (wx + 8 * S, wy + 34 * S, wz + 8.5 * S), 0)
    glFinish(); glMemoryBarrier(ALLB); glFinish()
    loadm(0x1700, np.eye(4)); loadm(0x1701, np.eye(4)); loadm(0x1702, np.eye(4)); glMatrixMode(0x1700)
    glBindFramebuffer(0x8D40, 0)

def reset_history():
    for n in range(12):
        for k in (0, 1):
            attach([CT[n][k]]); glClearColor(0, 0, 0, 0); glClear(0x4000)
    up3(cacheT, RGBA16F, RGBA, FLOAT, (12 * CS, CS, CS), np.zeros((CS, CS, 12 * CS, 4), np.float32))
    up3(metaT, R32UI, REDI, UINT, (6 * CS, CS, CS), np.zeros((CS, CS, 6 * CS), np.uint32))
    up2(stateT, R32UI, REDI, UINT, 8, 1, np.zeros((1, 8), np.uint32))
    glBindFramebuffer(0x8D40, 0)

def run_tree(label, work):
    wd = os.path.join(work, "shaders", "world0")
    names = [e[0] for e in PASSES if e[0] != "waterblend" and (os.path.exists(os.path.join(wd, e[0] + ".vsh")) or os.path.exists(os.path.join(wd, e[0] + ".csh")))]
    settings = open(os.path.join(work, "shaders", "lib", "settings.glsl")).read()
    NEWGLASS["on"] = "glassFilter" in open(os.path.join(work, "shaders", "lib", "common.glsl")).read()
    globals()["SKYONE"] = (1 << 20) if "w >> 20u" in open(os.path.join(work, "shaders", "lib", "gicache.glsl")).read() else 65536
    HALFRES["on"] = re.search(r"^#define GI_HALF_RES", settings, re.M) is not None
    cloud_half = re.search(r"^#define CLOUD_HALF_RES", settings, re.M) is not None
    cloud_alloc(cloud_half)
    progs = {n: build_prog(work, n) for n in names}
    for n in names:
        if not os.path.exists(os.path.join(wd, n + ".csh")): continue
        src = open(os.path.join(wd, n + ".csh")).read()
        if n == "deferred6_c":
            on = re.search(r"^#define SHADOW_HALF_RES", settings, re.M)
            progs["wg_" + n] = (((W + 1) // 2 + 7) // 8, ((H + 1) // 2 + 7) // 8, 1) if on else (1, 1, 1)
        elif n == "composite_a":
            on = re.search(r"^#define REFLECTION_HALF_RES", settings, re.M) and not re.search(r"^#define REFLECTION_MODE 0", settings, re.M)
            progs["wg_" + n] = (((W + 1) // 2 + 7) // 8, ((H + 1) // 2 + 7) // 8, 1) if on else (1, 1, 1)
        elif "workGroupsRender" in src:
            w, h = CLOUDRES["wh"] if n == "deferred6_a" else (W, H)
            progs["wg_" + n] = ((w + 7) // 8, (h + 7) // 8, 1)
        else:
            m = [tuple(int(v) for v in t) for t in re.findall(r"workGroups = ivec3\((\d+), (\d+), (\d+)\)", src)]
            m = [t for t in m if t != (1, 1, 1)] or [(1, 1, 1)]
            progs["wg_" + n] = m[-1]
    progs["gbuf"] = build_cs_text(work, GBUF_SRC.replace("SKYONE_U", "%du" % SKYONE).replace("#define NO_ENTITY_TRACE", "#define NO_ENTITY_TRACE\n#define BEVEL %s" % os.environ.get("BEVEL", "0.0")), "prof_gbuf")
    progs["blend"] = build_cs_text(work, BLEND_SRC, "prof_blend")
    progs["shadowmap"] = build_cs_text(work, SHADOW_SRC, "prof_shadow")
    U = {n: uniforms_of(progs[n]) for n in progs if not n.startswith("wg_")}
    results = {}
    for vname, eye, yaw, pitch, inwater, wt in VIEWS:
        if os.environ.get("YAW0"): yaw = float(os.environ["YAW0"])
        if os.environ.get("EYE0"): eye = tuple(float(v) for v in os.environ["EYE0"].split(","))
        vox[...] = VOX0; code[...] = CODE0; derive()
        eye0 = np.floor(np.array(eye))
        def upload(eye_f):
            # the voxel grid is centred on floor(cam); the scene is moved so that the eye's cell
            # is the grid's centre cell (64, 48, 64). cam moves with the eye (WALK) so that the
            # world cache, anchored to world cells, sees the same world from every frame.
            cam = np.array([0.0, 64.0, 0.0]) + (np.array(eye_f) - eye0)
            shift = np.floor(np.array(eye_f)).astype(int) - np.array([64, 48, 64])
            STATE["cam"] = cam
            R = lambda arr, sy=1, sx=1: np.roll(arr, (-shift[2], -sy * shift[1], -sx * shift[0]), axis=(0, 1, 2))
            vox_t = vox.copy(); gcol = np.zeros((VZ, VY, VX, 4), np.uint8)
            for (gx, gy, gz, srgb, ga) in GLASS_CELLS:
                vox_t[gz, gy, gx, :3] = np.round(glass_voxel(srgb, ga, NEWGLASS["on"]) * 255)
                gcol[gz, gy, gx, :3] = np.round(np.clip(glass_shadow(srgb, ga, NEWGLASS["on"]), 0, 1) * 255); gcol[gz, gy, gx, 3] = 255
            up3(voxT, RGBA8, RGBA, UBYTE, (VX, VY, VZ), R(vox_t))
            up3(glassColT, RGBA8, RGBA, UBYTE, (VX, VY, VZ), R(gcol))
            up3(shapeT, R32UI, REDI, UINT, (VX, VY, VZ), R(shape))
            up3(faceT, R32UI, REDI, UINT, (VX * 4, VY * 2, VZ), R(faceTex, 2, 4))
            surf = GROUND + 0.89 - shift[1]
            wm = np.roll(water, (-shift[2], -shift[0]), axis=(0, 1)).copy()
            wm[wm > 0] = int((surf - 48 + 256) * 64)
            up2(waterT, R32UI, REDI, UINT, VX, VZ, wm)
            lights = [(x - shift[0], y - shift[1], z - shift[2]) for (x, y, z) in LIGHTS]
            cr = R(code)
            occ = cr.reshape(VZ // 8, 8, VY // 8, 8, VX // 8, 8).max(axis=(1, 3, 5)) > 0
            globals()["HOME"] = build_home([l for l in lights if all(0 <= l[i] < (VX, VY, VZ)[i] for i in range(3))], occ)
            s15 = R(sky15)
            sk = (s15[64 - SKH:64 + SKH, 48 - SKH:48 + SKH, 64 - SKH:64 + SKH] * 255 + 0.5).astype(np.uint32) + SKYONE
            up3(skyT, R32UI, REDI, UINT, (SK, SK, SK), sk)
            up2(gridT, R32UI, REDI, UINT, GRID_W, LG_ROWS, HOME)     # the shadow map tracer reads the occupancy too
            # shadow map of this sun
            p = progs["shadowmap"]; glUseProgram(p); set_uniforms(p, U["shadowmap"], {}, False)
            glBindImageTexture(0, shadowT, 0, 0, 0, GL_WO, R32F); glUniform1i(glGetUniformLocation(p, b"outImg"), 0)
            glBindImageTexture(1, shadow0T, 0, 0, 0, GL_WO, R32F); glUniform1i(glGetUniformLocation(p, b"out0Img"), 1)
            glBindImageTexture(2, shcolT, 0, 0, 0, GL_WO, RGBA8); glUniform1i(glGetUniformLocation(p, b"colImg"), 2)
            glActiveTexture(0x84C0 + 15); glBindTexture(T3D, glassColT); glUniform1i(glGetUniformLocation(p, b"glassColSampler"), 15)
            glDispatchCompute(SHN // 8, SHN // 8, 1); glMemoryBarrier(ALLB); glFinish()
            globals()["SURF_Y"] = surf
            return cam, shift
        STATE.update(mv=view_matrix(yaw, pitch), sun=sun_dir(wt), smv=shadow_mv(sun_dir(wt)), eye=inwater, wt=wt,
                     eyesky=int(240 * sky15[int(eye[2]), int(eye[1]), int(eye[0])]), frame=0)
        cam, shift = upload(eye)
        STATE["pcam"] = cam
        draw_entities(work, cam, shift)
        pool_save = POOL
        globals()["POOL"] = (POOL[0] - shift[0], POOL[1] - shift[0], POOL[2] - shift[2], POOL[3] - shift[2])
        reset_history()
        timing = {}
        snaps = {}
        want = set(int(v) for v in os.environ.get("SNAPS", "").split(",") if v)
        yawspeed = float(os.environ.get("YAWSPEED", "0"))
        walk = np.array([float(v) for v in os.environ["WALK"].split(",")]) if os.environ.get("WALK") else None
        STATE["pmv"] = STATE["mv"]
        for f in range(FRAMES):
            STATE["frame"] = f
            if yawspeed:
                y0, y1 = int(os.environ.get("YAWSTART", "0")), int(os.environ.get("YAWSTOP", "100000"))
                STATE["pmv"] = STATE["mv"]
                STATE["mv"] = view_matrix(yaw + yawspeed * (min(max(f, y0), y1) - y0), pitch)
            STATE["pcam"] = STATE["cam"]
            if os.environ.get("CHANGE_AT") and f == int(os.environ["CHANGE_AT"]):
                apply_change(); derive(); upload(np.array(eye) + (walk * f if walk is not None else 0))
            if walk is not None and f > 0:
                eye_f = np.array(eye) + walk * f
                if np.any(np.floor(eye_f) != np.floor(np.array(eye) + walk * (f - 1))):
                    upload(eye_f)                                  # the grid follows the camera
                STATE["cam"] = np.array([0.0, 64.0, 0.0]) + (eye_f - eye0)
            frame(progs, U, timing)
            if (f + 1) in want:
                snaps[f + 1] = (read_tex(CT[0][CUR[0]])[..., :3].copy(), read_tex(screenT, RGBA, UBYTE)[..., :3].copy(),
                                read_tex(CT[9][CUR[9]])[..., :3].copy(), read_tex(CT[4][CUR[4]])[..., 3].copy())
            if os.environ.get("DUMPCACHE") and (f + 1) in want:
                cv = np.zeros((CS, CS, 12 * CS, 4), np.float32); glBindTexture(T3D, cacheT)
                glGetTexImage(T3D, 0, RGBA, FLOAT, cv.ctypes.data_as(c_void_p))
                mv_ = np.zeros((CS, CS, 6 * CS), np.uint32); glBindTexture(T3D, metaT)
                glGetTexImage(T3D, 0, REDI, UINT, mv_.ctypes.data_as(c_void_p))
                np.savez_compressed("%s_cache_%s_%s_%d.npz" % (os.environ.get("OUT", "x"), label, vname.replace(" ", "_"), f + 1), v=cv, m=mv_)
        SNAPRES.setdefault(label, {})[vname] = snaps
        globals()["POOL"] = pool_save; globals()["SURF_Y"] = GROUND + 0.89
        for k in timing: timing[k] = float(np.median(timing[k][3:])) if len(timing[k]) > 3 else float(np.median(timing[k]))
        hdr = read_tex(CT[0][CUR[0]])[..., :3].copy()
        if os.environ.get("DUMPGRID"):
            g_ = np.zeros((LG_ROWS, GRID_W), np.uint32); glBindTexture(T2D, gridT)
            glGetTexImage(T2D, 0, REDI, UINT, g_.ctypes.data_as(c_void_p))
            np.save("%s_grid_%s_%s.npy" % (os.environ.get("OUT", os.path.join(WORK, "prof")), label, vname.replace(" ", "_")), g_)
        ldr = read_tex(screenT, RGBA, UBYTE)[..., :3].copy()
        results[vname] = (timing, hdr, ldr)
    return results

if __name__ == "__main__":
    spec = os.environ.get("TREES", "pack=%s" % ROOT)
    trees = [s.split("=", 1) for s in spec.split()]
    glDisable(0x0B71); glDisable(0x0BE2)
    allres = {}
    for label, work in trees:
        allres[label] = run_tree(label, work)
    from PIL import Image
    pref = os.environ.get("OUT", os.path.join(WORK, "prof"))
    for vname, *_ in VIEWS:
        print("== %s" % vname)
        passes = [e[0] for e in PASSES if any(e[0] in allres[l][vname][0] for l, _ in trees)]
        print("%-12s" % "pass" + "".join("%12s" % l for l, _ in trees))
        tot = {l: 0.0 for l, _ in trees}
        for ps in passes:
            row = "%-12s" % ps
            for l, _ in trees:
                ms = allres[l][vname][0].get(ps, float("nan")); tot[l] += 0.0 if ms != ms else ms; row += "%12.1f" % ms
            print(row)
        print("%-12s" % "TOTAL" + "".join("%12.1f" % tot[l] for l, _ in trees))
        ref = allres[trees[0][0]][vname][1]
        for l, _ in trees[1:]:
            d = np.abs(allres[l][vname][1] - ref); m = ref.mean() + 1e-6
            print("  %s vs %s: mean abs diff %.4f (%.2f %% of mean %.4f), p99 %.4f" % (l, trees[0][0], d.mean(), 100 * d.mean() / m, m, np.percentile(d, 99)))
        imgs = [allres[l][vname][2][::-1] for l, _ in trees]
        Image.fromarray(np.concatenate(imgs, 1)).save("%s_%s.png" % (pref, vname.replace(" ", "_")))
        np.savez_compressed("%s_%s.npz" % (pref, vname.replace(" ", "_")), **{l: allres[l][vname][1] for l, _ in trees})
        if any(SNAPRES.get(l, {}).get(vname) for l, _ in trees):
            rows = []
            arrs = {}
            for l, _ in trees:
                sn = SNAPRES[l][vname]
                rows.append(np.concatenate([sn[k][1][::-1][::2, ::2] for k in sorted(sn)], 1))
                for k in sorted(sn):
                    arrs["%s_%d" % (l, k)] = sn[k][0]
                    arrs["gi_%s_%d" % (l, k)] = sn[k][2]; arrs["fr_%s_%d" % (l, k)] = sn[k][3]
            Image.fromarray(np.concatenate(rows, 0)).save("%s_%s_snaps.png" % (pref, vname.replace(" ", "_")))
            np.savez_compressed("%s_%s_snaps.npz" % (pref, vname.replace(" ", "_")), **arrs)
