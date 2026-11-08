-- Options/Developer.lua - Data collection and developer tools.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local sections = CLN.OptionsDefinition.args

-- ═══════════════════════════════════════════════
-- DATA COLLECTION — For community contributors
-- ═══════════════════════════════════════════════
sections.DataCollection = {
    order = 80,
    type = 'group',
    name = 'Data Collection',
    desc = 'Help the project by recording NPC dialog text for voiceover generation.',
    inline = true,
    args = {
        logNpcTexts = {
            order = 1,
            type = 'toggle',
            width = 'full',
            name = 'Track NPC Dialog Data',
            desc = 'Record NPC dialog text as you play for voiceover generation. Join our Discord if you want to contribute!',
            get = function(info) return CLN.db.profile.logNpcTexts end,
            set = function(info, value)
                CLN.db.profile.logNpcTexts = value
                if (not value) then
                    CLN.db.profile.printNpcTexts = false
                end
            end,
        },
        printNpcTexts = {
            order = 2,
            type = 'toggle',
            width = 'full',
            name = 'Log Collected Data to Chat',
            desc = 'Print collected NPC dialog data in the chat window as it is recorded.',
            disabled = function() return not CLN.db.profile.logNpcTexts end,
            get = function(info) return CLN.db.profile.printNpcTexts end,
            set = function(info, value) CLN.db.profile.printNpcTexts = value end,
        },
        overwriteExistingGossipValues = {
            order = 3,
            type = 'toggle',
            width = 'full',
            name = 'Overwrite Existing Data',
            desc = 'Replace previously collected dialog data when you talk to the same NPC again.',
            disabled = function() return not CLN.db.profile.logNpcTexts end,
            get = function(info) return CLN.db.profile.overwriteExistingGossipValues end,
            set = function(info, value) CLN.db.profile.overwriteExistingGossipValues = value end,
        },
    },
}

-- ═══════════════════════════════════════════════
-- DEVELOPER & DEBUG — For developers and testing
-- ═══════════════════════════════════════════════
sections.DeveloperDebug = {
    order = 90,
    type = 'group',
    name = 'Developer & Debug',
    desc = 'Diagnostic tools for addon developers and testers.',
    inline = true,
    args = {
        openLogsWindow = {
            order = 0,
            type = 'execute',
            name = 'Open Logs Window',
            desc = 'Open the debug logs viewer. Also accessible via /clnlogs.',
            func = function()
                local LW = CLN.ReplayFrame.LogsWindow
                if LW then
                    if not LW._frame or not LW._frame:IsShown() then LW:Show() else LW:Hide() end
                end
            end,
        },
        openDebugWindow = {
            order = 0.5,
            type = 'execute',
            name = 'Open Debug Window',
            desc = 'Open the model debug/inspection window. Also accessible via /clndebug.',
            func = function()
                local DW = CLN.ReplayFrame.DebugWindow
                if DW then
                    if not DW.frame or not DW.frame:IsShown() then DW:Show() else DW:Hide() end
                end
            end,
        },
        debugMode = {
            order = 1,
            type = 'toggle',
            width = 'full',
            name = 'Enable Debug Logging',
            desc = 'Enable debug messages. View them in the Logs window (/clnlogs) or enable chat mirroring below.',
            get = function(info) return CLN.db.profile.debugMode end,
            set = function(info, value)
                CLN.db.profile.debugMode = value
            end,
        },
        logToChat = {
            order = 2,
            type = 'toggle',
            width = 'full',
            name = 'Mirror Logs to Chat',
            desc = 'Print addon log messages (warnings, errors, info) in the chat window. The Logs window (/clnlogs) always captures everything regardless of this setting.',
            get = function(info) return CLN.db.profile.logToChat end,
            set = function(info, value)
                CLN.db.profile.logToChat = value
            end,
        },
        printMissingFiles = {
            order = 3,
            type = 'toggle',
            width = 'full',
            name = 'Log Missing Voiceover Files',
            desc = 'Show warnings when voiceover audio files are missing. Useful for finding gaps in voiceover packs.',
            disabled = function() return not CLN.db.profile.debugMode end,
            get = function(info) return CLN.db.profile.printMissingFiles end,
            set = function(info, value) CLN.db.profile.printMissingFiles = value end,
        },
        debugNoAnim = {
            order = 4,
            type = 'toggle',
            width = 'full',
            name = 'Freeze Animations',
            desc = 'Freeze all model and emote animations to debug camera framing.',
            disabled = function() return not CLN.db.profile.debugMode end,
            get = function(info) return CLN.db.profile.debugNoAnim end,
            set = function(info, value)
                CLN.db.profile.debugNoAnim = value
                CLN.ReplayFrame:SetNoAnimDebug(value)
                if CLN.ReplayFrame._UpdateModelOnUpdateHook then
                    CLN.ReplayFrame:_UpdateModelOnUpdateHook()
                end
            end,
        },
        debugAnimations = {
            order = 5,
            type = 'toggle',
            width = 'full',
            name = 'Animation Debug Logs',
            desc = 'Enable detailed animation and camera debug logs. Filter by category below.',
            disabled = function() return not CLN.db.profile.debugMode end,
            get = function(info) return CLN.db.profile.debugAnimations end,
            set = function(info, value) CLN.db.profile.debugAnimations = value end,
        },
        debugAnimCategories = {
            order = 6,
            type = 'select',
            width = 'double',
            name = 'Animation Log Filter',
            desc = 'Filter animation debug logs by category.',
            values = function()
                local C = CLN.Utils.LogCategories
                local values = {
                    all = 'All Categories',
                    none = 'None (Disable All)',
                }
                values[C.camera] = 'Camera Only'
                values[C.framing] = 'Framing Only'
                values[C.projection] = 'Projection Only'
                values[C.host] = 'Host/Backend Only'
                values[C.loader] = 'Loader Only'
                values[C.animation] = 'Animation Only'
                values[C.emotes] = 'Emotes Only'
                return values
            end,
            disabled = function()
                return not (CLN.db.profile.debugMode and CLN.db.profile.debugAnimations)
            end,
            get = function()
                local cats = CLN.db.profile.debugAnimCategories
                if cats == 'all' or not cats then return 'all' end
                if type(cats) == 'table' then
                    local count = 0
                    local lastCat = nil
                    for k, v in pairs(cats) do
                        if v then
                            count = count + 1
                            lastCat = k
                        end
                    end
                    if count == 0 then return 'none' end
                    if count == 1 then return lastCat end
                    return 'all'
                end
                return 'all'
            end,
            set = function(_, value)
                if value == 'all' then
                    CLN.db.profile.debugAnimCategories = 'all'
                elseif value == 'none' then
                    CLN.db.profile.debugAnimCategories = {}
                else
                    local cats = {}
                    cats[value] = true
                    CLN.db.profile.debugAnimCategories = cats
                end
            end,
        },
        openRaceModelManager = {
            order = 7.5,
            type = 'execute',
            name = 'Manage Unknown Race Models',
            desc = 'Label NPC models whose race could not be identified. Unknown models are collected while NPC text logging is enabled.',
            func = function()
                if CLN.RaceModelManager then CLN.RaceModelManager:Toggle() end
            end,
        },
    },
}
