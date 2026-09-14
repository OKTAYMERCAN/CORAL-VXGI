/*
=====================================================================
  CORAL VXGI - AYARLAR (lib/settings.glsl)
=====================================================================
  Shader paketinin TÜM kullanıcı ayarları bu dosyadadır. Iris bu
  satırları okuyarak oyun içindeki ayarlar menüsünü oluşturur.

  AYAR SATIRI BİÇİMİ
    Sayısal :  #define ISIM VARSAYILAN // [deger1 deger2 deger3] aciklama
    Açık    :  #define ISIM // aciklama
    Kapalı  :  //#define ISIM // aciklama

  IRIS KURALLARI (uyulmazsa ayar menüde görünmez)
    1. Değer listesi köşeli parantez içinde, TEK boşlukla ayrılır.
    2. Varsayılan değer listede bulunmalıdır.
    3. Açıklamada liste başlamadan önce '[' karakteri olmamalıdır.
    4. Açık/kapalı ayarlar dosyanın EN ALTINDAKİ #ifdef bloğunda
       da yazılmalıdır; Iris yalnızca #ifdef ile kullanılanları gösterir.
    5. Ondalıklı ayarlar #if içinde karşılaştırılamaz (önişlemci
       sadece tamsayı anlar). Onları normal GLSL kodunda kullanın.

  Menüdeki isimler ve fareyle üzerine gelince çıkan açıklamalar:
    shaders/lang/tr_tr.lang  ve  shaders/lang/en_us.lang
  Menü düzeni (hangi ayar hangi sayfada):
    shaders/shaders.properties
=====================================================================
*/
#ifndef INCLUDE_SETTINGS
#define INCLUDE_SETTINGS

// =====================================================================
//  HAKKINDA (bilgi amaçlı sahte ayarlar - değerleri kullanılmaz)
//  Görünen yazılar lang dosyalarındaki option.ABOUT_* satırlarıdır.
// =====================================================================
#define ABOUT_PACK 0         // [0]
#define ABOUT_VERSION 0      // [0]
#define ABOUT_AUTHOR 0       // [0]
#define ABOUT_CONTACT 0      // [0]
#define ABOUT_WEBSITE 0      // [0]
#define ABOUT_LICENSE 0      // [0]
#define ABOUT_THANKS 0       // [0]
#define ABOUT_REQUIREMENTS 0 // [0]
#define ABOUT_PERFORMANCE 0  // [0]
#define ABOUT_DEBUG_HELP 0   // [0]

