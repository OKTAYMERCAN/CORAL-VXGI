"""
CORAL VXGI - sarmalayıcı (wrapper) dosya üreteci
=================================================
Iris her program için shaders/world0, world-1, world1 klasörlerinde
.vsh ve .fsh dosyası arar. Bu dosyalar sadece birkaç #define yapıp
asıl kodu shaders/program/ klasöründen #include eder.

YENİ PROGRAM EKLEMEK İÇİN aşağıdaki PROGRAMS sözlüğüne bir satır ekleyip
bu betiği çalıştırın:   python tools/generate_wrappers.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SHADERS = os.path.join(HERE, "..", "shaders")

# klasör -> boyut tanımı
DIMENSIONS = {"world0": "OVERWORLD", "world-1": "NETHER", "world1": "END"}

# program adı -> (program/ içindeki kaynak, ek tanımlar, GLSL sürümü)
PROGRAMS = {
    "shadow":                ("shadow",           [],                      "430 compatibility"),
    "gbuffers_terrain":      ("gbuffers_solid",   ["GBUFFERS_TERRAIN"],    "330 compatibility"),
    "gbuffers_entities":     ("gbuffers_solid",   ["GBUFFERS_ENTITIES"],   "330 compatibility"),
    "gbuffers_block":        ("gbuffers_solid",   ["GBUFFERS_BLOCK"],      "330 compatibility"),
    "gbuffers_hand":         ("gbuffers_solid",   ["GBUFFERS_HAND"],       "330 compatibility"),
    "gbuffers_water":        ("gbuffers_water",   ["GBUFFERS_WATER"],      "330 compatibility"),
    "gbuffers_hand_water":   ("gbuffers_water",   ["GBUFFERS_HAND_WATER"], "330 compatibility"),
    "gbuffers_basic":        ("gbuffers_forward", ["FWD_BASIC"],           "330 compatibility"),
    "gbuffers_textured":     ("gbuffers_forward", ["FWD_TEXTURED"],        "330 compatibility"),
    "gbuffers_textured_lit": ("gbuffers_forward", ["FWD_TEXTURED"],        "330 compatibility"),
    "gbuffers_weather":      ("gbuffers_forward", ["FWD_WEATHER"],         "330 compatibility"),
    "gbuffers_spidereyes":   ("gbuffers_forward", ["FWD_EMISSIVE"],        "330 compatibility"),
    "gbuffers_beaconbeam":   ("gbuffers_forward", ["FWD_EMISSIVE"],        "330 compatibility"),
    "gbuffers_armor_glint":  ("gbuffers_forward", ["FWD_GLINT"],           "330 compatibility"),
    "gbuffers_damagedblock": ("gbuffers_forward", ["FWD_DAMAGED"],         "330 compatibility"),
    "gbuffers_skybasic":     ("gbuffers_sky",     ["SKY_BASIC"],           "330 compatibility"),
    "gbuffers_skytextured":  ("gbuffers_sky",     ["SKY_TEXTURED"],        "330 compatibility"),
    "deferred":              ("deferred",         [],                      "330 compatibility"),
    "deferred1":             ("deferred1",        [],                      "330 compatibility"),
    "deferred2":             ("deferred2",        [],                      "330 compatibility"),
    "composite":             ("composite",        [],                      "330 compatibility"),
    "final":                 ("final",            [],                      "330 compatibility"),
}

def main():
    count = 0
    for folder, dim in DIMENSIONS.items():
        os.makedirs(os.path.join(SHADERS, folder), exist_ok=True)
        for name, (src, defines, version) in PROGRAMS.items():
            for ext, stage in (("vsh", "VERTEX_SHADER"), ("fsh", "FRAGMENT_SHADER")):
                lines = [f"#version {version}"]
                if name == "shadow" and ext == "vsh":
                    lines.append("#extension GL_ARB_shader_image_load_store : enable")
                lines += ["", f"// Otomatik üretildi: tools/generate_wrappers.py - elle düzenlemeyin.",
                          f"// Asıl kod: shaders/program/{src}.glsl", ""]
                lines += [f"#define {stage}", f"#define {dim}"] + [f"#define {d}" for d in defines]
                lines += ["", f'#include "/program/{src}.glsl"', ""]
                with open(os.path.join(SHADERS, folder, f"{name}.{ext}"), "w", encoding="utf-8") as f:
                    f.write("\n".join(lines))
                count += 1
    print(f"{count} sarmalayıcı dosya yazıldı")

if __name__ == "__main__":
    main()
