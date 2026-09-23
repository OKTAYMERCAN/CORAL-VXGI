"""Compiles AND links every program with a REAL driver compiler.

glslangValidator (tools/validate_glsl.py) checks the language rules but is not
a driver; some errors (driver-specific limits, link errors between stages,
the number of image units) are only caught by a real OpenGL driver. This tool
opens Mesa's software driver (llvmpipe) headless. Mesa is the open-source
driver that AMD and Intel cards use on Linux.

REQUIREMENTS: Linux, Mesa (libEGL.so.1, libGL.so.1), Python 3.8+.
    Debian/Ubuntu: sudo apt install libegl1 libgl1-mesa-dri
Does not run on Windows; tools/validate_glsl.py is enough there.

USAGE
    python3 tools/mesa_check.py                     all programs
    python3 tools/mesa_check.py deferred shadow     only these programs (+ image counts)

Like Iris: compute shaders (if a pack has any; 4.19 has none) are switched to
the core profile, and the MC_RENDER_STAGE_* defines that Iris injects are added.
The number of images each program uses is checked against NVIDIA's limit (8).
"""
import ctypes, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders"))
MAX_IMAGE_UNITS_NVIDIA = 8
IRIS_INJECT = """#define MC_RENDER_STAGE_TERRAIN_SOLID 4
#define MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED 5
#define MC_RENDER_STAGE_TERRAIN_CUTOUT 6
#define MC_RENDER_STAGE_TERRAIN_TRANSLUCENT 8
#define MC_RENDER_STAGE_ENTITIES 10
#define MC_RENDER_STAGE_SUN 13
#define MC_RENDER_STAGE_MOON 14
#define MC_RENDER_STAGE_STARS 15
#define IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE"""

# ------------------------------------------------------------------ EGL / GL
os.environ.setdefault("EGL_PLATFORM", "surfaceless")
os.environ.setdefault("LIBGL_ALWAYS_SOFTWARE", "1")
os.environ.setdefault("GALLIUM_DRIVER", "llvmpipe")
try:
    egl = ctypes.CDLL("libEGL.so.1")
    ctypes.CDLL("libGL.so.1")
except OSError as e:
    print("Mesa not found (libEGL.so.1 / libGL.so.1):", e)
    sys.exit(2)
EGL_NONE = 0x3038; EGL_OPENGL_API = 0x30A2; EGL_RENDERABLE_TYPE = 0x3040; EGL_OPENGL_BIT = 0x0008
EGL_SURFACE_TYPE = 0x3033; EGL_PBUFFER_BIT = 0x0001
EGL_CONTEXT_MAJOR_VERSION = 0x3098; EGL_CONTEXT_MINOR_VERSION = 0x30FB
EGL_CONTEXT_OPENGL_PROFILE_MASK = 0x30FD; EGL_COMPAT_BIT = 0x2
EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
egl.eglGetProcAddress.restype = ctypes.c_void_p
egl.eglGetProcAddress.argtypes = [ctypes.c_char_p]
def fn(name, restype, *args):
    return ctypes.CFUNCTYPE(restype, *args)(egl.eglGetProcAddress(name.encode()))
getPlatformDisplay = fn("eglGetPlatformDisplayEXT", ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p)
dpy = getPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, None, None)
egl.eglInitialize.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
if not egl.eglInitialize(ctypes.c_void_p(dpy), None, None):
    print("EGL could not be initialized"); sys.exit(2)
egl.eglBindAPI(EGL_OPENGL_API)
attrs = (ctypes.c_int * 5)(EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_NONE)
cfg = ctypes.c_void_p(); n = ctypes.c_int()
egl.eglChooseConfig.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
egl.eglChooseConfig(ctypes.c_void_p(dpy), attrs, ctypes.byref(cfg), 1, ctypes.byref(n))
egl.eglCreateContext.restype = ctypes.c_void_p
egl.eglCreateContext.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
cattrs = (ctypes.c_int * 7)(EGL_CONTEXT_MAJOR_VERSION, 4, EGL_CONTEXT_MINOR_VERSION, 5,
                            EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_COMPAT_BIT, EGL_NONE)
ctx = egl.eglCreateContext(ctypes.c_void_p(dpy), cfg, None, cattrs)
if not ctx:
    print("Could not create an OpenGL 4.5 context"); sys.exit(2)
egl.eglMakeCurrent.argtypes = [ctypes.c_void_p] * 4
egl.eglMakeCurrent(ctypes.c_void_p(dpy), None, None, ctypes.c_void_p(ctx))

glGetString = fn("glGetString", ctypes.c_char_p, ctypes.c_uint)
glCreateShader = fn("glCreateShader", ctypes.c_uint, ctypes.c_uint)
glShaderSource = fn("glShaderSource", None, ctypes.c_uint, ctypes.c_int, ctypes.POINTER(ctypes.c_char_p), ctypes.c_void_p)
glCompileShader = fn("glCompileShader", None, ctypes.c_uint)
glGetShaderiv = fn("glGetShaderiv", None, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(ctypes.c_int))
glGetShaderInfoLog = fn("glGetShaderInfoLog", None, ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_char_p)
glCreateProgram = fn("glCreateProgram", ctypes.c_uint)
glAttachShader = fn("glAttachShader", None, ctypes.c_uint, ctypes.c_uint)
glLinkProgram = fn("glLinkProgram", None, ctypes.c_uint)
glGetProgramiv = fn("glGetProgramiv", None, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(ctypes.c_int))
glGetProgramInfoLog = fn("glGetProgramInfoLog", None, ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_char_p)
glGetActiveUniform = fn("glGetActiveUniform", None, ctypes.c_uint, ctypes.c_uint, ctypes.c_int,
                        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_uint), ctypes.c_char_p)
