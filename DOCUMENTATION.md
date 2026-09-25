# CORAL VXGI - Developer Documentation

Version: **4.46** - Author: Oktay Mercan

This document explains **how the pack works** and **how to develop it**. Player-facing explanations live in the in-game menu (the hover text of every setting, `shaders/lang/en_us.lang`). Code comments, tools and documentation are in English; shader sources are plain 7-bit ASCII.

**About this code base:** 4.19/4.20 is not a continuation of 4.18. It is the 2.1 code base with a few parts ported from 4.18: volumetric clouds, nine tonemaps, the parallax / normal-map fix and the About page (4.19), then reflections, the emissive-block system, FXAA and RCAS sharpening (4.20). 4.21 and 4.22 close the light leaks of the ray traced block light (5.1, 5.3), 4.23 brings over the sun glow fix (5.11), 4.24 gives blocks shaped like an L a correct shape (5.1), and 4.25 fixes how much sky light a shaded surface receives (5.11). 4.35 adds a light grid (5.3, redesigned from the 4.18 one) and post-and-arm shapes for fences, walls and panes (5.1, a new design; the 4.17 texel-exact detail shapes were not brought over). 4.36 adds half resolution GI (5.4) and 4.37 a world space GI cache (5.4.1, redesigned from the 4.x one: besides seeding newly visible pixels it also stands in for the later bounces of the screen's paths). 4.38 gives the voxels their block textures for reflections (5.15), 4.39 adds a voxel grid for entities (5.16, refined in 4.43), 4.40 rebuilds the water: caustics from the wave field, light shafts, depth absorption and the surface seen from below (5.10, softened in 4.42). 4.44 is a repair release after a review of the whole pack, and 4.45 / 4.46 close the light leaks along block corners that it exposed (5.1, 5.4; section 12). GI, shadows, the denoiser and the profile values are otherwise still 2.1. Eye adaptation of the 4.x line does not exist here.

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
- **Ray-traced block lights (`RT_LIGHTS`):** the shadow pass also fills the light grid (a light mask per 8-block region, 5.3). Each pixel picks one light from the list of its region by resampled importance sampling (RIS) and sends a shadow ray to a point inside the light's shape.
- **Path-traced GI:** one cosine-weighted path per pixel per frame, up to `GI_BOUNCES` bounces, cleaned up by temporal accumulation and an SVGF-style a-trous filter.
- **World space GI cache (`WORLD_SPACE_GI`):** every exposed block face within `GI_CACHE_RADIUS` blocks keeps its own indirect light, updated by two compute passes whether it is on screen or not. Pixels that come into view start from it, and the bounces after a GI ray's first hit are read from it (5.4.1).
- **Entities in ray tracing (`VOXELIZE_ENTITIES`):** mobs, players, chests and other entities are written into a grid of their own every frame, so they block GI rays and the shadow rays of block lights (5.16).
- **Textured voxels (`VOXEL_TEXTURES`):** every voxel face knows its sprite in the block atlas, so blocks in ray-traced reflections show their texture (5.15).
- **Water:** caustics refracted by the wave field, light shafts and depth absorption under water, a mirror of the underwater world at low angles from below (5.10).
- Also: ray-traced reflections with a screen-space fallback, colored sun shadows through stained glass, volumetric clouds, TAA, nine tonemaps, LabPBR support (smoothness, F0/metal, emission, normal maps, parallax).

---

## 2. Requirements and installation

| | |
|---|---|
| Minecraft | **1.21 or newer** (made on 1.21; unknown block names in `block.properties` are ignored). 1.20.1 works without entities in ray tracing: Iris 1.8 does not exist for it. |
| Mod loader | Fabric or NeoForge (whichever Iris supports) |
| Shader mod | **Iris 1.8+** with Sodium. Iris 1.8 added the `shadow_entities` / `shadow_block` programs that the entity grid is built in (5.16); Iris 1.7 (the last for 1.20.1) runs the pack with entities left out of ray tracing. |
| OpenGL | **4.3**. The shadow programs and the three compute passes (`deferred_a/b/c.csh`) are `#version 430` and write images (image load/store); `shadow_entities` / `shadow_block` add a geometry shader; every other program is `#version 330 compatibility`. |
| GPU | NVIDIA, AMD or Intel; only standard OpenGL is used |
| Operating system | Windows or Linux. macOS is not supported (OpenGL stops at 4.1, no image load/store). |
| Not supported | OptiFine, Oculus. Distant Horizons terrain is not lit by the pack (there are no DH programs). |

Iris features used: custom images (`image.*`), per-buffer blending (`blend.<program>.<buffer>`), compute passes, reversed shadow culling (`shadow.culling = reversed`) together with the `voxelDistance` constant, `renderStage`, `at_midBlock`, `mc_midTexCoord`, `at_tangent`, `blockEntityId`, a resource texture (`customTexture.blockAtlas = minecraft:textures/atlas/blocks.png`, 5.15). `iris.features.required = CUSTOM_IMAGES PER_BUFFER_BLENDING COMPUTE_SHADERS REVERSED_CULLING` (since 4.44; the last two were used but not required, so an Iris without them would have loaded the pack half-working; Iris 1.7 already knows all four). `BLOCK_EMISSION_ATTRIBUTE` is optional (`iris.features.optional`); it feeds `AUTO_EMITTERS`.

**Installation:** the release zip contains only the `shaders/` folder and `LICENSE.txt` and goes into `.minecraft/shaderpacks/` as-is.

### Video memory (approximate)

Computed from the `image.*` sizes in `shaders.properties` and the formats in `lib/pipeline.glsl` (4.42). The profile decides Voxel Range and shadow map resolution; the hole mask (`maskImg`) is on by default at 16x16 per block (8 words of 32 bits per voxel). Shadow maps are counted as two 32-bit depth maps plus one RGBA8 `shadowcolor0`.

| Profile | Voxel grid (cells) | voxel + shape + solid | faceTexImg | maskImg | light grid | Shadow maps | Total with GI cache, entity grid, water map |
|---|---|---|---|---|---|---|---|
| Low | 128x96x128 | 19 MB | 25 MB | 50 MB | 3.4 MB | 13 MB (1024^2) | ~0.15 GB |
| Medium (default) | 128x96x128 | 19 MB | 25 MB | 50 MB | 3.4 MB | 50 MB (2048^2) | ~0.19 GB |
| High | 192x128x192 | 57 MB | 75 MB | 151 MB | 14 MB | 113 MB (3072^2) | ~0.45 GB |
| Ultra | 256x128x256 | 101 MB | 134 MB | 268 MB | 18 MB | 201 MB (4096^2) | ~0.76 GB |

`CUTOUT_MASK_RES = 8` divides the mask by 4; turning `CUTOUT_SHADOW_MASK` off removes it. The world space GI cache adds 34 MB on every profile (`giCacheImg` 25 MB, `giCacheMetaImg` 6 MB, `giSkyImg` 1.5 MB, the face list 0.5 MB), the entity grid 4.3 MB, the water surface map 0.07-0.26 MB. Without the light grid its images are replaced by one 4 KB list.

**Screen buffers** come on top and do not depend on the profile: 12 colortex (84 bytes per pixel, see 4.1), and Iris keeps two copies of each, so about **0.35 GB at 1080p**, **0.6 GB at 1440p** and **1.4 GB at 4K**, plus the bloom mip chain of colortex0, the depth buffers and Minecraft's own share. The menu's System Requirements page (`ABOUT_REQ_VRAM`) quotes these numbers.

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
                         (2-channel and 8-bit), the colortex6.a packing (encodeReflectInfo)
    space.glsl           screen / view / player transforms, depth linearization,
                         geometricNormal() (the flat normal rebuilt from depth)
    materials.glsl       block IDs, voxel codes, light colors, voxelEmission()
    voxel.glsl           voxel grid, DDA tracers, post-and-arm shapes, hole mask lookup,
                         sampleBlockLights(), giEmissionScale()
    entity.glsl          entity grid layout (5.16)
    voxeltex.glsl        textured voxels: face classes, sprite words, texel lookup (5.15)
    water.glsl           wave field, caustics, water surface height map (5.10)
    lightgrid.glsl       light grid: regions, home masks, region lists, lgCovered()
    gipath.glsl          ONE GI path (giTracePath / giTraceBounces), shared by the screen
                         and the world space GI cache
    gicache.glsl         world space GI cache: layout, validity, SEED / REST lookups
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

**Wrappers:** Iris wants every program as a separate file per dimension folder. Each of the 213 files (36 programs: 31 with vertex + fragment shader, `shadow_entities` and `shadow_block` with vertex + geometry + fragment shader, and the compute passes `deferred_a.csh`, `deferred_b.csh`, `deferred_c.csh`; x 3 dimensions) is a short template: `#version`, the image extension line (shadow vertex shader only), `VERTEX_SHADER` / `GEOMETRY_SHADER` / `FRAGMENT_SHADER` / `COMPUTE_SHADER` (a compute pass also gets its `layout` and `workGroups` lines), the dimension define (`OVERWORLD`, `NETHER`, `END`), program-specific defines, then `#include "/program/xxx.glsl"` - and nothing after the path on that line: Iris reads the rest of an `#include` line as part of the file name (that is what broke 4.40). They are generated by `tools/generate_wrappers.py`; never edit them by hand.

---

## 4. Render pipeline (pass order)

The program list is the `PROGRAMS` table in `tools/generate_wrappers.py`; Iris runs the stages in its fixed order.

| # | Program | Source | What it does | Writes |
|---|---|---|---|---|
| 1 | `shadow`, `shadow_lightning` | `shadow.glsl` | Sun depth. Vertex shader: voxelizes terrain (5.1), records fences, walls and panes as post and arms (5.1), the atlas sprite of every face (5.15), the water surface height (5.10) and adds light blocks to the home masks of the light grid (5.3). Fragment shader: glass color for colored shadows (black for tinted glass), hole mask bits (5.2). | shadowtex0/1, shadowcolor0, `voxelImg`, `shapeImg`, `solidImg`, `lightHomeImg` (or `lightImg` without the grid), `maskImg`, `giSkyImg` (sky light in front of every face, 5.4.1), `faceTexImg`, `waterImg` |
| 1 | `shadow_entities`, `shadow_block` | `shadow_entity.glsl` | Entities and block entities (Iris 1.8+): shadow depth, and a geometry shader that clips every triangle against the cells it touches and writes the entity grid (5.16). | shadowtex0/1, shadowcolor0, `entityImg` |
| 2 | `gbuffers_terrain/entities/block/hand` | `gbuffers_solid.glsl` | Opaque G-buffer: albedo, normal (+ normal map, POM), lightmap, material, LabPBR. Entities and block entities are `MAT_ENTITY` with their flat face direction (5.7). End portal drawn unlit. | colortex0-2 |
| 2 | `gbuffers_basic/textured/textured_lit/weather/spidereyes/beaconbeam/lightning/armor_glint/damagedblock` | `gbuffers_forward.glsl` | Forward-lit with `lib/forward.glsl`; material `MAT_UNLIT` so the deferred passes leave them alone. Lightning (4.44) glows from its vertex color; without its own program Iris drew it with `gbuffers_entities` as a lit solid. | colortex0 (+2) |
| 2 | `gbuffers_skybasic/skytextured` | `gbuffers_sky.glsl` | Keeps only stars, moon (x `MOON_TEXTURE_BRIGHTNESS`) and the End sky texture; the dome is discarded, the vanilla sun too when `SUN_DISC` is on. | colortex0 |
| 2 | `gbuffers_clouds` | `clouds.glsl` | Vanilla clouds pass through (x `SKY_BRIGHTNESS`) when `CLOUD_STYLE == 1`; otherwise discard. | colortex0 |
| 3a | `deferred_a.csh` | `lightgrid_build.glsl` | Light grid: the list of home regions that reach every 8-block region, with its alias table (5.3). One work group per region. | `lightClusterImg`, word 17 of `lightHomeImg` |
| 3b | `deferred_b.csh` | `gicache_update.glsl` (`GICACHE_LIST`) | World space GI cache: lists the exposed block faces within `GI_CACHE_RADIUS`, split into phases when there are more than `GI_CACHE_BUDGET`; teleport check (5.4.1). One thread per cell of the 64^3 cache. | `giListImg`, `giListCountImg`, `giStateImg` |
| 3c | `deferred_c.csh` | `gicache_update.glsl` (`GICACHE_TRACE`) | Traces `GI_CACHE_RAYS` paths from every listed face and blends SEED and REST into its entry (5.4.1). One thread per face, dispatched 65536 wide. | `giCacheImg`, `giCacheMetaImg`, word 5 of `giStateImg` |
| 3 | `deferred` | `deferred.glsl` | One GI path per pixel (`lib/gipath.glsl`), including the block-light samples (5.4); the bounces after the first hit come from the world cache where it has the hit face (5.4.1). On an entity pixel the rays start ON the entity (5.16). With `GI_HALF_RES` (`scale.deferred = 0.5`) only the lower-left quarter, one traced pixel per 2x2 block. | colortex3 |
| 4 | `deferred1` | `deferred1.glsl` | Temporal accumulation; with `GI_HALF_RES` it first spreads the traced samples over the full resolution; a pixel without history starts from the world cache (5.5). | colortex4, colortex7 |
| 5 | `deferred2` | `denoise_seed.glsl` | Variance estimate. | colortex8 |
| 6-8 | `deferred3-5` | `denoise1-3.glsl` | A-trous passes, step 1, 2, 4 (a disabled pass copies). | colortex9, 8, 9 |
| 9 | `deferred6` | `lighting.glsl` | Final opaque lighting, sky pixels (sky, sun disc, clouds), deferred debug views. | colortex0, colortex6 |
| 10 | `gbuffers_water`, `gbuffers_hand_water` | `gbuffers_water.glsl` | Water, glass, ice, translucent light sources (Nether portal); forward-lit, waves; the glass opacity goes into colortex5.b. | colortex0, colortex5 |
| 11 | `composite` | `composite.glsl` | Refraction, metal behind glass and water (5.9), water absorption / scattering, caustics and depth light, the underwater mirror, reflections (+ reflection history), distance fog (the land behind a window gets its own), underwater fog and light shafts, **volumetric clouds in front of terrain** (`applyCloudsInFront`, last step). | colortex0, colortex11 |
| 12 | `composite1` | `taa_resolve.glsl` | TAA resolve (the hand keeps its history in place). | colortex0, colortex10 |
| 13 | `composite2` | `sharpen.glsl` | FXAA (`FXAA`, off by default) and RCAS sharpening (`SHARPEN`). | colortex0 |
| 14 | `final` | `final.glsl` | Bloom, exposure, tonemap, saturation, gamma, contrast, vignette, final debug views, dithering. | screen |

### 4.1 Texture layout (`lib/pipeline.glsl`)

| Texture | Format | Contents | Cleared |
|---|---|---|---|
| colortex0 | RGBA16F | gbuffers: albedo (sRGB) -> lit HDR scene after deferred6; mipmapped in final for bloom | yes |
| colortex1 | RGBA16 | rg normal (octahedral, player space), b block light, a sky light | yes |
| colortex2 | RGBA8 | r material (`MAT_*`: 0 unlit, 1 lit, 2 plant, 3 leaves, 4 emissive, 5 hand, 6 entity, 7 glowing part of an entity), g emission ID - or, on `MAT_ENTITY` pixels, the flat face direction in 8 bits (`encodeNormal8`), b smoothness, a F0 (>0.9 = metal; entities are capped at 0.08) | yes |
| colortex3 | RGBA16F | raw 1-sample GI (+ block-light samples) | yes |
| colortex4 | RGBA16F | GI history, a = accumulated frames (written with stochastic rounding, 5.5) | **no** |
| colortex5 | RGBA16 | translucent data: rg normal, b type (glass 0.3-0.7 = 0.3 + 0.4 x opacity, 1 water, 0 emitter), a sky light | yes |
| colortex6 | RGBA8 | reflection info: rgb F0, a smoothness and metal flag packed (`encodeReflectInfo`: 0-0.49 others, 0.51-1.0 metals; 0 on the hand and entities) | yes |
| colortex7 | R32F | linear depth of the previous frame | **no** |
| colortex8 / 9 | RGBA16F | a-trous ping-pong: rgb light, a variance; colortex9 is the result | yes |
| colortex10 | RGBA16F | TAA history | **no** |
| colortex11 | RGBA16F | reflection history: rgb reflection, a linear depth (`REFLECTION_DENOISE`) | **no** |

When adding a texture, add its format line to the header comment and its clear flag below it (Iris reads the format lines even inside the comment).

### 4.2 Custom images (`shaders.properties`, `image.*`)

| Image | Format / size | Purpose |
|---|---|---|
| `voxelImg` | RGBA8 3D, 128x96x128 / 192x128x192 / 256x128x256 | rgb = average block color (per-channel transmittance for glass, gray transmittance for cutout blocks), a = voxel code / 255 |
| `shapeImg` | R32UI 3D, same size | shape bit mask (bits 0-15 Y slices, 16-23 X, 24-31 Z); for post-and-arm voxels (codes 7, 8) the POST (5.1). The atomic OR also tells the first vertex of a cell (light ownership). Always defined. |
| `solidImg` | R32UI 3D, same size | solid sides of the faces inside the cell (4.24, 5.1); for post-and-arm voxels the ARMS. Only with `VOXEL_SHAPES`. |
| `maskImg` | R32UI 3D, width x `MASK_WORDS` (8 words at res 16, 2 at res 8) | hole bits of cutout blocks; only with `CUTOUT_SHADOW_MASK` |
| `lightHomeImg` | R32UI, 18 words per 8-block region (18x3072 / 54x4096 / 72x4096) | light grid home masks: count, 512 bits, running counts (5.3); with `RT_LIGHTS` + `LIGHT_GRID` |
| `lightClusterImg` | R32UI, 260 words per region (260x3072 / 780x4096 / 1040x4096) | light grid region lists with alias tables (5.3); rebuilt every frame, so **not** cleared |
| `lightImg` | R32UI 1025x1 | single global light list without the grid (4.44): the cells of the lights (x, y, z in 10 bits each), the atomic counter in the last texel (keeps counting past 1024); the color is read back from the voxel grid as with the grid. It was an RGBA16F list plus a separate counter image, which made the shadow program bind 9 images: one more than NVIDIA allows, so the pack did not load there with Light Grid off. |
| `faceTexImg` | R32UI 3D, 4 words per voxel (512x96x128 / 768x128x192 / 1024x128x256) | the atlas sprite of the top, side and bottom faces plus the biome tint of every voxel (5.15); only with `VOXEL_TEXTURES` |
| `entityImg` | R32UI 3D, 260x64x64 | the entity grid: 4 words per cell of a 64^3 grid around the camera plus the brick mask column (5.16); only with `VOXELIZE_ENTITIES` |
| `waterImg` | R32UI 2D, one texel per column (128^2 / 192^2 / 256^2) | height of the highest water surface of every column, `(y + 256) x 64`, 0 = none (5.10); with caustics, light shafts or depth absorption |
| `giCacheImg` | RGBA16F 3D, 768x64x64 | world space GI cache: 64^3 cells x 6 faces x 2 values (SEED, REST), x = cell.x * 12 + face * 2 + value (5.4.1) |
| `giCacheMetaImg` | R32UI 3D, 384x64x64 | per face: tag (bits 0-5), update count (6-11), frame of the last update (12-31) |
| `giListImg` | R32UI 512x256 | the faces listed this frame: camera-relative cell (3 x 6 bits) + face (3 bits) |
| `giListCountImg` | R32UI 4x1 | list length, sky flag, exposed face count |
| `giStateImg` | R32UI 8x1 | last frame + 1, last camera cell, epoch frame, previous exposed face count |
| `giSkyImg` | R32UI 3D, 72x72x72 | sky light of the air cell in front of every face: low 16 bits sum (0-255 scale), high 16 bits count |

`lightClusterImg`, `giCacheImg`, `giCacheMetaImg`, `giListImg` and `giStateImg` are not cleared (they are rebuilt, or carry their own validity); everything else is cleared every frame, so the grid and the light data are rebuilt from scratch each frame. The gi* images exist only with `WORLD_SPACE_GI` and `GI_ENABLED` (the same condition as `GI_CACHE_ACTIVE` in settings.glsl).

**Unit limits.** The shadow program binds 8 images with everything on (`voxelImg`, `shapeImg`, `solidImg`, `lightHomeImg` or `lightImg`, `giSkyImg`, `faceTexImg`, `waterImg`, `maskImg`) - exactly NVIDIA's limit, so a ninth image in that program stops the pack loading on GeForce cards. `shadow_entities` / `shadow_block` bind 1, `deferred_a` 2, `deferred_b` and `deferred_c` 3 each. All other passes read the images through samplers; OpenGL guarantees 16 texture units per program (most drivers have 32, but Iris refuses the pack when a program needs more units than the driver has). `deferred` uses 16 in the Overworld; `composite` used 19 (20 with the Reflection Denoiser) until 4.44 and now uses 15 (16): it no longer reads the material buffer (the metal flag moved into colortex6.a, `encodeReflectInfo`) and it defines `NO_COLORED_SHADOW_TINT` (the sun through stained glass is not tinted in the water's sun highlight and in blocks seen in reflections) and `NO_CUTOUT_MASK` (blocks with holes pass the block light inside reflections evenly). `tools/mesa_check.py` checks both limits for every program.

