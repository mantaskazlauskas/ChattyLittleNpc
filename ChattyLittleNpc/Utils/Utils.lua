---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

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

-- Canonical quest phase constants (file-name safe short codes)
Utils.QuestPhases = {
    DESC = "Desc",      -- Quest description / detail
    PROG = "Prog",      -- Quest progress / in-progress
    COMP = "Comp",      -- Quest completion / turn-in
}

-- Fast lookup set for canonical values
local _phaseSet = {
    ["Desc"] = true,
    ["Prog"] = true,
    ["Comp"] = true,
}

-- Mapping of legacy / verbose inputs to canonical short codes
local _phaseAliases = {
    DESCRIPTION = "Desc", DETAIL = "Desc", DETAILS = "Desc", DESC = "Desc",
    PROGRESS = "Prog", PROG = "Prog",
    COMPLETE = "Comp", COMPLETION = "Comp", COMP = "Comp",
}

--- Normalize an arbitrary quest phase string to canonical short code.
---@param phase string|nil
---@return string canonicalPhase Normalized (Desc|Prog|Comp) or original if unknown
function Utils:NormalizeQuestPhase(phase)
    if not phase or type(phase) ~= "string" then return phase end
    -- Preserve existing canonical inputs quickly
    if _phaseSet[phase] then return phase end
    local up = string.upper(phase)
    local mapped = _phaseAliases[up]
    if mapped then return mapped end
    return phase -- unknown; caller may still attempt playback (will likely miss file)
end

--- Determine if a phase is one of the canonical short codes.
---@param phase string|nil
---@return boolean
function Utils:IsCanonicalQuestPhase(phase)
    return _phaseSet[phase] == true
end

--- Validate & optionally warn for a phase string.
---@param phase string|nil
---@param original string|nil Original before normalization (for context)
function Utils:ValidateQuestPhase(phase, original)
    if _phaseSet[phase] then return true end
    if CLN and CLN.Logger then
        local msg = "Unexpected quest phase '" .. tostring(original or phase) .. "' (normalized='" .. tostring(phase) .. "')."
        CLN.Logger:warn(msg, false, self.LogCategories.loader)
    end
    return false
end

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

--- Safely retrieves and parses a unit's GUID, handling tainted/secret values.
--- @param unit string The unit identifier (e.g., "target", "npc", "player", "mouseover")
--- @return string|nil unitGuid The GUID string if successfully retrieved and not tainted, nil otherwise
--- @return string|nil unitType The type of unit ("Creature", "Vehicle", "GameObject", etc.), nil if unavailable
--- @return number|nil unitId The numeric ID of the unit (for creatures, vehicles, game objects), nil if unavailable
function Utils:GetSecureUnitGuid(unit)
    local unitGuid = UnitGUID(unit)
    if not unitGuid then
        return nil, nil, nil
    end

    -- Check if the GUID is tainted/secret
    -- issecurevariable returns false if the variable is tainted
    if issecurevariable("unitGuid") == false then
        return nil, nil, nil
    end

    -- Use pcall to safely parse the GUID
    local success, unitType, unitId = pcall(function()
        local t = select(1, strsplit("-", unitGuid))
        local id = nil
        if (t == "Creature" or t == "Vehicle" or t == "GameObject") then
            local idString = select(6, strsplit("-", unitGuid))
            id = tonumber(idString)
        end
        return t, id
    end)

    if success then
        return unitGuid, unitType, unitId
    else
        return nil, nil, nil
    end
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

--- Safely call SetPropagateKeyboardInput on a frame, avoiding protected/taint scenarios.
--- This guards against the ADDON_ACTION_BLOCKED errors when Blizzard marks the API
--- protected for certain frames (e.g., chat edit boxes) or during combat.
---@param frame Frame|nil The frame to modify
---@param propagate boolean|nil Whether to propagate keyboard input (defaults false)
---@return boolean success True if the call succeeded
function Utils:SafeSetPropagateKeyboardInput(frame, propagate)
    if not frame or type(frame) ~= "table" then return false end
    -- Hard opt-in flag; default OFF to avoid tainting the API at all.
    local allowed = CLN and CLN.db and CLN.db.profile and CLN.db.profile.allowKeyPropagation
    if not allowed then
        if CLN and CLN.Logger and CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
            local fname = (frame.GetName and frame:GetName()) or "<unnamed>"
            CLN.Logger:debug("SafeSetPropagateKeyboardInput suppressed (allowKeyPropagation not enabled) on "..fname, false, self.LogCategories.ui)
        end
        return false
    end
    local fn = frame.SetPropagateKeyboardInput
    if type(fn) ~= "function" then return false end
    local want = propagate and true or false
    local fname = (frame.GetName and frame:GetName()) or ""
    -- Skip dangerous frames regardless of opt-in
    if fname:find("^ChatFrame%d+EditBox") then return false end
    local ok, err = pcall(fn, frame, want)
    if not ok then
        if CLN and CLN.Logger then
            CLN.Logger:warn("SetPropagateKeyboardInput failed: " .. tostring(err), false, self.LogCategories.ui)
        end
        return false
    end
    return true
end
