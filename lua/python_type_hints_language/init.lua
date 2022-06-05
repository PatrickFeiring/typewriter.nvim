local M = {}

local a = vim.api
local language_detection = require(
    "python_type_hints_language.language_detection"
)

local Node = {}
Node.__index = Node

-- A node in a type
--
-- @param n The number of children if the type is generic.
function Node.new(name, n, parent)
    n = n or 0

    local self = setmetatable({
        name = name,
        parent = parent,
        n = n,
        children = {},
    }, Node)

    return self
end

function Node:get_output()
    local text = self.name
    local marks = {}

    if self.n > 0 then
        text = text .. "["

        for i = 1, self.n do
            if i > 1 then
                text = text .. ", "
            end

            if i > #self.children then
                table.insert(marks, #text)
            else
                output = self.children[i]:get_output(child)

                for j = 1, #output.marks do
                    table.insert(marks, #text + output.marks[j])
                end

                text = text .. output.text
            end
        end

        text = text .. "]"
    end

    return {
        text = text,
        marks = marks,
    }
end

local function parse_char(char)
    if char == "A" then
        return Node.new("Any")
    elseif char == "b" then
        return Node.new("bool")
    elseif char == "f" then
        return Node.new("float")
    elseif char == "i" then
        return Node.new("int")
    elseif char == "s" then
        return Node.new("str")
    end

    if char == "d" then
        return Node.new("dict", 2)
    elseif char == "F" then
        return Node.new("Final", 1)
    elseif char == "I" then
        return Node.new("Iterator", 1)
    elseif char == "l" then
        return Node.new("list", 1)
    elseif char == "L" then
        -- We need to alter the algorithm before we allows an unlimited number of args
        return Node.new("Literal", 100) -- math.huge)
    elseif char == "O" or char == "o" then
        return Node.new("Optional", 1)
    elseif char == "t" then
        return Node.new("tuple", 100) --math.huge)
    elseif char == "U" or char == "u" then
        return Node.new("Union", 100) -- math.huge)
    end

    return nil
end

-- Parses a snippet into a type tree
--
-- Returns a valid tree, but it might miss some nodes, e.g. an Optional[] that
-- does not contain python type, but should have a user defined type instead,
-- and would thus not be expressible with this language.
--
-- @param snippet text
local function parse(snippet_text)
    if #snippet_text == 0 then
        return
    end

    local tree = nil
    local current = nil

    for i = 1, #snippet_text do
        local char = snippet_text:sub(i, i)
        local node = parse_char(char)

        if not node then
            return
        end

        if tree then
            -- Find placement in the tree, iteraitvely seeing if the current
            -- node has room for more children
            while #current.children >= current.n do
                current = current.parent

                if not current then
                    return nil
                end
            end

            node.parent = current
            table.insert(current.children, node)
            -- we always create a tree depth first, the go back up later, if
            -- there are no more space
            current = node
        else
            tree = node
            current = node
        end
    end

    return tree
end

local function get_stop(before_cursor, i)
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
        }
    elseif multi == ", " then
        return {
            prefix = "",
        }
    end

    return nil
end

local function get_expansion(before_cursor)
    for i = #before_cursor, 1, -1 do
        local stop = get_stop(before_cursor, i)

        if stop then
            return {
                start = i + 1,
                replace = i + 1,
                prefix = stop.prefix,
            }
        end

        if before_cursor:sub(i, i) == " " then
            for j = i - 1, 1, -1 do
                local char = before_cursor:sub(j, j)

                if char == " " then
                else
                    local stop = get_stop(before_cursor, j)

                    if stop then
                        return {
                            start = i + 1,
                            replace = j + 1,
                            prefix = stop.prefix,
                        }
                    else
                        return {
                            start = i + 1,
                            replace = j + 1,
                            prefix = ": ",
                        }
                    end
                end
            end
        end
    end

    return nil
end

local function get_expansion_result()
    if language_detection.from_treesitter_or_filetype() ~= "python" then
        return nil
    end

    local cursor = a.nvim_win_get_cursor(0)
    local bufnr = a.nvim_win_get_buf(0)
    local line = a.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], true)[1]
    local before_cursor = line:sub(0, cursor[2])

    local expansion = get_expansion(before_cursor)

    if not expansion then
        return nil
    end

    local tree = parse(before_cursor:sub(expansion.start, cursor[2]))

    return {
        bufnr = bufnr,
        cursor = cursor,
        tree = tree,
        expansion = expansion,
    }
end

function M.expandable()
    return get_expansion_result() ~= nil
end

function M.expand()
    local expansion_result = get_expansion_result()

    if expansion_result == nil then
        return nil
    end

    local bufnr = expansion_result.bufnr
    local cursor = expansion_result.cursor
    local expansion = expansion_result.expansion
    local tree = expansion_result.tree

    if tree ~= nil then
        local output = tree:get_output()

        a.nvim_buf_set_text(
            bufnr,
            cursor[1] - 1,
            expansion.replace - 1, -- From lua 1 based to 0 based
            cursor[1] - 1,
            cursor[2],
            { expansion.prefix .. output.text }
        )

        if #output.marks > 0 then
            col = expansion.replace - 1 + #expansion.prefix + output.marks[1]
        else
            col = expansion.replace - 1 + #expansion.prefix + #output.text
        end

        a.nvim_win_set_cursor(0, { cursor[1], col })

        return true
    end

    return false
end

return M
