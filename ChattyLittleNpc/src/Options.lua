---@class Options
local Options = {}

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- Register this module with the main addon
CLN.Options = Options

-- Create config system instance
local config = ChattyLittleNpc.ConfigSystem:New()

-- The sections live in src/Options/*.lua, which load right after this file
-- and add themselves to options.args.
Options.config = config

local options = {
    name = "Chatty Little Npc",
    handler = CLN,
    type = 'group',
    args = {},
}

-- Expose the raw options table so SettingsWindow can render it into tabs.
CLN.OptionsDefinition = options

function Options:SetupOptions()
    -- Register a minimal Blizzard addon panel with just an "Open Settings" button.
    local panel = CreateFrame("Frame")
    panel.name = "Chatty Little NPC"

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(200, 26)
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    btn:SetText("Open Settings")
    btn:SetScript("OnClick", function()
        if CLN.SettingsWindow then CLN.SettingsWindow:Open() end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        config.category = category
        config.panel    = panel
    else
        InterfaceOptions_AddCategory(panel)
        config.panel = panel
    end

    -- After any profile switch, re-apply frame-driven settings and refresh the window.
    local function onProfileChange()
        CLN.ReplayFrame:ApplyProfileSettings()
        if CLN.SettingsWindow then
            CLN.SettingsWindow:Refresh()
        end
    end
    CLN.db:RegisterCallback("OnProfileChanged", onProfileChange)
    CLN.db:RegisterCallback("OnProfileCopied",  onProfileChange)
    CLN.db:RegisterCallback("OnProfileReset",   onProfileChange)
end

function Options:OpenSettings()
    if CLN.SettingsWindow then
        CLN.SettingsWindow:Toggle()
    else
        config:Open()
    end
end

SLASH_CLNSETTINGS1 = "/clnsettings"
SlashCmdList["CLNSETTINGS"] = function()
    Options:OpenSettings()
end