Iris runs `deferred_a`, `deferred_b` and `deferred_c` back to back and puts a memory barrier before every dispatch as long as `allowConcurrentCompute` is not set in `shaders.properties`; `deferred_c` depends on that, since it reads what the two before it wrote.

**Changing the grid size** needs these kept in sync: the `VOXEL_RANGE` list, `VOXEL_VOLUME` in `lib/voxel.glsl`, the `voxelImg` / `shapeImg` / `solidImg` / `faceTexImg` / `maskImg` / `waterImg` / light grid lines in `shaders.properties`, and `voxelDistance` in `lib/settings.glsl` (half the width + 8 blocks).

---

## 5. Core systems

### 5.1 Voxel grid (`program/shadow.glsl`, `lib/voxel.glsl`)

- With `shadow.culling = reversed`, Iris draws every chunk within `voxelDistance` (72 / 104 / 136 blocks for Voxel Range 128 / 192 / 256) in the shadow pass. The vertex shader finds the block center (`gl_Vertex + at_midBlock / 64`), moves it to player space with `shadowModelViewInverse` and writes the cell `floor(playerPos + fract(cameraPosition)) + size/2`.
- Render stages TERRAIN_SOLID, TERRAIN_CUTOUT and TERRAIN_CUTOUT_MIPPED are voxelized; from TERRAIN_TRANSLUCENT only glass (with `GLASS_TRANSMISSION`), tinted glass and - with `VOXELIZE_TRANSLUCENT_EMITTERS` - light sources. (Until 4.44 that switch kept the whole translucent layer out, stained glass included.) Entities and block entities have a grid of their own (5.16).
- Skipped IDs: water, plants, banners / string / dripstone / barriers / open fence gates (1003), end portal, glass and glass panes without `GLASS_TRANSMISSION`, leaves without `VOXELIZE_LEAVES`, box shapes (1004) without `VOXEL_SHAPES`, fences / walls / bars / cobwebs (1005, 1007, 1008) without `VOXEL_SHAPES` + `VOXELIZE_LATTICE`. Faces of ordinary (non-emitting, non-leaf) blocks whose average alpha is below 0.35 are skipped too (e.g. the grass side overlay). Tinted glass (1009) is always a solid voxel, whatever its texture's alpha.
- **Color:** `spriteAverage()`: the sprite's mip level 4 at `mc_midTexCoord` when the atlas has that level, otherwise (the game's Mipmap Levels below 4, 4.44) an alpha-weighted average of 4 x 4 texels spread over the face's part of the sprite; before 4.44 the read fell back to the highest level there was, down to the single middle texel at 0, and trapdoors or ladders with a hole in the middle dropped out of the grid. Divided by alpha and multiplied by the vertex (biome) color. Every vertex stores; the last write wins.
- **Voxel codes** (`lib/materials.glsl`): 0 air, 1 solid, 2 leaves, 3 polished (also concrete and mineral blocks while not emitting), 4 metal, 5 transmissive (glass), 6 cutout, 7 post and arms, opaque (fence, wall), 8 post and arms, tinting (glass pane, iron bars, chain), 9 veil (cobweb, scaffolding, copper grate), 11-19 fixed-color light categories 1-9 (19 = redstone lamp, its own category since 4.33), 20 texture-color light (candles), 21 concrete powder, 22-28 the seven mineral blocks, 29-43 auto-detected light level 1-15 (`AUTO_EMITTERS`, needs `at_midBlock.w`). The code is always `category + 10`.
- **Block shapes** (`VOXEL_SHAPES`): each vertex ORs the slice it lies in (Y 1/16, X and Z 1/8) into `shapeImg`. `getVoxelBox()` turns the lowest/highest bits into one bounding box per cell; an axis with a single bit (a flat quad) is widened to the whole cell. A **horizontal face also records which side of it the block is on** (4.22): for a face inside the cell (height 1/16 .. 15/16) all Y bits below a top face, or above a bottom face, are set. Without this a slab, dirt path, carpet or snow layer in a floor - which draws only its top face - left a single mark and became a full cell, so the surface the player walks on lay INSIDE the box: rays started inside the block and reached the lights behind it. The rule is not applied to a face at the very top or bottom of the cell (it would say nothing) and a mask that would collapse back to a single bit keeps the face's own bit, so a carpet stays 1/16 (measured 2/16) thick. Measured boxes: slab 0.5, dirt path 0.9375, trapdoor 0.1875, full block 1.0. `shapeEmissionBoost()` brightens small emitters when a GI ray hits them (`EMISSION_SHAPE_BOOST`, capped by `EMISSION_SHAPE_BOOST_MAX`).
- **Solid sides** (`solidImg`, 4.24): one box cannot describe a block shaped like an L. A stair is the lower half of the cell PLUS a step standing on one side of it, so its box is the whole cell and the tread lies inside it. Every face that lies INSIDE the cell therefore also writes, into a second image with the same bit layout as `shapeImg`, the whole side of that axis the block is on; the solid part of the block is the bounding box intersected with the UNION of those sides - for a stair `(y < 1/2) OR (x > 1/2)`, which is the shape exactly. Faces on the wall of the cell say nothing and are left out, and the side is rounded outward, so the stored block is never smaller than the real one. A cell with no face inside it (a full block, a chest, a fence post) has a mask of 0 and keeps its box. `solidEnterDist()` returns the distance at which a ray ENTERS that solid part; a ray that starts inside one of the sides is leaving the surface it sits on and is not stopped by it.
- **Post and arms** (`VOXELIZE_LATTICE`, 4.35): fences, fence gates, walls, glass panes, iron bars and chains are a post in the middle of the cell with up to four arms reaching to its sides; one box around them is the whole cell as soon as an arm exists, which is why they were left out of the grid (fences, bars) or stored as a full cell (walls). `writeLatticeShape()` classifies each vertex: within 0.3 of the middle on both x and z it belongs to the post and ORs its height slice and its distance from the middle (in 1/16, one-hot, the widest wins) into `shapeImg`; further out it belongs to the arm on the side it leans to most, and ORs that arm's bit, its distance across the arm and its height slice into `solidImg`. `latticeEnter()` intersects the ray with the post box and each present arm box (an arm runs from the middle of the cell to its side). No texture is read and nothing depends on block states, so walls without a post, closed fence gates, chains along x or z and modded fences work. An OPEN fence gate does not fit: its leaves lie along two sides of the block, their far ends were read as arms 7/16 wide ("the widest wins"), and the gate became almost a full block that shut out light like a wall. Since 4.44 `block.properties` puts `*_fence_gate:open=true` in the never-voxelized group 1003 and only `open=false` in 1005. Measured with the real writer on Minecraft's model boxes: fence post 6-10/16 and rails 7-9/16 exact, wall post 4-12 and arms 5-11 exact, bars and panes 7-9 exact; heights round up to the next 1/16 and a fence's two rails become one arm from 6/16 to the top, so the gap between them counts as closed (a little more shadow, never a leak). Code 7 stops rays, code 8 multiplies its color into the tint (a pane its glass tint, bars and chains `1 - alpha` of the sprite), code 9 is a full cell that tints everywhere (`1 - alpha`, 0.1-0.9). A light block's face next to one of these still counts as open for the shadow ray's aim point, as before 4.35.
- **Tracers:** `traceVoxels()` is a DDA (Amanatides & Woo) that tests the start cell against the solid sides above (4.24; without them a ray from a stair tread went straight through the step next to it) and then walks cell by cell, testing partial boxes with a slab test, and passes through transmissive and cutout voxels while multiplying their color into a tint. `traceTransmittance()` is the shadow ray for block lights: in the cell the surface itself sits in only a ray that runs INTO the solid part is stopped (4.24; before that the whole box stopped every ray, so a stair tread received no block light at all), light voxels are not occluders, glass tints, cutout voxels use the hole mask (5.2) or a uniform tint without it. Without `VOXEL_SHAPES` every block is a full cube, so the top of a slab, stair, path or farmland lies inside its own cell and that start-cell test stopped every ray (no block light on those floors); 4.44 let a ray go that starts inside the start cell's cube, which also let it out of the wall next to a floor pixel whose start point lay a hair inside that wall (torch light through wall corners). Since 4.45 it is let go only when that cube is the block the surface itself belongs to (`shadowStartInOwnBlock`: the cell just behind the surface is the cell the ray starts in). Both return "no hit" when the ray leaves the grid or runs out of steps. Entity boxes are tested in every cell too (5.16).
- **Rays that start inside a block** (4.45, 4.46). Every caller first steps off the surface into the open (5.4, 5.9), so a start point inside the solid part of a block is an error: the position rebuilt from depth (TAA jitter moves it by up to half a pixel) or an offset tilted into the block next door at a corner. Until 4.44 `traceVoxels()` treated a start inside a full cube as "leaving the surface it sits on" and walked out of the far side of the wall with the light behind it: the bright lines along corners between walls and floors. 4.45 stopped such a ray at t = 0 but lit the spot as the face the ray came from, which for half of all directions is the wall's OUTER face, whose world cache entry (REST) holds the torches outside. Since 4.46 a ray that starts inside the solid part of any block (`insideSolidPart()`: the box and, for an L-shaped block, one of its solid sides) ends there as a black, non-emissive hit, so the path gathers nothing. Leaves are exempt: fancy leaves show the faces between two leaf blocks, and a ray from one of those starts in the leaf block in front of it by design. `traceTransmittance()` does the same for its start cell: `solidEnterDist()` with `blockWhenInside` now also blocks a ray that starts inside a solid SIDE of an L-shaped block (it only did so for box-only cells), so direct light no longer comes out of the step of a stair or the floor of a cauldron (measured with the real `sampleBlockLights()`: a point buried in a stair's step or back half 0.079 / 0.079 -> 0; the tread, the riser and the floor in front unchanged).
- `voxelVolumeFade()` is 1 inside the grid and fades to 0 over the outer quarter; outside, GI falls back to sky ambient x sky lightmap.

