---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class Utils
local Utils = {}
CLN.Utils = Utils

-- Centralized log categories
Utils.LogCategories = {
    camera = "camera",
    framing = "framing",
    projection = "projection",
    host = "host",
    loader = "loader",
    modelFrame = "modelFrame",
    fsm = "fsm",
    animation = "animation",
    emotes = "emotes",
    ui = "ui",
    misc = "misc",
}

local function isValidCategory(cat)
    if not cat or cat == "" then return false end
    for k, v in pairs(Utils.LogCategories) do
        if v == cat then return true end
    end
    return false
end

Utils._warnedMissingCategory = Utils._warnedMissingCategory or false
local function normalizeCategory(cat)
    if isValidCategory(cat) then return cat end
    -- If missing/unknown, warn once and route to 'misc'
    if not Utils._warnedMissingCategory then
        Utils._warnedMissingCategory = true
    -- Route through centralized logger; captured by LogsWindow; no chat mirroring
    if CLN and CLN.Logger then CLN.Logger:warn("Log category missing/unknown; please use Utils.LogCategories.*. Defaulting to 'misc'.", false, Utils.LogCategories.misc) end
    end
    return Utils.LogCategories.misc
end

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
    if CLN and CLN.Logger then CLN.Logger:info("Table is nil.", false, self.LogCategories.misc) end
        return
    end

    if (not indent) then
        indent = 0
    end

    for k, v in pairs(t) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if (type(v) == "table") then
            if CLN and CLN.Logger then CLN.Logger:info(formatting, false, self.LogCategories.misc) end
            self.PrintTable(v, indent + 1)
        else
            if CLN and CLN.Logger then CLN.Logger:info(formatting .. tostring(v), false, self.LogCategories.misc) end
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
        return {}
    end

    local depersonalisedText =  CLN.Utils:CleanText(text)
    local hash = CLN.MD5:GenerateHash(npcId .. depersonalisedText)

    local depersonalisedText2 =  CLN.Utils:CleanTextV2(text)
    local hash2 = CLN.MD5:GenerateHash(npcId .. depersonalisedText2)

    local hashes = {hash, hash2}
    return hashes
end

--- Log debug messages to console
-- @param text The debug message to log.
function Utils:LogDebug(text)
    if not (CLN and CLN.Logger) then return end
    if CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
        CLN.Logger:debug(text, false, self.LogCategories.debug)
    end
end

--- Log animation debug messages to console
-- @param text The animation debug message to log.
-- Log animation debug messages with optional category
-- Usage:
--   Utils:LogAnimDebug("camera", "message") -- categorized
--   Utils:LogAnimDebug("message")             -- legacy, uncategorized
function Utils:LogAnimDebug(a, b)
    local hasCat = (b ~= nil)
    local category = hasCat and tostring(a) or nil
    local text = hasCat and tostring(b) or tostring(a)
    -- Enforce category usage
    category = normalizeCategory(category)
    if not self:ShouldLogAnimDebug(category) then return end
    if CLN and CLN.Logger then
        local catTag = category and ("[" .. category .. "] ") or ""
        CLN.Logger:debug(catTag .. text, false, category)
    end
end

-- Extended: Log animation debug with an optional session tag for per-model filtering
-- Usage:
--   Utils:LogAnimDebugEx("camera", "message", sessionId)
--   Utils:LogAnimDebugEx("message", sessionId)
function Utils:LogAnimDebugEx(a, b, session)
    local category, text
    if b ~= nil then
        category = tostring(a)
        text = tostring(b)
    else
        category = nil
        text = tostring(a)
        session = b -- when called as (text, session)
    end
    -- Enforce category usage
    category = normalizeCategory(category)
    if not self:ShouldLogAnimDebug(category) then return end
    local sessTag = session and ("[sess:" .. tostring(session) .. "] ") or ""
    local catTag = category and ("[" .. category .. "] ") or ""
    if CLN and CLN.Logger then
        CLN.Logger:debug(catTag .. sessTag .. text, false, category)
    end
end

--- Helper function to check if animation debug logging is enabled
-- @return boolean true if animation debug logging is enabled
-- Check if animation debug logging is enabled for an optional category
function Utils:ShouldLogAnimDebug(category)
    if not (CLN and CLN.db and CLN.db.profile and CLN.db.profile.debugMode and CLN.db.profile.debugAnimations) then
        return false
    end
    -- Normalize/validate category; uncategorized maps to 'misc'
    category = normalizeCategory(category)
    local cats = CLN.db.profile.debugAnimCategories
    if not cats then
        -- No per-category filter configured; allow all when global flag is on
        return true
    end
    local function normalizeKey(k)
        return type(k) == "string" and string.lower(k) or k
    end
    -- Table map form: { camera=true, framing=true } or { all=true }
    if type(cats) == "table" then
        if cats.all == true then return true end
        return cats[normalizeKey(category)] == true
    end
    -- String form: "camera,framing,projection" or "all"
    if type(cats) == "string" then
        local s = string.lower(cats)
        if s == "all" then return true end
        for token in s:gmatch("[^,%s]+") do
            if token == string.lower(category) then return true end
        end
        return false
    end
    -- Unknown type: default allow
    return true
end

--- Determines whether a string is null or empty.
--- Mimics C#'s string.IsNullOrEmpty() behavior.
-- @param str The string to test.
-- @return boolean true if the string is nil or empty; otherwise, false.
function Utils:IsNilOrEmpty(str)
    return str == nil or str == ""
end

--- Gets the path to a non-quest voiceover file based on the provided parameters.
--- @param npcId number The ID of the NPC.
--- @param type string The type of sound (e.g., "gossip", "item").
--- @param hashes table The text associated with the voiceover.
--- @param gender string The gender of the NPC (e.g., "male", "female").
--- @return string|nil result The path to the voiceover file if found, otherwise false.
function Utils:GetPathToNonQuestFile(npcId, type, hashes, gender)
    if not npcId or not type then
        return nil
    end

    if not hashes or #hashes == 0 then
        return nil
    end
    local fileName = ""
    local fileNameWithGender = ""

    local addonsFolderPath = "Interface\\AddOns\\"
    for _, hash in ipairs(hashes) do
        fileName = npcId .. "_" .. type .. "_" .. hash .. ".ogg"
        if (gender) then
            fileNameWithGender = npcId .. "_" .. type .. "_" .. hash .. "_" .. gender .. ".ogg"
        end

        for packName, packData in pairs(CLN.VoiceoverPacks) do
            ---@type string
            local path = addonsFolderPath .. packName .. "\\voiceovers\\"
            if (not CLN.Utils:IsNilOrEmpty(fileNameWithGender)
                and CLN.Utils:ContainsString(packData.Voiceovers, fileNameWithGender)) then
                CLN.Utils:LogDebug("Found voiceover file: " .. path .. fileNameWithGender)
                return path .. fileNameWithGender
            end

            if (CLN.Utils:ContainsString(packData.Voiceovers, fileName)) then
                CLN.Utils:LogDebug("Found voiceover file: " .. path .. fileName)
                return path .. fileName
            end
        end
    end

    return nil
end