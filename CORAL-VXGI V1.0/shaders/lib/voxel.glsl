/*
=====================================================================
  lib/voxel.glsl - Voxel ızgarası ve ışın izleyici
=====================================================================
  NASIL ÇALIŞIR
    Gölge geçişi (program/shadow.glsl) oyuncunun etrafındaki her bloğu
    3D bir görüntüye (voxelImg) yazar: rgb = bloğun ortalama rengi,
    a = voxel kodu (bkz. lib/materials.glsl).
    Diğer geçişler bu görüntüyü "voxelSampler" ile okur ve içinde
    DDA (Amanatides & Woo) algoritmasıyla ışın izler: ışın her adımda
    tam olarak bir sonraki bloğa geçer, hiçbir bloğu atlamaz.

  IZGARA HİZALAMASI
    voxel indeksi = floor(dünyaKonumu) - floor(cameraPosition) + boyut/2
    Bu yüzden playerToVoxel() fract(cameraPosition) ekler.

  BLOK ŞEKİLLERİ (VOXEL_SHAPES)
    Her blok tam küp değildir. Gölge geçişi, bloğun her köşesinin blok
    içindeki konumunu ikinci bir görüntüye (shapeImg) bit maskesi olarak
    yazar: Y ekseni 16, X ve Z ekseni 8 dilime bölünür ve köşenin denk
    geldiği dilimin biti imageAtomicOr ile işaretlenir.
      bit  0-15 : Y dilimleri
      bit 16-23 : X dilimleri
      bit 24-31 : Z dilimleri
    Okurken en düşük ve en yüksek işaretli bit, bloğun sınır kutusunu
    (AABB) verir. Böylece meşale ince bir direk, yarım blok yarım kutu,
    kapı ince bir levha olarak ışın izlenir; şekilli gölgeler oluşur.
    Kutu daima gerçek şekilden biraz BÜYÜK çıkar, bu yüzden geometriden
    ışık sızmaz.
    Bir eksende tek bit varsa geometri o eksende düz bir yüzeydir
    (ör. yalnızca üst yüzü çizilmiş blok) ve kalınlığı bilinemez;
    o eksen tüm hücreye genişletilir.

  BOYUT DEĞİŞTİRMEK İÇİN
    VOXEL_VOLUME, shaders.properties içindeki image.voxelImg satırıyla
    AYNI olmalıdır; ikisini birlikte değiştirin.
=====================================================================
*/
#ifndef INCLUDE_VOXEL
#define INCLUDE_VOXEL

#if VOXEL_RANGE == 256
    const ivec3 VOXEL_VOLUME = ivec3(256, 128, 256);
#elif VOXEL_RANGE == 192
    const ivec3 VOXEL_VOLUME = ivec3(192, 128, 192);
#else
    const ivec3 VOXEL_VOLUME = ivec3(128, 96, 128);
#endif

vec3 playerToVoxel(vec3 playerPos) { return playerPos + fract(cameraPosition) + vec3(VOXEL_VOLUME / 2); }
vec3 voxelToPlayer(vec3 voxelPos)  { return voxelPos - fract(cameraPosition) - vec3(VOXEL_VOLUME / 2); }

// Alanın içinde 1, kenarına doğru yumuşakça 0'a iner.
// Alan dışında ışın izlenmez, yerine vanilla ışık haritası kullanılır.
float voxelVolumeFade(vec3 playerPos) {
    vec3 halfSize = vec3(VOXEL_VOLUME / 2) - 2.0;
    return 1.0 - smoothstep(0.75, 1.0, maxOf(abs(playerPos) / halfSize));
}

// Işık listesi kapasitesi. shaders.properties'teki image.lightImg
// genişliğiyle AYNI olmalıdır.
const int MAX_RT_LIGHTS = 1024;

// Delik maskesi çözünürlüğü. Minecraft dokuları 16x16 olduğu için 16 tam
// hassasiyet verir; 8 dörtte bir bellek kullanır ama 1 piksellik delikleri kaçırır.
const int MASK_RES   = CUTOUT_MASK_RES;
const int MASK_WORDS = (CUTOUT_MASK_RES * CUTOUT_MASK_RES) / 32;

#ifndef SHADOW_PASS
uniform sampler3D voxelSampler; // shaders.properties: image.voxelImg = voxelSampler ...

#ifdef CUTOUT_SHADOW_MASK
uniform usampler3D maskSampler; // delik maskesi, voxel başına MASK_WORDS kelime

