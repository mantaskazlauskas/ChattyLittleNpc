-- NpcRaceLookup.lua - Infer an NPC's race from its model file
-- UnitRace() only works on players. Most humanoid NPCs reuse the playable-race
-- character models, so the model file ID tells us the race. Unknown model IDs
-- (creature-specific models, bosses, beasts) resolve to "" — better empty than wrong.
-- File IDs verified against the wowdev community listfile.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class NpcRaceLookup
local NpcRaceLookup = {}
CLN.NpcRaceLookup = NpcRaceLookup

local RACE_BY_MODEL_FILE_ID = {
    -- Human
    [119940] = "Human", [119563] = "Human",                    -- humanmale.m2 / humanfemale.m2
    [1011653] = "Human", [1000764] = "Human",                  -- _hd
    -- Orc (Mag'har orcs share these models)
    [121287] = "Orc", [121087] = "Orc",
    [917116] = "Orc", [949470] = "Orc",
    -- Dwarf
    [118355] = "Dwarf", [118135] = "Dwarf",
    [878772] = "Dwarf", [950080] = "Dwarf",
    -- Night Elf
    [120791] = "Night Elf", [120590] = "Night Elf",
    [974343] = "Night Elf", [921844] = "Night Elf",
    -- Undead
    [121768] = "Undead", [121608] = "Undead",
    [959310] = "Undead", [997378] = "Undead",
    -- Tauren
    [122055] = "Tauren", [121961] = "Tauren",
    [968705] = "Tauren", [986648] = "Tauren",
    -- Gnome
    [119159] = "Gnome", [119063] = "Gnome",
    [900914] = "Gnome", [940356] = "Gnome",
    -- Troll
    [122560] = "Troll", [122414] = "Troll",
    [1022938] = "Troll", [1018060] = "Troll",
    -- Blood Elf
    [117170] = "Blood Elf", [116921] = "Blood Elf",
    [1100087] = "Blood Elf", [1100258] = "Blood Elf",
    -- Draenei
    [117721] = "Draenei", [117437] = "Draenei",
    [1005887] = "Draenei", [1022598] = "Draenei",
    -- Goblin
    [119376] = "Goblin", [119369] = "Goblin",
    -- Worgen
    [307454] = "Worgen", [307453] = "Worgen",
    -- Pandaren
    [535052] = "Pandaren", [589715] = "Pandaren",
    -- Allied races
    [1814471] = "Nightborne", [1810676] = "Nightborne",
    [1630218] = "Highmountain Tauren", [1630402] = "Highmountain Tauren",
    [1734034] = "Void Elf", [1733758] = "Void Elf",
    [1620605] = "Lightforged Draenei", [1593999] = "Lightforged Draenei",
    [1839042] = "Lightforged Draenei", [1825438] = "Lightforged Draenei", -- _sdr
    [1630447] = "Zandalari Troll", [1662187] = "Zandalari Troll",
    [1900779] = "Zandalari Troll", [1894572] = "Zandalari Troll",         -- _sdr
    [1721003] = "Kul Tiran", [1886724] = "Kul Tiran",
    [1890765] = "Dark Iron Dwarf", [1890763] = "Dark Iron Dwarf",
    [1890761] = "Vulpera", [1890759] = "Vulpera",
    [2622502] = "Mechagnome", [2564806] = "Mechagnome",
    [4395382] = "Dracthyr", [4220448] = "Dracthyr", [4207724] = "Dracthyr", -- incl. dragon form
    [5548261] = "Earthen", [5548259] = "Earthen",
    [5422149] = "Haranir", [5422147] = "Haranir",
    -- Non-playable races with dedicated character models
    [117412] = "Broken", [117400] = "Broken",
    [118653] = "Fel Orc", [118652] = "Fel Orc",
    [118798] = "Forest Troll",
    [232863] = "Ice Troll",
    [120294] = "Naga", [120263] = "Naga",
    [233878] = "Taunka",
    [122738] = "Tuskarr",
    [122815] = "Vrykul",
}

local probeFrame

-- Lazy-create a hidden off-screen PlayerModel used solely to read model file IDs.
local function getProbe()
    if probeFrame then return probeFrame end
    local ok, frame = pcall(CreateFrame, "PlayerModel", "CLN_RaceProbe", UIParent)
    if not (ok and frame) then return nil end
    frame:SetSize(1, 1)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100) -- off-screen
    frame:SetAlpha(0)
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    frame:Hide()
    probeFrame = frame
    return frame
