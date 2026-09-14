/*
=====================================================================
  program/gbuffers_water.glsl - SAYDAM YÜZEYLER
=====================================================================
    GBUFFERS_WATER       gbuffers_water       su, renkli cam, buz
    GBUFFERS_HAND_WATER  gbuffers_hand_water  elde tutulan saydam eşyalar

  Deferred geçişlerden SONRA çizilir. İki çıktı:
    colortex0 : ileri aydınlatılmış renk (arkadaki sahneyle karışır)
    colortex5 : normal + tür + gökyüzü ışığı (karışımsız)
  composite geçişi colortex5'i okuyarak yansıma ve su emilimi ekler.
=====================================================================
*/
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/materials.glsl"
#include "/lib/shadows.glsl"
#include "/lib/sky.glsl"
#include "/lib/forward.glsl"

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

    #ifdef GBUFFERS_WATER
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

uniform sampler2D gtexture;

/* RENDERTARGETS: 0,5 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outTranslucent;

// Dalga yüksekliği: farklı yönlere kayan gürültü katmanlarının toplamı
float waterHeight(vec2 p) {
    float t = frameTimeCounter * WATER_WAVE_SPEED;
    p /= WATER_WAVE_SCALE;
    float h = 0.0;
    h += valueNoise(p * 0.35 + vec2( t * 0.35,  t * 0.20)) * 0.55;
    h += valueNoise(p * 0.90 + vec2(-t * 0.55,  t * 0.45)) * 0.28;
    h += valueNoise(p * 2.10 + vec2( t * 0.80, -t * 0.70)) * 0.12;
    h += sin(dot(p, vec2(0.55, 0.83)) * 1.6 + t * 1.8) * 0.05;
    return h;
}

// Yükseklik alanının eğiminden normal hesapla
vec3 waterNormal(vec2 p) {
    const float eps = 0.08;
    float h0 = waterHeight(p);
    float hx = waterHeight(p + vec2(eps, 0.0));
    float hz = waterHeight(p + vec2(0.0, eps));
    float strength = 0.35 * WATER_WAVE_STRENGTH;
    return normalize(vec3((h0 - hx) / eps * strength, 1.0, (h0 - hz) / eps * strength));
}

void main() {
    vec4 tex = texture(gtexture, texcoord);
    vec3 N = normalize(playerNormal);

    #ifdef GBUFFERS_WATER
        bool isWater = blockId == ID_WATER;
        vec4 albedo = vec4(tex.rgb * glcolor.rgb, tex.a); // alfa: separateAo nedeniyle köşe alfası kullanılmaz
    #else
        bool isWater = false;
        vec4 albedo = tex * glcolor;
    #endif

    if (albedo.a < 0.01) discard;

    #ifdef GBUFFERS_WATER
    // Saydam ışık kaynakları (Nether portalı gibi) kendi renginde parlar.
    // Saydam verisi 0 yazılır, böylece composite bunları cam sanıp yansıtmaz.
    if (isEmissiveCategory(blockId)) {
        vec3 base = toLinear(albedo.rgb);
        int category = blockId - ID_EMIT_FIRST + 1;
        vec3 emis = (category == TINTED_CATEGORY)
                  ? tintedEmission(base, EMIT_TINTED_I)
                  : base * luminance(emissionColor(category));
        outColor = vec4(base * 0.4 + emis * EMISSION_STRENGTH, albedo.a);
        outTranslucent = vec4(0.0);
        return;
    }
    #endif

    if (isWater) {
        #ifdef WATER_WAVES
            if (N.y > 0.5) N = waterNormal((playerPos + cameraPosition).xz); // sadece üst yüzey dalgalanır
        #endif
        vec3 tint = toLinear(glcolor.rgb); // biyom su rengi
        vec3 light = forwardLighting(playerPos, lmcoord, N, true);
        outColor = vec4(tint * 0.06 * light, WATER_SURFACE_OPACITY);
        outTranslucent = vec4(encodeNormal(N), 1.0, lmcoord.y);
    } else {
        vec3 light = forwardLighting(playerPos, lmcoord, N, true);
        outColor = vec4(toLinear(albedo.rgb) * light, albedo.a);
        outTranslucent = vec4(encodeNormal(N), 0.5, lmcoord.y);
    }
}

#endif