// Işın bu voxelden geçerken bir deliğe mi denk geliyor?
//   true  -> delik, ışık hiç zayıflamadan geçer
//   false -> dolu doku, ışık kesilir
// Hiç fragment işlenmemiş bloklarda maske boştur ve blok dolu sayılır;
// yani en kötü ihtimalle maskesiz davranışa döneriz, fazladan ışık sızmaz.
bool cutoutHoleAt(ivec3 cell, vec3 hitLocal, vec3 boxMin, vec3 boxMax) {
    // Levhanın ince ekseni ızgaranın dışında kalır
    // (gölge geçişindeki yüz normaliyle aynı ekseni seçer)
    vec3 ext = boxMax - boxMin;
    int axis = (ext.x < ext.y) ? ((ext.x < ext.z) ? 0 : 2) : ((ext.y < ext.z) ? 1 : 2);
    vec2 uv = (axis == 0) ? hitLocal.yz : ((axis == 1) ? hitLocal.xz : hitLocal.xy);
    uv = clamp(uv, 0.0, 0.9999);

    int bit = int(uv.y * float(MASK_RES)) * MASK_RES + int(uv.x * float(MASK_RES));
    uint word = texelFetch(maskSampler, ivec3(cell.x * MASK_WORDS + (bit >> 5), cell.y, cell.z), 0).r;
    return ((word >> uint(bit & 31)) & 1u) != 0u;
}
#endif

#ifdef VOXEL_SHAPES
uniform usampler3D shapeSampler; // shaders.properties: image.shapeImg = shapeSampler ...

// En düşük / en yüksek işaretli bitin sırası.
// findLSB/findMSB GLSL 4.00 gerektirir, bu yüzden log2 ile hesaplanır.
int rbLowBit(uint m)  { return int(log2(float(m & (~m + 1u)))); }
int rbHighBit(uint m) { return int(log2(float(m))); }

// Bir eksenin bit maskesini [min, max] aralığına çevirir
vec2 decodeShapeAxis(uint mask, float steps) {
    // 0 bit: veri yok | 1 bit: düz yüzey, kalınlık bilinmiyor -> tüm hücre
    if (mask == 0u || (mask & (mask - 1u)) == 0u) return vec2(0.0, 1.0);
    return vec2(float(rbLowBit(mask)) / steps, float(rbHighBit(mask) + 1) / steps);
}

// Hücre içindeki bloğun sınır kutusu (hücreye göre 0..1)
void getVoxelBox(ivec3 cell, out vec3 boxMin, out vec3 boxMax) {
    uint m = texelFetch(shapeSampler, cell, 0).r;
    if (m == 0u) { boxMin = vec3(0.0); boxMax = vec3(1.0); return; }
    vec2 ax = decodeShapeAxis((m >> 16) & 0xFFu, 8.0);
    vec2 ay = decodeShapeAxis( m        & 0xFFFFu, 16.0);
    vec2 az = decodeShapeAxis((m >> 24) & 0xFFu, 8.0);
    boxMin = vec3(ax.x, ay.x, az.x);
    boxMax = vec3(ax.y, ay.y, az.y);
}

// Küçülen ışık kaynakları için parlaklık telafisi.
// Bir kutunun her yönden görülen ortalama kesit alanı yüzey alanının 1/4'üdür;
// tam küpe göre oranı alınır, böylece meşale incelince sönükleşmez.
float shapeEmissionBoost(vec3 boxMin, vec3 boxMax) {
    vec3 e = max(boxMax - boxMin, vec3(0.02));
    float area = e.x * e.y + e.y * e.z + e.z * e.x; // tam küpte 3.0
    return clamp(3.0 / area, 1.0, EMISSION_SHAPE_BOOST_MAX);
}
#endif

