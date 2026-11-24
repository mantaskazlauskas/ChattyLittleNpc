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

--- The window object when its file loaded fully (it has the method used to
--- open it), else nil. A file that errors part-way can leave the table set but
--- the method missing.
local function withMethod(object, method)
    return (object and object[method]) and object or nil
end

--- Show the window when hidden, hide it when shown (logs and debug windows).
local function toggleShown(window, frame)
    if not frame or not frame:IsShown() then window:Show() else window:Hide() end
end

-- Each window: the object its file creates (nil when that file failed to
-- load), and how to show or hide it.
local WINDOWS = {
    logs = {
        get = function() return withMethod(CLN.ReplayFrame.LogsWindow, "Show") end,
        toggle = function(LW) toggleShown(LW, LW._frame) end,
    },
    debug = {
        get = function() return withMethod(CLN.ReplayFrame.DebugWindow, "Show") end,
        toggle = function(DW) toggleShown(DW, DW.frame) end,
    },
    raceModels = {
        get = function() return withMethod(CLN.RaceModelManager, "Toggle") end,
        toggle = function(manager)
            -- The labels are saved by the collector; load it so they show even
            -- while recording is off (it only records when the box is ticked).
            -- Without it the window still opens, on labels not moved yet.
            -- Said once per session, not on every open and close.
            local ok, reason = CLN.Collector:Load()
            if not ok and not Tools._warnedCollector then
                Tools._warnedCollector = true
                CLN:WarnAddonNotLoaded(CLN.Collector.ADDON_NAME, reason, "Race model labels may be missing")
            end
            manager:Toggle()
        end,
    },
    portraitTuner = {
        get = function() return withMethod(CLN.PortraitTuner, "Toggle") end,
        toggle = function(tuner) tuner:Toggle() end,
    },
    itemProps = {
        get = function() return withMethod(CLN.ItemPropPicker, "Toggle") end,
        toggle = function(picker) picker:Toggle() end,
    },
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

    CLN:WarnAddonNotLoaded(self.ADDON_NAME, reason, "Can't open this window")
    return false
end

--- Loads the module if needed, then shows or hides one of its windows.
---@param window "logs"|"debug"|"raceModels"|"portraitTuner"|"itemProps"
function Tools:Toggle(window)
    local entry = WINDOWS[window]
    if not (entry and self:Load()) then return end

    -- LoadAddOn reports success even when one of the module's files raised an
    -- error while loading; that window is then missing.
    local object = entry.get()
    if not object then
        CLN:WarnAddonNotLoaded(self.ADDON_NAME, "NOT_READY", "Can't open this window")
        return
    end
    entry.toggle(object)
end

-- Slash commands for the module's windows (/clnmark stays in LogsBuffer.lua:
-- marking the log does not need the window)
SLASH_CLNLOGS1 = "/clnlogs"
SlashCmdList["CLNLOGS"] = function() Tools:Toggle("logs") end

SLASH_CLNDEBUG1 = "/clndebug"
SLASH_CLNDEBUG2 = "/clnmodel"
SlashCmdList["CLNDEBUG"] = function() Tools:Toggle("debug") end

return Tools
