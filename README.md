# CORAL VXGI 1.2

Minecraft Java Edition için voxel tabanlı, gerçek zamanlı ışın izlemeli (ray traced) shader paketi.

## Gereksinimler

- **Iris 1.6 veya daha yeni** + Sodium. OptiFine desteklenmez.
- OpenGL 4.3 destekleyen ekran kartı (NVIDIA GTX 900+, AMD RX 400+, yeni Intel).

## Bilinen Sorunlar
- macOS resmi olarak desteklenmiyor ama çalışır ise şanslısınız.
- Denoise flitresi yeterince iyi değil karıncalanma durumu oluyor.
- 

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


## Yapımcı

Oktay Mercan — www.youtube.com/OKTAYMERCAN

Bu paket, bir yapay zeka asistanı olan Claude (Anthropic) ile birlikte geliştirilmiştir.

## Düzenlemek isteyenler için

- **Paketin yapısı ve düzenleme rehberi:** [`DOKUMANTASYON.md`](DOKUMANTASYON.md)
- **Geliştirme araçları:** `tools/` klasöründe derleme testi, tutarlılık denetimi ve dosya üreteci bulunur.