// =====================================================================
//  IŞIN İZLEME - GLOBAL AYDINLATMA (GI)
// =====================================================================
#define GI_ENABLED                      // Voxel ızgarasında ışın izlemeli dolaylı aydınlatma
#define GI_MAX_STEPS 48                 // [8 16 24 32 48 64 96 128 192 256 384 512] Bir GI ışınının geçebileceği en fazla voxel sayısı
#define GI_MAX_DISTANCE 96.0            // [16.0 24.0 32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0] GI ışınının blok cinsinden en uzun mesafesi
#define GI_STRENGTH 1.0                 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0] Dolaylı ışığın genel çarpanı
#define GI_BOUNCES 2                    // [1 2 3 4 5 6 8] Işığın kaç kez sekeceği (renk taşıması için 2 veya daha fazlası gerekir)
#define GI_SATURATION 1.5               // [0.0 0.5 1.0 1.15 1.3 1.5 1.75 2.0 2.5 3.0 4.0 6.0] Dolaylı ışığın renk yoğunluğu (renk taşıması)
#define GI_SKY_STRENGTH 0.65            // [0.0 0.1 0.25 0.5 0.65 0.8 1.0 1.25 1.5 2.0 3.0 4.0] Hiçbir şeye çarpmayan ışınların gökyüzünden aldığı ışık
#define GI_SUN_BOUNCE 1.0               // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0] Güneşin yüzeylerden sekerek gelen ışığı
#define GI_HIT_AMBIENT 0.15             // [0.0 0.05 0.1 0.15 0.2 0.35 0.5 0.75 1.0 1.5 2.0] Çarpılan yüzeydeki ortam ışığı (çoklu sekme yaklaşımı)
#define GI_FIREFLY_CLAMP 24.0           // [1.0 2.0 4.0 8.0 12.0 16.0 24.0 32.0 64.0 128.0 512.0 4096.0] Parlak nokta (ateşböceği) gürültüsü sınırı
#define GI_TEMPORAL_FRAMES 24           // [1 2 4 8 12 16 24 32 48 64 96 128 192 256 384 512 1024] Zamansal biriktirmede kullanılan en fazla kare
#define GI_TEMPORAL_DEPTH_TOLERANCE 0.04 // [0.005 0.01 0.02 0.04 0.06 0.1 0.2 0.4] Geçmiş reddetme için bağıl derinlik toleransı
#define GI_DENOISE                      // Uzamsal gürültü giderici
#define GI_DENOISE_SAMPLES 12           // [4 8 12 16 24 32 48 64] Gürültü gidericinin örnek sayısı
#define GI_DENOISE_RADIUS 10.0          // [0.0 2.0 4.0 6.0 8.0 10.0 14.0 20.0 28.0 40.0 64.0] Geçmiş kısayken bulanıklık yarıçapı (piksel)
#define GI_DENOISE_MIN_RADIUS 2.5       // [0.0 0.5 1.0 1.5 2.5 4.0 6.0 10.0 16.0 24.0] Geçmiş dolunca bulanıklık yarıçapı (piksel)
#define GI_DENOISE_NORMAL_WEIGHT 16.0   // [1.0 2.0 4.0 8.0 16.0 32.0 64.0 128.0 256.0] Normali farklı pikselleri karıştırmama sertliği
#define VOXEL_RANGE 128                 // [128 192 256] Işın izlenen alanın genişliği (blok)
#define VOXELIZE_LEAVES                 // Yapraklar ışığı engellesin
#define VOXEL_SHAPES                    // Blokların gerçek şeklini kullan (meşale, kapı, yarım blok...)
#define VOXELIZE_TRANSLUCENT_EMITTERS   // Saydam ışık kaynakları da ışın izlemeye girsin (Nether portalı)
#define EMISSION_SHAPE_BOOST 1.0        // [0.0 0.25 0.5 0.75 1.0] Küçük şekilli ışık kaynaklarının parlaklık telafisi
#define EMISSION_SHAPE_BOOST_MAX 6.0    // [1.0 2.0 3.0 4.0 6.0 8.0 12.0 16.0 24.0 32.0] Telafinin üst sınırı
#define AUTO_EMITTERS                   // Listede olmayan (modlu) ışık kaynaklarını otomatik algıla
#define EMISSION_STRENGTH 1.5           // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0 16.0] Işık yayan blokların genel gücü

// ---- Doğrudan ışık örnekleme: blok ışıklarının gerçek, şekilli gölgeleri ----
// Işınların meşaleye rastgele çarpmasını beklemek yerine ışık kaynaklarının
// listesi tutulur ve her piksel bir kaynağa gölge ışını gönderir.
#define RT_LIGHTS                       // Blok ışıkları gerçek gölge yapsın
#define RT_LIGHT_SAMPLES 8              // [1 2 4 6 8 12 16 24 32 48 64 96 128] Her karede değerlendirilen ışık adayı sayısı
#define RT_LIGHT_STRENGTH 1.0           // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0] Işın izlemeli blok ışığının gücü
#define RT_LIGHT_RANGE 40.0             // [8.0 16.0 24.0 32.0 40.0 64.0 96.0 128.0 192.0 256.0] Işık kaynağının etki menzili (blok)
#define RT_LIGHT_FALLOFF 0.7            // [0.05 0.1 0.25 0.4 0.55 0.7 1.0 1.5 2.0 3.0] Işığın mesafeyle azalma hızı
#define RT_LIGHT_SIZE 1.0               // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0] Işık kaynağının gerçek boyutunun çarpanı (0 = nokta ışık, sert gölge)
#define REFLECTION_BLOCK_LIGHT          // Yansıyan yüzeylere de blok ışığı düşsün (kapalı mekanda siyah yansımayı önler)

