/*
=====================================================================
  program/shadow.glsl - GÖLGE GEÇİŞİ + VOXELLEŞTİRME
=====================================================================
  Her karede İLK çalışan geçiştir. İki iş yapar:
    1. Güneşin gözünden derinlik çizer -> shadowtex0/shadowtex1
    2. Vertex shader'da, oyuncunun etrafındaki her arazi bloğunu
       3D voxel görüntüsüne (voxelImg) yazar. Sonraki geçişler bu
       ızgarada ışın izler.

  NEDEN GÖLGE GEÇİŞİ?
    shaders.properties'deki "shadow.culling = reversed" ayarı sayesinde
    Iris, voxelDistance içindeki TÜM chunk'ları bu geçişte çizer. Böylece
    kameranın görmediği bloklar da voxel ızgarasına girer.

  at_midBlock: Iris'in verdiği, köşeden blok merkezine olan uzaklık
  (1/64 blok birimi). w bileşeni bloğun ışık seviyesidir (0-15).
=====================================================================
*/
#define SHADOW_PASS

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/materials.glsl"
#include "/lib/shadows.glsl"
#include "/lib/voxel.glsl"

// ================================================================ VERTEX
#ifdef VERTEX_SHADER

in vec4 mc_Entity;       // x: block.properties kimliği
in vec4 mc_midTexCoord;  // doku atlasında bu yüzün doku merkezi
in vec4 at_midBlock;     // köşeden blok merkezine uzaklık * 64, w: ışık seviyesi

uniform int renderStage;
uniform sampler2D gtexture;
layout(rgba8) writeonly uniform image3D voxelImg; // shaders.properties: image.voxelImg
layout(r32ui) coherent uniform uimage3D shapeImg; // şekil maskesi + hücre sahiplenme
#ifdef RT_LIGHTS
layout(rgba16f) writeonly uniform image2D lightImg;      // ışık listesi
layout(r32ui) coherent uniform uimage2D lightCountImg;   // liste uzunluğu sayacı
#endif

out vec2 texcoord;
flat out int isTranslucentCaster;
#ifdef CUTOUT_SHADOW_MASK
out vec3 shadowPlayerPos;        // köşenin oyuncu uzayındaki konumu
flat out vec3 shadowBlockCenter; // bloğun merkezi (hücreyi buradan buluruz)
flat out vec3 shadowFaceNormal;  // yüzün normali (hangi eksene bakıyor)
flat out int  isCutoutBlock;     // dokusunda delik olabilen blok mu
#endif

// Bu köşenin blok içindeki konumunu şekil maskesine işler ve hücrenin
// ÖNCEKİ değerini döndürür. Bloğun tüm köşeleri aynı hücreye OR'landığı için
// sonuçta bloğun sınır kutusu ortaya çıkar (bkz. lib/voxel.glsl).
// Dönen değer 0 ise bu köşe hücreye ilk dokunan köşedir; ışık listesine
// her bloğun yalnızca bir kez eklenmesi bu sayede sağlanır.
uint writeShape(ivec3 cell) {
    // Köşenin blok içindeki konumu: merkez - köşe = at_midBlock/64 olduğundan
    vec3 off = clamp(0.5 - at_midBlock.xyz / 64.0, 0.0, 1.0);
    uint maskY = 1u << uint(min(int(off.y * 16.0), 15));
    uint maskX = 1u << uint(min(int(off.x *  8.0),  7));
    uint maskZ = 1u << uint(min(int(off.z *  8.0),  7));
    return imageAtomicOr(shapeImg, cell, maskY | (maskX << 16) | (maskZ << 24));
}

#ifdef RT_LIGHTS
// Bloğu ışık listesine ekler. Liste dolduysa sessizce atlanır.
void addLight(ivec3 cell, vec3 color) {
    if (maxOf(color) < 0.01) return;
    uint index = imageAtomicAdd(lightCountImg, ivec2(0, 0), 1u);
    if (index < uint(MAX_RT_LIGHTS)) {
        imageStore(lightImg, ivec2(int(index), 0), vec4(vec3(cell) + 0.5, 1.0));
        imageStore(lightImg, ivec2(int(index), 1), vec4(color, 1.0));
    }
}
#endif

