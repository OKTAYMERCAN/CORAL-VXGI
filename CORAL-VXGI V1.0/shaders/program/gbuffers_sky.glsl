/*
=====================================================================
  program/gbuffers_sky.glsl - VANİLLA GÖKYÜZÜ GEOMETRİSİ
=====================================================================
    SKY_BASIC     gbuffers_skybasic     gökyüzü kubbesi, yıldızlar
    SKY_TEXTURED  gbuffers_skytextured  güneş, ay, End gökyüzü dokusu

  Asıl gökyüzü rengi, güneş diski ve bulutlar deferred2'de çizilir.
  Burada yalnızca yıldızlar, ay ve özel gökyüzü dokuları korunur;
  deferred2 bunları colortex0'dan okuyup gökyüzüne ekler.
=====================================================================
*/
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec2 texcoord;
out vec4 glcolor;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

in vec2 texcoord;
in vec4 glcolor;

uniform int renderStage;     // Iris: şu an ne çiziliyor (MC_RENDER_STAGE_*)
uniform sampler2D gtexture;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
#ifdef SKY_BASIC
    if (renderStage != MC_RENDER_STAGE_STARS) discard; // kubbe ve gün batımı yelpazesini atla
    outColor = vec4(toLinear(glcolor.rgb) * STARS_BRIGHTNESS, glcolor.a);
#else
    vec4 tex = texture(gtexture, texcoord) * glcolor;
    #ifdef OVERWORLD
        #ifdef SUN_DISC
            if (renderStage == MC_RENDER_STAGE_SUN) discard; // yerine analitik güneş diski çizilir
        #endif
        float boost = renderStage == MC_RENDER_STAGE_MOON ? MOON_TEXTURE_BRIGHTNESS : 1.0;
        outColor = vec4(toLinear(tex.rgb) * boost, tex.a);
    #else
        outColor = vec4(toLinear(tex.rgb) * 0.6, tex.a); // End gökyüzü dokusu
    #endif
#endif
}

#endif
