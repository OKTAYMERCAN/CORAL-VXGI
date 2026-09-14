/*
=====================================================================
  lib/sky.glsl - Gökyüzü, ışık renkleri, bulutlar ve sis
=====================================================================
  Boyuta göre davranış OVERWORLD / NETHER / END tanımlarıyla seçilir.
  Bu tanımlar world0 / world-1 / world1 klasörlerindeki küçük sarmalayıcı
  dosyalarda yapılır.

  Tüm yönler "player" uzayındadır (y yukarı). sunDir birim vektördür.
=====================================================================
*/
#ifndef INCLUDE_SKY
#define INCLUDE_SKY

// Güneş ve gölge ışığı yönleri (görüş uzayından oyuncu uzayına)
vec3 getSunDir()   { return normalize(mat3(gbufferModelViewInverse) * sunPosition); }
vec3 getLightDir() { return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition); }

// Göz hizasındaki gökyüzü ışığı: 0 = mağara, 1 = açık alan
float getEyeSkylight() { return saturate(float(eyeBrightnessSmooth.y) / 240.0); }

// ---------------------------------------------------------------------
//  Gölge veren ışığın rengi: gündüz güneş, gece ay
// ---------------------------------------------------------------------
vec3 getDirectLight(vec3 sunDir) {
#ifdef OVERWORLD
    float h = sunDir.y; // güneşin yüksekliği: >0 gündüz
    vec3 sunCol  = mix(vec3(1.0, 0.42, 0.12), vec3(1.0, 0.93, 0.84), smoothstep(0.02, 0.45, h)) * 3.2 * SUN_BRIGHTNESS;
    vec3 moonCol = vec3(0.45, 0.55, 0.85) * MOON_BRIGHTNESS;
    // Ufukta güneş/ay değişirken ışığı söndür (ani sıçramayı önler)
    float swapFade = smoothstep(0.0, 0.08, abs(h));
    vec3 col = (h > 0.0 ? sunCol : moonCol) * swapFade;
    return col * (1.0 - rainStrength * RAIN_DARKNESS);
#else
    return vec3(0.0); // Nether ve End'de güneş yok
#endif
}

// ---------------------------------------------------------------------
//  Açık gökyüzünden gelen ortalama ışık (ortam ışığı)
// ---------------------------------------------------------------------
vec3 getSkyAmbient(vec3 sunDir) {
#if defined NETHER
    return toLinear(fogColor) * NETHER_AMBIENT + vec3(0.020, 0.012, 0.008);
#elif defined END
    return vec3(1.0, 0.7, 1.4) * END_AMBIENT;
#else
    float h = sunDir.y;
    float day = smoothstep(-0.12, 0.25, h);
    vec3 col = mix(vec3(0.020, 0.028, 0.055), vec3(0.32, 0.50, 1.0) * 0.55, day);
    col += vec3(0.25, 0.10, 0.03) * (1.0 - smoothstep(0.0, 0.3, abs(h))) * 0.4 * SUNSET_STRENGTH;
    col = mix(col, vec3(luminance(col)) * 0.8, rainStrength * 0.7);
    return col * SKY_BRIGHTNESS;
#endif
}