// ---- Işık yayan blok renkleri (kırmızı, yeşil, mavi, güç) ----
#define EMIT_FIRE_R 1.0      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_FIRE_G 0.5      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_FIRE_B 0.2      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_FIRE_I 4.0      // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_SOUL_R 0.2      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_SOUL_G 0.75     // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_SOUL_B 1.0      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_SOUL_I 3.0      // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_LAMP_R 1.0      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_LAMP_G 0.8      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_LAMP_B 0.5      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_LAMP_I 1.5      // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_LAVA_R 1.0      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_LAVA_G 0.35     // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_LAVA_B 0.05     // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_LAVA_I 5.0      // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_REDSTONE_R 1.0  // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_REDSTONE_G 0.1  // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_REDSTONE_B 0.05 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_REDSTONE_I 2.5  // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_COOL_R 0.7      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_COOL_G 0.9      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_COOL_B 1.0      // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_COOL_I 5.0      // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_PURPLE_R 0.6    // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_PURPLE_G 0.3    // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_PURPLE_B 1.0    // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_PURPLE_I 2.5    // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_GREEN_R 0.35    // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_GREEN_G 1.0     // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_GREEN_B 0.75    // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define EMIT_GREEN_I 2.0     // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]

// Renkli mumlar gibi bloklar ışığı kendi doku renginde yayar
#define EMIT_TINTED_I 3.0     // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0 14.0 20.0]
#define EMIT_TINTED_SAT 1.3   // [0.0 0.25 0.5 0.75 1.0 1.15 1.3 1.5 2.0 3.0 4.0] Doku renginin doygunluğu

// Normalde ışık yaymayan blokları ışık kaynağına çevirir (renk karışımı denemek için).
// Her biri ışığı kendi doku renginde yayar: kırmızı + mavi = mor.
#define EMIT_CUSTOM_I 0.5               // [0.0 0.02 0.05 0.1 0.2 0.3 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Bu blokların ışık gücü
//#define EMIT_CONCRETE_POWDER          // Beton tozu blokları ışık yaysın
//#define EMIT_CONCRETE                 // Beton blokları ışık yaysın
//#define EMIT_WOOL                     // Yün blokları ışık yaysın
//#define EMIT_MINERAL_BLOCKS           // Kızıltaş, lapis, zümrüt, elmas, ametist, kömür blokları ışık yaysın

// =====================================================================
//  RENKLİ IŞIK GEÇİŞİ (cam, buz, delikli bloklar)
// =====================================================================
#define COLORED_SHADOWS                 // Güneş ışığı renkli camdan geçerken renklenir
#define GLASS_TRANSMISSION              // Blok ışıkları da renkli camdan geçerken renklenir
#define GLASS_TINT_STRENGTH 0.85        // [0.0 0.25 0.5 0.7 0.85 1.0] Camın ışığı ne kadar renklendireceği
#define TRANSMISSION_FROM_ALPHA         // Delikli bloklar (kapak, parmaklık) ışığın bir kısmını geçirsin
#define CUTOUT_SHADOW_MASK              // Delikli blokların gölgesi deliklerin şeklinde düşsün
#define CUTOUT_MASK_RES 16              // [8 16] Delik maskesi çözünürlüğü (16 = doku ile birebir, 4 kat bellek)
#define SHADOW_TINT_BRIGHTNESS 1.3      // [0.5 0.75 1.0 1.3 1.6 2.0] Renkli gölgelerin parlaklığı

