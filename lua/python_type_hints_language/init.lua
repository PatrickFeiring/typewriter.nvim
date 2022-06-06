local M = {}

local a = vim.api
local language_detection = require(
    "python_type_hints_language.language_detection"
)

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

local Node = {}
Node.__index = Node

function Node.new(name, min_children, max_children, parent)
    min_children = min_children or 0
    max_children = max_children or min_children

    local self = setmetatable({
        name = name,
        min_children = min_children,
        max_children = max_children,
        parent = parent,
        children = {},
    }, Node)

    return self
end

function Node:get_output()
    local text = self.name
    local marks = {}

    if self.min_children > 0 or #self.children > 0 then
        text = text .. "["

        for i = 1, #self.children do
            if i > 1 then
                text = text .. ", "
            end

            output = self.children[i]:get_output(child)

            for j = 1, #output.marks do
                table.insert(marks, #text + output.marks[j])
            end

            text = text .. output.text
        end

        -- We should have more children, in the case were we could
        -- potentially have more children, we require the user to type ,
        -- explicitly
        if self.min_children > #self.children then
            if #self.children > 0 then
                text = text .. ", "
            end

            table.insert(marks, #text)
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
    elseif char == "n" or char == "N" then
        -- Only makes sense in function return type, I guess, the rest is Optional
        return Node.new("None")
    elseif char == "s" then
        return Node.new("str")
    elseif char == "S" then
        return Node.new("Self")
    end

    if char == "d" then
        return Node.new("dict", 2)
    elseif char == "F" then
        return Node.new("Final", 0, 1)
    elseif char == "I" then
        return Node.new("Iterator", 1)
    elseif char == "l" then
        return Node.new("list", 1)
    elseif char == "L" then
        return Node.new("Literal", 1, math.huge)
    elseif char == "O" or char == "o" then
        return Node.new("Optional", 1)
    elseif char == "t" then
        return Node.new("tuple", 2, math.huge)
    elseif char == "U" or char == "u" then
        return Node.new("Union", 2, math.huge)
    end

    return nil
end

-- Parses a snippet into a type tree
--
-- Returns a valid tree, but it might miss some nodes, e.g. an Optional[]
-- that does not contain python type, but should have a user defined type
-- instead, and would thus not be expressible with this language.
local function parse_target(target)
    if #target.text == 0 then
        return
    end

    local tree = nil
    local current = nil

    for i = 1, #target.text do
        local char = target.text:sub(i, i)
        local node = parse_char(char)

        if not node then
            return
        end

        if tree then
            -- Find placement in the tree, iteraitvely seeing if the current
            -- node has room for more children
            while #current.children >= current.max_children do
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

local function parse()
    if language_detection.from_treesitter_or_filetype() ~= "python" then
        return nil
    end

    local cursor = a.nvim_win_get_cursor(0)
    local bufnr = a.nvim_win_get_buf(0)
    local line = a.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], true)[1]

    local target = find_parse_target(line, cursor)

    if not target then
        return nil
    end

    local tree = parse_target(target)

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