// ---------------------------------------------------------------------
//  Belirli bir yönde gökyüzünün rengi (güneş diski ve bulut hariç)
// ---------------------------------------------------------------------
vec3 getSkyRadiance(vec3 dir, vec3 sunDir) {
#if defined NETHER
    return toLinear(fogColor) * 0.6;
#elif defined END
    return vec3(0.030, 0.020, 0.045);
#else
    float h   = sunDir.y;
    float day = smoothstep(-0.15, 0.2, h);
    float up  = dir.y;

    // Tepe (zenith) ve ufuk renkleri arasında geçiş
    vec3 zenith  = mix(vec3(0.004, 0.006, 0.014), vec3(0.10, 0.28, 0.85), day);
    vec3 horizon = mix(vec3(0.018, 0.024, 0.045), vec3(0.55, 0.72, 1.00), day);
    vec3 col = mix(horizon, zenith, pow(saturate(up), 0.45));

    float mu = dot(dir, sunDir); // bakış yönü ile güneş arasındaki açının kosinüsü

    // Gün doğumu / batımı turuncu bandı
    float sunsetAmount = 1.0 - smoothstep(0.0, 0.32, abs(h + 0.02));
    float band = pow(1.0 - saturate(up), 6.0);
    float towardSun = pow(saturate(mu * 0.5 + 0.5), 3.0);
    col += vec3(1.0, 0.36, 0.08) * sunsetAmount * band * (0.25 + 1.6 * towardSun) * SUNSET_STRENGTH;

    // Güneş çevresindeki parlaklık (Mie saçılması yaklaşımı)
    float sunVis = smoothstep(-0.1, 0.05, h);
    vec3 sunTint = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.9, 0.8), smoothstep(0.0, 0.4, h));
    col += sunTint * sunVis * (pow(saturate(mu), 10.0) * 0.35 + pow(saturate(mu), 120.0) * 1.2);

    // Ay çevresindeki hafif parlaklık
    col += vec3(0.05, 0.07, 0.12) * pow(saturate(-mu), 30.0) * (1.0 - day);

    // Ufkun altı: daha koyu
    if (up < 0.0) col = mix(col, horizon * 0.35, 1.0 - smoothstep(-0.25, 0.0, up));

    col = mix(col, vec3(luminance(col)) * 0.7, rainStrength * 0.8);
    return col * SKY_BRIGHTNESS;
#endif
}

// ---------------------------------------------------------------------
//  Güneş diski
// ---------------------------------------------------------------------
vec3 getSunDisc(vec3 dir, vec3 sunDir) {
#if defined OVERWORLD && defined SUN_DISC
    float radius = 0.0345 * SUN_DISC_SIZE; // radyan (~2 derece)
    float disc = smoothstep(cos(radius * 1.3), cos(radius), dot(dir, sunDir));
    vec3 tint = mix(vec3(1.0, 0.45, 0.15), vec3(1.0, 0.95, 0.88), smoothstep(0.0, 0.3, sunDir.y));
    return tint * disc * SUN_DISC_BRIGHTNESS * (1.0 - rainStrength) * SUN_BRIGHTNESS * smoothstep(-0.02, 0.02, dir.y);
#else
    return vec3(0.0);
#endif
}