// =====================================================================
//  YANSIMALAR
// =====================================================================
#define RT_REFLECTIONS                  // Işın izlemeli yansımalar
#define REFLECTION_STEPS 96             // [8 16 32 48 64 96 128 192 256 384 512] Yansıma ışınının geçebileceği en fazla voxel
#define REFLECTION_MAX_DISTANCE 160.0   // [16.0 32.0 64.0 96.0 128.0 160.0 256.0 384.0 512.0] Yansıma ışınının en uzun mesafesi (blok)
#define REFLECTION_SCREEN_LOOKUP        // Isabet noktası ekrandaysa dokulu pikseli kullan
#define SSR_FALLBACK                    // Voxelde olmayan şeyler için ekran uzayı yansıması
#define SSR_MAX_STEPS 40                // [8 16 24 32 40 64 96 128 192 256] Ekran uzayı yansımasında en fazla adım
#define SSR_THICKNESS 0.4               // [0.05 0.1 0.2 0.4 0.8 1.6 3.0 6.0] Ekran uzayı yansımasında yüzey kalınlığı (blok)
#define WATER_REFLECTIONS               // Suda yansıma
#define GLASS_REFLECTIONS               // Cam ve buzda yansıma
#define GLASS_REFLECTION_STRENGTH 0.6   // [0.2 0.4 0.6 0.8 1.0 1.5 2.0] Cam yansımasının gücü
#define GLASS_REFRACTION                // Cam ve buzun arkasındaki görüntüyü hafifçe kaydır
#define GLASS_REFRACTION_STRENGTH 0.15  // [0.0 0.05 0.1 0.15 0.25 0.35 0.5 0.75 1.0] Cam kırılma gücü
#define GLASS_REFRACTION_DEPTH 0.35    // [0.1 0.2 0.35 0.5 0.75 1.0 2.0] Camın kırılma için varsayılan kalınlığı
#define BLOCK_REFLECTIONS               // Cilalı ve metal bloklarda yansıma
#define POLISHED_SMOOTHNESS 0.82        // [0.5 0.6 0.7 0.75 0.82 0.9 0.95 1.0] Cilalı blokların pürüzsüzlüğü
#define METAL_SMOOTHNESS 0.72           // [0.5 0.6 0.72 0.8 0.9 0.95 1.0] Metal blokların pürüzsüzlüğü
#define REFLECTION_MIN_SMOOTHNESS 0.35  // [0.0 0.05 0.1 0.2 0.35 0.5 0.7 0.9] Bu değerin altındaki yüzeyler yansıtmaz
#define ROUGH_REFLECTION_JITTER 0.6     // [0.0 0.15 0.3 0.6 1.0 1.5 2.0 3.0] Pürüzlü yüzeylerde yansıma dağınıklığı
#define SUN_SPECULAR                    // Pürüzsüz yüzeylerde güneş parlaması
#define LABPBR                          // LabPBR kaynak paketi haritalarını kullan (pürüzsüzlük/metal)
#define LABPBR_EMISSION                 // LabPBR ışıma haritalarını kullan

// =====================================================================
//  AYDINLATMA
// =====================================================================
#define SUN_BRIGHTNESS 1.0              // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0] Güneş ışığı gücü
#define MOON_BRIGHTNESS 0.1             // [0.0 0.02 0.05 0.1 0.15 0.2 0.3 0.5 1.0 2.0 4.0] Ay ışığı gücü
#define SKY_BRIGHTNESS 1.0              // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0] Gökyüzü ve ortam ışığı gücü
#define MIN_LIGHT 0.008                 // [0.0 0.002 0.004 0.008 0.016 0.03 0.05 0.1 0.15 0.25 0.4] Tamamen karanlık yerlerdeki en düşük ışık
#define BLOCKLIGHT_STRENGTH 1.0         // [0.0 0.1 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0] Vanilla blok ışığı gücü
#define BLOCKLIGHT_R 1.0                // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define BLOCKLIGHT_G 0.6                // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define BLOCKLIGHT_B 0.3                // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define BLOCKLIGHT_CURVE 3.0            // [1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0] Blok ışığının mesafeyle azalma eğrisi
#define LIGHTMAP_RT_BLEND 0.15          // [0.0 0.15 0.3 0.45 0.6 0.8 1.0] Voxel alanında vanilla blok ışığından ne kadar kalsın
#define HAND_LIGHT                      // Elde tutulan ışık kaynağı çevreyi aydınlatsın
#define HAND_LIGHT_STRENGTH 2.2         // [0.0 0.25 0.5 1.0 1.5 2.2 3.0 4.0 6.0 8.0 12.0] Elde tutulan ışığın gücü
#define HAND_LIGHT_RANGE 1.0            // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0] Elde tutulan ışığın menzili
#define FOLIAGE_TRANSLUCENCY            // Bitki ve yapraklardan ışık geçsin
#define LEAK_FIX                        // Mağaralara gökyüzü/güneş ışığı sızmasını engelle
#define NETHER_AMBIENT 0.3              // [0.1 0.2 0.3 0.4 0.6 0.8 1.0 1.5 2.0 3.0] Nether ortam ışığı
#define END_AMBIENT 0.05                // [0.02 0.05 0.08 0.12 0.2 0.3 0.5 0.75 1.0] End ortam ışığı

