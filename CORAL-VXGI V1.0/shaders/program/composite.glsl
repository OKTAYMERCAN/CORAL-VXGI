/*
=====================================================================
  program/composite.glsl - YANSIMALAR + SU + SİS
=====================================================================
  Saydam yüzeyler çizildikten sonra çalışır. Sırasıyla:
    1. Su: kalınlığa göre ışık emilimi ve suyun kendi rengi
    2. Yansımalar (su, cam, cilalı ve metal bloklar):
         a) voxel ızgarasında ışın izle
            - isabet ekranda görünüyorsa dokulu pikseli al
            - değilse voxelin düz rengini aydınlat
         b) voxel ıskalarsa ekran uzayında ara (mob, bitki, uzak arazi)
         c) o da ıskalarsa gökyüzü
    3. Mesafe sisi ve su altı / lav / toz kar sisi
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

uniform sampler2D colortex0; // sahne (saydamlar dahil)
uniform sampler2D colortex1; // opak normal + ışık haritası
uniform sampler2D colortex2; // malzeme
uniform sampler2D colortex5; // saydam yüzey verisi
uniform sampler2D colortex6; // opak yansıma bilgisi
uniform sampler2D depthtex0; // saydamlar dahil derinlik
uniform sampler2D depthtex1; // yalnızca opak derinlik

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

// Iris eli [0.4375, 0.5625] derinlik aralığına sıkıştırır; bunun altı el sayılır
const float HAND_DEPTH_LIMIT = 0.5625;

#ifdef WATER_CAUSTICS
// Su yüzeyindeki dalgaların odakladığı ışık desenleri.
// İki kayan gürültü katmanının farkı sıfıra yaklaştığı yerlerde parlak
// çizgiler oluşur; bu da caustic desenine benzer.
float waterCaustics(vec2 worldXZ) {
    float t = frameTimeCounter * CAUSTICS_SPEED;
    vec2 p = worldXZ * (0.8 / CAUSTICS_SCALE);
    float a = valueNoise(p + vec2(t * 0.20, t * 0.14));
    float b = valueNoise(p * 1.7 - vec2(t * 0.13, t * 0.21));
    float ridge = abs(a + b - 1.0);
    return pow(1.0 - saturate(ridge * 2.0), 4.0);
}
#endif

// ---------------------------------------------------------------------
//  Ekran uzayı ışın izleme: derinlik dokusunda adım adım ilerler.
//  Voxel ızgarasında olmayan şeyleri (mob, bitki, uzak arazi) yakalar.
// ---------------------------------------------------------------------
#ifdef SSR_FALLBACK
bool screenSpaceTrace(vec3 viewPos, vec3 viewRay, float jitter, out vec2 hitUV) {
    hitUV = vec2(0.0);
    vec2 res = vec2(viewWidth, viewHeight);

    // Kameraya doğru giden ışını yakın kesme düzleminde durdur
    float rayLength = 96.0;
    if (viewRay.z > 0.0) {
        rayLength = min(rayLength, (-near * 1.5 - viewPos.z) / viewRay.z);
        if (rayLength <= 0.05) return false;
    }

    vec3 start = viewToScreen(viewPos);
    vec3 end = viewToScreen(viewPos + viewRay * rayLength);
    vec3 delta = end - start;
    float pixelLength = length(delta.xy * res);
    if (pixelLength < 1.0) return false;

    int steps = int(clamp(pixelLength / 8.0, 8.0, float(SSR_MAX_STEPS)));
    vec3 stepVec = delta / float(steps);
    vec3 p = start + stepVec * jitter;

    for (int i = 0; i < steps; i++) {
        p += stepVec;
        if (any(lessThan(p.xy, vec2(0.0))) || any(greaterThan(p.xy, vec2(1.0))) || p.z >= 1.0) return false;

        float sceneDepth = texelFetch(depthtex0, ivec2(p.xy * res), 0).r;
        if (sceneDepth < HAND_DEPTH_LIMIT || sceneDepth >= 1.0) continue;

        if (p.z > sceneDepth) { // ışın bir yüzeyin arkasına geçti
            float rayLin = linearizeDepth(p.z);
            float sceneLin = linearizeDepth(sceneDepth);
            float stepLin = abs(rayLin - linearizeDepth(p.z - stepVec.z));
            if (rayLin - sceneLin < max(stepLin * 1.5, SSR_THICKNESS)) {
                // İkili arama ile tam kesişimi bul
                vec3 lo = p - stepVec;
                vec3 hi = p;
                for (int j = 0; j < 5; j++) {
                    vec3 mid = (lo + hi) * 0.5;
                    float d = texelFetch(depthtex0, ivec2(mid.xy * res), 0).r;
                    if (mid.z > d) hi = mid; else lo = mid;
                }
                hitUV = hi.xy;
                return true;
            }
        }
    }
    return false;
}
#endif

// ---------------------------------------------------------------------
//  Bir noktadan R yönündeki yansımayı bulur
// ---------------------------------------------------------------------
vec3 traceReflection(vec3 playerPos, vec3 viewPos, vec3 N, vec3 R, float lmSky, vec3 sunDir, vec3 lightDir) {
    float sunExposure = sunExposureFromLightmap(lmSky);
    float skyExposure = skyExposureFromLightmap(lmSky);
    vec2 res = vec2(viewWidth, viewHeight);
    vec3 tint = vec3(1.0); // yansıma ışını renkli camdan geçtiyse renklenir

    // 1) Voxel ızgarasında ışın izle
    if (voxelVolumeFade(playerPos) > 0.0) {
        vec3 hitPos, hitNormal;
        vec4 voxel;
        float emitBoost;
        vec3 origin = playerToVoxel(playerPos + N * 0.05);
        if (traceVoxels(origin, R, REFLECTION_STEPS, REFLECTION_MAX_DISTANCE, hitPos, hitNormal, voxel, emitBoost, tint)) {
            vec3 hitPlayer = voxelToPlayer(hitPos);

            #ifdef REFLECTION_SCREEN_LOOKUP
            // İsabet noktası ekranda görünüyor ve önünde bir şey yoksa dokulu pikseli kullan
            vec3 hitView = playerToView(hitPlayer + hitNormal * 0.02);
            if (hitView.z < -near) {
                vec3 hitScreen = viewToScreen(hitView);
                if (all(greaterThan(hitScreen.xy, vec2(0.0))) && all(lessThan(hitScreen.xy, vec2(1.0)))) {
                    ivec2 hp = ivec2(hitScreen.xy * res);
                    float sd = texelFetch(depthtex0, hp, 0).r;
                    if (sd >= HAND_DEPTH_LIMIT && sd < 1.0 && abs(linearizeDepth(sd) + hitView.z) < 0.35 - hitView.z * 0.01) {
                        return texelFetch(colortex0, hp, 0).rgb * tint;
                    }
                }
            }
            #endif

            // Değilse voxelin kendisini aydınlat
            vec3 shaded = shadeVoxelHit(hitPos, hitNormal, voxel, lightDir, getDirectLight(sunDir), getSkyAmbient(sunDir),
                                        sunExposure, skyExposure, emitBoost, GI_HIT_AMBIENT);
#if defined RT_LIGHTS && defined REFLECTION_BLOCK_LIGHT
            // Yansıyan yüzeye düşen blok ışığı. Bu olmadan kapalı mekanda güneş ve
            // gökyüzü sıfır olduğu için yansımalar simsiyah çıkıyordu; metal kapı
            // gibi tamamen yansıtıcı yüzeyler de kararıyordu.
            vec3 rndRef = hash33(uvec3(uvec2(gl_FragCoord.xy), uint(frameCounter) * 3299u + 71u));
            shaded += toLinear(voxel.rgb) * sampleBlockLights(hitPos + hitNormal * 0.02, hitNormal, rndRef);
#endif
            return shaded * tint;
        }
    }

    // 2) Ekran uzayı yedeği
#ifdef SSR_FALLBACK
    vec2 hitUV;
    if (screenSpaceTrace(viewPos, mat3(gbufferModelView) * R, ign(gl_FragCoord.xy), hitUV)) {
        return texelFetch(colortex0, ivec2(hitUV * res), 0).rgb * tint;
    }
#endif

    // 3) Gökyüzü (yolda cam varsa onun renginde süzülmüş olarak)
    return getReflectedSky(R, sunDir) * skyExposure * tint;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, px, 0).rgb;

    // Hata ayıklama: deferred2'nin ürettiği görünümleri olduğu gibi geçir
    bool debugHere = debugActive(texcoord);
    if (debugHere && isDeferredDebugView(DEBUG_VIEW)) {
        outColor = vec4(color, 1.0);
        return;
    }
    bool reflectionsOnly = debugHere && DEBUG_VIEW == DBG_REFLECTIONS;
    vec3 reflectionDebug = vec3(0.0);

    float depth0 = texelFetch(depthtex0, px, 0).r;
    float depth1 = texelFetch(depthtex1, px, 0).r;
    vec4 translucent = texelFetch(colortex5, px, 0);
    int material = int(texelFetch(colortex2, px, 0).r * 255.0 + 0.5);
    bool isHand = material == MAT_HAND || depth0 < HAND_DEPTH_LIMIT;

    vec3 sunDir = getSunDir();
    vec3 lightDir = getLightDir();

    vec3 viewPos0 = screenToView(texcoord, depth0);
    vec3 playerPos0 = viewToPlayer(viewPos0);
    vec3 viewDir = normalize(playerPos0);

    bool hasTranslucent = translucent.b > 0.25 && depth0 < depth1;

    // ============================================= Saydam yüzeyler
    if (hasTranslucent && !isHand) {
        bool isWater = translucent.b > 0.75;
        vec3 N = decodeNormal(translucent.rg);
        float lmSky = translucent.a;
        vec2 res = vec2(viewWidth, viewHeight);

        // Yüzeyin arkasındaki opak noktaya olan mesafe = suyun kalınlığı
        vec3 playerPos1 = viewToPlayer(screenToView(texcoord, depth1));
        float thickness = depth1 >= 1.0 ? 32.0 : min(distance(playerPos0, playerPos1), 32.0);

        // ---------------- Kırılma (refraction)
        // Işık su/cam yüzeyinde yön değiştirir. Kırılan ışının hedeflediği
        // noktayı ekrana geri yansıtıp arka planı oradan örnekliyoruz.
#if defined WATER_REFRACTION || defined GLASS_REFRACTION
        float refractStrength = 0.0;
    #ifdef WATER_REFRACTION
        if (isWater) refractStrength = WATER_REFRACTION_STRENGTH;
    #endif
    #ifdef GLASS_REFRACTION
        if (!isWater) refractStrength = GLASS_REFRACTION_STRENGTH;
    #endif
        if (refractStrength > 0.0) {
            // Suyun kırılma indisi 1.33; su altındayken oran ters çevrilir
            float eta = (isEyeInWater == 1 && isWater) ? 1.333 : 1.0 / 1.333;
            // refract(), normalin ışına ters bakmasını bekler. Su altından yüzeye
            // bakarken normal yukarı, ışın da yukarı gider; bu durumda çevrilmeli.
            vec3 refractN = dot(viewDir, N) > 0.0 ? -N : N;
            vec3 refracted = refract(viewDir, refractN, eta);
            if (dot(refracted, refracted) > 0.0) {
                // Kırılma kaydırması, ışının kırıldıktan sonra ne kadar yol aldığıyla
                // orantılıdır. Cam ince bir levhadır; arkasındaki duvara olan mesafeyi
                // kullanmak kaydırmayı devasa yapıp büyüteç etkisi yaratıyordu.
                float refractDepth = isWater ? min(thickness, 6.0) : min(thickness, GLASS_REFRACTION_DEPTH);
                vec3 target = playerPos0 + refracted * refractDepth;
                vec3 targetScreen = viewToScreen(playerToView(target));
                // Kenarlara yakın bakışta kırılma aşırı büyür; sınırla
                float maxOffset = isWater ? 0.06 : 0.02;
                vec2 offset = clamp((targetScreen.xy - texcoord) * refractStrength, vec2(-maxOffset), vec2(maxOffset));
                ivec2 rp = ivec2(clamp(texcoord + offset, vec2(0.0015), vec2(0.9985)) * res);
                // Yalnızca gerçekten yüzeyin arkasında kalan pikselleri kullan,
                // yoksa su kenarlarında kıyıdaki pikseller içeri sızar
                if (texelFetch(depthtex1, rp, 0).r > depth0) color = texelFetch(colortex0, rp, 0).rgb;
            }
        }
#endif

        // ---------------- Su altındaki yüzeyler
        if (isWater && isEyeInWater == 0) {
            float sunExp = sunExposureFromLightmap(lmSky);
            float skyExp = skyExposureFromLightmap(lmSky);

#ifdef WATER_CAUSTICS
            // Dalgaların odakladığı ışık desenleri zemine düşer
            if (depth1 < 1.0) {
                float c = waterCaustics((playerPos1 + cameraPosition).xz);
                color *= 1.0 + c * CAUSTICS_STRENGTH * (0.25 + sunExp) * skyExp;
            }
#endif
            // Derinlikle ışık emilimi: kırmızı en hızlı kaybolur, bu yüzden
            // derin su maviye kayar. Saçılma ise suyun kendi rengini ekler.
            vec3 absorption = exp(-vec3(0.45, 0.14, 0.10) * WATER_ABSORPTION * thickness);
            vec3 scatter = vec3(0.05, 0.22, 0.28) * WATER_SCATTER
                         * (getSkyAmbient(sunDir) * skyExp + getDirectLight(sunDir) * 0.08 * sunExp + 0.01);
            color = color * absorption + scatter * (1.0 - absorption);
        }

        bool reflect_ = false;
        #ifdef WATER_REFLECTIONS
            if (isWater && isEyeInWater == 0) reflect_ = true;
        #endif
        #ifdef GLASS_REFLECTIONS
            if (!isWater) reflect_ = true;
        #endif

        if (reflect_) {
            float F0 = isWater ? 0.02 : 0.04;
            float cosTheta = saturate(dot(-viewDir, N));
            float fresnel = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0); // Schlick yaklaşımı

            vec3 R = reflect(viewDir, N);
            if (isWater) R = normalize(vec3(R.x, max(R.y, 0.01), R.z)); // dalgalar ışını suya çevirmesin

            #ifdef RT_REFLECTIONS
                vec3 reflection = traceReflection(playerPos0, viewPos0, N, R, lmSky, sunDir, lightDir);
            #else
                vec3 reflection = getReflectedSky(R, sunDir) * skyExposureFromLightmap(lmSky);
            #endif

            float strength = fresnel * (isWater ? 1.0 : GLASS_REFLECTION_STRENGTH);
            color = mix(color, reflection, strength);
            reflectionDebug = reflection * strength;

            #if defined OVERWORLD && defined WATER_SUN_SPECULAR
                if (isWater) {
                    vec3 H = normalize(lightDir - viewDir);
                    float NdotH = saturate(dot(N, H));
                    float spec = pow(NdotH, 900.0) * 60.0 + pow(NdotH, 120.0) * 1.5;
                    vec3 sunSpec = getDirectLight(sunDir) * spec * shadowSingle(playerPos0 + N * 0.1) * sunExposureFromLightmap(lmSky);
                    color += sunSpec;
                    reflectionDebug += sunSpec;
                }
            #endif
        }
    }
    // ===================================== Opak pürüzsüz yüzeyler
    else if (depth0 < 1.0 && !isHand) {
        #if defined RT_REFLECTIONS && defined BLOCK_REFLECTIONS
        vec4 reflectInfo = texelFetch(colortex6, px, 0);
        float smoothness = reflectInfo.a;
        if (smoothness > REFLECTION_MIN_SMOOTHNESS) {
            vec4 normalLight = texelFetch(colortex1, px, 0);
            vec3 N = decodeNormal(normalLight.rg);
            vec3 F0 = reflectInfo.rgb;
            float cosTheta = saturate(dot(-viewDir, N));
            vec3 F = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);

            // Sabit (kareden kareye değişmeyen) sapma: titreşimsiz pürüzlülük hissi
            float roughness = (1.0 - smoothness) * (1.0 - smoothness);
            vec3 jitter = hash33(uvec3(uvec2(px), 7u)) - 0.5;
            vec3 R = reflect(viewDir, normalize(N + jitter * roughness * ROUGH_REFLECTION_JITTER));
            if (dot(R, N) < 0.0) R = reflect(R, N);

            vec3 reflection = traceReflection(playerPos0, viewPos0, N, R, normalLight.a, sunDir, lightDir);
            vec3 added = reflection * F * smoothstep(REFLECTION_MIN_SMOOTHNESS, REFLECTION_MIN_SMOOTHNESS + 0.35, smoothness);
            color += added;
            reflectionDebug = added;
        }
        #endif
    }

    if (reflectionsOnly) {
        outColor = vec4(reflectionDebug, 1.0);
        return;
    }

    // ========================================================== Sis
    float dist = depth0 >= 1.0 ? far : length(playerPos0);

    if (isEyeInWater == 0) {
        if (depth0 < 1.0 && !isHand) color = applyDistanceFog(color, playerPos0, viewDir, sunDir);
    } else if (isEyeInWater == 1) {
        float eyeSky = getEyeSkylight();

#ifdef WATER_CAUSTICS
        // Su altındayken tüm yüzeylerde ışık desenleri
        if (depth0 < 1.0 && !isHand) {
            float c = waterCaustics((playerPos0 + cameraPosition).xz);
            color *= 1.0 + c * CAUSTICS_STRENGTH * (0.2 + 0.8 * eyeSky);
        }
#endif
#ifdef UNDERWATER_BIOME_TINT
        vec3 waterTint = toLinear(fogColor);   // biyomun kendi su rengi
#else
        vec3 waterTint = vec3(0.05, 0.30, 0.40);
#endif
        vec3 fogCol = waterTint * (getSkyAmbient(sunDir) * 2.0 * eyeSky + getDirectLight(sunDir) * 0.15 * eyeSky + 0.02);
        vec3 absorption = exp(-vec3(0.30, 0.08, 0.05) * UNDERWATER_FOG_DENSITY * dist);
        if (!isHand) color = color * absorption + fogCol * (1.0 - absorption);
    } else if (isEyeInWater == 2) {
        if (!isHand) color = mix(color, vec3(2.0, 0.4, 0.05), 1.0 - exp(-dist * 1.5));
    } else if (isEyeInWater == 3) {
        if (!isHand) color = mix(color, vec3(0.7, 0.8, 0.9), 1.0 - exp(-dist * 1.2));
    }

    if (blindness > 0.0) color *= mix(1.0, exp(-dist * 0.5), blindness);

    outColor = vec4(max(color, vec3(0.0)), 1.0);
}

#endif
