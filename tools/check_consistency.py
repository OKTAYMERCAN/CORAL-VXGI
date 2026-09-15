"""
CORAL VXGI - tutarlılık denetimi
=================================
settings.glsl, shaders.properties ve lang dosyalarının birbiriyle uyumlu
olup olmadığını Iris'in kurallarıyla kontrol eder:
  - her ayar menüde bir sayfada mı, menüdeki her ayar kodda var mı
  - açık/kapalı ayarlar #ifdef kaydında mı (yoksa Iris gizler)
  - varsayılan değer listede mi, listede çift boşluk var mı
  - her ayarın iki dilde de adı ve açıklaması var mı
KULLANIM:  python tools/check_consistency.py
"""
import re, sys, os
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders"))
settings = open(f"{ROOT}/lib/settings.glsl", encoding="utf-8").read()
props = open(f"{ROOT}/shaders.properties", encoding="utf-8").read()
errors = []

# ---- options in settings.glsl (Iris rules)
numeric, booleans = {}, set()
CONST_OPTS = {"shadowMapResolution", "shadowDistance", "sunPathRotation"}
for line in settings.split("\n"):
    m = re.match(r'^\s*(//)?\s*#define\s+(\w+)\s*(//.*)?$', line)
    if m:
        booleans.add(m.group(2)); continue
    m = re.match(r'^\s*#define\s+(\w+)\s+(\S+)\s*//(.*)$', line)
    if m:
        name, default, comment = m.groups()
        lb = comment.find("["); rb = comment.find("]", lb)
        if lb == -1 or rb == -1:
            errors.append(f"{name}: numeric define without [values]"); continue
        vals = comment[lb + 1:rb].split(" ")
        if "" in vals: errors.append(f"{name}: double space in value list")
        if default not in vals: errors.append(f"{name}: default {default} not in list")
        numeric[name] = vals
        continue
    m = re.match(r'^\s*const\s+\w+\s+(\w+)\s*=\s*([^;]+);\s*//\s*\[([^\]]*)\]', line)
    if m and m.group(1) in CONST_OPTS:
        numeric[m.group(1)] = m.group(3).split(" ")
# ignore include guard
booleans.discard("INCLUDE_SETTINGS")
all_opts = set(numeric) | booleans

# ---- booleans must be referenced with #ifdef/#ifndef in the same logical file
refs = set(re.findall(r'#if(?:n)?def\s+(\w+)', settings))
for b in booleans:
    if b not in refs: errors.append(f"boolean {b} not referenced by #ifdef (Iris will hide it)")

# ---- properties: flatten continuations, collect screen/slider/profile references
flat = re.sub(r'\\\n\s*', ' ', props)
screen_items, screens_defined, links, sliders, profile_opts = set(), set(), set(), set(), set()
for line in flat.split("\n"):
    line = line.strip()
    if line.startswith("#") or "=" not in line: continue
    key, val = [x.strip() for x in line.split("=", 1)]
    toks = val.split()
    if key == "screen" or (key.startswith("screen.") and not key.endswith(".columns")):
        if key != "screen": screens_defined.add(key[7:])
        for t in toks:
            if t in ("<empty>", "<profile>", "*"): continue
            if t.startswith("["): links.add(t[1:-1])
            else: screen_items.add(t)
    elif key == "sliders":
        sliders.update(toks)
    elif key.startswith("profile."):
        for t in toks:
            profile_opts.add(t.lstrip("!").split("=")[0])

for s in links - screens_defined: errors.append(f"screen link [{s}] has no screen.{s} definition")
for o in screen_items - all_opts: errors.append(f"menu item {o} is not an option in settings.glsl")
for o in all_opts - screen_items: errors.append(f"option {o} is not placed on any menu page")
for o in sliders - set(numeric): errors.append(f"slider {o} is not a numeric option")
for o in profile_opts - all_opts: errors.append(f"profile uses unknown option {o}")

# ---- lang files
def load_props(path):
    d = {}
    for raw in open(path, encoding="utf-8").read().split("\n"):
        if not raw or raw.startswith("#") or raw.startswith("!"): continue
        k, v = raw.split("=", 1)
        d[k] = v
    return d
langs = {c: load_props(f"{ROOT}/lang/{c}.lang") for c in ("en_us", "tr_tr")}
en, tr = langs["en_us"], langs["tr_tr"]
if set(en) != set(tr):
    errors.append(f"lang key mismatch: only en {sorted(set(en)-set(tr))[:5]} only tr {sorted(set(tr)-set(en))[:5]}")
