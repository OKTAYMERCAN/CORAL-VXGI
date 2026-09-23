"""Consistency check: settings.glsl <-> shaders.properties <-> lang/en_us.lang."""
import os, re, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders"))
errors = []
DERIVED = {"RT_REFLECTIONS", "SSR_FALLBACK"}   # derived from REFLECTION_MODE inside settings.glsl

settings = open(f"{ROOT}/lib/settings.glsl", encoding="utf-8").read()
props    = open(f"{ROOT}/shaders.properties", encoding="utf-8").read()
lang     = open(f"{ROOT}/lang/en_us.lang", encoding="utf-8").read()

# 1) numeric options: is the default in the value list
num = {}
for m in re.finditer(r"^#define (\w+)\s+(\S+)\s*//\s*\[([^\]]*)\]", settings, flags=re.M):
    num[m.group(1)] = m.group(3).split()
    if m.group(2) not in num[m.group(1)]:
        errors.append(f"{m.group(1)}: default {m.group(2)} not in list")
for m in re.finditer(r"^const \w+ (\w+)\s*=\s*([^;]+);\s*//\s*\[([^\]]*)\]", settings, flags=re.M):
    num[m.group(1)] = m.group(3).split()
    if m.group(2).strip() not in num[m.group(1)]:
        errors.append(f"{m.group(1)}: default {m.group(2).strip()} not in list")

# 2) boolean options and their #ifdef registration
bools = set(re.findall(r"^(?://)?#define (\w+)\s*(?://(?!\s*\[).*)?$", settings, flags=re.M))
bools = {b for b in bools if b not in num and not b.startswith("INCLUDE_")}  # include guards are not options
registered = set(re.findall(r"^#ifdef (\w+)\s*\n#endif", settings, flags=re.M))
for b in bools:
    if b in DERIVED: continue
    if b not in registered:
        errors.append(f"boolean {b} not referenced by #ifdef (Iris will hide it)")

# 3) is every option placed on a menu page
# join the line continuations (\\) first
joined = props.replace("\\\n", " ")
menu_items = set()
for line in joined.split("\n"):
    st = line.strip()
    if st.startswith("screen") or st.startswith("sliders") or st.startswith("profile."):
        menu_items |= set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", st.split("=", 1)[-1]))
all_opts = set(num) | bools
for o in all_opts:
    if o in DERIVED: continue
    if o not in menu_items:
        errors.append(f"option {o} is not placed on any menu page")
# The names of [PAGE] links are not options; they are collected from the screen.X = lines
pages = set(re.findall(r"^screen\.(\w+)", props, flags=re.M)) | {"screen"}
for it in menu_items:
    if not it.isupper(): continue
    if it in all_opts or it in pages: continue
    if it.startswith(("ABOUT", "DEBUG_HELP")): continue
    if it in ("LOW", "MEDIUM", "HIGH", "ULTRA"): continue
    errors.append(f"menu item {it} is not an option in settings.glsl")

# 3b) DEAD SETTING: shown in the menu but never read anywhere in the shader code.
#     Changing such a setting does nothing; it is the most annoying kind of bug
#     a user can run into (CAUSTICS_SPEED was like this for a while).
#     ABOUT_* and DEBUG_HELP_* are fake options on purpose: they only exist to
#     show text in the menu.
code_text = []
for dp, _, fns in os.walk(ROOT):
    for fn in fns:
        if fn == "settings.glsl": continue
        if os.path.splitext(fn)[1] in (".glsl", ".vsh", ".fsh"):
            with open(os.path.join(dp, fn), encoding="utf-8", errors="ignore") as f:
                code_text.append(f.read())
