-- Tools.lua - Opens the windows that live in the ChattyLittleNpc_Tools module.
--
-- The logs, model inspection, race model, portrait camera and book & letter
-- model windows are only needed when someone opens them, so they ship as a
-- load-on-demand addon. The buttons and slash commands below load it on first
-- use, then toggle the window.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class Tools
local Tools = {}
CLN.Tools = Tools

Tools.ADDON_NAME = "ChattyLittleNpc_Tools"

local loadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn

--- Show the window when hidden, hide it when shown (logs and debug windows).
local function toggleShown(window, frame)
    if not frame or not frame:IsShown() then window:Show() else window:Hide() end
end

local WINDOWS = {
    logs = function()
        local LW = CLN.ReplayFrame.LogsWindow
        toggleShown(LW, LW._frame)
    end,
    debug = function()
        local DW = CLN.ReplayFrame.DebugWindow
        toggleShown(DW, DW.frame)
    end,
    raceModels = function()
        -- The labels are saved by the collector; load it so they show even
        -- while recording is off (it only records when the box is ticked)
        CLN.Collector:Load()
        CLN.RaceModelManager:Toggle()
    end,
    portraitTuner = function() CLN.PortraitTuner:Toggle() end,
    itemProps = function() CLN.ItemPropPicker:Toggle() end,
}

--- Loads the module if it is not loaded yet. Says in chat when it can't.
---@return boolean loaded
function Tools:Load()
    if self.loaded then return true end

    local loaded, reason
    if loadAddOn then
        loaded, reason = loadAddOn(self.ADDON_NAME)
    else
        reason = "UNAVAILABLE"
    end
    if loaded then
        self.loaded = true
        return true
    end

    -- ADDON_DISABLED, ADDON_MISSING, ... are the client's own descriptions
    local why = reason and _G["ADDON_" .. reason] or reason or "unknown reason"
    CLN.Logger:warn(string.format(
        "Can't open this window: %s could not be loaded (%s). Enable it in the AddOns list, or reinstall Chatty Little NPC.",
        self.ADDON_NAME, tostring(why)), true, CLN.Utils.LogCategories.misc)
    return false
end

--- Loads the module if needed, then shows or hides one of its windows.
---@param window "logs"|"debug"|"raceModels"|"portraitTuner"|"itemProps"
function Tools:Toggle(window)
    local open = WINDOWS[window]
    if open and self:Load() then open() end
end

-- Slash commands for the module's windows (/clnmark stays in LogsBuffer.lua:
-- marking the log does not need the window)
SLASH_CLNLOGS1 = "/clnlogs"
SlashCmdList["CLNLOGS"] = function() Tools:Toggle("logs") end

SLASH_CLNDEBUG1 = "/clndebug"
SLASH_CLNDEBUG2 = "/clnmodel"
SlashCmdList["CLNDEBUG"] = function() Tools:Toggle("debug") end

return Tools
