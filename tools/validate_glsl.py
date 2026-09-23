"""Compiles every world*/ program with glslangValidator.
The defines that Iris injects into Sodium terrain shaders are emulated."""
import os, re, subprocess, tempfile, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders"))

IRIS_INJECT = """
#define MC_RENDER_STAGE_TERRAIN_SOLID 4
#define MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED 5
#define MC_RENDER_STAGE_TERRAIN_CUTOUT 6
#define MC_RENDER_STAGE_TERRAIN_TRANSLUCENT 8
#define MC_RENDER_STAGE_ENTITIES 10
#define MC_RENDER_STAGE_SUN 13
#define MC_RENDER_STAGE_MOON 14
#define MC_RENDER_STAGE_STARS 15
#define IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
"""

def expand(path, seen=None):
    out = []
    for line in open(path, encoding="utf-8").read().split("\n"):
        m = re.match(r'\s*#include\s+"(.+)"', line)
        if m:
            out.append(expand(os.path.join(ROOT, m.group(1).lstrip("/"))))
        else:
            out.append(line)
    return "\n".join(out)

# ---------------------------------------------------------------------
#  RESERVED WORD CHECK
#  glslang accepts some reserved words (e.g. 'packed') as variable names,
#  while the NVIDIA driver refuses to load the pack at all. So the
#  preprocessed source is scanned separately.
# ---------------------------------------------------------------------
NEVER_LEGAL = set("""common partition active asm class union enum typedef template this resource
goto inline noinline public static extern external interface long short half fixed unsigned superp
input output hvec2 hvec3 hvec4 fvec2 fvec3 fvec4 sampler3DRect filter sizeof cast namespace using
packed""".split())
KEYWORD_4X = set("sample patch subroutine buffer shared coherent volatile restrict readonly writeonly precise atomic_uint".split())
DECL = re.compile(r'\b(?:float|double|int|uint|bool|[iud]?vec[234]|d?mat[234](?:x[234])?|[iu]?sampler\w+|[iu]?image\w+)\s+([A-Za-z_]\w*)\s*[=;,)\[(]')

def reserved_issues(pre, version):
    issues = []
    tokens = set(re.findall(r'[A-Za-z_]\w*', pre))
    for w in sorted(NEVER_LEGAL & tokens):
        issues.append(f"'{w}' is a reserved word in GLSL and cannot be used as an identifier")
    for m in DECL.finditer(pre):
        name = m.group(1)
        if version >= 400 and name in KEYWORD_4X:
            issues.append(f"'{name}' is a #version {version} keyword, cannot be a variable name")
    return sorted(set(issues))

def main():
    ok, fail = 0, 0
    msgs = []
    with tempfile.TemporaryDirectory() as tmp:
        for world in sorted(d for d in os.listdir(ROOT) if d.startswith("world")):
            wdir = os.path.join(ROOT, world)
            for f in sorted(os.listdir(wdir)):
                if not f.endswith((".vsh", ".fsh", ".csh")):
                    continue
                src = expand(os.path.join(wdir, f))
                # insert the Iris defines right after the version line
                lines = src.split("\n")
                for i, l in enumerate(lines):
                    if l.strip().startswith("#version"):
                        ins = i + 1
                        while ins < len(lines) and lines[ins].strip().startswith("#extension"):
                            ins += 1
                        lines[ins:ins] = IRIS_INJECT.strip().split("\n")
                        break
                src = "\n".join(lines)
                stage = {".vsh": "vert", ".fsh": "frag", ".csh": "comp"}[os.path.splitext(f)[1]]
                p = os.path.join(tmp, f"{world}_{f}.{stage}")
                open(p, "w", encoding="utf-8").write(src)
                r = subprocess.run(["glslangValidator", "-S", stage, p],
                                   capture_output=True, text=True)
                pre = subprocess.run(["glslangValidator", "-E", "-S", stage, p],
                                     capture_output=True, text=True).stdout
                vm = re.search(r"#version\s+(\d+)", src)
                issues = reserved_issues(pre, int(vm.group(1)) if vm else 330)
                if r.returncode == 0 and not issues:
                    ok += 1
                else:
                    fail += 1
                    detail = r.stdout.strip()[:600] if r.returncode != 0 else "\n".join(issues)
                    msgs.append(f"ERROR  {world}/{f}\n{detail}")
    for m in msgs[:6]:
        print(m + "\n")
    print(f"{ok}/{ok+fail} programs compiled")
    sys.exit(1 if fail else 0)

main()