// ---------------------------------------------------------------------
//  traceVoxels: origin noktasından dir yönünde ışın gönderir.
//    origin   : voxel uzayında başlangıç (playerToVoxel ile)
//    maxSteps : en fazla kaç blok sınırı geçilecek
//    maxDist  : blok cinsinden en uzun mesafe
//  Çıkışlar:
//    hitPos    : çarpılan yüzeyin voxel uzayındaki noktası
//    hitNormal : çarpılan yüzün normali (eksen hizalı)
//    voxelData : çarpılan voxelin verisi (rgb renk, a kod)
//  Başlangıç hücresi atlanır; böylece yüzeyin kendi bloğuna çarpılmaz.
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
//  traceTransmittance: bir yüzeyden bir ışık kaynağına giden yolun ne kadar
//  ışık geçirdiğini döndürür. Doğrudan ışık örneklemesinin gölge ışınıdır.
//    vec3(0)   : yol kapalı (gölgede)
//    vec3(1)   : yol açık
//    ara değer : renkli camdan veya delikli bloktan süzülen ışık
//  Işık kaynağı voxelleri engel sayılmaz, yoksa kaynak kendi ışığını keserdi.
// ---------------------------------------------------------------------
vec3 traceTransmittance(vec3 origin, vec3 dir, float maxDist, int maxSteps) {
    vec3 tint = vec3(1.0);

    vec3 d = dir + vec3(equal(dir, vec3(0.0))) * 1e-5;
    vec3 invDir   = 1.0 / d;
    vec3 stepSign = sign(d);
    vec3 tDelta   = abs(invDir);
    vec3 cellF    = floor(origin);
    ivec3 cell    = ivec3(cellF);
    ivec3 istep   = ivec3(stepSign);
    vec3 tMax     = (cellF + max(stepSign, vec3(0.0)) - origin) * invDir;

    for (int i = 0; i < maxSteps; i++) {
        vec3 mask = step(tMax, tMax.yzx) * step(tMax, tMax.zxy);
        if (mask.x > 0.5) mask.yz = vec2(0.0);
        else if (mask.y > 0.5) mask.z = 0.0;

        float t = dot(tMax, mask);
        if (t > maxDist) return tint;          // ışığa ulaşıldı

        tMax += mask * tDelta;
        cell += ivec3(mask) * istep;

        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, VOXEL_VOLUME))) return tint;

        vec4 v = texelFetch(voxelSampler, cell, 0);
        if (v.a <= 0.002) continue;

        int code = int(v.a * 255.0 + 0.5);
        if (maxOf(voxelEmission(code, vec3(1.0))) > 0.0) continue; // ışık kaynakları engel değil

#ifdef VOXEL_SHAPES
        // Kısmi şekilli bloklarda ışın kutuyu ıskalayabilir
        vec3 bMin, bMax;
        getVoxelBox(cell, bMin, bMax);
        if (any(greaterThan(bMin, vec3(0.0))) || any(lessThan(bMax, vec3(1.0)))) {
            vec3 cf = vec3(cell);
            vec3 t1 = (cf + bMin - origin) * invDir;
            vec3 t2 = (cf + bMax - origin) * invDir;
            vec3 tSmall = min(t1, t2);
            vec3 tBig   = max(t1, t2);
            float tEnter = max(max(tSmall.x, tSmall.y), tSmall.z);
            float tExit  = min(min(tBig.x, tBig.y), tBig.z);
            if (tExit < max(tEnter, 0.0) || tEnter > maxDist) continue; // kutuyu ıskaladı
        }
#endif

        if (code == VOXEL_CUTOUT) {
#ifdef CUTOUT_SHADOW_MASK
            // Delikli blok: ışının tam olarak nereye denk geldiğine bak.
            // Böylece kapağın gölgesi deliklerinin şeklinde düşer.
            {
                vec3 bMin2 = vec3(0.0), bMax2 = vec3(1.0);
    #ifdef VOXEL_SHAPES
                getVoxelBox(cell, bMin2, bMax2);
    #endif
                // Levhanın orta düzlemini kestiği nokta
                vec3 ext2 = bMax2 - bMin2;
                int ax = (ext2.x < ext2.y) ? ((ext2.x < ext2.z) ? 0 : 2) : ((ext2.y < ext2.z) ? 1 : 2);
                float mid = float(cell[ax]) + 0.5 * (bMin2[ax] + bMax2[ax]);
                float tPlane = (mid - origin[ax]) * invDir[ax];
                vec3 local = origin + dir * tPlane - vec3(cell);
                if (cutoutHoleAt(cell, local, bMin2, bMax2)) continue; // delikten geçti
                return vec3(0.0);                                     // dolu kısma çarptı
            }
#else
            tint *= v.rgb;                      // maske kapalıysa düzgün geçirgenlik
            if (maxOf(tint) < 0.02) return vec3(0.0);
            continue;
#endif
        }
        if (code == VOXEL_TRANSMISSIVE) {
            tint *= v.rgb;                      // renkli cam: ışığı renklendirir
            if (maxOf(tint) < 0.02) return vec3(0.0);
            continue;
        }
        return vec3(0.0);                       // opak engel
    }
    return tint;
}

#ifdef RT_LIGHTS
uniform sampler2D  lightSampler;      // satır 0: voxel konumu, satır 1: ışık rengi
uniform usampler2D lightCountSampler; // listedeki ışık sayısı

