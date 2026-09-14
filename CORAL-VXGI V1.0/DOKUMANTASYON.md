# CORAL VXGI — Geliştirici Dokümantasyonu

Yapımcı: Oktay Mercan. Yapay zeka desteğiyle (Claude / Anthropic) geliştirilmiştir.

Bu belge shader paketinin nasıl çalıştığını ve nasıl düzenleneceğini anlatır. Kodun kendisi de ayrıntılı Türkçe yorum satırları içerir; her dosyanın başında o dosyanın görevi yazar.

**İçindekiler**

1. [Genel bakış](#1-genel-bakış)
2. [Klasör yapısı](#2-klasör-yapısı)
3. [Bir karenin çizim sırası](#3-bir-karenin-çizim-sırası)
4. [Doku (buffer) düzeni](#4-doku-buffer-düzeni)
5. [Voxel sistemi ve blok şekilleri](#5-voxel-sistemi-ve-blok-şekilleri)
6. [Işın izlemeli GI](#6-ışın-izlemeli-gi)
7. [Yansımalar, su ve kırılma](#7-yansımalar-su-ve-kırılma)
8. [Koordinat uzayları](#8-koordinat-uzayları)
9. [Ayar ekleme](#9-ayar-ekleme)
10. [Hakkında bölümü ve adınız](#10-hakkında-bölümü-ve-adınız)
11. [Hata ayıklama görünümleri](#11-hata-ayıklama-görünümleri)
12. [Blok ve ışık kategorisi ekleme](#12-blok-ve-ışık-kategorisi-ekleme)
13. [Yeni hata ayıklama görünümü ekleme](#13-yeni-hata-ayıklama-görünümü-ekleme)
14. [Yeni program ekleme](#14-yeni-program-ekleme)
15. [Araçlar](#15-araçlar)
16. [Sık karşılaşılan hatalar](#16-sık-karşılaşılan-hatalar)
17. [Değişiklik geçmişi](#17-değişiklik-geçmişi)

---

## 1. Genel bakış

CORAL VXGI, **Iris** için yazılmış ertelenmiş (deferred) bir shader paketidir. Işın izleme ekran kartının donanımsal RT özelliğiyle değil, **voxel ızgarasında yazılımsal olarak** yapılır:

1. Gölge geçişi sırasında oyuncunun etrafındaki her blok 3D bir dokuya yazılır.
2. Her piksel için bu dokuda ışınlar gönderilir.
3. Işınların çarptığı bloklar ışığı hesaplamak için kullanılır.

Bu yüzden normal bir OpenGL 4.3 ekran kartında çalışır.

| Gereksinim | Neden |
|---|---|
| Iris 1.6+ ve Sodium | `image.` (3D özel görüntü) ve blok başına voxel verisi (`at_midBlock`) yalnızca Iris'te var |
| OpenGL 4.3 | Vertex shader'dan 3D dokuya yazmak (`imageStore`) için |
| `CUSTOM_IMAGES`, `PER_BUFFER_BLENDING` | `shaders.properties` içinde zorunlu özellik olarak istenir; yoksa Iris paketi yüklemez ve nedenini söyler |

---

## 2. Klasör yapısı

```
CORAL-VXGI/
├── README.md                 Kullanıcıya yönelik kısa tanıtım ve kurulum
├── DOKUMANTASYON.md          Bu belge
├── tools/                    Geliştirme araçları (oyun bunları okumaz)
│   ├── generate_wrappers.py  world klasörlerindeki sarmalayıcıları üretir
│   ├── validate_glsl.py      Tüm programları derleyerek hata arar
│   └── check_consistency.py  Ayarlar / menü / dil dosyaları uyumunu denetler
└── shaders/                  Iris'in okuduğu klasör
    ├── shaders.properties    Özellikler, voxel görüntüsü, karışım, AYAR MENÜSÜ düzeni
    ├── block.properties      Blok grupları ve kimlik numaraları
    ├── dimension.properties  Hangi boyut hangi world klasörünü kullanır
    ├── lang/
    │   ├── tr_tr.lang        Türkçe ayar isimleri ve açıklamaları
    │   └── en_us.lang        İngilizce ayar isimleri ve açıklamaları
    ├── lib/                  Ortak kod (her program #include eder)
    │   ├── settings.glsl     TÜM AYARLAR burada
    │   ├── pipeline.glsl     colortex biçimleri ve temizleme ayarları
    │   ├── uniforms.glsl     Iris'in gönderdiği ortak değişkenler
    │   ├── common.glsl       Matematik, malzeme kimlikleri, normal kodlama, rastgelelik
    │   ├── materials.glsl    Blok kimlikleri, voxel kodları, ışık renkleri
    │   ├── space.glsl        Koordinat uzayı dönüşümleri
    │   ├── shadows.glsl      Gölge haritası bozulması ve örnekleme
    │   ├── sky.glsl          Gökyüzü, güneş, bulutlar, sis, sızıntı önleme
    │   ├── voxel.glsl        Voxel ızgarası ve DDA ışın izleyici
    │   ├── forward.glsl      Su/parçacık için basit aydınlatma
    │   └── debug.glsl        Hata ayıklama görünüm numaraları ve renkleri
    ├── program/              Asıl program kodları
    │   ├── shadow.glsl           Gölge haritası + voxelleştirme
    │   ├── gbuffers_solid.glsl   Opak geometri -> G-buffer
    │   ├── gbuffers_forward.glsl Parçacık, çizgi, yağmur, parıltı
    │   ├── gbuffers_sky.glsl     Yıldız ve ay
    │   ├── gbuffers_water.glsl   Su, cam, buz
    │   ├── deferred.glsl         Işın izlemeli GI
    │   ├── deferred1.glsl        Zamansal biriktirme
    │   ├── deferred2.glsl        Gürültü giderme + aydınlatma + gökyüzü
    │   ├── composite.glsl        Yansımalar + su + sis
    │   └── final.glsl            Bloom, ton eşleme, hata ayıklama görünümleri
    ├── world0/    Overworld sarmalayıcıları  (#define OVERWORLD)
    ├── world-1/   Nether sarmalayıcıları     (#define NETHER)
    └── world1/    End sarmalayıcıları        (#define END)
```

### Sarmalayıcı (wrapper) nedir?

Iris her program için `world0/gbuffers_terrain.fsh` gibi bir dosya arar. Bu dosyalar yalnızca birkaç satırdır:

```glsl
#version 330 compatibility            // GLSL sürümü (her zaman ilk satır)

#define FRAGMENT_SHADER               // hangi aşama: vertex mi fragment mi
#define OVERWORLD                     // hangi boyut
#define GBUFFERS_TERRAIN              // aynı kaynağı paylaşan programlardan hangisi

#include "/program/gbuffers_solid.glsl"  // asıl kod
```

Asıl kod tek bir `.glsl` dosyasında hem vertex hem fragment bölümünü `#ifdef VERTEX_SHADER` / `#ifdef FRAGMENT_SHADER` ile içerir. **Sarmalayıcıları elle düzenlemeyin**; `tools/generate_wrappers.py` üretir.

---

## 3. Bir karenin çizim sırası

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 1. shadow            güneşten derinlik  +  voxelImg'e blokları yaz   │
 └──────────────────────────────────────────────────────────────────────┘
                                   │
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 2. gbuffers (opak)   skybasic, skytextured -> yıldız/ay (colortex0)  │
 │                      terrain, entities, block, hand                  │
 │                      -> albedo (0), normal+ışık haritası (1),        │
 │                         malzeme (2)                                  │
 └──────────────────────────────────────────────────────────────────────┘
                                   │
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 3. deferred          piksel başına 1 GI ışını -> colortex3           │
 │ 4. deferred1         yeniden projeksiyon + biriktirme -> colortex4/7 │
 │ 5. deferred2         gürültü giderme + güneş + blok ışığı + ışıma    │
 │                      + gökyüzü -> colortex0 (HDR), colortex6         │
 └──────────────────────────────────────────────────────────────────────┘
                                   │
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 6. gbuffers (saydam) water, hand_water, weather, (parçacıklar)       │
 │                      -> colortex0'a karışır, colortex5'e normal      │
 └──────────────────────────────────────────────────────────────────────┘
                                   │
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 7. composite         su emilimi + yansımalar + sis -> colortex0      │
 │ 8. final             bloom + pozlama + ton eşleme -> ekran           │
 └──────────────────────────────────────────────────────────────────────┘
```

**Önemli kavramlar**

- **Ertelenmiş aydınlatma:** Opak yüzeyler önce sadece "ne olduklarını" (renk, normal, malzeme) yazar. Işık tek seferde deferred2'de hesaplanır.
- **İleri (forward) çizim:** Parçacık, su ve yağmur gibi şeyler rengini kendi hesaplar. Ertelenmiş geçişlerin onlara dokunmaması için `colortex2`'ye malzeme `0` (`MAT_UNLIT`) yazarlar.
- **Flip (değiş tokuş):** Bir geçiş aynı dokuyu hem okuyup hem yazarsa (ör. deferred2'nin colortex0'ı), Iris iki kopya tutar ve otomatik değiştirir. Bu yüzden `colortex0` önce albedo, sonra aydınlatılmış sahne olabilir.

---

## 4. Doku (buffer) düzeni

Biçimler `lib/pipeline.glsl` içinde tanımlıdır.

| Doku | Biçim | Yazan | İçerik | Kareler arası |
|---|---|---|---|---|
| colortex0 | RGBA16F | gbuffers → deferred2 → composite | albedo (sRGB) → aydınlatılmış HDR sahne | temizlenir |
| colortex1 | RGBA16 | gbuffers_solid | rg: oktahedral normal, b: blok ışığı, a: gökyüzü ışığı | temizlenir |
| colortex2 | RGBA8 | gbuffers_solid / forward | r: malzeme, g: ışıma kimliği, b: pürüzsüzlük, a: F0 | temizlenir |
| colortex3 | RGBA16F | deferred | ham 1 örnekli GI | temizlenir |
| colortex4 | RGBA16F | deferred1 | rgb: biriktirilmiş GI, a: biriken kare sayısı | **korunur** |
| colortex5 | RGBA16 | gbuffers_water | rg: normal, b: tür (0.5 cam, 1 su), a: gökyüzü ışığı | temizlenir |
| colortex6 | RGBA8 | deferred2 | rgb: yansıma rengi (F0), a: pürüzsüzlük | temizlenir |
| colortex7 | R32F | deferred1 | önceki karenin doğrusal derinliği | **korunur** |
| voxelImg | RGBA8 3D | shadow | rgb: blok rengi, a: voxel kodu | her kare temizlenir |
| shapeImg | R32UI 3D | shadow | blok sınır kutusu bit maskesi (VOXEL_SHAPES) | her kare temizlenir |
| lightImg | RGBA16F 2D | shadow | ışık kaynağı listesi: satır 0 konum, satır 1 renk | her kare temizlenir |
| lightCountImg | R32UI 2D | shadow | listedeki ışık sayısı (atomik sayaç) | her kare temizlenir |

### Malzeme kimlikleri (`colortex2.r × 255`)

| Değer | Sabit | Anlam |
|---|---|---|
| 0 | `MAT_UNLIT` | Zaten aydınlatılmış, dokunma (parçacık, çizgi, End portalı) |
| 1 | `MAT_LIT` | Normal katı yüzey |
| 2 | `MAT_PLANT` | Bitki: normal yukarı kabul edilir |
| 3 | `MAT_LEAVES` | Yaprak: ışık geçirgen |
| 4 | `MAT_EMISSIVE` | Işık yayan yüzey |
| 5 | `MAT_HAND` | Birinci şahıs el: ışın izlenmez |

### Işıma kimliği (`colortex2.g × 255`)

| Değer | Anlam |
|---|---|
| 0 | ışıma yok |
| 1–8 | `block.properties` ışık kategorisi (renk `emissionColor()` fonksiyonundan) |
| 9 | doku renginde ışıma (`tintedEmission()`, renkli mumlar) |
| 16–255 | LabPBR ışıma gücü: `(değer − 16) / 239` |

---

## 5. Voxel sistemi ve blok şekilleri

### Voxelleştirme (`program/shadow.glsl`)

`shaders.properties` içindeki `shadow.culling = reversed` ayarı, Iris'e `voxelDistance` içindeki **tüm** chunk'ları gölge geçişinde çizmesini söyler. Gölge vertex shader'ı her köşe için şunu yapar:

```glsl
// at_midBlock: köşeden blok merkezine uzaklık (1/64 blok). Iris kaynağında:
//   computeMidBlock = blokKonumu + 0.5 - köşeKonumu
vec3 modelCenter  = gl_Vertex.xyz + at_midBlock.xyz / 64.0;     // bloğun merkezi (model uzayı)
vec3 viewCenter   = mat3(gl_ModelViewMatrix) * modelCenter + gl_ModelViewMatrix[3].xyz;
vec3 playerCenter = mat3(shadowModelViewInverse) * viewCenter + shadowModelViewInverse[3].xyz;

// Hücre = floor(dünyaKonumu) - floor(kamera) + boyut/2
ivec3 cell = ivec3(floor(playerCenter + fract(cameraPosition))) + VOXEL_VOLUME / 2;

imageStore(voxelImg, cell, vec4(ortalamaRenk, kod / 255.0));
```

- **Ortalama renk:** Doku atlasından `mc_midTexCoord` noktasında mipmap seviyesi 4 okunarak bulunur.
- **Işık seviyesi:** `at_midBlock.w` ile gelir (Iris `BLOCK_EMISSION_ATTRIBUTE` özelliği).

### Voxel kodları (`voxelImg.a × 255`)

| Kod | Anlam |
|---|---|
| 0 | boş |
| 1 | katı |
| 2 | yaprak |
| 3 | cilalı |
| 4 | metal |
| 5 | ışık geçiren: rgb = kanal başına geçirgenlik (renkli cam, delikli blok) |
| 11–18 | listelenmiş ışık kaynağı, kategori 1–8 (sabit renk) |
| 19 | ışığı kendi doku renginde yayan (kategori 9, renkli mumlar) |
| 20 | ayarla açılan ışık kaynakları (kategori 10: beton, yün, mineral) |
| 21–35 | otomatik algılanan ışık kaynağı, ışık seviyesi 1–15 |

> Kod 21'den itibarası otomatik algılanan ışıklara ayrılmıştır. Yeni bir sabit
> renk kategorisi eklemek için o aralığı kaydırmanız gerekir.

### Blok şekilleri (VOXEL_SHAPES)

Her blok tam küp değildir. Meşale ince bir direk, halı yassı bir levhadır. Şekil bilgisi
ikinci bir 3D görüntüde (`shapeImg`) **bit maskesi** olarak saklanır:

```
bit  0-15 : Y ekseni, 16 dilim   (yarım blok, halı, kar katmanı için hassasiyet)
bit 16-23 : X ekseni,  8 dilim
bit 24-31 : Z ekseni,  8 dilim
```

Gölge geçişinde her köşe, blok içindeki konumuna denk gelen dilimin bitini
`imageAtomicOr` ile işaretler. Bloğun tüm köşeleri aynı hücreye OR'landığı için
sonuçta en düşük ve en yüksek işaretli bitler **sınır kutusunu (AABB)** verir.

`imageAtomicOr` kullanılmasının sebebi, OR işleminin bitler üzerinde bağımsız
çalışmasıdır; `imageAtomicMax` ile paketlenmiş alanlar birbirini ezerdi.

**Özel durum:** Minecraft görünmeyen yüzleri çizmez. Zemine gömülü bir bloğun
yalnızca üst yüzü çizilirse o eksende tek bit işaretlenir ve kalınlık bilinemez.
Bu durumda eksen tüm hücreye genişletilir, aksi halde blok yassı bir düzleme
dönüşür ve içinden ışık sızardı.

Kutular gerçek şekilden daima **biraz büyük** çıkar (en fazla 1/16 blok), bu da
geometriden ışık sızmasını önler.

Işın izleyici, dolu bir hücreye girdiğinde hücre sınırı yerine bu kutuyla
kesişim testi yapar (slab yöntemi). Kutuyu ıskalarsa yoluna devam eder; meşalenin
yanından geçen ışık artık engellenmez.

**Küçük ışık kaynağı telafisi:** Meşale küçüldükçe ışınlar ona daha az çarpar ve
sönük görünür. `EMISSION_SHAPE_BOOST`, kutunun ortalama kesit alanına göre
(tam küpte 3.0 olan `ex·ey + ey·ez + ez·ex` değeri) parlaklığı telafi eder.

### Voxelleştirilmeyen bloklar

| Grup | Davranış |
|---|---|
| `ID_WATER`, `ID_TRANSLUCENT`, `ID_PLANT`, `ID_END_PORTAL` | Hiç voxelleştirilmez |
| `ID_NONSOLID` (1003) | Hiç voxelleştirilmez. Çit, parmaklık, zincir gibi **kafes şekilliler**: sınır kutuları gerçek şekillerinden çok büyük olurdu |
| `ID_SHAPED` (1004) | **Yalnızca `VOXEL_SHAPES` açıkken.** Kapı, kapak, örs, halı, ray gibi kutu şekilliler. Şekiller kapalıyken tam küp olarak çirkin görüneceği için atlanırlar |
| `ID_LEAVES` | `VOXELIZE_LEAVES` kapalıysa atlanır |

Çoğu şeffaf katmanlar da atlanır: ortalama alfa 0.35'in altındaysa yazılmaz. Örneğin çim bloğunun yan katmanı bu yüzden bloğun rengini bozmaz.

**Saydam ışık kaynakları:** Nether portalı saydam katmanda çizildiği için normalde
voxelleştirilmezdi. `VOXELIZE_TRANSLUCENT_EMITTERS` açıkken o katmandaki ışık
kaynakları da ızgaraya girer ve kendi renginde ışık yayar.

### Boyut değiştirmek

İki yer **birlikte** değişmelidir:

1. `shaders.properties` → `image.voxelImg = ... X Y Z`
2. `lib/voxel.glsl` → `VOXEL_VOLUME`

Ayrıca `lib/settings.glsl` içindeki `voxelDistance` en az yatay boyutun yarısı + 8 olmalıdır.

---

## 6. Işın izlemeli GI

### DDA ışın izleyici (`lib/voxel.glsl → traceVoxels`)

Amanatides & Woo algoritması ışını her adımda **tam olarak bir sonraki bloğa** ilerletir, hiçbir bloğu atlamaz ve maliyeti geçilen blok sayısıyla orantılıdır:

```glsl
vec3 tDelta = abs(1.0 / dir);                      // bir blok geçmek için gereken mesafe
vec3 tMax   = (hücre + max(işaret, 0) - başlangıç) / dir;  // her eksende ilk sınıra mesafe
for (...) {
    vec3 mask = en küçük tMax ekseni;              // hangi yüzden çıkıyoruz?
    tMax += mask * tDelta;                         // o eksende bir sonraki sınır
    hücre += mask * işaret;                        // komşu hücreye geç
    if (voxel dolu) return isabet;                 // normal = -mask * işaret
}
```

Başlangıç hücresi atlanır, böylece yüzeyin kendi bloğuna çarpılmaz.

### Bir pikselin GI'sı (`program/deferred.glsl`)

1. Yüzey normali etrafında **kosinüs ağırlıklı** rastgele bir yön seçilir. Bu dağılımda örneğin ortalaması doğrudan "gelen ışık" olur, ayrıca `cos` ile çarpmaya gerek kalmaz.
2. Işın izlenir:
   - **İsabet:** blok rengi × (güneş × gölge haritası + ortam) + ışıma.
   - **Iskalama:** gökyüzü rengi × `GI_SKY_STRENGTH`.
3. Sonuç `GI_FIREFLY_CLAMP` ile sınırlanır.

### Çok sekmeli yol izleme (GI_BOUNCES)

Tek sekme yalnızca ışının **doğrudan çarptığı** yüzeylerden ışık taşır. Rengin
odaya yayılması için ışığın en az bir kez daha sekmesi gerekir:

```glsl
vec3 radiance = 0, throughput = 1;
for (bounce = 0; bounce < GI_BOUNCES; bounce++) {
    if (çarptı) {
        throughput *= tint;                 // yolda renkli cam varsa
        radiance   += throughput * (ışıma + güneş * albedo);
        throughput *= albedo;               // kosinüs örneklemede difüz çarpan = albedo
        ışın = yeni kosinüs yönü;           // sonraki sekme
    } else {
        radiance += throughput * gökyüzü;
        break;
    }
}
```

`throughput` çarpanı her sekmede çarpılan yüzeyin rengiyle çarpıldığı için,
turuncu bir tavandan seken güneş ışığı odaya **turuncu** gelir. Sonraki sekmeler
daha az önemli olduğundan yarı adım sayısıyla izlenir.

`GI_HIT_AMBIENT` yalnızca **son** sekmede eklenir; daha ileri sekmeleri taklit
eden kaba bir yaklaşımdır ve erken sekmelerde eklenirse ışık iki kez sayılır.

`GI_SATURATION` sonuçtaki rengi griden uzaklaştırarak renk taşımasını belirginleştirir.

### Gürültüyü azaltma

| Aşama | Dosya | Yöntem |
|---|---|---|
| Zamansal | deferred1 | Pikselin dünya konumu önceki karenin matrisleriyle ekrana yansıtılır. Derinliği tutan komşulardan geçmiş okunur ve `1/kareSayısı` ağırlıkla karıştırılır. |
| Uzamsal | deferred2 | 12 noktalı döndürülmüş Poisson diski. Normal benzerliği (`GI_DENOISE_NORMAL_WEIGHT`) ve aynı düzlemde olma ağırlığıyla karıştırılır. Geçmiş dolunca yarıçap küçülür. |

### Sızıntı önleme (`LEAK_FIX`)

Gölge haritası derin mağaraları bilemez. Bu yüzden gökyüzü ve güneş katkısı, yüzeyin vanilla gökyüzü ışık haritasıyla (`lmSky`) çarpılır:

- `sunExposureFromLightmap()`
- `skyExposureFromLightmap()`

---

## 6.5 Doğrudan ışık örnekleme (RT_LIGHTS)

**Neden gerekli?** GI ışınları yüzeyden rastgele yönlere gönderilir. Bir meşale
bir bloğun yalnızca küçük bir parçasını kaplar, bu yüzden rastgele bir ışının ona
çarpma olasılığı çok düşüktür. Sonuç: meşale ışığı ya hiç görünmez ya da aşırı
gürültülü olur. Bu yüzden blok ışığı eskiden vanilla ışık haritasından geliyordu
ve **hiç gölge oluşturmuyordu** — kapağın deliklerinden ışık sızmamasının sebebi buydu.

**Çözüm:** Işığın ışını bulmasını beklemek yerine, ışını doğrudan ışığa göndeririz.

1. **Liste oluşturma** (gölge geçişi): Bir blok voxelleştirilirken, hücreyi ilk
   sahiplenen köşe bloğu ışık listesine ekler. Sahiplenme, şekil maskesine yazan
   `imageAtomicOr`'un döndürdüğü eski değerin 0 olmasıyla anlaşılır; böylece bir
   blok 24 köşesi olmasına rağmen listeye bir kez girer.
2. **Aday seçme** (deferred): Listeden `RT_LIGHT_SAMPLES` kadar rastgele aday
   çekilir, her birinin gölgesiz katkısı ağırlık olarak hesaplanır ve ağırlıkla
   orantılı olarak bir tanesi seçilir (ağırlıklı rezervuar örnekleme / RIS).
3. **Gölge ışını**: Seçilen kaynağa `traceTransmittance()` ile tek bir ışın
   gönderilir. Yol kapalıysa `vec3(0)`, renkli camdan geçiyorsa camın rengi döner.
4. **Ölçekleme**: Sonuç `toplam ağırlık / aday sayısı` ile çarpılır. Bu, tahmin
   ediciyi sapmasız yapar: kaç aday çekilirse çekilsin ortalama sonuç doğru kalır.

Işık kaynağı voxelleri gölge ışınını engellemez, yoksa kaynak kendi ışığını keserdi.

Örnekleme hem birincil yüzeyde hem de ilk sekme noktasında yapılır; böylece meşale
ışığı duvarlardan sekerek ortama renk verir. Maliyeti sınırlamak için sonraki
sekmelerde tekrarlanmaz.

**Sınır:** Liste `MAX_RT_LIGHTS` (varsayılan 1024) kaynakla sınırlıdır ve bu değer
`shaders.properties` içindeki `image.lightImg` genişliğiyle aynı olmalıdır.
`tools/check_consistency.py` bunu denetler.

---

## 6.6 Delikli blokların gölgesi (CUTOUT_SHADOW_MASK)

Kapak, kapı ve parmaklık gibi blokların delikleri **dokudadır, geometride değildir**.
Voxel ızgarası blok başına tek bir kutu ve tek bir geçirgenlik sakladığı için bu
desen kaybolur ve blok düzgün yarı saydam bir levhaya dönüşür: ışık her yerinden
eşit sızar, gölgede delik deseni görünmez.

Çözüm, deliklerin blok içindeki yerini kaydetmektir:

1. **İşaretleme** (gölge geçişi, fragment aşaması): Dokunun saydam olan her pikseli,
   bloğun içindeki **8x8'lik ızgarada** kendi yerine denk gelen "delik" bitini
   `imageAtomicOr` ile işaretler. Izgaranın iki ekseni, yüzün baktığı eksen dışındaki
   eksenlerdir. İşaretleme doğrudan dünya uzayında yapılır, bu yüzden dokunun
   yönünü tahmin etmek gerekmez.
2. **Kullanma** (gölge ışını): Işın böyle bir voxelden geçerken levhanın orta
   düzlemini kestiği noktayı bulur ve o noktanın bitine bakar. Delikse ışık hiç
   zayıflamadan geçer, doluysa kesilir.

64 bit iki ayrı `r32ui` görüntüde saklanır; `imageAtomic*` yalnızca tek kanallı
formatlarda çalıştığı için tek bir RG32UI görüntü kullanılamaz.

**Neden güvenli:** Yalnızca DELİKLER işaretlenir. Bir bloğa hiç fragment gelmezse
(çok uzaksa veya gölge haritasında görünmüyorsa) maske boş kalır ve blok dolu
sayılır; yani en kötü ihtimalle eski davranışa dönülür, fazladan ışık sızmaz.

**Sınır:** Izgara 8x8'dir, doku ise 16x16. Bu yüzden desen yarı çözünürlükte, biraz
iri taneli düşer. Ayrıca gölge haritasında hiç görünmeyen blokların deliklerini
kaydedemeyiz.

---

## 7. Yansımalar, su ve kırılma

`program/composite.glsl → traceReflection()` sırasıyla dener:

1. **Voxel ışını.** İsabet noktası ekranda görünüyorsa ve derinlik tutuyorsa gerçek dokulu pikseli kullanır (`REFLECTION_SCREEN_LOOKUP`). Tutmuyorsa voxelin düz rengini aydınlatır.
2. **Ekran uzayı araması** (`SSR_FALLBACK`). Canlılar, bitkiler ve voxel menzili dışındaki arazi için.
3. **Gökyüzü** × gökyüzü ışık haritası.

Yansıma gücü Schlick Fresnel ile hesaplanır: `F0 + (1 − F0)(1 − cosθ)⁵`.

Metallerde ışıma dışı dağınık renk deferred2'de sıfırlanır; metalin rengi yansımanın F0 (albedo) ile çarpılmasından gelir.

### Su

Suyun su gibi görünmesini sağlayan dört etki `composite` geçişinde uygulanır:

| Etki | Nasıl çalışır |
|---|---|
| **Kırılma** (`WATER_REFRACTION`) | Işık yüzeyde yön değiştirir. Kırılan ışının hedeflediği nokta ekrana geri yansıtılır ve arka plan oradan örneklenir. Dalgalar normali oynattığı için zemin de oynar. Örneklenen pikselin gerçekten yüzeyin arkasında olup olmadığı kontrol edilir, yoksa su kenarlarında kıyıdaki pikseller içeri sızar |
| **Emilim** | `exp(-katsayı · kalınlık)`. Kırmızı en hızlı yutulduğu için derin su maviye kayar. Kalınlık, yüzey ile arkasındaki opak yüzey arasındaki mesafedir |
| **Saçılma** | Suyun kendi mavi yeşil rengi, emilen ışığın yerine eklenir |
| **Işık desenleri** (`WATER_CAUSTICS`) | İki kayan gürültü katmanının farkının sıfıra yaklaştığı yerlerde parlak çizgiler oluşur. Su altındaki yüzeylere ve kamera su altındayken her şeye uygulanır |

Su altı sisi `UNDERWATER_BIOME_TINT` açıkken `fogColor` uniformunu kullanır; bu
değer biyomun su rengidir, böylece bataklık ile sıcak okyanus farklı görünür.

Aynı kırılma tekniği `GLASS_REFRACTION` ile cam ve buza da uygulanır.

---

## 7b. Renkli ışık geçişi

Işığın renkli camdan geçerken renklenmesi iki ayrı yoldan sağlanır, çünkü güneş
ışığı gölge haritasıyla, blok ışıkları ise ışın izlemeyle hesaplanır.

### Güneş: renkli gölgeler (`COLORED_SHADOWS`)

Iris iki gölge derinliği tutar:

| Doku | İçerik |
|---|---|
| `shadowtex0` | **tüm** engeller (saydamlar dahil) |
| `shadowtex1` | yalnızca **opak** engeller (saydamlar çizilmeden önce kopyalanır) |
| `shadowcolor0` | gölge geçişinin yazdığı renk |

Bir nokta `shadowtex1`'e göre aydınlık ama `shadowtex0`'a göre gölgedeyse, arada
yalnızca saydam bir blok vardır. O zaman ışık `shadowcolor0`'daki renkle çarpılır.

Gölge geçişinin fragment shader'ı saydam blokların rengini alfa = 1 ile yazar;
opak bloklar alfa = 0 yazar, böylece yanlışlıkla renk olarak okunmazlar.

Renk her PCF örneği için değil, tek bir merkez örneğinde okunur: 12 kat daha az
doku okuması yapar ve görsel fark edilmez.

### Blok ışıkları: geçirgen voxeller (`GLASS_TRANSMISSION`)

Renkli cam, voxel ızgarasına **kod 5** ile yazılır ve rgb kanalları o blokta
kanal başına ne kadar ışık geçtiğini tutar. Işın izleyici böyle bir voxele
çarptığında durmaz:

```glsl
if (code == VOXEL_TRANSMISSIVE) {
    transmittance *= v.rgb;   // kırmızı cam yeşil ve maviyi yutar
    continue;                 // ışın yoluna devam eder
}
```

`transmittance` çağırana döndürülür ve yol izleyicideki `throughput` ile
çarpılır. Aynı mekanizma yansımalarda da çalışır.

### Delikli bloklar (`TRANSMISSION_FROM_ALPHA`)

Kapak ve parmaklık gibi bloklarda dokunun boş kısmı kadar ışık geçirilir:
`geçirgenlik = 1 − ortalamaAlfa`. Blok yine kutu şeklindedir, yani kutunun
yanından geçen ışık hiç engellenmez, kutudan geçen ışık ise kısmen geçer.

> **Sınır:** Bu yöntem deliklerin **şeklini** taşımaz. Güneş gölgesi gölge
> haritasında gerçek doku ile çizildiği için delik şeklinde düşer; blok ışıkları
> ise voxel kutusuna baktığından gölge şekilli değil **yumuşak** olur.
> Delik şekilli blok ışığı gölgesi için her isabet noktasında doku atlasından
> alfa örneklemek gerekir; bu da her voxel için atlas koordinatlarını saklamayı
> gerektirir ve şu an uygulanmamıştır.

## 8. Koordinat uzayları

| Uzay | Tanım | Dönüşüm |
|---|---|---|
| screen | uv [0,1] + derinlik [0,1] | `screenToView`, `viewToScreen` |
| view | kamera merkezli, bakış yönü −Z | `viewToPlayer`, `playerToView` |
| player | kamera merkezli, dünya eksenlerine hizalı. `dünya = player + cameraPosition` | çoğu hesap burada |
| voxel | voxel dokusu indeksleri | `playerToVoxel`, `voxelToPlayer` |
| shadow clip | gölge kamerası, bozulma uygulanmış | `playerToShadowClip`, `distortShadowClip` |

Eksenler: **+X doğu, +Y yukarı, +Z güney.**

---

## 9. Ayar ekleme

Örnek olarak GI rengini doygunlaştıran yeni bir kaydırıcı ekleyelim.

**Adım 1 — `lib/settings.glsl`** (uygun bölüme):

```glsl
// Sayısal ayar: ad, varsayılan, // [izin verilen değerler] açıklama
// Varsayılan (1.0) listede OLMALI, değerler TEK boşlukla ayrılmalı.
#define GI_SATURATION 1.0 // [0.0 0.5 1.0 1.5 2.0] GI renginin doygunluğu
```

Açık/kapalı bir ayar olsaydı:

```glsl
#define YENI_OZELLIK        // açık
//#define YENI_OZELLIK      // kapalı
```

Ayrıca aynı dosyanın **en altındaki kayıt bloğuna** eklenmelidir, yoksa Iris menüde göstermez:

```glsl
#ifdef YENI_OZELLIK
#endif
```

**Adım 2 — Kodda kullanın** (ör. `program/deferred2.glsl`):

```glsl
// Ondalıklı ayarlar #if içinde KULLANILAMAZ (önişlemci tamsayı anlar),
// normal GLSL kodunda kullanın; derleyici sabit olduğu için yine optimize eder.
indirect = mix(vec3(luminance(indirect)), indirect, GI_SATURATION);
```

**Adım 3 — `shaders.properties`:** ayarı bir sayfaya ekleyin. Kaydırıcı olacaksa `sliders` satırına da yazın.

```properties
screen.RAY_TRACING = GI_ENABLED VOXEL_RANGE ... GI_SATURATION
sliders = ... GI_SATURATION
```

**Adım 4 — `lang/tr_tr.lang` ve `lang/en_us.lang`:**

```properties
option.GI_SATURATION=GI Doygunluğu
option.GI_SATURATION.comment=Dolaylı ışığın renk yoğunluğu. 0 gri, 1 normal
```

Açıklamada her `". "` (nokta + boşluk) yeni bir satır başlatır. Bir değere isim vermek için `value.GI_SATURATION.0.0=Gri`, birim eklemek için `suffix.AYAR=\ blok` yazın. Baştaki boşluğu korumak için ters eğik çizgi gerekir.

**Adım 5 — Denetleyin:**

```
python tools/check_consistency.py
python tools/validate_glsl.py
```

---

## 10. Hakkında bölümü ve adınız

Hakkında sayfasındaki satırlar değer taşımayan "sahte" ayarlardır. Kodda yalnızca menüde görünsün diye tanımlıdır:

```glsl
#define ABOUT_AUTHOR 0 // [0]
```

Görünen yazının tamamı dil dosyalarındadır. **Adınızı eklemek için** `shaders/lang/tr_tr.lang` ve `shaders/lang/en_us.lang` dosyalarında şu satırları düzenleyin:

```properties
option.ABOUT_AUTHOR=Yapımcı: §eAdınız Soyadınız
option.ABOUT_AUTHOR.comment=Buraya kendinizle ilgili kısa bir açıklama yazın. Her cümle ayrı satırda görünür
option.ABOUT_CONTACT=İletişim: §bdiscord_adiniz
option.ABOUT_WEBSITE=Web sitesi: §bmodrinth.com/shader/raybound-rt
option.ABOUT_LICENSE=Lisans: §7Tüm Hakları Saklıdır
option.ABOUT_VERSION=Sürüm: §f1.1
```

Renk kodları: `§e` sarı, `§a` yeşil, `§b` camgöbeği, `§c` kırmızı, `§d` pembe, `§6` altın, `§7` gri, `§f` beyaz, `§l` kalın, `§r` sıfırla.

Dosyayı **UTF-8** olarak kaydedin, yoksa Türkçe karakterler bozulur.

Yeni bir bilgi satırı eklemek için:

1. `settings.glsl` dosyasına `#define ABOUT_YENI 0 // [0]` ekleyin.
2. `shaders.properties` içinde `screen.ABOUT` satırına `ABOUT_YENI` yazın.
3. Dil dosyalarına `option.ABOUT_YENI=...`, `option.ABOUT_YENI.comment=...` ve `value.ABOUT_YENI.0=` (boş) ekleyin.

---

## 11. Hata ayıklama görünümleri

**Ayarlar → Hata Ayıklama → Görünüm.** Her görünüm verinin hesaplandığı geçişte üretilir (`lib/debug.glsl`).

| # | Görünüm | Geçiş | Ne gösterir | Neye bakmalı |
|---|---|---|---|---|
| 1 | Albedo | deferred2 | Işıksız doku rengi | Siyah/pembe alan = doku okunamıyor |
| 2 | Normaller | final | Yüzey yönü (R doğu, G yukarı, B güney) | Düz yüzeyde renk değişimi = hatalı normal |
| 3 | Işık haritası | final | R blok ışığı, B gökyüzü ışığı | Derin mağara siyah olmalı |
| 4 | Malzeme kimliği | final | Gri katı, açık yeşil bitki, koyu yeşil yaprak, sarı ışık, pembe el, siyah aydınlatılmayan | Yanlış renk = block.properties grubu yanlış |
| 5 | Pürüzsüzlük / metal | final | R pürüzsüzlük, G F0, B metal | Cilalı bloklar kırmızı olmalı |
| 6 | Işıma kategorisi | final | Kategori rengi, beyaz tonlar LabPBR | Işık kaynağı rengi doğru mu |
| 7 | Derinlik | final | Yakın koyu, uzak açık, gökyüzü lacivert | Derinlik okuması çalışıyor mu |
| 8 | GI ham | final | Tek ışının sonucu (gürültülü) | Tamamen siyah = voxel ızgarası boş → 15'e bakın |
| 9 | GI biriktirilmiş | final | Kareler arası ortalama | Hareketle iz = toleransı düşürün |
| 10 | GI gürültüsüz | deferred2 | Aydınlatmada kullanılan dolaylı ışık | Son GI kalitesi |
| 11 | GI geçmiş uzunluğu | final | Kırmızı sıfırlandı → yeşil birikti | Kamera dururken kırmızı = biriktirme bozuk |
| 12 | Doğrudan ışık | deferred2 | Güneş/ay + parlama | Güneş yönü ve rengi |
| 13 | Gölge | deferred2 | Beyaz aydınlık, siyah gölge | Çizgili desen = Gölge Kaymasını artırın |
| 14 | Blok ışığı | deferred2 | Vanilla ışık haritası + el ışığı | Blok ışığı rengi/eğrisi |
| 15 | Voxel dünyası | final | Kameradan voxel ızgarasına ışın, blok renkleri | Eksik blok = voxelleştirilmemiş |
| 16 | Voxel tipleri | final | Gri katı, yeşil yaprak, camgöbeği cilalı, altın metal, ışık rengi, pembe otomatik | Voxel kodları doğru mu |
| 17 | Voxel menzili | final | Yeşil içeride, sarı geçiş, kırmızı dışarıda | Işın izleme alanının sınırı |
| 18 | Yansımalar | composite | Yalnızca yansıma katkısı | Yansıma kaynağı ve gücü |
| 19 | Saydam yüzeyler | final | Su (mavi tonlu) ve cam normalleri | Dalga normalleri, su algılama |
| 20 | Işıma | deferred2 | Yüzeylerin kendi ışığı | Parlayan kısımlar doğru mu |
| 21 | Voxel şekilleri | final | Gri tam küp, sarıdan kırmızıya küçülen şekiller | Bir bloğun şekli doğru ölçülmüş mü |
| 22 | Blok ışıkları (RT) | deferred2 | Güneş hariç, yalnızca ışın izlemeli blok ışığı | Kaynak listeye girmiş mi, gölgeleri doğru mu |

**Araçlar**

| Araç | Ne işe yarar |
|---|---|
| Bölünmüş Ekran | Sol yarı hata ayıklama, sağ yarı normal görüntü. |
| Bozuk Pikselleri Göster | NaN/sonsuz değerli pikselleri pembe yapar. Kaynağı genelde sıfıra bölme veya negatif tabanlı `pow`'dur. GI geçmişine giren NaN yayılır. |
| Gölge Haritası Önizleme | Sol alt köşede gölge haritasını gösterir. |
| Gürültüyü Dondur | GI ışın yönlerini sabitler, ayarlar titremeden karşılaştırılır. Normal oyunda kapalı tutun. |

---

## 12. Blok ve ışık kategorisi ekleme

> `block.properties` artık `tools/generate_blocks.py` tarafından üretilir.
> Kalıcı değişiklikler için o betiği düzenleyip çalıştırın; betik aynı bloğun
> iki gruba yazılmasını da engeller.

### Doğru grubu seçmek

| Blok nasıl görünüyor? | Grup |
|---|---|
| Tam küp | listeye eklemeyin, varsayılan davranış |
| Kutu ama küp değil (kapı, örs, halı, ray) | `1004` — şekli otomatik ölçülür |
| Kafes/çapraz (çit, parmaklık, zincir) | `1003` — hiç voxelleştirilmez |
| Bitki | `1002` |
| Işık yayan, rengi sabit | `3000`–`3007` |
| Işık yayan, rengi kendi dokusundan gelsin | `3008` |
| Ayarla ışık kaynağına çevrilebilsin | `2100`–`2103` (beton tozu, beton, yün, mineral) |

### Mevcut gruba blok eklemek

`shaders/block.properties` içinde uygun satıra blok adını ekleyin:

```properties
# Modlu bir lambayı ateş rengi ışık kaynağı yapmak:
block.3000 = torch wall_torch lantern ... benimmod:kristal_lamba
```

Durum belirtmek için `blok:ozellik=deger` yazın, örneğin `redstone_lamp:lit=true`. Bir blok yalnızca bir grupta olmalıdır.

### Yeni ışık rengi kategorisi (ör. pembe)

1. **`block.properties`** — yeni grup:
   ```properties
   block.3008 = benimmod:pembe_lamba
   ```
2. **`lib/materials.glsl`**
   - `ID_EMIT_LAST` değerini `3009` yapın (3008 doku renginde yayanlara ayrılmıştır).
   - `emissionColor()` fonksiyonuna şu satırı ekleyin:
     ```glsl
     if (category == 9) return vec3(EMIT_PINK_R, EMIT_PINK_G, EMIT_PINK_B) * EMIT_PINK_I; // pembe
     ```
   - Voxel kodu `11 + kategori - 1` olur. **Kod 20'yi geçmeyin**: otomatik algılanan
     ışıklar 21'den başlar. Kategori 9 (kod 19) doku renginde yayanlara ayrılmıştır,
     bu yüzden 10. bir sabit renk kategorisi için önce `voxelEmission()` içindeki
     21–35 aralığını kaydırmanız gerekir.
3. **`lib/debug.glsl`** — `debugVoxelTypeColor()` içindeki kod aralıklarını güncelleyin.
4. **`lib/settings.glsl`** — `EMIT_PINK_R`, `EMIT_PINK_G`, `EMIT_PINK_B`, `EMIT_PINK_I` ayarlarını mevcut `EMIT_` satırlarını kopyalayarak ekleyin.
5. **Menü ve dil dosyaları** — ayarları `screen.EMISSION_COLORS` ve `sliders` satırlarına, isimlerini dil dosyalarına ekleyin.
6. **Denetleyin** — `tools/check_consistency.py` ile kontrol edin.

---

## 13. Yeni hata ayıklama görünümü ekleme

1. **`lib/debug.glsl`** — `const int DBG_YENI = 21;` ekleyin.
2. **`lib/settings.glsl`** — `DEBUG_VIEW` değer listesinin sonuna `21` ekleyin.
3. **Görünümü üretin.** Veri final'de hâlâ okunabiliyorsa `program/final.glsl → finalDebugView()` içine ekleyin:
   ```glsl
   if (view == DBG_YENI) {
       // Örnek: colortex6'daki yansıma rengini göster
       return texelFetch(colortex6, px, 0).rgb;
   }
   ```
   Veri yalnızca bir ara geçişte varsa, o geçişte `debugActive(texcoord)` kontrolüyle colortex0'a yazın. Ayrıca `isDeferredDebugView()` veya `isCompositeDebugView()` listesine ekleyin; HDR ise `isHdrDebugView()` listesine de ekleyin.
4. **Dil dosyaları** — `value.DEBUG_VIEW.21=21 Yeni görünüm` ekleyin ve ilgili `DEBUG_HELP_` açıklamasını güncelleyin.

---

## 14. Yeni program ekleme

Örnek: bulutlar için ayrı bir `gbuffers_clouds` programı.

1. `shaders/program/gbuffers_clouds.glsl` dosyasını `#ifdef VERTEX_SHADER` / `#ifdef FRAGMENT_SHADER` bölümleriyle yazın.
2. `tools/generate_wrappers.py` içindeki `PROGRAMS` sözlüğüne bir satır ekleyin:
   ```python
   "gbuffers_clouds": ("gbuffers_clouds", [], "330 compatibility"),
   ```
3. Sarmalayıcıları üretin: `python tools/generate_wrappers.py`
4. Programın çizdiği yere göre `shaders.properties` içine `blend.gbuffers_clouds.colortexN = off` satırları gerekebilir.

**Iris program geri dönüşleri.** Bir program yoksa Iris zincirdeki bir sonrakini kullanır:

```
terrain → textured_lit → textured → basic
water → terrain
clouds → textured
entities_glowing → entities
hand_water → hand
```

---

## 15. Araçlar

| Betik | Ne yapar | Ne zaman |
|---|---|---|
| `tools/generate_wrappers.py` | world klasörlerindeki 132 sarmalayıcıyı üretir | Program ekleyince veya GLSL sürümü değişince |
| `tools/generate_blocks.py` | `block.properties` dosyasını üretir, çift kayıtları engeller | Blok grubu değiştirince |
| `tools/check_consistency.py` | Ayarlar, menü, dil dosyaları, blok kimlikleri ve voxel boyutlarını karşılaştırır | Ayar, blok veya dil dosyası değişince |
| `tools/validate_glsl.py` | Tüm programları glslangValidator ile derler; Iris makrolarını ve Sodium'un eklediği fonksiyonları taklit eder | Her kod değişikliğinden sonra |

**Gereksinimler**

- Python 3
- `glslangValidator`
  - Windows'ta Vulkan SDK ile gelir
  - Linux'ta `sudo apt install glslang-tools`

**Oyun içi hızlı döngü**

1. Shader dosyasını düzenleyip kaydedin.
2. Oyunda **R** tuşuna basın (Iris "shader'ları yeniden yükle" kısayolu). **O** shader menüsünü açar, **K** shader'ları açıp kapatır.
3. Derleme hatası olursa Iris sohbet ekranında gösterir. Ayrıntılar `.minecraft/logs/latest.log` dosyasındadır.

Iris ayarlarında "Debug" seçeneği açıksa hatalı kaynak kodu `.minecraft/patched_shaders/` klasörüne yazılır. Hata mesajındaki satır numarası bu dosyalara göredir.

---

## 16. Sık karşılaşılan hatalar

| Belirti | Neden | Çözüm |
|---|---|---|
| `function "X" is already defined` | Iris, Sodium arazi shader'larına kendi fonksiyonlarını ekler (`signNotZero`, `decodeOct24`...) | Genel isimli fonksiyonlara `rb_` öneki verin. `validate_glsl.py` bunu yakalar. |
| Ayar menüde görünmüyor | Açık/kapalı ayar `#ifdef` ile kullanılmıyor; veya değer listesi hatalı | settings.glsl sonundaki kayıt bloğuna ekleyin. `check_consistency.py` çalıştırın. |
| Garip derleme hatası, satır anlamsız | Yorum içinde `*/` geçiyor (ör. `world*/`), blok yorum erken kapanıyor | Yorumlarda `*/` yazmayın |
| `#if AYAR > 0.5` çalışmıyor | Önişlemci ondalık sayı anlamaz | Normal GLSL `if` kullanın |
| Ekranda pembe noktalar, zamanla yayılıyor | NaN değeri (sıfıra bölme, `pow` negatif taban, `normalize(vec3(0))`) | "Bozuk Pikselleri Göster" ile yerini bulun. `pow` tabanını `saturate`/`max` ile koruyun. |
| Mağaralar aydınlık | Işık sızıntısı | `LEAK_FIX` açık mı, görünüm 3'te mağara siyah mı kontrol edin |
| GI tamamen siyah | Voxel ızgarası boş | Görünüm 15'e bakın. Iris sürümü eski olabilir veya `shadow.culling` desteklenmiyor olabilir. |
| Işık kaynağı ışık vermiyor | Blok listede yok veya yanlış grupta | Görünüm 16'da voxel rengi, görünüm 4'te malzeme kontrolü |
| Işın izleme alanı kenarında ani değişim | Menzil sınırı | Görünüm 17 ile alanı görün; `VOXEL_RANGE` büyütün |
| Yansımada bloklar düz renkli görünüyor | Voxeller dokusuzdur, isabet noktası ekran dışında | Normaldir; ekranda görünen isabetler dokulu olur |
| Türkçe karakterler bozuk | Dil dosyası UTF-8 değil | Dosyayı UTF-8 olarak kaydedin |
| Bir blok küp gölge yapıyor | Şekli ölçülememiş veya listede yanlış grupta | Görünüm 21'e bakın. Gri görünüyorsa kutu tam küp ölçülmüş demektir; bloğu `1004` grubuna alın |
| İnce blok hiç gölge yapmıyor | `VOXEL_SHAPES` kapalı, `1004` grubu atlanıyor | Blok Şekilleri ayarını açın |
| Su kenarlarında tuhaf kaymalar | Kırılma gücü fazla | Su Kırılma Gücünü azaltın |
| Blok ışığı delikli bloğun şeklini almıyor | Voxel kutusu delikleri taşımaz (bkz. bölüm 7b) | "Deliklerden Işık" ayarını açın; gölge şekilli değil yumuşak olur |
| Renk taşıması zayıf | Tek sekme veya düşük doygunluk | "Işık Sekmesi"ni 2+ yapın, "Renk Taşıması"nı artırın, "RT Alanında Işık Haritası"nı düşürün |
| Işık kaynağı zayıf, ambiyans yok | Vanilla ışık haritası ışın izlemeli ışığı bastırıyor | "RT Alanında Işık Haritası"nı 0'a yaklaştırın ve "Işık Kaynağı Gücü"nü artırın |
| Karıncalanma (gürültü) geçmiyor | Biriktirme ve gürültü giderici düşük | Sırasıyla Biriktirme Kareleri, Gürültü Giderici Örnekleri ve Işık Adayı Sayısı'nı artırın |
| Açık kapak gölge yapmıyor | 1.5'te düzeltildi (maske komşu hücreye yazılıyordu) | Güncelleyin |
| Delik deseni iri taneli | Delik Ayrıntısı 8x8 | 16x16 yapın (4 kat bellek) |
| Bir ışık kaynağı ortamı aydınlatmıyor | Listeye girmemiş veya menzil dışında | Görünüm 22'ye bakın. Hiç görünmüyorsa blok `block.properties` içinde ışık grubunda değildir |
| Çok ışıklı yapıda ışıklar titriyor | Liste kapasitesi dolmuş (1024) | Işık Menzilini düşürün veya `MAX_RT_LIGHTS` ile `image.lightImg` genişliğini birlikte artırın |
| Işıkta koni/üçgen şeklinde parlak lekeler | Gölge ışınının adım bütçesi yetersiz (1.3'te düzeltildi) | Çapraz yönde ışın duvara varmadan bitip "engel yok" sayılıyordu |
| Delikli bloğun gölgesi düz çıkıyor | Deliklerin Gölgeye Yansıması kapalı veya blok `1004` grubunda değil | Ayarı açın; blok kutu şekilli gruba ait olmalı |
| Gölgenin ortasında parlak leke | 1.1'de düzeltildi (gölge ışını ışıktan önce duruyordu) | Güncelleyin |
| Bir nesnenin birden fazla gölgesi var | Işık Kaynağı Büyüklüğü çok küçük | Değeri artırın; 0 nokta ışıktır ve her blok ayrı gölge atar |
| Gölgeler fazla yumuşak | Işık Kaynağı Büyüklüğü fazla | Değeri düşürün |
| Blok ışığı gölge yapmıyor | Işın İzlemeli Blok Işıkları kapalı | Ayarı açın; kapalıyken blok ışığı düz ışık haritasından gelir |
| Renkli mum beyaz ışık veriyor | Blok `3008` yerine `3000` grubunda | `tools/generate_blocks.py` içinde `emit_tinted` listesine taşıyın |
| Değer arkasındaki birim yapışık görünüyor | Java properties baştaki boşluğu siler | `suffix.AYAR=\ blok` biçimini kullanın |

---

## 17. Değişiklik geçmişi

### 1.2

- **Gölge keskinliği geri geldi.** Işık kaynağı büyüklüğü sabit bir değerdi, bu da
  meşaleyi de ışık taşı kadar büyük sayıp tüm gölgeleri yumuşatıyordu. Artık boyut,
  bloğun voxelleştirme sırasında ölçülen sınır kutusundan alınıyor: meşale ince bir
  direk olduğu için keskin, ışık taşı tam bir küp olduğu için yumuşak gölge atıyor.
  `RT_LIGHT_SIZE` artık bu gerçek boyutun çarpanı (1.0 = fiziksel doğru).
- Gölge ışını yalnızca seçilen kaynak için kutu içinden örnekleniyor; aday
  ağırlıkları blok merkezinden hesaplandığı için ek maliyet piksel başına tek fetch.

### 1.1

- Paket adı **CORAL VXGI** olarak güncellendi (voxel tabanlı global aydınlatma).
- **Gölgenin ortasındaki parlak dikdörtgen düzeltildi.** Gölge ışını ışığın
  0.55 blok öncesinde duruyordu; bu, engelin ortasında yaklaşık yarım blok çapında
  hiç test edilmeyen bir delik bırakıyordu. Işık kaynağı voxelleri zaten engel
  sayılmadığı için bu paya gerek yoktu, kaldırıldı.
- **Çoklu gölge (gece maçı etkisi) giderildi.** Her ışık bloğu tek bir nokta olarak
  örnekleniyordu, bu yüzden yan yana duran portal veya ışık blokları üst üste binen
  ayrı ayrı keskin gölgeler atıyordu. Artık kaynak blok hacmi boyunca örnekleniyor
  (`RT_LIGHT_SIZE`), komşu bloklar tek bir yumuşak gölgede birleşiyor.


### 1.0 (CORAL VXGI olarak ilk sürüm)

- Paket **CORAL VXGI** adını aldı, Hakkında sayfası yeniden düzenlendi.
- **Kapalı mekanda siyah yansımalar düzeltildi.** Yansımada görünen yüzeylere blok
  ışığı uygulanmıyordu; güneş ve gökyüzü sıfır olduğu için metal kapı gibi tamamen
  yansıtıcı yüzeyler kararıyordu (`REFLECTION_BLOCK_LIGHT`).
- **Camdaki büyüteç etkisi giderildi.** Kırılma kaydırması camın arkasındaki duvara
  olan mesafeyle ölçekleniyordu; artık camın kendi kalınlığı kullanılıyor
  (`GLASS_REFRACTION_DEPTH`) ve kenarlardaki aşırı bozulma sınırlandı.


### 1.5

- **Tüm ayar aralıkları genişletildi.** Gölge çözünürlüğü 16384'e, biriktirme
  kareleri 1024'e, GI adımları 512'ye, ışık adayı sayısı 128'e, gölge örnekleri
  128'e kadar çıkabiliyor. Gürültüyle mücadele için üst sınırlar artık engel değil.
- Gölge ve gürültü giderici 12'den fazla örnek alabiliyor: 12 noktalı Poisson
  diski her turda döndürülüp ölçeklenerek tekrar kullanılıyor (`poissonTap`).
- Yeni ayar: **Gürültü Giderici Örnekleri** (`GI_DENOISE_SAMPLES`).
- **Açık kapaklarda gölge düşmemesi düzeltildi.** Maske hücresi köşe konumundan
  bulunuyordu; bloğun uzak kenarında duran levhalarda (açık kapak, kapı) köşe tam
  1.0'a düşüp komşu hücreye kayıyordu. Artık hücre blok merkezinden bulunuyor.
- **Delik maskesi 16x16'ya çıkarıldı** (`CUTOUT_MASK_RES`). Minecraft dokusuyla
  birebir örtüşür; tek piksellik delikler artık kayboluyor. 8x8 seçeneği dörtte
  bir bellek kullanır.
- Delikli bloklar için ayrı voxel kodu (`VOXEL_CUTOUT`) eklendi; renkli camdan
  ayrıldığı için maske yokken cam yanlışlıkla opaklaşmıyor.
- Işık taşı ve test ışık kaynaklarının varsayılan gücü düşürüldü.


### 1.4

- **Koni şeklindeki ışık sızıntıları düzeltildi.** Gölge ışınının adım bütçesi
  yalnızca `uzunluk + 2` idi; çapraz yönlerde bir ışın `uzunluk x 1.73` adım
  gerektirdiği için duvara varmadan bitiyor ve "engel yok" sayılıyordu. Bütçe
  `uzunluk x 1.8 + 3` yapıldı.
- **Delikli blokların gölgesi** artık deliklerin şeklinde düşüyor
  (`CUTOUT_SHADOW_MASK`, bkz. bölüm 6.6).
- Test ışık kaynaklarının varsayılan gücü 2.5'ten 0.5'e düşürüldü; doğrudan ışık
  örnekleme eklendikten sonra bu bloklar kör edici hale gelmişti. Güç ayarı
  Işık Renkleri sayfasındaki *Bu blokların ışık gücü* kaydırıcısıdır.


### 1.3

- **Doğrudan ışık örnekleme (RT_LIGHTS):** Blok ışıkları artık gerçekten ışın
  izleniyor. Meşale, lav, portal ve renkli mumlar gerçek ve şekilli gölge
  oluşturuyor, delikli bloklardan ışık sızıyor ve renkli ışık ortama yayılıyor.
- Işık kaynağı listesi gölge geçişinde atomik sayaçla oluşturuluyor; her blok
  listeye yalnızca bir kez giriyor.
- Işık örneklemesi ilk sekmede de yapılıyor, böylece blok ışığı duvarlardan sekiyor.
- Vanilla ışık haritasının payı düşürüldü, böylece ışın izlemeli renkli ışık öne çıkıyor.
- Yeni hata ayıklama görünümü 22: yalnızca ışın izlemeli blok ışıkları.
- Denetim aracına ışık listesi kapasitesi kontrolü eklendi.


### 1.3

- **Çok sekmeli GI (`GI_BOUNCES`).** Işık artık birden fazla kez sekiyor, böylece
  renk odaya taşınıyor. `GI_SATURATION` ile renk taşıması ayarlanabiliyor.
- **Renkli cam ışığı renklendiriyor:** güneş için gölge haritası tabanlı renkli
  gölgeler, blok ışıkları için geçirgen voxeller.
- **Delikli bloklar** (kapak, parmaklık) ışığın bir kısmını geçiriyor.
- Işık kaynakları belirgin şekilde güçlendirildi: `EMISSION_STRENGTH` 1.5,
  `LIGHTMAP_RT_BLEND` 0.15, `GI_HIT_AMBIENT` 0.15, ateşböceği sınırı 24.
- **Beton tozu, beton, yün ve mineral blokları** ayrı ayrı açılabilen ışık
  kaynaklarına çevrilebiliyor; her biri kendi doku renginde ışık yayıyor.
- Listelenmiş ışık kaynaklarındaki ışık seviyesi koşulu kaldırıldı: bir blok
  `block.properties` içinde ışık kaynağıysa her durumda ışık yayar.
  Bu, beacon gibi blokların sessizce sönük kalmasını önler.
- Eksik ışık kaynakları eklendi: büyü masası, End geçidi, dolu yeniden doğma
  çapası, uğursuz deneme çağırıcısı ve kasa.

### 1.2

- **Blok şekilleri:** Her bloğun sınır kutusu gölge geçişinde otomatik ölçülüyor.
  Meşale, kapı, kapak, yarım blok, halı ve örs artık bir küp dolusu ışığı
  engellemiyor; gölgeler ve yansımalar gerçek şekli izliyor.
- Yeni blok grubu `1004`: kutu şekilli bloklar yalnızca şekiller açıkken voxelleşir.
- Küçük ışık kaynakları için parlaklık telafisi eklendi.
- **Doku renginde ışıma** (`3008`): 16 mum rengi kendi renginde ışık yayıyor.
- Saydam ışık kaynakları (Nether portalı) artık ışın izlemeye giriyor ve parlıyor.
- Eksik ışık kaynakları eklendi: lav kazanı, sculk katalizörü, orta/küçük ametist
  tomurcuğu, deneme çağırıcısı, kasa.
- **Su kırılması**, ışık desenleri (caustics), biyom renkli su altı sisi ve daha
  güçlü derinlik emilimi eklendi. Cam kırılması seçeneği eklendi.
- Elde tutulan ışığa menzil ayarı eklendi.
- Yeni hata ayıklama görünümü 21: voxel şekilleri.
- Denetim aracına blok kimliği ve voxel boyutu kontrolleri eklendi.

### 1.1

- Paketteki tüm sabitler ayar olarak menüye eklendi: 118 sayısal + 30 açık/kapalı ayar, 12 alt sayfa.
- Hakkında sayfası eklendi (yapımcı, iletişim, lisans, gereksinimler, ipuçları).
- İsimli ve açıklamalı 20 hata ayıklama görünümü ile bölünmüş ekran, NaN tespiti, gölge haritası önizleme ve gürültü dondurma araçları eklendi.
- Ton eşleme seçenekleri eklendi (ACES, Reinhard, Hable, yok), ayrıca kontrast ve kenar kararması.
- Tüm kod ayrıntılı Türkçe yorumlarla yeniden düzenlendi.
- Geliştirme araçları eklendi: `tools/`.
- `CLOUDS` ayarının menüde görünmemesine yol açan `#ifdef` eksikliği giderildi.

### 1.0.1

- Iris'in Sodium'a eklediği `signNotZero` ile isim çakışması düzeltildi (`rb_signNotZero`).

### 1.0

- İlk sürüm: voxel ışın izlemeli GI, yansımalar, gölgeler, gökyüzü, su.
