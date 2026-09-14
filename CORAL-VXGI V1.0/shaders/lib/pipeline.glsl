/*
=====================================================================
  lib/pipeline.glsl - Ekran dokularının (buffer) biçimleri
=====================================================================
  Iris aşağıdaki "const" satırlarını okuyarak colortex dokularını
  oluşturur. Biçim satırları yorum içinde olsa bile okunur.

  DOKU DÜZENİ
  colortex0  RGBA16F  gbuffers: albedo (sRGB)  |  deferred2 sonrası: aydınlatılmış HDR sahne
  colortex1  RGBA16   rg: normal (oktahedral, oyuncu uzayı), b: blok ışığı, a: gökyüzü ışığı
  colortex2  RGBA8    r: malzeme, g: ışıma kimliği, b: pürüzsüzlük, a: F0/metal
  colortex3  RGBA16F  ham 1 örnekli ışın izlemeli GI           (deferred yazar)
  colortex4  RGBA16F  GI geçmişi: rgb ışık, a: biriken kare     (deferred1 yazar, silinmez)
  colortex5  RGBA16   saydam veri: rg normal, b tür (0.5 cam, 1 su), a gökyüzü ışığı
  colortex6  RGBA8    yansıma bilgisi: rgb yansıma rengi (F0), a pürüzsüzlük (deferred2 yazar)
  colortex7  R32F     önceki karenin doğrusal derinliği         (deferred1 yazar, silinmez)

  "Clear = false" olan dokular kareler arasında korunur (zamansal geçmiş).
  Yeni doku eklerken buraya biçimini, aşağıya temizleme ayarını ekleyin.

const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA8;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16;
const int colortex6Format = RGBA8;
const int colortex7Format = R32F;
*/
#ifndef INCLUDE_PIPELINE
#define INCLUDE_PIPELINE

const bool colortex0Clear = true;
const bool colortex1Clear = true;
const bool colortex2Clear = true;
const bool colortex3Clear = true;
const bool colortex4Clear = false; // GI geçmişi korunur
const bool colortex5Clear = true;
const bool colortex6Clear = true;
const bool colortex7Clear = false; // önceki derinlik korunur

const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

#endif // INCLUDE_PIPELINE
