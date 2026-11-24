-- Collector.lua - Loads the ChattyLittleNpc_Collector module on demand.
--
-- Recording dialog text (NpcDialogTracker and the collected-text tables) lives
-- in a separate load-on-demand addon, so players who don't record never load
-- it or its saved variables. It is loaded at login when 'Track NPC Dialog Data'
-- is on, and as soon as the box is ticked. An addon cannot be unloaded: after
-- the box is unticked it stays loaded, but Active() returns nil so nothing more
-- is recorded.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class Collector
local Collector = {}
CLN.Collector = Collector

Collector.ADDON_NAME = "ChattyLittleNpc_Collector"

local loadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn

--- Says in chat that one of the load-on-demand modules (collector, tools) is
--- not available, and what to do about it. Shared with src/Tools.lua.
---@param addonName string
---@param reason string|nil LoadAddOn's reason code (DISABLED, MISSING, ...), or
---  "NOT_READY" when the addon loaded but one of its files raised an error
---@param consequence string what the player loses, e.g. "Can't record NPC dialog"
function CLN:WarnAddonNotLoaded(addonName, reason, consequence)
    local message
    if reason == "NOT_READY" then
        message = string.format(
            "%s: %s loaded but failed to start. Check for a Lua error at login, or reinstall Chatty Little NPC.",
            consequence, addonName)
    else
        -- ADDON_DISABLED, ADDON_MISSING, ... are the client's own descriptions
        local why = reason and _G["ADDON_" .. reason] or reason or "unknown reason"
        message = string.format(
            "%s: %s could not be loaded (%s). Enable it in the AddOns list, or reinstall Chatty Little NPC.",
            consequence, addonName, tostring(why))
    end
    CLN.Logger:warn(message, true, CLN.Utils.LogCategories.misc)
end

--- True once the module has loaded and set up its tables.
---@return boolean
function Collector:IsLoaded()
    local tracker = CLN.NpcDialogTracker
    return tracker ~= nil and tracker.ready == true
end

--- The NpcDialogTracker to record into, or nil when recording is off or the
--- module is not loaded.
---@return NpcDialogTracker|nil
function Collector:Active()
    local profile = CLN.db and CLN.db.profile
    if not (profile and profile.logNpcTexts) then return nil end
    if not self:IsLoaded() then return nil end
    return CLN.NpcDialogTracker
end

--- Loads the module if it is not loaded yet.
---@return boolean loaded
---@return string|nil reason  why it could not be loaded (LoadAddOn's reason code)
function Collector:Load()
    if self:IsLoaded() then return true end
    if not loadAddOn then return false, "UNAVAILABLE" end

    local loaded, reason = loadAddOn(self.ADDON_NAME)
    if loaded and self:IsLoaded() then return true end
    return false, reason or "NOT_READY"
end

--- Loads the module when recording is on. Says in chat when it can't, since
--- recording would otherwise silently do nothing.
function Collector:LoadIfEnabled()
    local profile = CLN.db and CLN.db.profile
    if not (profile and profile.logNpcTexts) then return end

    local ok, reason = self:Load()
    if ok then return end
    CLN:WarnAddonNotLoaded(self.ADDON_NAME, reason, "Can't record NPC dialog")
end

return Collector
