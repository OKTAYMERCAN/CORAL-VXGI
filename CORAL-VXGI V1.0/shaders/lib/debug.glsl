/*
=====================================================================
  lib/debug.glsl - Hata ayıklama görünümleri
=====================================================================
  Ayarlar > Hata Ayıklama > "Görünüm" seçeneği (DEBUG_VIEW) ekranda
  normal görüntü yerine bir ara veriyi gösterir. Her görünüm, verinin
  bulunduğu geçişte üretilir:

    deferred2 : albedo, gürültüsüz GI, doğrudan ışık, gölge,
                blok ışığı, ışıma   (aydınlatma bileşenleri orada birleşir)
    composite : yansımalar          (yansımalar orada hesaplanır)
    final     : diğerleri           (G-buffer ve geçmiş dokuları hâlâ geçerli)

  YENİ BİR GÖRÜNÜM EKLEMEK İÇİN
    1. Aşağıya yeni bir DBG_ sabiti ekleyin (sıradaki numara)
    2. settings.glsl'deki DEBUG_VIEW değer listesine numarayı ekleyin
    3. Görünümü uygun geçişte üretin (genelde program/final.glsl
       içindeki finalDebugView fonksiyonu yeterli)
    4. Lang dosyalarına value.DEBUG_VIEW.N ismini ve açıklamayı ekleyin
=====================================================================
*/
#ifndef INCLUDE_DEBUG
#define INCLUDE_DEBUG

const int DBG_OFF          = 0;
const int DBG_ALBEDO       = 1;  // deferred2 - yüzey rengi (ışıksız)
const int DBG_NORMALS      = 2;  // final     - yüzey normalleri
const int DBG_LIGHTMAP     = 3;  // final     - vanilla ışık haritası
const int DBG_MATERIAL     = 4;  // final     - malzeme kimliği
const int DBG_SMOOTHNESS   = 5;  // final     - pürüzsüzlük / F0 / metal
const int DBG_EMISSION_ID  = 6;  // final     - ışıma kategorisi
const int DBG_DEPTH        = 7;  // final     - derinlik
const int DBG_GI_RAW       = 8;  // final     - ham 1 örnekli GI
const int DBG_GI_ACCUM     = 9;  // final     - zamansal biriktirilmiş GI
const int DBG_GI_DENOISED  = 10; // deferred2 - gürültüsü giderilmiş GI
const int DBG_GI_HISTORY   = 11; // final     - biriktirilen kare sayısı
const int DBG_DIRECT       = 12; // deferred2 - güneş/ay ışığı
const int DBG_SHADOW       = 13; // deferred2 - gölge terimi
const int DBG_BLOCKLIGHT   = 14; // deferred2 - blok ışığı + el ışığı
const int DBG_VOXEL_ALBEDO = 15; // final     - voxel dünyasının renkleri
const int DBG_VOXEL_TYPES  = 16; // final     - voxel kodları
const int DBG_VOXEL_RANGE  = 17; // final     - ışın izleme alanı sınırı
const int DBG_REFLECTIONS  = 18; // composite - yalnızca yansımalar
const int DBG_TRANSLUCENT  = 19; // final     - saydam yüzey verisi
const int DBG_EMISSION      = 20; // deferred2 - yüzeylerin ışıması
const int DBG_RT_LIGHTS     = 22; // deferred2 - yalnızca ışın izlemeli blok ışıkları
const int DBG_VOXEL_SHAPES  = 21; // final     - voxel şekilleri (tam küp / kısmi)

// Bu piksel hata ayıklama görüntüsü mü gösteriyor? (bölünmüş ekranda sol yarı)
bool debugActive(vec2 uv) {
    if (DEBUG_VIEW == DBG_OFF) return false;
    #ifdef DEBUG_SPLIT
        return uv.x < 0.5;
    #else
        return true;
    #endif
}

bool isDeferredDebugView(int v) {
    return v == DBG_ALBEDO || v == DBG_GI_DENOISED || v == DBG_DIRECT || v == DBG_RT_LIGHTS ||
           v == DBG_SHADOW || v == DBG_BLOCKLIGHT || v == DBG_EMISSION;
}

bool isCompositeDebugView(int v) { return v == DBG_REFLECTIONS; }

// HDR değerli görünümler final'de sıkıştırılarak gösterilir
bool isHdrDebugView(int v) {
    return v == DBG_GI_DENOISED || v == DBG_DIRECT || v == DBG_BLOCKLIGHT || v == DBG_RT_LIGHTS ||
           v == DBG_EMISSION || v == DBG_REFLECTIONS || v == DBG_GI_RAW || v == DBG_GI_ACCUM;
}

// HDR değeri ekranda görülebilir hale getirir (basit Reinhard + gamma)
vec3 debugCompress(vec3 hdr) { return toSRGB(hdr / (1.0 + hdr)); }

// Malzeme kimliği renkleri
vec3 debugMaterialColor(int m) {
    if (m == MAT_UNLIT)    return vec3(0.0);            // siyah
    if (m == MAT_LIT)      return vec3(0.55);           // gri
    if (m == MAT_PLANT)    return vec3(0.4, 1.0, 0.3);  // açık yeşil
    if (m == MAT_LEAVES)   return vec3(0.1, 0.5, 0.1);  // koyu yeşil
    if (m == MAT_EMISSIVE) return vec3(1.0, 0.85, 0.1); // sarı
    if (m == MAT_HAND)     return vec3(1.0, 0.2, 1.0);  // pembe
    return vec3(1.0, 0.0, 0.0);                          // bilinmeyen: kırmızı
}

// Voxel kodu renkleri
vec3 debugVoxelTypeColor(int code) {
    if (code == VOXEL_SOLID)    return vec3(0.6);            // katı: gri
    if (code == VOXEL_LEAVES)   return vec3(0.2, 0.8, 0.2);  // yaprak: yeşil
    if (code == VOXEL_POLISHED) return vec3(0.3, 0.9, 1.0);  // cilalı: camgöbeği
    if (code == VOXEL_METAL)    return vec3(1.0, 0.8, 0.3);  // metal: altın
    if (code == VOXEL_TINTED)   return vec3(1.0, 1.0, 0.6);  // doku renginde yayan: açık sarı
    if (code >= 11 && code < VOXEL_TINTED) {                 // listelenmiş ışık: kendi rengi
        vec3 c = emissionColor(code - 10);
        return c / max(maxOf(c), 0.001);
    }
    if (code >= 21 && code <= 35) return vec3(1.0, 0.4, 1.0); // otomatik ışık: mor-pembe
    return vec3(1.0, 0.0, 0.0);                                // bilinmeyen: kırmızı
}

#endif // INCLUDE_DEBUG
