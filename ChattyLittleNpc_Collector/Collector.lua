-- Collector.lua - Sets up the recorded-data tables when this module loads.
--
-- This load-on-demand addon owns the data the player has recorded:
--   ChattyLittleNpc_NpcInfoDB[locale][npcId]   (layout: Core/CollectedData.lua)
--   ChattyLittleNpc_UnitInfoDB[locale][unitId]
--   ChattyLittleNpc_UnknownRaceModelsDB[fileId] (layout: Core/NpcRaceLookup.lua)
-- They are saved in SavedVariables\ChattyLittleNpc_Collector.lua.
--
-- Versions up to 3.7 kept them in the main addon as NpcInfoDB, UnitInfoDB and
-- UnknownRaceModelsDB. The main .toc still declares those names so older data
-- is not lost; the first time this module loads, it moves that data here and
-- clears the old globals, so ChattyLittleNpc.lua no longer saves a copy.

local ADDON_NAME = ...

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local CollectedData = CLN.CollectedData

--- Moves one table the main addon used to save into its new home, then clears
--- the old global.
---@param newName string global saved by this module
---@param oldName string global the main addon used to save
---@param merge fun(dst: table, src: table): integer  copies src into dst, returns the key count
---@return integer moved  how many top-level keys were copied in
local function adopt(newName, oldName, merge)
    if type(_G[newName]) ~= "table" then _G[newName] = {} end
    local old = _G[oldName]
    if type(old) ~= "table" then return 0 end

    local moved = merge(_G[newName], old)
    _G[oldName] = nil
    return moved
end

--- Merge for tables keyed by id with no locale level: what dst already has wins.
local function mergeById(dst, src)
    local moved = 0
    for key, value in pairs(src) do
        if dst[key] == nil then
            dst[key] = value
        elseif type(dst[key]) == "table" and type(value) == "table" then
            CollectedData.FillMissing(dst[key], value)
        end
        moved = moved + 1
    end
    return moved
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    local locale = CLN.locale or GetLocale()
    local function mergeText(dst, src) return CollectedData.MoveInto(dst, src, locale) end
    local npcs = adopt("ChattyLittleNpc_NpcInfoDB", "NpcInfoDB", mergeText)
    local units = adopt("ChattyLittleNpc_UnitInfoDB", "UnitInfoDB", mergeText)
    local models = adopt("ChattyLittleNpc_UnknownRaceModelsDB", "UnknownRaceModelsDB", mergeById)
    if (npcs + units + models) > 0 then
        CLN.Logger:info(string.format(
            "Collected data moved to ChattyLittleNpc_Collector.lua (%d NPC and %d object/item locale tables, %d unknown race models)",
            npcs, units, models), false, CLN.Utils.LogCategories.misc)
    end

    -- Data saved by a module from before the locale-first layout, if any
    CollectedData.MigrateTable(ChattyLittleNpc_NpcInfoDB, locale)
    CollectedData.MigrateTable(ChattyLittleNpc_UnitInfoDB, locale)

    CLN.NpcDialogTracker:GatherTooltipInfo()
    CLN.NpcDialogTracker.ready = true
end)
