-- Init.lua - Initialization handler
-- This file loads LAST and triggers addon initialization after all modules are loaded

local CLN = _G.ChattyLittleNpc

-- Create event frame for addon initialization
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", function(self, event, addonName)
    -- TEMP DIAGNOSTIC: record when saved data becomes visible (see Core/Print.lua)
    local diag = _G.ChattyLittleNpcSVDiag
    if diag and #diag.events < 40 then
        local db = _G.ChattyLittleNpcDB
        local pos = db and db.profiles and db.profiles.Default and db.profiles.Default.framePos
        diag.events[#diag.events + 1] = string.format("%s %s db=%s npcInfo=%s charDb=%s pos=%s",
            event, tostring(addonName), tostring(db ~= nil), tostring(_G.NpcInfoDB ~= nil),
            tostring(_G.ChattyLittleNpcCharDB ~= nil),
            pos and (tostring(pos.point) .. " " .. tostring(pos.xOfs) .. "," .. tostring(pos.yOfs)) or "nil")
    end
    -- PLAYER_LOGIN fires after all startup addons have loaded.
    -- Unregister ADDON_LOADED here so our handler never runs inside a
    -- secure LoadAddOn call chain (e.g. Blizzard_GroupFinder loading and
    -- immediately calling the protected Search() function), which would
    -- taint that thread and cause ADDON_ACTION_BLOCKED errors.
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
        if CLN.FlushSavedVarsDiag then CLN:FlushSavedVarsDiag() end
        return
    end

    if addonName == "ChattyLittleNpc" then
        -- Initialize the addon
        if CLN.OnInitialize then
            CLN:OnInitialize()
        end

        -- TEMP DIAGNOSTIC: what the profile holds right after initialization
        if diag and CLN.db then
            local pos = CLN.db.profile and CLN.db.profile.framePos
            diag.afterInit = string.format("sameTable=%s profile=%s pos=%s",
                tostring(CLN.db.sv == _G.ChattyLittleNpcDB), tostring(CLN.db.sv and CLN.db.sv.currentProfile),
                pos and (tostring(pos.point) .. " " .. tostring(pos.xOfs) .. "," .. tostring(pos.yOfs)) or "nil")
        end

        -- Migrate legacy saved variables to new format
        if CLN._MigrateSavedVars then
            CLN:_MigrateSavedVars()
        end

        -- Initialize dialog tracker tables and NPC metadata cache
        if CLN.NpcDialogTracker and CLN.NpcDialogTracker.InitializeTables then
            CLN.NpcDialogTracker:InitializeTables()
        end
        if CLN.NpcMetadataCache then
            CLN.NpcMetadataCache:Initialize()
            CLN.NpcMetadataCache:Prune(30)
        end

        -- Enable the addon (register events, etc.)
        if CLN.OnEnable then
            CLN:OnEnable()
        end

        -- Start the voiceover playback watcher
        if CLN.EventHandler and CLN.EventHandler.StartWatcher then
            CLN.EventHandler:StartWatcher()
        end

        -- Initialize Options panel after everything is loaded
        if CLN.Options and CLN.Options.SetupOptions then
            CLN.Options:SetupOptions()
        end

    elseif addonName and addonName:match("^ChattyLittleNpc_.+_voiceovers$") then
        -- A voiceover pack was loaded, add it to our collection
        local addon = _G[addonName]
        if addon and CLN.VoiceoverPacks then
            CLN.VoiceoverPacks[addonName] = addon
            if addon.Voiceovers then
                addon._voiceoverIndex = {}
                for _, name in ipairs(addon.Voiceovers) do
                    addon._voiceoverIndex[name] = true
                end
            end
            if CLN.db and CLN.db.profile and CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:info("Detected voiceover pack: " .. tostring(addonName), false, (CLN.Utils and CLN.Utils.LogCategories.loader) or 'misc')
                if addon.Voiceovers then
                    CLN.Logger:info("  Voiceover count: " .. tostring(#addon.Voiceovers), false, (CLN.Utils and CLN.Utils.LogCategories.loader) or 'misc')
                end
            end
        end
    end
end)

-- TEMP DIAGNOSTIC: write the SavedVariables load trace into the Logs window
-- (/clnlogs, category "savedvars"). Info/warn lines are always captured there.
function CLN:FlushSavedVarsDiag()
    local diag = _G.ChattyLittleNpcSVDiag
    local log = self.Logger
    if not (diag and log) then return end
    local cat = (self.Utils and self.Utils.LogCategories.savedvars) or "savedvars"

    local f = diag.firstFile or {}
    log:info(string.format("first file: db=%s npcInfo=%s charDb=%s",
        tostring(f.db), tostring(f.npcInfo), tostring(f.charDb)), false, cat)

    local ownLoadHadData
    for _, line in ipairs(diag.events) do
        log:info(line, false, cat)
        if ownLoadHadData == nil and line:find("^ADDON_LOADED ChattyLittleNpc ") then
            ownLoadHadData = line:find("db=true", 1, true) ~= nil
        end
    end
    log:info("after init: " .. tostring(diag.afterInit), false, cat)

    if ownLoadHadData == false then
        log:warn("Saved data was NOT loaded before initialization - settings start from defaults this session.", true, cat)
    elseif ownLoadHadData then
        log:info("Saved data was loaded before initialization.", false, cat)
    end
end
