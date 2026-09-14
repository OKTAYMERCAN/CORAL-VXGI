/*
=====================================================================
  lib/forward.glsl - Basit "ileri" aydınlatma
=====================================================================
  Ertelenmiş ışın izlemeden geçmeyen şeyler için ucuz aydınlatma:
  su, cam, parçacıklar. Işık haritası + tek örnekli gölge kullanır.
=====================================================================
*/
#ifndef INCLUDE_FORWARD
#define INCLUDE_FORWARD

// useNormal = false ise yüzey yönü önemsizdir (parçacıklar kameraya bakar)
vec3 forwardLighting(vec3 playerPos, vec2 lm, vec3 N, bool useNormal) {
    vec3 sunDir = getSunDir();
    vec3 light = getSkyAmbient(sunDir) * (lm.y * lm.y) * 1.2;

#ifdef OVERWORLD
    vec3 lightDir = getLightDir();
    float NdotL = useNormal ? saturate(dot(N, lightDir)) : 0.6;
    if (NdotL > 0.0) {
        light += getDirectLight(sunDir) * NdotL * shadowSingle(playerPos + lightDir * 0.1) * smoothstep(0.0, 0.25, lm.y);
    }
#endif

    light += BLOCKLIGHT_COLOR * pow(lm.x, BLOCKLIGHT_CURVE) * 1.8 * BLOCKLIGHT_STRENGTH;
    light += vec3(MIN_LIGHT * 2.0) + vec3(nightVision * 0.3);
    return light;
}

#endif // INCLUDE_FORWARD
