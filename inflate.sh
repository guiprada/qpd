#!/usr/bin/env bash
# inflate.sh
# Creates a new LÖVE2D project from the qpd template.
#
# Usage:
#   ./inflate.sh <target_dir>

set -e

TARGET="$1"
if [ -z "$TARGET" ]; then
    echo "Usage: ./inflate.sh <target_dir>"
    echo ""
    echo "Creates a new LÖVE2D / qpd project at <target_dir>."
    exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"

echo "Inflating qpd project to: $TARGET"

# Copy template scaffolding
mkdir -p "$TARGET"
cp -r "$SRC/template/." "$TARGET/"

# Copy qpd library into project/qpd/
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
    cp -r "$SRC/$ITEM" "$TARGET/qpd/"
done

echo ""
echo "Done! Your new project is at: $TARGET"
echo ""
echo "To run:"
echo "  cd $TARGET"
echo "  love ."
echo ""
echo "Tip: to use qpd as a git submodule instead of a copy:"
echo "  git init $TARGET"
echo "  cd $TARGET"
echo "  git submodule add https://github.com/guiprada/qpd qpd"
