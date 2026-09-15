"""
CORAL VXGI - tam proje denetimi
===============================
Oyunu açmadan yakalanabilecek her şeyi kontrol eder:

  1. Kullanılan uniform adları Iris'in sağladıklarıyla uyuşuyor mu
     (yanlış yazılmış bir uniform sessizce sıfır döner ve hata vermez)
  2. Kullanılan her sampler tanımlı mı, tanımlı her sampler kullanılıyor mu
  3. RENDERTARGETS sayısı ile fragment çıkış sayısı eşleşiyor mu
  4. image.* yönergelerinin parametre sayısı ve boyutları geçerli mi
  5. Geçiş sırası: bir geçiş kendinden SONRAKİ bir geçişin yazdığı
     dokuyu okuyorsa veri bir kare geriden gelir (sessiz hata)

KULLANIM:  python tools/audit.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "shaders"))

# Iris'in sağladığı uniformlar (shaders.properties dokümantasyonundan)
IRIS_UNIFORMS = set("""
frameCounter frameTime frameTimeCounter worldTime worldDay moonPhase
viewWidth viewHeight aspectRatio near far
rainStrength wetness thunderStrength nightVision blindness darknessFactor darknessLightFactor
screenBrightness isEyeInWater eyeAltitude eyeBrightness eyeBrightnessSmooth
heldItemId heldBlockLightValue heldItemId2 heldBlockLightValue2 heldItemLight
centerDepthSmooth atlasSize entityColor entityId blockEntityId currentRenderedItemId
cameraPosition previousCameraPosition cameraPositionFract cameraPositionInt
sunPosition moonPosition shadowLightPosition upPosition
sunAngle shadowAngle skyColor fogColor fogDensity fogStart fogEnd fogMode fogShape
gbufferModelView gbufferModelViewInverse gbufferProjection gbufferProjectionInverse
gbufferPreviousModelView gbufferPreviousProjection
shadowModelView shadowModelViewInverse shadowProjection shadowProjectionInverse
renderStage alphaTestRef playerMood
gtexture texture lightmap normals specular shadow shadowtex0 shadowtex1
shadowcolor shadowcolor0 shadowcolor1 noisetex depthtex0 depthtex1 depthtex2
colortex0 colortex1 colortex2 colortex3 colortex4 colortex5 colortex6 colortex7
colortex8 colortex9 colortex10 colortex11 colortex12 colortex13 colortex14 colortex15
gaux1 gaux2 gaux3 gaux4 tempOffsets
""".split())

# geçiş sırası (Iris bunları bu sırayla çalıştırır)
PASS_ORDER = ["shadow", "gbuffers_solid", "gbuffers_sky", "gbuffers_forward",
              "deferred", "deferred1", "denoise_seed", "denoise1", "denoise2", "denoise3",
              "lighting", "gbuffers_water", "composite", "final"]


def expand(path, seen=None):
    out = []
    for line in open(path, encoding="utf-8").read().split("\n"):
        m = re.match(r'\s*#include\s+"(.+)"', line)
        out.append(expand(ROOT + m.group(1)) if m else line)
    return "\n".join(out)


def main():
    errors, warnings = [], []
    props = open(os.path.join(ROOT, "shaders.properties"), encoding="utf-8").read()

    # ---------------------------------------------------- 4) image yönergeleri
    declared_image_samplers = set()
    for line in props.split("\n"):
        m = re.match(r"\s*image\.(\w+)\s*=\s*(.+)", line)
        if not m:
            continue
        name, rest = m.group(1), m.group(2).split()
        declared_image_samplers.add(rest[0])
        # sampler format internalFormat type clear relative + (W H) veya (W H D)
        if len(rest) not in (8, 9):
            errors.append(f"image.{name}: {len(rest)} parametre, 8 (2B) veya 9 (3B) olmalı")
            continue
        dims = [int(x) for x in rest[6:]]
        if any(d <= 0 for d in dims):
            errors.append(f"image.{name}: geçersiz boyut {dims}")
        if len(dims) == 3 and max(dims) > 2048:
            warnings.append(f"image.{name}: {dims} - 3B doku sınırını (yaygın 2048) zorluyor")
        if rest[4] not in ("true", "false") or rest[5] not in ("true", "false"):
            errors.append(f"image.{name}: clear/relative 'true' veya 'false' olmalı")

    # ---------------------------------------------- 1-3) program başına denetim
    program_dir = os.path.join(ROOT, "program")
    writes = {}   # colortex indeksi -> yazan program
    reads = {}    # program -> okunan colortex indeksleri
    for fname in sorted(os.listdir(program_dir)):
        if not fname.endswith(".glsl"):
            continue
        prog = fname[:-5]
        src = expand(os.path.join(program_dir, fname))
        code = re.sub(r"//.*", "", src)
        code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)

        # layout(...) ile tanımlanan görüntüler shaders.properties'ten gelir
        image_uniforms = set(re.findall(r"layout\([^)]*\)[^;]*uniform\s+u?image\w+\s+(\w+)\s*;", code))

        # 1) uniform adları
        for m in re.finditer(r"^\s*uniform\s+\w+\s+(\w+)\s*;", code, flags=re.M):
            u = m.group(1)
            if u not in IRIS_UNIFORMS and u not in declared_image_samplers and u not in image_uniforms:
                errors.append(f"{prog}: '{u}' uniform'unu Iris sağlamıyor (sessizce sıfır döner)")

        # 2) kullanılan ama tanımsız sampler
        used = set(re.findall(r"\b(?:texture|texelFetch|textureLod)\s*\(\s*(\w+)", code))
        declared = set(re.findall(r"uniform\s+u?sampler\w*\s+(\w+)\s*;", code))
        # fonksiyon parametresi olarak geçen örnekleyiciler tanımlı sayılır
        params = set(re.findall(r"u?sampler\w+\s+(\w+)\s*[,)]", code))
        for s in used - declared - params:
            if s not in ("gtexture",):
                errors.append(f"{prog}: '{s}' örnekleyicisi kullanılıyor ama tanımlı değil")
        for s in declared - used - params:
            # ortak kütüphaneye parametre olarak geçiriliyor olabilir
            if not re.search(rf"\b{s}\b\s*[,)]", code):
                warnings.append(f"{prog}: '{s}' tanımlı ama kullanılmıyor")

        # 3) RENDERTARGETS <-> çıkış sayısı
        all_rt = re.findall(r"RENDERTARGETS:\s*([\d,\s]+)", src)
        if all_rt:
            # #ifdef dalları yüzünden birden fazla blok olabilir; hepsi yazar sayılır
            counts = []
            for block in all_rt:
                idx = [int(x) for x in block.replace(" ", "").rstrip(",").split(",") if x != ""]
                counts.append(len(idx))
                for t in idx:
                    writes.setdefault(t, []).append(prog)
            outs = len(re.findall(r"layout\(location\s*=\s*\d+\)\s*out\s+", code))
            if outs and outs not in counts and outs != sum(counts):
                errors.append(f"{prog}: RENDERTARGETS {counts} hedef, {outs} çıkış tanımlı")
        reads[prog] = {int(m) for m in re.findall(r"uniform\s+sampler2D\s+colortex(\d+)", code)}

    # ---------------------------------------------- 5) geçiş sırası tutarlılığı
    order = {p: i for i, p in enumerate(PASS_ORDER)}
    for prog, rd in reads.items():
        if prog not in order:
            continue
        for tex in rd:
            for writer in writes.get(tex, []):
                if writer in order and order[writer] > order[prog] and writer != prog:
                    warnings.append(
                        f"{prog}, colortex{tex}'i okuyor ama onu {writer} yazıyor "
                        f"(sonraki geçiş) - veri bir kare geriden gelir")

    print(f"{len(writes)} doku yazılıyor, {len(declared_image_samplers)} özel görüntü")
    if warnings:
        print(f"\nUYARILAR ({len(warnings)}):")
        for w in warnings:
            print("  -", w)
    if errors:
        print(f"\nHATALAR ({len(errors)}):")
        for e in errors:
            print("  -", e)
        sys.exit(1)
    print("\nDenetim temiz")


if __name__ == "__main__":
    main()
