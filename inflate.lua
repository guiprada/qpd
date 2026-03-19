#!/usr/bin/env lua
-- inflate.lua
-- Places qpd template files into an existing or new project directory.
-- Non-destructive: never overwrites files that already exist.
--
-- Usage:
--   lua inflate.lua <target_dir>

local target = arg[1]
if not target then
    io.write("Usage: lua inflate.lua <target_dir>\n\n")
    io.write("Places qpd framework files into <target_dir>.\n")
    io.write("Existing files are never overwritten.\n")
    os.exit(1)
end

local src = debug.getinfo(1, "S").source:match("@(.+/)[^/]+$") or "./"

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function run(cmd)
    local code = os.execute(cmd)
    if code ~= true and code ~= 0 then
        io.write("Command failed: " .. cmd .. "\n")
        os.exit(1)
    end
end

-- Copy a single file only if it does not exist at destination
local function copy_if_absent(src_path, dst_path)
    if not file_exists(dst_path) then
        run("cp " .. src_path .. " " .. dst_path)
    end
end

-- Recursively copy a directory, skipping files that already exist
local function copy_dir_if_absent(src_dir, dst_dir)
    run("mkdir -p " .. dst_dir)
    local handle = io.popen("find " .. src_dir .. " -type f")
    for src_file in handle:lines() do
        local rel = src_file:sub(#src_dir + 2)
        local dst_file = dst_dir .. "/" .. rel
        local dst_subdir = dst_file:match("(.+)/[^/]+$")
        if dst_subdir then run("mkdir -p " .. dst_subdir) end
        copy_if_absent(src_file, dst_file)
    end
    handle:close()
end

io.write("Inflating qpd into: " .. target .. "\n")

-- Template scaffolding
copy_dir_if_absent(src .. "template", target)

-- qpd library
local lib_items = {
    "ann.lua", "ann_activation_functions.lua", "ann_neat.lua",
    "array.lua", "camera.lua", "collision.lua", "color.lua",
    "gamestate.lua", "grid.lua", "logger.lua", "love_utils.lua",
    "matrix.lua", "point.lua", "population_io.lua", "qpd.lua",
    "random.lua", "table.lua", "tilemap.lua", "tilemap_view.lua",
    "timer.lua", "value.lua",
    "archive", "cells", "services", "templates", "widgets",
}
for _, item in ipairs(lib_items) do
    local src_path = src .. item
    local dst_path = target .. "/qpd/" .. item
    -- directories
    local handle = io.popen("test -d " .. src_path .. " && echo dir || echo file")
    local kind = handle:read("*l")
    handle:close()
    if kind == "dir" then
        copy_dir_if_absent(src_path, dst_path)
    else
        run("mkdir -p " .. target .. "/qpd")
        copy_if_absent(src_path, dst_path)
    end
end

io.write("\nDone. Existing files were not modified.\n")
io.write("\nTo run:\n  cd " .. target .. " && love .\n")
