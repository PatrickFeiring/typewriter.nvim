# typewriter.nvim

Efficiently write type annotations by expanding letters.

## What is typewriter.nvim?

## Getting started

Neovim v0.6.0 or later is required for typewriter.nvim to work properly.

### Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use "PatrickFeiring/typewriter.nvim"
```

Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'PatrickFeiring/typewriter.nvim'
```

## Integrate with other plugins

It is possible to setup typewriter.nvim to fallback to a snippet plugin when the type expansion fails, this way the generation of types works as a prioritized layer of 'snippets' atop the snippet engine. 

This is how you could achieve that effect, using LuaSnip as a fallback:

```lua
typewriter = prequire("typewriter.nvim")

local function t(str)
    return vim.api.nvim_replace_termcodes(str, true, true, true)
end

vim.api.nvim_set_keymap("i", "<Tab>", "", {
    expr = true,
    callback = function()
        if typewriter and typewriter.expandable() then
            return t("<Plug>typewriter-expand")
        elseif luasnip and luasnip.expandable() then
            return t("<Plug>luasnip-expand-snippet")
        else
            return t("<Tab>")
        end
    end,
})
```
