-- Init.lua - Initialization handler
-- This file loads LAST and triggers addon initialization after all modules are loaded

local CLN = _G.ChattyLittleNpc

-- Create event frame for addon initialization
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", function(self, event, addonName)
    -- PLAYER_LOGIN fires after all startup addons have loaded.
    -- Unregister ADDON_LOADED here so our handler never runs inside a
    -- secure LoadAddOn call chain (e.g. Blizzard_GroupFinder loading and
    -- immediately calling the protected Search() function), which would
    -- taint that thread and cause ADDON_ACTION_BLOCKED errors.
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end

    if addonName == "ChattyLittleNpc" then
        -- Initialize the addon
        if CLN.OnInitialize then
            CLN:OnInitialize()
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
