---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class Utils
local Utils = {}
CLN.Utils = Utils

-- Cached CleanText patterns (built once, reused)
local _cleanPatternsBuilt = false
local _cleanPatterns = {}     -- { {find, replace}, ... } for CleanText
local _cleanV2Patterns = {}   -- { {find, replace}, ... } for CleanTextV2
local _cleanHtmlPatterns = {  -- shared HTML cleanup patterns
    {"\r\n", " "},
    {"<HTML>", ""}, {"</HTML>", ""},
    {"<BODY>", ""}, {"</BODY>", ""},
    {"<BR/>", ""}, {"<p>", ""}, {"</p>", ""},
    {'<p align="center">', ""},
}

local function buildCleanPatterns()
    if _cleanPatternsBuilt then return end
    local name = UnitName("player")
    if not name or name == "" or name == UNKNOWNOBJECT then return end
    local class = select(1, UnitClass("player"))
    local race = select(1, UnitRace("player"))

    _cleanPatterns = {
        {name, "Hero"}, {name:lower(), "Hero"}, {name:upper(), "Hero"},
        {class, "Hero"}, {class:lower(), "Hero"}, {class:upper(), "Hero"},
        {race, "Hero"}, {race:lower(), "Hero"}, {race:upper(), "Hero"},
    }
    _cleanV2Patterns = {
        {name, "{name|" .. name .. "}"}, {name:lower(), "{name|" .. name:lower() .. "}"}, {name:upper(), "{name|" .. name:upper() .. "}"},
        {class, "{class|" .. class .. "}"}, {class:lower(), "{class|" .. class:lower() .. "}"}, {class:upper(), "{class|" .. class:upper() .. "}"},
        {race, "{race|" .. race .. "}"}, {race:lower(), "{race|" .. race:lower() .. "}"}, {race:upper(), "{race|" .. race:upper() .. "}"},
    }
    _cleanPatternsBuilt = true
end

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
    secrets = "secrets",
}

--- Session-level counters for secret-value encounters.
--- Callers of Desecret() can read these for telemetry/debug display.
Utils.SecretStats = {
    total   = 0,   -- Desecret() calls that detected a secret value
    blocked = 0,   -- times the value was truly inaccessible (returned nil)
}

--- Convert a WoW 12.0+ "secret value" into a normal Lua value safe for
--- comparison, boolean tests, table-key use, and string operations.
--- Returns the plain value when possible, or nil when the value is truly
--- inaccessible (e.g. during M+/PvP combat restrictions).
---@param val any
---@return any|nil plainValue
---@return boolean wasBlocked true when val was secret and could not be extracted
function Utils.Desecret(val)
    local t = type(val)
    if t ~= "string" and t ~= "number" then return val, false end
    -- Fast path: value is not secret at all (outside M+/PvP/combat contexts)
    if issecretvalue and not issecretvalue(val) then return val, false end
    -- Value is (or might be) secret — count it
    Utils.SecretStats.total = Utils.SecretStats.total + 1
    -- Attempt concatenation (allowed on secret strings/numbers per Blizzard docs).
    -- Use `if ok then` (not `if ok and plain then`) to avoid a truthiness test
    -- on the result, which would itself error if the result is still secret.
    local ok, plain = pcall(function() return "" .. val end)
    if ok then
        -- Concatenation can produce another secret string (tainted by our addon);
        -- verify the result is actually usable for comparison/branching.
        if issecretvalue and issecretvalue(plain) then
            Utils.SecretStats.blocked = Utils.SecretStats.blocked + 1
            return nil, true
        end
        if not issecretvalue then
            local canCompare = pcall(function() return plain == plain end)
            if not canCompare then
                Utils.SecretStats.blocked = Utils.SecretStats.blocked + 1
                return nil, true
            end
        end
        return plain, false
    end
    -- Concatenation failed — try string.format which is also listed as allowed
    ok, plain = pcall(string.format, "%s", val)
    if ok then
        if issecretvalue and issecretvalue(plain) then
            Utils.SecretStats.blocked = Utils.SecretStats.blocked + 1
            return nil, true
        end
        if not issecretvalue then
            local canCompare = pcall(function() return plain == plain end)
            if not canCompare then
                Utils.SecretStats.blocked = Utils.SecretStats.blocked + 1
                return nil, true
            end
        end
        return plain, false
    end
    -- Value is truly inaccessible
    Utils.SecretStats.blocked = Utils.SecretStats.blocked + 1
    return nil, true
end

--- Return a one-line summary of secret-value encounter stats for telemetry.
---@return string
function Utils.GetSecretReport()
    local s = Utils.SecretStats
    if s.total == 0 then return "Secrets: none encountered" end
    return string.format("Secrets: %d encountered, %d blocked (%.0f%% blocked)",
        s.total, s.blocked, (s.blocked / s.total) * 100)
