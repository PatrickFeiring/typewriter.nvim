local M = {}

local a = vim.api
local ok_parsers, ts_parsers = pcall(require, "nvim-treesitter.parsers")

if not ok_parsers then
    ts_parsers = nil
end

function M.from_filetype()
    return vim.bo.filetype
end

function M.from_treesitter()
    local parser = ts_parsers.get_parser()

    if not parser then
        return nil
    end

    local cursor = a.nvim_win_get_cursor(0)

    tree = parser:language_for_range({
        cursor[1] - 1,
        cursor[2],
        cursor[1] - 1,
        cursor[2],
    })

    if not tree then
        return nil
    end

    return tree:lang()
end

-- Determines if position is located in a section with given language.
--
-- With treesitter, we can detect the language also of embedded code, e.g. a
-- python block in markdown.
--
-- If treesitter is not installed, we fall back to the file type.
--
function M.from_treesitter_or_filetype()
    local lang = M.from_treesitter()

    if not lang then
        return lang
    end

    return M.from_filetype()
end

return M