// =====================================================================
//  GÖLGELER
// =====================================================================
const int shadowMapResolution = 2048;   // [512 1024 1536 2048 3072 4096 6144 8192 12288 16384]
const float shadowDistance = 128.0;     // [32.0 64.0 96.0 128.0 160.0 192.0 256.0 320.0 384.0 512.0]
const float sunPathRotation = -25.0;    // [-40.0 -30.0 -25.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0]
const float shadowDistanceRenderMul = 1.0;
#define SHADOW_SOFTNESS 1.0             // [0.0 0.25 0.5 1.0 1.5 2.0 3.0 4.0 6.0 8.0 12.0] Gölge kenarı yumuşaklığı
#define SHADOW_SAMPLES 12               // [1 2 4 8 12 16 24 32 48 64 96 128] Yumuşak gölge için örnek sayısı
#define SHADOW_DISTORTION 0.85          // [0.0 0.5 0.7 0.8 0.85 0.9 0.95] Yakın gölgelere daha çok çözünürlük ver
#define SHADOW_BIAS 1.2                 // [0.1 0.25 0.5 0.8 1.0 1.2 1.5 2.0 3.0 4.0 6.0] Gölge sivilcesi önleme kayması
#define SHADOW_EDGE_FADE                // Gölge mesafesinin sonunda gölgeyi yumuşakça bitir

// Iris, voxel alanındaki chunk'ları gölge geçişinde çizmek için bunu kullanır
#if VOXEL_RANGE == 256
    const float voxelDistance = 136.0;
#elif VOXEL_RANGE == 192
    const float voxelDistance = 104.0;
#else
    const float voxelDistance = 72.0;
#endif

// =====================================================================
//  GÖKYÜZÜ VE SİS
// =====================================================================
#define SUN_DISC                        // Gökyüzünde güneş diski çiz
#define SUN_DISC_SIZE 1.0               // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Güneş diski boyutu
#define SUN_DISC_BRIGHTNESS 60.0        // [10.0 20.0 40.0 60.0 100.0 200.0 400.0 800.0] Güneş diski parlaklığı
#define SUNSET_STRENGTH 1.0             // [0.0 0.5 1.0 1.5 2.0 3.0 4.0] Gün doğumu/batımı renk gücü
#define STARS_BRIGHTNESS 2.0            // [0.0 0.5 1.0 2.0 3.0 4.0 6.0 8.0 12.0] Yıldız parlaklığı
#define MOON_TEXTURE_BRIGHTNESS 1.5     // [0.5 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Ay dokusunun parlaklığı
#define CLOUDS                          // Prosedürel bulutlar
#define CLOUD_HEIGHT 420.0              // [192.0 256.0 320.0 420.0 512.0 768.0 1024.0 1536.0] Bulut yüksekliği (Y)
#define CLOUD_AMOUNT 0.5                // [0.2 0.35 0.5 0.65 0.8] Bulut miktarı
#define CLOUD_SPEED 1.0                 // [0.0 0.5 1.0 2.0 4.0 8.0 16.0] Bulut hızı
#define CLOUD_SCALE 1.0                 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0] Bulut boyutu
#define FOG                             // Mesafe sisi
#define FOG_DENSITY 1.0                 // [0.0 0.1 0.25 0.5 1.0 1.5 2.0 3.0 5.0 8.0] Sis yoğunluğu
#define BORDER_FOG                      // Görüş mesafesi sınırında sis (chunk kenarlarını gizler)
#define BORDER_FOG_START 0.72           // [0.5 0.6 0.72 0.8 0.9] Sınır sisinin başladığı oran
#define RAIN_DARKNESS 0.85              // [0.0 0.25 0.5 0.7 0.85 1.0] Yağmurda güneş ne kadar kararsın

