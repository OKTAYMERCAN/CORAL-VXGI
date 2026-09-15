"""
CORAL VXGI - block.properties üreteci
======================================
Blok listelerini tek yerden üretir, böylece 16 renkli varyantları elle
yazmak gerekmez.  KULLANIM:  python tools/generate_blocks.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "shaders", "block.properties"))

colors = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
          "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]
woods = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry",
         "bamboo", "crimson", "warped", "pale_oak"]
copper_stages = ["", "exposed_", "weathered_", "oxidized_"]

# --------------------------------------------------------------------- 1000
water = ["water", "flowing_water", "bubble_column"]

# --------------------------------------------------------------------- 1001
translucent = ["glass", "glass_pane", "tinted_glass", "ice", "frosted_ice", "slime_block", "honey_block"]
translucent += [f"{c}_stained_glass" for c in colors]
translucent += [f"{c}_stained_glass_pane" for c in colors]

# --------------------------------------------------------------------- 1002
plants = """short_grass grass tall_grass fern large_fern dead_bush dandelion poppy blue_orchid allium azure_bluet
red_tulip orange_tulip white_tulip pink_tulip oxeye_daisy cornflower lily_of_the_valley wither_rose torchflower
sunflower lilac rose_bush peony pitcher_plant wheat carrots potatoes beetroots sweet_berry_bush sugar_cane
bamboo bamboo_sapling oak_sapling spruce_sapling birch_sapling jungle_sapling acacia_sapling dark_oak_sapling
cherry_sapling pale_oak_sapling mangrove_propagule azalea flowering_azalea brown_mushroom red_mushroom
crimson_roots warped_roots nether_sprouts crimson_fungus warped_fungus seagrass tall_seagrass kelp kelp_plant
hanging_roots spore_blossom small_dripleaf big_dripleaf big_dripleaf_stem pink_petals torchflower_crop pitcher_crop
melon_stem pumpkin_stem attached_melon_stem attached_pumpkin_stem cave_vines:berries=false
cave_vines_plant:berries=false vine twisting_vines twisting_vines_plant weeping_vines weeping_vines_plant
nether_wart cocoa chorus_plant chorus_flower short_dry_grass tall_dry_grass bush firefly_bush leaf_litter
wildflowers cactus_flower open_eyeblossom closed_eyeblossom pale_hanging_moss""".split()

# --------------------------------------------------------------------- 1003
# Hiç voxelleştirilmeyenler: kafes/çapraz şekilliler. Sınır kutuları gerçek
# şekillerinden çok büyük olurdu, bu yüzden ışığı hiç engellemesinler.
nonsolid = """cobweb iron_bars chain scaffolding pointed_dripstone string tripwire barrier light structure_void
nether_brick_fence""".split()
nonsolid += [f"{w}_fence" for w in woods] + [f"{w}_fence_gate" for w in woods]
nonsolid += [f"{c}_banner" for c in colors] + [f"{c}_wall_banner" for c in colors]
nonsolid += [f"{wax}{p}copper_grate" for p in copper_stages for wax in ("", "waxed_")]

# --------------------------------------------------------------------- 1004
# Kutu şekilli ama tam küp olmayanlar. VOXEL_SHAPES açıkken gerçek
# kutularıyla voxelleştirilir, kapalıyken hiç eklenmezler.
shaped = """rail powered_rail detector_rail activator_rail redstone_wire tripwire_hook ladder lever snow
lily_pad turtle_egg frogspawn sculk_vein moss_carpet pale_moss_carpet flower_pot repeater comparator
daylight_detector end_portal_frame stone_pressure_plate light_weighted_pressure_plate
heavy_weighted_pressure_plate polished_blackstone_pressure_plate stone_button polished_blackstone_button
iron_door iron_trapdoor lightning_rod candle:lit=false skeleton_skull skeleton_wall_skull
wither_skeleton_skull wither_skeleton_wall_skull zombie_head zombie_wall_head player_head player_wall_head
creeper_head creeper_wall_head dragon_head dragon_wall_head piglin_head piglin_wall_head bell lectern
brewing_stand cauldron water_cauldron powder_snow_cauldron hopper grindstone anvil chipped_anvil damaged_anvil
resin_clump sculk_sensor calibrated_sculk_sensor sculk_shrieker lodestone stonecutter cake decorated_pot
heavy_core creaking_heart""".split()
shaped += [f"{c}_carpet" for c in colors] + [f"{c}_candle:lit=false" for c in colors]
for w in woods:
    shaped += [f"{w}_door", f"{w}_trapdoor", f"{w}_sign", f"{w}_wall_sign", f"{w}_hanging_sign",
               f"{w}_wall_hanging_sign", f"{w}_pressure_plate", f"{w}_button"]
shaped += [f"{wax}{p}copper_door" for p in copper_stages for wax in ("", "waxed_")]
shaped += [f"{wax}{p}copper_trapdoor" for p in copper_stages for wax in ("", "waxed_")]

# --------------------------------------------------------------------- 2000+
leaves = [f"{w}_leaves" for w in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak",
                                  "mangrove", "cherry", "azalea", "flowering_azalea", "pale_oak"]]

polished = """polished_andesite polished_diorite polished_granite polished_blackstone polished_deepslate polished_tuff
smooth_quartz quartz_block quartz_pillar chiseled_quartz_block quartz_bricks calcite obsidian packed_ice blue_ice
polished_basalt smooth_basalt dripstone_block
polished_andesite_slab polished_diorite_slab polished_granite_slab smooth_quartz_slab quartz_slab
polished_andesite_stairs polished_diorite_stairs polished_granite_stairs smooth_quartz_stairs quartz_stairs""".split()
polished += [f"{c}_glazed_terracotta" for c in colors]
# not: beton, yün, beton tozu ve mineral blokları kendi gruplarındadır (2100-2103),
# çünkü ayarla ışık kaynağına çevrilebilirler. Kapalıyken shader onları
# cilalı/normal blok gibi işler.
concrete_powder = [f"{c}_concrete_powder" for c in colors]
concrete        = [f"{c}_concrete" for c in colors]
wool            = [f"{c}_wool" for c in colors]
mineral = ("redstone_block lapis_block emerald_block diamond_block amethyst_block coal_block "
           "raw_copper_block slime_block_unused").split()
mineral.remove("slime_block_unused")

# not: iron_door / iron_trapdoor şekilli gruptadır (1004), bir blok tek grupta olabilir
metal = ["iron_block", "gold_block", "netherite_block", "raw_iron_block", "raw_gold_block"]
for p in copper_stages:
    for wax in ("", "waxed_"):
        metal += [f"{wax}{p}copper_block" if not p else f"{wax}{p}copper",
                  f"{wax}{p}cut_copper", f"{wax}{p}chiseled_copper",
                  f"{wax}{p}cut_copper_slab", f"{wax}{p}cut_copper_stairs"]

# --------------------------------------------------------------- 3000..3008
emit_fire = """torch wall_torch lantern campfire:lit=true fire jack_o_lantern furnace:lit=true smoker:lit=true
blast_furnace:lit=true candle:lit=true candle_cake:lit=true""".split()
emit_soul = "soul_torch soul_wall_torch soul_lantern soul_campfire:lit=true soul_fire".split()
emit_lamp = "glowstone redstone_lamp:lit=true shroomlight ochre_froglight".split()
emit_lamp += [f"{wax}{p}copper_bulb:lit=true" for p in copper_stages for wax in ("", "waxed_")]
emit_lava = "lava flowing_lava magma_block lava_cauldron".split()
emit_redstone = ("redstone_torch:lit=true redstone_wall_torch:lit=true redstone_ore:lit=true "
                 "deepslate_redstone_ore:lit=true").split()
emit_cool = ("sea_lantern beacon end_rod conduit trial_spawner vault "
             "trial_spawner:ominous=true vault:ominous=true").split()
emit_purple = ("crying_obsidian amethyst_cluster large_amethyst_bud medium_amethyst_bud small_amethyst_bud "
               "nether_portal pearlescent_froglight enchanting_table end_gateway "
               "respawn_anchor:charges=1 respawn_anchor:charges=2 respawn_anchor:charges=3 "
               "respawn_anchor:charges=4").split()
emit_green = ("glow_lichen verdant_froglight cave_vines:berries=true cave_vines_plant:berries=true "
              "sea_pickle sculk_catalyst copper_torch copper_wall_torch copper_lantern").split()
# Işığı kendi doku renginde yayanlar: 16 mum rengi için 16 kategori gerekmez
emit_tinted = [f"{c}_candle:lit=true" for c in colors] + [f"{c}_candle_cake:lit=true" for c in colors]

sections = [
    ("Su - voxelleştirilmez, gbuffers_water'da dalga ve yansıma alır", 1000, water),
    ("Saydam bloklar - voxelleştirilmez, ışığı engellemez", 1001, translucent),
    ("Bitkiler - voxelleştirilmez, üzerinde durdukları zemin gibi aydınlanır", 1002, plants),
    ("Kafes/çapraz şekilliler - hiç voxelleştirilmez (sınır kutusu yanıltıcı olurdu)", 1003, nonsolid),
    ("Kutu şekilliler - yalnızca VOXEL_SHAPES açıkken, gerçek kutularıyla", 1004, shaped),
    ("Yapraklar - ışığı engeller (ayarla kapatılabilir), ışık geçirgen aydınlanır", 2000, leaves),
    ("Cilalı bloklar - yansıtır (pürüzsüzlük: POLISHED_SMOOTHNESS)", 2001, polished),
    ("Metal bloklar - metal yansıma (pürüzsüzlük: METAL_SMOOTHNESS)", 2002, metal),
    ("Işık kaynağı: ateş rengi (EMIT_FIRE_*)", 3000, emit_fire),
    ("Işık kaynağı: ruh ateşi rengi (EMIT_SOUL_*)", 3001, emit_soul),
    ("Işık kaynağı: lamba rengi (EMIT_LAMP_*)", 3002, emit_lamp),
    ("Işık kaynağı: lav rengi (EMIT_LAVA_*)", 3003, emit_lava),
    ("Işık kaynağı: kızıltaş rengi (EMIT_REDSTONE_*)", 3004, emit_redstone),
    ("Işık kaynağı: soğuk beyaz (EMIT_COOL_*)", 3005, emit_cool),
    ("Işık kaynağı: mor (EMIT_PURPLE_*)", 3006, emit_purple),
    ("Işık kaynağı: yeşil / camgöbeği (EMIT_GREEN_*)", 3007, emit_green),
    ("Işık kaynağı: bloğun KENDİ doku renginde (EMIT_TINTED_*) - renkli mumlar", 3008, emit_tinted),
    ("Beton tozu - EMIT_CONCRETE_POWDER açıksa kendi renginde ışık yayar", 2100, concrete_powder),
    ("Beton - EMIT_CONCRETE açıksa ışık yayar, kapalıyken cilalı bloktur", 2101, concrete),
    ("Yün - EMIT_WOOL açıksa ışık yayar", 2102, wool),
    ("Mineral blokları - EMIT_MINERAL_BLOCKS açıksa ışık yayar, kapalıyken cilalıdır", 2103, mineral),
    ("End portalı - blok varlığı, kendi yıldızlı görünümünü çizer", 4000, ["end_portal"]),
]

HEADER = """# =====================================================================
#  CORAL VXGI - BLOK KİMLİKLERİ (block.properties)
# =====================================================================
#  OTOMATİK ÜRETİLDİ: tools/generate_blocks.py
#  Kalıcı değişiklikler için o dosyayı düzenleyip betiği yeniden çalıştırın.
#
#  Her satır bir grup bloğa bir kimlik numarası verir:
#      block.NUMARA = blok1 blok2 blok3:durum=deger
#  Shader bu numarayı mc_Entity.x olarak okur. Numaraların anlamı
#  shaders/lib/materials.glsl içindeki ID_ sabitlerinde tanımlıdır.
#
#  KURALLAR
#   - Listede OLMAYAN bloklar tam küp olarak voxelleştirilir.
#     (VOXEL_SHAPES açıkken şekilleri otomatik ölçülür.)
#   - Bir blok yalnızca TEK grupta olmalıdır (durum ile ayrılmıyorsa).
#   - Durum belirtmek için:  redstone_lamp:lit=true
#   - Uzun satırlar sonuna ters eğik çizgi konarak alt satırda sürer.
#   - Başka sürümlerde olmayan blok adları sorunsuzca yok sayılır.
#   - Modlu bloklar için ad alanı yazın:  modadi:blok_adi
#
#  ÖRNEK: Bir bloğu ateş rengi ışık kaynağı yapmak için 3000 satırına ekleyin.
#         Kendi renginde ışık yayması için 3008 satırına ekleyin.
#  Değişiklikten sonra shader'ı yeniden yükleyin (R tuşu).
# =====================================================================
"""


def wrap(ids, indent="    ", width=112):
    out, line = [], ""
    for i in ids:
        if len(line) + len(i) > width:
            out.append(line.rstrip())
            line = ""
        line += i + " "
    if line:
        out.append(line.rstrip())
    return (" \\\n" + indent).join(out)


def main():
    seen = {}
    for title, bid, ids in sections:
        for i in ids:
            if i in seen:
                raise SystemExit(f"HATA: '{i}' hem {seen[i]} hem {bid} grubunda")
            seen[i] = bid
    text = HEADER
    for title, bid, ids in sections:
        text += f"\n# {title}\nblock.{bid} = {wrap(ids)}\n"
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"{len(seen)} blok, {len(sections)} grup yazıldı -> {OUT}")


if __name__ == "__main__":
    main()
