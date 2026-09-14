/*
=====================================================================
  program/deferred2.glsl - GÜRÜLTÜ GİDERME + AYDINLATMA + GÖKYÜZÜ
=====================================================================
  Opak sahnenin son rengini üretir:
    1. GI geçmişini komşu piksellerle yumuşatır (kenarları koruyarak)
    2. Güneş/ay ışığını yumuşak gölgeyle hesaplar
    3. Vanilla blok ışığını, el ışığını ve yüzey ışımasını ekler
    4. Gökyüzü piksellerine gökyüzü, güneş diski ve bulutları çizer
  Çıktılar:
    colortex0: aydınlatılmış HDR sahne (albedonun yerine yazılır)
    colortex6: yansıma bilgisi (composite okur)

  Son renk formülü:
    renk = albedo * (doğrudan + dolaylı*GI_STRENGTH + blokIşığı + elIşığı + minIşık)
         + güneşParlaması + ışıma
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

uniform sampler2D colortex0; // albedo (gökyüzünde: yıldız/ay)
uniform sampler2D colortex1; // normal + ışık haritası
uniform sampler2D colortex2; // malzeme
uniform sampler2D colortex4; // biriktirilmiş GI
uniform sampler2D depthtex0;

/* RENDERTARGETS: 0,6 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outReflectInfo;

// ---------------------------------------------------------------------
//  Kenar korumalı uzamsal gürültü giderici
//  Komşu pikseller şu durumlarda karışıma daha az katılır:
//    - normalleri farklıysa (köşe, kenar)
//    - aynı düzlemde değillerse (derinlik farkı)
//  Yarıçap, geçmiş ne kadar doluysa o kadar küçülür.
// ---------------------------------------------------------------------
vec3 denoiseGI(ivec2 px, vec3 centerPlayer, vec3 N) {
    vec4 center = texelFetch(colortex4, px, 0);
#ifndef GI_DENOISE
    return center.rgb;
#else
    vec2 res = vec2(viewWidth, viewHeight);
    float radius = mix(GI_DENOISE_RADIUS, GI_DENOISE_MIN_RADIUS, saturate(center.a / float(GI_TEMPORAL_FRAMES)));
    if (radius < 0.5) return center.rgb;

    float planeTolerance = 0.06 + length(centerPlayer) * 0.012;
    mat2 rot = rotate2D(ign(gl_FragCoord.xy) * TAU);

    vec3 sum = center.rgb;
    float weightSum = 1.0;

    for (int i = 0; i < GI_DENOISE_SAMPLES; i++) {
        ivec2 sp = ivec2(gl_FragCoord.xy + poissonTap(i, rot) * radius);
        if (any(lessThan(sp, ivec2(0))) || any(greaterThanEqual(sp, ivec2(res)))) continue;

        float sDepth = texelFetch(depthtex0, sp, 0).r;
        if (sDepth >= 1.0) continue;
        int sMat = int(texelFetch(colortex2, sp, 0).r * 255.0 + 0.5);
        if (sMat == MAT_UNLIT || sMat == MAT_HAND) continue;

        vec3 sN = decodeNormal(texelFetch(colortex1, sp, 0).rg);
        vec3 sPlayer = viewToPlayer(screenToView((vec2(sp) + 0.5) / res, sDepth));

        float wNormal = pow(saturate(dot(N, sN)), GI_DENOISE_NORMAL_WEIGHT);
        float wPlane  = exp(-abs(dot(N, sPlayer - centerPlayer)) / planeTolerance);
        float w = wNormal * wPlane;

        sum += texelFetch(colortex4, sp, 0).rgb * w;
        weightSum += w;
    }
    return sum / weightSum;
#endif
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec4 albedoTex = texelFetch(colortex0, px, 0);
    float depth = texelFetch(depthtex0, px, 0).r;
    vec3 sunDir = getSunDir();
    bool debugHere = debugActive(texcoord) && isDeferredDebugView(DEBUG_VIEW);

    vec3 viewPos = screenToView(texcoord, depth);

    // ------------------------------------------------------------ Gökyüzü
    if (depth >= 1.0) {
        vec3 dir = normalize(mat3(gbufferModelViewInverse) * viewPos);
        outColor = debugHere ? vec4(0.0, 0.0, 0.0, 1.0) : vec4(getFullSky(dir, sunDir, albedoTex.rgb), 1.0);
        outReflectInfo = vec4(0.0);
        return;
    }

    vec4 matData = texelFetch(colortex2, px, 0);
    int material = int(matData.r * 255.0 + 0.5);

    // ---------------------------------- İleri çizilmiş (parçacık, çizgi...)
    if (material == MAT_UNLIT) {
        vec3 passColor = albedoTex.rgb;
        if (debugHere) passColor = DEBUG_VIEW == DBG_ALBEDO ? albedoTex.rgb : vec3(0.0);
        outColor = vec4(passColor, 1.0);
        outReflectInfo = vec4(0.0);
        return;
    }

    // ---------------------------------------------------- G-buffer'ı çöz
    vec4 normalLight = texelFetch(colortex1, px, 0);
    vec3 N = decodeNormal(normalLight.rg);
    float lmBlock = normalLight.b;
    float lmSky = normalLight.a;

    int emissionId = int(matData.g * 255.0 + 0.5);
    float smoothness = matData.b;
    bool isMetal = matData.a > 0.9;

    vec3 albedo = toLinear(albedoTex.rgb);
    vec3 playerPos = viewToPlayer(viewPos);
    vec3 viewDir = normalize(playerPos);
    float dist = length(playerPos);

    vec3 lightDir = getLightDir();
    vec3 directLight = getDirectLight(sunDir);
    vec3 skyAmbient = getSkyAmbient(sunDir);

    // ------------------------------------------ Dolaylı ışık (ışın izleme)
    vec3 indirect;
    float rtFade = 0.0; // 1 = bu piksel voxel alanının içinde
    if (material == MAT_HAND) {
        indirect = skyAmbient * skyExposureFromLightmap(lmSky);
    } else {
        indirect = denoiseGI(px, playerPos, N);
        #ifdef GI_ENABLED
            rtFade = voxelVolumeFade(playerPos);
        #endif
    }
    // Renk taşımasını belirginleştir: gri tondan uzaklaştır
    indirect = max(mix(vec3(luminance(indirect)), indirect, GI_SATURATION), vec3(0.0));

    // ------------------------------------------------- Doğrudan güneş/ay
    vec3 direct = vec3(0.0);
    vec3 specular = vec3(0.0);
    vec3 shadowTerm = vec3(1.0); // renkli camdan geçen ışık renkli olur
#ifdef OVERWORLD
    float NdotL = dot(N, lightDir);
    float diffuse = saturate(NdotL);
    vec3 shadowNormal = N;

    #ifdef FOLIAGE_TRANSLUCENCY
        if (material == MAT_PLANT) {
            diffuse = 0.4 + 0.6 * saturate(NdotL);
            shadowNormal = lightDir;
        } else if (material == MAT_LEAVES) {
            diffuse = mix(abs(NdotL), 1.0, 0.25) * (NdotL < 0.0 ? 0.6 : 1.0);
            if (NdotL < 0.0) shadowNormal = -N; // ışık yaprağın arkasından geçiyor
        }
    #endif

    if (diffuse > 0.0 || (debugHere && DEBUG_VIEW == DBG_SHADOW)) {
        if (material == MAT_HAND) {
            shadowTerm = vec3(smoothstep(0.7, 0.95, lmSky)); // elin gerçek konumu yok, ışık haritasıyla tahmin
        } else {
            shadowTerm = shadowFiltered(playerPos, shadowNormal, abs(NdotL), gl_FragCoord.xy);
            #ifdef LEAK_FIX
                shadowTerm *= smoothstep(0.0, 0.2, lmSky); // derin mağarada güneş olmaz
            #endif
        }
        direct = directLight * diffuse * shadowTerm;

        #ifdef SUN_SPECULAR
        // GGX güneş parlaması (pürüzsüz yüzeyler)
        if (smoothness > 0.05 && NdotL > 0.0) {
            float alpha = max((1.0 - smoothness) * (1.0 - smoothness), 0.02);
            float a2 = alpha * alpha;
            vec3 H = normalize(lightDir - viewDir);
            float NdotH = saturate(dot(N, H));
            float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
            float D = a2 / (PI * denom * denom);
            vec3 F0 = isMetal ? albedo : vec3(max(matData.a, 0.02));
            float VdotH = saturate(dot(-viewDir, H));
            vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
            specular = directLight * shadowTerm * min(D * 0.25, 60.0) * F * NdotL;
        }
        #endif
    }
#endif

    // --------------------------------------------------------- Blok ışığı
    // Vanilla ışık haritası sabit bir taban verir. Voxel alanının içinde
    // ışın izlenen ışıma zaten renkli ve gölgeli ışık getirdiği için taban azaltılır.
    vec3 blockLight = BLOCKLIGHT_COLOR * pow(lmBlock, BLOCKLIGHT_CURVE) * 1.8 * BLOCKLIGHT_STRENGTH
                    * mix(1.0, LIGHTMAP_RT_BLEND, rtFade);

    vec3 handLight = vec3(0.0);
    #ifdef HAND_LIGHT
        float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;
        if (material == MAT_HAND) {
            handLight = BLOCKLIGHT_COLOR * held * HAND_LIGHT_STRENGTH * 0.55;
        } else {
            float falloff = 0.18 / (HAND_LIGHT_RANGE * HAND_LIGHT_RANGE);
            handLight = BLOCKLIGHT_COLOR * held * HAND_LIGHT_STRENGTH / (1.0 + dist * dist * falloff)
                      * (0.4 + 0.6 * saturate(dot(N, -viewDir)));
        }
    #endif

    // ----------------------------------------------------------- Işıma
    vec3 emission = vec3(0.0);
    if (material == MAT_EMISSIVE) {
        if (emissionId >= 16) {
            emission = albedo * (float(emissionId - 16) / 239.0) * 6.0 * EMISSION_STRENGTH; // LabPBR
        } else if (emissionId == TINTED_CATEGORY || emissionId == CUSTOM_CATEGORY) {
            // Işık rengi bloğun kendi doku renginden gelir (renkli mumlar, beton, yün...)
            float intensity = emissionId == CUSTOM_CATEGORY ? EMIT_CUSTOM_I : EMIT_TINTED_I;
            float mask = emissionId == CUSTOM_CATEGORY ? 1.0 : pow(saturate(maxOf(albedoTex.rgb)), 2.0);
            emission = tintedEmission(albedo, intensity) * mask * 0.5 * EMISSION_STRENGTH;
        } else if (emissionId > 0) {
            float mask = pow(saturate(maxOf(albedoTex.rgb)), 3.0); // dokunun parlak kısımları daha çok parlar
            emission = albedo * luminance(emissionColor(emissionId)) * mask * 1.5 * EMISSION_STRENGTH;
        }
    }

    // --------------------------------------------------------- Birleştir
    float metalness = 0.0;
    #if defined RT_REFLECTIONS && defined BLOCK_REFLECTIONS
        if (isMetal) metalness = 1.0; // metalin rengi composite'teki yansımadan gelir
    #endif
    vec3 minimumLight = vec3(MIN_LIGHT) + vec3(nightVision * 0.25);
    vec3 color = albedo * (1.0 - metalness) * (direct + indirect * GI_STRENGTH + blockLight + handLight + minimumLight)
               + specular + emission;

    // ---------------------------------------------- Hata ayıklama çıktısı
    if (debugHere) {
        if      (DEBUG_VIEW == DBG_ALBEDO)      color = albedoTex.rgb;
        else if (DEBUG_VIEW == DBG_GI_DENOISED) color = indirect * GI_STRENGTH;
        else if (DEBUG_VIEW == DBG_RT_LIGHTS)   color = indirect;
        else if (DEBUG_VIEW == DBG_DIRECT)      color = direct + specular;
        else if (DEBUG_VIEW == DBG_SHADOW)      color = shadowTerm;
        else if (DEBUG_VIEW == DBG_BLOCKLIGHT)  color = blockLight + handLight;
        else if (DEBUG_VIEW == DBG_EMISSION)    color = emission;
    }

    vec3 F0 = isMetal ? albedo : vec3(max(matData.a, 0.02));
    outColor = vec4(max(color, vec3(0.0)), 1.0);
    outReflectInfo = vec4(saturate(F0), material == MAT_HAND ? 0.0 : smoothness);
}

#endif
