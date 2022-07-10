local M = {}

local tree = require("typewriter.tree")

local Parser = {}
Parser.__index = Parser

function Parser.new()
    local self = setmetatable({}, Parser)

    return self
end

-- Parses a snippet into a type tree
--
-- Returns a valid tree, but it might miss some nodes, e.g. an Optional[]
-- that does not contain python type, but should have a user defined type
-- instead, and would thus not be expressible with this language.
function Parser:parse(text)
    if #text == 0 then
        return
    end

    local tree = nil
    local current = nil

    for i = 1, #text do
        local char = text:sub(i, i)
        local node = self:parse_char(char)

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

function Parser:parse_char(char)
    if char == "A" then
        return tree.Node.new("Any")
    elseif char == "b" then
        return tree.Node.new("bool")
    elseif char == "f" then
        return tree.Node.new("float")
    elseif char == "i" then
        return tree.Node.new("int")
    elseif char == "n" or char == "N" then
        -- Only makes sense in function return type, I guess, the rest is Optional
        return tree.Node.new("None")
    elseif char == "s" then
        return tree.Node.new("str")
    elseif char == "S" then
        return tree.Node.new("Self")
    end

    if char == "d" then
        return tree.Node.new("dict", 2)
    elseif char == "F" then
        return tree.Node.new("Final", 0, 1)
    elseif char == "I" then
        return tree.Node.new("Iterator", 1)
    elseif char == "l" then
        return tree.Node.new("list", 1)
    elseif char == "L" then
        return tree.Node.new("Literal", 1, math.huge)
    elseif char == "O" or char == "o" then
        return tree.Node.new("Optional", 1)
    elseif char == "t" then
        return tree.Node.new("tuple", 2, math.huge)
    elseif char == "U" or char == "u" then
        return tree.Node.new("Union", 2, math.huge)
    end

    return nil
end

M.Parser = Parser

return M
