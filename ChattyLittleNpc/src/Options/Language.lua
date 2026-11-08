-- Options/Language.lua - Voiceover language and installed voiceover packs.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local sections = CLN.OptionsDefinition.args

-- ═══════════════════════════════════════════════
-- LANGUAGE — Which voiceover packs are used
-- ═══════════════════════════════════════════════
sections.VoiceoverLanguage = {
    order = 7,
    type = 'group',
    name = 'Voiceover Language',
    desc = 'Choose which language voiceovers are played in. Languages appear here when packs for them are installed.',
    inline = true,
    args = {
        voiceoverLanguage = {
            order = 1,
            type = 'select',
            width = 'double',
            name = 'Language',
            desc = 'Voiceover packs for this language are used for playback. Automatic uses your game client language when packs for it are installed, otherwise English.',
            values = function()
                local result = {
                    auto = 'Automatic (currently ' .. CLN:GetVoiceoverLocaleName(CLN:GetVoiceoverLanguage()) .. ')',
                }
                local function add(locale) result[locale] = CLN:GetVoiceoverLocaleName(locale) end
                add(CLN.DEFAULT_VOICEOVER_LOCALE)
                for _, pack in ipairs(CLN:GetInstalledVoiceoverPacks()) do add(pack.locale) end
                -- Keep a saved choice selectable even if its packs were removed.
                local current = CLN.db.profile.voiceoverLanguage
                if current and current ~= 'auto' then add(current) end
                return result
            end,
            get = function() return CLN.db.profile.voiceoverLanguage or 'auto' end,
            set = function(_, value)
                CLN.db.profile.voiceoverLanguage = value
                CLN.PlayButton:UpdatePlayButton()
            end,
        },
        voiceoverLanguageFallback = {
            order = 2,
            type = 'toggle',
            width = 'full',
            name = 'Fall Back to English',
            desc = 'When the selected language has no voiceover for a quest or NPC, play the English one instead.',
            get = function() return CLN.db.profile.voiceoverLanguageFallback ~= false end,
            set = function(_, value) CLN.db.profile.voiceoverLanguageFallback = value end,
            disabled = function() return CLN:GetVoiceoverLanguage() == CLN.DEFAULT_VOICEOVER_LOCALE end,
        },
    },
}

sections.InstalledVoiceoverPacks = {
    order = 8,
    type = 'group',
    name = 'Installed Voiceover Packs',
    desc = 'Voiceover packs found in your AddOns folder. Enable or disable them from the AddOns list, then /reload.',
    inline = true,
    args = {
        packList = {
            order = 1,
            type = 'description',
            name = function() return CLN:GetVoiceoverPackListText() end,
        },
    },
}
