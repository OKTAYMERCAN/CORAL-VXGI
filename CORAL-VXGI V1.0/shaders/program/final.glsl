/*
=====================================================================
  program/final.glsl - SON İŞLEME + HATA AYIKLAMA GÖRÜNÜMLERİ
=====================================================================
  Ekrana giden son geçiş:
    1. Bloom (colortex0'ın mipmap seviyelerinden)
    2. Pozlama (sabit + mağara/gece için otomatik)
    3. Ton eşleme (HDR -> ekran), doygunluk, kontrast, gamma
    4. Kenar kararması ve titreşim (dithering)
  Hata ayıklama açıksa, istenen ara veri bunun yerine gösterilir.
=====================================================================
*/
#include "/lib/settings.glsl"
#include "/lib/pipeline.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/materials.glsl"
#include "/lib/space.glsl"
#include "/lib/shadows.glsl"
#include "/lib/sky.glsl"
#include "/lib/voxel.glsl"
#include "/lib/debug.glsl"

#ifdef VERTEX_SHADER
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
#endif

#ifdef FRAGMENT_SHADER

in vec2 texcoord;

uniform sampler2D colortex0; // son HDR sahne
uniform sampler2D colortex1; // normal + ışık haritası (hata ayıklama)
uniform sampler2D colortex2; // malzeme (hata ayıklama)
uniform sampler2D colortex3; // ham GI (hata ayıklama)
uniform sampler2D colortex4; // GI geçmişi (hata ayıklama)
uniform sampler2D colortex5; // saydam veri (hata ayıklama)
uniform sampler2D colortex6; // yansıma bilgisi (hata ayıklama)
uniform sampler2D depthtex0;
const bool colortex0MipmapEnabled = true; // bloom için mipmap üret

layout(location = 0) out vec4 fragColor;

