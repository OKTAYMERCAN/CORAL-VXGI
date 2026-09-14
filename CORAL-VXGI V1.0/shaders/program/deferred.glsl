/*
=====================================================================
  program/deferred.glsl - IŞIN İZLEMELİ GLOBAL AYDINLATMA (GI)
=====================================================================
  Opak geometri çizildikten sonra çalışan ilk tam ekran geçiş.
  Her piksel için yüzeyin yarımküresine KOSİNÜS AĞIRLIKLI tek bir ışın
  gönderir ve voxel ızgarasında izler:
    - ışın bir bloğa çarparsa: o bloğun güneşten aldığı ışık + ışıması
    - hiçbir şeye çarpmazsa  : gökyüzünün o yöndeki rengi
  Sonuç "bu yüzeye gelen dolaylı ışık"tır ve colortex3'e yazılır.

  Tek ışın çok gürültülüdür; deferred1 kareler arasında biriktirir,
  deferred2 komşu piksellerle yumuşatır.
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

uniform sampler2D colortex1; // normal + ışık haritası
uniform sampler2D colortex2; // malzeme
uniform sampler2D depthtex0; // opak derinlik

/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 outGI;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex0, px, 0).r;
    int material = int(texelFetch(colortex2, px, 0).r * 255.0 + 0.5);

    // Gökyüzü, ileri çizilmiş şeyler ve el için ışın izlenmez
    if (depth >= 1.0 || material == MAT_UNLIT || material == MAT_HAND) {
        outGI = vec4(0.0);
        return;
    }

    vec4 normalLight = texelFetch(colortex1, px, 0);
    vec3 N = decodeNormal(normalLight.rg);
    float lmSky = normalLight.a;

    vec3 playerPos = viewToPlayer(screenToView(texcoord, depth));

    vec3 sunDir      = getSunDir();
    vec3 lightDir    = getLightDir();
    vec3 directLight = getDirectLight(sunDir);
    vec3 skyAmbient  = getSkyAmbient(sunDir);
    float sunExposure = sunExposureFromLightmap(lmSky);
    float skyExposure = skyExposureFromLightmap(lmSky);

    // Voxel alanı dışında kullanılan basit ortam ışığı
    vec3 gi = skyAmbient * skyExposure;

#ifdef GI_ENABLED
    float fade = voxelVolumeFade(playerPos);
    if (fade > 0.0) {
        // ---------------------------------------------------------------
        //  Yol izleme (path tracing)
        //  Işın yüzeyden çıkar, bir bloğa çarpar, oradan tekrar sekerek
        //  devam eder. Her sekmede "throughput" çarpanı o yüzeyin rengiyle
        //  çarpılır; turuncu bir tavandan seken ışık bu sayede turuncu olur.
        // ---------------------------------------------------------------
        #ifdef DEBUG_FREEZE_NOISE
            uint seed = 0u;
        #else
            uint seed = uint(frameCounter);
        #endif

        vec3 radiance   = vec3(0.0);
        vec3 throughput = vec3(1.0);
        vec3 rayNormal  = N;
        vec3 surfaceVoxel = playerToVoxel(playerPos + N * 0.02);
        vec3 rayOrigin  = surfaceVoxel;
        vec3 rayDir     = cosineHemisphere(rayNormal, hash33(uvec3(uvec2(px), seed)).xy);

        vec3 neeOnly = vec3(0.0);
#ifdef RT_LIGHTS
        // Doğrudan ışık örnekleme: meşale, lav, portal gibi kaynaklara gölge
        // ışını gönderilir. Bu olmadan blok ışığı gölge oluşturmaz.
        neeOnly = sampleBlockLights(surfaceVoxel, N, hash33(uvec3(uvec2(px), seed * 7919u + 13u)));
        radiance += neeOnly;
#endif

        int   steps    = GI_MAX_STEPS;
        float rayDist  = GI_MAX_DISTANCE;

        for (int bounce = 0; bounce < GI_BOUNCES; bounce++) {
            vec3 hitPos, hitNormal, tint;
            vec4 voxel;
            float emitBoost;

            if (traceVoxels(rayOrigin, rayDir, steps, rayDist, hitPos, hitNormal, voxel, emitBoost, tint)) {
                throughput *= tint; // yolda renkli camdan geçtiyse

                // Son sekmede, daha ileri sekmeleri taklit eden ortam ışığı eklenir
                float ambientScale = (bounce == GI_BOUNCES - 1) ? GI_HIT_AMBIENT : 0.0;
                radiance += throughput * shadeVoxelHit(hitPos, hitNormal, voxel, lightDir, directLight,
                                                       skyAmbient, sunExposure, skyExposure,
                                                       emitBoost, ambientScale);

                // Kosinüs örneklemede difüz sekmenin çarpanı doğrudan albedodur
                throughput *= toLinear(voxel.rgb);
                if (maxOf(throughput) < 0.015) break; // ışık bitti, devam etmenin anlamı yok

                vec3 rnd2 = hash33(uvec3(uvec2(px), seed * 9781u + uint(bounce) + 1u));

#ifdef RT_LIGHTS
                // İlk sekmede de ışık kaynakları örneklenir; meşale ışığı böylece
                // duvarlardan sekerek ortama renk verir. Maliyet için tek sekmeyle sınırlı.
                if (bounce == 0) {
                    radiance += throughput * sampleBlockLights(hitPos + hitNormal * 0.02, hitNormal, rnd2);
                }
#endif
                rayNormal = hitNormal;
                rayOrigin = hitPos + hitNormal * 0.02;
                rayDir    = cosineHemisphere(rayNormal, rnd2.xy);
                steps     = max(steps / 2, 8);   // sonraki sekmeler daha kısa izlenir
                rayDist  *= 0.5;
            } else {
                throughput *= tint;
                radiance += throughput * getSkyRadiance(rayDir, sunDir) * GI_SKY_STRENGTH * skyExposure;
                break;
            }
        }

        if (DEBUG_VIEW == DBG_RT_LIGHTS) radiance = neeOnly; // hata ayıklama: yalnızca blok ışıkları

        // Çok parlak tek örnekler (ör. meşaleye isabet) beyaz noktalar yapar; sınırla
        float lum = luminance(radiance);
        radiance *= min(1.0, GI_FIREFLY_CLAMP / max(lum, 1e-4));

        gi = mix(gi, radiance, fade);
    }
#endif

    outGI = vec4(max(gi, vec3(0.0)), 1.0);
}

#endif