GL_VERTEX_SHADER = 0x8B31; GL_FRAGMENT_SHADER = 0x8B30; GL_COMPUTE_SHADER = 0x91B9
GL_COMPILE_STATUS = 0x8B81; GL_LINK_STATUS = 0x8B82; GL_ACTIVE_UNIFORMS = 0x8B86
IMAGE_TYPES = {0x904D, 0x904E, 0x9063, 0x9064, 0x9051, 0x9058}   # image2D/3D, uimage2D/3D, iimage2D/3D

def compile_shader(kind, src):
    s = glCreateShader(kind)
    b = ctypes.c_char_p(src.encode())
    glShaderSource(s, 1, ctypes.byref(b), None)
    glCompileShader(s)
    ok = ctypes.c_int(); glGetShaderiv(s, GL_COMPILE_STATUS, ctypes.byref(ok))
    buf = ctypes.create_string_buffer(65536); glGetShaderInfoLog(s, 65536, None, buf)
    return s, bool(ok.value), buf.value.decode(errors="replace")

def link(shaders):
    p = glCreateProgram()
    for s in shaders: glAttachShader(p, s)
    glLinkProgram(p)
    ok = ctypes.c_int(); glGetProgramiv(p, GL_LINK_STATUS, ctypes.byref(ok))
    buf = ctypes.create_string_buffer(65536); glGetProgramInfoLog(p, 65536, None, buf)
    return p, bool(ok.value), buf.value.decode(errors="replace")

def image_uniforms(p):
    cnt = ctypes.c_int(); glGetProgramiv(p, GL_ACTIVE_UNIFORMS, ctypes.byref(cnt))
    out = []
    for i in range(cnt.value):
        ln = ctypes.c_int(); sz = ctypes.c_int(); ty = ctypes.c_uint(); nm = ctypes.create_string_buffer(256)
        glGetActiveUniform(p, i, 256, ctypes.byref(ln), ctypes.byref(sz), ctypes.byref(ty), nm)
        if ty.value in IMAGE_TYPES: out.append(nm.value.decode())
    return out

# ------------------------------------------------------------------ source
def expand(path):
    out = []
    for line in open(path, encoding="utf-8").read().split("\n"):
        m = re.match(r'\s*#include\s+"(.+)"', line)
        out.append(expand(os.path.join(ROOT, m.group(1).lstrip("/"))) if m else line)
    return "\n".join(out)

def prepare(path, compute):
    lines = expand(path).split("\n")
    for i, l in enumerate(lines):
        if l.strip().startswith("#version"):
            if compute: lines[i] = l.replace("compatibility", "core")   # Iris compiles compute as core
            ins = i + 1
            while ins < len(lines) and lines[ins].strip().startswith("#extension"): ins += 1
            lines[ins:ins] = IRIS_INJECT.split("\n")
            break
    return "\n".join(lines)

def main():
    only = set(sys.argv[1:])
    print("Driver:", glGetString(0x1F01).decode(), "|", glGetString(0x1F02).decode())
    total = fails = 0
    for w in sorted(d for d in os.listdir(ROOT) if d.startswith("world")):
        wd = os.path.join(ROOT, w)
        files = set(os.listdir(wd))
        for base in sorted({os.path.splitext(f)[0] for f in files if f.endswith((".vsh", ".fsh", ".csh"))}):
            if only and base not in only: continue
            if base + ".csh" in files:
                stages = [(GL_COMPUTE_SHADER, base + ".csh", True)]
            else:
                stages = [(k, base + e, False) for k, e in ((GL_VERTEX_SHADER, ".vsh"), (GL_FRAGMENT_SHADER, ".fsh"))
                          if base + e in files]
            total += 1
            shaders, logs = [], []
            for kind, f, compute in stages:
                s, ok, log = compile_shader(kind, prepare(os.path.join(wd, f), compute))
                shaders.append(s)
                if not ok: logs.append(f"{f}: {log.strip()[:1500]}")
            if not logs:
                p, ok, log = link(shaders)
                if not ok:
                    logs.append("LINK: " + log.strip()[:1500])
                else:
                    imgs = image_uniforms(p)
                    if len(imgs) > MAX_IMAGE_UNITS_NVIDIA:
                        logs.append(f"uses {len(imgs)} images, NVIDIA allows at most {MAX_IMAGE_UNITS_NVIDIA}: {imgs}")
                    elif only:
                        print(f"  {w}/{base}: {len(imgs)} image {imgs}")
            if logs:
                fails += 1
                print(f"ERROR {w}/{base}\n  " + "\n  ".join(logs))
    print(f"{total - fails}/{total} programs compiled and linked in Mesa")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