// ---------------------------------------------------------------------
//  Ton eşleme yöntemleri (TONEMAP ayarı)
// ---------------------------------------------------------------------
// 0: ACES (film görünümü, sinematik kontrast)
vec3 tonemapACES(vec3 x) {
    const mat3 inputM = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    const mat3 outputM = mat3(
         1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    x = inputM * x;
    x = (x * (x + 0.0245786) - 0.000090537) / (x * (0.983729 * x + 0.4329510) + 0.238081);
    return saturate(outputM * x);
}

// 1: Reinhard (yumuşak, parlaklığı korur)
vec3 tonemapReinhard(vec3 x) {
    return x / (1.0 + luminance(x));
}

// 2: Uncharted 2 / Hable (oyun filmik)
vec3 hableCurve(vec3 x) {
    const float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}
vec3 tonemapHable(vec3 x) {
    return saturate(hableCurve(x * 2.0) / hableCurve(vec3(11.2)));
}

vec3 applyTonemap(vec3 x) {
    if (TONEMAP == 1) return saturate(tonemapReinhard(x));
    if (TONEMAP == 2) return tonemapHable(x);
    if (TONEMAP == 3) return saturate(x); // 3: yok (sadece kırp)
    return tonemapACES(x);
}

// ---------------------------------------------------------------------
//  final geçişinde üretilen hata ayıklama görünümleri
// ---------------------------------------------------------------------
vec3 finalDebugView(int view, ivec2 px, vec3 sceneColor) {
    float depth = texelFetch(depthtex0, px, 0).r;
    vec4 normalLight = texelFetch(colortex1, px, 0);
    vec4 matData = texelFetch(colortex2, px, 0);
    bool sky = depth >= 1.0;

    if (view == DBG_NORMALS) {
        return sky ? vec3(0.0) : decodeNormal(normalLight.rg) * 0.5 + 0.5;
    }
    if (view == DBG_LIGHTMAP) {
        // Kırmızı = blok ışığı, Mavi = gökyüzü ışığı
        return sky ? vec3(0.0) : vec3(normalLight.b, 0.0, normalLight.a);
    }
    if (view == DBG_MATERIAL) {
        return sky ? vec3(0.0, 0.0, 0.15) : debugMaterialColor(int(matData.r * 255.0 + 0.5));
    }
    if (view == DBG_SMOOTHNESS) {
        // Kırmızı = pürüzsüzlük, Yeşil = F0, Mavi = metal
        return sky ? vec3(0.0) : vec3(matData.b, matData.a, matData.a > 0.9 ? 1.0 : 0.0);
    }
    if (view == DBG_EMISSION_ID) {
        if (sky) return vec3(0.0);
        int id = int(matData.g * 255.0 + 0.5);
        if (id >= 16) return vec3(float(id - 16) / 239.0);           // LabPBR: beyaz tonu = güç
        if (id > 0) { vec3 c = emissionColor(id); return c / max(maxOf(c), 0.001); }
        return vec3(0.08);
    }
    if (view == DBG_DEPTH) {
        return sky ? vec3(0.1, 0.1, 0.3) : vec3(sqrt(saturate(linearizeDepth(depth) / far)));
    }
    if (view == DBG_GI_RAW) {
        return debugCompress(texelFetch(colortex3, px, 0).rgb);
    }
    if (view == DBG_GI_ACCUM) {
        return debugCompress(texelFetch(colortex4, px, 0).rgb);
    }
    if (view == DBG_GI_HISTORY) {
        // Kırmızı = geçmiş yeni sıfırlandı, Yeşil = tamamen birikti
        if (sky) return vec3(0.0);
        float t = saturate(texelFetch(colortex4, px, 0).a / float(GI_TEMPORAL_FRAMES));
        return vec3(1.0 - t, t, 0.0);
    }
    if (view == DBG_VOXEL_SHAPES) {
        // Kameradan voxel ızgarasına ışın: gri = tam küp, sarıdan kırmızıya = giderek küçülen şekil
        vec3 camPlayer = gbufferModelViewInverse[3].xyz;
        vec3 dir = normalize(mat3(gbufferModelViewInverse) * screenToView(texcoord, 1.0));
        vec3 hitPos, hitNormal;
        vec4 voxel;
        float boost;
        if (traceVoxels(playerToVoxel(camPlayer), dir, 512, 512.0, hitPos, hitNormal, voxel, boost)) {
            float shade = 0.45 + 0.55 * saturate(dot(hitNormal, normalize(vec3(0.4, 1.0, 0.3))));
            float small = saturate((boost - 1.0) / max(EMISSION_SHAPE_BOOST_MAX - 1.0, 0.001));
            vec3 tint = boost <= 1.001 ? vec3(0.55) : mix(vec3(1.0, 0.95, 0.2), vec3(1.0, 0.15, 0.1), small);
            return tint * shade;
        }
        return vec3(0.02, 0.02, 0.06);
    }
    if (view == DBG_VOXEL_ALBEDO || view == DBG_VOXEL_TYPES) {
        // Kameradan voxel ızgarasına doğrudan ışın: ışın izleyicinin "gördüğü" dünya
        vec3 camPlayer = gbufferModelViewInverse[3].xyz;
        vec3 dir = normalize(mat3(gbufferModelViewInverse) * screenToView(texcoord, 1.0));
        vec3 hitPos, hitNormal;
        vec4 voxel;
        if (traceVoxels(playerToVoxel(camPlayer), dir, 512, 512.0, hitPos, hitNormal, voxel)) {
            float shade = 0.45 + 0.55 * saturate(dot(hitNormal, normalize(vec3(0.4, 1.0, 0.3))));
            if (view == DBG_VOXEL_ALBEDO) return voxel.rgb * shade;
            return debugVoxelTypeColor(int(voxel.a * 255.0 + 0.5)) * shade;
        }
        return vec3(0.02, 0.02, 0.06);
    }
    if (view == DBG_VOXEL_RANGE) {
        // Yeşil = ışın izleme alanı içi, Sarı = geçiş bölgesi, Kırmızı = dışı (ışık haritası kullanılır)
        if (sky) return sceneColor * 0.5;
        float fade = voxelVolumeFade(viewToPlayer(screenToView(texcoord, depth)));
        vec3 tint = mix(vec3(1.0, 0.15, 0.1), vec3(0.2, 1.0, 0.3), fade);
        if (fade > 0.05 && fade < 0.95) tint = vec3(1.0, 0.9, 0.1);
        return tint * (0.25 + 0.75 * luminance(sceneColor));
    }
    if (view == DBG_TRANSLUCENT) {
        // Mavi tonlu = su, beyaz tonlu = cam/buz; renk normali gösterir
        vec4 tr = texelFetch(colortex5, px, 0);
        if (tr.b < 0.25) return vec3(0.0);
        vec3 n = decodeNormal(tr.rg) * 0.5 + 0.5;
        return tr.b > 0.75 ? n * vec3(0.5, 0.8, 1.0) : n;
    }
    return sceneColor;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 hdr = texture(colortex0, texcoord).rgb;
    vec3 color = hdr;

    // --------------------------------------------------------- Bloom
#ifdef BLOOM
    vec3 bloom = vec3(0.0);
    float weightSum = 0.0;
    for (int i = 2; i <= 7; i++) {
        float w = 1.0 / float(i);
        bloom += textureLod(colortex0, texcoord, float(i)).rgb * w;
        weightSum += w;
    }
    bloom /= weightSum;
    color = mix(color, bloom, BLOOM_STRENGTH) + bloom * BLOOM_STRENGTH * 0.5;
#endif

    // ------------------------------------------------------- Pozlama
    float exposure = EXPOSURE;
#ifdef AUTO_EXPOSURE
    float eyeSky = getEyeSkylight();
    #ifdef OVERWORLD
        float night = 1.0 - smoothstep(-0.15, 0.1, getSunDir().y);
        exposure *= mix(CAVE_EXPOSURE, 1.0, eyeSky) * mix(1.0, NIGHT_EXPOSURE, night * eyeSky);
    #else
        exposure *= 1.6;
    #endif
#endif
    color *= exposure;

    // ---------------------------------------------- Ton eşleme + renk
    color = applyTonemap(color);
    float l = luminance(color);
    color = max(mix(vec3(l), color, SATURATION), 0.0);
    color = toSRGB(color);
    color = saturate((color - 0.5) * CONTRAST + 0.5);

    if (VIGNETTE_STRENGTH > 0.0) {
        vec2 c = texcoord - 0.5;
        color *= 1.0 - VIGNETTE_STRENGTH * dot(c, c) * 2.0;
    }

    // ------------------------------------------------ Hata ayıklama
    if (debugActive(texcoord)) {
        int view = DEBUG_VIEW;
        if (isDeferredDebugView(view) || isCompositeDebugView(view)) {
            vec3 raw = texelFetch(colortex0, px, 0).rgb;
            color = isHdrDebugView(view) ? debugCompress(raw) : raw; // albedo ve gölge ham gösterilir
        } else {
            color = finalDebugView(view, px, color);
        }
    }

    #ifdef DEBUG_SPLIT
        if (DEBUG_VIEW != DBG_OFF && abs(gl_FragCoord.x - viewWidth * 0.5) < 1.0) color = vec3(1.0); // ayırıcı çizgi
    #endif

    #ifdef DEBUG_SHADOW_OVERLAY
        // Sol alt köşede gölge haritası (koyu = yakın, açık = uzak)
        float overlaySize = min(viewHeight * 0.35, 512.0);
        if (gl_FragCoord.x < overlaySize && gl_FragCoord.y < overlaySize) {
            float sd = texture(shadowtex1, gl_FragCoord.xy / overlaySize).r;
            color = vec3(pow(sd, 8.0));
        }
    #endif

    #ifdef DEBUG_NAN_CHECK
        // Bozuk değerler: pembe
        vec3 h = texelFetch(colortex4, px, 0).rgb;
        if (any(isnan(hdr)) || any(isinf(hdr)) || any(isnan(h)) || any(isinf(h))) color = vec3(1.0, 0.0, 1.0);
    #endif

    #ifdef DITHERING
        color += (ign(gl_FragCoord.xy) - 0.5) / 255.0; // renk bantlanmasını kır
    #endif

    fragColor = vec4(color, 1.0);
}

#endif