for code, d in langs.items():
    for o in all_opts:
        if f"option.{o}" not in d: errors.append(f"{code}: missing option.{o}")
        if f"option.{o}.comment" not in d: errors.append(f"{code}: missing option.{o}.comment")
    for s in screens_defined:
        if f"screen.{s}" not in d: errors.append(f"{code}: missing screen.{s}")
    for k, v in d.items():
        stripped = v[2:] if v.startswith("\\ ") else v
        if "\\" in stripped: errors.append(f"{code}: stray backslash in {k}")
        if k.startswith("value."):
            _, name, val = k.split(".", 2)
            if name in numeric and val not in numeric[name]:
                errors.append(f"{code}: {k} names a value that is not in the list")
    # debug view names must cover all values
    for v in numeric.get("DEBUG_VIEW", []):
        if f"value.DEBUG_VIEW.{v}" not in d: errors.append(f"{code}: DEBUG_VIEW value {v} has no name")

# ---- block.properties kimlikleri materials.glsl ile uyuşuyor mu
mats = open(f"{ROOT}/lib/materials.glsl", encoding="utf-8").read()
known_ids = set(int(v) for v in re.findall(r'const int ID_\w+\s*=\s*(\d+)', mats))
emit_first = int(re.search(r'ID_EMIT_FIRST\s*=\s*(\d+)', mats).group(1))
emit_last = int(re.search(r'ID_EMIT_LAST\s*=\s*(\d+)', mats).group(1))
known_ids |= set(range(emit_first, emit_last + 1))
blocks_raw = open(f"{ROOT}/block.properties", encoding="utf-8").read()
# once satir devamlarini birlestir, sonra yorum satirlarini at
blocks_txt = "\n".join(l for l in re.sub(r'\\\n\s*', ' ', blocks_raw).split("\n")
                       if not l.strip().startswith("#"))
used_ids, seen_blocks = set(), {}
for m in re.finditer(r'^block\.(\d+)\s*=(.*?)$', blocks_txt, flags=re.M):
    bid = int(m.group(1)); used_ids.add(bid)
    for name in m.group(2).split():
        if name in seen_blocks:
            errors.append(f"block '{name}' hem {seen_blocks[name]} hem {bid} grubunda")
        seen_blocks[name] = bid
for bid in sorted(used_ids - known_ids):
    errors.append(f"block.{bid} materials.glsl icinde tanimli degil")

# ---- voxel hacmi ile shaders.properties goruntu boyutlari uyusuyor mu
vox = open(f"{ROOT}/lib/voxel.glsl", encoding="utf-8").read()
vol = dict(zip(re.findall(r'VOXEL_RANGE == (\d+)', vox) + ["128"],
               [tuple(x) for x in re.findall(r'ivec3\((\d+),\s*(\d+),\s*(\d+)\)', vox)]))
# maskImg voxel basina birden fazla 32 bitlik kelime tuttugu icin genisligi carpilidir
mask_words = set()
for r in re.findall(r'CUTOUT_MASK_RES\s+\d+\s*//\s*\[([^\]]*)\]', settings):
    for val in r.split():
        mask_words.add((int(val) * int(val)) // 32)
for img, dims in re.findall(r'image\.(\w+)\s*=\s*\S+(?:\s+\S+){4}\s+\S+\s+(\d+ \d+ \d+)', props):
    d = tuple(dims.split())
    if d in vol.values():
        continue
    if img == "maskImg" and any(
            (str(int(v[0]) * w), v[1], v[2]) == d for v in vol.values() for w in mask_words):
        continue
    errors.append(f"image.{img} boyutu {dims}, lib/voxel.glsl VOXEL_VOLUME degerlerinden hicbiriyle eslesmiyor")

# ---- ışık listesi kapasitesi görüntü genişliğiyle uyuşuyor mu
m = re.search(r'MAX_RT_LIGHTS\s*=\s*(\d+)', vox)
mi = re.search(r'image\.lightImg\s*=\s*\S+(?:\s+\S+){4}\s+\S+\s+(\d+)\s+(\d+)', props)
if m and mi:
    if int(m.group(1)) != int(mi.group(1)):
        errors.append(f"MAX_RT_LIGHTS={m.group(1)} ama image.lightImg genisligi {mi.group(1)}")
    if int(mi.group(2)) != 2:
        errors.append("image.lightImg yuksekligi 2 olmali (satir 0 konum, satir 1 renk)")

print(f"{len(seen_blocks)} blok, {len(used_ids)} grup")
print(f"{len(numeric)} numeric + {len(booleans)} boolean options, {len(screens_defined)} sub pages, {len(en)} lang keys")
if errors:
    print("HATALAR:"); [print("  -", e) for e in errors]; sys.exit(1)
print("Tutarlılık denetimi başarılı")
