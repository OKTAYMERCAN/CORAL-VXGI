# 🪸 CORAL VXGI

![Platform](https://img.shields.io/badge/platform-Minecraft%20Java-darkgreen.svg)
![Loader](https://img.shields.io/badge/requires-Iris%20%2B%20Sodium-blue.svg)
![PBR](https://img.shields.io/badge/LabPBR-supported-purple.svg)

CORAL VXGI is a voxel based, real time **ray traced global illumination** shaderpack for Minecraft Java Edition. Very customizable shaderpack, you can thinkerin almost every settings in shaderpack settings.

## 🚀 Key Features

* ✅ **Ray traced global illumination** — multi-bounce light transport through a voxel copy of the world, with real colour bleeding from every surface it touches.
* ✅ **World Space global illumination** — not screen space, Objects behind you and outside your view still light the scene.
* ✅ **Ray traced block lights** — torches, lava, lamps and portals are sampled directly with shadow rays, so they cast real, shaped shadows instead of the flat vanilla light map.
* ✅ **Real block shapes** — each block's bounding box is measured automatically during voxelisation. Torches, doors, trapdoors, slabs, carpets and anvils no longer block a whole cube of light.
* ✅ **Shaped holes** — the holes in trapdoors and similar blocks are recorded at up to 16×16 per block, so light falls through them in the correct pattern.
* ✅ **Area lights** — shadow softness comes from each emitter's measured size. A torch stays sharp; a glowstone block casts a soft shadow and neighbouring blocks merge into one.
* ✅ **Coloured light** — 9 light colour categories plus texture-tinted emitters, so all 16 candle colours glow in their own colour. Light passing through stained glass takes on the glass colour.
* ✅ **Ray traced reflections** on water, glass, polished and metal blocks, including geometry that is off screen, with an optional screen-space fallback for mobs and foliage.
* ✅ **SVGF denoiser** — a variance guided à-trous wavelet filter that removes crawling grain while keeping edges and detail.
* ✅ **TAA** — sub-pixel jitter with reprojection and neighbourhood clamping for clean edges.
* ✅ **Water** — refraction, depth based absorption, caustics, animated waves and biome tinted underwater fog.
* ✅ **LabPBR support** — smoothness, metalness, emission, normal mapping and parallax occlusion mapping.
* ✅ **200+ settings** — every single one with a hover description.
* ✅ **22 debug views** — inspect albedo, normals, raw GI, the voxel world, block lights and more, with split screen comparison.
* ✅ **And more...** — I still actively add tons of feature.
  
> [!IMPORTANT]
> Iris stores your settings in a `.txt` file next to the pack, named after the zip. When updating, delete the old zip **and** its `.txt`, otherwise your saved settings override the new defaults.

> [!TIP]
> If the framerate is low, switch the profile to **Low** first, then reduce **Voxel Range** to 128 and lower **GI Ray Steps**.

## 📸 Screenshots

<!-- Replace the placeholders below with your own screenshots -->
*(Global illumination and coloured block lights)*

*(Shaped shadows through trapdoors)*

*(Water refraction and caustics)*

## 🗺️ Planned Features

* 🔜 **Sharpening pass (RCAS)** — to offset the softness that TAA and the denoiser introduce.
* 🔜 **Half resolution GI with upscaling** — a large performance win for weaker systems.
* 🔜 **Volumetric clouds** — cumulus and blocky vanilla-style variants you can fly through.
* 🔜 **Entity voxelisation** — so mobs and players block and bounce light, not just cast sun shadows.
* 🔜 **Improved caustics** — currently an approximation rather than true light focusing.
* 🔜 **FSR** — İmprove visuals and Performance
* 🔜 **Antialising** — For Good visuals far views
* 🔜 **Distant Horizon and VOXY support** — Far far land...
* 🔜 **Wider driver compatibility** — lowering the OpenGL requirement below 4.3 where possible.

## 🐛 Known Issues

* **Mobs, players and plants are not in the voxel grid.** They cast sun shadows, but they do not block or bounce ray traced light.
* **GI is limited to the voxel range** (128–256 blocks). Outside it, lighting falls back to the vanilla light map.
* **Fences, iron bars and other lattice shaped blocks are not voxelised**, because a bounding box would be far larger than the real shape.
* **TAA and the denoiser both soften the image.** There is no sharpening pass yet — see Planned Features. Lower *Jitter Amount* and *Noise Tolerance* if it bothers you.
* **Hole shadows only work for blocks drawn in the shadow pass.** A block that is never rendered there is treated as solid.
* **Normal mapping and POM need a LabPBR resource pack.** Without one they do nothing, which is why they ship disabled.
* **Reflections on rough surfaces are approximated** with a fixed jitter rather than proper multi-sampling.
* **Requires a fairly recent GPU.** Voxel ray tracing is expensive; older hardware will struggle even on the Low profile.
* **Optifine Not supporting
* **MAC not officially supported but if it works then it is good to you.

## 📋 Requirements

* Minecraft Java Edition with **Iris 1.6+** and **Sodium**
* A GPU supporting **OpenGL 4.3**
* **OptiFine is not supported.** **macOS is not supported.**

## ⚙️ Settings

Everything is configurable in game, no file editing required:

| Page | What it controls |
|---|---|
| Ray Tracing | GI bounces, ray steps, voxel range, block light sampling, emissive colours |
| Denoiser | SVGF rounds, edge sharpness, noise tolerance, temporal accumulation |
| Transmission | Coloured light through glass, holes in cutout blocks |
| Reflections | Voxel and screen space reflections, smoothness, LabPBR |
| Lighting | Sun, moon, sky, block light colour and falloff, held light |
| Shadows | Resolution, distance, softness, samples, bias |
| Sky & Fog | Sun disc, clouds, sunset colouring, fog density |
| Water | Waves, refraction, absorption, caustics, underwater fog |
| Materials (PBR) | Normal mapping and parallax occlusion mapping |
| Anti-Aliasing | TAA strength, ghost removal, jitter |
| Post Processing | Bloom, exposure, tonemapping, saturation, contrast |
| Debug | 22 inspection views and diagnostic tools |

Custom block groups live in `shaders/block.properties`; menu text lives in `shaders/lang/`. Full internals are documented in `DOKUMANTASYON.md`.

## Contains AI-generated code, assets, and text Made with AI.
 I wanted to create my own shaderpack because the existing ones are either paid or locked behind paywalls or subscriptions. I decided to make my own, but due to life circumstances, I didn't have the time or the necessary skills to do it from scratch. So, I purchased a paid AI subscription to test how much the technology has advanced and what it's capable of, while also bringing my dream of a flawless shaderpack to life to share with the community.