end

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

-- Pre-built set for O(1) category validation
local _validCategorySet = {}
for _, v in pairs(Utils.LogCategories) do _validCategorySet[v] = true end

local function isValidCategory(cat)
    if not cat or cat == "" then return false end
    return _validCategorySet[cat] or false
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
    if not text or text == "" then return text or "" end
    buildCleanPatterns()
    for _, p in ipairs(_cleanPatterns) do
        text = text:gsub(p[1], p[2])
    end
    text = text:gsub("\n\n", " ")
    for _, p in ipairs(_cleanHtmlPatterns) do
        text = text:gsub(p[1], p[2])
    end
    return text
end

--- Cleans the provided text by removing unwanted characters or formatting.
-- @param text The string to be cleaned.
function Utils:CleanTextV2(text)
    if not text or text == "" then return text or "" end
    buildCleanPatterns()
    for _, p in ipairs(_cleanV2Patterns) do
        text = text:gsub(p[1], p[2])
    end
    for _, p in ipairs(_cleanHtmlPatterns) do
        text = text:gsub(p[1], p[2])
    end
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
            self:PrintTable(v, indent + 1)
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

-- Simple hash cache to avoid redundant MD5 computation for repeated NPC interactions
local _hashCache = {}
local _hashCacheSize = 0
local HASH_CACHE_MAX = 32

function Utils:GetHashes(npcId, text)
    if not npcId or not text then
        return {}
    end

    -- Check cache first
    local cacheKey = tostring(npcId) .. "|" .. text
    local cached = _hashCache[cacheKey]
    if cached then return cached end

    local depersonalisedText = CLN.Utils:CleanText(text)
    local hash = CLN.MD5:GenerateHash(npcId .. depersonalisedText)

    local depersonalisedText2 = CLN.Utils:CleanTextV2(text)
    local hash2 = CLN.MD5:GenerateHash(npcId .. depersonalisedText2)

    local hashes = {hash, hash2}

    -- Store in cache with simple eviction
    if _hashCacheSize >= HASH_CACHE_MAX then
        _hashCache = {}
        _hashCacheSize = 0
    end
    _hashCache[cacheKey] = hashes
    _hashCacheSize = _hashCacheSize + 1

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
                and packData._voiceoverIndex and packData._voiceoverIndex[fileNameWithGender]) then
                CLN.Utils:LogDebug("Found voiceover file: " .. path .. fileNameWithGender)
                return path .. fileNameWithGender
            end

            if (packData._voiceoverIndex and packData._voiceoverIndex[fileName]) then
                CLN.Utils:LogDebug("Found voiceover file: " .. path .. fileName)
                return path .. fileName
            end
        end
    end

    return nil
end

--- Estimate how long a spoken line of text takes.
--- ~75 WPM ≈ 12.9 chars/sec for English, +1.0 s buffer, scaled up by 1/10.
---@param text string|nil  The text to estimate duration for.
---@param minDuration number|nil  Floor clamp in seconds (default 2).
---@param maxDuration number|nil  Ceiling clamp in seconds (default unlimited).
---@return number seconds
function Utils.EstimateVODuration(text, minDuration, maxDuration)
    local floor = minDuration or 2
    local raw
    if not text or #text == 0 then
        raw = 3.0
    else
        raw = (#text / 12.9 + 1.0) * 1.1
    end
    if maxDuration then
        return math.max(floor, math.min(maxDuration, raw))
    end
    return math.max(floor, raw)
end

--- Estimate how long a sentence takes to READ (not hear).
--- ~200 WPM ≈ 20 chars/sec for English — roughly 3x faster than speech.
---@param sentence string|nil  The sentence to estimate reading duration for.
---@return number seconds
function Utils.EstimateReadDuration(sentence)
    if not sentence or #sentence == 0 then return 1.5 end
    return math.max(1.5, #sentence / 20)
end

--- Given an array of sentences and a 0-1 progress value, estimate which
--- sentence was being spoken at that point using character-count proportions.
---@param sentences string[]  Array of sentence strings.
---@param progress number     0-1 progress through the total text.
---@return number index       1-based index of the estimated current sentence.
function Utils.EstimateSentenceAtPosition(sentences, progress)
    if not sentences or #sentences == 0 then return 1 end
    if progress <= 0 then return 1 end
    if progress >= 1 then return #sentences end

    local totalChars = 0
    for i = 1, #sentences do
        totalChars = totalChars + #sentences[i]
    end
    if totalChars == 0 then return 1 end

    local targetChars = totalChars * progress
    local cumulative = 0
    for i = 1, #sentences do
        cumulative = cumulative + #sentences[i]
        if cumulative >= targetChars then
            return i
        end
    end
    return #sentences
end