void voxelize(int id, bool translucentPass) {
    // Renkli cam ve buz: ışığı durdurmaz, rengini verir (aşağıda işlenir)
    bool transmissive = false;
#ifdef GLASS_TRANSMISSION
    if (id == ID_TRANSLUCENT) transmissive = true;
#endif
    // Işığı hiç etkilemeyen bloklar ızgaraya girmez
    if (id == ID_WATER || id == ID_PLANT || id == ID_NONSOLID || id == ID_END_PORTAL) return;
    if (id == ID_TRANSLUCENT && !transmissive) return;
    #ifndef VOXELIZE_LEAVES
        if (id == ID_LEAVES) return;
    #endif
    // Bu bloklar tam küp olarak çirkin görünür; yalnızca şekilli voxel açıkken eklenir
    #ifndef VOXEL_SHAPES
        if (id == ID_SHAPED) return;
    #endif
    // Saydam katmanda yalnızca ışık kaynakları ve renkli camlar voxelleştirilir
    if (translucentPass && !isEmissiveCategory(id) && !isCustomEmitter(id) && !transmissive) return;

    // Bu köşenin ait olduğu bloğun merkezi -> oyuncu uzayı -> voxel hücresi
    vec3 modelCenter  = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
    vec3 viewCenter   = mat3(gl_ModelViewMatrix) * modelCenter + gl_ModelViewMatrix[3].xyz;
    vec3 playerCenter = mat3(shadowModelViewInverse) * viewCenter + shadowModelViewInverse[3].xyz;

    ivec3 cell = ivec3(floor(playerCenter + fract(cameraPosition))) + VOXEL_VOLUME / 2;
    if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, VOXEL_VOLUME))) return;

    // Bloğun ışık seviyesi (Iris destekliyorsa)
    float lightLevel = 0.0;
    #ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
        lightLevel = at_midBlock.w;
    #endif

    // Ortalama doku rengi: doku merkezinden düşük mipmap seviyesi okunur
    vec4 avg = textureLod(gtexture, mc_midTexCoord.xy, 4.0);

    // Şeffaf pikseller ortalamayı karartır; alfaya bölerek düzelt. Biyom rengini uygula.
    vec3 albedo = min(avg.rgb / max(avg.a, 0.25), vec3(1.0)) * gl_Color.rgb;

    int code = VOXEL_SOLID;
    if (transmissive) {
        // Kanal başına geçirgenlik: kırmızı cam kırmızı ışığı geçirir, diğerlerini yutar
        vec3 transmit = mix(vec3(1.0), albedo, GLASS_TINT_STRENGTH);
        // Cam ne kadar opaksa o kadar az ışık geçirir
        transmit *= mix(1.0, 0.45, saturate(avg.a));
        imageStore(voxelImg, cell, vec4(clamp(transmit, 0.01, 1.0), float(VOXEL_TRANSMISSIVE) / 255.0));
        writeShape(cell);
        return;
    }

    // Blok listede ışık kaynağı olarak geçiyorsa durum zaten block.properties'te
    // ayrılmıştır (ör. furnace:lit=true), bu yüzden ışık seviyesine bakılmaz.
    if (isEmissiveCategory(id) || isCustomEmitter(id)) {
        code = 11 + emissionCategoryOf(id) - 1;
    } else if (lightLevel > 0.5) {
        #ifdef AUTO_EMITTERS
            code = 20 + int(clamp(lightLevel, 1.0, 15.0) + 0.5); // listede olmayan / modlu ışık kaynağı
        #endif
    } else if (id == ID_LEAVES) {
        code = VOXEL_LEAVES;
    } else {
        if (avg.a < 0.35) return; // çoğu şeffaf katmanları atla (ör. çim bloğu yan katmanı)
        #ifdef TRANSMISSION_FROM_ALPHA
            // Kapak, parmaklık gibi delikli bloklar: dokunun boş kısmı kadar ışık geçirir
            if (id == ID_SHAPED && avg.a < 0.95) {
                float transmit = clamp(1.0 - avg.a, 0.0, 0.85);
                if (transmit > 0.05) {
                    imageStore(voxelImg, cell, vec4(vec3(transmit), float(VOXEL_CUTOUT) / 255.0));
                    writeShape(cell);
                    return;
                }
            }
        #endif
        if (id == ID_POLISHED || id == ID_CONCRETE || id == ID_MINERAL) code = VOXEL_POLISHED;
        else if (id == ID_METAL) code = VOXEL_METAL;
    }

    imageStore(voxelImg, cell, vec4(albedo, float(code) / 255.0));

    // Hücreyi ilk sahiplenen köşe, bloğu ışık listesine ekler
    uint previous = writeShape(cell);
#ifdef RT_LIGHTS
    if (previous == 0u) {
        vec3 emitted = voxelEmission(code, toLinear(albedo));
        // Şekli küçük kaynaklar (meşale) için parlaklık telafisi burada uygulanmaz;
        // doğrudan örneklemede ışın kaynağı ıskalamadığı için gerekmez.
        addLight(cell, emitted);
    }