// =====================================================================
//  SU
// =====================================================================
#define WATER_WAVES                     // Su dalgaları
#define WATER_WAVE_STRENGTH 1.0         // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0] Dalga yüksekliği
#define WATER_WAVE_SPEED 1.0            // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Dalga hızı
#define WATER_WAVE_SCALE 1.0            // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0] Dalga boyutu
#define WATER_REFRACTION                // Su yüzeyinin arkasındaki görüntüyü kırılmayla kaydır
#define WATER_REFRACTION_STRENGTH 1.0   // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Su kırılma gücü
#define WATER_ABSORPTION 1.4            // [0.25 0.5 0.75 1.0 1.2 1.4 1.7 2.0 3.0 4.0 6.0 8.0] Derin suyun ışığı yutması
#define WATER_SCATTER 1.4               // [0.0 0.5 1.0 1.2 1.4 1.7 2.0 3.0 4.0 6.0 8.0] Suyun kendi mavi yeşil rengi
#define WATER_SURFACE_OPACITY 0.12      // [0.0 0.05 0.12 0.2 0.3 0.5] Su yüzeyinin opaklığı
#define WATER_SUN_SPECULAR              // Suda güneş parlaması
#define WATER_CAUSTICS                  // Su altındaki yüzeylerde ışık desenleri
#define CAUSTICS_STRENGTH 1.0           // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Işık deseni gücü
#define CAUSTICS_SCALE 1.0              // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0 8.0] Işık deseni boyutu
#define CAUSTICS_SPEED 1.0              // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 6.0] Işık deseni hızı
#define UNDERWATER_FOG_DENSITY 1.0      // [0.25 0.5 1.0 1.5 2.0 3.0 4.0 6.0] Su altı sisi yoğunluğu
#define UNDERWATER_BIOME_TINT           // Su altı sisinde biyomun su rengini kullan

// =====================================================================
//  SON İŞLEME
// =====================================================================
#define BLOOM                           // Parlak alanların etrafında parlama
#define BLOOM_STRENGTH 0.06             // [0.0 0.01 0.02 0.04 0.06 0.08 0.12 0.16 0.24 0.4 0.6 1.0] Parlama gücü
#define EXPOSURE 1.0                    // [0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0 6.0 8.0] Genel pozlama
#define AUTO_EXPOSURE                   // Mağarada ve gece otomatik pozlama
#define CAVE_EXPOSURE 2.6               // [1.0 1.5 2.0 2.6 3.5 5.0 8.0 12.0 16.0] Mağarada pozlama artışı
#define NIGHT_EXPOSURE 2.2              // [1.0 1.5 2.2 3.0 4.0 6.0 8.0 12.0] Gece pozlama artışı
#define TONEMAP 0                       // [0 1 2 3] Ton eşleme yöntemi
#define SATURATION 1.05                 // [0.0 0.25 0.5 0.8 0.9 1.0 1.05 1.1 1.2 1.3 1.5 2.0 3.0] Renk doygunluğu
#define CONTRAST 1.0                    // [0.5 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.5 2.0] Kontrast
#define VIGNETTE_STRENGTH 0.0           // [0.0 0.1 0.2 0.3 0.5 0.75 1.0] Ekran kenarı kararması (0 = kapalı)
#define DITHERING                       // Renk bantlanmasını azaltan titreşim

