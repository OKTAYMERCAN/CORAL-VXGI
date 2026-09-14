/*
=====================================================================
  program/gbuffers_forward.glsl - İLERİ ÇİZİLEN PROGRAMLAR
=====================================================================
  Bunlar ertelenmiş aydınlatmadan GEÇMEZ; rengi kendileri hesaplar ve
  colortex2'ye malzeme 0 (MAT_UNLIT) yazarak deferred2'ye "bana dokunma"
  derler. (colortex2 karışımı shaders.properties'de kapatılmıştır.)

    FWD_BASIC     gbuffers_basic          blok seçim çizgisi, ipler
    FWD_TEXTURED  gbuffers_textured(_lit) parçacıklar
    FWD_WEATHER   gbuffers_weather        yağmur, kar
    FWD_EMISSIVE  gbuffers_spidereyes     örümcek/enderman gözleri
                  gbuffers_beaconbeam     fener ışını
    FWD_GLINT     gbuffers_armor_glint    büyü parıltısı
    FWD_DAMAGED   gbuffers_damagedblock   blok kırılma çatlakları
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

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 playerPos;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = normalizeLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    glcolor  = gl_Color;

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
in vec3 playerPos;

uniform sampler2D gtexture;

// Yağmur, parıltı ve çatlaklar deferred'dan sonra/üstüne çizilir; malzeme yazmaları gerekmez
#if defined FWD_WEATHER || defined FWD_GLINT || defined FWD_DAMAGED
    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 outColor;
#else
    /* RENDERTARGETS: 0,2 */
    layout(location = 0) out vec4 outColor;
    layout(location = 1) out vec4 outMaterial;
#endif

void main() {
#if defined FWD_BASIC
    vec4 col = glcolor;
    if (col.a < 0.01) discard;
    outColor = vec4(toLinear(col.rgb), col.a);
    outMaterial = vec4(0.0);

#elif defined FWD_TEXTURED
    vec4 col = texture(gtexture, texcoord) * glcolor;
    if (col.a < 0.1) discard;
    vec3 light = forwardLighting(playerPos, lmcoord, vec3(0.0, 1.0, 0.0), false);
    outColor = vec4(toLinear(col.rgb) * light, col.a);
    outMaterial = vec4(0.0);

#elif defined FWD_WEATHER
    vec4 col = texture(gtexture, texcoord) * glcolor;
    if (col.a < 0.01) discard;
    vec3 sunDir = getSunDir();
    vec3 light = getSkyAmbient(sunDir) * 1.5 * lmcoord.y + BLOCKLIGHT_COLOR * pow(lmcoord.x, BLOCKLIGHT_CURVE) + vec3(0.02);
    outColor = vec4(toLinear(col.rgb) * light, col.a * 0.6);

#elif defined FWD_EMISSIVE
    vec4 col = texture(gtexture, texcoord) * glcolor;
    if (col.a < 0.01) discard;
    outColor = vec4(toLinear(col.rgb) * 3.0, col.a);
    outMaterial = vec4(0.0);

#elif defined FWD_GLINT
    vec4 col = texture(gtexture, texcoord) * glcolor;
    outColor = vec4(toLinear(col.rgb) * 0.6, col.a);

#elif defined FWD_DAMAGED
    // Çatlaklar aydınlatmadan önce albedo ile çarpılır (vanilla çarpımsal karışım)
    vec4 col = texture(gtexture, texcoord) * glcolor;
    if (col.a < 0.01) discard;
    outColor = col;

#else
    // Tanımsız program: fark edilsin diye pembe
    outColor = vec4(1.0, 0.0, 1.0, 1.0);
    outMaterial = vec4(0.0);
#endif
}

#endif
