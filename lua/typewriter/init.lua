local M = {}

local a = vim.api
local language_detection = require("typewriter.language_detection")
local parsers = require("typewriter.parsers")

CONTEXT_FUNCTION = 1

local function find_type_delimiter(before_cursor, i)
    local char = before_cursor:sub(i, i)

    if char == ":" then
        return {
            prefix = " ",
        }
    elseif char == "[" then
        return {
            prefix = "",
        }
    elseif char == ")" then
        return {
            prefix = " -> ",
            context = CONTEXT_FUNCTION,
        }
    elseif char == "," then
        return {
            prefix = " ",
        }
    end

    if i == 1 then
        return nil
    end

    local multi = before_cursor:sub(i - 1, i)

    if multi == "->" then
        return {
            prefix = " ",
            context = CONTEXT_FUNCTION,
        }
    elseif multi == ", " then
        return {
            prefix = "",
        }
    end

    return nil
end

local function find_suffix(line, cursor, context)
    if #line == 0 then
        return ""
    end

    if context == CONTEXT_FUNCTION then
        if not line:sub(cursor[2], #line):find(":") then
            return ":"
        end

        return ""
    else
        -- It's not completely straight forward to distinguish between the
        -- cases where we are defining a variable, and where we'd like to add
        -- = if it is missing, and the case where we are in a functions multi
        -- line argument list, and where we don't want to add it. This is a
        -- rudimentary check, we might consider moving this to treesitter
        -- later
        local after_cursor = line:sub(cursor[2] + 1, #line)
        local non_space_after_cursor = false

        for j = 1, #after_cursor do
            if after_cursor:sub(j, j) ~= " " then
                non_space_after_cursor = true
                break
            end
        end

        if non_space_after_cursor then
            return ""
        end

        if line:sub(1, 1) ~= " " then
            return " = "
        end

        return ""
    end
end

local function find_parse_target(line, cursor)
    local before_cursor = line:sub(0, cursor[2])

    -- If we hit a space we count that as a type delimiter regardless, and
    -- rather fill in the type delimiter ourselves
    local start_space = nil

    for i = #before_cursor, 1, -1 do
        if before_cursor:sub(i, i) == " " then
            if start_space == nil then
                start_space = i
            end
        else
            local delimiter = find_type_delimiter(before_cursor, i)

            if delimiter then
                local start_text = i

                if start_space ~= nil then
                    start_text = start_space
                end

                return {
                    replace_from = i + 1,
                    replace_to = cursor[2] + 1,
                    prefix = delimiter.prefix,
                    suffix = find_suffix(line, cursor, delimiter.context),
                    text = before_cursor:sub(start_text + 1, cursor[2]),
                }
            elseif start_space ~= nil then
                return {
                    replace_from = i + 1,
                    replace_to = cursor[2] + 1,
                    prefix = ": ",
                    suffix = find_suffix(line, cursor),
                    text = before_cursor:sub(start_space + 1, cursor[2]),
                }
            end
        end
    end

    return nil
end

local function parse()
    local lang = language_detection.from_treesitter_or_filetype()
    local parser = nil

    if lang == "python" then
        parser = parsers.PythonParser:new()
    elseif lang == "rust" then
        parser = parsers.RustParser:new()
    end

    if not parser then
        return
    end

    local cursor = a.nvim_win_get_cursor(0)
    local bufnr = a.nvim_win_get_buf(0)
    local line = a.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], true)[1]

    local target = find_parse_target(line, cursor)

    if not target then
        return nil
    end

    local tree = parser:parse(target.text)

    if not tree then
        return nil
    end

    return {
        bufnr = bufnr,
        line = cursor[1],
        replace_from = target.replace_from,
        replace_to = target.replace_to,
        prefix = target.prefix,
        tree = tree,
        suffix = target.suffix,
    }
end

function M.expandable()
    return parse() ~= nil
end

function M.expand()
    local result = parse()

    if result == nil then
        return nil
    end

    local output = result.tree:get_output()

    -- From lua 1 based to 0 based
    a.nvim_buf_set_text(
        result.bufnr,
        result.line - 1,
        result.replace_from - 1,
        result.line - 1,
        result.replace_to - 1,
        { result.prefix .. output.text .. result.suffix }
    )

    local col

    if #output.marks > 0 then
        col = result.replace_from
            - 1
            + #result.prefix
            + output.marks[1]
            + #result.suffix
    else
        col = result.replace_from
            - 1
            + #result.prefix
            + #output.text
            + #result.suffix
    end

    a.nvim_win_set_cursor(0, { result.line, col })

    return true
end

return M
