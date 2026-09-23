# CORAL VXGI - Developer Documentation

Version: **4.34** - Author: Oktay Mercan

This document explains **how the pack works** and **how to develop it**. Player-facing explanations live in the in-game menu (the hover text of every setting, `shaders/lang/en_us.lang`). Code comments, tools and documentation are in English; shader sources are plain 7-bit ASCII.

**About this code base:** 4.19/4.20 is not a continuation of 4.18. It is the 2.1 code base with a few parts ported from 4.18: volumetric clouds, nine tonemaps, the parallax / normal-map fix and the About page (4.19), then reflections, the emissive-block system, FXAA and RCAS sharpening (4.20). 4.21 and 4.22 close the light leaks of the ray traced block light (5.1, 5.3), 4.23 brings over the sun glow fix (5.11), 4.24 gives blocks shaped like an L a correct shape (5.1), and 4.25 fixes how much sky light a shaded surface receives (5.11). GI, shadows, water, the denoiser and the profile values are still 2.1. Nothing else from the 4.x line (light grid, world-space GI cache, detail shapes, compute passes, eye adaptation) exists here.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements and installation](#2-requirements-and-installation)
3. [Folder structure](#3-folder-structure)
4. [Render pipeline (pass order)](#4-render-pipeline-pass-order)
5. [Core systems](#5-core-systems)
6. [Settings system](#6-settings-system)
7. [Block IDs and light sources](#7-block-ids-and-light-sources)
8. [Debug views](#8-debug-views)
9. [Tools (tools/)](#9-tools-tools)
10. [Release checklist](#10-release-checklist)
11. [Known limitations](#11-known-limitations)
12. [Version history](#12-version-history)

---

## 1. Overview

CORAL VXGI is a Minecraft Java shader pack for Iris that uses **voxel ray-traced global illumination (VXGI)**.

- **Voxel grid:** the shadow pass writes every terrain block around the player into a 3D image. GI, block-light shadow rays and reflections are traced in this grid, not on screen, so off-screen blocks still emit, occlude and reflect.
- **Ray-traced block lights (`RT_LIGHTS`):** the shadow pass also fills one global list of light blocks. Each pixel picks one light from it by resampled importance sampling (RIS) and sends a shadow ray to a point inside the light's shape.
- **Path-traced GI:** one cosine-weighted path per pixel per frame, up to `GI_BOUNCES` bounces, cleaned up by temporal accumulation and an SVGF-style a-trous filter.
- Also: ray-traced reflections with a screen-space fallback, colored sun shadows through stained glass, waves / refraction / caustics on water, volumetric clouds, TAA, nine tonemaps, LabPBR support (smoothness, F0/metal, emission, normal maps, parallax).

---

## 2. Requirements and installation

| | |
|---|---|
| Minecraft | 1.20.1 or newer (made on 1.21; unknown block names in `block.properties` are ignored) |
| Mod loader | Fabric or NeoForge (whichever Iris supports) |
| Shader mod | **Iris 1.7+** with Sodium. Iris 1.6.6 is the absolute minimum. |
| OpenGL | **4.3**. The shadow pass is `#version 430 compatibility` and writes images (image load/store); every other program is `#version 330 compatibility`. |
| GPU | NVIDIA, AMD or Intel; only standard OpenGL is used |
| Operating system | Windows or Linux. macOS is not supported (OpenGL stops at 4.1, no image load/store). |
| Not supported | OptiFine, Oculus. Distant Horizons terrain is not lit by the pack (there are no DH programs). |

Iris features used: custom images (`image.*`, `iris.features.required = CUSTOM_IMAGES PER_BUFFER_BLENDING`), per-buffer blending (`blend.<program>.<buffer>`), reversed shadow culling (`shadow.culling = reversed`) together with the `voxelDistance` constant, `renderStage`, `at_midBlock`, `mc_midTexCoord`, `at_tangent`. `BLOCK_EMISSION_ATTRIBUTE` is optional (`iris.features.optional`); it feeds `AUTO_EMITTERS`.

**Installation:** the release zip contains only the `shaders/` folder and `LICENSE.txt` and goes into `.minecraft/shaderpacks/` as-is.

### Video memory (approximate)

Computed from the `image.*` sizes in `shaders.properties` and the formats in `lib/pipeline.glsl`. The profile decides Voxel Range and shadow map resolution; the hole mask (`maskImg`) is on by default at 16x16 per block (8 words of 32 bits per voxel). Shadow maps are counted as two 32-bit depth maps plus one RGBA8 `shadowcolor0`.

| Profile | Voxel grid (cells) | voxelImg + shapeImg | maskImg | Shadow maps | Total |
|---|---|---|---|---|---|
| Low | 128x96x128 | 13 MB | 50 MB | 13 MB (1024^2) | ~0.07 GB |
| Medium (default) | 128x96x128 | 13 MB | 50 MB | 50 MB (2048^2) | ~0.1 GB |
| High | 192x128x192 | 38 MB | 151 MB | 113 MB (3072^2) | ~0.3 GB |
| Ultra | 256x128x256 | 67 MB | 268 MB | 201 MB (4096^2) | ~0.5 GB |

`CUTOUT_MASK_RES = 8` divides the mask by 4; turning `CUTOUT_SHADOW_MASK` off removes it. The light list (`lightImg`, 1024x2 RGBA16F) is 16 KB.

**Screen buffers** come on top and do not depend on the profile: 12 colortex (84 bytes per pixel, see 4.1), and Iris keeps two copies of each, so about **0.35 GB at 1080p** and **1.4 GB at 4K**, plus the bloom mip chain of colortex0, the depth buffers and Minecraft's own share. The menu's System Requirements page (`ABOUT_REQ_VRAM`) quotes these numbers.

---

## 3. Folder structure

```
shaders/
  shaders.properties     Iris settings: features, images, blending, MENU, profiles
  block.properties       block name -> ID number (edited by hand)
  dimension.properties   world0 = everything else, world-1 = Nether, world1 = End
  lang/en_us.lang        menu text, hover descriptions, value labels (the only language)
  lib/
    settings.glsl        ALL settings (#define + value list), voxelDistance, on/off registry
    pipeline.glsl        colortex formats (inside the header comment) and clear flags
    uniforms.glsl        Iris uniforms
    common.glsl          constants, MAT_* material IDs, hashes, noise, normal encoding
    space.glsl           screen / view / player transforms, depth linearization
    materials.glsl       block IDs, voxel codes, light colors, voxelEmission()
    voxel.glsl           voxel grid, DDA tracers, hole mask lookup, sampleBlockLights()
    atrous.glsl          a-trous filter pass
    shadows.glsl         shadow map distortion, PCF, colored shadows
    sky.glsl             sky, sun disc, light colors, fog, volumetric clouds
    forward.glsl         lightmap lighting for forward-rendered surfaces
    taa.glsl             Halton jitter
    debug.glsl           DBG_* view numbers and helpers
  program/               the code of each pass (section 4)
  world0/ world-1/ world1/   Overworld / Nether / End wrappers (GENERATED)
tools/                   development tools (not shipped, section 9)
docs/DOCUMENTATION.md    this document (not shipped)
```

**Wrappers:** Iris wants every program as a separate file per dimension folder. Each of the 174 files (29 programs x vertex+fragment x 3 dimensions) is a short template: `#version`, the image extension line (shadow vertex shader only), `VERTEX_SHADER`/`FRAGMENT_SHADER`, the dimension define (`OVERWORLD`, `NETHER`, `END`), program-specific defines, then `#include "/program/xxx.glsl"`. They are generated by `tools/generate_wrappers.py`; never edit them by hand.

---

## 4. Render pipeline (pass order)

The program list is the `PROGRAMS` table in `tools/generate_wrappers.py`; Iris runs the stages in its fixed order.

| # | Program | Source | What it does | Writes |
|---|---|---|---|---|
| 1 | `shadow` | `shadow.glsl` | Sun depth. Vertex shader: voxelizes terrain (5.1) and fills the light list (5.3). Fragment shader: glass color for colored shadows, hole mask bits (5.2). | shadowtex0/1, shadowcolor0, `voxelImg`, `shapeImg`, `lightImg`, `lightCountImg`, `maskImg` |
| 2 | `gbuffers_terrain/entities/block/hand` | `gbuffers_solid.glsl` | Opaque G-buffer: albedo, normal (+ normal map, POM), lightmap, material, LabPBR. End portal drawn unlit. | colortex0-2 |
| 2 | `gbuffers_basic/textured/textured_lit/weather/spidereyes/beaconbeam/armor_glint/damagedblock` | `gbuffers_forward.glsl` | Forward-lit with `lib/forward.glsl`; material `MAT_UNLIT` so the deferred passes leave them alone. | colortex0 (+2) |
| 2 | `gbuffers_skybasic/skytextured` | `gbuffers_sky.glsl` | Keeps only stars, moon (x `MOON_TEXTURE_BRIGHTNESS`) and the End sky texture; the dome is discarded, the vanilla sun too when `SUN_DISC` is on. | colortex0 |
| 2 | `gbuffers_clouds` | `clouds.glsl` | Vanilla clouds pass through (x `SKY_BRIGHTNESS`) when `CLOUD_STYLE == 1`; otherwise discard. | colortex0 |
| 3 | `deferred` | `deferred.glsl` | One GI path per pixel, including the block-light samples (5.4). | colortex3 |
| 4 | `deferred1` | `deferred1.glsl` | Temporal accumulation. | colortex4, colortex7 |
| 5 | `deferred2` | `denoise_seed.glsl` | Variance estimate. | colortex8 |
| 6-8 | `deferred3-5` | `denoise1-3.glsl` | A-trous passes, step 1, 2, 4 (a disabled pass copies). | colortex9, 8, 9 |
| 9 | `deferred6` | `lighting.glsl` | Final opaque lighting, sky pixels (sky, sun disc, clouds), deferred debug views. | colortex0, colortex6 |
| 10 | `gbuffers_water`, `gbuffers_hand_water` | `gbuffers_water.glsl` | Water, glass, ice, translucent light sources (Nether portal); forward-lit, waves. | colortex0, colortex5 |
| 11 | `composite` | `composite.glsl` | Refraction, water absorption / scattering, caustics, reflections (+ reflection history), distance and underwater fog, **volumetric clouds in front of terrain** (`applyCloudsInFront`, last step). | colortex0, colortex11 |
| 12 | `composite1` | `taa_resolve.glsl` | TAA resolve. | colortex0, colortex10 |
| 13 | `composite2` | `sharpen.glsl` | FXAA (`FXAA`, off by default) and RCAS sharpening (`SHARPEN`). | colortex0 |
| 14 | `final` | `final.glsl` | Bloom, exposure, tonemap, saturation, gamma, contrast, vignette, final debug views, dithering. | screen |

### 4.1 Texture layout (`lib/pipeline.glsl`)

| Texture | Format | Contents | Cleared |
|---|---|---|---|
| colortex0 | RGBA16F | gbuffers: albedo (sRGB) -> lit HDR scene after deferred6; mipmapped in final for bloom | yes |
| colortex1 | RGBA16 | rg normal (octahedral, player space), b block light, a sky light | yes |
| colortex2 | RGBA8 | r material (`MAT_*`), g emission ID, b smoothness, a F0 (>0.9 = metal) | yes |
| colortex3 | RGBA16F | raw 1-sample GI (+ block-light samples) | yes |
| colortex4 | RGBA16F | GI history, a = accumulated frames | **no** |
| colortex5 | RGBA16 | translucent data: rg normal, b type (0.5 glass, 1 water, 0 emitter), a sky light | yes |
| colortex6 | RGBA8 | reflection info: rgb F0, a smoothness (0 on the hand) | yes |
| colortex7 | R32F | linear depth of the previous frame | **no** |
| colortex8 / 9 | RGBA16F | a-trous ping-pong: rgb light, a variance; colortex9 is the result | yes |
| colortex10 | RGBA16F | TAA history | **no** |
| colortex11 | RGBA16F | reflection history: rgb reflection, a linear depth (`REFLECTION_DENOISE`) | **no** |

When adding a texture, add its format line to the header comment and its clear flag below it (Iris reads the format lines even inside the comment).

### 4.2 Custom images (`shaders.properties`, `image.*`)

| Image | Format / size | Purpose |
|---|---|---|
| `voxelImg` | RGBA8 3D, 128x96x128 / 192x128x192 / 256x128x256 | rgb = average block color (per-channel transmittance for glass, gray transmittance for cutout blocks), a = voxel code / 255 |
| `shapeImg` | R32UI 3D, same size | shape bit mask (bits 0-15 Y slices, 16-23 X, 24-31 Z); the atomic OR also tells the first vertex of a cell (light list ownership). Always defined. |
| `maskImg` | R32UI 3D, width x `MASK_WORDS` (8 words at res 16, 2 at res 8) | hole bits of cutout blocks; only with `CUTOUT_SHADOW_MASK` |
| `lightImg` | RGBA16F 1024x2 | light list: row 0 cell center in voxel space, row 1 linear color; only with `RT_LIGHTS` |
| `lightCountImg` | R32UI 1x1 | atomic counter of the list (keeps counting past 1024) |

All five are cleared every frame, so the grid and the list are rebuilt from scratch each frame. Only the shadow program binds images (5; the NVIDIA limit is 8, `tools/mesa_check.py` checks it); all other passes read them through samplers (`voxelSampler`, `shapeSampler`, `maskSampler`, `lightSampler`, `lightCountSampler`).

**Changing the grid size** needs these kept in sync: the `VOXEL_RANGE` list, `VOXEL_VOLUME` in `lib/voxel.glsl`, the `voxelImg` / `shapeImg` / `maskImg` lines in `shaders.properties`, and `voxelDistance` in `lib/settings.glsl` (half the width + 8 blocks).

---

## 5. Core systems

### 5.1 Voxel grid (`program/shadow.glsl`, `lib/voxel.glsl`)

- With `shadow.culling = reversed`, Iris draws every chunk within `voxelDistance` (72 / 104 / 136 blocks for Voxel Range 128 / 192 / 256) in the shadow pass. The vertex shader finds the block center (`gl_Vertex + at_midBlock / 64`), moves it to player space with `shadowModelViewInverse` and writes the cell `floor(playerPos + fract(cameraPosition)) + size/2`.
- Only render stages TERRAIN_SOLID, TERRAIN_CUTOUT and TERRAIN_CUTOUT_MIPPED are voxelized; TERRAIN_TRANSLUCENT only for light sources and (with `GLASS_TRANSMISSION`) glass, when `VOXELIZE_TRANSLUCENT_EMITTERS` is on. Entities and block entities never enter the grid.
- Skipped IDs: water, plants, lattice blocks (1003), end portal, glass without `GLASS_TRANSMISSION`, leaves without `VOXELIZE_LEAVES`, box shapes (1004) without `VOXEL_SHAPES`. Faces of ordinary (non-emitting, non-leaf) blocks whose mip-4 alpha is below 0.35 are skipped too (e.g. the grass side overlay).
- **Color:** the sprite is read at mip 4 at `mc_midTexCoord`, divided by alpha and multiplied by the vertex (biome) color. Every vertex stores; the last write wins.
- **Voxel codes** (`lib/materials.glsl`): 0 air, 1 solid, 2 leaves, 3 polished (also concrete and mineral blocks while not emitting), 4 metal, 5 transmissive (glass), 6 cutout, 11-19 fixed-color light categories 1-9 (19 = redstone lamp, its own category since 4.33), 20 texture-color light (candles), 21 concrete powder, 22-28 the seven mineral blocks, 29-43 auto-detected light level 1-15 (`AUTO_EMITTERS`, needs `at_midBlock.w`). The code is always `category + 10`.
- **Block shapes** (`VOXEL_SHAPES`): each vertex ORs the slice it lies in (Y 1/16, X and Z 1/8) into `shapeImg`. `getVoxelBox()` turns the lowest/highest bits into one bounding box per cell; an axis with a single bit (a flat quad) is widened to the whole cell. A **horizontal face also records which side of it the block is on** (4.22): for a face inside the cell (height 1/16 .. 15/16) all Y bits below a top face, or above a bottom face, are set. Without this a slab, dirt path, carpet or snow layer in a floor - which draws only its top face - left a single mark and became a full cell, so the surface the player walks on lay INSIDE the box: rays started inside the block and reached the lights behind it. The rule is not applied to a face at the very top or bottom of the cell (it would say nothing) and a mask that would collapse back to a single bit keeps the face's own bit, so a carpet stays 1/16 (measured 2/16) thick. Measured boxes: slab 0.5, dirt path 0.9375, trapdoor 0.1875, full block 1.0. `shapeEmissionBoost()` brightens small emitters when a GI ray hits them (`EMISSION_SHAPE_BOOST`, capped by `EMISSION_SHAPE_BOOST_MAX`).
- **Solid sides** (`solidImg`, 4.24): one box cannot describe a block shaped like an L. A stair is the lower half of the cell PLUS a step standing on one side of it, so its box is the whole cell and the tread lies inside it. Every face that lies INSIDE the cell therefore also writes, into a second image with the same bit layout as `shapeImg`, the whole side of that axis the block is on; the solid part of the block is the bounding box intersected with the UNION of those sides - for a stair `(y < 1/2) OR (x > 1/2)`, which is the shape exactly. Faces on the wall of the cell say nothing and are left out, and the side is rounded outward, so the stored block is never smaller than the real one. A cell with no face inside it (a full block, a chest, a fence post) has a mask of 0 and keeps its box. `solidEnterDist()` returns the distance at which a ray ENTERS that solid part; a ray that starts inside one of the sides is leaving the surface it sits on and is not stopped by it.
- **Tracers:** `traceVoxels()` is a DDA (Amanatides & Woo) that tests the start cell against the solid sides above (4.24; without them a ray from a stair tread went straight through the step next to it) and then walks cell by cell, testing partial boxes with a slab test, and passes through transmissive and cutout voxels while multiplying their color into a tint. `traceTransmittance()` is the shadow ray for block lights: in the cell the surface itself sits in only a ray that runs INTO the solid part is stopped (4.24; before that the whole box stopped every ray, so a stair tread received no block light at all), light voxels are not occluders, glass tints, cutout voxels use the hole mask (5.2) or a uniform tint without it. Both return "no hit" when the ray leaves the grid or runs out of steps.
- `voxelVolumeFade()` is 1 inside the grid and fades to 0 over the outer quarter; outside, GI falls back to sky ambient x sky lightmap.

### 5.2 Hole mask (`CUTOUT_SHADOW_MASK`)

Cutout voxels (code 6) are created for box-shaped blocks (ID 1004, e.g. trapdoors, doors) whose mip-4 alpha is below 0.95, when `TRANSMISSION_FROM_ALPHA` is on; their stored transmittance is `1 - alpha` (at most 0.85). With the mask on, the **shadow fragment shader** marks every texel with alpha < 0.5 of an ID 1004 block in a `CUTOUT_MASK_RES`^2 grid on the face plane (the two axes other than the face normal). `cutoutHoleAt()` reads the bit where a block-light shadow ray crosses the middle plane of the box. Only holes are marked: a cell with no marked bits counts as solid. The mask is used only by `traceTransmittance()`; GI and reflection rays see cutout voxels as a uniform gray tint.

### 5.3 Ray-traced block lights (`sampleBlockLights`, `lib/voxel.glsl`)

- **List:** in the shadow vertex shader, the first vertex that touches a light cell (`imageAtomicOr` on `shapeImg` returned 0) does `imageAtomicAdd` on `lightCountImg` and stores position and `voxelEmission()` color at that index if it is below `MAX_RT_LIGHTS` (1024, must equal the `lightImg` width). There is **one global list** for the whole grid, filled in the order the GPU processes the shadow-pass vertices. Entries beyond 1024 are dropped silently (see section 11).
- **RIS:** `RT_LIGHT_SAMPLES` candidates are drawn **uniformly** from the whole list (golden-ratio stratified index). Candidates farther than `RT_LIGHT_RANGE` or behind the surface get weight 0. Target = luminance(color) x N.L x falloff, with falloff `1 / (1 + d^2 x RT_LIGHT_FALLOFF)` and a soft cutoff over the last 45 % of the range. Weight = target x list length; one candidate is kept in proportion to its weight; the result is `color / luminance(color) x visibility x weightSum / candidates x RT_LIGHT_STRENGTH`.
- **Soft shadows:** the sample point is jittered inside the light's measured box (x `RT_LIGHT_SIZE`; 0 = no jitter), so a torch casts a sharp shadow and glowstone a soft one, and is then moved onto the box FACE that the shaded surface sees - skipping faces whose neighbouring cell is occupied, because the side faces of a block in the middle of a glowstone ceiling are covered by its neighbours. Aiming at a point inside the emitter made the last stretch of the ray run inside a ceiling or lake of light blocks, where its neighbours shadowed it. The step budget is `1.8 x length + 3`, at most 256.
- **Occluders (`traceTransmittance`, `shadowCellBlocks`):** every cell is tested with its box, so a ray can miss a partial shape. Two rules were fixed in 4.21:
  - **A light block is a solid block.** Only the cell of the source being sampled (and anything within a block of it, so a lava lake or a lamp cluster does not shadow itself) lets the ray pass. Before, EVERY emissive voxel was skipped, which turned a glowstone ceiling or wall into a window: its light reached everything behind it, and since Minecraft never draws the blocks buried inside a solid mass (no visible face, so nothing about them reaches the grid) that light then spread through the whole mass and came out of the surfaces above it.
  - **The cell the surface itself sits in is tested.** The DDA starts at the next cell boundary, so it skipped that cell. On a partial block (slab, path, carpet, trapdoor, stairs) the visible surface lies inside its own cell, so the block did not shield its own surface. It is now tested for rays that ENTER the box (`tEnter > 0.002`); a ray leaving the face it starts on is unaffected.
- **Where it is called:** at the pixel (deferred), at the first GI bounce hit (deferred), and at reflection hits (composite, `REFLECTION_BLOCK_LIGHT`). The pixel and bounce samples are part of the GI radiance in colortex3, so they are temporally accumulated, denoised, scaled by `GI_STRENGTH` and `GI_SATURATION`, and limited by `GI_FIREFLY_CLAMP` like the rest of GI. Because the sampling sits inside `#ifdef GI_ENABLED` in `deferred.glsl`, turning GI off also removes ray-traced block light from visible surfaces.
- GI rays that hit an emissive voxel add its emission as well (`shadeVoxelHit`); there is no exclusion or MIS between the two, so listed lights reach a surface through both terms.
- Vanilla block light is kept as a base: inside the grid it is scaled by `LIGHTMAP_RT_BLEND`, which is **0.0** by default, so inside the ray traced area block light is ray traced only.

- **Cluster limit** (`RT_LIGHT_SOFT_CAP`, 4.29): the RIS sum (the unshadowed contribution of every source in range) is bent over with `sum * inversesqrt(1 + (sum/cap)^2)`, default cap 3.0, 0 disables it. Lamps add up linearly, so measured on a floor 4 blocks below: one glowstone 0.259, 3x3 2.02, 9x9 8.85, 21x21 15.00 (58x one block). After the limit: 0.258 / 1.96 / 6.10 / 6.32, a torch at 5 and 20 blocks unchanged at 0.0189 and 0.0003, a lava lake from above 26.7 -> 8.2.
### 5.4 GI path tracing (`program/deferred.glsl`)

1. Skipped for sky, `MAT_UNLIT` and `MAT_HAND` pixels.
2. Block light is sampled at the surface (5.3).
3. A cosine-weighted ray is traced with `GI_MAX_STEPS` / `GI_MAX_DISTANCE`. At a hit, `shadeVoxelHit()` adds sun bounce (single shadow-map tap, x `GI_SUN_BOUNCE`, Overworld only), sky ambient (`GI_HIT_AMBIENT` on the last bounce only, + a small constant) and emission. Throughput is multiplied by the hit albedo (and by any glass passed); the path stops below 0.015.
4. On the first bounce, block light is sampled at the hit point. Each later bounce halves the steps (minimum 8) and the distance.
5. A miss (sky, out of steps, or out of the grid) adds `getSkyRadiance()` x `GI_SKY_STRENGTH` x the pixel's sky exposure.
6. The total radiance is clamped to luminance `GI_FIREFLY_CLAMP`, then blended with the sky-ambient fallback by `voxelVolumeFade()`.

Leak prevention (`LEAK_FIX`): sun terms use `smoothstep(0, 0.35, skyLight)`, sky terms `skyLight^2`, taken from the pixel's vanilla sky lightmap. Random numbers are PCG3D of `(pixel.x, pixel.y, frameCounter)`; `DEBUG_FREEZE_NOISE` sets the frame to 0.

- **No double counting of emitters** (4.31): `shadeVoxelHit()` takes an `emissionScale`; `deferred.glsl` passes 0 on bounce 0 when `RT_LIGHTS` is on, the hit is within `RT_LIGHT_RANGE` of the shaded point and the light list did not overflow (`lightCountSampler > MAX_RT_LIGHTS`). NEE already paid for those sources, and the second helping was multiplied by `shapeEmissionBoost` (up to `EMISSION_SHAPE_BOOST_MAX` = 6) for small emitters. Measured on a wall 1 block from a torch: direct 0.434, duplicate indirect 1.387 -> 0.060; totals 1 block away torch 1.82 -> 0.49, glowstone 1.65 -> 0.62, lava 3.22 -> 1.13; at 8 blocks all three are unchanged. Reflections and later bounces keep the emission (no shadow ray is sent from there).
### 5.5 Temporal accumulation and denoising

- `deferred1`, **spike removal** (`GI_SPIKE_FILTER`, `GI_SPIKE_TOLERANCE`, 4.24, reworked in 4.25): AFTER the blend, the accumulated value's luminance is compared with the 8 neighbors of the history (colortex4) and clamped to `max(mean + GI_SPIKE_TOLERANCE x deviation + 0.02, luminance(own history))`. One ray per pixel means a ray that reaches a light through a gap leaves a point tens of times brighter than its surroundings, which the a-trous filter keeps because it reads as a luminance edge; dark rooms then fill with star-like dots. 4.24 did this on the RAW frame, which is wrong: where only a fraction p of the rays find any light, nearly all the light is in those few samples. Simulated over 300 frames (true value T, hit probability p, unbiased sample T/p, 24 accumulation frames), light kept: raw 0.50 at p=0.1 and 0.20 at p=0.03, accumulated 0.98 and 0.74, with a lower peak pixel in both cases. The floor at the pixel's own history keeps surfaces that are simply brighter than their surroundings from being pulled down.
- `deferred1`: reprojects with the previous camera matrices and reads the history bilinearly, testing each of the 4 taps against colortex7 (tolerance `expectedDepth x GI_TEMPORAL_DEPTH_TOLERANCE + 0.08`). Blend weight `1/frames`, frames capped at `GI_TEMPORAL_FRAMES`. NaN/Inf history is reset.
- `deferred2`: variance = 3x3 luminance variance of the accumulated GI divided by the frame count.
- `deferred3-5` (need both `GI_DENOISE` and `DENOISER_ATROUS`; `ATROUS_PASSES` 1-3): 5x5 B-spline kernel at step 1, 2, 4. Weights: `N.N'^ATROUS_NORMAL_WEIGHT`, `exp(-|dz| / (ATROUS_DEPTH_WEIGHT x step))` on linear depth, `exp(-|dLuma| / (ATROUS_LUMA_WEIGHT x sqrt(blurred variance)))`. Variance is propagated with squared weights. A disabled pass copies its input, so the result is always in colortex9.
- `deferred6`: reads colortex9. With `DENOISER_ATROUS` off, `denoiseGI()` runs the older single-pass Poisson filter on colortex4 (`GI_DENOISE`, `GI_DENOISE_SAMPLES`, radius from `GI_DENOISE_RADIUS` down to `GI_DENOISE_MIN_RADIUS` as history fills, normal and plane-distance weights). Then `GI_SATURATION` pushes the GI away from gray (clamped at 0).

### 5.6 Final lighting (`program/lighting.glsl`)

```
color = albedo x (1 - metalness) x (direct + indirect x GI_STRENGTH + blockLight + handLight + minLight)
      + sunSpecular + emission x EMISSION_SURFACE
```

- **Direct:** Overworld only. PCF shadow (5.8), `FOLIAGE_TRANSLUCENCY` wraps light on plants and leaves, `LEAK_FIX` removes sun where the sky lightmap is 0. The hand estimates its shadow from the lightmap.
- **Sun specular** (`SUN_SPECULAR`): GGX with Schlick Fresnel for smoothness > 0.05.
- **Block light:** `BLOCKLIGHT_COLOR x lightmap^BLOCKLIGHT_CURVE x 1.8 x BLOCKLIGHT_STRENGTH`, scaled by `LIGHTMAP_RT_BLEND` (0.0 by default) inside the grid. **Hand light** (`HAND_LIGHT`): held light level with an inverse-square falloff (`HAND_LIGHT_RANGE`).
- **Emission:** LabPBR (ID >= `LABPBR_EMISSION_BASE` = 24, strength `(id - 24) / 231`), concrete powder and minerals (categories 11-18, `mineralSurfaceEmission` with the per-block gain from the albedo alpha), texture color (category 10, `tintedEmission`), fixed categories 1-9 (albedo x category luminance x bright-texel mask). The sum is scaled by `EMISSION_SURFACE`.
- **Metals:** with `RT_REFLECTIONS` and `BLOCK_REFLECTIONS` the diffuse term of metals is 0; their color comes from the reflection in composite.
- Sky pixels get `getFullSky()`: sky gradient + sun disc + stars/moon from gbuffers_sky + volumetric clouds.

### 5.7 Materials (`program/gbuffers_solid.glsl`)

- Material from the block ID: plants (normal forced up), leaves, emissive categories, polished / concrete / minerals (`POLISHED_SMOOTHNESS`, F0 0.04), metal (`METAL_SMOOTHNESS`, F0 1.0). For an emissive mineral block or concrete powder the pass also computes the **surface gain** (`mineralSurfaceGain` from the mip-4 sprite average at `mc_midTexCoord`) and writes it into the terrain albedo alpha, which is why `blend.gbuffers_terrain.colortex0` is off and the damaged-block blend keeps the alpha. `LABPBR` overrides smoothness/F0 from `_s` red/green; `LABPBR_EMISSION` reads `_s` alpha (255 = none) into emission IDs 24-255.
- **Normal maps** (`MATERIAL_NORMALS`, ported from 4.18, default `NORMAL_STRENGTH` 4.0): the `_n` rg normal is used only if its slope is between 0.004 and 0.999 (Iris's flat default texture is rejected), scaled by `NORMAL_STRENGTH`, and only if the result faces the same side as the geometric normal. A missing tangent (`tbnValid`) disables it.
- **Parallax** (`MATERIAL_POM`, ported fix): `POM_STEPS` march steps (default 32) through `_n` alpha within `POM_DISTANCE`, optional `POM_SMOOTH` interpolation. `wrapInSprite()` **clamps** the coordinate to the sprite instead of wrapping it with `mod()` (no repeated copies), and the total shift `0.12 x POM_DEPTH x tan(angle)` (atlas UV) is limited to **0.9 x the smaller sprite half size**. With typical atlas sizes that limit is reached a few degrees away from the normal, so the displacement is mostly the clamped length. There is no depth offset and no self-shadowing.

- **Parallax** (`MATERIAL_POM`, 4.27): the shift is `(tv.xy / max(tv.z, 0.25)) x POM_DEPTH x 0.25 x spriteSize`, i.e. measured in SPRITES. Before 4.27 the sprite size was missing and the constant was 0.12 in atlas units, which for a 16 px sprite in a 512 px atlas is 3.8 sprites; the `0.9 x spriteHalf` cap then flattened every direction to the same maximum from 6.7 degrees off the normal onward, which read on screen as a lens centered on the view direction and made `POM_DEPTH` do nothing. The cap is now one sprite (reached at 76 degrees), `wrapInSprite()` wraps with `mod` instead of clamping (block textures tile), the march keeps an unwrapped offset so `POM_SMOOTH` never interpolates across a border, and every sprite read (`gtexture`, `normals`, `specular`) uses `textureGrad` with the derivatives of the ORIGINAL coordinate so a wrap cannot force the blurriest mip. `POM_DISTANCE` fades over its last 30 % instead of cutting off.
### 5.8 Shadows (`lib/shadows.glsl`)

Distortion `clip.xy / (|clip.xy| x SHADOW_DISTORTION + 1 - SHADOW_DISTORTION)`, shared by the shadow pass and all readers. `shadowFiltered()`: normal offset of one texel x (`SHADOW_BIAS` + more at grazing angles), `SHADOW_SAMPLES` Poisson taps (12-point disk reused with rotation) rotated per pixel by interleaved gradient noise, radius `SHADOW_SOFTNESS`, fade at the end of the distance (`SHADOW_EDGE_FADE`). **Colored shadows** (`COLORED_SHADOWS`): where shadowtex1 is lit but shadowtex0 is not, the occluder is translucent and `shadowcolor0` (written without blending, a = translucent flag) tints the light by `SHADOW_TINT_BRIGHTNESS`. `shadowSingle()` is the one-tap version used at ray hits and on forward surfaces.

### 5.9 Reflections (`program/composite.glsl`, ported from 4.18)

- **`REFLECTION_MODE`** is the only reflection option in the menu: 0 off, 1 screen space only, 2 voxel ray tracing + screen fallback. The end of `lib/settings.glsl` turns it into the internal switches `RT_REFLECTIONS` and `SSR_FALLBACK`, which the code reads.
- `traceReflection()`: (1) voxel ray (`REFLECTION_STEPS`, `REFLECTION_MAX_DISTANCE`); if the hit is on screen and not covered (`REFLECTION_SCREEN_LOOKUP`) the textured pixel is used, otherwise the flat voxel color is lit with `shadeVoxelHit` plus a block-light sample (`REFLECTION_BLOCK_LIGHT`); (2) screen-space march with binary refinement (`SSR_FALLBACK`, `SSR_MAX_STEPS`, `SSR_THICKNESS`); (3) sky with clouds.
- **Water and glass:** Schlick Fresnel on F0 0.02 (water, not while underwater) and 0.04 (glass, x `GLASS_REFLECTION_STRENGTH`).
- **Opaque surfaces** above `REFLECTION_MIN_SMOOTHNESS`: the Fresnel term is capped by roughness (`max(1 - roughness, F0)`), so a rough surface seen at a grazing angle no longer turns into a mirror. The normal is jittered by `ROUGH_REFLECTION_JITTER x roughness` with a seed that **changes every frame**, and the reflection REPLACES the surface color by its weight instead of being added (energy conserving).
- **Reflection denoiser** (`REFLECTION_DENOISE`, off by default, on the Denoiser page): the reflection of the previous frame is reprojected from the surface position out of `colortex11` and blended in with `1 / REFLECTION_TEMPORAL_FRAMES`, scaled by roughness so mirror-smooth surfaces are never averaged. History is thrown away when the reprojected depth differs by more than `REFLECTION_DENOISE_TOLERANCE`. The history is written even when the denoiser is off.
- **Refraction** (`WATER_REFRACTION`, `GLASS_REFRACTION`): the offset uses a fixed assumed thickness (`WATER_REFRACTION_DEPTH`, `GLASS_REFRACTION_DEPTH`) faded out as the surface is viewed head-on, never the real distance to whatever is behind it - that turned water and glass into a magnifying lens.

- **Modes** (4.26): `REFLECTION_MODE` 1 (screen space) and 2 (ray traced) both call `traceReflection()`; the voxel step inside it is compiled only for mode 2 (`RT_REFLECTIONS`), the screen-space march only for modes 1 and 2 (`SSR_FALLBACK`). Before 4.26 the call sites themselves required `RT_REFLECTIONS`, so mode 1 produced no reflection at all on blocks and only the sky on water, while the voxel step ran unconditionally inside the function.
- **Miss handling** (4.26): `traceReflection()` reports whether it found anything. On a miss the opaque reflection weight is multiplied by `skyExposureFromLightmap(lmSky)`, so indoors, where the sky fallback is black, a polished or metal block keeps its own color instead of being painted black.
- **Rough reflections and flicker** (4.28): each frame the normal is jittered by `ROUGH_REFLECTION_JITTER x roughness` so a rough surface gathers a blurred reflection over time. `REFLECTION_DENOISE` is now ON by default and the accumulation ramp is `saturate(roughness x 16)` (was x 8), so the frame-to-frame difference drops from 0.0097 to 0.0033 on polished and mineral blocks (smoothness 0.82) and from 0.0235 to 0.0059 on metal (0.72). With the denoiser off, that difference is shown directly and reads as shimmer.
- **Light on a reflected block** (4.28): `shadeVoxelHit()` is called from the reflection with `ambientScale = 1.0` instead of `GI_HIT_AMBIENT` (0.15). GI_HIT_AMBIENT belongs to the last bounce of a GI ray, where the surface already carries the light of every bounce before it; a reflection has no history, so that was all the light the reflected block ever got. A white surface in open shade, direct view counted as 1.00, came out 0.11 in a reflection and now comes out 0.62.
- **Metal and the miss fade** (4.28): the 4.26 fade is skipped when `colortex2.a > 0.9` (LabPBR metal). `lighting.glsl` removes a metal's diffuse color (`metalness`), so fading its reflection away left black.
- **Reflection normal** (`REFLECTION_NORMAL_STRENGTH`, 4.29): the geometric normal is reconstructed once per pixel in uniform control flow as `cross(dFdx(viewPos), dFdy(viewPos))` (exact on block faces) and the reflection ray uses `mix(geoNormal, N, REFLECTION_NORMAL_STRENGTH)`, default 0.25, only where `dot(geoNormal, N) > 0.25`. With `NORMAL_STRENGTH` 4.0 a single texel's normal tilts by tens of degrees and a mirror doubles it, which tore reflected geometry apart. Lighting still uses the full mapped normal.
- **Stable rays without the denoiser** (4.30): the per-frame jitter seed is `frameCounter * 747796405 + 7` only while `REFLECTION_DENOISE` is defined; with the denoiser off the seed is a constant, so a pixel keeps the same ray every frame and detailed normal maps stop flickering.
- **Specular AA** (`SPECULAR_AA`, `SPECULAR_AA_MAX`, 4.30): `normalVariance = 0.5 (|dNdx|^2 + |dNdy|^2)` of the shading normal, measured once in uniform control flow, widens the GGX alpha in `lighting.glsl` and the reflection roughness in `composite.glsl` by `min(2 x variance, SPECULAR_AA_MAX)`.
- **Sharpening** (`REFLECTION_SHARPEN`, `REFLECTION_SHARPEN_STRENGTH`, 4.30): after the temporal blend, `reflection + (reflection - average of 4 history neighbours) x strength`, applied to the output only; colortex11 keeps the unsharpened value so the effect cannot accumulate.
- **Frame-stable reflections** (4.31): the `REFLECTION_BLOCK_LIGHT` sample inside `traceReflection()` uses a constant seed when `REFLECTION_DENOISE` is off, like the ray jitter since 4.30. A per-frame seed without anything averaging it is shown to the viewer directly and reads as twinkling on polished and metal blocks.
### 5.10 Water and translucents

- `gbuffers_water.glsl`: forward-lit with `lib/forward.glsl` (lightmap + one shadow tap), no GI and no ray-traced block light. Water top faces get a wave normal (three scrolling value-noise layers + one sine, `WATER_WAVE_*`); the water color is `biome tint x 0.06 x light` with alpha `WATER_SURFACE_OPACITY`. Translucent emitters (Nether portal) write their own glow and translucent type 0 so they are not reflected.
- `composite.glsl`: refraction (`WATER_REFRACTION`, `GLASS_REFRACTION`, offset clamped, only background pixels used), absorption `exp(-(0.45, 0.14, 0.10) x WATER_ABSORPTION x thickness)` plus in-scattered water color (`WATER_SCATTER`), caustics from two scrolling noise layers (`CAUSTICS_*`, also on all surfaces while underwater), underwater fog with the biome water color (`UNDERWATER_FOG_DENSITY`, `UNDERWATER_BIOME_TINT`), lava and powder snow fog, blindness.

### 5.11 Sky, fog and clouds (`lib/sky.glsl`, `program/clouds.glsl`)

- Sky: zenith/horizon gradient, sunset band (`SUNSET_STRENGTH`), sun aureole, moon glow, rain desaturation; analytic sun disc (`SUN_DISC_*`). Nether and End use fixed colors (`NETHER_AMBIENT` from the fog color, `END_AMBIENT`).
- **Sun aureole (ported from 4.18), `SUN_GLOW`:** the forward-scattered glow around the sun is computed from the angle to it, `ang = sqrt(2 * (1 - mu))` (the small-angle form of `acos`), as `exp(-ang * 55) * 0.55 + exp(-ang * 7) * 0.045` scaled by `SUN_GLOW` (default 2.0). Half-width 0.79 degrees instead of the 7.3 degrees of the old `pow(mu, 10) * 0.35 + pow(mu, 120) * 1.2`, which reached 1.55 over a huge area, tonemapped to near white and made the sun look enormous. The disc edge fades over `radius x 1.06` instead of `x 1.3`, so `SUN_DISC_SIZE` matches the size on screen; defaults `SUN_DISC_SIZE` 0.5 and `SUN_DISC_BRIGHTNESS` 8.0 (`SUN_DISC_SIZE` 0.25 is about the real sun).
- **Sky light in shade** (`SKY_LIGHT_CURVE`, 4.25): `skyExposureFromLightmap()` returns `pow(lmSky, SKY_LIGHT_CURVE)`, default 0.8 since 4.26 (it was `lmSky x lmSky`), and `GI_SKY_STRENGTH` defaults to 1.25 instead of 0.65. Both multiply every path that carries sky light: the GI ray that escapes (`getSkyRadiance x GI_SKY_STRENGTH x skyExposure`), the ambient term of `shadeVoxelHit()` and the fallback outside the voxel volume. Measured with the real functions at a high sun, light on a white floor with the sun straight on it as 1.00: open shadow 0.078 -> 0.121 -> 0.151 (4.24 -> 4.25 -> 4.26), roof 2 blocks in 0.033 -> 0.058 -> 0.074, roof 5 blocks in 0.012 -> 0.028 -> 0.038, room with a window 0.007 -> 0.018 -> 0.025; a sunlit surface changes by 7 % in total. `sunExposureFromLightmap()` (`smoothstep(0, 0.35, lmSky)`, the sun bounce) is unchanged, and lmSky = 0 still gives 0, so caves stay dark.
- Fog (composite): exponential height fog in the Overworld (`FOG_DENSITY`, thicker in rain), per-dimension fog elsewhere, border fog from `BORDER_FOG_START x far`.
- **Clouds (ported from 4.18), `CLOUD_STYLE`:** 0 off, 1 vanilla, 2 volumetric (default). `shaders.properties` sets `clouds = off` unless `CLOUD_STYLE == 1`; `clouds.glsl` (as `gbuffers_clouds`) discards unless the style is vanilla.
- **Volumetric march** (Overworld only): the view ray is intersected with the layer `CLOUD_HEIGHT .. + CLOUD_THICKNESS` from above or below, limited by `CLOUD_MAX_DISTANCE` and the surface distance; `CLOUD_STEPS` steps with a per-pixel offset. Density: 5-octave value-noise fbm (`CLOUD_SCALE`, `CLOUD_SPEED`), eroded by a detail fbm (`CLOUD_DETAIL`, `CLOUD_DETAIL_SCALE`), height profile, coverage threshold from `CLOUD_AMOUNT` (lowered by rain), x `CLOUD_DENSITY`. Lighting: `CLOUD_LIGHT_STEPS` samples toward the sun, Beer-Lambert with `CLOUD_ABSORPTION`, `CLOUD_MULTISCATTER`, sky ambient x `CLOUD_AMBIENT`, sun x `CLOUD_BRIGHTNESS`.
- Clouds are drawn on sky pixels in deferred6, in water/glass/metal reflections of the sky, and in front of terrain by `applyCloudsInFront()` at the end of composite (not on the hand and not while underwater). The Clouds page is `CLOUDS_PAGE` under Sky & Fog.

### 5.12 Post-processing (`program/final.glsl`)

- **Bloom:** weighted average of colortex0 mip levels 2-7 (`colortex0MipmapEnabled`), `mix(color, bloom, BLOOM_STRENGTH) + bloom x BLOOM_STRENGTH x 0.5`.
- **Exposure:** `EXPOSURE`; with `AUTO_EXPOSURE` in the Overworld x `CAVE_EXPOSURE` by low eye sky light (`eyeBrightnessSmooth`) and x `NIGHT_EXPOSURE` at night outdoors; x 1.6 in the Nether and End. There is no image metering.
- **Tonemaps (ported from 4.18), `TONEMAP`:** 0 ACES (default), 1 Reinhard, 2 Hable (Uncharted 2), 3 None (clamp), 4 AgX, 5 Lottes, 6 Soft filmic, 7 Reinhard-Jodie, 8 Uchimura (GT). Then `SATURATION`, gamma 2.2, `CONTRAST`, `VIGNETTE_STRENGTH`, `DITHERING`.

- **Auto exposure** (4.29): the cave boost is `mix(mix(CAVE_EXPOSURE, 1.0, eyeSky), 1.0, lit)` with `lit = smoothstep(0.35, 0.9, eyeBrightnessSmooth.x / 240)`, and the night boost carries `(1 - lit)`. Before, only the sky lightmap was read, so a hall lit by a glowstone ceiling counted as a cave and was multiplied by up to 2.6 on top of an already bright image.
- **Highlight washout** (`HIGHLIGHT_DESAT`, 4.30): before the tonemap, a color whose brightest channel exceeds 1.0 is mixed towards `vec3(peak)` by `(1 - 1/peak) x HIGHLIGHT_DESAT`. Per-channel tonemapping keeps a saturated over-range color (a wall of redstone blocks) at full, flat saturation; this is the film-like washout instead. Nothing below 1.0 changes.
### 5.13 TAA (`lib/taa.glsl`, `program/taa_resolve.glsl`)

gbuffers vertex shaders add a Halton(2,3) sub-pixel jitter (`TAA_JITTER_PATTERN` frames, `TAA_JITTER_SCALE`); the shadow pass is not jittered. The resolve reprojects with the camera matrices, clamps the history to the 3x3 neighborhood range in a luminance-compressed space, lowers the weight by the clamp distance (`TAA_CLAMP_SENSITIVITY`) and near the screen edge, and blends with `TAA_STRENGTH`.

### 5.14 FXAA and sharpening (`program/sharpen.glsl`, composite2, ported from 4.18)

- **FXAA** (`FXAA`, off by default): classic single-frame edge smoothing on colortex0 - the luminance of the four diagonal neighbors gives the edge direction, and the pixel is blended along it by `FXAA_STRENGTH`. It works with or without TAA.
- **RCAS** (`SHARPEN`, on by default): the sharpening stage of AMD FSR (there is no FSR upscaling; the pack always renders at full resolution). The gain of the cross-shaped kernel is limited by the local contrast, so it creates no halos and does not amplify noise. `SHARPEN_STRENGTH` scales it.

**This pass is on the HDR path.** composite2 runs *before* `final.glsl`, so colortex0 is still linear HDR here: a sunlit white block is ~2.6 and the sun disc is `SUN_DISC_BRIGHTNESS` (8.0). Three things follow, and all three were wrong until 4.34:

1. The RCAS resolve is `(center + lobe * (up+down+left+right)) / (1 + 4*lobe)` with a **negative** lobe weight. Here the lobe is `-gain`, so the divisor must be `1 - 4*gain`. It was written `1 - 4*(-gain)`, i.e. `1 + 4*gain`, which makes the filter's DC gain `(1-4g)/(1+4g)` instead of 1. Measured on a flat patch at the default strength: **0.619x**; at strength 1.0, 0.111x. A flat patch is the regression test - it must come out at exactly 1.000x at every brightness, HDR included (`sharpen_test.py`).
2. The contrast limiter must be **scale-invariant**. It used `min(mn, 1.0 - mx)`, which assumes 1.0 is the peak; above 1.0 that term goes negative, the gain collapses to 0 and nothing bright is sharpened at all. It is now the local dark-to-bright ratio `sqrt(mn/mx)`, which behaves the same whether the neighborhood sits at 0.2 or at 20.
3. The result must **not** be clamped to 1.0. It was, and since `final.glsl` reads this same buffer for bloom, exposure and tonemapping, everything above white arrived as exactly white - a lit sheep, a glowstone, a lava lake and the sun all landed on 0.804 on screen. Only `max(color, 0.0)` is applied, which is what the bloom mip chain needs (no negatives).

A third limiter was added in 4.34: `gain <= center / sum(neighbors)`, so the numerator cannot go negative and a single dark pixel among bright ones is no longer pushed past black and clipped.

---

## 6. Settings system

### 6.1 `lib/settings.glsl`

- **Numeric:** `#define NAME value // [list] description`. The list uses single spaces, the default must be in it, and no `[` may appear before the list. Fractional values cannot be tested in `#if`.
- **On/off:** `#define NAME // description` or `//#define NAME`. Iris shows it only if it sees `#ifdef NAME` somewhere, so every switch is also listed in the **ON/OFF SETTING REGISTRY** at the end of the file.
- **Iris constants:** `shadowMapResolution`, `shadowDistance`, `sunPathRotation` (with value lists), `shadowDistanceRenderMul`, and `voxelDistance`, which follows `VOXEL_RANGE`.
- **Dummy settings:** `ABOUT_*` (About, Changelog and System Requirements pages) and `DEBUG_HELP_*` are `// [0]` options that only show text; their `value.NAME.0=` label is empty.

### 6.2 `shaders.properties`

- `screen = [ABOUT] <profile> [RAY_TRACING] ...` with `screen.columns = 2`, so About and the profile button sit side by side at the top. `[PAGE]` links a sub-page `screen.PAGE`, `<empty>` is a blank cell. `sliders = ...` lists the numeric settings drawn as sliders.
- Pages: About (-> System Requirements, Changelog), Ray Tracing, Denoiser, Emissive Block Colors, Coloured Light, Reflections, Lighting (-> Block Light Color), Shadows, Sky & Fog (-> Clouds), Water, Materials, Post Processing, Anti-Aliasing & Sharpening, Debug.
- **Profiles** `profile.A_LOW`, `B0_MEDIUM`, `C1_HIGH`, `C5_ULTRA`: the key names make Iris sort them Low, Medium, High, Ultra (display names come from the lang file). **Every profile sets the same 13 settings.** Medium equals the defaults in `settings.glsl`.

| Setting | Low | Medium | High | Ultra |
|---|---|---|---|---|
| RT_LIGHT_SAMPLES | 4 | 8 | 8 | 8 |
| GI_BOUNCES | 1 | 2 | 2 | 3 |
| GI_MAX_STEPS | 24 | 48 | 64 | 96 |
| REFLECTION_STEPS | 48 | 96 | 128 | 192 |
| REFLECTION_MAX_DISTANCE | 64 | 128 | 256 | 384 |
| shadowMapResolution | 1024 | 2048 | 3072 | 4096 |
| VOXEL_RANGE | 128 | 128 | 192 | 256 |
| SHADOW_SAMPLES | 4 | 12 | 12 | 12 |
| VOXEL_SHAPES | on | on | on | on |
| MATERIAL_NORMALS | off | off | on | on |
| MATERIAL_POM | off | off | off | on |
| POM_STEPS | 32 | 32 | 32 | 64 |
| CLOUD_MAX_DISTANCE | 5000 | 5000 | 10000 | 10000 |

Write `NAME=value` for numbers and `NAME` / `!NAME` for switches. The mixed form `!NAME=value` is silently ignored by Iris; `check_consistency.py` rejects it. A setting missing from one profile would keep its old value when switching to that profile.

### 6.3 `lang/en_us.lang`

- `option.NAME` is the label, `option.NAME.comment` the hover text (every ". " starts a new line). Both are required; the comment must be at least 40 characters. `screen.PAGE` / `.comment` name pages, `profile.X` names profiles.
- Labels must be distinguishable (ignoring color codes, parentheses and case), and one numeric label may not be the start or end of another.
- `value.NAME.VALUE` labels are written by hand (there is no generator in this code base).
- Color codes are the section sign plus a letter, e.g. `§e` yellow, `§a` green, `§c` red, `§6` gold, `§r` reset. The lang file may contain such non-ASCII characters (it also has a degree sign in `suffix.sunPathRotation`); shader sources may not.

---

## 7. Block IDs and light sources

`block.properties` (edited by hand) maps block names (with optional states, e.g. `furnace:lit=true`, and `namespace:block` for mods) to IDs. The `ID_*` constants in `lib/materials.glsl` must match.

| ID | Group | In the voxel grid |
|---|---|---|
| 1000 | Water, bubble column | no |
| 1001 | Glass, panes, ice, slime, honey | only with `GLASS_TRANSMISSION` (tinting voxel) |
| 1002 | Plants, crops, vines | no; normal forced up, lit like the ground |
| 1003 | Fences, gates, iron bars, chains, cobweb, banners, copper grates, scaffolding, dripstone... | **never** |
| 1004 | Doors, trapdoors, rails, carpets, unlit candles, heads, anvils, signs... | only with `VOXEL_SHAPES`; cutout path with `TRANSMISSION_FROM_ALPHA` |
| 2000 | Leaves | with `VOXELIZE_LEAVES` |
| 2001 / 2002 | Polished / metal blocks | yes (reflective codes 3 / 4) |
| 2100 | Concrete powder | light source when `EMIT_CONCRETE_POWDER` is on (`EMIT_CUSTOM_I`, texture color, balanced like the minerals); otherwise a normal block |
| 2101 / 2102 | Concrete / wool | never emit: concrete is polished (reflective), wool is matte |
| 2103-2109 | Mineral blocks: redstone, lapis, emerald, diamond, amethyst, coal, raw copper | light sources when `EMIT_MINERAL_BLOCKS` is on, each with its own `EMIT_MINERAL_*_I`; otherwise polished |
| 3000-3007 | Light categories: fire, soul, lamp (glowstone, shroomlight, froglight, copper bulb), lava, redstone, cool, purple (incl. Nether portal), green | yes, `EMIT_<CATEGORY>_R/G/B/I` |
| 3008 | Lit redstone lamp - its own category since 4.33, so it can be set apart from glowstone | yes, `EMIT_RLAMP_R/G/B/I` |
| 3009 | Lit colored candles and candle cakes | yes, texture color (`EMIT_TINTED_I`, `EMIT_TINTED_SAT`) |
| 4000 | End portal (block entity) | no; drawn procedurally, unlit |

Blocks not listed are voxelized as solid (shape measured with `VOXEL_SHAPES`). Blocks outside the light categories that report a light level (e.g. modded lamps) become light sources (codes 29-43, color from the texture) when `AUTO_EMITTERS` is on and Iris provides `BLOCK_EMISSION_ATTRIBUTE`.

**Adding a light category.** IDs 3000-3009 and categories 1-18 are all taken, and the layout is used in several places: `emissionCategoryOf()`, `emissionColor()` and `voxelEmission()` (materials.glsl), `code = 11 + category - 1` and the auto-emitter codes `(VOXEL_AUTO_FIRST - 1) + level` (shadow.glsl), the category branches in `lighting.glsl` and `gbuffers_water.glsl`, `debugVoxelTypeColor()` (debug.glsl) and the emission-ID view (final.glsl). A new category therefore needs: a `block.30xx` line and `ID_EMIT_LAST`; `EMIT_NEW_R/G/B/I` in settings.glsl, the lang file, `screen.EMISSION_COLORS` and `sliders`; and new, non-overlapping voxel codes (move `ID_EMIT_TINTED`, `TINTED_CATEGORY`, `CUSTOM_CATEGORY`, the mineral categories, `VOXEL_TINTED`, `VOXEL_TINTED_CUSTOM`, `VOXEL_MINERAL_FIRST/LAST` and `VOXEL_AUTO_FIRST`, and update every range test above). Categories must stay below `LABPBR_EMISSION_BASE` (24) in colortex2.g, where LabPBR emission starts. 4.33 did exactly this for the redstone lamp: IDs shifted by one from 3008, categories from 10 and voxel codes from 20; `codes_test.py` in the scratchpad walks every range end to end afterwards.

---

**Light output balance (4.33).** Measured by evaluating `emissionColor()` and `mineralEmission()` in the real shader (`emitcolor_test.py`); brightness is luminance, peak is the largest channel (1.0 is the display limit). "4.31" is the state before the 4.32/4.33 rebalance.

| source | 4.31 | 4.32 | 4.33 | peak 4.31 | 4.33 |
|---|---|---|---|---|---|
| glowstone / lamp (`EMIT_LAMP_I` 1.5 -> 1.25) | 1.23 | 1.23 | **1.03** | 1.50 | 1.25 |
| redstone lamp (own category since 4.33, `EMIT_RLAMP_I` 2.0) | 1.23 | 1.23 | **1.33** | 1.50 | 2.00 |
| sea lantern, end rod, beacon (`EMIT_COOL_I` 5.0 -> 1.5 -> 1.25) | 4.32 | 1.30 | **1.08** | 5.00 | 1.25 |
| redstone torch / ore (`EMIT_REDSTONE_I` 2.5 -> 1.5 -> 1.25) | 0.72 | 0.43 | **0.36** | 2.50 | 1.25 |
| amethyst cluster, crying obsidian (`EMIT_PURPLE_I` 2.5 -> 2.0) | 1.04 | 0.83 | 0.83 | 2.50 | 2.00 |
| mineral emerald (1.2 -> 0.85 -> 0.7) | 1.03 | 0.73 | **0.60** | 1.40 | 0.81 |
| mineral diamond (1.2 -> 0.8) | 1.10 | 0.74 | 0.74 | 1.31 | 0.87 |
| mineral amethyst (1.2 -> 1.0) | 0.84 | 0.70 | 0.70 | 1.71 | 1.42 |
| mineral coal (1.2 -> 0.75), copper (1.2 -> 0.9), redstone (1.2 -> 1.0) | 1.20 / 0.95 / 0.58 | 0.75 / 0.71 / 0.48 | same | | |
| mineral lapis (1.2, unchanged) | 0.72 | 0.72 | 0.72 | 1.99 | 1.99 |
| fire / torch / lantern, soul, lava, glow lichen (unchanged since 4.31) | 2.34 / 1.95 / 2.33 / 1.69 | same | same | 4.00 / 3.00 / 5.00 / 2.00 | same |

The mineral setting is not brightness: `mineralEmission()` normalizes by `sqrt(luminance x max channel)`, so at one shared value a green or cyan block reads far brighter than a blue one. The per-block defaults above put them all near lapis.

The `EMIT_*_I` value lists were also refined in 4.33 (range unchanged at 0.0-20.0, extra steps 0.2-0.4, 0.6, 0.9, 1.1, 1.25, 1.4, 1.75, 2.25 below 3.0), because the old quarter steps made 1.5 -> 1.0 the smallest possible reduction.

## 8. Debug views

**View** (`DEBUG_VIEW`) on the Debug page replaces the image with intermediate data; **Split Screen** (`DEBUG_SPLIT`) shows it on the left half with a divider line. HDR views are compressed with Reinhard + gamma in final; views from deferred6 and composite skip bloom, exposure and tonemapping.

| # | View | Produced in |
|---|---|---|
| 1 | Albedo | deferred6 |
| 2 | Normals | final |
| 3 | Lightmap (red block, blue sky) | final |
| 4 | Material ID | final |
| 5 | Smoothness / F0 / metal | final |
| 6 | Emission category | final |
| 7 | Depth | final |
| 8 | Raw GI (1 path) | final |
| 9 | Accumulated GI | final |
| 10 | Denoised GI (x `GI_STRENGTH`) | deferred6 |
| 11 | GI history length (red new, green full) | final |
| 12 | Direct sun/moon + specular | deferred6 |
| 13 | Shadow term | deferred6 |
| 14 | Block light + hand light | deferred6 |
| 15 | Voxel world (colors, traced from the camera) | final |
| 16 | Voxel codes | final |
| 17 | Ray tracing area (green in, yellow fade, red out) | final |
| 18 | Reflections only | composite |
| 19 | Translucent surface data | final |
| 20 | Emission | deferred6 |
| 21 | Voxel shapes (gray full cube, yellow-red small) | final |
| 22 | Ray-traced block lights only | deferred (GI replaced by the block-light samples) + deferred6 |

Tools: **Highlight Broken Pixels** (`DEBUG_NAN_CHECK`, NaN/Inf in colortex0 or the GI history in pink), **Shadow Map Preview** (`DEBUG_SHADOW_OVERLAY`), **Freeze Noise** (`DEBUG_FREEZE_NOISE`, GI random numbers only).

**Adding a view:** add a `DBG_` constant in `lib/debug.glsl`, add the number to the `DEBUG_VIEW` list in settings.glsl, produce it (usually in `finalDebugView()`; views made in deferred6 or composite must also be added to `isDeferredDebugView()` / `isCompositeDebugView()` and, if HDR, `isHdrDebugView()`), and add `value.DEBUG_VIEW.N=N Name` and the description in the lang file.

---

## 9. Tools (`tools/`)

Python 3.8+, run from the pack root (the folder that holds `shaders/`). Not shipped in the pack. The checks (`generate_wrappers.py --check` and the other four) exit with a non-zero code on failure.

| Tool | Command | What it checks / does | Needs |
|---|---|---|---|
| `generate_wrappers.py` | `python3 tools/generate_wrappers.py [--check]` | Writes the 174 wrapper files from the `PROGRAMS` table (program, source, `#version`, extension lines, extra defines). `--check` only reports differing files and files not in the table. Without `--check`, stray files are only warned about, not deleted. To add a program, add a row and rerun. | - |
| `validate_glsl.py` | `python3 tools/validate_glsl.py` | Expands `#include`s, inserts the defines Iris injects (`MC_RENDER_STAGE_*`, `IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE`) and compiles all 174 files with glslangValidator. Also scans the preprocessed source for GLSL reserved words used as identifiers (e.g. `packed`), which NVIDIA rejects and glslang accepts. | `glslangValidator` |
| `mesa_check.py` | `python3 tools/mesa_check.py [program ...]` | Compiles **and links** every program (87 = 29 x 3) with Mesa llvmpipe through a headless EGL OpenGL 4.5 compatibility context, and fails if a program uses more than 8 image uniforms (NVIDIA limit). With program names it checks only those and prints their images (shadow: 5). | Linux, Mesa (`libEGL.so.1`, `libGL.so.1`) |
| `sharpen_check.py` | `python3 tools/sharpen_check.py` | Runs the RCAS block from `program/sharpen.glsl` itself on Mesa llvmpipe, lifted verbatim out of the file, and feeds it flat patches and edges. **A flat patch must come back at exactly 1.0000x at every brightness, HDR included**; anything else means the filter is scaling the whole image, which is what 4.34 fixed. Exits non-zero on failure. `STRENGTH=1.0` to check another setting. | Linux, Mesa |
| `check_consistency.py` | `python3 tools/check_consistency.py` | settings.glsl <-> shaders.properties <-> en_us.lang: defaults inside their lists, on/off switches registered with `#ifdef`, every option on a menu page, no unknown menu items, **no dead settings** (in the menu but never read by shader code), valid profile tokens and values, label and 40-character comment for every option, distinguishable labels. **Language guard:** no Turkish letters or common Turkish words in `shaders/`, `tools/` and `docs/`; shader sources (`.glsl .vsh .fsh .csh .gsh .properties`) must be 7-bit ASCII. | - |

---

## 10. Release checklist

1. `lang/en_us.lang`: set `option.ABOUT_VERSION=Version: §fX.Y` and the version in `screen.CHANGELOG=§aChangelog X.Y`.
2. Rewrite the changelog lines `ABOUT_CL_HEAD` and `ABOUT_CL_1` ... `ABOUT_CL_5` (label and `.comment`). For more lines, add `ABOUT_CL_n` to settings.glsl (`// [0]`), to `screen.CHANGELOG` in shaders.properties and an empty `value.ABOUT_CL_n.0=` to the lang file.
3. If memory or requirements changed, update the `ABOUT_REQ_*` lines (and section 2 of this document).
4. Keep new comments, tool messages and documentation in English and shader sources in plain ASCII.
5. Run, all must pass: `python3 tools/generate_wrappers.py --check` (run it without `--check` first if a program was added or changed), `python3 tools/validate_glsl.py`, `python3 tools/mesa_check.py` (Linux), `python3 tools/check_consistency.py`, `python3 tools/sharpen_check.py` (Linux).
6. Package: `CORAL-VXGI-X.Y.zip` contains **only** `shaders/` and `LICENSE.txt`. `tools/` and `docs/` go into a separate `CORAL-VXGI-X.Y-dev.zip`. Both names carry the version.

---

## 11. Known limitations

- **Ray-traced light list overflow.** All light blocks share one global list of 1024 entries (`lightImg`), filled by the shadow pass in vertex processing order (roughly chunk draw order), not by distance. When the grid holds more than 1024 light cells (every lava block, lit candle or glowstone cell is one entry; lava lakes and the Nether reach this easily), the extra entries are **dropped silently**: those lights get no direct sampling and no shaped shadows, and they only reach surfaces through random GI rays that happen to hit them (noisy, limited by `GI_FIREFLY_CLAMP`) and the vanilla lightmap base (`LIGHTMAP_RT_BLEND`). The dropped lights can be the ones next to the player, and which lights make it into the list can change from frame to frame as chunks are redrawn, so lights may pop in and out.
- **Noise with many lights, even below the limit.** Candidates are drawn uniformly from the whole list and rejected afterwards if out of `RT_LIGHT_RANGE`, so a torch next to the pixel is one entry out of the list length. With hundreds of lights in the grid, nearby lights become much noisier for the same `RT_LIGHT_SAMPLES`.
- Ray-traced block light on visible surfaces needs `GI_ENABLED`, and it goes through the GI chain (`GI_STRENGTH`, `GI_SATURATION`, firefly clamp, denoiser).
- **The voxel grid holds terrain only.** Entities and block entities (chests, signs, beds) do not block or reflect rays. Blocks buried inside a solid mass are not in the grid either: Minecraft does not draw them, so the shadow pass never sees them and the grid has air there. Since the visible boundary of the mass is always solid, rays cannot reach that air any more (4.21) - but a probe placed inside such a mass still measures light. Group 1003 (fences, bars, chains, cobwebs, banners, grates) is never voxelized, so these blocks do not block block light, GI or reflections (their sun shadows come from the shadow map).
- **Block shapes** are one box per cell at 1/8 (X, Z) and 1/16 (Y) resolution; stairs and other L-shapes are a full box. Voxels have one flat color, so reflections of off-screen geometry are untextured.
- **Hole mask** bits come from the rasterized shadow map, so coverage depends on shadow map resolution, distortion and sun direction; unmarked texels count as solid. It only affects block-light shadow rays. `CUTOUT_MASK_RES` 16 is used at every Voxel Range (see the memory table).
- **Outside the grid** GI is replaced by sky ambient x sky lightmap and vanilla block light is used at full strength. GI rays that leave the grid or run out of steps count as sky hits (weighted by the pixel's sky lightmap).
- Stained glass, ice, slime and honey are drawn in the translucent layer, so they tint block light only when both `GLASS_TRANSMISSION` and `VOXELIZE_TRANSLUCENT_EMITTERS` are on (plain glass is in the cutout layer and needs only the first).
- Translucent surfaces, particles and weather are lit from the lightmap only (no GI, no ray-traced block light). The hand is not ray traced; its indirect light is sky ambient.
- Rough reflections trace one jittered ray per frame, so they are grainy unless the Reflection Denoiser is on (it is off by default) or TAA smooths them over time. Temporal reprojection (GI, TAA and the reflection denoiser) uses camera motion only; moving mobs can smear slightly.
- **Clouds:** volumetric clouds exist only in the Overworld, cast no shadows and do not enter the GI sky term; they are also ray-marched in sky reflections, which costs time on large water surfaces. Vanilla clouds (Cloud Type = Vanilla) follow the game's own Clouds video setting (Fast / Fancy / Off); for Off and Volumetric the pack turns the vanilla layer off.
- Debug view 22 replaces the GI of the whole frame, so with Split Screen the "normal" right half is also missing its GI.
- At Voxel Range 256 `voxelDistance` (136) is above the default `shadowDistance` (128); Iris documents that the shadow distance cannot be lower than `voxelDistance`.
- Distant Horizons is not supported. GPU recommendations in the menu are estimates, not measurements.

---

## 12. Version history

**4.34** - a review pass; all of these are bug fixes, no new features.
- `sharpen.glsl`: the RCAS divisor had a sign error (every flat surface came out at 0.62x), the contrast limiter assumed an LDR signal (nothing above 1.0 was sharpened), and the result was clamped to 1.0 on the HDR path (every value above white collapsed onto one). Measured before/after with `sharpen_test.py` and `postchain_test.py`. This is why earlier versions kept raising the indirect light: they were compensating for it (5.14).
- Metal no longer goes black where the normal map is busy: `SPECULAR_AA` lowered the smoothness that the reflection fade-in reads, while `lighting.glsl` had already handed the metal's color to the reflection. The fade now reads the material's own smoothness, and `metalness` fades with the same curve so a rough LabPBR metal is not left with neither (5.9, 5.6).
- a-trous edge stop uses distance to the surface plane instead of raw depth difference, so the GI filter keeps working on ground seen at a grazing angle past ~25 blocks (5.5).
- GI reprojection tolerance scales with the surface slope instead of distance alone; a block-deep disocclusion is rejected again past 23 blocks (5.5).
- The spike filter's "never below the pixel's own history" floor is only applied where there IS history - it used to compare a fresh pixel against itself, so disoccluded edges kept their dots (5.5).
- `taa_resolve`: the neighborhood clamp could leave the domain `tonemapUnweight` inverts, flipping sign and returning a ~40000x pixel. The clamped value is projected back into range first (5.13).
- Bounce-0 emission is handed over to the shadow ray with a smoothstep over the same window in which `sampleBlockLights` fades out, instead of an on/off at `RT_LIGHT_RANGE` - that step made a distant lava lake brighter than a near one (5.4).
- Bloom is added, not mixed in and added (5.12). Reflection sharpening skips neighbors with no reflection and at a different depth, and guards NaN (5.9).
- Menu: `EMISSION_SURFACE` is a slider; `GLASS_REFRACTION_STRENGTH` renamed "Glass Bending Amount"; About-page placeholder text replaced; orphan `VOXELIZE_IN_FRAGMENT` lang keys removed; redundant state tokens dropped from `block.3005`.

**4.33**
- The redstone lamp is a light category of its own (ID 3008, category 9, voxel code 19, `EMIT_RLAMP_R/G/B/I`): it used to share the glowstone setting, so it could not be brighter than glowstone. This shifted the tinted ID, categories 10-18 and voxel codes 20-43 up by one (7).
- Light output turned down again: `EMIT_LAMP_I` / `EMIT_COOL_I` / `EMIT_REDSTONE_I` 1.5 -> 1.25 and `EMIT_MINERAL_EMERALD_I` 0.85 -> 0.7 (7).
- Finer steps below 3.0 in every `EMIT_*_I` value list; range unchanged.
- Settings only plus the renumbering; every leak, stair and noise case measures the same as in 4.32.

**4.32**
- Light output rebalanced (settings only, no code): sea lantern -70 % (it was 3.5x glowstone at the same vanilla light level), redstone torch's red channel 2.5 -> 1.5, mineral blocks set per block so they all land near lapis (7).

**4.31**
- Emitters are no longer counted twice (shadow ray + first indirect ray), which is what blew out the wall around every torch, lantern, glowstone and lava pool (5.4).
- Block light inside reflections is frame-stable while the reflection denoiser is off (5.9).
- `HIGHLIGHT_DESAT` defaults to 0.0 again.

**4.30**
- Defaults now match `profile.B0_MEDIUM` exactly (Medium keeps `MATERIAL_NORMALS`, parallax stays Ultra-only), so the profile button reads Medium instead of Custom.
- Reflections: fixed jitter seed when the denoiser is off, specular anti-aliasing, optional sharpening; `REFLECTION_DENOISE` is off by default again (5.9).
- `HIGHLIGHT_DESAT` washes very bright saturated colors towards white (5.12); `CLOUD_HEIGHT` default 320.

**4.29**
- Auto exposure no longer treats a lamp-lit room as a cave, which is what burned bright interiors out to white (5.12).
- `RT_LIGHT_SOFT_CAP`: a crowd of light blocks stops adding up without end; single lamps unchanged (5.3).
- `REFLECTION_NORMAL_STRENGTH`: the normal map no longer bends reflections into unrecognisable shapes (5.9).

**4.28**
- `REFLECTION_DENOISE` on by default and a steeper accumulation ramp: iron, the mineral blocks and polished stone stop flickering (5.9).
- Blocks seen in a reflection are lit with the full sky ambient instead of 15 % of it (5.9).
- The miss fade from 4.26 no longer applies to metal, which has no diffuse color to fall back on (5.9).

**4.27**
- Parallax fixed: the shift is measured in sprites instead of atlas coordinates, so the radial "lens" distortion is gone and `POM_DEPTH` works; wrap instead of clamp at sprite borders, explicit derivatives for every sprite read, smooth distance fade (5.7).

**4.26**
- `SKY_LIGHT_CURVE` 0.8 and `GI_SKY_STRENGTH` 1.25: shaded places another 25-40 % brighter, full sun +3 % (5.11).
- Screen-space reflection mode fixed: both reflection modes go through `traceReflection()`, the voxel step is compiled only for the ray traced mode, and a reflection that finds nothing fades out instead of blackening the surface (5.9).

**4.25**
- Sky light in shade: `SKY_LIGHT_CURVE` (new, default 1.0) replaces the squared lightmap and `GI_SKY_STRENGTH` defaults to 1.0. Shaded places are 1.5-4x brighter, sunlit ones within 4 % of before (5.11).
- Spike removal moved from the raw frame to the accumulated image, where it no longer removes the indirect light of dimly lit rooms (5.5).
- `shaders.properties`: three lines of the `sliders` list had been sitting inside the comment header since 4.20, so the mineral strengths, FXAA and sharpening strength, the reflection denoiser settings and `WATER_REFRACTION_DEPTH` were not drawn as sliders.

**4.24**
- New `solidImg` grid: every face inside a cell records which side of it the block is on, so a block shaped like an L (a stair) is the union of those sides instead of a full cell. Both tracers now test the cell the ray starts in: indirect light no longer passes through the block's own step, and direct light reaches a stair tread again instead of being stopped by its own box.
- Spike removal in `deferred1` (`GI_SPIKE_FILTER`, `GI_SPIKE_TOLERANCE`): single pixels far brighter than their neighbors are pulled back before accumulation, which clears the star-like dots in dark rooms.
- Every leak case measured for 4.21/4.22 returns exactly the same value as in 4.23.

**4.23**
- Sun glow ported from 4.18: the bright patch around the sun is now an angle-based aureole with the new `SUN_GLOW` setting (Sky page, 0.0-8.0, default 2.0), the sun disc edge is narrow again (`x 1.06`), and the sun defaults to `SUN_DISC_SIZE` 0.5 / `SUN_DISC_BRIGHTNESS` 8.0 with much finer value lists.

**4.22**
- Block shapes: a horizontal face now records which side of it the block is on, so partial blocks in a floor (slab, dirt path, carpet, snow) are no longer stored as full cells and their own surface is no longer inside their box. This closed the last way light got out of a floor above a lit room.

**4.21**
- Block-light shadow rays: light blocks are occluders again (only the sampled source passes), the cell the surface sits in is tested, and the ray aims at the visible face of the light block instead of a point inside it. Together these close the "light comes out of the floor above a glowstone ceiling" leak; measured before/after with a software-GPU test of the real GLSL, ordinary lighting is unchanged.

**4.20**
- Reflections ported from 4.18: one `REFLECTION_MODE` setting (off / screen space / full ray traced), roughness-capped Fresnel, per-frame jitter, energy-conserving opaque reflections, fixed-thickness refraction (`WATER_REFRACTION_DEPTH`) and the optional Reflection Denoiser (`REFLECTION_DENOISE`, colortex11).
- Emissive blocks ported from 4.18 (without the separate Nether portal category): wool and concrete no longer emit, concrete powder and the seven mineral blocks each have their own setting, per-block surface gain in the albedo alpha, `EMISSION_SURFACE`, LabPBR emission from ID 24.
- New pass `composite2` (`program/sharpen.glsl`): FXAA (off) and RCAS sharpening (on).
- Denoiser and Emissive Block Colors moved to the main menu.
- Defaults: `LIGHTMAP_RT_BLEND` 0.0, `NORMAL_STRENGTH` 4.0, `CAUSTICS_STRENGTH` 2.0, `CAUSTICS_SCALE` 0.5, `CAUSTICS_SPEED` 2.0; profiles also set `REFLECTION_MAX_DISTANCE`.

**4.19**
- Rebuilt on the 2.1 code base; lighting, GI, reflections, shadows, water, the denoiser and the profile values are 2.1.
- Ported from 4.18: volumetric clouds (`CLOUD_STYLE` 0/1/2, `lib/sky.glsl`, `program/clouds.glsl` as `gbuffers_clouds`, `applyCloudsInFront` at the end of composite, Clouds page); nine tonemaps; the parallax / normal-map fix (clamping `wrapInSprite`, POM shift limited to 0.9 x the sprite half size, `NORMAL_STRENGTH` 2.0, `POM_STEPS` 32, 0.05-step value lists); the About page (About and the profile button side by side, System Requirements and Changelog pages; the performance tips line removed).
- Profiles `A_LOW` / `B0_MEDIUM` / `C1_HIGH` / `C5_ULTRA` set the same settings; High and Ultra enable normal mapping and 10000-block clouds, Ultra also parallax with 64 steps.

**3.x - 4.18:** history of the abandoned 4.x code line; only the parts listed above were brought over. **2.1** is the base.