// ---------------------------------------------------------------------
//  sampleBlockLights - doğrudan ışık örnekleme (next event estimation)
//
//  Işınların küçük bir meşaleye rastgele çarpmasını beklemek yerine, ışık
//  kaynaklarının listesinden birini seçip ona GÖLGE IŞINI göndeririz.
//  Böylece blok ışığı gerçek, şekilli gölgeler oluşturur ve renkli ışık
//  gürültüsüz biçimde ortama yayılır.
//
//  Seçim yöntemi (ağırlıklı rezervuar örnekleme / RIS):
//    1. Listeden RT_LIGHT_SAMPLES tane rastgele aday çekilir.
//    2. Her adayın gölgesiz katkısı ağırlık olarak hesaplanır.
//    3. Ağırlıkla orantılı olarak bir aday seçilir.
//    4. Yalnızca ona gölge ışını gönderilir.
//  Tahmin edici sapmasız kalsın diye sonuç (toplam ağırlık / aday sayısı)
//  ile ölçeklenir; eksik kalan gürültüyü zamansal biriktirme temizler.
// ---------------------------------------------------------------------
// Işık kaynağı içinde rastgele bir nokta seçmek için ucuz karıştırıcı
vec3 lightJitter(vec3 seed3, int i) {
    vec3 p = seed3 * 127.1 + float(i) * vec3(311.7, 269.5, 183.3);
    return fract(sin(p) * 43758.5453) - 0.5;
}

vec3 sampleBlockLights(vec3 voxelPos, vec3 normal, vec3 rnd) {
    uint count = texelFetch(lightCountSampler, ivec2(0, 0), 0).r;
    count = min(count, uint(MAX_RT_LIGHTS));
    if (count == 0u) return vec3(0.0);

    int candidates = min(RT_LIGHT_SAMPLES, int(count));
    float weightSum = 0.0;
    vec3  chosenColor = vec3(0.0);
    vec3  chosenDir = vec3(0.0);
    vec3  chosenPos = vec3(0.0);
    float chosenDist = 0.0;
    float chosenTarget = 0.0;
    float rndPick = rnd.z;

    for (int i = 0; i < candidates; i++) {
        // Her aday için listeden sözde rastgele bir sıra numarası
        float r = fract(rnd.x + float(i) * 0.6180339887);
        int index = int(r * float(count));
        index = clamp(index, 0, int(count) - 1);

        vec3 lightPos = texelFetch(lightSampler, ivec2(index, 0), 0).xyz;
        vec3 toLight = lightPos - voxelPos;
        float dist2 = dot(toLight, toLight);
        if (dist2 > RT_LIGHT_RANGE * RT_LIGHT_RANGE) continue;

        float dist = sqrt(max(dist2, 1e-4));
        vec3 dirToLight = toLight / dist;
        float ndotl = dot(normal, dirToLight);
        if (ndotl <= 0.0) continue;

        vec3 color = texelFetch(lightSampler, ivec2(index, 1), 0).rgb;
        float falloff = 1.0 / (1.0 + dist2 * RT_LIGHT_FALLOFF);
        falloff *= smoothstep(RT_LIGHT_RANGE, RT_LIGHT_RANGE * 0.55, dist); // menzil sonunda yumuşak kesim

        float target = luminance(color) * ndotl * falloff;
        if (target <= 0.0) continue;

        // Adaylar düzgün dağılımla çekildiği için ağırlık = hedef * liste uzunluğu
        float weight = target * float(count);
        weightSum += weight;
        rndPick = fract(rndPick * 1.61803398875 + 0.31830988618);
        if (rndPick * weightSum < weight) {
            chosenColor  = color;
            chosenDir    = dirToLight;
            chosenPos    = lightPos;
            chosenDist   = dist;
            chosenTarget = target;
        }
    }

    if (weightSum <= 0.0 || chosenTarget <= 0.0) return vec3(0.0);

    // Gölge ışını: kaynağın kendi hücresine girmeden hemen önce dur
    // Işık voxelleri traceTransmittance içinde zaten engel sayılmıyor, bu yüzden
    // ışığın önünde durmaya gerek yok. Eski 0.55 bloklık pay, engelin ortasında
    // yarım bloka yakın çapta test edilmeyen bir delik bırakıyor ve gölgenin
    // ortasına parlak bir dikdörtgen düşürüyordu.
    // Gölgenin yumuşaklığı kaynağın gerçek büyüklüğünden gelmelidir: meşale ince
    // bir direktir ve keskin gölge atar, ışık taşı tam bir kübdür ve yumuşak atar.
    // Bu yüzden örnek noktası, bloğun voxelleştirme sırasında ölçülen sınır
    // kutusu içinden seçilir. Sabit bir boyut kullanmak meşaleyi de blok
    // büyüklüğünde sayıp gölgelerin keskinliğini yok ediyordu.
    vec3 sampleDir  = chosenDir;
    float sampleDist = chosenDist;
    if (RT_LIGHT_SIZE > 0.001) {
        vec3 boxMin = vec3(0.0), boxMax = vec3(1.0);
#ifdef VOXEL_SHAPES
        getVoxelBox(ivec3(floor(chosenPos)), boxMin, boxMax);
#endif
        vec3 extent = max(boxMax - boxMin, vec3(0.05));
        vec3 offset = lightJitter(rnd, 17) * extent * RT_LIGHT_SIZE;
        vec3 toSample = (chosenPos + offset) - voxelPos;
        float sd = length(toSample);
        if (sd > 1e-3) {
            sampleDir  = toSample / sd;
            sampleDist = sd;
        }
    }

    float rayLength = max(sampleDist - 0.02, 0.02);
    // DDA, L uzunluğunda bir ışın için L*(|dx|+|dy|+|dz|) hücre sınırı geçer;
    // bu çapraz yönlerde L'nin 1.73 katına çıkar. Bütçe yetmezse ışın duvara
    // varmadan biter ve "engel yok" sayılır: çapraz yönlerde ışık sızar,
    // ekranda koni/üçgen şeklinde parlak lekeler oluşurdu.
    int steps = int(min(rayLength * 1.8 + 3.0, 256.0));
    vec3 visibility = traceTransmittance(voxelPos + normal * 0.02, sampleDir, rayLength, steps);
    if (maxOf(visibility) <= 0.0) return vec3(0.0);

    // RIS tahmin edicisi: renkli katkı / skaler hedef * ortalama ağırlık
    vec3 contribution = chosenColor / max(luminance(chosenColor), 1e-4);
    return contribution * visibility * (weightSum / float(candidates)) * RT_LIGHT_STRENGTH;
}
#endif

