<h1 align="center">startpage.nvim</h1>
<p align="center">
  <img src="screenshot.png"/>
</p>

Simple startpage for Neovim. If you want something that is highly customizable,
use something else, e.g. [dashboard-nvim](https://github.com/nvimdev/dashboard-nvim).
The startpage provides shortcuts to `oldfiles` with icons loaded from
[nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons).
Requires Neovim 0.10.0 or later.

```lua
require 'startpage'.setup{
    recent_files_header = "  Recent files",
    oldfiles_count = 7,
    default_icon = '', -- Must be blankspace or a glyph
    -- The keys in this table will cancel out of the startpage and be sent
    -- as they would normally.
    passed_keys = { 'i', 'o', 'p', 'P' }
}
```


