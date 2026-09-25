# 🪸 CORAL VXGI

![Platform](https://img.shields.io/badge/platform-Minecraft%20Java-darkgreen.svg)
![Loader](https://img.shields.io/badge/requires-Iris%20%2B%20Sodium-blue.svg)
![PBR](https://img.shields.io/badge/LabPBR-supported-purple.svg)
![Version](https://img.shields.io/badge/version-4.46-orange.svg)

CORAL VXGI is a voxel based, real time **ray traced global illumination** shaderpack for Minecraft Java Edition. Very customizable shaderpack — you can tinker with almost every setting from the in-game shader options.

I wanted to create my own shaderpack because the existing ones are either paid or locked behind paywalls or subscriptions, which is frustrating. I decided to make my own, but due to life circumstances, I didn't have the time or the necessary skills to do it from scratch. So I purchased a paid AI subscription (Claude Pro) and then started making CORAL VXGI to test how much the technology has advanced and what it's capable of, while also bringing my dream of a flawless shaderpack to life to share with the community.

## 🚀 Key Features

* ✅ **Ray traced global illumination** — multi-bounce light transport through a voxel copy of the world, with real colour bleeding from every surface it touches.
* ✅ **World space global illumination** — not screen space. Objects behind you and outside your view still light the scene, and a **world space GI cache** keeps the indirect light of every block face within 24 blocks, on screen or not: turn around or step round a corner and the light there is already settled instead of starting as noise.
* ✅ **Cached later bounces** — once a GI ray hits a cached face, the rest of its path is read from the cache: a faster GI pass and less grain in rooms lit by bounced light.
* ✅ **Ray traced block lights** — torches, lava, lamps and portals are sampled directly with shadow rays, so they cast real, shaped shadows instead of the flat vanilla light map. A **light grid** gives every 8-block region its own light list, so there is no limit on the number of light blocks.
* ✅ **Real block shapes** — each block's bounding box is measured automatically during voxelisation. Torches, doors, trapdoors, slabs, carpets and anvils no longer block a whole cube of light. Blocks shaped like an **L, such as stairs, are stored as their true shape** rather than as a full cube, so light reaches a stair tread and does not pass through its own step.
* ✅ **Entities in ray tracing** — mobs, players, animals, chests, signs, beds, boats and armor stands are written into a voxel grid of their own every frame, clipped exactly at block boundaries. They block bounced light, so the ground around and under them gets a contact shadow, they cast real shadows in the light of torches, lanterns and lava, and no light leaks through their bodies.
* ✅ **Fences, walls, panes and bars** — stored as a post and up to four arms, so fences and walls shadow ray traced light, glass panes tint it, and iron bars, chains and cobwebs dim it.
* ✅ **Shaped holes** — the holes in trapdoors and similar blocks are recorded at up to 16×16 per block, so light falls through them in the correct pattern.
* ✅ **Area lights** — shadow softness comes from each emitter's measured size. A torch stays sharp; a glowstone block casts a soft shadow and neighbouring blocks merge into one.
* ✅ **Coloured light** — 9 fixed light colour categories plus texture-tinted emitters, so all 16 candle colours glow in their own colour. Concrete powder and the seven mineral blocks can be made emissive too, each with its own brightness. Light passing through stained glass takes on the glass colour, and tinted glass blocks it completely, as in the game.
* ✅ **Ray traced reflections** on water, glass, polished and metal blocks (also under water and behind glass), including geometry that is off screen, with an optional screen-space fallback for mobs and foliage, and the same distance fog as the world they mirror. **Textured voxels**: every face of the voxel world remembers its block texture, so blocks in reflections show stone, planks and ores as they are instead of one flat colour.
* ✅ **SVGF denoiser** — a variance guided à-trous wavelet filter that removes crawling grain while keeping edges and detail.
* ✅ **TAA, FXAA and RCAS sharpening** — sub-pixel jitter with reprojection and neighbourhood clamping for clean edges, an optional single-frame pass for distant flicker, and AMD's contrast-adaptive sharpening to restore what TAA and the denoiser soften.
* ✅ **Volumetric clouds** — ray-marched clouds you can fly through, with a vanilla-style and an off setting as well.
* ✅ **Water** — **real caustics**: sunlight is refracted by the actual wave field and gathers into bright lines on the floor, sharp in shallow water and soft in deep water. Under water: **light shafts** traced through the shadow map, sunlight that loses red and then green with depth, a surface that mirrors the underwater world when seen at a low angle, plus refraction, animated waves and biome tinted fog.
* ✅ **LabPBR support** — smoothness, metalness, emission, normal mapping and parallax occlusion mapping.
* ✅ **9 tonemapping operators** — ACES, AgX, Lottes, Uchimura, Hable, Reinhard, Reinhard-Jodie, Soft Filmic, or none.
* ✅ **Half resolution GI** — one traced pixel per 2×2 block, filled in by surface: the GI pass takes a quarter of the time on slower cards (Low profile).
* ✅ **Four quality profiles** — Low, Medium, High and Ultra, one click each.
* ✅ **250 settings** — 189 adjustable values and 61 on/off switches, every single one with a hover description.
* ✅ **23 debug views** — inspect albedo, normals, raw GI, the voxel world, block lights and more, with split screen comparison.
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

* 🔜 **Entities in reflections** — entities are in the voxel world for light and shadows, but a mob made of boxes would look wrong in a mirror, so reflections still show them only when they are on screen.
* 🔜 **FSR upscaling** — the sharpening half of FSR already ships; the upscaler does not.
* 🔜 **Distant Horizons and VOXY support** — far far land...
* 🔜 **Wider driver compatibility** — lowering the OpenGL requirement below 4.3 where possible.

## 🐛 Known Issues

* **Direct light sampling reaches 48 blocks and 64 light regions per area.** Beyond that (a huge lava ocean) the weakest regions are lit by bounced rays only, which are noisier.
* **Entities are boxes to the ray tracer.** Each block of space an entity touches holds one box around its parts there, so a mob's shadow in torch light is blocky at close range. Entities are only traced within 32 blocks, bounce light with one average colour per block of space, give off no light of their own, appear in reflections only when they are on screen, and all of it needs Iris 1.8 (Minecraft 1.21 or newer). Plants are not in the voxel grid either.
* **Mobs, chests and the held item have no ray-traced reflections.** Reflection rays cannot see entities and a moving mob never keeps a steady reflection, so they keep their texture colour and get only a sun highlight; with a LabPBR resource pack an iron golem or iron armor looks like smooth plastic rather than a mirror. Metal blocks reflect as metal.
* **Caustics come from the sun and moon only** and follow the pack's own wave field; they fade out in rain, and light from torches or lava makes none.
* **Hole shadows depend on the sun.** Where the sun sees a trapdoor or door edge-on, its holes cannot be recorded; it then passes light evenly by how empty its texture is instead of in the shape of its holes.
* **The underwater mirror is softened on purpose.** Real water shows the sky only inside a sharp circle above you; the pack blends the sky and the mirror over a wide range of angles instead. Set Underwater Surface Mirror to 1 for the strongest mirror, 0 to switch it off.
* **With Block Shapes off**, a light ray that starts inside a block by mistake can still leave it through the far side (a slab's top lies inside its own full cube there, so the start cannot be checked). The camera-facing start point makes this rare; keep Block Shapes on (the default) for the cleanest corners.
* **GI is limited to the voxel range** (128–256 blocks). Outside it, lighting falls back to the vanilla light map.
* **Fences are simplified**: a fence's two rails count as one solid arm, so a little more shadow falls through the gap between them than in reality.
* **The world GI cache reaches 24 blocks** (32 at most) and holds one value per block face. When a torch is placed or broken, the bounced part of its light fades in or out over up to a second; the direct light and the first bounce react at once.
* **Reflections on rough surfaces trace one jittered ray per frame**, so they are grainy unless the Reflection Denoiser is turned on (it ships off) or TAA smooths them over time.
* **Textured voxels use one texture per face direction** (top, sides, bottom) and the block's full-cube mapping, so blocks whose sides differ (a furnace's front) or whose texture is rotated (logs lying sideways, glazed terracotta) can look slightly off in reflections.
* **Hole shadows only work for blocks drawn in the shadow pass.** A block that is never rendered there is treated as solid.
* **Tinted glass blocks sunlight only with Coloured Shadows on** (the default); without it no glass casts a sun shadow.
* **Volumetric clouds are Overworld only**, cast no shadows, and are ray-marched again in sky reflections, which costs time on large water surfaces.
* **Normal mapping and POM need a LabPBR resource pack.** Without one they do nothing. Normal mapping is on from the Medium profile up; parallax is Ultra only, because it is the most expensive setting in the pack.
* **At Voxel Range 256, Shadow Distance must be at least 136 blocks** — Iris requires the shadow distance to be no lower than the voxel distance.
* **Requires a fairly recent GPU.** Voxel ray tracing is expensive; older hardware will struggle even on the Low profile.
* **OptiFine and Oculus are not supported.**
* **macOS is not supported** — Apple's OpenGL stops at 4.1 and has no image load/store, which the voxel grid needs.

## 📋 Requirements

| | |
|---|---|
| Minecraft | **1.21 or newer** (developed on 1.21). 1.20.1 works, but without entities in ray tracing |
| Mod loader | Fabric or NeoForge |
| Shader mod | **Iris 1.8+** with Sodium. Iris 1.7 (the last version for 1.20.1) runs the pack with entities left out of ray tracing |
| OpenGL | **4.3** (image load/store and compute passes) |
| GPU | NVIDIA, AMD or Intel — only standard OpenGL is used |
| OS | Windows or Linux |
| Not supported | OptiFine, Oculus, macOS |

### Video memory, roughly

On top of Minecraft's own usage. Screen buffers are about **0.35 GB at 1080p**, **0.6 GB at 1440p** and **1.4 GB at 4K** regardless of profile. The "pack data" column counts everything the pack allocates besides them: the voxel grid with block shapes and textures, the hole mask, the entity grid, the water map, the light grid, the world GI cache and the shadow map.

| Profile | Voxel grid | Shadow map | Pack data | Suggested video memory |
|---|---|---|---|---|
| Low | 128×96×128 | 1024² | ~0.15 GB | 2 GB |
| Medium (default) | 128×96×128 | 2048² | ~0.19 GB | 3 GB |
| High | 192×128×192 | 3072² | ~0.45 GB | 4 GB |
| Ultra | 256×128×256 | 4096² | ~0.76 GB | 4 GB, 6 GB at 4K |

The hole mask of **Shaped Holes** is the largest single part (50 / 151 / 268 MB at Voxel Range 128 / 192 / 256); dropping **Hole Detail** from 16 to 8 cuts it to a quarter. **Textured Voxel Reflections** take 25 / 75 / 134 MB, the world GI cache about 35 MB and the entity grid about 4 MB on every profile.

## ⚙️ Settings

Everything is configurable in game, no file editing required:

| Page | What it controls |
|---|---|
| Ray Tracing | GI bounces, half resolution GI, world GI cache, ray steps, voxel range, block light sampling, light grid, textured voxels, entities in ray tracing |
| Denoiser | SVGF rounds, edge sharpness, noise tolerance, temporal accumulation |
| Emissive Block Colors | The colour and brightness of every light category |
| Transmission | Coloured light through glass, holes in cutout blocks |
| Reflections | Voxel and screen space reflections, smoothness, refraction, reflection denoiser |
| Lighting | Sun, moon, sky, block light colour and falloff, held light |
| Shadows | Resolution, distance, softness, samples, bias |
| Sky & Fog | Sun disc and glow, volumetric clouds, sunset colouring, fog density |
| Water | Waves, refraction, absorption, caustics, underwater light shafts, depth absorption, surface mirror, underwater fog |
| Materials (PBR) | Normal mapping and parallax occlusion mapping |
| Anti-Aliasing | TAA strength, ghost removal, jitter, FXAA, sharpening |
| Post Processing | Bloom, exposure, tonemapping, saturation, contrast |
| Debug | 23 inspection views and diagnostic tools |

The About page also carries a **Changelog** and a **System Requirements** page, and every setting has a hover description explaining what it does and what it costs.

Custom block groups live in `shaders/block.properties`; menu text lives in `shaders/lang/`. Full internals are documented in `DOCUMENTATION.md`, which ships in the separate **`-dev`** download along with the validation tools — the normal release zip contains only `shaders/` and `LICENSE.txt`.

## 📜 Changelog

See `CHANGELOG.md` for the full history. In short, the current version is **4.46**, and the largest changes since the 2.1 base are:

* **Ray traced reflections, emissive blocks, volumetric clouds and sharpening** all arrived in 4.19–4.20.
* **Light leaks closed** (4.21–4.24) — light no longer escapes through slabs, carpets, dirt paths or stairs.
* **Blow-outs fixed** (4.29–4.34) — emitters were being counted twice, and the sharpening pass was scaling the whole image down and clipping HDR. Light sources have real gradation again.
* **Reflection flicker fixed** (4.26–4.34) — including metal blocks that went black where a normal map was busy.
* **Parallax fixed** (4.27) — the radial "lens" distortion is gone and the depth setting works.
* **Light grid and fences** (4.35) — no limit on light blocks; fences, walls, panes and bars are part of the ray traced world.
* **Half resolution GI** (4.36) — a quarter of the GI cost for slower cards.
* **World space GI cache** (4.37) — newly visible places start with settled light, and later bounces come from the cache.
* **Textured voxels** (4.38) — blocks in ray traced reflections show their real texture.
* **Entities in ray tracing** (4.39) — mobs, players and chests block bounced light and cast shadows in torch light.
* **Real caustics and underwater light** (4.40) — refracted sunlight on the floor, light shafts, depth absorption and a mirror-like surface from below.
* **Polish** (4.41–4.43) — a loading fix, no hard circle of sky under water, iron golems and armor no longer see-through and no light through mobs, updated system requirements.
* **Full review** (4.44) — about two dozen faults fixed in one release: metal behind glass and water, loading on NVIDIA with Light Grid off, dark patches on newly revealed terrain, fog through windows and in reflections, tinted glass, open fence gates, trapdoor holes over the day, AgX / Soft Filmic tonemaps, lightning, the held item's anti-aliasing, and wrong tooltips.
* **Corner leaks closed** (4.45–4.46) — no more bright lines, white specks or rows of orange dots where a wall meets the floor, and no light through the edges of stairs: every light ray now starts in the open, on the camera's side of the surface, and a ray that starts inside a block ends there.

---
Contains AI-generated code, assets and text. Made with AI.
