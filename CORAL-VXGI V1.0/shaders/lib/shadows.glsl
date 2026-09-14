/*
=====================================================================
  lib/shadows.glsl - Gölge haritası bozulması ve örnekleme
=====================================================================
  Gölge haritası güneşin gözünden çizilmiş bir derinlik resmidir.
  "Bozulma" (distortion) oyuncuya yakın bölgeye daha çok piksel verir.
  Aynı bozulma hem gölge geçişinde (shadow.glsl) hem de okumada
  kullanılmalıdır, bu yüzden tek yerde tanımlıdır.
=====================================================================
*/
#ifndef INCLUDE_SHADOWS
#define INCLUDE_SHADOWS

// Merkeze uzaklığa göre ölçek: SHADOW_DISTORTION = 0 ise bozulma yok
float shadowDistortFactor(vec2 clipXY) {
    return length(clipXY) * SHADOW_DISTORTION + (1.0 - SHADOW_DISTORTION);
}

vec3 distortShadowClip(vec3 clip) {
    return vec3(clip.xy / shadowDistortFactor(clip.xy), clip.z);
}

// Aşağıdakiler gölge geçişinin kendisinde gerekmez
#ifndef SHADOW_PASS
uniform sampler2D shadowtex1; // Yalnızca OPAK nesnelerin gölge derinliği
#ifdef COLORED_SHADOWS
uniform sampler2D shadowtex0;   // TÜM nesneler (saydamlar dahil)
uniform sampler2D shadowcolor0; // Gölge geçişinde yazılan renk
#endif

// Renkli gölge: shadowtex1 "engel yok" derken shadowtex0 "engel var" diyorsa
// arada yalnızca saydam bir blok vardır; o zaman ışık onun renginde süzülür.
vec3 translucentShadowTint(vec2 uv, float refZ, float litByOpaque) {
#ifdef COLORED_SHADOWS
    float litByAll = step(refZ, texture(shadowtex0, uv).r);
    if (litByOpaque > litByAll) {
        vec4 sc = texture(shadowcolor0, uv);
        if (sc.a > 0.01) {
            vec3 tint = sc.rgb * SHADOW_TINT_BRIGHTNESS;
            return mix(vec3(1.0), tint, sc.a);
        }
    }
#endif
    return vec3(1.0);
}

vec3 playerToShadowClip(vec3 playerPos) {
    vec3 shadowView = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
    return (shadowProjection * vec4(shadowView, 1.0)).xyz;
}

// Tek örnekli gölge testi: ışın çarpma noktaları gibi ucuz olması gereken yerler için.
// 1 = aydınlık, 0 = gölgede. Harita dışı her zaman aydınlık sayılır.
vec3 shadowSingle(vec3 playerPos) {
    vec3 clip = playerToShadowClip(playerPos);
    vec3 s = distortShadowClip(clip) * 0.5 + 0.5;
    if (any(lessThan(s, vec3(0.0))) || any(greaterThan(s, vec3(1.0)))) return vec3(1.0);
    float refZ = s.z - 0.0003;
    float lit = step(refZ, texture(shadowtex1, s.xy).r);
    return lit * translucentShadowTint(s.xy, refZ, lit);
}

// Yumuşak (PCF) gölge: doğrudan görünen yüzeyler için.
// Renkli cam arkasındaki noktalar için renkli döner.
vec3 shadowFiltered(vec3 playerPos, vec3 normal, float NdotL, vec2 fragCoord) {
    float dist = length(playerPos);
    if (dist > shadowDistance * 0.98) return vec3(1.0);

    vec3 clip = playerToShadowClip(playerPos);
    float factor = shadowDistortFactor(clip.xy);
    // Bu noktada bir gölge pikselinin dünyadaki boyutu
    float texelWorld = 2.0 * shadowDistance / float(shadowMapResolution) * factor;

    // Normal yönünde kaydırma: "gölge sivilcesi" (shadow acne) önler.
    // Işığa yan bakan yüzeylerde daha fazla kaydırılır.
    vec3 biasedPos = playerPos + normal * texelWorld * (SHADOW_BIAS + 1.5 * (1.0 - saturate(NdotL)));
    clip = playerToShadowClip(biasedPos);
    vec3 s = distortShadowClip(clip) * 0.5 + 0.5;
    if (any(lessThan(s, vec3(0.0))) || any(greaterThan(s, vec3(1.0)))) return vec3(1.0);

    float refDepth = s.z - 0.00005;
    float radius = SHADOW_SOFTNESS * 1.25 / float(shadowMapResolution);
    float lit;
    vec3 tint;

    if (radius <= 0.0) {
        lit = step(refDepth, texture(shadowtex1, s.xy).r);
        tint = translucentShadowTint(s.xy, refDepth, lit);
    } else {
        // Her piksel için farklı döndürülmüş Poisson diski: bantlanma yerine ince gürültü
        mat2 rot = rotate2D(ign(fragCoord) * TAU);
        lit = 0.0;
        for (int i = 0; i < SHADOW_SAMPLES; i++) {
            lit += step(refDepth, texture(shadowtex1, s.xy + poissonTap(i, rot) * radius).r);
        }
        lit /= float(SHADOW_SAMPLES);
        // Renk her örnek için ayrı okunmaz; tek merkez örneği yeterlidir ve
        // 12 kat daha az doku okuması yapar
        tint = translucentShadowTint(s.xy, refDepth, 1.0);
    }

    #ifdef SHADOW_EDGE_FADE
        // Gölge mesafesinin sonuna yaklaşınca gölgeyi yavaşça kaldır
        lit = mix(lit, 1.0, smoothstep(shadowDistance * 0.8, shadowDistance * 0.98, dist));
    #endif
    return lit * tint;
}
#endif // SHADOW_PASS

#endif // INCLUDE_SHADOWS
