---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local Utils = {}

ChattyLittleNpc.Utils = Utils

--- Cleans the provided text by removing unwanted characters or formatting.
-- @param text The string to be cleaned.
function Utils:CleanText(text)
    text = text:gsub("\n\n", " ")
    text = text:gsub("\r\n", " ")
    text = text:gsub("<HTML>", "")
    text = text:gsub("</HTML>", "")
    text = text:gsub("<BODY>", "")
    text = text:gsub("</BODY>", "")
    text = text:gsub("<BR/>", "")
    text = text:gsub("<p>", "")
    text = text:gsub("</p>", "")
    text = text:gsub("<p align=\"center\">", "")
    text = text:gsub(UnitName("player"), "Hero")
    text = text:gsub(UnitClass("player"), "Hero")
    text = text:gsub(UnitRace("player"), "Hero")
    return text
end

--[[
    Prints the contents of a table in a readable format.
    
    @param t table: The table to be printed.
    @param indent number: The indentation level for nested tables (optional).
]]
function Utils:PrintTable(t, indent)
    if not t then
        ChattyLittleNpc:Print("Table is nil.")
        return
    end

    if not indent then indent = 0 end
    for k, v in pairs(t) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if type(v) == "table" then
            ChattyLittleNpc:Print(formatting)
            self.PrintTable(v, indent + 1)
        else
            ChattyLittleNpc:Print(formatting, tostring(v))
        end
    end
end