code_text = "\n".join(code_text)
#     These really do something but never appear in the GLSL code:
#       REFLECTION_MODE  -> turned into RT_REFLECTIONS/SSR_FALLBACK inside settings.glsl
#       sunPathRotation  -> read by Iris itself; it rotates the path of the sun
CONSUMED_ELSEWHERE = {"REFLECTION_MODE", "sunPathRotation"}
for o in sorted(all_opts):
    if o in DERIVED or o in CONSUMED_ELSEWHERE: continue
    if o.startswith(("ABOUT", "DEBUG_HELP")): continue
    if not re.search(r"\b" + re.escape(o) + r"\b", code_text):
        errors.append(f"option {o} is in the menu but never read by any shader (dead setting)")

# 3c) PROFILE LINES: every token must be either 'OPTION=value' (the value must be
#     in the list) or, for a boolean, 'OPTION' / '!OPTION'. A mixed form such as
#     '!SHADOW_SAMPLES=4' was silently ignored by Iris: the Low profile never
#     actually lowered the shadow samples.
IRIS_BUILTIN = {"shadowMapResolution", "shadowDistance", "sunPathRotation"}
for line in joined.split("\n"):
    st = line.strip()
    if not st.startswith("profile."): continue
    pname, body = st.split("=", 1)
    for tok in body.split():
        if tok.startswith("profile."): continue      # inherits another profile
        if "=" in tok:
            k, v = tok.split("=", 1)
            if k.startswith("!"):
                errors.append(f"{pname.strip()}: '{tok}' is invalid ('!' only turns a boolean off)")
            elif k in num:
                if v not in num[k]:
                    errors.append(f"{pname.strip()}: {k}={v} is not in the option's value list")
            elif k not in IRIS_BUILTIN:
                errors.append(f"{pname.strip()}: {k} is not a numeric option")
        else:
            k = tok.lstrip("!")
            if k not in bools:
                errors.append(f"{pname.strip()}: {k} is not a boolean option")

# 4) language file
langkeys =set(k.split("=")[0] for k in lang.split("\n") if "=" in k and not k.startswith("#"))
for o in all_opts:
    if o in DERIVED: continue
    if f"option.{o}" not in langkeys: errors.append(f"en_us: missing option.{o}")
    if f"option.{o}.comment" not in langkeys: errors.append(f"en_us: missing option.{o}.comment")

# 4b) Is the description REALLY written: an empty or few-word description does not
#     tell the user in the menu what the option is for. ABOUT_* lines are free text.
langvals = {}
for line in lang.split("\n"):
    if "=" in line and not line.strip().startswith("#"):
        k, v = line.split("=", 1)
        langvals[k.strip()] = v.strip()
MIN_COMMENT = 40
for o in sorted(all_opts):
    if o in DERIVED or o.startswith(("ABOUT", "DEBUG_HELP")): continue
    c = langvals.get(f"option.{o}.comment")
    if c is None: continue          # missing, already reported above
    if len(c) < MIN_COMMENT:
        errors.append(f"en_us: option.{o}.comment is too thin to be useful ({len(c)} chars): {c!r}")
# 4c) LABELS MUST BE DISTINGUISHABLE FROM EACH OTHER.
#     If two options show the same name, the user cannot tell which one they are
#     changing ('Block Light Strength' and 'Block Light Strength (RT)' got mixed up
#     like this; 'Edge Sharpness' was the exact name of two different options).
#     Labels are compared ignoring color codes, text in parentheses and letter case.
def _norm_label(v):
    v = re.sub("\u00a7.", "", v).lower()
    v = re.sub(r"\(.*?\)", "", v)
    return re.sub(r"[^a-z0-9]+", " ", v).strip()
_seen = {}
for o in sorted(all_opts):
    if o in DERIVED or o.startswith(("ABOUT", "DEBUG_HELP")): continue
    lab = langvals.get(f"option.{o}")
    if lab is None: continue
    key = _norm_label(lab)
    if key in _seen:
        errors.append(f"en_us: '{lab}' ({o}) and '{langvals[f'option.{_seen[key]}']}' ({_seen[key]}) look the same")
    else:
        _seen[key] = o