#endif
}

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    int entityId = int(mc_Entity.x + 0.5);
#ifdef CUTOUT_SHADOW_MASK
    {
        vec3 viewVertex = mat3(gl_ModelViewMatrix) * gl_Vertex.xyz + gl_ModelViewMatrix[3].xyz;
        shadowPlayerPos = mat3(shadowModelViewInverse) * viewVertex + shadowModelViewInverse[3].xyz;
        // Hücre, köşeden değil BLOK MERKEZİNDEN bulunur. Açık kapak gibi bloğun
        // uzak kenarında duran levhalarda köşe tam 1.0'a düşüp komşu hücreye
        // kayıyordu; bu yüzden açık kapakların gölgesi hiç düşmüyordu.
        vec3 centerModel = gl_Vertex.xyz + at_midBlock.xyz / 64.0;
        vec3 centerView  = mat3(gl_ModelViewMatrix) * centerModel + gl_ModelViewMatrix[3].xyz;
        shadowBlockCenter = mat3(shadowModelViewInverse) * centerView + shadowModelViewInverse[3].xyz;
        shadowFaceNormal = mat3(shadowModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
        isCutoutBlock = (entityId == ID_SHAPED) ? 1 : 0;
    }
#endif
    isTranslucentCaster = (entityId == ID_TRANSLUCENT || entityId == ID_WATER) ? 1 : 0;

    // Sadece arazi voxelleştirilir (varlıklar hareket eder, ızgaraya girmez)
    if (renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ||
        renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT ||
        renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED) {
        voxelize(int(mc_Entity.x + 0.5), false);
    }
    #ifdef VOXELIZE_TRANSLUCENT_EMITTERS
    else if (renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) {
        voxelize(int(mc_Entity.x + 0.5), true); // Nether portalı gibi saydam ışık kaynakları
    }
    #endif

    vec4 clip = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex);
    clip.xyz = distortShadowClip(clip.xyz);
    gl_Position = clip;
}

#endif

// ============================================================== FRAGMENT
#ifdef FRAGMENT_SHADER

in vec2 texcoord;
flat in int isTranslucentCaster;
uniform sampler2D gtexture;
#ifdef CUTOUT_SHADOW_MASK
in vec3 shadowPlayerPos;
flat in vec3 shadowBlockCenter;
flat in vec3 shadowFaceNormal;
flat in int  isCutoutBlock;
layout(r32ui) coherent uniform uimage3D maskImg; // delik maskesi, voxel başına MASK_WORDS kelime
#endif

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 shadowColorOut;

void main() {
    vec4 c = texture(gtexture, texcoord);

#ifdef CUTOUT_SHADOW_MASK
    // Kapak, kapı gibi blokların delikleri dokudadır, geometride değildir.
    // Burada her saydam doku pikseli, bloğun içindeki 8x8'lik ızgarada kendi
    // yerine denk gelen "delik" bitini işaretler. İşaretleme dünya uzayında
    // yapıldığı için doku yönünü tahmin etmeye gerek kalmaz.
    // Yalnızca DELİKLER işaretlenir; hiç fragment gelmezse blok dolu sayılır,
    // yani en kötü ihtimalle bugünkü davranışa döneriz, ışık sızmaz.
    if (isCutoutBlock == 1 && c.a < 0.5) {
        vec3 base = floor(shadowBlockCenter + fract(cameraPosition));
        ivec3 cell = ivec3(base) + VOXEL_VOLUME / 2;
        if (all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, VOXEL_VOLUME))) {
            vec3 local = clamp(shadowPlayerPos + fract(cameraPosition) - base, 0.0, 0.9999);
            vec3 an = abs(shadowFaceNormal);
            // Yüzün baktığı eksen dışındaki iki eksen ızgarayı oluşturur
            int axis = (an.x > an.y) ? ((an.x > an.z) ? 0 : 2) : ((an.y > an.z) ? 1 : 2);
            vec2 uv = (axis == 0) ? local.yz : ((axis == 1) ? local.xz : local.xy);
            int bit = int(uv.y * float(MASK_RES)) * MASK_RES + int(uv.x * float(MASK_RES));
            imageAtomicOr(maskImg, ivec3(cell.x * MASK_WORDS + (bit >> 5), cell.y, cell.z),
                          1u << uint(bit & 31));
        }
    }
#endif

    if (c.a < 0.1) discard; // yaprak ve çimlerin boşlukları gölge yapmasın

    // Renkli gölgeler için: saydam bir engelin rengi shadowcolor0'a yazılır,
    // alfa "buradaki engel saydamdır" bilgisini taşır (bkz. lib/shadows.glsl)
    if (isTranslucentCaster == 1) {
        shadowColorOut = vec4(c.rgb, 1.0);
    } else {
        shadowColorOut = vec4(c.rgb, 0.0);
    }
}

#endif
