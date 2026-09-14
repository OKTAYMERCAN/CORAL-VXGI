/*
=====================================================================
  lib/common.glsl - Ortak matematik ve yardımcı fonksiyonlar
=====================================================================
  Her programın kullandığı küçük araçlar: sabitler, malzeme kimlikleri,
  renk dönüşümleri, normal kodlama, rastgele sayı üretimi ve gürültü.

  ÖNEMLİ: Iris, Sodium arazi shader'larına kendi fonksiyonlarını
  (signNotZero, decodeOct24 gibi) enjekte eder. İsim çakışmasını önlemek
  için genel isimli fonksiyonlara "rb_" (CORAL VXGI) öneki verin.
=====================================================================
*/
#ifndef INCLUDE_COMMON
#define INCLUDE_COMMON

const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

// ---------------------------------------------------------------------
//  Malzeme kimlikleri - G-buffer'da colortex2.r kanalına (değer/255) yazılır
// ---------------------------------------------------------------------
const int MAT_UNLIT    = 0; // Zaten aydınlatılmış (parçacık, çizgi, gökyüzü) - ertelenmiş geçişler dokunmaz
const int MAT_LIT      = 1; // Normal katı yüzey
const int MAT_PLANT    = 2; // Çim, çiçek: normal yukarı kabul edilir
const int MAT_LEAVES   = 3; // Yapraklar: ışık geçirgen
const int MAT_EMISSIVE = 4; // Işık yayan yüzey (meşale, lav, LabPBR ışıma)
const int MAT_HAND     = 5; // Birinci şahıs el - ışın izlenmez

// ---------------------------------------------------------------------
//  Küçük matematik araçları
// ---------------------------------------------------------------------
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, 0.0, 1.0); }
float maxOf(vec3 v)     { return max(v.x, max(v.y, v.z)); }
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Doku renkleri sRGB'dir; ışık hesabı doğrusal (linear) uzayda yapılmalıdır
vec3 toLinear(vec3 c) { return pow(max(c, 0.0), vec3(2.2)); }
vec3 toSRGB(vec3 c)   { return pow(max(c, 0.0), vec3(1.0 / 2.2)); }

// ---------------------------------------------------------------------
//  Oktahedral normal kodlama: 3 bileşenli normali 2 kanala sıkıştırır
//  (colortex1.rg ve colortex5.rg bu şekilde saklanır)
// ---------------------------------------------------------------------
vec2 rb_signNotZero(vec2 v) { return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0); }

vec2 encodeNormal(vec3 n) {
    vec2 p = n.xy / (abs(n.x) + abs(n.y) + abs(n.z) + 1e-6);
    if (n.z < 0.0) p = (1.0 - abs(p.yx)) * rb_signNotZero(p);
    return p * 0.5 + 0.5;
}

vec3 decodeNormal(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) n.xy = (1.0 - abs(n.yx)) * rb_signNotZero(n.xy);
    return normalize(n);
}

// ---------------------------------------------------------------------
//  Rastgele sayılar
// ---------------------------------------------------------------------
// PCG3D: piksel konumu + kare sayısından kaliteli rastgele sayı üretir
uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v;
}

vec3 hash33(uvec3 v) { return vec3(pcg3d(v)) / 4294967295.0; }

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Interleaved gradient noise: ekran üzerinde düzgün dağılmış sabit desen
// (gölge filtresi döndürme ve renk titreşimi için)
float ign(vec2 p) {
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

// ---------------------------------------------------------------------
//  Değer gürültüsü (bulut ve su dalgaları için)
// ---------------------------------------------------------------------
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f); // yumuşak geçiş
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ---------------------------------------------------------------------
//  Örnekleme
// ---------------------------------------------------------------------
// Kosinüs ağırlıklı yarımküre yönü: dağınık (diffuse) yüzeyler için
// fiziksel olarak doğru dağılım. r: [0,1) aralığında iki rastgele sayı.
vec3 cosineHemisphere(vec3 n, vec2 r) {
    float phi  = TAU * r.x;
    float sinT = sqrt(r.y);
    float cosT = sqrt(1.0 - r.y);
    vec3 t = normalize(abs(n.y) < 0.999 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(1.0, 0.0, 0.0)));
    vec3 b = cross(n, t);
    return normalize(t * (cos(phi) * sinT) + b * (sin(phi) * sinT) + n * cosT);
}

// 12 noktalı Poisson diski (gölge ve gürültü giderici örnek konumları)
const vec2 poisson12[12] = vec2[12](
    vec2(-0.326212, -0.405805), vec2(-0.840144, -0.073580),
    vec2(-0.695914,  0.457137), vec2(-0.203345,  0.620716),
    vec2( 0.962340, -0.194983), vec2( 0.473434, -0.480026),
    vec2( 0.519456,  0.767022), vec2( 0.185461, -0.893124),
    vec2( 0.507431,  0.064425), vec2( 0.896420,  0.412458),
    vec2(-0.321940, -0.932615), vec2(-0.791559, -0.597705)
);

mat2 rotate2D(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

// 12 noktalı Poisson diski, her turda döndürülüp ölçeklenerek tekrar kullanılır.
// Böylece örnek sayısı 12'yi aşabilir ve diziyi taşırmayız.
vec2 poissonTap(int i, mat2 baseRot) {
    int turn = i / 12;
    mat2 turnRot = rotate2D(float(turn) * 0.7853981634);
    float scale = max(1.0 - float(turn) * 0.13, 0.25);
    return baseRot * turnRot * poisson12[i % 12] * scale;
}

// ---------------------------------------------------------------------
//  Işık haritası: Minecraft [1/32, 31/32] aralığında verir, [0,1]'e çeviririz
//  x = blok ışığı (meşale vb.), y = gökyüzü ışığı
// ---------------------------------------------------------------------
vec2 normalizeLightmap(vec2 lm) {
    return clamp((lm - 0.03125) * 1.06667, 0.0, 1.0);
}

#endif // INCLUDE_COMMON