end

--- Get the model file ID currently used by a unit, or nil if unavailable.
---@param unit string
---@return number|nil fileId
---@return number|nil displayId Creature display ID, when the client exposes it
function NpcRaceLookup:GetUnitModelFileID(unit)
    if not (UnitExists and UnitExists(unit)) then return nil end
    local probe = getProbe()
    if not (probe and probe.GetModelFileID) then return nil end

    probe:Show()
    local fileId, displayId
    if pcall(probe.SetUnit, probe, unit) then
        local ok, fid = pcall(probe.GetModelFileID, probe)
        if ok and type(fid) == "number" and fid > 0 then
            fileId = fid
        end
        if probe.GetDisplayInfo then
            local okD, did = pcall(probe.GetDisplayInfo, probe)
            if okD and type(did) == "number" and did > 0 then
                displayId = did
            end
        end
    end
    pcall(probe.ClearModel, probe)
    probe:Hide()

    if not displayId and UnitCreatureDisplayID then
        local okU, did = pcall(UnitCreatureDisplayID, unit)
        if okU and type(did) == "number" and did > 0 then
            displayId = did
        end
    end
    return fileId, displayId
end

-- Unknown model IDs seen while collecting, labeled by hand in the Race Model Manager.
-- UnknownRaceModelsDB[fileId] = { npcId, name, displayId, creatureType, count, race, ignored }
local function getUnknownDB()
    if not UnknownRaceModelsDB then UnknownRaceModelsDB = {} end
    return UnknownRaceModelsDB
end

--- Race for a model file ID: built-in table first, then manual labels. "" when unknown.
---@param fileId number
---@return string race
function NpcRaceLookup:GetRaceForFileID(fileId)
    if not fileId then return "" end
    local race = RACE_BY_MODEL_FILE_ID[fileId]
    if race then return race end
    local entry = getUnknownDB()[fileId]
    if entry and not entry.ignored and entry.race and entry.race ~= "" then
        return entry.race
    end
    return ""
end

--- Infer a unit's race from its model. Returns "" when the model is not a known race model.
---@param unit string
---@return string race
---@return number|nil fileId The model file ID, when it could be read
---@return number|nil displayId The creature display ID, when it could be read
function NpcRaceLookup:GetRaceFromModel(unit)
    local fileId, displayId = self:GetUnitModelFileID(unit)
    return self:GetRaceForFileID(fileId), fileId, displayId
end

--- True when the file ID is in the built-in table (not a manual label).
---@param fileId number
---@return boolean
function NpcRaceLookup:IsBuiltIn(fileId)
    return RACE_BY_MODEL_FILE_ID[fileId] ~= nil
end

--- Record a model file ID that did not resolve to a race. One entry per file ID.
---@param fileId number
---@param info table { npcId, name, displayId, creatureType }
function NpcRaceLookup:RecordUnknown(fileId, info)
    if not fileId or RACE_BY_MODEL_FILE_ID[fileId] then return end
    local db = getUnknownDB()
    local entry = db[fileId]
    if not entry then
        entry = { count = 0, race = "" }
        db[fileId] = entry
        if CLN.Logger then
            CLN.Logger:debug("Unknown race model file ID " .. fileId .. " (" .. tostring(info and info.name) .. ")", false, CLN.Utils.LogCategories.misc)
        end
    end
    entry.count = (entry.count or 0) + 1
    if info then
        -- Keep the first NPC seen with this model; fill gaps from later sightings
        entry.npcId = entry.npcId or info.npcId
        entry.name = entry.name or info.name
        entry.displayId = entry.displayId or info.displayId
        entry.creatureType = entry.creatureType or info.creatureType
    end
end

--- All recorded unknown models as a sorted list of { fileId = n, ...entry }.
---@return table
function NpcRaceLookup:GetUnknownList()
    local list = {}
    for fileId, entry in pairs(getUnknownDB()) do
        if type(fileId) == "number" and not RACE_BY_MODEL_FILE_ID[fileId] then
            table.insert(list, { fileId = fileId, entry = entry })
        end
    end
    table.sort(list, function(a, b) return a.fileId < b.fileId end)
    return list
end
