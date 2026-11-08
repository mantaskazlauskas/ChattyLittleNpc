-- Options/NativeVoicedNpcs.lua - Pausing for NPCs that have Blizzard voice lines.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Options = CLN.Options
local config = Options.config
local sections = CLN.OptionsDefinition.args

-- Resolve all known numeric IDs for an NPC name from baked-in and contribution DBs.
local function getKnownIdsForName(npcName)
    local ids = {}
    local baked = _G.KnownVoicedNpcsDB
    if baked and baked[npcName] and baked[npcName].ids then
        for _, id in ipairs(baked[npcName].ids) do ids[id] = true end
    end
    local contrib = _G.VoicedNpcContributions
    if contrib and contrib[npcName] and contrib[npcName].ids then
        for _, id in ipairs(contrib[npcName].ids) do ids[id] = true end
    end
    return ids
end

-- Remove an NPC name and its known IDs from a table (whitelist or dismissed).
local function removeNpcFromTable(tbl, npcName)
    if not tbl then return end
    tbl[npcName] = nil
    for id in pairs(getKnownIdsForName(npcName)) do
        tbl[id] = nil
    end
end

-- Add an NPC name and its known IDs to a table (whitelist or dismissed).
local function addNpcToTable(tbl, npcName)
    if not tbl then return end
    tbl[npcName] = true
    for id in pairs(getKnownIdsForName(npcName)) do
        tbl[id] = true
    end
end

-- ═══════════════════════════════════════════════════
-- NATIVE VOICED NPCS — Pause-for whitelist management
-- ═══════════════════════════════════════════════════
sections.NativeVoicedNpcs = {
    order = 85,
    type = 'group',
    name = 'Native Voiced NPCs',
    desc = 'Pause addon voiceovers when NPCs with Blizzard voice acting are speaking.',
    inline = true,
    args = {
        nativeVOMode = {
            order = 1,
            type = 'toggle',
            width = 'full',
            name = 'Pause for Voiced NPCs',
            desc = 'When enabled, the addon pauses its voiceover when an NPC from your '
                .. 'whitelist speaks with native voice acting.\n\n'
                .. 'To add NPCs automatically: pause playback while an NPC is speaking and a popup will ask if you want to remember that NPC.\n\n'
                .. 'To add NPCs manually: use the \'Add NPC by Name...\' button below.',
            get = function(info) return (CLN.db.profile.nativeVOMode or "off") ~= "off" end,
            set = function(info, value)
                CLN.db.profile.nativeVOMode = value and "whitelist" or "off"
                if value and CLN.MergeKnownVoicedNpcs then CLN:MergeKnownVoicedNpcs() end
                config:Refresh()
            end,
        },
        manageWhitelist = {
            order = 2,
            type = 'execute',
            name = function()
                local wl = CLN.db.profile.nativeVOWhitelist or {}
                local count = 0
                for k, v in pairs(wl) do
                    if v and type(k) == "string" then count = count + 1 end
                end
                return count > 0 and ('Manage Whitelist (' .. count .. ')…') or 'Manage Whitelist…'
            end,
            desc = 'Open the whitelist window to add or remove NPCs.',
            func = function()
                if CLN.WhitelistWindow then CLN.WhitelistWindow:Open() end
            end,
        },
        neverAskHeader = {
            order = 5,
            type = 'header',
            name = function()
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                local count = 0
                for k, v in pairs(dismissed) do
                    if v and type(k) == "string" then count = count + 1 end
                end
                return count > 0 and ('Never Ask (' .. count .. ')') or 'Never Ask'
            end,
            hidden = function()
                if (CLN.db.profile.nativeVOMode or "off") == "off" then return true end
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                for k, v in pairs(dismissed) do
                    if v and type(k) == "string" then return false end
                end
                return true
            end,
        },
        neverAskEmpty = {
            order = 6,
            type = 'description',
            name = "No NPCs dismissed.",
            hidden = function()
                if (CLN.db.profile.nativeVOMode or "off") == "off" then return true end
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                for k, v in pairs(dismissed) do
                    if v and type(k) == "string" then return true end
                end
                return false
            end,
        },
        neverAskList = {
            order = 7,
            type = 'multiselect',
            name = '',
            desc = 'Uncheck to move NPC back to Pause For.',
            width = 'full',
            values = function()
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                local sorted = {}
                for k, v in pairs(dismissed) do
                    if v and type(k) == "string" then sorted[#sorted + 1] = k end
                end
                table.sort(sorted)
                local result = {}
                for _, name in ipairs(sorted) do result[name] = name end
                return result
            end,
            get = function(info, key)
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                return dismissed[key] == true
            end,
            set = function(info, key, value)
                if not value then
                    removeNpcFromTable(CLN.db.profile.nativeVODismissed, key)
                    if not CLN.db.profile.nativeVOWhitelist then CLN.db.profile.nativeVOWhitelist = {} end
                    addNpcToTable(CLN.db.profile.nativeVOWhitelist, key)
                end
            end,
            hidden = function()
                if (CLN.db.profile.nativeVOMode or "off") == "off" then return true end
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                for k, v in pairs(dismissed) do
                    if v and type(k) == "string" then return false end
                end
                return true
            end,
        },
        neverAskClear = {
            order = 8,
            type = 'execute',
            name = 'Clear All Dismissed',
            desc = 'Re-enable popups for all dismissed NPCs.',
            func = function()
                CLN.db.profile.nativeVODismissed = {}
                CLN.Logger:info("Cleared Never Ask list.", false, CLN.Utils.LogCategories.loader)
            end,
            hidden = function()
                if (CLN.db.profile.nativeVOMode or "off") == "off" then return true end
                local dismissed = CLN.db.profile.nativeVODismissed or {}
                for k, v in pairs(dismissed) do
                    if v and type(k) == "string" then return false end
                end
                return true
            end,
        },
    },
}
