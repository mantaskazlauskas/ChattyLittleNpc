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
        -- Give the loading screen time to clear before the first-run welcome.
        C_Timer.After(3, function() CLN.WelcomeWindow:ShowIfFirstRun() end)
        return
    end

    if addonName == "ChattyLittleNpc" then
        -- Initialize the addon
        CLN:OnInitialize()

        -- Initialize dialog tracker tables and NPC metadata cache
        CLN.NpcDialogTracker:InitializeTables()
        CLN.NpcMetadataCache:Initialize()
        CLN.NpcMetadataCache:Prune(30)

        -- Enable the addon (register events, etc.)
        CLN:OnEnable()

        -- Start the voiceover playback watcher
        CLN.EventHandler:StartWatcher()

        -- Initialize Options panel after everything is loaded
        CLN.Options:SetupOptions()

    elseif addonName and addonName:match("^ChattyLittleNpc_.+_voiceovers$") then
        -- A voiceover pack was loaded, add it to our collection
        local addon = _G[addonName]
        if CLN:RegisterVoiceoverPack(addonName) then
            if CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
                CLN.Logger:info("Detected voiceover pack: " .. tostring(addonName), false, CLN.Utils.LogCategories.loader)
                if addon.Voiceovers then
                    CLN.Logger:info("  Voiceover count: " .. tostring(#addon.Voiceovers), false, CLN.Utils.LogCategories.loader)
                end
            end
        end
    end
end)
