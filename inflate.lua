#!/usr/bin/env lua
-- inflate.lua
-- Creates a new LÖVE2D project from the qpd template.
--
-- Usage:
--   lua inflate.lua <target_dir>
--
-- What it does:
--   1. Copies template/ contents into <target_dir>  (main.lua, gamestates/, entities/, data/, fonts/)
--   2. Copies the qpd library into <target_dir>/qpd/
--   3. Prints next steps

local target = arg[1]
if not target then
    io.write("Usage: lua inflate.lua <target_dir>\n\n")
    io.write("Creates a new LÖVE2D / qpd project at <target_dir>.\n")
    os.exit(1)
end

-- Resolve the directory containing this script
local src = debug.getinfo(1, "S").source:match("@(.+/)[^/]+$") or "./"

local function run(cmd)
    local code = os.execute(cmd)
    -- os.execute returns true/0 on success depending on Lua version
    if code ~= true and code ~= 0 then
        io.write("Command failed: " .. cmd .. "\n")
        os.exit(1)
    end
end

io.write("Inflating qpd project to: " .. target .. "\n")

-- Copy template scaffolding
run("mkdir -p " .. target)
run("cp -r " .. src .. "template/. " .. target .. "/")

-- Copy qpd library into project/qpd/
run("mkdir -p " .. target .. "/qpd")
local lib_items = {
    "ann.lua",
    "ann_activation_functions.lua",
    "ann_neat.lua",
    "array.lua",
    "camera.lua",
    "collision.lua",
    "color.lua",
    "gamestate.lua",
    "grid.lua",
    "logger.lua",
    "love_utils.lua",
    "matrix.lua",
    "point.lua",
    "population_io.lua",
    "qpd.lua",
    "random.lua",
    "table.lua",
    "tilemap.lua",
    "tilemap_view.lua",
    "timer.lua",
    "value.lua",
    "archive",
    "cells",
    "services",
    "widgets",
}
for _, item in ipairs(lib_items) do
    run("cp -r " .. src .. item .. " " .. target .. "/qpd/")
end

io.write("\nDone! Your new project is at: " .. target .. "\n")
io.write("\nTo run:\n")
io.write("  cd " .. target .. "\n")
io.write("  love .\n")
io.write("\nTip: to use qpd as a git submodule instead of a copy:\n")
io.write("  git init " .. target .. "\n")
io.write("  cd " .. target .. "\n")
io.write("  git submodule add https://github.com/guiprada/qpd qpd\n")
