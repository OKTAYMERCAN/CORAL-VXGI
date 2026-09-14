/*
=====================================================================
  lib/materials.glsl - Blok kimlikleri, voxel kodları, ışık renkleri
=====================================================================
  Blok kimlikleri shaders/block.properties dosyasında atanır ve
  shader'a mc_Entity.x (arazi) veya blockEntityId (blok varlıkları)
  olarak gelir. Buradaki sabitler o dosyadaki numaralarla AYNI olmalı.

  YENİ BİR IŞIK RENGİ KATEGORİSİ EKLEMEK İÇİN:
    1. block.properties'e block.3008 = ... satırı ekleyin
    2. ID_EMIT_LAST değerini 3008 yapın
    3. settings.glsl'e EMIT_YENI_R/G/B/I ayarlarını ekleyin
    4. emissionColor() fonksiyonuna "category == 9" satırı ekleyin
    5. Voxel kodu 11 + 8 = 19 olur; 20'yi geçmemeye dikkat edin
=====================================================================
*/
#ifndef INCLUDE_MATERIALS
#define INCLUDE_MATERIALS

// ---------------------------------------------------------------------
//  block.properties kimlikleri
// ---------------------------------------------------------------------
const int ID_WATER       = 1000; // Su (voxelleştirilmez)
const int ID_TRANSLUCENT = 1001; // Cam, buz, bal... (voxelleştirilmez)
const int ID_PLANT       = 1002; // Çim, çiçek, ekin (voxelleştirilmez)
const int ID_NONSOLID    = 1003; // Çit, parmaklık, zincir, ağ... (hiç voxelleştirilmez)
const int ID_SHAPED      = 1004; // Kapı, kapak, örs, halı... (yalnızca VOXEL_SHAPES açıkken)
const int ID_LEAVES      = 2000; // Yapraklar
const int ID_POLISHED    = 2001; // Cilalı bloklar (yansıtır)
const int ID_METAL       = 2002; // Metal bloklar (metal yansıma)
const int ID_EMIT_FIRST  = 3000; // 3000..3007 sabit renkli ışık kategorileri
const int ID_EMIT_TINTED = 3008; // ışığı kendi doku renginde yayanlar (renkli mumlar)
const int ID_EMIT_LAST   = 3008;

// Normalde ışık yaymayan ama ayarla ışık kaynağına çevrilebilen bloklar.
// Ayar kapalıyken normal blok gibi davranırlar (beton cilalı, yün mat...).
const int ID_CONCRETE_POWDER = 2100;
const int ID_CONCRETE        = 2101;
const int ID_WOOL            = 2102;
const int ID_MINERAL         = 2103;
const int ID_END_PORTAL  = 4000; // End portalı (blok varlığı)

// Vanilla blok ışığının rengi (ayarlardan)
const vec3 BLOCKLIGHT_COLOR = vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B);

// ---------------------------------------------------------------------
//  Voxel kodları: voxel görüntüsünün alfa kanalında (değer/255) saklanır
// ---------------------------------------------------------------------
//    0        boş (hava)
//    1        katı blok
//    2        yaprak
//    3        cilalı blok
//    4        metal blok
//    5        ışık geçiren (renkli cam, delikli blok): rgb = kanal başına geçirgenlik
//    11..19   listelenmiş ışık kaynağı, kategori 1..9 (9 = doku renginde)
//    21..35   otomatik algılanan ışık kaynağı, ışık seviyesi 1..15
const int VOXEL_EMPTY    = 0;
const int VOXEL_SOLID    = 1;
const int VOXEL_LEAVES   = 2;
const int VOXEL_POLISHED = 3;
const int VOXEL_METAL    = 4;
const int VOXEL_TRANSMISSIVE = 5;   // renkli cam: ışığı düzgün biçimde renklendirir
const int VOXEL_CUTOUT       = 6;   // dokusunda delik olan blok (kapak, kapı): delik maskesi kullanılır

const int TINTED_CATEGORY = 9;           // doku renginde yayan kategori (mumlar)
const int CUSTOM_CATEGORY = 10;          // ayarla açılan bloklar (beton, yün, mineral)
const int VOXEL_TINTED        = 19;      // 11 + 9 - 1
const int VOXEL_TINTED_CUSTOM = 20;

bool isEmissiveCategory(int id) { return id >= ID_EMIT_FIRST && id <= ID_EMIT_LAST; }