### 5.2 Hole mask (`CUTOUT_SHADOW_MASK`)

Cutout voxels (code 6) are created for box-shaped blocks (ID 1004, e.g. trapdoors, doors) whose average alpha is below 0.95, when `TRANSMISSION_FROM_ALPHA` is on; their stored transmittance is `1 - alpha` (at most 0.85). With the mask on, the **shadow fragment shader** marks every texel with alpha < 0.5 of an ID 1004 block in a `CUTOUT_MASK_RES`^2 grid on the face plane (the two axes other than the face normal). `cutoutHoleAt()` reads the bit where a block-light shadow ray crosses the middle plane of the panel. Only holes are marked: a cell with no marked bits counts as solid. The mask is used only by `traceTransmittance()` (and not in composite, `NO_CUTOUT_MASK`); GI and reflection rays see cutout voxels as a uniform gray tint.

- **Panel axis** (`cutoutPanelAxis()`, 4.44): the axis the panel faces is the one with a single shape slice when there is one, otherwise the thinnest side of its box. A panel flat against a side of its block (a ladder) has one slice on that axis, which widens the box to the whole cell, so all three sides were equal and the tie picked z: the mask of a ladder facing east or west was read across the wrong axes.
- **Sun angle** (4.44): holes are recorded by the shadow map's pixels, and a panel seen edge-on from the sun gets none. Where the sun direction is within about 17 degrees of the panel's plane (`|sun[axis]| < 0.3`), the panel passes light evenly by its stored transmittance instead of reading the mask; before, every hole was lost there and torch light through trapdoors and doors came and went with the time of day.

### 5.3 Ray-traced block lights (`sampleBlockLights`, `lib/voxel.glsl`)

- **Light grid** (`LIGHT_GRID`, 4.35, `lib/lightgrid.glsl`): the grid is split into regions of 8 blocks.
  - *Home masks* (shadow pass): the first vertex that touches a light cell (`imageAtomicOr` on `shapeImg` returned 0) sets the cell's bit in the 512-bit mask of its region in `lightHomeImg` and counts it. A region has exactly 512 cells, so nothing overflows and no light is ever left out.
  - *Region lists* (`deferred_a.csh`, one work group of 64 threads per region, dispatched 16384 wide): the home regions around the target are walked ring by ring (Chebyshev rings, only the shell of each cube; at most 6 rings = 48 blocks, and a ring is only started while at most `LG_EVAL_BUDGET` = 4096 lights have been scored). Each home region's score is the sum over its lights of luminance x falloff at the nearest point of the target's box - an upper bound for every pixel in the region. Up to 64 home regions are kept (a 64-bin log histogram drops the weakest), sorted by index, and an alias table (Vose) is built so a pixel draws an entry in proportion to its score with one random number. Each entry also stores its light count and lowest light bit; the build writes the running popcounts of the target's own mask into word 17 of its home record.
  - *Sampling*: `lgDraw()` picks a home region, then one of its lights uniformly (`lgHomeLight()`: at most 4 mask words thanks to word 17; a home region with one light is resolved from the entry alone). Source probability = (score / total) / lights in the home region. The color is read back from the voxel grid (`voxelEmission()`), exactly as a GI hit sees it.
  - *Why home regions*: two earlier designs were measured with the real GLSL on Mesa under a 20 x 20 glowstone ceiling. The best 64 single lights per region, the rest left to GI rays, came out up to 21 % darker than the single list, because a shadow ray and a GI ray do not agree on a light's brightness. A random pool of copies drawn in proportion to score was unbiased but made a whole region's light jump 8-13 % from frame to frame - an error shared by every pixel of the region, which the denoiser cannot remove. The home-region list is identical every frame, holds every light of its home regions, and leaves only per-pixel randomness.
  - *Measured* (Voxel Range 128, 32 frames): with `RT_LIGHT_SOFT_CAP` off the grid and the single list agree within 0.1-0.2 % at every probe under and around the ceiling, and the region-wide frame-to-frame variation is 0.5-0.8 % (sample noise only). Per-sample noise in a room corner 0.26 -> 0.09. A torch drawn after 4096 lava blocks: 0 -> 0.763 at one block. A wall facing a 64 x 64 lava lake: direct light 0 -> 2.96, relative noise 1.06 -> 0.06. With the soft cap on, the grid is up to 9.5 % brighter than the single list at the edges of dense light fields: the cap is applied to each sample, so the noisier single list was compressed more than its real light warranted. Cost on llvmpipe: the per-pixel block-light work is 1.09x the single list in a torch-lit area and 1.30x under the glowstone ceiling; the build pass for a lava lake of 4096 lights took 0.17 s against about 25 s for the GI work of one 1080p frame, i.e. well under 1 %.
- **Without the grid** (`LIGHT_GRID` off): one global list of light cells in `lightImg` with its counter in the last texel (one image since 4.44, see 4.2), entries past `MAX_RT_LIGHTS` (1024) dropped in the order the GPU processes the shadow-pass vertices; candidates drawn uniformly; the color is read back from the voxel grid like the grid does. Measured against the grid with the real `sampleBlockLights()` on Mesa: a torch at 1, 5 and 20 blocks gives identical values (0.7628, 0.0174, 0.0003).
- **RIS:** `RT_LIGHT_SAMPLES` candidates (golden-ratio stratified). Candidates farther than `RT_LIGHT_RANGE` or behind the surface get weight 0. Target = luminance(color) x N.L x falloff, with falloff `1 / (1 + d^2 x RT_LIGHT_FALLOFF)` and a soft cutoff over the last 45 % of the range. Weight = target / source probability; one candidate is kept in proportion to its weight; the result is `color / luminance(color) x visibility x weightSum / candidates x RT_LIGHT_STRENGTH`.
- **Soft shadows:** the sample point is jittered inside the light's measured box (x `RT_LIGHT_SIZE`; 0 = no jitter), so a torch casts a sharp shadow and glowstone a soft one, and is then moved onto the box FACE that the shaded surface sees - skipping faces whose neighbouring cell is occupied, because the side faces of a block in the middle of a glowstone ceiling are covered by its neighbours. Aiming at a point inside the emitter made the last stretch of the ray run inside a ceiling or lake of light blocks, where its neighbours shadowed it. The step budget is `1.8 x length + 3`, at most 256.
- **Occluders (`traceTransmittance`, `shadowCellBlocks`):** every cell is tested with its box, so a ray can miss a partial shape. Two rules were fixed in 4.21:
  - **A light block is a solid block.** Only the cell of the source being sampled (and anything within a block of it, so a lava lake or a lamp cluster does not shadow itself) lets the ray pass. Before, EVERY emissive voxel was skipped, which turned a glowstone ceiling or wall into a window: its light reached everything behind it, and since Minecraft never draws the blocks buried inside a solid mass (no visible face, so nothing about them reaches the grid) that light then spread through the whole mass and came out of the surfaces above it.
  - **The cell the surface itself sits in is tested.** The DDA starts at the next cell boundary, so it skipped that cell. On a partial block (slab, path, carpet, trapdoor, stairs) the visible surface lies inside its own cell, so the block did not shield its own surface. It is now tested for rays that ENTER the box (`tEnter > 0.002`); a ray leaving the face it starts on is unaffected.
- **Start point of the shadow ray:** `voxelPos + offsetNormal x 0.02`, where the offset normal is `neeOffsetNormal` when a caller has set it, else the normal passed in (which is also the one used for N.L). The GI pass sets the flat, camera-facing normal of the pixel for the one call from the pixel itself (4.46; `giTracePath()` clears it again): the normal-mapped N it used before could push the start point into the block next door at a corner (measured at 1280x720 in a closed room: 6.1 % of the corner pixel-frames started inside a block, now none). Hits (bounce, reflection) pass their axis-aligned face normal.
- **Where it is called:** at the pixel (deferred), at the first GI bounce hit (deferred), and at reflection hits (composite, `REFLECTION_BLOCK_LIGHT`). The pixel and bounce samples are part of the GI radiance in colortex3, so they are temporally accumulated, denoised, scaled by `GI_STRENGTH` and `GI_SATURATION`, and limited by `GI_FIREFLY_CLAMP` like the rest of GI. Because the sampling sits inside `#ifdef GI_ENABLED` in `deferred.glsl`, turning GI off also removes ray-traced block light from visible surfaces.
- GI rays that hit an emissive voxel add its emission only when the shadow ray could NOT have picked that light (`giEmissionScale()`, 5.4).
- Vanilla block light is kept as a base: inside the grid it is scaled by `LIGHTMAP_RT_BLEND`, which is **0.0** by default, so inside the ray traced area block light is ray traced only.

- **Cluster limit** (`RT_LIGHT_SOFT_CAP`, 4.29): the RIS sum (the unshadowed contribution of every source in range) is bent over with `sum * inversesqrt(1 + (sum/cap)^2)`, default cap 3.0, 0 disables it. Lamps add up linearly, so measured on a floor 4 blocks below: one glowstone 0.259, 3x3 2.02, 9x9 8.85, 21x21 15.00 (58x one block). After the limit: 0.258 / 1.96 / 6.10 / 6.32, a torch at 5 and 20 blocks unchanged at 0.0189 and 0.0003, a lava lake from above 26.7 -> 8.2.
### 5.4 GI path tracing (`program/deferred.glsl`)

1. Skipped for sky, `MAT_UNLIT` and `MAT_HAND` pixels. On a `MAT_ENTITY` pixel the flat face direction is read from colortex2.g and handed to the tracer (`entityStartNormal`), so the rays that start on the entity know which way is out of it (5.16); on `MAT_ENTITY_EMISSIVE` the pixel's own normal stands in. It is cleared after the path's first ray.
2. **Start point** (4.45, 4.46): `surfaceVoxel = playerPos + flatN x 0.02 - normalize(playerPos) x (0.005 + pixelSize)`, where `pixelSize = 2 x distance / (gbufferProjection[1][1] x viewHeight)` is the size of one pixel at that distance and `flatN` the flat normal rebuilt from depth (`geometricNormal()`, lib/space.glsl) when normal maps or POM are on. The offset went along the normal-mapped N until 4.44, which tilts by tens of degrees at the default Bump Depth, so on a floor right at a wall a texel leaning towards the wall put the start point inside the wall. The step back towards the camera takes the point out of anything the position rebuilt from depth has pushed it into: the camera sees the point, so the way back to it is open. `geometricNormal()` chose its side by agreement with N until 4.45; where the neighbors of a floor pixel at a wall give the WALL's direction, that flipped the flat normal into the wall on every texel leaning towards it (a sixth of the corner pixels at Bump Depth 4), one start point in the wall per texel - the rows of orange dots along corners. Since 4.46 the flat normal always faces the camera. Measured with the real passes on Mesa in a closed room with torches outside (Bump Depth 4, TAA jitter): at 1280x720 the start point was inside a block in 2.9 % of the corner pixel-frames with 4.45 (1365 corner pixels at least once) and in none with 4.46; the problem grows with resolution, because the step back is one pixel.
3. Block light is sampled at the surface (5.3).
4. A cosine-weighted ray is traced with `GI_MAX_STEPS` / `GI_MAX_DISTANCE`. At a hit, `shadeVoxelHit()` adds sun bounce (single shadow-map tap, x `GI_SUN_BOUNCE`, Overworld only), sky ambient (`GI_HIT_AMBIENT` on the last bounce only, + a small constant) and emission. Throughput is multiplied by the hit albedo (and by any glass passed); the path stops below 0.015.
5. On the first bounce, block light is sampled at the hit point. Each later bounce halves the steps (minimum 8) and the distance.
6. A miss (sky, out of steps, or out of the grid) adds `getSkyRadiance()` x `GI_SKY_STRENGTH` x the pixel's sky exposure.
7. The total radiance is clamped to luminance `GI_FIREFLY_CLAMP`, then blended with the sky-ambient fallback by `voxelVolumeFade()`.

