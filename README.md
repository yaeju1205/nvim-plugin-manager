# nvim-plugin-manager
nvim-plugin-manager is simple plugin manager for neovim

## Usage
### windows
Add `~/AppData/Local/nvim/lua/plugin-manager.lua` and put nvim-plugin-manager code

### linux, macos
Add `~/.config/nvim/lua/plugin-manager.lua` and put nvim-plugin-manager code

### api
```lua
local plugin_manager = require("plugin-manager")
plugin_manager.install("https://github.com/yaeju1205/warp.nvim")(function()
    local warp = require("warp")
    ...
end)

plugin_manager.upgrade("warp.nvim")
```

or
```lua
vim.plugin.install("https://github.com/yaeju1205/warp.nvim")(function()
    local warp = require("warp")
    ...
end)
```