// Ayarla ışık kaynağına çevrilen bloklar
bool isCustomEmitter(int id) {
#ifdef EMIT_CONCRETE_POWDER
    if (id == ID_CONCRETE_POWDER) return true;
#endif
#ifdef EMIT_CONCRETE
    if (id == ID_CONCRETE) return true;
#endif
#ifdef EMIT_WOOL
    if (id == ID_WOOL) return true;
#endif
#ifdef EMIT_MINERAL_BLOCKS
    if (id == ID_MINERAL) return true;
#endif
    return false;
}

// Bir bloğun ışık kategorisi (1..8 sabit renk, 9 doku rengi, 10 ayarla açılan)
int emissionCategoryOf(int id) {
    if (isCustomEmitter(id)) return CUSTOM_CATEGORY;
    if (id == ID_EMIT_TINTED) return TINTED_CATEGORY;
    return id - ID_EMIT_FIRST + 1;
}

// Bloğun kendi doku renginden ışık rengi üretir. Böylece 16 mum rengi için
// 16 ayrı kategori tanımlamak gerekmez; mavi mum mavi, pembe mum pembe ışık verir.
vec3 tintedEmission(vec3 albedo, float intensity) {
    vec3 tint = albedo / max(maxOf(albedo), 0.05);        // en parlak kanala göre normalize et
    tint = mix(vec3(luminance(tint)), tint, EMIT_TINTED_SAT);
    return max(tint, vec3(0.0)) * intensity;
}

// Kategori (1..8) başına doğrusal HDR ışık rengi
vec3 emissionColor(int category) {
    if (category == 1) return vec3(EMIT_FIRE_R,     EMIT_FIRE_G,     EMIT_FIRE_B)     * EMIT_FIRE_I;     // ateş, meşale, fener
    if (category == 2) return vec3(EMIT_SOUL_R,     EMIT_SOUL_G,     EMIT_SOUL_B)     * EMIT_SOUL_I;     // ruh ateşi
    if (category == 3) return vec3(EMIT_LAMP_R,     EMIT_LAMP_G,     EMIT_LAMP_B)     * EMIT_LAMP_I;     // ışık taşı, lambalar
    if (category == 4) return vec3(EMIT_LAVA_R,     EMIT_LAVA_G,     EMIT_LAVA_B)     * EMIT_LAVA_I;     // lav, magma
    if (category == 5) return vec3(EMIT_REDSTONE_R, EMIT_REDSTONE_G, EMIT_REDSTONE_B) * EMIT_REDSTONE_I; // kızıltaş
    if (category == 6) return vec3(EMIT_COOL_R,     EMIT_COOL_G,     EMIT_COOL_B)     * EMIT_COOL_I;     // deniz feneri, end çubuğu
    if (category == 7) return vec3(EMIT_PURPLE_R,   EMIT_PURPLE_G,   EMIT_PURPLE_B)   * EMIT_PURPLE_I;   // ametist, ağlayan obsidyen
    if (category == 8) return vec3(EMIT_GREEN_R,    EMIT_GREEN_G,    EMIT_GREEN_B)    * EMIT_GREEN_I;    // parlak liken, parlak meyve
    // kategori 9 (doku renginde) sabit renk kullanmaz, bkz. tintedEmission()
    return vec3(0.0);
}

// Işın bir voxele çarptığında o voxelin yaydığı ışık
vec3 voxelEmission(int code, vec3 albedo) {
    if (code == VOXEL_TINTED) {
        return tintedEmission(albedo, EMIT_TINTED_I) * EMISSION_STRENGTH;
    }
    if (code == VOXEL_TINTED_CUSTOM) {
        return tintedEmission(albedo, EMIT_CUSTOM_I) * EMISSION_STRENGTH;
    }
    if (code >= 11 && code < VOXEL_TINTED) {
        return emissionColor(code - 10) * EMISSION_STRENGTH;
    }
    if (code >= 21 && code <= 35) {
        // Otomatik algılanan kaynak: rengi dokudan, gücü ışık seviyesinden
        float level = float(code - 20) / 15.0;
        vec3 tint = albedo / max(maxOf(albedo), 0.05);
        return tint * level * level * 3.0 * EMISSION_STRENGTH;
    }
    return vec3(0.0);
}

#endif // INCLUDE_MATERIALS