// =====================================================================
//  HATA AYIKLAMA (DEBUG)
//  DEBUG_VIEW numaraları lib/debug.glsl içinde isimlendirilmiştir.
// =====================================================================
// Bilgi satırları (üzerine gelince hata ayıklama görünümlerinin ayrıntılı açıklaması çıkar)
#define DEBUG_HELP_GBUFFER 0            // [0]
#define DEBUG_HELP_GI 0                 // [0]
#define DEBUG_HELP_LIGHT 0              // [0]
#define DEBUG_HELP_VOXEL 0              // [0]
#define DEBUG_HELP_TOOLS 0              // [0]
#define DEBUG_VIEW 0                    // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22] Ekranda gösterilecek ara veri
//#define DEBUG_SPLIT                   // Ekranın sol yarısında hata ayıklama, sağ yarısında normal görüntü
//#define DEBUG_NAN_CHECK               // Bozuk (NaN/sonsuz) pikselleri pembe göster
//#define DEBUG_SHADOW_OVERLAY          // Sol alt köşede gölge haritasını göster
//#define DEBUG_FREEZE_NOISE            // GI rastgeleliğini dondur (değişiklikleri karşılaştırmak için)

// =====================================================================
//  AÇIK/KAPALI AYAR KAYDI
//  Iris açık/kapalı ayarları sadece #ifdef/#ifndef ile kullanıldıklarında
//  menüde gösterir. YENİ BİR AÇIK/KAPALI AYAR EKLERSENİZ BURAYA DA YAZIN.
// =====================================================================
#ifdef GI_ENABLED
#endif
#ifdef GI_DENOISE
#endif
#ifdef VOXELIZE_LEAVES
#endif
#ifdef VOXEL_SHAPES
#endif
#ifdef RT_LIGHTS
#endif
#ifdef REFLECTION_BLOCK_LIGHT
#endif
#ifdef CUTOUT_SHADOW_MASK
#endif
#ifdef COLORED_SHADOWS
#endif
#ifdef GLASS_TRANSMISSION
#endif
#ifdef TRANSMISSION_FROM_ALPHA
#endif
#ifdef EMIT_CONCRETE_POWDER
#endif
#ifdef EMIT_CONCRETE
#endif
#ifdef EMIT_WOOL
#endif
#ifdef EMIT_MINERAL_BLOCKS
#endif
#ifdef VOXELIZE_TRANSLUCENT_EMITTERS
#endif
#ifdef GLASS_REFRACTION
#endif
#ifdef WATER_REFRACTION
#endif
#ifdef WATER_CAUSTICS
#endif
#ifdef UNDERWATER_BIOME_TINT
#endif
#ifdef AUTO_EMITTERS
#endif
#ifdef RT_REFLECTIONS
#endif
#ifdef REFLECTION_SCREEN_LOOKUP
#endif
#ifdef SSR_FALLBACK
#endif
#ifdef WATER_REFLECTIONS
#endif
#ifdef GLASS_REFLECTIONS
#endif
#ifdef BLOCK_REFLECTIONS
#endif
#ifdef SUN_SPECULAR
#endif
#ifdef LABPBR
#endif
#ifdef LABPBR_EMISSION
#endif
#ifdef HAND_LIGHT
#endif
#ifdef FOLIAGE_TRANSLUCENCY
#endif
#ifdef LEAK_FIX
#endif
#ifdef SHADOW_EDGE_FADE
#endif
#ifdef SUN_DISC
#endif
#ifdef CLOUDS
#endif
#ifdef FOG
#endif
#ifdef BORDER_FOG
#endif
#ifdef WATER_WAVES
#endif
#ifdef WATER_SUN_SPECULAR
#endif
#ifdef BLOOM
#endif
#ifdef AUTO_EXPOSURE
#endif
#ifdef DITHERING
#endif
#ifdef DEBUG_SPLIT
#endif
#ifdef DEBUG_NAN_CHECK
#endif
#ifdef DEBUG_SHADOW_OVERLAY
#endif
#ifdef DEBUG_FREEZE_NOISE
#endif

#endif // INCLUDE_SETTINGS
