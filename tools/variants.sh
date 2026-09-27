#!/bin/bash
# =====================================================================
#  tools/variants.sh - compile the pack with other settings
# =====================================================================
#  validate_glsl.py and mesa_check.py check the settings as they are in
#  lib/settings.glsl. This copies shaders/ and tools/ to a temporary folder,
#  applies a sed expression to the copy's lib/settings.glsl and runs both
#  compilers there, so the switches a change touches can be checked the other
#  way round without editing the pack.
#
#  usage: tools/variants.sh NAME 'SED EXPRESSION' ['PATTERN']
#    NAME     a label (also the folder name under $VARIANTS_DIR, default /tmp/coral_variants)
#    PATTERN  a text that must be found in settings.glsl after the edit (grep), to catch a
#             sed expression that matched nothing
#  examples:
#    tools/variants.sh pom 's/^\/\/ *#define MATERIAL_POM /#define MATERIAL_POM /' '^#define MATERIAL_POM '
#    tools/variants.sh labpbr12 's/^#define LABPBR_VERSION 0 /#define LABPBR_VERSION 1 /' 'LABPBR_VERSION 1 '
#  Several can run in parallel (append &, then wait). Needs glslangValidator and Mesa like
#  the two compilers themselves.
# =====================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
name="$1"; expr="$2"; pattern="${3:-}"
base="${VARIANTS_DIR:-/tmp/coral_variants}"
dir="$base/$name"
rm -rf "$dir" && mkdir -p "$dir" && cp -r "$ROOT/shaders" "$ROOT/tools" "$dir/"
sed -i "$expr" "$dir/shaders/lib/settings.glsl"
if [ -n "$pattern" ] && ! grep -q -- "$pattern" "$dir/shaders/lib/settings.glsl"; then
    echo "WARNING: pattern '$pattern' not found after the sed expression"
fi
cd "$dir"
g=$(python3 tools/validate_glsl.py 2>&1); gs=$?
m=$(python3 tools/mesa_check.py 2>&1); ms=$?
echo "== $name: glslang $(echo "$g" | tail -1) | mesa $(echo "$m" | tail -1)"
if [ $gs -ne 0 ]; then echo "$g" | grep -A6 "^ERROR" | head -30; fi
if [ $ms -ne 0 ]; then echo "$m" | grep -B2 -A6 -i "error\|fail" | head -30; fi
[ $gs -eq 0 ] && [ $ms -eq 0 ]