# 4d) The name of one NUMERIC option must not be the start or the end of another's,
#     such as 'Light Falloff' and 'Block Light Falloff', or 'Green' and 'Green Power'.
#     Reading the shorter one, the user may think they are changing the other.
#     (An on/off switch and its own setting - 'Bloom' and 'Bloom Strength' - are one
#     family and are not counted.)
_numlabels = {o: _norm_label(langvals[f"option.{o}"]) for o in num
              if f"option.{o}" in langvals and not o.startswith(("ABOUT", "DEBUG_HELP"))}
for a, la in sorted(_numlabels.items()):
    for b, lb in sorted(_numlabels.items()):
        if a != b and (lb.startswith(la + " ") or lb.endswith(" " + la)):
            errors.append(f"en_us: the name '{langvals[f'option.{a}']}' ({a}) appears inside '{langvals[f'option.{b}']}' ({b}); they can be confused")
# The pack is English only: no Turkish characters may be left in the menu
for k, v in langvals.items():
    if set("\u00e7\u011f\u0131\u015f\u00f6\u00fc\u00c7\u011e\u0130\u015e\u00d6\u00dc") & set(v):
        errors.append(f"en_us: {k} still contains Turkish characters")
for o, vals in num.items():
    for v in vals:
        pass  # value labels are optional

# 5) LANGUAGE GUARD: the whole project (code comments, tools, documentation) is English.
#    a) no Turkish letters anywhere; b) no common Turkish words written in plain ASCII
#       (older comments were often typed without Turkish letters);
#    c) shader sources are pure 7-bit ASCII - some drivers mis-read other bytes even in comments.
#    The word list below is detection data; this file is skipped when scanning.
TURKISH_LETTERS = set("\u00e7\u011f\u0131\u015f\u00f6\u00fc\u00c7\u011e\u0130\u015e\u00d6\u00dc")
TURKISH_WORDS = set("""ve bir bu icin ile degil olarak gibi yok cunku sonra yalnizca sadece kadar
olan olur olmaz eder yapar burada simdi eger veya hic cok ayar ayari ayarlar deger degeri renk isik
golge yuzey dunya gore ornek sayi satir dosya varsayilan kapali acik doku icinde uzerinde tum butun
yeni eski boylece zaten artik ancak fakat bunu buna bunun onun nasil neden yani ornegin hesapla
kullanilir kullanici oyuncu gunes blok bloklar isin yansima gerekir gerekli gereken yerine""".split())
PROJECT = os.path.dirname(ROOT)
SELF = os.path.abspath(__file__)
SHADER_EXT = (".glsl", ".vsh", ".fsh", ".csh", ".gsh", ".properties")
for sub, exts in (("shaders", SHADER_EXT + (".lang",)), ("tools", (".py",)), ("docs", (".md", ".txt"))):
    for dp, _, fns in os.walk(os.path.join(PROJECT, sub)):
        for fn in sorted(fns):
            path = os.path.join(dp, fn)
            if not fn.endswith(exts) or os.path.abspath(path) == SELF: continue
            rel = os.path.relpath(path, PROJECT)
            for no, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
                if TURKISH_LETTERS & set(line):
                    errors.append(f"{rel}:{no}: Turkish letters (the project is English only)")
                    continue
                # whole tokens only: '0x846ca68bu' or 'rb_bu' are code, not words
                words = [w for w in re.findall(r"[A-Za-z0-9_]+", re.sub(r"[A-Za-z]+'[A-Za-z]+", " ", line))
                         if w.isalpha()]
                hits = sorted({w for w in words if w.lower() in TURKISH_WORDS})
                if hits:
                    errors.append(f"{rel}:{no}: looks Turkish ({', '.join(hits[:4])}): {line.strip()[:70]}")
                if fn.endswith(SHADER_EXT) and any(ord(c) > 127 for c in line):
                    errors.append(f"{rel}:{no}: non-ASCII character in a shader source")

print(f"{len(num)} numeric + {len(bools)} boolean options, {len(langkeys)} lang keys")
if errors:
    print("ERRORS:")
    for e in errors: print("  -", e)
    sys.exit(1)
print("Consistency check passed")
