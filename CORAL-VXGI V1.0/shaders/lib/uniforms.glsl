/*
=====================================================================
  lib/uniforms.glsl - Iris'in her kare gönderdiği ortak değişkenler
=====================================================================
  Kullanılmayan uniform'lar derleyici tarafından otomatik silinir,
  bu yüzden hepsini tek yerde tanımlamak güvenlidir.
  Sampler'lar (doku okuyucular) BURADA DEĞİL, her programda ayrı
  tanımlanır; çünkü bir programın yazdığı dokuyu okuması sorun çıkarır.
  Tam liste: https://shaders.properties (Iris dokümantasyonu)
=====================================================================
*/
#ifndef INCLUDE_UNIFORMS
#define INCLUDE_UNIFORMS

uniform int   frameCounter;          // Başlangıçtan beri kare sayısı
uniform float frameTimeCounter;      // Saniye cinsinden süre (saatte bir sıfırlanır)
uniform float viewWidth;             // Ekran genişliği (piksel)
uniform float viewHeight;            // Ekran yüksekliği (piksel)
uniform float near;                  // Kamera yakın kesme mesafesi
uniform float far;                   // Görüş mesafesi (blok)
uniform float rainStrength;          // 0 = açık hava, 1 = tam yağış
uniform float nightVision;           // Gece görüşü iksiri etkisi
uniform float blindness;             // Körlük etkisi
uniform int   isEyeInWater;          // 0 hava, 1 su, 2 lav, 3 toz kar
uniform int   worldTime;             // Oyun içi saat (0-24000)
uniform int   heldBlockLightValue;   // Ana eldeki eşyanın ışık seviyesi
uniform int   heldBlockLightValue2;  // İkinci eldeki eşyanın ışık seviyesi
uniform ivec2 eyeBrightnessSmooth;   // Göz hizasındaki ışık (y = gökyüzü, 0-240)

uniform vec3 cameraPosition;         // Kameranın dünya konumu
uniform vec3 previousCameraPosition; // Önceki karedeki kamera konumu
uniform vec3 sunPosition;            // Güneş yönü (görüş uzayı)
uniform vec3 moonPosition;           // Ay yönü (görüş uzayı)
uniform vec3 shadowLightPosition;    // Gölge veren ışık: gündüz güneş, gece ay
uniform vec3 fogColor;               // Vanilla sis rengi (Nether'da biyoma göre)
uniform vec3 skyColor;               // Vanilla gökyüzü rengi

// Dönüşüm matrisleri (uzaylar için bkz. lib/space.glsl)
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

#endif // INCLUDE_UNIFORMS
