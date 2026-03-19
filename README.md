# qpd

A LÖVE2D framework / library.

## Structure

```
qpd/               ← library root (use as a git submodule or copy)
├── qpd.lua        ← main entry point: require "qpd" to get everything
├── camera.lua
├── collision.lua
├── color.lua
├── gamestate.lua
├── grid.lua
├── logger.lua
├── love_utils.lua
├── matrix.lua
├── point.lua
├── random.lua
├── table.lua
├── tilemap.lua
├── tilemap_view.lua
├── timer.lua
├── value.lua
├── ann.lua / ann_neat.lua   ← neural network / NEAT
├── cells/           ← color and sprite grid cells
├── services/        ← files, fonts, keymap, strings, window
├── templates/       ← gamestate template
├── widgets/         ← UI widgets (cell_box, file_picker, fps, ...)
├── template/        ← starter project scaffolding
└── inflate.lua      ← script to create a new project from the template
```

## Creating a new project

```bash
lua inflate.lua my_game
cd my_game
love .
```

inflate.lua copies the template scaffolding and a fresh copy of the qpd
library into `my_game/qpd/`.

## Using qpd as a git submodule

```bash
git submodule add https://github.com/guiprada/qpd qpd
```

Then in your project:

```lua
local qpd = require "qpd"
```

Or require individual modules:

```lua
local camera    = require "qpd.camera"
local gamestate = require "qpd.gamestate"
local qpd_table = require "qpd.table"
```
