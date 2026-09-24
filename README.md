# 🪸 CORAL VXGI

![Platform](https://img.shields.io/badge/platform-Minecraft%20Java-darkgreen.svg)
![Loader](https://img.shields.io/badge/requires-Iris%20%2B%20Sodium-blue.svg)
![PBR](https://img.shields.io/badge/LabPBR-supported-purple.svg)
![Version](https://img.shields.io/badge/version-4.34-orange.svg)

CORAL VXGI is a voxel based, real time **ray traced global illumination** shaderpack for Minecraft Java Edition. Very customizable shaderpack — you can tinker with almost every setting from the in-game shader options.

I wanted to create my own shaderpack because the existing ones are either paid or locked behind paywalls or subscriptions, which is frustrating. I decided to make my own, but due to life circumstances, I didn't have the time or the necessary skills to do it from scratch. So I purchased a paid AI subscription (Claude Pro) and then started making CORAL VXGI to test how much the technology has advanced and what it's capable of, while also bringing my dream of a flawless shaderpack to life to share with the community.

## 🚀 Key Features

* ✅ **Ray traced global illumination** — multi-bounce light transport through a voxel copy of the world, with real colour bleeding from every surface it touches.
* ✅ **World space global illumination** — not screen space. Objects behind you and outside your view still light the scene.
* ✅ **Ray traced block lights** — torches, lava, lamps and portals are sampled directly with shadow rays, so they cast real, shaped shadows instead of the flat vanilla light map.
* ✅ **Real block shapes** — each block's bounding box is measured automatically during voxelisation. Torches, doors, trapdoors, slabs, carpets and anvils no longer block a whole cube of light. Blocks shaped like an **L, such as stairs, are stored as their true shape** rather than as a full cube, so light reaches a stair tread and does not pass through its own step.
* ✅ **Shaped holes** — the holes in trapdoors and similar blocks are recorded at up to 16×16 per block, so light falls through them in the correct pattern.
* ✅ **Area lights** — shadow softness comes from each emitter's measured size. A torch stays sharp; a glowstone block casts a soft shadow and neighbouring blocks merge into one.
* ✅ **Coloured light** — 9 fixed light colour categories plus texture-tinted emitters, so all 16 candle colours glow in their own colour. Concrete powder and the seven mineral blocks can be made emissive too, each with its own brightness. Light passing through stained glass takes on the glass colour.
* ✅ **Ray traced reflections** on water, glass, polished and metal blocks, including geometry that is off screen, with an optional screen-space fallback for mobs and foliage.
* ✅ **SVGF denoiser** — a variance guided à-trous wavelet filter that removes crawling grain while keeping edges and detail.
* ✅ **TAA, FXAA and RCAS sharpening** — sub-pixel jitter with reprojection and neighbourhood clamping for clean edges, an optional single-frame pass for distant flicker, and AMD's contrast-adaptive sharpening to restore what TAA and the denoiser soften.
* ✅ **Volumetric clouds** — ray-marched clouds you can fly through, with a vanilla-style and an off setting as well.
* ✅ **Water** — refraction, depth based absorption, caustics, animated waves and biome tinted underwater fog.
* ✅ **LabPBR support** — smoothness, metalness, emission, normal mapping and parallax occlusion mapping.
* ✅ **9 tonemapping operators** — ACES, AgX, Lottes, Uchimura, Hable, Reinhard, Reinhard-Jodie, Soft Filmic, or none.
* ✅ **Four quality profiles** — Low, Medium, High and Ultra, one click each.
* ✅ **250+ settings** — 206 sliders and 52 on/off switches, every single one with a hover description.
* ✅ **22 debug views** — inspect albedo, normals, raw GI, the voxel world, block lights and more, with split screen comparison.
* ✅ **And more...** — I still actively add tons of features.

> [!IMPORTANT]
> Iris stores your settings in a `.txt` file next to the pack, named after the zip. When updating, delete the old zip **and** its `.txt`, otherwise your saved settings override the new defaults.

> [!TIP]
> If the framerate is low, switch the profile to **Low** first, then reduce **Voxel Range** to 128 and lower **GI Ray Steps**.

## 📸 Screenshots

<img width="2560" height="1370" alt="2026-09-24_03 04 33" src="https://github.com/user-attachments/assets/13ec20a0-af45-4c8b-8bf0-efee1f93b0a1" />
<img width="2560" height="1370" alt="2026-09-24_03 04 11" src="https://github.com/user-attachments/assets/507b5aad-53e1-43d4-ad76-db557d838d0c" />
<img width="2560" height="1370" alt="2026-09-24_03 00 28" src="https://github.com/user-attachments/assets/2d3dbd13-bd5a-4f69-943c-6e700db0d040" />
<img width="2560" height="1370" alt="2026-09-24_02 59 28" src="https://github.com/user-attachments/assets/29269bdd-b797-4032-bd25-6e8901a2e002" />
<img width="2560" height="1370" alt="2026-09-24_02 58 43" src="https://github.com/user-attachments/assets/b679d83a-4719-4dfc-ba71-9d44ac469317" />
<img width="2560" height="1370" alt="2026-09-21_11 47 12" src="https://github.com/user-attachments/assets/ee71561a-7703-4acd-bab4-f9f021e9e994" />
<img width="2560" height="1370" alt="2026-09-24_03 01 21" src="https://github.com/user-attachments/assets/e2e8fe20-a4d1-41cc-a579-4b92a3fd0e40" />



## 🗺️ Planned Features

* 🔜 **Half resolution GI with upscaling** — a large performance win for weaker systems.
* 🔜 **Entity voxelisation** — so mobs and players block and bounce light, not just cast sun shadows.
* 🔜 **More than 1024 light sources** — and a light list sorted by distance, so nearby lights are never the ones dropped (see Known Issues).
* 🔜 **Improved caustics** — currently an approximation rather than true light focusing.
* 🔜 **FSR upscaling** — the sharpening half of FSR already ships; the upscaler does not.
* 🔜 **Distant Horizons and VOXY support** — far far land...
* 🔜 **Wider driver compatibility** — lowering the OpenGL requirement below 4.3 where possible.

## 🐛 Known Issues

* **Only 1024 light sources fit in the grid at once.** Every lava block, lit candle or glowstone cell is one entry, so lava lakes and the Nether reach this easily. Extra lights get no direct sampling and no shaped shadows, and because the list is filled in chunk draw order rather than by distance, the dropped ones can be the ones right next to you — and they may pop in and out as chunks are redrawn.
* **Mobs, players, plants and block entities are not in the voxel grid.** Chests, signs and beds included. They cast sun shadows, but they do not block or bounce ray traced light.
* **GI is limited to the voxel range** (128–256 blocks). Outside it, lighting falls back to the vanilla light map.
* **Fences, iron bars and other lattice shaped blocks are not voxelised**, because a bounding box would be far larger than the real shape.
* **Reflections on rough surfaces trace one jittered ray per frame**, so they are grainy unless the Reflection Denoiser is turned on (it ships off) or TAA smooths them over time.
* **Voxels have one flat colour**, so reflections of off-screen geometry are untextured.
* **Hole shadows only work for blocks drawn in the shadow pass.** A block that is never rendered there is treated as solid.
* **Volumetric clouds are Overworld only**, cast no shadows, and are ray-marched again in sky reflections, which costs time on large water surfaces.
* **Normal mapping and POM need a LabPBR resource pack.** Without one they do nothing. Normal mapping is on from the Medium profile up; parallax is Ultra only, because it is the most expensive setting in the pack.
* **At Voxel Range 256, Shadow Distance must be at least 136 blocks** — Iris requires the shadow distance to be no lower than the voxel distance.
* **Requires a fairly recent GPU.** Voxel ray tracing is expensive; older hardware will struggle even on the Low profile.
* **OptiFine and Oculus are not supported.**
* **macOS is not supported** — Apple's OpenGL stops at 4.1 and has no image load/store, which the voxel grid needs.

## 📋 Requirements

| | |
|---|---|
| Minecraft | 1.20.1 or newer (developed on 1.21) |
| Mod loader | Fabric or NeoForge |
| Shader mod | **Iris 1.7+** with Sodium (1.6.6 is the absolute minimum) |
| OpenGL | **4.3** |
| GPU | NVIDIA, AMD or Intel — only standard OpenGL is used |
| OS | Windows or Linux |
| Not supported | OptiFine, Oculus, macOS |

### Video memory, roughly

On top of Minecraft's own usage. Screen buffers are about **0.35 GB at 1080p** and **1.4 GB at 4K** regardless of profile.

| Profile | Voxel grid | Shadow map | Grid + shadows |
|---|---|---|---|
| Low | 128×96×128 | 1024² | ~0.07 GB |
| Medium (default) | 128×96×128 | 2048² | ~0.1 GB |
| High | 192×128×192 | 3072² | ~0.3 GB |
| Ultra | 256×128×256 | 4096² | ~0.5 GB |

Turning **Shaped Holes** off, or dropping **Hole Detail** from 16 to 8, saves most of the grid memory.

## ⚙️ Settings

Everything is configurable in game, no file editing required:

| Page | What it controls |
|---|---|
| Ray Tracing | GI bounces, ray steps, voxel range, block light sampling, emissive minerals |
| Denoiser | SVGF rounds, edge sharpness, noise tolerance, temporal accumulation |
| Emissive Block Colors | The colour and brightness of every light category |
| Transmission | Coloured light through glass, holes in cutout blocks |
| Reflections | Voxel and screen space reflections, smoothness, refraction, reflection denoiser |
| Lighting | Sun, moon, sky, block light colour and falloff, held light |
| Shadows | Resolution, distance, softness, samples, bias |
| Sky & Fog | Sun disc and glow, volumetric clouds, sunset colouring, fog density |
| Water | Waves, refraction, absorption, caustics, underwater fog |
| Materials (PBR) | Normal mapping and parallax occlusion mapping |
| Anti-Aliasing | TAA strength, ghost removal, jitter, FXAA, sharpening |
| Post Processing | Bloom, exposure, tonemapping, saturation, contrast |
| Debug | 22 inspection views and diagnostic tools |

The About page also carries a **Changelog** and a **System Requirements** page, and every setting has a hover description explaining what it does and what it costs.

Custom block groups live in `shaders/block.properties`; menu text lives in `shaders/lang/`. Full internals are documented in `DOCUMENTATION.md`, which ships in the separate **`-dev`** download along with the validation tools — the normal release zip contains only `shaders/` and `LICENSE.txt`.

## 📜 Changelog

See `CHANGELOG.md` for the full history. In short, the current version is **4.34**, and the largest changes since the 2.1 base are:

* **Ray traced reflections, emissive blocks, volumetric clouds and sharpening** all arrived in 4.19–4.20.
* **Light leaks closed** (4.21–4.24) — light no longer escapes through slabs, carpets, dirt paths or stairs.
* **Blow-outs fixed** (4.29–4.34) — emitters were being counted twice, and the sharpening pass was scaling the whole image down and clipping HDR. Light sources have real gradation again.
* **Reflection flicker fixed** (4.26–4.34) — including metal blocks that went black where a normal map was busy.
* **Parallax fixed** (4.27) — the radial "lens" distortion is gone and the depth setting works.

---
Contains AI-generated code, assets and text. Made with AI.
