"""
CORAL VXGI - GLSL derleme testi
================================
Tüm programları glslangValidator ile derleyerek sözdizimi hatalarını
oyunu açmadan bulur. Iris'in eklediği makroları (MC_RENDER_STAGE_*) ve
Sodium'un arazi shader'larına enjekte ettiği fonksiyonları da ekler,
böylece isim çakışmaları da yakalanır.

KURULUM
  Windows : Vulkan SDK'yı kurun (glslangValidator içinde gelir)
  Linux   : sudo apt install glslang-tools
KULLANIM
  python tools/validate_glsl.py

NOT: Bu test yalnızca derlemeyi kontrol eder. Iris'e özgü bazı hatalar
(ör. yanlış uniform adı) ancak oyunda görülür.
"""
import os, re, subprocess, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "shaders"))

STAGES = ["NONE", "SKY", "SUNSET", "CUSTOM_SKY", "SUN", "MOON", "STARS", "VOID", "TERRAIN_SOLID",
          "TERRAIN_CUTOUT_MIPPED", "TERRAIN_CUTOUT", "ENTITIES", "BLOCK_ENTITIES", "DESTROY", "OUTLINE",
          "DEBUG", "HAND_SOLID", "TERRAIN_TRANSLUCENT", "TRIPWIRE", "PARTICLES", "CLOUDS", "RAIN_SNOW",
          "WORLD_BORDER", "HAND_TRANSLUCENT"]
IRIS_MACROS = "\n".join(f"#define MC_RENDER_STAGE_{s} {i}" for i, s in enumerate(STAGES))

# Iris'in Sodium arazi shader'larına eklediği fonksiyonların imzaları (çakışma testi için)
SODIUM_INJECT = """
vec2 signNotZero(vec2 v) { return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0); }
vec3 decodeOct24(uint packe) { return vec3(0.0); }
void onb_from_normal(in vec3 n, out vec3 t1, out vec3 t2) { t1 = n; t2 = n; }
vec2 decode_diamond(float p) { return vec2(p); }
vec4 decode_diamond_tangent_with_sign(vec3 normal, int qByte, bool signPositive) { return vec4(normal, 1.0); }
"""
SODIUM_PROGRAMS = ("gbuffers_terrain", "gbuffers_water", "shadow")

def expand(path):
    out = []
    for line in open(path, encoding="utf-8").read().split("\n"):
        m = re.match(r'\s*#include\s+"(.+)"', line)
        out.append(expand(ROOT + m.group(1)) if m else line)
    return "\n".join(out)

def build(wrapper):
    lines = expand(wrapper).split("\n")
    head, rest = [lines[0]], lines[1:]
    if rest and rest[0].startswith("#extension"):
        head.append(rest[0]); rest = rest[1:]
    extra = [IRIS_MACROS, "#define IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE"]
    if os.path.basename(wrapper).split(".")[0] in SODIUM_PROGRAMS:
        extra.append(SODIUM_INJECT)
    return "\n".join(head + extra + rest)

def main():
    exe = shutil.which("glslangValidator")
    if not exe:
        print("glslangValidator bulunamadı. Kurulum için dosyanın başındaki açıklamaya bakın.")
        sys.exit(2)
    tmp = tempfile.mkdtemp()
    total = failed = 0
    for folder in ("world0", "world-1", "world1"):
        for f in sorted(os.listdir(os.path.join(ROOT, folder))):
            stage = {"vsh": "vert", "fsh": "frag"}.get(f.rsplit(".", 1)[-1])
            if not stage:
                continue
            total += 1
            src = os.path.join(tmp, f"{folder}_{f}.{stage}")
            open(src, "w", encoding="utf-8").write(build(os.path.join(ROOT, folder, f)))
            r = subprocess.run([exe, "-S", stage, src], capture_output=True, text=True)
            if r.returncode != 0:
                failed += 1
                print(f"HATA  {folder}/{f}\n{(r.stdout + r.stderr).strip()[:1500]}\n")
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"{total - failed}/{total} program derlendi")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
