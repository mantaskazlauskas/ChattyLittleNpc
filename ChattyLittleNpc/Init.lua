-- Init.lua - Initialization handler
-- This file loads LAST and triggers addon initialization after all modules are loaded

local CLN = _G.ChattyLittleNpc

-- Create event frame for addon initialization
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "ChattyLittleNpc" then
        -- Initialize the addon
        if CLN.OnInitialize then
            CLN:OnInitialize()
        end
        
        -- Enable the addon (register events, etc.)
        if CLN.OnEnable then
            CLN:OnEnable()
        end
        
        -- Initialize Options panel after everything is loaded
        if CLN.Options and CLN.Options.SetupOptions then
            CLN.Options:SetupOptions()
        end
        
        -- Don't unregister - keep listening for voiceover pack addons
    elseif addonName and addonName:match("^ChattyLittleNpc_.+_voiceovers$") then
        -- A voiceover pack was loaded, add it to our collection
        local addon = _G[addonName]
        if addon and CLN.VoiceoverPacks then
            CLN.VoiceoverPacks[addonName] = addon
            if CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
                CLN:Print("Detected voiceover pack:", addonName)
                if addon.Voiceovers then
                    CLN:Print("  Voiceover count:", #addon.Voiceovers)
                end
            end
        end
    end
end)
