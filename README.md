# CORAL VXGI 1.2

Minecraft Java Edition için voxel tabanlı, gerçek zamanlı ışın izlemeli (ray traced) shader paketi.

## Gereksinimler

- **Iris 1.6 veya daha yeni** + Sodium. OptiFine desteklenmez.
- OpenGL 4.3 destekleyen ekran kartı (NVIDIA GTX 900+, AMD RX 400+, yeni Intel). macOS desteklenmez.

## Kurulum

1. Zip dosyasını **açmadan** `.minecraft/shaderpacks/` klasörüne koyun.
2. Oyunda **O** tuşuna basın (veya Seçenekler → Video Ayarları → Shader Paketleri) ve **CORAL VXGI**'yi seçin.
3. Ayarlar için paket adının yanındaki ayar düğmesine tıklayın. Her ayarın üzerine fareyle gelince açıklaması çıkar.

## Özellikler

- **Delikli bloklar:** kapak ve kapıların gölgesi deliklerinin şeklinde düşer
- **Işın izlemeli blok ışıkları:** meşale, lav ve renkli ışıklar gerçek gölge yapar, delikli bloklardan sızar ve ortamı kendi renkleriyle doldurur
- **Işın izlemeli global aydınlatma:** meşale, lav ve ışık taşından gölgeli renkli ışık, seken ışık, gerçek ortam gölgelemesi
- **Gerçek blok şekilleri:** meşale, kapı, kapak, yarım blok ve halı küp gölge yapmaz; gölgeler bloğun gerçek şeklini izler
- **Işın izlemeli yansımalar:** su, cam, cilalı ve metal bloklar (ekran dışı nesneler dahil)
- **Su:** kırılma, derinlikle renk değişimi, ışık desenleri (caustics), biyom renkli su altı sisi
- **Renkli ışık:** 16 mum rengi kendi renginde ışık yayar, Nether portalı mor ışık saçar
- Yumuşak gölgeler, prosedürel gökyüzü ve bulutlar, dalgalı su, bloom
- LabPBR kaynak paketi desteği, modlu ışık kaynaklarını otomatik algılama
- Overworld, Nether ve End için ayrı aydınlatma

## Ayarlar menüsü

| Sayfa | İçerik |
|---|---|
| Hakkında | Yapımcı, sürüm, iletişim, gereksinimler, performans ipuçları |
| Işın İzleme (GI) | Işın adımları, menzil, güçler, gürültü giderici, ışık kaynağı renkleri |
| Yansımalar | Voxel/ekran uzayı yansımaları, su, cam, blok pürüzsüzlükleri, LabPBR |
| Aydınlatma | Güneş, ay, gökyüzü, blok ışığı rengi ve eğrisi, el ışığı, Nether/End |
| Gölgeler | Çözünürlük, mesafe, yumuşaklık, örnek sayısı, bozulma, kayma |
| Gökyüzü ve Sis | Güneş diski, gün batımı, yıldızlar, bulutlar, sis |
| Su | Dalgalar, kırılma, derinlik kararması, ışık desenleri, su altı sisi |
| Son İşleme | Parlama, pozlama, ton eşleme, doygunluk, kontrast, kenar kararması |
| Hata Ayıklama | 21 isimli görünüm, bölünmüş ekran, NaN tespiti, gölge haritası önizleme |

## Performans

FPS düşükse sırasıyla deneyin:

1. Profili **Düşük** yapın.
2. **Voxel Menzili**'ni 128'e indirin.
3. **Blok Şekilleri**'ni kapatın (ince bloklar gölge yapmaz ama hızlanır).
4. **GI Işın Adımları**'nı düşürün.
5. **Gölge Çözünürlüğü**'nü 1024 yapın.
6. Minecraft görüş mesafesini azaltın.

## Yapımcı

Oktay Mercan — www.youtube.com/OKTAYMERCAN

Bu paket, bir yapay zeka asistanı olan Claude (Anthropic) ile birlikte geliştirilmiştir.

## Düzenlemek isteyenler için

- **Paketin yapısı ve düzenleme rehberi:** [`DOKUMANTASYON.md`](DOKUMANTASYON.md)
- **Geliştirme araçları:** `tools/` klasöründe derleme testi, tutarlılık denetimi ve dosya üreteci bulunur.
