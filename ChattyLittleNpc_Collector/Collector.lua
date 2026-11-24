-- Collector.lua - Sets up the collected-text tables when this module loads.
--
-- This load-on-demand addon owns the dialog text the player has recorded:
--   ChattyLittleNpc_NpcInfoDB[locale][npcId]   (layout: Core/CollectedData.lua)
--   ChattyLittleNpc_UnitInfoDB[locale][unitId]
-- They are saved in SavedVariables\ChattyLittleNpc_Collector.lua.
--
-- Versions up to 3.7 kept them in the main addon as NpcInfoDB and UnitInfoDB.
-- The main .toc still declares those names so older data is not lost; the
-- first time this module loads, it moves that data here and clears the old
-- globals, so ChattyLittleNpc.lua no longer saves a copy.

local ADDON_NAME = ...

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local CollectedData = CLN.CollectedData

--- Moves one table the main addon used to save into its new home, then clears
--- the old global.
---@param newName string global saved by this module
---@param oldName string global the main addon used to save
---@param locale string
---@return integer moved  how many top-level keys were copied in
local function adopt(newName, oldName, locale)
    if type(_G[newName]) ~= "table" then _G[newName] = {} end
    local old = _G[oldName]
    if type(old) ~= "table" then return 0 end

    local moved = CollectedData.MoveInto(_G[newName], old, locale)
    _G[oldName] = nil
    return moved
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    local locale = CLN.locale or GetLocale()
    local npcs = adopt("ChattyLittleNpc_NpcInfoDB", "NpcInfoDB", locale)
    local units = adopt("ChattyLittleNpc_UnitInfoDB", "UnitInfoDB", locale)
    if (npcs + units) > 0 then
        CLN.Logger:info(string.format(
            "Collected dialog text moved to ChattyLittleNpc_Collector.lua (%d NPC and %d object/item locale tables)",
            npcs, units), false, CLN.Utils.LogCategories.misc)
    end

    -- Data saved by a module from before the locale-first layout, if any
    CollectedData.MigrateTable(ChattyLittleNpc_NpcInfoDB, locale)
    CollectedData.MigrateTable(ChattyLittleNpc_UnitInfoDB, locale)

    CLN.NpcDialogTracker:GatherTooltipInfo()
    CLN.NpcDialogTracker.ready = true
end)