bool traceVoxels(vec3 origin, vec3 dir, int maxSteps, float maxDist,
                 out vec3 hitPos, out vec3 hitNormal, out vec4 voxelData, out float emitBoost,
                 out vec3 transmittance) {
    hitPos = vec3(0.0);
    hitNormal = vec3(0.0);
    voxelData = vec4(0.0);
    emitBoost = 1.0;
    transmittance = vec3(1.0); // ışın renkli camdan geçtikçe bu renklenir

    // Sıfır bileşenli yönlerde bölme hatasını önle
    vec3 d = dir + vec3(equal(dir, vec3(0.0))) * 1e-5;
    vec3 invDir   = 1.0 / d;
    vec3 stepSign = sign(d);
    vec3 tDelta   = abs(invDir);                  // bir blok geçmek için gereken t
    vec3 cellF    = floor(origin);
    ivec3 cell    = ivec3(cellF);
    ivec3 istep   = ivec3(stepSign);
    vec3 tMax     = (cellF + max(stepSign, vec3(0.0)) - origin) * invDir; // ilk sınıra t

    for (int i = 0; i < maxSteps; i++) {
        // En yakın sınır hangi eksende? (eşitlikte tek eksen seç)
        vec3 mask = step(tMax, tMax.yzx) * step(tMax, tMax.zxy);
        if (mask.x > 0.5) mask.yz = vec2(0.0);
        else if (mask.y > 0.5) mask.z = 0.0;

        float t = dot(tMax, mask);
        if (t > maxDist) return false;

        tMax += mask * tDelta;
        cell += ivec3(mask) * istep;

        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, VOXEL_VOLUME))) return false;

        vec4 v = texelFetch(voxelSampler, cell, 0);
        if (v.a > 0.002) { // boş olmayan voxel
            int code = int(v.a * 255.0 + 0.5);
            vec3 bMin = vec3(0.0), bMax = vec3(1.0);
#ifdef VOXEL_SHAPES
            getVoxelBox(cell, bMin, bMax);

            if (any(greaterThan(bMin, vec3(0.0))) || any(lessThan(bMax, vec3(1.0)))) {
                // Kısmi şekil: hücre yerine kutuyla kesişim testi (slab yöntemi)
                vec3 cf = vec3(cell);
                vec3 t1 = (cf + bMin - origin) * invDir;
                vec3 t2 = (cf + bMax - origin) * invDir;
                vec3 tSmall = min(t1, t2);
                vec3 tBig   = max(t1, t2);
                float tEnter = max(max(tSmall.x, tSmall.y), tSmall.z);
                float tExit  = min(min(tBig.x, tBig.y), tBig.z);

                if (tExit < max(tEnter, 0.0) || tEnter > maxDist) continue; // kutuyu ıskaladı, yola devam

                // Işık geçiren blok: ışını durdurma, rengini emip yoluna devam et
                if (code == VOXEL_TRANSMISSIVE || code == VOXEL_CUTOUT) {
                    transmittance *= max(v.rgb, vec3(0.01));
                    if (maxOf(transmittance) < 0.02) return false; // ışık tamamen yutuldu
                    continue;
                }

                tEnter = max(tEnter, 0.0);
                // Girişi hangi eksen belirlediyse yüzey normali odur
                vec3 nMask = vec3(equal(tSmall, vec3(tEnter)));
                if (nMask.x > 0.5) nMask.yz = vec2(0.0);
                else if (nMask.y > 0.5) nMask.z = 0.0;

                hitPos    = origin + dir * tEnter;
                hitNormal = -nMask * stepSign;
                voxelData = v;
                emitBoost = shapeEmissionBoost(bMin, bMax);
                return true;
            }
#endif
            // Tam küp ışık geçiren blok (renkli cam bloğu)
            if (code == VOXEL_TRANSMISSIVE || code == VOXEL_CUTOUT) {
                transmittance *= max(v.rgb, vec3(0.01));
                if (maxOf(transmittance) < 0.02) return false;
                continue;
            }

            // Tam küp: hücre sınırındaki isabet
            hitPos    = origin + dir * t;
            hitNormal = -mask * stepSign;
            voxelData = v;
            emitBoost = 1.0;
            return true;
        }
    }
    return false;
}

