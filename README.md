# 🪸 CORAL VXGI

![Platform](https://img.shields.io/badge/platform-Minecraft%20Java-darkgreen.svg)
![Loader](https://img.shields.io/badge/requires-Iris%20%2B%20Sodium-blue.svg)
![PBR](https://img.shields.io/badge/LabPBR-supported-purple.svg)
![Version](https://img.shields.io/badge/version-4.50-orange.svg)

CORAL VXGI is a voxel based, real time **ray traced global illumination** shaderpack for Minecraft Java Edition. Very customizable shaderpack — you can tinker with almost every setting from the in-game shader options.

I wanted to create my own shaderpack because the existing ones are either paid or locked behind paywalls or subscriptions, which is frustrating. I decided to make my own, but due to life circumstances, I didn't have the time or the necessary skills to do it from scratch. So I purchased a paid AI subscription (Claude Pro) and then started making CORAL VXGI to test how much the technology has advanced and what it's capable of, while also bringing my dream of a flawless shaderpack to life to share with the community.

## 🚀 Key Features

* ✅ **Ray traced global illumination** — multi-bounce light transport through a voxel copy of the world, with real colour bleeding from every surface it touches. The ray traced area is 128 blocks wide by default and can be set up to **512 blocks**.
* ✅ **World space global illumination** — not screen space. Objects behind you and outside your view still light the scene, and a **world space GI cache** keeps the indirect light of every block face within 24 blocks (up to 64), on screen or not: turn around or step round a corner and the light there is already settled instead of starting as noise.
* ✅ **Cached later bounces** — once a GI ray hits a cached face, the rest of its path is read from the cache: a faster GI pass and less grain in rooms lit by bounced light.
* ✅ **Ray traced block lights** — torches, lava, lamps and portals are sampled directly with shadow rays, so they cast real, shaped shadows instead of the flat vanilla light map. A **light grid** gives every 8-block region its own light list, so there is no limit on the number of light blocks, and lights can reach **up to 512 blocks**: far away they are gathered by 32-block region, so empty space costs nothing.
* ✅ **Real block shapes** — each block's bounding box is measured automatically during voxelisation. Torches, doors, trapdoors, slabs, carpets and anvils no longer block a whole cube of light. Blocks shaped like an **L, such as stairs, are stored as their true shape** rather than as a full cube, so light reaches a stair tread and does not pass through its own step.
* ✅ **Entities in ray tracing** — mobs, players, animals, chests, signs, beds, boats and armor stands are written into a voxel grid of their own every frame, clipped exactly at block boundaries. They block bounced light, so the ground around and under them gets a contact shadow, they cast real shadows in the light of torches, lanterns and lava, and no light leaks through their bodies.
* ✅ **Entities in reflections** — every entity also keeps a **textured copy at 1/8 block**, so mirrors, metal, glass and water show villagers, cows, other players and you — hat, eyes and crossed arms included — even when they are behind the camera or you are in first person.
* ✅ **Fences, walls, panes and bars** — stored as a post and up to four arms, so fences and walls shadow ray traced light, glass panes tint it, and iron bars, chains and cobwebs dim it.
* ✅ **Shaped holes** — the holes in trapdoors and similar blocks are recorded at up to 16×16 per block, so light falls through them in the correct pattern.
* ✅ **Area lights** — shadow softness comes from each emitter's measured size. A torch stays sharp; a glowstone block casts a soft shadow and neighbouring blocks merge into one.
* ✅ **Coloured light** — 9 fixed light colour categories plus texture-tinted emitters, so all 16 candle colours glow in their own colour. Concrete powder and the seven mineral blocks can be made emissive too, each with its own brightness. Light passing through stained glass takes on the glass colour, and tinted glass blocks it completely, as in the game.
* ✅ **Ray traced reflections** on water, glass, polished and metal blocks (also under water and behind glass), including geometry that is off screen, with an optional screen-space fallback, and the same distance fog as the world they mirror. **Textured voxels**: each of the six faces of every block remembers its own texture and how it is turned, so a furnace shows its front on one side only, and sideways logs and glazed terracotta are turned as in the world.
* ✅ **SVGF denoiser** — a variance guided à-trous wavelet filter that removes crawling grain while keeping edges and detail.
* ✅ **TAA, FXAA and RCAS sharpening** — sub-pixel jitter with reprojection and neighbourhood clamping for clean edges, an optional single-frame pass for distant flicker, and AMD's contrast-adaptive sharpening to restore what TAA and the denoiser soften.
* ✅ **Volumetric clouds** — ray-marched clouds you can fly through, with a vanilla-style and an off setting as well.
* ✅ **Water** — **real caustics**: sunlight is refracted by the actual wave field and gathers into bright lines on the floor, sharp in shallow water and soft in deep water. Under water: **light shafts** traced through the shadow map, sunlight that loses red and then green with depth, refraction, animated waves and biome tinted fog.
* ✅ **The water surface from below** — looking up from under water, the surface has **waves**: the sky, the clouds and the land above bend and ripple through it the way real water bends them, and all around it mirrors the water below — mobs included — with a reach you choose (8 blocks by default, like a real sea, up to 512). No hard circle of sky.
* ✅ **LabPBR support** — smoothness, metalness, emission, normal mapping and parallax occlusion mapping.
* ✅ **9 tonemapping operators** — ACES, AgX, Lottes, Uchimura, Hable, Reinhard, Reinhard-Jodie, Soft Filmic, or none.
* ✅ **Half resolution GI** — one traced pixel per 2×2 block, filled in by surface: the GI pass takes a quarter of the time on slower cards (Low profile).
* ✅ **Four quality profiles** — Low, Medium, High and Ultra, one click each.
* ✅ **257 settings** — 195 adjustable values and 62 on/off switches, every single one with a hover description and, where it matters, a warning about what it costs.
* ✅ **23 debug views** — inspect albedo, normals, raw GI, the voxel world, block lights and more, with split screen comparison.
* ✅ **And more...** — I still actively add tons of features.

## 📋 Requirements

| | |
|---|---|
| Minecraft | **1.21 or newer** (developed on 1.21). 1.20.1 works, but without entities in ray tracing and in reflections |
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
| Low | 128×96×128 | 1024² | ~0.18 GB | 2 GB |
| Medium (default) | 128×96×128 | 2048² | ~0.22 GB | 3 GB |
| High | 192×128×192 | 3072² | ~0.53 GB | 4 GB |
| Ultra | 256×128×256 | 4096² | ~0.89 GB | 4 GB, 6 GB at 4K |
| *Voxel Range 384* | 384×128×384 | — | ~1.1 GB | 6 GB |
| *Voxel Range 512* | 512×128×512 | — | ~1.8 GB | 8 GB |

The hole mask of **Shaped Holes** is the largest single part (50 / 151 / 268 MB at Voxel Range 128 / 192 / 256); dropping **Hole Detail** from 16 to 8 cuts it to a quarter. **Textured Voxel Reflections** take 50 / 151 / 268 MB (604 MB / 1.07 GB at 384 / 512), the world GI cache about 35 MB (0.25 GB with a Cache Radius above 32) and the entity grid about 6 MB (38 MB at Entity Range 64).

> [!IMPORTANT]
> Iris stores your settings in a `.txt` file next to the pack, named after the zip. When updating, delete the old zip **and** its `.txt`, otherwise your saved settings override the new defaults.

> [!TIP]
> .

## 📸 Screenshots
<img width="2560" height="1365" alt="2026-09-26_00 52 09" src="https://github.com/user-attachments/assets/8dff6746-7f41-48b8-983b-66458598467e" />

<!-- Replace the placeholders below with your own screenshots -->
*(Global illumination and coloured block lights)*
<img width="2560" height="1365" alt="2026-09-26_00 45 27" src="https://github.com/user-attachments/assets/ceea6fca-6744-4a5b-8f4f-f6539918ea12" />
<img width="2560" height="1365" alt="2026-09-26_00 48 10" src="https://github.com/user-attachments/assets/f33e98a2-38e1-4be3-95c9-f5e326e126ff" />
<img width="2560" height="1365" alt="2026-09-26_00 46 45" src="https://github.com/user-attachments/assets/4a13000f-40ab-4558-a1e1-af288b06dcb3" />
<img width="2560" height="1365" alt="2026-09-26_00 46 27" src="https://github.com/user-attachments/assets/edc0b62b-30f1-4d74-bc9a-32ed3d3622c2" />

*(Water refraction and caustics)*
<img width="2560" height="1365" alt="2026-09-26_00 23 58" src="https://github.com/user-attachments/assets/fa898c2f-8276-437d-b17a-c7f2bcd413da" />

*(The water surface seen)*
<img width="2560" height="1365" alt="2026-09-26_00 57 05" src="https://github.com/user-attachments/assets/cbc000e6-9fb1-414c-85a5-99b02589c8da" />

<img width="2560" height="1365" alt="2026-09-25_00 43 33" src="https://github.com/user-attachments/assets/50166e05-08e5-45d5-bd56-fd873e79f5ba" />

*(PBR)*
<img width="2560" height="1365" alt="2026-09-26_00 50 05" src="https://github.com/user-attachments/assets/f65e5f02-67bb-4d32-b907-6f92f83b85bd" />

*(Shadows and Mob shadows)*
<img width="2560" height="1365" alt="2026-09-26_00 46 01" src="https://github.com/user-attachments/assets/dc4ee608-f37f-45c9-955b-fba8b12c8682" />

## 🗺️ Planned Features

* 🔜 **Distant Horizons and VOXY support** — far far land...
* 🔜 **Performance Improvements** — For Mid and low end devices...
  
## 🐛 Known Issues

* **Far block lights are gathered by region.** Within 48 blocks every light region is listed on its own; further out lights are gathered per 32-block region, and each list keeps the brightest regions only (**Light Regions per List**, 64 by default). In a huge lava ocean or the Nether the regions that do not fit are lit by bounced rays only, which are noisier.
* **Entities are boxes to light and shadows.** Each block of space an entity touches holds one box around its parts there, so a mob's shadow in torch light is blocky at close range. Reflections use the textured 1/8-block copy instead, but that copy is coarse for small details (the texture of a held item), and up to 1024 blocks of space get one (2048 at Entity Range 64); beyond that a mob shows as boxes in reflections. Entities are only traced within 32 blocks (64 at most), give off no light of their own, and all of it needs Iris 1.8 (Minecraft 1.21 or newer). Plants are not in the voxel grid either.
* **Mobs and held items reflect only when you ask.** Their own surfaces get ray traced reflections with **Mobs and Items Reflect** (off by default), because a moving mob never keeps a steady reflection; without it, iron golems and armor from a LabPBR resource pack look like smooth plastic rather than mirrors. Mobs do appear *in* the reflections of other surfaces by default.
* **Caustics come from the sun and moon only** and follow the pack's own wave field; they fade out in rain, and light from torches or lava makes none.
* **Hole shadows depend on the sun.** Where the sun sees a trapdoor or door edge-on, its holes cannot be recorded; it then passes light evenly by how empty its texture is instead of in the shape of its holes.
* **The water surface from below is softened on purpose.** Real water shows the sky only inside a circle above you (Snell's window); by default the pack blends sky and mirror over a wide range of angles and lets the waves decide it ripple by ripple, so no circle shows. Set **Sky Circle Softness** to 0 for the physical circle. Where the bent view of the sky leaves the screen, the sky is worked out again with its clouds, which costs a little while you look up from under water.
* **A long underwater mirror costs time.** **Underwater Mirror Reach** goes up to 512 blocks, but the mirror also needs enough Reflection Ray Steps to get that far and ends at the edge of the ray traced area.
* **With Block Shapes off**, a light ray that starts inside a block by mistake can still leave it through the far side (a slab's top lies inside its own full cube there, so the start cannot be checked). The camera-facing start point makes this rare; keep Block Shapes on (the default) for the cleanest corners.
* **GI is limited to the voxel range** (128–512 blocks). Outside it, lighting falls back to the vanilla light map. Minecraft's full 32 chunks would need a 1024-block area, which is more video memory and larger 3D images than drivers have to allow.
* **Large Voxel Ranges pull the shadows along.** Iris only builds the voxel world from chunks the shadow pass draws, so Shadow Distance is raised to what the Voxel Range needs (72 to 264 blocks). At 384 and 512 that spreads the shadow map thinner (raise Shadow Resolution), fixes Hole Detail at 8, and needs a Render Distance of at least 13 / 17 chunks.
* **Fences are simplified**: a fence's two rails count as one solid arm, so a little more shadow falls through the gap between them than in reality.
* **The world GI cache holds one value per block face.** When a torch is placed or broken, the bounced part of its light fades in or out over up to a second; the direct light and the first bounce react at once. A Cache Radius above 32 takes another 0.25 GB of video memory.
* **Reflections on rough surfaces trace one jittered ray per frame**, so they are grainy unless the Reflection Denoiser is turned on (it ships off) or TAA smooths them over time.
* **Mirrored textures can come out flipped in reflections.** Textured voxels record how each face's texture is turned, but not a texture the block model mirrors (a door hinged on the other side).
* **Hole shadows only work for blocks drawn in the shadow pass.** A block that is never rendered there is treated as solid.
* **Tinted glass blocks sunlight only with Coloured Shadows on** (the default); without it no glass casts a sun shadow.
* **Volumetric clouds are Overworld only**, cast no shadows, and are ray-marched again in sky reflections and in the sky seen through the water surface from below, which costs time on large water surfaces.
* **Normal mapping and POM need a LabPBR resource pack.** Without one they do nothing. Normal mapping is on from the Medium profile up; parallax is Ultra only, because it is the most expensive setting in the pack.
* **Requires a fairly recent GPU.** Voxel ray tracing is expensive; older hardware will struggle even on the Low profile.
* **OptiFine and Oculus are not supported.**
* **macOS is not supported** — Apple's OpenGL stops at 4.1 and has no image load/store, which the voxel grid needs.

## ⚙️ Settings

Everything is configurable in game, no file editing required:

| Page | What it controls |
|---|---|
| Ray Tracing | GI bounces, half resolution GI, world GI cache, ray steps, voxel range, block light sampling and range, light grid, textured voxels, entities in ray tracing and their range |
| Denoiser | SVGF rounds, edge sharpness, noise tolerance, temporal accumulation |
| Emissive Block Colors | The colour and brightness of every light category |
| Transmission | Coloured light through glass, holes in cutout blocks |
| Reflections | Voxel and screen space reflections, smoothness, refraction, entities in reflections, mobs and items that reflect, reflection denoiser |
| Lighting | Sun, moon, sky, block light colour and falloff, held light |
| Shadows | Resolution, distance (raised to what the voxel range needs), softness, samples, bias |
| Sky & Fog | Sun disc and glow, volumetric clouds, sunset colouring, fog density |
| Water | Waves, refraction, absorption, caustics, underwater light shafts, depth absorption, underwater fog, and the **Water Surface From Below** page: its waves, sky circle softness, mirror strength and mirror reach |
| Materials (PBR) | Normal mapping and parallax occlusion mapping |
| Anti-Aliasing | TAA strength, ghost removal, jitter, FXAA, sharpening |
| Post Processing | Bloom, exposure, tonemapping, saturation, contrast |
| Debug | 23 inspection views and diagnostic tools |

The About page also carries a **Changelog** and a **System Requirements** page, and every setting has a hover description explaining what it does and what it costs.

Custom block groups live in `shaders/block.properties`; menu text lives in `shaders/lang/`. The validation tools ship in the separate **`-dev`** download — the normal release zip contains only `shaders/` and `LICENSE.txt`.

## 📜 Changelog

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
* **Long distances** (4.47) — Voxel Range up to 512 blocks, block light up to 512 blocks, ray steps up to 1024, a world cache radius up to 64, entities up to 64 blocks away, and a Shadow Distance that follows the Voxel Range. The profiles are unchanged.
* **Entities in reflections** (4.48) — mobs, other players and you appear in mirrors, metal, glass and water, as a textured 1/8-block copy.
* **Per-face textures** (4.49) — every face of a reflected block has its own texture, turned the way the block is turned; the underwater mirror reaches only what is near, like a real sea.
* **The water surface from below** (4.50) — waves, a sky that bends and ripples through them, no hard circle, and an underwater mirror whose reach goes from 2 to 512 blocks.

---
Contains AI-generated code, assets and text. Made with AI.