// ---------------------------------------------------------------------
//  Prosedürel bulutlar: sabit yükseklikte bir düzleme gürültü desenidir
// ---------------------------------------------------------------------
#if defined CLOUDS && defined OVERWORLD
float cloudFbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 m = mat2(1.6, 1.2, -1.2, 1.6); // her katmanda döndür + büyüt
    for (int i = 0; i < 5; i++) {
        v += a * valueNoise(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

// rgb = bulut ışığı, a = bulut örtüsü (0..1)
vec4 getClouds(vec3 dir, vec3 sunDir) {
    if (dir.y < 0.01) return vec4(0.0);
    float t = (CLOUD_HEIGHT - cameraPosition.y) / dir.y; // bulut düzlemine olan mesafe
    if (t <= 0.0) return vec4(0.0);                      // bulutların üstündeyiz
    t = min(t, 30000.0);

    vec2 wind = vec2(2.0, 0.6) * frameTimeCounter * CLOUD_SPEED;
    vec2 p = (cameraPosition.xz + dir.xz * t + wind) * 0.0016 / CLOUD_SCALE;

    float threshold = mix(0.72, 0.32, CLOUD_AMOUNT) - rainStrength * 0.22;
    float density = smoothstep(threshold, threshold + 0.28, cloudFbm(p));
    if (density <= 0.0) return vec4(0.0);

    // Güneşe doğru bir örnek daha: bulutun kendi gölgesi
    float h = sunDir.y;
    float towardLight = 1.0 - smoothstep(threshold, threshold + 0.5, cloudFbm(p + normalize(sunDir.xz + 1e-4) * 0.12)) * 0.7;
    vec3 sunCol = mix(vec3(1.0, 0.40, 0.12), vec3(1.0, 0.95, 0.90), smoothstep(0.0, 0.4, h)) * 2.2 * smoothstep(-0.1, 0.02, h);
    vec3 light = sunCol * towardLight * (1.0 - rainStrength * 0.8) * SUN_BRIGHTNESS + getSkyAmbient(sunDir) * 1.6;

    density *= smoothstep(0.01, 0.12, dir.y); // ufka doğru incelt
    return vec4(light, density * 0.95);
}
#endif

// Doğrudan görülen gökyüzü. celestial = vanilla yıldız ve ay (gbuffers_sky'dan)
vec3 getFullSky(vec3 dir, vec3 sunDir, vec3 celestial) {
    vec3 col = getSkyRadiance(dir, sunDir) + getSunDisc(dir, sunDir) + celestial;
#if defined CLOUDS && defined OVERWORLD
    vec4 clouds = getClouds(dir, sunDir);
    col = mix(col, clouds.rgb, clouds.a);
#endif
    return col;
}

// Yansımalarda görülen gökyüzü (güneş parlaması ayrıca eklenir)
vec3 getReflectedSky(vec3 dir, vec3 sunDir) {
    vec3 col = getSkyRadiance(dir, sunDir);
#if defined CLOUDS && defined OVERWORLD
    vec4 clouds = getClouds(dir, sunDir);
    col = mix(col, clouds.rgb, clouds.a);
#endif
    return col;
}

// ---------------------------------------------------------------------
//  Sızıntı önleme: bir yüzeyin gökyüzü ışık haritası (lmSky) düşükse
//  (mağara, kapalı oda) oraya gökyüzü ve güneş ışığı gelmemeli.
// ---------------------------------------------------------------------
float sunExposureFromLightmap(float lmSky) {
#ifdef OVERWORLD
    #ifdef LEAK_FIX
        return smoothstep(0.0, 0.35, lmSky);
    #else
        return 1.0;
    #endif
#else
    return 0.0;
#endif
}

float skyExposureFromLightmap(float lmSky) {
#ifdef OVERWORLD
    #ifdef LEAK_FIX
        return lmSky * lmSky;
    #else
        return 1.0;
    #endif
#else
    return 1.0;
#endif
}

// ---------------------------------------------------------------------
//  Mesafe sisi (composite geçişinde uygulanır)
// ---------------------------------------------------------------------
vec3 applyDistanceFog(vec3 color, vec3 playerPos, vec3 viewDir, vec3 sunDir) {
    float dist = length(playerPos);
    float fog = 0.0;
    vec3 fogCol;

#if defined NETHER
    #ifdef FOG
        fog = 1.0 - exp(-dist * 0.012 * FOG_DENSITY);
    #endif
    #ifdef BORDER_FOG
        fog = max(fog, smoothstep(far * BORDER_FOG_START * 0.7, far, dist));
    #endif
    fogCol = toLinear(fogColor) * 0.6;
#elif defined END
    #ifdef FOG
        fog = 1.0 - exp(-dist * 0.004 * FOG_DENSITY);
    #endif
    #ifdef BORDER_FOG
        fog = max(fog, smoothstep(far * BORDER_FOG_START, far, dist));
    #endif
    fogCol = vec3(0.030, 0.020, 0.045);
#else
    #ifdef FOG
        // Alçakta daha yoğun, yağışta daha kalın sis
        float density = 0.0012 * FOG_DENSITY * (1.0 + rainStrength * 5.0);
        float altitude = cameraPosition.y + playerPos.y * 0.5 - 63.0;
        fog = 1.0 - exp(-dist * density * exp(-max(altitude, 0.0) * 0.01));
    #endif
    #ifdef BORDER_FOG
        fog = max(fog, smoothstep(far * BORDER_FOG_START, far, dist));
    #endif
    vec3 fogDir = normalize(vec3(viewDir.x, max(viewDir.y, 0.0) * 0.3 + 0.001, viewDir.z));
    fogCol = getSkyRadiance(fogDir, sunDir) * mix(0.08, 1.0, getEyeSkylight());
#endif

    return mix(color, fogCol, fog);
}

#endif // INCLUDE_SKY
