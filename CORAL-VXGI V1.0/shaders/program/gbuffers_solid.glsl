/*
=====================================================================
  program/gbuffers_solid.glsl - OPAK GEOMETRİ -> G-BUFFER
=====================================================================
  Kullanan programlar (world0, world-1, world1 klasörlerindeki sarmalayıcılar):
    gbuffers_terrain   (GBUFFERS_TERRAIN)   arazi blokları
    gbuffers_entities  (GBUFFERS_ENTITIES)  canlılar, eşya çerçeveleri
    gbuffers_block     (GBUFFERS_BLOCK)     sandık, tabela gibi blok varlıkları
    gbuffers_hand      (GBUFFERS_HAND)      birinci şahıs el

  Burada IŞIK HESAPLANMAZ. Sadece yüzey bilgileri yazılır:
    colortex0: albedo   colortex1: normal + ışık haritası   colortex2: malzeme
  Aydınlatma deferred2 geçişinde yapılır.
=====================================================================
*/
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/materials.glsl"

// ================================================================ VERTEX
#ifdef VERTEX_SHADER

in vec4 mc_Entity;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 playerNormal;
out vec3 playerPos;
flat out int blockId;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = normalizeLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    glcolor  = gl_Color;
    playerNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

    #ifdef GBUFFERS_TERRAIN
        blockId = int(mc_Entity.x + 0.5);
    #else
        blockId = 0;
    #endif

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = mat3(gbufferModelViewInverse) * viewPos.xyz + gbufferModelViewInverse[3].xyz;
    gl_Position = gl_ProjectionMatrix * viewPos;
}

#endif

// ============================================================== FRAGMENT
#ifdef FRAGMENT_SHADER

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 playerNormal;
in vec3 playerPos;
flat in int blockId;

uniform sampler2D gtexture;  // blok/varlık dokusu
uniform sampler2D specular;  // LabPBR _s dokusu (yoksa siyah)
uniform vec4 entityColor;    // hasar alınca kırmızı parlama
uniform int blockEntityId;   // blok varlığının block.properties kimliği

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormalLight;
layout(location = 2) out vec4 outMaterial;

void main() {
    vec4 albedo = texture(gtexture, texcoord);
    #ifdef GBUFFERS_TERRAIN
        // separateAo=true: köşe alfası vanilla AO taşır. Işın izleme AO'yu zaten ürettiği için kullanılmaz.
        albedo.rgb *= glcolor.rgb;
    #else
        albedo *= glcolor;
    #endif
    if (albedo.a < 0.1) discard;

    #ifdef GBUFFERS_ENTITIES
        albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    #ifdef GBUFFERS_BLOCK
        // End portalı: kendi yıldızlı görünümünü çiz, aydınlatılmasın (MAT_UNLIT)
        if (blockEntityId == ID_END_PORTAL) {
            vec3 dir = normalize(playerPos);
            vec2 p = dir.xz / (abs(dir.y) + 0.35) * 30.0 + vec2(frameTimeCounter * 0.4, 0.0);
            float stars = step(0.975, hash12(floor(p)));
            vec3 col = vec3(0.015, 0.03, 0.04) + vec3(0.05, 0.16, 0.14) * valueNoise(p * 0.15) + vec3(0.5, 0.9, 1.0) * stars * 3.0;
            outAlbedo = vec4(col, 1.0);
            outNormalLight = vec4(encodeNormal(vec3(0.0, 1.0, 0.0)), 0.0, 0.0);
            outMaterial = vec4(0.0);
            return;
        }
    #endif

    vec3 N = normalize(playerNormal);
    int material = MAT_LIT;
    int emission = 0;      // 0 yok, 1..8 kategori, 16..255 LabPBR ışıma gücü
    float smoothness = 0.0;
    float f0 = 0.0;        // >= 0.9 metal demektir (LabPBR kuralı: 230/255)

    #ifdef GBUFFERS_TERRAIN
        if (blockId == ID_PLANT) {
            material = MAT_PLANT;
            N = vec3(0.0, 1.0, 0.0); // bitkiler üzerinde durdukları zemin gibi aydınlansın
        } else if (blockId == ID_LEAVES) {
            material = MAT_LEAVES;
        } else if (isEmissiveCategory(blockId) || isCustomEmitter(blockId)) {
            material = MAT_EMISSIVE;
            emission = emissionCategoryOf(blockId);
        } else if (blockId == ID_POLISHED || blockId == ID_CONCRETE || blockId == ID_MINERAL) {
            smoothness = POLISHED_SMOOTHNESS;
            f0 = 0.04;
        } else if (blockId == ID_METAL) {
            smoothness = METAL_SMOOTHNESS;
            f0 = 1.0;
        }
    #endif

    // LabPBR kaynak paketi haritaları varsayılanları geçersiz kılar
    vec4 spec = texture(specular, texcoord);
    #ifdef LABPBR
        if (spec.r > 0.0 || spec.g > 0.0) {
            smoothness = spec.r;
            f0 = spec.g;
        }
    #endif
    #ifdef LABPBR_EMISSION
        if (spec.a > 0.0 && spec.a < 0.999) { // LabPBR: 255 = ışıma yok
            float e = saturate(spec.a * 255.0 / 254.0);
            emission = 16 + int(e * 239.0 + 0.5);
            material = MAT_EMISSIVE;
        }
    #endif

    #ifdef GBUFFERS_HAND
        material = MAT_HAND;
    #endif

    #ifdef GBUFFERS_TERRAIN
        outAlbedo = vec4(albedo.rgb, 1.0);
    #else
        outAlbedo = albedo;
    #endif
    outNormalLight = vec4(encodeNormal(N), lmcoord);
    outMaterial = vec4(float(material) / 255.0, float(emission) / 255.0, smoothness, f0);
}

#endif