// Geçirgenlik ve telafiye ihtiyaç duymayan çağrılar için kısa biçimler
bool traceVoxels(vec3 origin, vec3 dir, int maxSteps, float maxDist,
                 out vec3 hitPos, out vec3 hitNormal, out vec4 voxelData, out float emitBoost) {
    vec3 ignoredTint;
    return traceVoxels(origin, dir, maxSteps, maxDist, hitPos, hitNormal, voxelData, emitBoost, ignoredTint);
}

bool traceVoxels(vec3 origin, vec3 dir, int maxSteps, float maxDist,
                 out vec3 hitPos, out vec3 hitNormal, out vec4 voxelData) {
    float ignoredBoost;
    return traceVoxels(origin, dir, maxSteps, maxDist, hitPos, hitNormal, voxelData, ignoredBoost);
}

// ---------------------------------------------------------------------
//  shadeVoxelHit: çarpılan voxel yüzeyinden kameraya doğru çıkan ışık.
//  Voxellerin dokusu yoktur, düz renkle aydınlatılır.
//    sunExposure / skyExposure : sızıntı önleme çarpanları (bkz. sky.glsl)
// ---------------------------------------------------------------------
vec3 shadeVoxelHit(vec3 hitPos, vec3 hitNormal, vec4 voxel, vec3 lightDir,
                   vec3 directLight, vec3 skyAmbient, float sunExposure, float skyExposure,
                   float emitBoost, float ambientScale) {
    int code = int(voxel.a * 255.0 + 0.5);
    vec3 albedo = toLinear(voxel.rgb);
    vec3 radiance = vec3(0.0);

#ifdef OVERWORLD
    // Çarpma noktası güneş görüyor mu? Gölge haritasına sor.
    float NdotL = dot(hitNormal, lightDir);
    if (NdotL > 0.0 && sunExposure > 0.0) {
        vec3 hitPlayer = voxelToPlayer(hitPos + hitNormal * 0.15);
        radiance += albedo * directLight * NdotL * shadowSingle(hitPlayer) * sunExposure * GI_SUN_BOUNCE;
    }
#endif

    radiance += albedo * skyAmbient * (ambientScale * skyExposure + 0.03);
    // Şekil küçüldükçe ışın onu daha az yakalar; telafi ile parlaklık korunur
    radiance += voxelEmission(code, albedo) * mix(1.0, emitBoost, EMISSION_SHAPE_BOOST);
    return radiance;
}
#endif // SHADOW_PASS

#endif // INCLUDE_VOXEL
