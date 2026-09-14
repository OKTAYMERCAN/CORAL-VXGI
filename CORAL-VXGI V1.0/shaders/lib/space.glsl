/*
=====================================================================
  lib/space.glsl - Koordinat uzayı dönüşümleri
=====================================================================
  Kullanılan uzaylar:
    screen (ekran) : uv [0,1] + derinlik [0,1]
    view  (görüş)  : kamera merkezli, kameranın baktığı yön -Z
    player(oyuncu) : kamera merkezli ama dünya eksenlerine hizalı
                     dunyaKonumu = playerPos + cameraPosition
    voxel          : voxel ızgarasının indeksleri (bkz. lib/voxel.glsl)
    shadow         : gölge kamerasının uzayı (bkz. lib/shadows.glsl)
  Işık hesaplarının çoğu "player" uzayında yapılır.
=====================================================================
*/
#ifndef INCLUDE_SPACE
#define INCLUDE_SPACE

// Ekran uv + derinlik -> görüş uzayı
vec3 screenToView(vec2 uv, float depth) {
    vec4 v = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}

// Görüş -> oyuncu uzayı (kafa sallanması da hesaba katılır)
vec3 viewToPlayer(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
}

// Oyuncu -> görüş uzayı
vec3 playerToView(vec3 playerPos) {
    return mat3(gbufferModelView) * playerPos + gbufferModelView[3].xyz;
}

// Görüş uzayı -> ekran uv + derinlik
vec3 viewToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

// [0,1] derinlik değerini kameradan pozitif doğrusal mesafeye çevirir
float linearizeDepth(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return gbufferProjection[3][2] / (ndc + gbufferProjection[2][2]);
}

#endif // INCLUDE_SPACE