The path is `giTracePath()` / `giTraceBounces()` in `lib/gipath.glsl`, shared with the world cache. Leak prevention (`LEAK_FIX`): sun terms use `smoothstep(0, 0.35, skyLight)`, sky terms `skyLight^SKY_LIGHT_CURVE`, taken from the pixel's vanilla sky lightmap (in the cache: the face's own sky light, 5.4.1). Random numbers are PCG3D of `(pixel.x, pixel.y, frameCounter)`; `DEBUG_FREEZE_NOISE` sets the frame to 0.

- **Half resolution** (`GI_HALF_RES`, 4.36, on in the Low profile): `scale.deferred = 0.5` makes Iris draw the pass into the lower-left quarter of colortex3. Each of its pixels stands for a 2x2 block of real pixels and traces one of them: `giHalfSlot()` / `giHalfStart()` (`lib/common.glsl`) try the four in the order (0,0), (1,1), (1,0), (0,1), starting one further every frame and at a hashed place in every block, so each pixel is traced once every four frames and neighbouring blocks never all pick the same corner; a sky or hand pixel is skipped for the next one. The G-buffer is read at the traced pixel and the alpha of colortex3 records which one it was (1-4, 0 = none). Measured with the real deferred + deferred1 passes on Mesa (640x360, 128 frames, static camera): the pass takes 0.27x the time, the converged mean differs by +0.1 %, the median per-pixel difference is 2.2 % on flat surfaces and 3.5 % at depth/normal edges (both mostly the remaining sampling noise of the two runs), no surface pixel is left black, the result is not shifted (every 1-pixel shift compares worse), and the frame-to-frame noise left in the history is lower than at full resolution (0.6 % against 1.4 %) because each pixel blends several samples. While the camera turns: -0.4 %, no black pixels.
- **No double counting of emitters** (4.31, extended in 4.34 and 4.35): `shadeVoxelHit()` takes an `emissionScale` from `giEmissionScale(neeOrigin, hit)`: 1 when the shadow ray sent from `neeOrigin` could not have picked the light (with the grid: its home region is not in the origin region's list, `lgCovered()`; without it: the list overflowed), otherwise `smoothstep(0.55 R, R, distance)` - the window in which the shadow ray's own falloff dies out. It is applied on bounce 0 (from the surface) and, since 4.35, on bounce 1 (from the first hit, where a shadow ray is sent as well); from the second hit on no shadow ray was sent and the emission stays. The first-hit shadow ray uses its own random numbers, independent of the ones that pick the next direction. NEE already paid for those sources, and the second helping was multiplied by `shapeEmissionBoost` (up to `EMISSION_SHAPE_BOOST_MAX` = 6) for small emitters. Measured on a wall 1 block from a torch: direct 0.434, duplicate indirect 1.387 -> 0.060; totals 1 block away torch 1.82 -> 0.49, glowstone 1.65 -> 0.62, lava 3.22 -> 1.13; at 8 blocks all three are unchanged. Reflections and later bounces keep the emission (no shadow ray is sent from there).

#### 5.4.1 World space GI cache (`WORLD_SPACE_GI`, 4.37, `lib/gicache.glsl`, `program/gicache_update.glsl`)

Every exposed block face within `GI_CACHE_RADIUS` blocks (at most 32) of the camera keeps its own indirect light, whether it is on screen or not. It is read in two places: `deferred1` seeds a pixel that has no history with it (5.5), and `deferred` reads the rest of a path from it once the path's first ray has hit a face that has an entry (`GI_CACHE_BOUNCES`).

- **Two values per face**, both computed with the screen's own path code (`lib/gipath.glsl`), so that nothing drifts when a pixel's own samples take over:
  - *SEED* (value 0): the whole GI of a pixel standing on that face - the shadow ray to the block lights, then `GI_BOUNCES` bounces with a shadow ray at the first hit - with the pixel's firefly clamp.
  - *REST* (value 1): what a pixel's path still gathers after it has hit that face and sent the shadow ray from there: `giTraceBounces(firstBounce = 1)` - `GI_BOUNCES - 1` more bounces, traced as short as those bounces are on screen, no shadow ray at the start, the emission of the first light it lands on scaled by `giEmissionScale()` from the face (5.4), `GI_HIT_AMBIENT` on its own last bounce. `deferred` adds `throughput x REST` and stops; the first bounce, its shading and both shadow rays stay live every frame. With `GI_BOUNCES = 1` nothing follows the first hit, so `GI_CACHE_BOUNCES_ACTIVE` is not defined.
  The cache's own paths never read the cache: light is not fed back into itself.
- **Layout**: 64^3 cells, toroidal (`cell = world & 63`), 6 face entries per cell. The meta word holds a 6-bit tag (the world "lap", 2 bits per axis), the update count and the frame of the last update; an entry is valid when the tag matches, it has at least one update, it is younger than 120 frames and not older than the epoch. REST is used only from 4 updates on (`GI_CACHE_REST_MIN`): a face traced once or twice is still noisy, and every pixel whose ray lands on it would share that error.
- **LIST** (`deferred_b.csh`, 64^3 threads): a cell inside the radius that holds a block (not glass, fence, pane or cobweb - those have no entries) checks its six faces; a face is exposed when its neighbour is air, glass, a cutout block, a fence / pane / cobweb, or a partial shape, or when the face lies inside its own cell (a slab top). Leaf faces looking at leaves do not count. The scan order shifts every frame. **Budget**: with T exposed faces last frame the faces are split into `ceil(T / GI_CACHE_BUDGET)` phases (at most 32) by a hash of their world position, so each face is updated exactly once every N frames. Thread 0 also does the **teleport check**: a camera jump of more than 32 blocks or a gap in the frame sequence moves the epoch to the current frame, which invalidates everything written before (the tag alone repeats every 256 blocks). Otherwise the epoch follows `GI_CACHE_STALE` frames behind the current one once it is older than that (4.44): ages are counted modulo Iris' frame wrap (720720), so an epoch left alone for 720720 frames read as age 0 again and the whole cache was dropped at once, about every 3.3 hours at 60 fps.
- **TRACE** (`deferred_c.csh`, one thread per listed face up to the budget): `GI_CACHE_RAYS` paths from random points on the face (kept inside the cell, 0.02 in front of it), each giving one SEED and one REST sample, blended in with weight `1 / min(count + 1, GI_CACHE_FRAMES)`.
- **Sky light**: a face has no lightmap, so the shadow vertex shader adds the sky light of every vertex (`gl_MultiTexCoord1`, raw 0-240 values rescaled) into the air cell in front of its face (`giSkyImg`, atomic sum + count, so the result does not depend on draw order; slanted faces such as plants are skipped). A cell nobody wrote to takes its brightest neighbour minus one level. If the whole region reads zero while the player stands in the open (Iris not delivering the lightmap in the shadow pass), the player's own sky light is used instead.
- **Lookups**: REST reads the single entry of the hit face (`floor(hitPos - n x 0.01)`, dominant axis of the hit normal). SEED blends the four entries around the point across the face plane, weights renormalized over the valid ones, and gives up below 25 % coverage; the face is found from the geometric normal rebuilt from depth when normal maps or POM are on (`giGeometricNormal()`), and a plant pixel falls back to the top of the block below it.
- **Measured** with the real `deferred_b`, `deferred_c`, `deferred` and `deferred1` on Mesa llvmpipe (`gicache_test.py` in the scratchpad: 320x180, a walled yard with a roofed half and a closed hall with a skylight, a real shadow map, 96-128 frames):
  - Cache off is 4.36: colortex3 compared at frames 3, 7 and 12 - no pixel differs in two, one pixel by one 16-bit rounding step in the third.
  - SEED against the converged screen GI: -0.16 %. (The converged screen image itself sits 1.6 % lower in the yard because the spike filter trims it.)
  - Later bounces from the cache against traced ones, same random first bounce: hall with uniform sky light -0.04 % (floor 0.0 %, walls -0.3 %); torch-lit hall at night +0.17 % (the emission rule holds); 3 bounces -0.25 % daylight, +0.9 % torch-lit (the REST samples are clamped on their own and lose less to the firefly clamp). Where the sky light changes between surfaces (under the roof next to the skylight) the floor comes out -3.3 % and the walls +0.7 %: REST uses each face's own sky light, the traced path used the pixel's. Raw one-sample noise in the hall 188 % -> 153 %, with 3 bounces 145 % -> 126 %; in the sunlit yard and in the torch-lit hall, where the direct terms dominate, it hardly changes. GI pass time 0.59x-0.84x.
  - Camera cut by 180 degrees after 48 frames: median error of the accumulated GI in the first frame after the cut 87 % -> 22 % (hall), 95 % -> 13 % (yard). Without the cache the hall also came up 44 % too dark (the spike filter trimming the few bright first samples) and was still 8 % too dark 24 frames later; with it the mean starts 5 % above the spike-trimmed reference and settles onto it.
  - Walking at 0.15 blocks per frame through the hall: at the last frame the accumulated GI was 37 % too dark (median per-pixel error 51 %) without the cache and 3.5 % (21 %) with it; in the bright yard at 0.1 blocks per frame -2.1 % (5.8 %) against +0.5 % (5.4 %).
  - Cost: 0.0016 s for the list and 0.014 s for tracing 9248 faces with 2 paths each, against 0.015 s for the GI pass at 320x180. A 1080p GI pass has 36x the pixels, so the cache costs about 3 % of it, while reading the later bounces saves 16-41 % of it.

### 5.5 Temporal accumulation and denoising

- **Half-resolution upsampling** (`GI_HALF_RES`): before accumulating, `deferred1` gathers the traced samples of the pixel's own 2x2 block and the eight around it and weights each by the distance to the traced pixel (`exp(-d^2 / 4.5)`, in full-resolution pixels), by the distance off this pixel's surface plane (the same `0.06 + 0.012 x distance` tolerance as the other filters) and by `pow(N.N', 8)`. With no matching sample (a thin edge whose neighbours are other surfaces) a pixel that has a history keeps it unchanged and does not count the frame; one without history starts from the samples weighted by distance alone.

- `deferred1`, **spike removal** (`GI_SPIKE_FILTER`, `GI_SPIKE_TOLERANCE`, 4.24, reworked in 4.25 and 4.44): AFTER the blend, the accumulated value's luminance is compared with the 8 neighbors of the history (colortex4) around the REPROJECTED position, each of which must pass the history's depth test against colortex7 (at twice its tolerance), and clamped to `max(mean + GI_SPIKE_TOLERANCE x deviation + 0.02, luminance(own history))`; with fewer than 3 valid neighbors (or off the previous screen) the filter stays out. Until 4.44 the neighbors were read around the pixel's current position in the old picture, which held something else whenever the camera moved: next to the sky (stored as 0) a newly revealed pixel got a limit of 0.02 and started dark, climbing back over dozens of frames (simulated: half its light after 10 frames, 10 % short after 40), which drew dark patches wherever terrain came into view beyond the world cache. One ray per pixel means a ray that reaches a light through a gap leaves a point tens of times brighter than its surroundings, which the a-trous filter keeps because it reads as a luminance edge; dark rooms then fill with star-like dots. 4.24 did this on the RAW frame, which is wrong: where only a fraction p of the rays find any light, nearly all the light is in those few samples. Simulated over 300 frames (true value T, hit probability p, unbiased sample T/p, 24 accumulation frames), light kept: raw 0.50 at p=0.1 and 0.20 at p=0.03, accumulated 0.98 and 0.74, with a lower peak pixel in both cases. The floor at the pixel's own history keeps surfaces that are simply brighter than their surroundings from being pulled down.
- `deferred1`: reprojects with the previous camera matrices and reads the history bilinearly, testing each of the 4 taps against colortex7 (tolerance `expectedDepth x GI_TEMPORAL_DEPTH_TOLERANCE x 0.15 / facing + 0.08`, where facing is `|flatN . view|`, at least 0.15, since 4.34). `flatN` is the flat normal rebuilt from depth (`geometricNormal()`, lib/space.glsl; facing the camera since 4.46, see 5.4) when normal maps or POM are on (4.44): with the bumped normal a texel tilted towards the camera made the test three times stricter on a floor seen edge-on, and far floors lost their history texel by texel. Blend weight `1/frames`, frames capped at `GI_TEMPORAL_FRAMES`. NaN/Inf history is reset.
- **Stochastic rounding** (4.44): colortex4 is RGBA16F, whose values near 1.0 are 1/1024 apart. With `GI_TEMPORAL_FRAMES` at 128 or more a frame's step `(new - old) / frames` was smaller than half of that and was rounded away (measured: the history stuck at 1.14 / 1.08 / 1.00 while chasing 1.2 at 128 / 256 / 1024 frames). A random offset of up to half a half-float step is added before the write, so the rounding goes up or down in the right proportion and every step arrives on average; the added noise is 0.05 %.
- `deferred1`, **seeding from the world cache** (`WORLD_SPACE_GI`, `GI_CACHE_TRUST > 0`, 4.37): a pixel without usable history starts from the SEED of its face (5.4.1) and counts it as `min(GI_CACHE_TRUST, updates x GI_CACHE_RAYS)` frames of history; it then counts as having history, so the spike filter's floor applies to it. The face is found from `flatN`; a plant keeps its N (gbuffers_solid points it straight up) and is looked up on the top of the block below it - with the flat normal of a cross-shaped plant (horizontal) the lookup found the side of a block or nothing, until 4.44. The per-face value has no per-pixel detail (the darkening in a corner, a sharp shadow edge); the frames that follow bring it back.
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
- **Metals:** with `RT_REFLECTIONS` and `BLOCK_REFLECTIONS` the diffuse term of metals is multiplied by `1 - metalness` (the reflection fade-in over smoothness); their color comes from the reflection in composite, which ADDS it for metals instead of blending (5.9) and also adds it behind glass and water (4.44). The metal flag and smoothness go to composite packed in colortex6.a (`encodeReflectInfo`).
- **Entities** (`MAT_ENTITY`, `MAT_ENTITY_EMISSIVE`) and the hand get a smoothness of 0 in colortex6, so composite traces no reflection for them; their sun highlight stays. `MAT_ENTITY_EMISSIVE` is lit like `MAT_EMISSIVE`.
- Sky pixels get `getFullSky()`: sky gradient + sun disc + stars/moon from gbuffers_sky + volumetric clouds.

### 5.7 Materials (`program/gbuffers_solid.glsl`)

- Material from the block ID: plants (normal forced up), leaves, emissive categories, polished / concrete / minerals (`POLISHED_SMOOTHNESS`, F0 0.04), metal (`METAL_SMOOTHNESS`, F0 1.0). For an emissive mineral block or concrete powder the pass also computes the **surface gain** (`mineralSurfaceGain` from the mip-4 sprite average at `mc_midTexCoord`) and writes it into the terrain albedo alpha, which is why `blend.gbuffers_terrain.colortex0` is off and the damaged-block blend keeps the alpha. `LABPBR` overrides smoothness/F0 from `_s` red/green; `LABPBR_EMISSION` reads `_s` alpha (255 = none) into emission IDs 24-255.
- **Entities** (4.42-4.44): `gbuffers_entities` and `gbuffers_block` write `MAT_ENTITY` (or `MAT_ENTITY_EMISSIVE` for a LabPBR-glowing part) and put the flat face direction into colortex2.g (`encodeNormal8`, 4 bits per axis of the octahedral map: 5 degrees for most directions, 15 at worst); a two-sided part seen from behind (golem vines, banners, the outer skin layer) gets its normal turned towards the camera first. Entities, block entities and the hand keep F0 at 0.08 at most and turn metal (F0 > 0.9) into 0.04: a metal hands its color to the reflection, which cannot see entities and never settles on a moving mob, and an iron golem or iron armor from a LabPBR pack looked see-through and grainy (4.42 caught metal, 4.43 the high non-metal values and the reflection itself).
- **Normal maps** (`MATERIAL_NORMALS`, ported from 4.18, default `NORMAL_STRENGTH` 4.0): the `_n` rg normal is used only if its slope is between 0.004 and 0.999 (Iris's flat default texture is rejected), scaled by `NORMAL_STRENGTH`, and only if the result faces the same side as the geometric normal. A missing tangent (`tbnValid`) disables it.
- **Parallax** (`MATERIAL_POM`, ported fix): `POM_STEPS` march steps (default 32) through `_n` alpha within `POM_DISTANCE`, optional `POM_SMOOTH` interpolation. `wrapInSprite()` **clamps** the coordinate to the sprite instead of wrapping it with `mod()` (no repeated copies), and the total shift `0.12 x POM_DEPTH x tan(angle)` (atlas UV) is limited to **0.9 x the smaller sprite half size**. With typical atlas sizes that limit is reached a few degrees away from the normal, so the displacement is mostly the clamped length. There is no depth offset and no self-shadowing.

- **Parallax** (`MATERIAL_POM`, 4.27): the shift is `(tv.xy / max(tv.z, 0.25)) x POM_DEPTH x 0.25 x spriteSize`, i.e. measured in SPRITES. Before 4.27 the sprite size was missing and the constant was 0.12 in atlas units, which for a 16 px sprite in a 512 px atlas is 3.8 sprites; the `0.9 x spriteHalf` cap then flattened every direction to the same maximum from 6.7 degrees off the normal onward, which read on screen as a lens centered on the view direction and made `POM_DEPTH` do nothing. The cap is now one sprite (reached at 76 degrees), `wrapInSprite()` wraps with `mod` instead of clamping (block textures tile), the march keeps an unwrapped offset so `POM_SMOOTH` never interpolates across a border, and every sprite read (`gtexture`, `normals`, `specular`) uses `textureGrad` with the derivatives of the ORIGINAL coordinate so a wrap cannot force the blurriest mip. `POM_DISTANCE` fades over its last 30 % instead of cutting off.
### 5.8 Shadows (`lib/shadows.glsl`)

Distortion `clip.xy / (|clip.xy| x SHADOW_DISTORTION + 1 - SHADOW_DISTORTION)`, shared by the shadow pass and all readers. `shadowFiltered()`: normal offset of one texel x (`SHADOW_BIAS` + more at grazing angles), `SHADOW_SAMPLES` Poisson taps (12-point disk reused with rotation) rotated per pixel by interleaved gradient noise, radius `SHADOW_SOFTNESS`, fade at the end of the distance (`SHADOW_EDGE_FADE`). **Colored shadows** (`COLORED_SHADOWS`): where shadowtex1 is lit but shadowtex0 is not, the occluder is translucent and `shadowcolor0` (written without blending, a = translucent flag) tints the light by `SHADOW_TINT_BRIGHTNESS`. `shadowSingle()` is the one-tap version used at ray hits and on forward surfaces. Tinted glass (4.44) writes a black filter (`shadowcolor0 = (0, 0, 0, 1)`), so it stops the sun like an opaque block while `COLORED_SHADOWS` is on (it is drawn in the translucent layer, so shadowtex1 never holds it). A program short of texture units defines `NO_COLORED_SHADOW_TINT` (composite): shadowtex0 and shadowcolor0 are then not bound there and the sun is untinted.

### 5.9 Reflections (`program/composite.glsl`, ported from 4.18)

- **`REFLECTION_MODE`** is the only reflection option in the menu: 0 off, 1 screen space only, 2 voxel ray tracing + screen fallback. The end of `lib/settings.glsl` turns it into the internal switches `RT_REFLECTIONS` and `SSR_FALLBACK`, which the code reads.
- `traceReflection()`: (1) voxel ray (`REFLECTION_STEPS`, `REFLECTION_MAX_DISTANCE`); if the hit is on screen and not covered (`REFLECTION_SCREEN_LOOKUP`) the textured pixel is used, otherwise the voxel is lit with `shadeVoxelHit` (its texel from the atlas with `VOXEL_TEXTURES`, 5.15, else its flat color) plus a block-light sample (`REFLECTION_BLOCK_LIGHT`); (2) screen-space march with binary refinement (`SSR_FALLBACK`, `SSR_MAX_STEPS`, `SSR_THICKNESS`); (3) sky with clouds.
- **Water and glass:** Schlick Fresnel on F0 0.02 (water, not while underwater) and 0.04 (glass, x `GLASS_REFLECTION_STRENGTH`).
- **Opaque surfaces** above `REFLECTION_MIN_SMOOTHNESS`: the Fresnel term is capped by roughness (`max(1 - roughness, F0)`), so a rough surface seen at a grazing angle no longer turns into a mirror. The normal is jittered by `ROUGH_REFLECTION_JITTER x roughness` with a seed that **changes every frame**, and the reflection REPLACES the surface color by its weight instead of being added (energy conserving).
- **Reflection denoiser** (`REFLECTION_DENOISE`, off by default, on the Denoiser page): the reflection of the previous frame is reprojected from the surface position out of `colortex11` and blended in with `1 / REFLECTION_TEMPORAL_FRAMES`, scaled by roughness so mirror-smooth surfaces are never averaged. History is thrown away when the reprojected depth differs by more than `REFLECTION_DENOISE_TOLERANCE`. The history is written even when the denoiser is off.
- **Refraction** (`WATER_REFRACTION`, `GLASS_REFRACTION`): the offset uses a fixed assumed thickness (`WATER_REFRACTION_DEPTH`, `GLASS_REFRACTION_DEPTH`) faded out as the surface is viewed head-on, never the real distance to whatever is behind it - that turned water and glass into a magnifying lens.

- **Modes** (4.26): `REFLECTION_MODE` 1 (screen space) and 2 (ray traced) both call `traceReflection()`; the voxel step inside it is compiled only for mode 2 (`RT_REFLECTIONS`), the screen-space march only for modes 1 and 2 (`SSR_FALLBACK`). Before 4.26 the call sites themselves required `RT_REFLECTIONS`, so mode 1 produced no reflection at all on blocks and only the sky on water, while the voxel step ran unconditionally inside the function.
- **Miss handling** (4.26): `traceReflection()` reports whether it found anything. On a miss the opaque reflection weight is multiplied by `skyExposureFromLightmap(lmSky)`, so indoors, where the sky fallback is black, a polished or metal block keeps its own color instead of being painted black.
- **Rough reflections and flicker** (4.28): each frame the normal is jittered by `ROUGH_REFLECTION_JITTER x roughness` so a rough surface gathers a blurred reflection over time. `REFLECTION_DENOISE` is now ON by default and the accumulation ramp is `saturate(roughness x 16)` (was x 8), so the frame-to-frame difference drops from 0.0097 to 0.0033 on polished and mineral blocks (smoothness 0.82) and from 0.0235 to 0.0059 on metal (0.72). With the denoiser off, that difference is shown directly and reads as shimmer.
- **Light on a reflected block** (4.28): `shadeVoxelHit()` is called from the reflection with `ambientScale = 1.0` instead of `GI_HIT_AMBIENT` (0.15). GI_HIT_AMBIENT belongs to the last bounce of a GI ray, where the surface already carries the light of every bounce before it; a reflection has no history, so that was all the light the reflected block ever got. A white surface in open shade, direct view counted as 1.00, came out 0.11 in a reflection and now comes out 0.62.
- **Metal and the miss fade** (4.28): the 4.26 fade is skipped for metals (LabPBR F0 > 0.9; composite reads the flag from colortex6.a since 4.44). `lighting.glsl` removes a metal's diffuse color (`metalness`), so fading its reflection away left black.
- **Reflection normal** (`REFLECTION_NORMAL_STRENGTH`, 4.29): the geometric normal is reconstructed once per pixel in uniform control flow as `cross(dFdx(viewPos), dFdy(viewPos))` (exact on block faces) and the reflection ray uses `mix(geoNormal, N, REFLECTION_NORMAL_STRENGTH)`, default 0.25, only where `dot(geoNormal, N) > 0.25`. With `NORMAL_STRENGTH` 4.0 a single texel's normal tilts by tens of degrees and a mirror doubles it, which tore reflected geometry apart. Lighting still uses the full mapped normal.
- **Stable rays without the denoiser** (4.30): the per-frame jitter seed is `frameCounter * 747796405 + 7` only while `REFLECTION_DENOISE` is defined; with the denoiser off the seed is a constant, so a pixel keeps the same ray every frame and detailed normal maps stop flickering.
- **Specular AA** (`SPECULAR_AA`, `SPECULAR_AA_MAX`, 4.30): `normalVariance = 0.5 (|dNdx|^2 + |dNdy|^2)` of the shading normal, measured once in uniform control flow, widens the GGX alpha in `lighting.glsl` and the reflection roughness in `composite.glsl` by `min(2 x variance, SPECULAR_AA_MAX)`.
- **Sharpening** (`REFLECTION_SHARPEN`, `REFLECTION_SHARPEN_STRENGTH`, 4.30): after the temporal blend, `reflection + (reflection - average of 4 history neighbours) x strength`, applied to the output only; colortex11 keeps the unsharpened value so the effect cannot accumulate.
- **Frame-stable reflections** (4.31): the `REFLECTION_BLOCK_LIGHT` sample inside `traceReflection()` uses a constant seed when `REFLECTION_DENOISE` is off, like the ray jitter since 4.30. A per-frame seed without anything averaging it is shown to the viewer directly and reads as twinkling on polished and metal blocks.
- **Textured hits** (4.38): a voxel hit reads the block's own texel from the atlas (5.15); a ray that meets a hole in a leaf texture goes on (at most two holes).
- **Entities** are not traced by reflections (`NO_ENTITY_TRACE` before `lib/voxel.glsl`): a mob as boxes would look wrong in a mirror, and the screen-space fallback shows the real mob when it is on screen. Entity pixels themselves get no reflection (5.6).
- **Start point** (4.46): the voxel ray starts at `playerPos + n x 0.05 - normalize(playerPos) x (0.005 + pixelSize)`. For opaque surfaces `n` is the flat, camera-facing normal from `geometricNormal()` (5.4); it was the reflection normal `Nr`, which at the very edge of a block (where the quad derivatives mix two faces and `geoNormal` is rejected) is the full normal-mapped N, so a texel leaning towards the wall next to it started the ray inside that wall. Water and glass pass their own normal as before. A ray that starts inside a block anyway (a black hit at distance 0, 5.1) returns black: no screen lookup, no sky.
- **Fog on what a reflection shows** (4.44, `fogReflected()`): screen-lookup, screen-march and voxel hits get the distance fog they would have if seen directly, at the hit's position (the reflected content came from before the fog, so a lake mirrored the hills at the render edge crisp under the fogged real ones). Not while the camera is under water.
- **Metal behind glass and water** (4.44, `metalBehindTranslucent()`): the opaque branch only ran where nothing translucent was in front, so a metal block at the bottom of a pool or behind a window kept nothing but its sun highlight and was black. In the translucent branch a metal pixel behind the surface now traces its own reflection (voxel trace only: the depth buffer holds the glass or water in front) and adds it, scaled by how much of it the surface lets through (`1 - WATER_SURFACE_OPACITY`, or the glass opacity from colortex5.b); for water from above this happens after the underwater light and before the absorption.
- **Metal is added, not blended** (4.44): lighting.glsl already takes `metalness` of a metal's color out, so composite adds `reflection x weight` for metals instead of `color x (1 - weight) + ...`; a LabPBR metal of smoothness 0.35-0.7 lost its color twice and was up to a fifth too dark.
- **Glass Reflection Strength** above 1 no longer overshoots: the blend factor is capped at 1 (4.44).
- **Reflection denoiser** (4.44): the history is read as four texels around the reprojected position, each tested for "holds a reflection" (a > 0) and for the depth, and renormalized - a filtered read blended in neighbours that were black with a depth of -1, which drew a dark outline around shiny blocks while the camera moved. The sharpening reads its four neighbours around the same reprojected position (it read them around the current pixel, which trailed false edges behind reflected edges while turning).
### 5.10 Water and translucents (`gbuffers_water.glsl`, `lib/water.glsl`, `composite.glsl`)

- `gbuffers_water.glsl`: forward-lit with `lib/forward.glsl` (lightmap + one shadow tap), no GI and no ray-traced block light. Water top faces get the wave normal of `waterNormal()`; the water color is `biome tint x 0.06 x light` with alpha `WATER_SURFACE_OPACITY`. Glass writes type "glass" as `0.3 + 0.4 x opacity` into colortex5.b (4.44; composite needs the opacity for metal behind glass). Translucent emitters (Nether portal) write their own glow and translucent type 0 so they are not reflected.
- **Waves** (4.40): three layers of quintic value noise (curvature continuous, so caustics show no grid lines) scrolling in different directions, each turned by its own angle (`WAVE_ROT1/2`), plus a long sine swell; `WATER_WAVE_STRENGTH / SPEED / SCALE`.
- **Caustics** (`WATER_CAUSTICS`, 4.40): sunlight entering the surface is refracted by the wave normal and followed down to the depth of the point; the brightness is the ratio of the area of a small triangle of three rays on the surface to its area on the floor (`waterCaustics()`), with a correction step towards where the ray that lands on the point really entered, a triangle that grows with depth (the sun is a disk), per-color refraction (`CAUSTICS_DISPERSION`) and a depth normalization: past the focal depth rays of neighbouring lenses cross, and the mean measured on Mesa (1.0 at the focus, 1.4 at twice, 1.9 at five times that depth) is divided out while deep water gets softer patterns. The caustic field is the surface's without its finest layer at full strength and without the sine (they drew half-block cells and stripes). Floor brightness over a patch stays within 0.93-1.02 at every depth. `CAUSTICS_STRENGTH`, `CAUSTICS_FOCUS` (depth scale). Only where the sun reaches past the opaque blocks (shadowtex1) and not in rain.
- **Water surface map** (`waterImg`): the shadow vertex shader writes the height of every top water face into its column (`imageAtomicMax`), so any point under water knows its depth (`waterSurfaceAt()`).
- **From above** (composite): refraction (`WATER_REFRACTION`, offset clamped, only background pixels used), caustics and depth light on the floor (`underwaterSurfaceLight()`), metal on the floor gets its reflection (5.9), then absorption `exp(-(0.45, 0.14, 0.10) x WATER_ABSORPTION x thickness)` plus in-scattered water color (`WATER_SCATTER`), then the surface reflection (Schlick F0 0.02) and the sun highlight.
- **Depth absorption** (`UNDERWATER_DEPTH_LIGHT`, 4.40): sun and sky light on a surface `depth` blocks under the water lose `exp(-extinction x 0.35 x depth)` (red first), weighted by the surface's sky light, so a deep floor is lit blue and torches keep their color.
- **Around the camera under water**: absorption `exp(-extinction x distance)` with extinction `(0.30, 0.08, 0.05) x UNDERWATER_FOG_DENSITY`, sky light scattered in with the biome water color (`UNDERWATER_BIOME_TINT`), and with `UNDERWATER_VOLUMETRIC` the sun marched along the view ray (`underwaterShafts()`): `UNDERWATER_VL_STEPS` samples packed towards the camera (t grows with the square of the step), each with shadowtex1 visibility, the light left after coming down from the surface, and the broad caustic field within 16 blocks, weighted by a Henyey-Greenstein phase (g = 0.7, averaged it equals the old constant term); `UNDERWATER_SHAFTS` scales it.
- **The surface from below** (`UNDERWATER_MIRROR`, 4.40, softened in 4.42): the reflection of the underwater world (voxel trace only, with its own absorption and depth light) is mixed in by `(1 - smoothstep(0.26, 0.87, cos theta)) x UNDERWATER_MIRROR`: nothing within 30 degrees of straight up, full strength from 75 degrees. Real total internal reflection begins at 48.6 degrees with a sharp rim, which read as a hole in the picture; the blend has no edge. 0 turns it off; default 0.5.
- Lava and powder snow fog, blindness.

### 5.11 Sky, fog and clouds (`lib/sky.glsl`, `program/clouds.glsl`)

- Sky: zenith/horizon gradient, sunset band (`SUNSET_STRENGTH`), sun aureole, moon glow, rain desaturation; analytic sun disc (`SUN_DISC_*`). Nether and End use fixed colors (`NETHER_AMBIENT` from the fog color, `END_AMBIENT`).
- **Sun aureole (ported from 4.18), `SUN_GLOW`:** the forward-scattered glow around the sun is computed from the angle to it, `ang = sqrt(2 * (1 - mu))` (the small-angle form of `acos`), as `exp(-ang * 55) * 0.55 + exp(-ang * 7) * 0.045` scaled by `SUN_GLOW` (default 2.0). Half-width 0.79 degrees instead of the 7.3 degrees of the old `pow(mu, 10) * 0.35 + pow(mu, 120) * 1.2`, which reached 1.55 over a huge area, tonemapped to near white and made the sun look enormous. The disc edge fades over `radius x 1.06` instead of `x 1.3`, so `SUN_DISC_SIZE` matches the size on screen; defaults `SUN_DISC_SIZE` 0.5 and `SUN_DISC_BRIGHTNESS` 8.0 (`SUN_DISC_SIZE` 0.25 is about the real sun).
- **Sky light in shade** (`SKY_LIGHT_CURVE`, 4.25): `skyExposureFromLightmap()` returns `pow(lmSky, SKY_LIGHT_CURVE)`, default 0.8 since 4.26 (it was `lmSky x lmSky`), and `GI_SKY_STRENGTH` defaults to 1.25 instead of 0.65. Both multiply every path that carries sky light: the GI ray that escapes (`getSkyRadiance x GI_SKY_STRENGTH x skyExposure`), the ambient term of `shadeVoxelHit()` and the fallback outside the voxel volume. Measured with the real functions at a high sun, light on a white floor with the sun straight on it as 1.00: open shadow 0.078 -> 0.121 -> 0.151 (4.24 -> 4.25 -> 4.26), roof 2 blocks in 0.033 -> 0.058 -> 0.074, roof 5 blocks in 0.012 -> 0.028 -> 0.038, room with a window 0.007 -> 0.018 -> 0.025; a sunlit surface changes by 7 % in total. `sunExposureFromLightmap()` (`smoothstep(0, 0.35, lmSky)`, the sun bounce) is unchanged, and lmSky = 0 still gives 0, so caves stay dark.
- Fog (composite): exponential height fog in the Overworld (`FOG_DENSITY`, thicker in rain), per-dimension fog elsewhere, border fog from `BORDER_FOG_START x far`. The Overworld fog color is the sky toward the horizon times `mix(0.08, 1, max(eye sky light, the surface's sky light))` (4.44: the camera's alone made the far landscape outside fade to black when seen from a cave or a room). The land behind a window is fogged at its own distance before the glass is applied (4.44; the fog was measured to the glass, and the render edge showed as a hard line through windows), and so are reflections (5.9).
- **Clouds (ported from 4.18), `CLOUD_STYLE`:** 0 off, 1 vanilla, 2 volumetric (default). `shaders.properties` sets `clouds = off` unless `CLOUD_STYLE == 1`; `clouds.glsl` (as `gbuffers_clouds`) discards unless the style is vanilla.
- **Volumetric march** (Overworld only): the view ray is intersected with the layer `CLOUD_HEIGHT .. + CLOUD_THICKNESS` from above or below, limited by `CLOUD_MAX_DISTANCE` and the surface distance; `CLOUD_STEPS` steps with a per-pixel offset. Density: 5-octave value-noise fbm (`CLOUD_SCALE`, `CLOUD_SPEED`), eroded by a detail fbm (`CLOUD_DETAIL`, `CLOUD_DETAIL_SCALE`), height profile, coverage threshold from `CLOUD_AMOUNT` (lowered by rain), x `CLOUD_DENSITY`. Lighting: `CLOUD_LIGHT_STEPS` samples toward the sun, Beer-Lambert with `CLOUD_ABSORPTION`, `CLOUD_MULTISCATTER`, sky ambient x `CLOUD_AMBIENT`, sun x `CLOUD_BRIGHTNESS`.
- Clouds are drawn on sky pixels in deferred6, in water/glass/metal reflections of the sky, and in front of terrain by `applyCloudsInFront()` at the end of composite (not on the hand and not while underwater). The Clouds page is `CLOUDS_PAGE` under Sky & Fog.

### 5.12 Post-processing (`program/final.glsl`)

- **Bloom:** weighted average of colortex0 mip levels 2-7 (`colortex0MipmapEnabled`), `mix(color, bloom, BLOOM_STRENGTH) + bloom x BLOOM_STRENGTH x 0.5`.
- **Exposure:** `EXPOSURE`; with `AUTO_EXPOSURE` in the Overworld x `CAVE_EXPOSURE` by low eye sky light (`eyeBrightnessSmooth`) and x `NIGHT_EXPOSURE` at night outdoors; x 1.6 in the Nether and End. There is no image metering.
- **Tonemaps (ported from 4.18), `TONEMAP`:** 0 ACES (default), 1 Reinhard, 2 Hable (Uncharted 2), 3 None (clamp), 4 AgX, 5 Lottes, 6 Soft filmic, 7 Reinhard-Jodie, 8 Uchimura (GT). Every curve returns linear light; then `SATURATION`, the sRGB encoding, `CONTRAST`, `VIGNETTE_STRENGTH`, `DITHERING`. AgX and Soft filmic produce display-encoded output by construction and were encoded a second time until 4.44 (middle grey 0.85 / 0.75 on screen, washed out); AgX is now the reference minimal AgX (log encoding, the polynomial contrast fit, outset matrix, power 2.2 back to linear: middle grey 0.50 on screen) and Soft filmic is linearized with power 2.2 (0.54).

- **Auto exposure** (4.29): the cave boost is `mix(mix(CAVE_EXPOSURE, 1.0, eyeSky), 1.0, lit)` with `lit = smoothstep(0.35, 0.9, eyeBrightnessSmooth.x / 240)`, and the night boost carries `(1 - lit)`. Before, only the sky lightmap was read, so a hall lit by a glowstone ceiling counted as a cave and was multiplied by up to 2.6 on top of an already bright image.
- **Highlight washout** (`HIGHLIGHT_DESAT`, 4.30): before the tonemap, a color whose brightest channel exceeds 1.0 is mixed towards `vec3(peak)` by `(1 - 1/peak) x HIGHLIGHT_DESAT`. Per-channel tonemapping keeps a saturated over-range color (a wall of redstone blocks) at full, flat saturation; this is the film-like washout instead. Nothing below 1.0 changes.
### 5.13 TAA (`lib/taa.glsl`, `program/taa_resolve.glsl`)

gbuffers vertex shaders add a Halton(2,3) sub-pixel jitter (`TAA_JITTER_PATTERN` frames, `TAA_JITTER_SCALE`); the shadow pass is not jittered. The resolve reprojects with the camera matrices, clamps the history to the 3x3 neighborhood range in a luminance-compressed space, lowers the weight by the clamp distance (`TAA_CLAMP_SENSITIVITY`) and near the screen edge, and blends with `TAA_STRENGTH`. The hand (depth below 0.5625) keeps its history where it is on screen (4.44): its squeezed depth rebuilt to a point a tenth of a block in front of the camera, and reprojecting that sent the lookup far away whenever you moved, so the held item lost its anti-aliasing.

### 5.14 FXAA and sharpening (`program/sharpen.glsl`, composite2, ported from 4.18)

- **FXAA** (`FXAA`, off by default): classic single-frame edge smoothing on colortex0 - the luminance of the four diagonal neighbors gives the edge direction, and the pixel is blended along it by `FXAA_STRENGTH`. It works with or without TAA.
- **RCAS** (`SHARPEN`, on by default): the sharpening stage of AMD FSR (there is no FSR upscaling; the pack always renders at full resolution). The gain of the cross-shaped kernel is limited by the local contrast, so it creates no halos and does not amplify noise. `SHARPEN_STRENGTH` scales it.

**This pass is on the HDR path.** composite2 runs *before* `final.glsl`, so colortex0 is still linear HDR here: a sunlit white block is ~2.6 and the sun disc is `SUN_DISC_BRIGHTNESS` (8.0). Three things follow, and all three were wrong until 4.34:

1. The RCAS resolve is `(center + lobe * (up+down+left+right)) / (1 + 4*lobe)` with a **negative** lobe weight. Here the lobe is `-gain`, so the divisor must be `1 - 4*gain`. It was written `1 - 4*(-gain)`, i.e. `1 + 4*gain`, which makes the filter's DC gain `(1-4g)/(1+4g)` instead of 1. Measured on a flat patch at the default strength: **0.619x**; at strength 1.0, 0.111x. A flat patch is the regression test - it must come out at exactly 1.000x at every brightness, HDR included (`sharpen_test.py`).
2. The contrast limiter must be **scale-invariant**. It used `min(mn, 1.0 - mx)`, which assumes 1.0 is the peak; above 1.0 that term goes negative, the gain collapses to 0 and nothing bright is sharpened at all. It is now the local dark-to-bright ratio `sqrt(mn/mx)`, which behaves the same whether the neighborhood sits at 0.2 or at 20.
3. The result must **not** be clamped to 1.0. It was, and since `final.glsl` reads this same buffer for bloom, exposure and tonemapping, everything above white arrived as exactly white - a lit sheep, a glowstone, a lava lake and the sun all landed on 0.804 on screen. Only `max(color, 0.0)` is applied, which is what the bloom mip chain needs (no negatives).

A third limiter was added in 4.34: `gain <= center / sum(neighbors)`, so the numerator cannot go negative and a single dark pixel among bright ones is no longer pushed past black and clipped.

### 5.15 Textured voxels (`VOXEL_TEXTURES`, 4.38, `lib/voxeltex.glsl`)

A voxel's one color is right for GI but a reflection SHOWS the block. The shadow vertex shader (`writeFaceTexture()`) records, per voxel, the atlas sprite of three face classes (0 top, 1 sides, 2 bottom) and the biome tint in `faceTexImg` (4 words per voxel). A sprite word holds the origin in 16-pixel units (12 bits x, 12 bits y), a valid bit (24), a tinted bit (28) and log2(size / 16) (bits 29-31); the size is measured from how far the vertex's UV lies from `mc_midTexCoord`, and `imageAtomicMax` keeps the largest, so a small face (a torch side) cannot override a full one. A reflection hit works out where on the face it landed, turns that into a texel with Minecraft's face orientation (up: u = x, v = z; down: u = x, v = 1 - z; south u = x, north u = 1 - x, east u = 1 - z, west u = z; sides v = 1 - y) and reads `customTexture.blockAtlas` at the mip level of the texel's size on screen (camera distance plus the reflected distance, `pixelFootprint()`). The texel average is the old flat color, so brightness is kept. Debug view 15 shows the same textures. Limits: one texture per face class, full-cube mapping, no rotation (a furnace front, sideways logs and glazed terracotta can look off).

### 5.16 Entities in ray tracing (`VOXELIZE_ENTITIES`, 4.39, `lib/entity.glsl`, `program/shadow_entity.glsl`)

- **Grid:** `entityImg`, 64^3 cells around the camera's block (32 blocks each way), 4 words per cell: the shape (same slice layout as the terrain: Y 16, X and Z 8 slices; a single slice here means "this thin", a thin wall), red + green sums and blue + sample count (6 bits per sample, at most 1000 samples), plus a brick mask (one bit per 8^3 brick) so a ray reads entity cells only where there are entities. Cleared every frame.
- **Writer:** `shadow_entities` and `shadow_block` (Iris 1.8+) have a geometry shader that emits the triangle for the shadow map and clips it against every cell it touches (Sutherland-Hodgman, at most 6 cells per axis), marking the slices its clipped part covers and adding the texture color at the triangle's middle. Transparent spots (alpha < 0.1) are skipped. End portals, beacon / conduit (3005) and end gateway / enchanting table (3006) block entities are left out: beams and portal surfaces are not solid.
- **Readers:** GI rays and the shadow rays of block lights test the entity box of every cell next to the terrain (the nearer hit wins); a hit returns the cell's average color with voxel code `VOXEL_ENTITY`, and the world cache's REST is not read at entity hits. Reflections do not trace entities.
- **Rays that start inside an entity box** (`entityEnter()`, 4.43): the box is only the bounds of the entity's parts in the cell, rounded out to eighths, so the point just off an entity's surface is always inside it. Until 4.43 such a ray passed freely in every direction; with normal maps tilting a surface's rays far from the face, rays that pointed into a mob crossed its whole body (measured on Mesa: a ray from a player's back went through the chest to the glowstone in front). Now: from an entity's own face (`entityStartNormal`, set by `deferred.glsl` from colortex2.g) a ray leaves unless it heads back in, then it is stopped at once; from anything else (the ground under a mob, a wall a mob leans on) the point lies within the entity and the ray is stopped - the contact shadow (0.0 blocks from a player's feet: 19 % -> 100 % of GI rays blocked); from the camera (`entityStartFree`, debug views) it is never stopped.
- **No Iris 1.8:** older versions draw entities with the plain `shadow` program, whose voxelizer only takes terrain render stages, so entities simply stay out.

### 5.17 Forward-lit surfaces (`lib/forward.glsl`, `program/gbuffers_forward.glsl`)

Water, glass, particles and weather are lit from the lightmap: sky ambient x `skyExposureFromLightmap()` (the same curve as the deferred lighting; it was the squared lightmap, which gave zero in the Nether and the End, 4.44), the sun with one shadow tap (Overworld), vanilla block light, `MIN_LIGHT`. `gbuffers_lightning` (4.44) draws the bolt from its vertex color x 8, unlit, with colortex2 blending off.

---

## 6. Settings system

### 6.1 `lib/settings.glsl`

- **Numeric:** `#define NAME value // [list] description`. The list uses single spaces, the default must be in it, and no `[` may appear before the list. Fractional values cannot be tested in `#if`.
- **On/off:** `#define NAME // description` or `//#define NAME`. Iris shows it only if it sees `#ifdef NAME` somewhere, so every switch is also listed in the **ON/OFF SETTING REGISTRY** at the end of the file.
- **Iris constants:** `shadowMapResolution`, `shadowDistance`, `sunPathRotation` (with value lists), `shadowDistanceRenderMul`, and `voxelDistance`, which follows `VOXEL_RANGE`.
- **Dummy settings:** `ABOUT_*` (About, Changelog and System Requirements pages) and `DEBUG_HELP_*` are `// [0]` options that only show text; their `value.NAME.0=` label is empty.

### 6.2 `shaders.properties`

- `screen = [ABOUT] <profile> [RAY_TRACING] ...` with `screen.columns = 2`, so About and the profile button sit side by side at the top. `[PAGE]` links a sub-page `screen.PAGE`, `<empty>` is a blank cell. `sliders = ...` lists the numeric settings drawn as sliders.
- Pages: About (-> System Requirements, Changelog), Ray Tracing (-> World GI Cache), Denoiser, Emissive Block Colors, Coloured Light, Reflections, Lighting (-> Block Light Color), Shadows, Sky & Fog (-> Clouds), Water, Materials, Post Processing, Anti-Aliasing & Sharpening, Debug.
- `iris.features.required` / `.optional`, `customTexture.blockAtlas`, the `image.*` lines (4.2) and the per-program `blend.*` overrides (colortex2 blending off for every program that writes a material, including `gbuffers_lightning`) are at the top of the file.
- **Profiles** `profile.A_LOW`, `B0_MEDIUM`, `C1_HIGH`, `C5_ULTRA`: the key names make Iris sort them Low, Medium, High, Ultra (display names come from the lang file). **Every profile sets the same 16 settings.** Medium equals the defaults in `settings.glsl`.

| Setting | Low | Medium | High | Ultra |
|---|---|---|---|---|
| GI_HALF_RES | on | off | off | off |
| RT_LIGHT_SAMPLES | 4 | 8 | 8 | 8 |
| GI_BOUNCES | 1 | 2 | 2 | 3 |
| GI_MAX_STEPS | 24 | 48 | 64 | 96 |
| REFLECTION_STEPS | 48 | 96 | 128 | 192 |
| REFLECTION_MAX_DISTANCE | 64 | 128 | 256 | 384 |
| shadowMapResolution | 1024 | 2048 | 3072 | 4096 |
| VOXEL_RANGE | 128 | 128 | 192 | 256 |
| SHADOW_SAMPLES | 4 | 12 | 12 | 12 |
| VOXEL_SHAPES | on | on | on | on |
| MATERIAL_NORMALS | off | on | on | on |
| MATERIAL_POM | off | off | off | on |
| POM_STEPS | 32 | 32 | 32 | 64 |
| CLOUD_MAX_DISTANCE | 5000 | 5000 | 10000 | 10000 |
| GI_CACHE_RAYS | 1 | 2 | 2 | 3 |
| GI_CACHE_BUDGET | 8192 | 16384 | 16384 | 32768 |

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
| 1001 | Glass, stained glass, ice, slime, honey | only with `GLASS_TRANSMISSION` (tinting voxel) |
| 1002 | Plants, crops, vines | no; normal forced up, lit like the ground |
| 1003 | Banners, string, tripwire, pointed dripstone, barrier, light, structure void, OPEN fence gates (`:open=true`, 4.44) | **never** |
| 1005 | Fences, closed fence gates (`:open=false`), walls | post and arms, opaque (code 7) with `VOXEL_SHAPES` + `VOXELIZE_LATTICE` |
| 1006 | Glass panes | post and arms, tinting (code 8) with `GLASS_TRANSMISSION`; without the lattice setting a box as before |
| 1007 | Cobweb, scaffolding, copper grates | veil (code 9): passes `1 - alpha` everywhere |
| 1008 | Iron bars, chains (and the copper variants of later versions) | post and arms, passing `1 - alpha` (code 8) |
| 1004 | Doors, trapdoors, rails, carpets, unlit candles, heads, anvils, signs... | only with `VOXEL_SHAPES`; cutout path with `TRANSMISSION_FROM_ALPHA` |
| 1009 | Tinted glass (4.44; it was in 1001 and passed light) | always, as a solid voxel; a black filter in the sun's shadow map |
| 2000 | Leaves | with `VOXELIZE_LEAVES` |
| 2001 / 2002 | Polished / metal blocks | yes (reflective codes 3 / 4) |
| 2100 | Concrete powder | light source when `EMIT_CONCRETE_POWDER` is on (`EMIT_CUSTOM_I`, texture color, balanced like the minerals); otherwise a normal block |
| 2101 / 2102 | Concrete / wool | never emit: concrete is polished (reflective), wool is matte |
| 2103-2109 | Mineral blocks: redstone, lapis, emerald, diamond, amethyst, coal, raw copper | light sources when `EMIT_MINERAL_BLOCKS` is on, each with its own `EMIT_MINERAL_*_I`; otherwise polished |
| 3000-3007 | Light categories: fire, soul, lamp (glowstone, shroomlight, froglight, copper bulb), lava, redstone, cool, purple (incl. Nether portal), green (glow lichen, glow berries, waterlogged sea pickles, copper torches and all copper lanterns; 4.44 added the lantern stages and the waterlogged state) | yes, `EMIT_<CATEGORY>_R/G/B/I` |
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
| 4 | Material ID (gray lit, light green plant, dark green leaves, yellow light source, pink hand, blue entity, light blue glowing entity part, black unlit) | final |
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
| 23 | World GI cache: the SEED of the face under each pixel (dark red = no valid entry, dark blue = outside the radius or cache off) | final |

Tools: **Highlight Broken Pixels** (`DEBUG_NAN_CHECK`, NaN/Inf in colortex0 or the GI history in pink), **Shadow Map Preview** (`DEBUG_SHADOW_OVERLAY`), **Freeze Noise** (`DEBUG_FREEZE_NOISE`, GI random numbers only).

**Adding a view:** add a `DBG_` constant in `lib/debug.glsl`, add the number to the `DEBUG_VIEW` list in settings.glsl, produce it (usually in `finalDebugView()`; views made in deferred6 or composite must also be added to `isDeferredDebugView()` / `isCompositeDebugView()` and, if HDR, `isHdrDebugView()`), and add `value.DEBUG_VIEW.N=N Name` and the description in the lang file.

---

## 9. Tools (`tools/`)

Python 3.8+, run from the pack root (the folder that holds `shaders/`). Not shipped in the pack. The checks (`generate_wrappers.py --check` and the other four) exit with a non-zero code on failure.

| Tool | Command | What it checks / does | Needs |
|---|---|---|---|
| `generate_wrappers.py` | `python3 tools/generate_wrappers.py [--check]` | Writes the 213 wrapper files from the `PROGRAMS` table (program, source, `#version`, extension lines, extra defines, for a compute pass its `layout` and `workGroups` lines, `GEOMETRY` for a vertex + geometry + fragment program). `--check` only reports differing files and files not in the table. Without `--check`, stray files are only warned about, not deleted. To add a program, add a row and rerun. | - |
| `validate_glsl.py` | `python3 tools/validate_glsl.py` | Expands `#include`s, inserts the defines Iris injects (`MC_RENDER_STAGE_*`, `IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE`) and compiles all 213 files with glslangValidator. Also scans the preprocessed source for GLSL reserved words used as identifiers (e.g. `packed`), which NVIDIA rejects and glslang accepts. | `glslangValidator` |
| `mesa_check.py` | `python3 tools/mesa_check.py [program ...]` | Compiles **and links** every program (108 = 36 x 3) with Mesa llvmpipe through a headless EGL OpenGL 4.5 compatibility context, and fails if a program uses more than 8 image uniforms (NVIDIA limit) or, since 4.44, more than 16 textures (what OpenGL guarantees). With program names it checks only those and prints their images and texture counts (shadow: 8 images; composite: 15 textures; deferred: 16). Only the settings as they are in `settings.glsl` are checked, so run it on a copy with other settings too (the Light Grid image overflow of 4.43 only existed with Light Grid off). | Linux, Mesa (`libEGL.so.1`, `libGL.so.1`) |
| `sharpen_check.py` | `python3 tools/sharpen_check.py` | Runs the RCAS block from `program/sharpen.glsl` itself on Mesa llvmpipe, lifted verbatim out of the file, and feeds it flat patches and edges. **A flat patch must come back at exactly 1.0000x at every brightness, HDR included**; anything else means the filter is scaling the whole image, which is what 4.34 fixed. Exits non-zero on failure. `STRENGTH=1.0` to check another setting. | Linux, Mesa |
| `check_consistency.py` | `python3 tools/check_consistency.py` | settings.glsl <-> shaders.properties <-> en_us.lang: defaults inside their lists, on/off switches registered with `#ifdef`, every option on a menu page, no unknown menu items, **no dead settings** (in the menu but never read by shader code), valid profile tokens and values, label and 40-character comment for every option, distinguishable labels, and (since 4.41) no `#include` line with anything after the quoted path. **Language guard:** no Turkish letters or common Turkish words in `shaders/`, `tools/` and `docs/`; shader sources (`.glsl .vsh .fsh .csh .gsh .properties`) must be 7-bit ASCII. | - |

---

## 10. Release checklist

1. `lang/en_us.lang`: set `option.ABOUT_VERSION=Version: §fX.Y` and the version in `screen.CHANGELOG=§aChangelog X.Y`.
2. Rewrite the changelog lines `ABOUT_CL_HEAD` and `ABOUT_CL_1` ... `ABOUT_CL_5` (label and `.comment`). For more lines, add `ABOUT_CL_n` to settings.glsl (`// [0]`), to `screen.CHANGELOG` in shaders.properties and an empty `value.ABOUT_CL_n.0=` to the lang file.
3. If memory or requirements changed, update the `ABOUT_REQ_*` lines (and section 2 of this document).
4. Keep new comments, tool messages and documentation in English and shader sources in plain ASCII.
5. Run, all must pass: `python3 tools/generate_wrappers.py --check` (run it without `--check` first if a program was added or changed), `python3 tools/validate_glsl.py`, `python3 tools/mesa_check.py` (Linux), `python3 tools/check_consistency.py`, `python3 tools/sharpen_check.py` (Linux). Then run `validate_glsl.py` and `mesa_check.py` on copies of the tree with the switches you touched turned the other way (for 4.44: Light Grid, Block Shapes, the Reflection Denoiser and its sharpening, half resolution GI, tonemaps 4 and 6, the hole mask, colored shadows, translucent light sources, the reflection modes, block lights, GI, the world cache, entities, TAA, LabPBR; for 4.46: Block Shapes, normal maps off, the reflection modes 0 and 1, the Reflection Denoiser, half resolution GI, block lights, Light Grid, entities).
6. Package: `CORAL-VXGI-X.Y.zip` contains **only** `shaders/` and `LICENSE.txt`. `tools/` and `docs/` go into a separate `CORAL-VXGI-X.Y-dev.zip`. Both names carry the version.

---

## 11. Known limitations

- **Light grid limits.** A region list keeps at most 64 home regions (8-block regions) and is built from at most 6 rings (48 blocks) and 4096 scored lights; when more home regions reach a region (a huge lava ocean), the weakest are left to GI rays, which are noisier and, because a GI ray and the shadow ray do not agree on a light's brightness, slightly different in brightness. Direct sampling reaches at most 48 blocks even when `RT_LIGHT_RANGE` is higher. Inside a home region with many lights one is picked at random, so a pixel right next to one lava block among 64 still has some noise. `LIGHT_GRID` off restores the single list of 1024 with all of its old problems (dropped lights that pop in and out).
- Ray-traced block light on visible surfaces needs `GI_ENABLED`, and it goes through the GI chain (`GI_STRENGTH`, `GI_SATURATION`, firefly clamp, denoiser).
- **Entities are boxes to the ray tracer** (5.16): one box per block of space an entity touches, within 32 blocks, one average color per cell, no emission of their own, not in reflections, and all of it needs Iris 1.8. Entities, block entities and the hand get no ray-traced reflection and at most 8 % F0, so a LabPBR metal mob looks like smooth plastic. Blocks buried inside a solid mass are not in the terrain grid: Minecraft does not draw them, so the shadow pass never sees them and the grid has air there. Since the visible boundary of the mass is always solid, rays cannot reach that air any more (4.21) - but a probe placed inside such a mass still measures light. Group 1003 (banners, string, dripstone, barriers, open fence gates) is never voxelized. Fences, walls, panes and bars (5.1) are a post and at most four axis-aligned arms: a fence's two rails count as one solid arm, heights round up to the next 1/16, and a wall's tall and low arms are described by one arm height range per block.
- **Block shapes** are one box per cell at 1/8 (X, Z) and 1/16 (Y) resolution, intersected with the solid-side masks of `solidImg` (4.24), so an L-shape such as a stair is stored as its real shape and not as a full box. Shapes that are neither a box nor a box minus half-spaces - a lantern hanging on a chain - still round out to their bounding box or are left out of the grid entirely (group 1003). Textured voxels (5.15) keep one texture per face class and the full-cube mapping.
- **Without Block Shapes** a GI or reflection ray that starts inside a block still leaves it through the far side: there the top of a slab or stair lies inside its own full cube, so the start cell cannot be told apart from an error and is not tested (5.1). The flat, camera-facing start point (5.4) makes such starts rare; the shadow ray to the block lights is covered by `shadowStartInOwnBlock`.
- **Hole mask** bits come from the rasterized shadow map, so coverage depends on shadow map resolution and distortion; unmarked texels count as solid. Where the sun sees a panel at a flat angle the panel passes light evenly instead (5.2). It only affects block-light shadow rays outside reflections. `CUTOUT_MASK_RES` 16 is used at every Voxel Range (see the memory table).
- **Outside the grid** GI is replaced by sky ambient x sky lightmap and vanilla block light is used at full strength. GI rays that leave the grid or run out of steps count as sky hits (weighted by the pixel's sky lightmap).
- Stained glass, ice, slime and honey tint block light with `GLASS_TRANSMISSION` (since 4.44 no longer also needing `VOXELIZE_TRANSLUCENT_EMITTERS`). Tinted glass blocks the sun only while `COLORED_SHADOWS` is on (without it no translucent block casts a sun shadow).
- **Water:** caustics come from the sun and moon only and follow the pack's own wave field; the underwater mirror is deliberately softened (5.10). A metal block behind glass or water gets its reflection from the voxel trace alone and ignores the refraction's bend.
- The emission gain of emissive mineral blocks and concrete powder in `gbuffers_solid.glsl` still reads mip level 4 (GLSL 330 has no `textureQueryLevels`), so with the game's Mipmap Levels below 4 their surface brightness normalization uses fewer texels; the voxel colors are right (5.1).
- Translucent surfaces, particles and weather are lit from the lightmap only (no GI, no ray-traced block light). The hand is not ray traced; its indirect light is sky ambient.
- Rough reflections trace one jittered ray per frame, so they are grainy unless the Reflection Denoiser is on (it is off by default) or TAA smooths them over time. Temporal reprojection (GI, TAA and the reflection denoiser) uses camera motion only; moving mobs can smear slightly. The composite pass does without the stained-glass tint of sunlight and without hole masks to stay within 16 texture units (4.2).
- **Clouds:** volumetric clouds exist only in the Overworld, cast no shadows and do not enter the GI sky term; they are also ray-marched in sky reflections, which costs time on large water surfaces. Vanilla clouds (Cloud Type = Vanilla) follow the game's own Clouds video setting (Fast / Fancy / Off); for Off and Volumetric the pack turns the vanilla layer off.
- **World space GI cache.** It reaches at most 32 blocks (64^3 cells); further out pixels trace every bounce as before. One entry per block face: SEED has none of a pixel's own detail and REST is a face average. Glass, fences, panes, bars and cobwebs have no entries, and a stair tread shares the entry of the step's top face. The cached later bounces react to a change of light (a torch placed or broken, the sun moving) over up to `GI_CACHE_FRAMES` updates - the direct light and the first bounce react at once - and with more exposed faces than `GI_CACHE_BUDGET` each face is updated only every N-th frame (at most 32), which stretches that further. The later bounces use each face's own sky light, so bounced light next to openings can differ from 4.36 by a few percent (measured -3 % / +1 %).
- Debug view 22 replaces the GI of the whole frame, so with Split Screen the "normal" right half is also missing its GI.
- At Voxel Range 256 `voxelDistance` (136) is above the default `shadowDistance` (128); Iris documents that the shadow distance cannot be lower than `voxelDistance`.
- Distant Horizons is not supported. GPU recommendations in the menu are estimates, not measurements.

---

## 12. Version history

**4.46** - the rest of the corner leaks.
- `geometricNormal()` faces the camera instead of agreeing with the normal-mapped N: at a wall-floor corner the old choice flipped the flat normal into the wall on every texel leaning towards it, and GI rays started inside the wall (rows of orange dots along corners, strongest at high resolutions). Corner pixel-frames with the start point inside a block at 1280x720: 2.9 % -> 0 (5.4).
- The shadow ray to the block lights steps off along that flat normal (`neeOffsetNormal`), not the normal-mapped N: 6.1 % -> 0 (5.3).
- A traced ray that starts inside the solid part of a block (leaves excepted) ends there in the dark; 4.45 lit that spot as the face the ray came from, for half the directions the far side of the wall with its cached torch light. The shadow ray is stopped when it starts inside a solid side of an L-shaped block (light through stair steps and cauldron floors) (5.1).
- Reflection rays of opaque surfaces start from the flat, camera-facing normal and one pixel back towards the camera; a ray starting inside a block returns black (5.9).

**4.45** - light leaks along block corners.
- GI rays start from the flat normal rebuilt from depth, pulled back towards the camera by one pixel, instead of `playerPos + N x 0.02` with the normal-mapped N: at a corner that put the start point inside the neighboring wall, and `traceVoxels()` let a ray that starts inside a full cube leave through the far side with the light behind it. Such a ray is now stopped where it starts (refined in 4.46). Measured in a closed room with sunlit land outside (Bump Depth 4, TAA jitter): the wall-floor corner went from up to 7x the brightness of the floor beside it (mean 0.0107, peak 0.0594) to the floor's own (0.0073 / 0.0082, floor 0.0071), and the white specks on walls and ceilings seen at a slant, the same leak, are gone (5.1, 5.4).
- Without Block Shapes, 4.44's rule that lets the shadow ray out of the cube it starts in applies only to the block the surface belongs to (`shadowStartInOwnBlock`): slab tops keep their torch light, walls hold it back again (floor at a wall face 0.0508 -> 0.0046, as in 4.43) (5.1).

**4.44** - a review of the whole pack; all bug fixes.
- Metal blocks behind glass, ice or water rendered black (their color comes from the reflection, which composite added only where nothing translucent was in front): `metalBehindTranslucent()`, with the glass opacity now in colortex5.b. Metal reflections are added instead of blended, so LabPBR metals of middling smoothness are no longer up to a fifth too dark (5.9).
- Light Grid off made the shadow program bind 9 images and the pack failed to load on NVIDIA: the legacy light list and its counter are one R32UI image (4.2, 5.3). `mesa_check.py` also checks the 16 texture units OpenGL guarantees; composite came down from 19 to 15 (4.2).
- GI spike filter read its neighbours at the current pixel of the OLD picture; now around the reprojected position with a depth test (dark patches on newly revealed terrain). The history depth test and the cache seed use the flat normal; plants keep their up normal for the seed; the GI history is written with stochastic rounding (Temporal Frames 128+ no longer stall); the cache epoch can no longer wrap round (5.4.1, 5.5).
- Fog: the land behind a window and what reflections show get their own distance fog; fog brightness follows the surface's sky light too (5.9, 5.11). Glass Reflection Strength above 1 capped. Reflection denoiser: per-texel history taps and reprojected sharpening neighbours (5.9).
- Blocks: tinted glass is a solid voxel and a black sun filter (ID 1009); open fence gates are not voxelized; translucent light sources off no longer removes stained glass; dry sea pickles no longer glow and every copper lantern stage is listed; with Block Shapes off slab and stair tops get block light; hole masks fall back to even transmission where the sun sees a panel edge-on, and ladders facing east or west read their mask on the right axes; voxel colors are averaged by hand when the atlas has no mip level 4 (5.1, 5.2, 7).
- Glowing entity parts (LabPBR emission) are `MAT_ENTITY_EMISSIVE`: no reflection, GI rays start on the entity (5.16).
- AgX and Soft filmic were gamma-encoded twice (5.12); the hand keeps its TAA history (5.13); `gbuffers_lightning` draws a glowing bolt instead of a lit entity; forward surfaces get their ambient light in the Nether and the End (5.17).
- `iris.features.required` adds `COMPUTE_SHADERS REVERSED_CULLING`. Tooltips that named non-existent settings, a wrong denoiser default, the profile note on normal mapping and the lamp block lists are corrected.

**4.43**
- Light passed through mobs: a ray starting inside an entity box passed it freely, and normal-map-tilted rays crossed thin bodies. Entity pixels store their flat face direction (colortex2.g, `MAT_ENTITY`), and inside-box rays are stopped when they head into the entity or start within it (5.16).
- Entities, block entities and the hand get no ray-traced reflection and at most 8 % F0 (the reflection's grain and see-through look on iron golems). Two-sided entity parts face the camera.

**4.42**
- The underwater mirror fades in over a wide range of angles instead of a hard circle of sky; `UNDERWATER_MIRROR` is a strength 0-1 (default 0.5) instead of a switch (5.10).
- Entity and hand metals (LabPBR) become dielectric. System requirements: Iris 1.8+ / Minecraft 1.21+, full video memory figures.

**4.41**
- 4.40 did not load: an `#include` line carried a comment after the path, which Iris reads as part of the file name. `check_consistency.py` now rejects that.

**4.40**
- Water rebuilt: caustics refracted by the wave field (area ratio, dispersion, depth normalization, 0.93-1.02 mean at every depth), waves without grid lines, the water surface map, light shafts under water (`UNDERWATER_VOLUMETRIC`), depth absorption (`UNDERWATER_DEPTH_LIGHT`), the mirror of the surface from below. `CAUSTICS_SCALE` / `CAUSTICS_SPEED` removed, `CAUSTICS_FOCUS` / `CAUSTICS_DISPERSION` added (5.10).

**4.39**
- Entities in ray tracing (`VOXELIZE_ENTITIES`): `shadow_entities` / `shadow_block` with a geometry shader write the entity grid; GI and block-light shadow rays test it (5.16). Needs Iris 1.8.

**4.38**
- Textured voxels (`VOXEL_TEXTURES`): the atlas sprite of every face class is recorded and reflections read the real texel; leaf holes are passed (5.15). Debug view 15 shows the textures.

**4.37**
- World space GI cache (`WORLD_SPACE_GI`, on): every exposed block face within 24 blocks keeps its own indirect light, updated by two new compute passes (`deferred_b.csh` lists the faces, `deferred_c.csh` traces them) whether it is on screen or not. Pixels without history start from it (`GI_CACHE_TRUST` frames), and with `GI_CACHE_BOUNCES` (on) the bounces after a GI ray's first hit are read from it. The path code moved to `lib/gipath.glsl` so the screen and the cache share it; with the cache off the output is 4.36's. Measured: after a half turn the first frame's error 87-95 % -> 13-22 %, walking through a dim hall 37 % too dark -> 3.5 %, GI pass 0.59x-0.84x, the same brightness within 0.3 % wherever the sky light is the same (5.4.1, 5.5).
- New page Ray Tracing > World GI Cache, debug view 23, two more profile settings (`GI_CACHE_RAYS`, `GI_CACHE_BUDGET`). About 34 MB of video memory.
- Documentation: the history depth tolerance and the sky exposure curve were described with their pre-4.34 / pre-4.25 formulas.

**4.36**
- Half resolution GI (`GI_HALF_RES`, on in the Low profile): the GI pass traces one pixel of every 2x2 block, a different one each frame, and deferred1 spreads the samples over the full resolution by surface plane and normal. 0.27x the pass time on Mesa with the same converged brightness (+0.1 %) (5.4, 5.5).
- Profile table: Medium has had normal mapping on since 4.30; the table said off.

**4.35**
- Light grid (`LIGHT_GRID`, on): every 8-block region keeps its own light mask and a list of the home regions that reach it, built by the new compute pass `deferred_a.csh`. No more limit of 1024 light blocks, so lights in the Nether or next to a lava lake no longer lose their shadows or pop in and out; candidates are drawn in proportion to how much light each home region can bring, so torch light is less noisy in light-dense areas. Measured against the single list: identical where it did not overflow (0.1-0.2 %, cap off), a wall facing a lava lake 0 -> 2.96 direct light (5.3).
- Fences, fence gates, walls, glass panes, iron bars, chains, cobwebs, scaffolding and copper grates enter the voxel grid (`VOXELIZE_LATTICE`, on): a post and up to four arms read from the vertices, no texture and no block state needed (5.1). Walls were full cells before as soon as they had an arm.
- The GI emission rule now also applies on the second ray: a shadow ray is sent from the first hit too, and a second ray landing on a lamp added its light a second time. The first-hit shadow ray uses its own random numbers (5.4).
- The dense-light edges of a glowstone ceiling are up to ~10 % brighter than in 4.34: the soft cap had been compressing the noisier single list more than its real light.

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
