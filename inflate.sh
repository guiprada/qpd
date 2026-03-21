#!/usr/bin/env bash
# inflate.sh
# Places qpd template files into an existing or new project directory.
# Non-destructive: never overwrites files that already exist.
#
# Usage:
#   ./inflate.sh <target_dir>

set -e

TARGET="$1"
if [ -z "$TARGET" ]; then
    echo "Usage: ./inflate.sh <target_dir>"
    echo ""
    echo "Places qpd framework files into <target_dir>."
    echo "Existing files are never overwritten."
    exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"

echo "Inflating qpd into: $TARGET"

# -n = no-clobber (never overwrite existing files)
mkdir -p "$TARGET"
cp -rn "$SRC/template/." "$TARGET/"

mkdir -p "$TARGET/qpd"
for ITEM in \
    ann.lua \
    ann_activation_functions.lua \
    ann_neat.lua \
    array.lua \
    camera.lua \
    collision.lua \
    color.lua \
    gamestate.lua \
    grid.lua \
    logger.lua \
    love_utils.lua \
    matrix.lua \
    point.lua \
    population_io.lua \
    qpd.lua \
    random.lua \
    table.lua \
    tilemap.lua \
    tilemap_view.lua \
    timer.lua \
    value.lua \
    archive \
    cells \
    services \
    templates \
    widgets
do
    cp -rn "$SRC/$ITEM" "$TARGET/qpd/"
done

echo ""
echo "Done. Existing files were not modified."
echo ""
echo "To run:"
echo "  cd $TARGET && love ."
