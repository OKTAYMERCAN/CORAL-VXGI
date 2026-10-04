#!/usr/bin/env python3
"""Runs the REAL RCAS block from shaders/program/sharpen.glsl on Mesa (llvmpipe).

The code between the SHARPEN ifdef is lifted verbatim out of the file and only
the four texelFetch() calls are redirected at a small array, so the arithmetic
is byte-for-byte the shipped one.  Each case feeds a 5-tap cross (centre + 4
neighbours) and prints what comes out, so a flat patch must come back unchanged.
"""
import ctypes, os, re
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get("PACK_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
exec(open(os.path.join(WORK, "tools", "mesa_check.py")).read().split("def main():")[0])
ROOT = os.path.join(WORK, "shaders")

c_uint, c_int, c_void_p = ctypes.c_uint, ctypes.c_int, ctypes.c_void_p
glUseProgram = fn("glUseProgram", None, c_uint)
glDispatchCompute = fn("glDispatchCompute", None, c_uint, c_uint, c_uint)
glMemoryBarrier = fn("glMemoryBarrier", None, c_uint)
glGenBuffers = fn("glGenBuffers", None, c_int, ctypes.POINTER(c_uint))
glBindBuffer = fn("glBindBuffer", None, c_uint, c_uint)
glBufferData = fn("glBufferData", None, c_uint, ctypes.c_ssize_t, c_void_p, c_uint)
glBindBufferBase = fn("glBindBufferBase", None, c_uint, c_uint, c_uint)
glGetBufferSubData = fn("glGetBufferSubData", None, c_uint, ctypes.c_ssize_t, ctypes.c_ssize_t, c_void_p)
glFinish = fn("glFinish", None)
SSBO, DYN, ALLB = 0x90D2, 0x88E8, 0xFFFFFFFF

# ---- lift the RCAS block verbatim out of the shipped file -------------------
srcfile = open(os.path.join(ROOT, "program", "sharpen.glsl")).read()
block = srcfile.split("#ifdef SHARPEN")[1].split("#endif")[0]
block = block.split("{", 1)[1].rsplit("}", 1)[0]          # inside the if
block = block.replace("texelFetch(colortex0, clamp(px + ivec2( 0,-1), ivec2(0), res-1), 0).rgb", "TAP(1)")
block = block.replace("texelFetch(colortex0, clamp(px + ivec2( 0, 1), ivec2(0), res-1), 0).rgb", "TAP(2)")
block = block.replace("texelFetch(colortex0, clamp(px + ivec2(-1, 0), ivec2(0), res-1), 0).rgb", "TAP(3)")
block = block.replace("texelFetch(colortex0, clamp(px + ivec2( 1, 0), ivec2(0), res-1), 0).rgb", "TAP(4)")
assert "TAP(1)" in block and "TAP(4)" in block and "texelFetch" not in block, "extraction failed"

STRENGTH = os.environ.get("STRENGTH", "0.5")

CS = """#version 430
layout(local_size_x = 1) in;
layout(std430, binding = 0) buffer In  { vec4 taps[]; };   // 5 per case: centre,up,down,left,right
layout(std430, binding = 1) buffer Out { vec4 res[]; };
#define SHARPEN_STRENGTH %s
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, 0.0, 1.0); }
void main() {
    uint i = gl_GlobalInvocationID.x;
    vec3 color = taps[i*5u + 0u].rgb;
    #define TAP(k) (taps[i*5u + uint(k)].rgb)
%s
    res[i] = vec4(color, 1.0);
}
""" % (STRENGTH, block)

cs, ok, log = compile_shader(GL_COMPUTE_SHADER, CS)
assert ok, log
prog, ok, log = link([cs])
assert ok, log

# ---- cases ------------------------------------------------------------------
# name, centre, the four neighbours
cases = [
    ("flat 0.10 (dark interior)",        0.10, [0.10]*4),
    ("flat 0.30 (shaded wall)",          0.30, [0.30]*4),
    ("flat 0.80 (bright wall)",          0.80, [0.80]*4),
    ("flat 0.98 (near white)",           0.98, [0.98]*4),
    ("flat 2.60 (sunlit HDR)",           2.60, [2.60]*4),
    ("flat 8.00 (sun disc HDR)",         8.00, [8.00]*4),
    ("edge 0.30 vs 0.60",                0.30, [0.60, 0.60, 0.30, 0.30]),
    ("thin bright line 0.6 on 0.2",      0.60, [0.20]*4),
    ("thin dark line 0.2 on 0.6",        0.20, [0.60]*4),
]
n = len(cases)
inp = np.zeros((n*5, 4), dtype=np.float32)
for i, (_, c, nb) in enumerate(cases):
    inp[i*5 + 0] = (c, c, c, 1.0)
    for k, v in enumerate(nb):
        inp[i*5 + 1 + k] = (v, v, v, 1.0)
out = np.zeros((n, 4), dtype=np.float32)

for binding, arr in ((0, inp), (1, out)):
    b = c_uint(); glGenBuffers(1, ctypes.byref(b)); glBindBuffer(SSBO, b.value)
    glBufferData(SSBO, arr.nbytes, arr.ctypes.data_as(c_void_p), DYN)
    glBindBufferBase(SSBO, binding, b.value)
    if binding == 1: outbuf = b

glUseProgram(prog)
glDispatchCompute(n, 1, 1)
glMemoryBarrier(ALLB); glFinish()
glBindBuffer(SSBO, outbuf.value)
glGetBufferSubData(SSBO, 0, out.nbytes, out.ctypes.data_as(c_void_p))

print("SHARPEN_STRENGTH = %s   (shipped default 0.5, SHARPEN on by default)" % STRENGTH)
print("%-32s %8s %8s %8s" % ("case", "in", "out", "out/in"))
failed = False
for i, (name, c, nb) in enumerate(cases):
    o = out[i][0]
    ratio = o / c if c else float("nan")
    flag = ""
    if all(v == c for v in nb):          # flat patch: must be unchanged
        if abs(ratio - 1.0) > 0.01:
            flag = "  <-- FLAT PATCH CHANGED"
    print("%-32s %8.4f %8.4f %8.4f%s" % (name, c, o, ratio, flag))

    if all(v == c for v in nb) and abs(ratio - 1.0) > 0.01:
        failed = True
if failed:
    raise SystemExit("FAIL: the filter does not preserve a flat patch")
print("\nflat patches preserved at every level")
