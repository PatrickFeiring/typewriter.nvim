local M = {}

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

M.Node = Node

return M
