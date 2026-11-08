-- Options/Profiles.lua - Profiles: switch, copy, reset and delete settings profiles.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Options = CLN.Options
local config = Options.config
local sections = CLN.OptionsDefinition.args

-- ──────────────────────────────────────────────────────────────────────────────
-- Profile management dialogs
-- ──────────────────────────────────────────────────────────────────────────────

StaticPopupDialogs["CLN_NEW_PROFILE"] = {
    text = "Enter a name for the new profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 64,
    OnAccept = function(self)
        local name = self.EditBox:GetText()
        if name and name ~= "" then
            CLN.db:SetProfile(name)
            config:Refresh()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        if name and name ~= "" then
            CLN.db:SetProfile(name)
            config:Refresh()
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CLN_RESET_PROFILE"] = {
    text = "Reset the current profile to default settings? This cannot be undone.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        CLN.db:ResetProfile()
        config:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CLN_DELETE_PROFILE"] = {
    text = "Delete profile \"%s\"? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data)
        local profileToDelete = data
        CLN.db:DeleteProfile(profileToDelete)
        -- Fall back to Default profile; create it if missing
        CLN.db:SetProfile("Default")
        config:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ═══════════════════════════════════════════════
-- PROFILES — Per-character / per-playstyle profiles
-- ═══════════════════════════════════════════════
sections.Profiles = {
    order = 5,
    type = 'group',
    name = 'Profiles',
    desc = 'Manage settings profiles. Useful for keeping different settings per character or playstyle.',
    inline = true,
    args = {
        currentProfile = {
            order = 1,
            type = 'select',
            width = 'double',
            name = 'Active Profile',
            desc = 'Switch to a different settings profile. Each profile stores its own independent settings.',
            values = function()
                local result = {}
                for _, name in ipairs(CLN.db:GetProfiles()) do
                    result[name] = name
                end
                return result
            end,
            get = function() return CLN.db.sv.currentProfile end,
            set = function(_, value)
                CLN.db:SetProfile(value)
                config:Refresh()
            end,
        },
        newProfile = {
            order = 2,
            type = 'execute',
            name = 'New Profile...',
            desc = 'Create a new empty profile with default settings.',
            func = function()
                StaticPopup_Show("CLN_NEW_PROFILE")
            end,
        },
        copyFromSource = {
            order = 3,
            type = 'select',
            width = 'double',
            name = 'Copy Settings From',
            desc = 'Copy all settings from another profile into the active profile, overwriting its current values.',
            values = function()
                local result = {}
                for _, name in ipairs(CLN.db:GetProfiles()) do
                    if name ~= CLN.db.sv.currentProfile then
                        result[name] = name
                    end
                end
                return result
            end,
            get = function()
                -- Return the stored pick, or the first available other profile
                if Options._copyFromSource and Options._copyFromSource ~= CLN.db.sv.currentProfile then
                    return Options._copyFromSource
                end
                for _, name in ipairs(CLN.db:GetProfiles()) do
                    if name ~= CLN.db.sv.currentProfile then
                        Options._copyFromSource = name
                        return name
                    end
                end
                return nil
            end,
            set = function(_, value)
                Options._copyFromSource = value
            end,
            hidden = function()
                return #CLN.db:GetProfiles() <= 1
            end,
        },
        copyFromButton = {
            order = 4,
            type = 'execute',
            name = 'Copy',
            desc = 'Overwrite the active profile with the settings from the selected profile.',
            func = function()
                local source = Options._copyFromSource
                if not source then
                    for _, name in ipairs(CLN.db:GetProfiles()) do
                        if name ~= CLN.db.sv.currentProfile then source = name; break end
                    end
                end
                if source then
                    CLN.db:CopyProfile(source)
                    config:Refresh()
                end
            end,
            hidden = function()
                return #CLN.db:GetProfiles() <= 1
            end,
        },
        resetProfile = {
            order = 5,
            type = 'execute',
            name = 'Reset to Defaults',
            desc = 'Reset all settings in the active profile back to their default values.',
            func = function()
                StaticPopup_Show("CLN_RESET_PROFILE")
            end,
        },
        deleteProfile = {
            order = 6,
            type = 'execute',
            name = 'Delete Profile',
            desc = 'Permanently delete the active profile. You must have at least two profiles to delete one.',
            func = function()
                StaticPopup_Show("CLN_DELETE_PROFILE", CLN.db.sv.currentProfile)
            end,
            disabled = function()
                return #CLN.db:GetProfiles() <= 1
            end,
        },
    },
}
