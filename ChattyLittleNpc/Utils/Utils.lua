---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class Utils
local Utils = {}
CLN.Utils = Utils

--- Cleans the provided text by removing unwanted characters or formatting.
--- Replacing player name, race and class with "Hero" so that it would be consistent across all players (for hash generation).
-- @param text The string to be cleaned.
function Utils:CleanText(text)
    text = text:gsub(UnitName("player"), "Hero")
    text = text:gsub(UnitClass("player"), "Hero")
    text = text:gsub(UnitRace("player"), "Hero")
    text = text:gsub(UnitName("player"):lower(), "Hero")
    text = text:gsub(UnitClass("player"):lower(), "Hero")
    text = text:gsub(UnitRace("player"):lower(), "Hero")
    text = text:gsub(UnitName("player"):upper(), "Hero")
    text = text:gsub(UnitClass("player"):upper(), "Hero")
    text = text:gsub(UnitRace("player"):upper(), "Hero")
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
    return text
end

--- Cleans the provided text by removing unwanted characters or formatting.
-- @param text The string to be cleaned.
function Utils:CleanTextV2(text)
    text = text:gsub(UnitName("player"), "{name|" .. UnitName("player") .. "}")
    text = text:gsub(UnitClass("player"), "{class|" .. UnitClass("player") .. "}")
    text = text:gsub(UnitRace("player"), "{race|" .. UnitRace("player") .. "}")
    text = text:gsub(UnitName("player"):lower(), "{name|" .. UnitName("player"):lower() .. "}")
    text = text:gsub(UnitClass("player"):lower(), "{class|" .. UnitClass("player"):lower() .. "}")
    text = text:gsub(UnitRace("player"):lower(), "{race|" .. UnitRace("player"):lower() .. "}")
    text = text:gsub(UnitName("player"):upper(), "{name|" .. UnitName("player"):upper() .. "}")
    text = text:gsub(UnitClass("player"):upper(),"{class|" .. UnitClass("player"):upper() .. "}")
    text = text:gsub(UnitRace("player"):upper(), "{race|" .. UnitRace("player"):upper() .. "}")
    text = text:gsub("<HTML>", "")
    text = text:gsub("</HTML>", "")
    text = text:gsub("<BODY>", "")
    text = text:gsub("</BODY>", "")
    text = text:gsub("<BR/>", "")
    text = text:gsub("<p>", "")
    text = text:gsub("</p>", "")
    text = text:gsub("<p align=\"center\">", "")
    return text
end

--[[
    Prints the contents of a table in a readable format.
    
    @param t table: The table to be printed.
    @param indent number: The indentation level for nested tables (optional).
]]
function Utils:PrintTable(t, indent)
    if (not t) then
        CLN:Print("Table is nil.")
        return
    end

    if (not indent) then
        indent = 0
    end

    for k, v in pairs(t) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if (type(v) == "table") then
            CLN:Print(formatting)
            self.PrintTable(v, indent + 1)
        else
            CLN:Print(formatting, tostring(v))
        end
    end
end

function Utils:ContainsString(table, searchString)
    for _, value in ipairs(table) do
        if value == searchString then
            return true
        end
    end
    return false
end

function Utils:GetHashes(npcId, text)
    if not npcId or not text then
        return nil
    end

    local depersonalisedText =  CLN.Utils:CleanText(text)
    local hash = CLN.MD5:GenerateHash(npcId .. depersonalisedText)

    local depersonalisedText2 =  CLN.Utils:CleanTextV2(text)
    local hash2 = CLN.MD5:GenerateHash(npcId .. depersonalisedText2)

    local hashes = {hash, hash2}
    return hashes
end

function Utils:LogDebug(text)
    if CLN.db.profile.debugMode then
        CLN:Print(text)
    end
end