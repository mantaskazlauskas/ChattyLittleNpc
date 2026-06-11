---@class Options
local Options = {}

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- Register this module with the main addon
CLN.Options = Options

-- Create config system instance
local config = ChattyLittleNpc.ConfigSystem:New()

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



local options = {
    name = "Chatty Little Npc",
    handler = CLN,
    type = 'group',
    args = {
        -- ═══════════════════════════════════════════════
        -- PROFILES — Per-character / per-playstyle profiles
        -- ═══════════════════════════════════════════════
        Profiles = {
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
        },

        -- ═══════════════════════════════════════════════
        -- PLAYBACK — Core functionality users care about
        -- ═══════════════════════════════════════════════
        Playback = {
            order = 10,
            type = 'group',
            name = 'Playback',
            desc = 'Control when and how voiceovers are played.',
            inline = true,
            args = {
                autoPlayVoiceovers = {
                    order = 1,
                    type = 'toggle',
                    width = 'full',
                    name = 'Auto-Play Voiceovers',
                    desc = 'Automatically play voiceovers when opening a quest or gossip window.',
                    get = function(info) return CLN.db.profile.autoPlayVoiceovers end,
                    set = function(info, value) CLN.db.profile.autoPlayVoiceovers = value end,
                },
                questPlaybackMode = {
                    order = 2,
                    type = 'select',
                    width = 'double',
                    name = 'Quest Playback Mode',
                    desc = 'Controls how quest voiceovers are handled:\n\n• Queue — plays all lines in order, continues after dialog closes\n• Stop On Close — stops playback when the dialog window closes\n• Manual — only plays when you click the play button',
                    values = {
                        queue = 'Queue (play all in order)',
                        stopOnClose = 'Stop when dialog closes',
                        manual = 'Manual (play button only)',
                    },
                    get = function() return CLN.db.profile.questPlaybackMode or 'queue' end,
                    set = function(_, value)
                        CLN.db.profile.questPlaybackMode = value
                        if CLN._SyncLegacyQuestPlaybackFlags then CLN:_SyncLegacyQuestPlaybackFlags() end
                    end,
                },
                gossipPlaybackMode = {
                    order = 3,
                    type = 'select',
                    width = 'double',
                    name = 'Gossip Playback Mode',
                    desc = 'Controls how gossip/greeting voiceovers are handled (independent from quests):\n\n'
                        .. '• Queue — gossip continues playing after the dialog closes\n'
                        .. '• Stop On Close — gossip stops when you close the gossip window\n'
                        .. '• Manual — only plays when you click the play button',
                    values = {
                        queue = 'Queue (continue after close)',
                        stopOnClose = 'Stop when dialog closes',
                        manual = 'Manual (play button only)',
                    },
                    get = function() return CLN.db.profile.gossipPlaybackMode or 'queue' end,
                    set = function(_, value) CLN.db.profile.gossipPlaybackMode = value end,
                },
                playVoiceoverAfterDelay = {
                    order = 4,
                    type = 'range',
                    width = 'double',
                    name = 'Playback Delay (seconds)',
                    desc = 'Wait this many seconds before starting voiceover playback after opening a dialog.',
                    min = 0,
                    max = 3,
                    step = 0.1,
                    get = function(info) return CLN.db.profile.playVoiceoverAfterDelay end,
                    set = function(info, value) CLN.db.profile.playVoiceoverAfterDelay = value end,
                },
                audioChannel = {
                    order = 5,
                    type = 'select',
                    width = 'double',
                    name = 'Audio Channel',
                    desc = 'Which audio channel voiceovers play through. This determines which volume slider controls voiceover volume.',
                    values = {
                        MASTER = 'Master',
                        DIALOG = 'Dialog',
                        SFX = 'Sound Effects',
                        MUSIC = 'Music',
                        AMBIENCE = 'Ambience',
                    },
                    get = function(info) return CLN.db.profile.audioChannel end,
                    set = function(info, value) CLN.db.profile.audioChannel = value end,
                },
                showSpeakButton = {
                    order = 6,
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Play Button on Dialogs',
                    desc = 'Show a play button next to quest and gossip dialog frames for manual playback.',
                    get = function(info) return CLN.db.profile.showSpeakButton end,
                    set = function(info, value) CLN.db.profile.showSpeakButton = value end,
                },
                gossipCooldownEnabled = {
                    order = 7,
                    type = 'toggle',
                    width = 'full',
                    name = 'Gossip Cooldown',
                    desc = 'When enabled, the same gossip voiceover will not be played again for a configurable amount of time.',
                    get = function(info) return CLN.db.profile.gossipCooldownEnabled end,
                    set = function(info, value) CLN.db.profile.gossipCooldownEnabled = value end,
                },
                gossipCooldownMinutes = {
                    order = 8,
                    type = 'range',
                    width = 'double',
                    name = 'Gossip Cooldown (minutes)',
                    desc = 'How long to wait before allowing the same gossip line to play again. Set to 0 for infinite (entire session, until reload/logout).',
                    min = 0,
                    max = 120,
                    step = 1,
                    disabled = function() return not CLN.db.profile.gossipCooldownEnabled end,
                    get = function(info) return CLN.db.profile.gossipCooldownMinutes end,
                    set = function(info, value) CLN.db.profile.gossipCooldownMinutes = value end,
                },
                gossipQueueMode = {
                    order = 9,
                    type = 'select',
                    width = 'full',
                    name = 'Gossip Queueing',
                    desc = 'Controls whether gossip/greeting voiceovers queue behind active playback or override it.\n\n'
                        .. '|cFFFFFFFFNone|r — Gossip replaces whatever is playing (default).\n'
                        .. '|cFFFFFFFFMedium|r — Queue gossip if the current VO has been playing for more than 5 seconds.\n'
                        .. '|cFFFFFFFFLong Only|r — Queue gossip if the current VO has been playing for more than 10 seconds.\n'
                        .. '|cFFFFFFFFAll|r — Always queue gossip behind active playback.',
                    values = { none = "None (Override)", medium = "Medium (>5s)", long = "Long Only (>10s)", all = "Always Queue" },
                    get = function(info) return CLN.db.profile.gossipQueueMode or "none" end,
                    set = function(info, value) CLN.db.profile.gossipQueueMode = value end,
                },
                textContinuationEnabled = {
                    order = 10,
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Text on Resume',
                    desc = 'When you resume a voiceover that was already near the end, show the remaining dialog text so you can read what you missed.',
                    get = function(info) return CLN.db.profile.textContinuationEnabled end,
                    set = function(info, value) CLN.db.profile.textContinuationEnabled = value end,
                },
                keybindSpacer = {
                    order = 10.5,
                    type = 'header',
                    name = 'Keybinding',
                },
                playVoiceoverKeybind = {
                    order = 11,
                    type = 'keybinding',
                    name = 'Play / Resume Voiceover',
                    desc = 'Key to trigger, resume, or stop voiceover playback. Click the button then press the desired key. Right-click or press Escape to clear.',
                    get = function()
                        return CLN.db.profile.playVoiceoverKey
                    end,
                    set = function(_, key)
                        CLN.db.profile.playVoiceoverKey = (key and key ~= "") and key or nil
                    end,
                },
            },
        },

        -- ═══════════════════════════════════════════════════
        -- VOICEOVER FRAME — The NPC portrait + queue panel
        -- ═══════════════════════════════════════════════════
        VoiceoverFrame = {
            order = 20,
            type = 'group',
            name = 'Voiceover Frame',
            desc = 'Customize the floating NPC portrait and playback queue.',
            inline = true,
            args = {
                showReplayFrame = {
                    order = 1,
                    type = 'toggle',
                    width = 'full',
                    name = 'Enable Voiceover Frame',
                    desc = 'Show the voiceover frame with NPC portrait and playback queue during voiceover playback.',
                    get = function(info) return CLN.db.profile.showReplayFrame end,
                    set = function(info, value)
                        CLN.db.profile.showReplayFrame = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
                    end,
                },
                compactMode = {
                    order = 2,
                    type = 'toggle',
                    width = 'full',
                    name = 'Compact Mode',
                    desc = 'Hide the NPC portrait and show only the playback queue in a smaller frame.',
                    get = function(info) return CLN.db.profile.compactMode end,
                    set = function(info, value)
                        CLN.db.profile.compactMode = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
                    end,
                },
                combatAutoCollapse = {
                    order = 4,
                    type = 'toggle',
                    width = 'full',
                    name = 'Auto-Hide in Combat',
                    desc = 'Automatically hide the voiceover frame when you enter combat and restore it when combat ends.',
                    get = function(info) return CLN.db.profile.combatAutoCollapse end,
                    set = function(info, value) CLN.db.profile.combatAutoCollapse = value end,
                },
                idleFadeDelay = {
                    order = 4.1,
                    type = 'range',
                    width = 'double',
                    name = 'Idle Fade Delay',
                    desc = 'Seconds of inactivity before the frame fades to idle opacity.',
                    min = 1,
                    max = 60,
                    step = 1,
                    get = function(info) return CLN.db.profile.idleFadeDelay or 10 end,
                    set = function(info, value)
                        CLN.db.profile.idleFadeDelay = value
                    end,
                },
                idleFadeOpacity = {
                    order = 4.2,
                    type = 'range',
                    width = 'double',
                    name = 'Idle Opacity',
                    desc = 'How opaque the frame remains when faded (0%% = invisible, 100%% = fully visible).',
                    min = 0,
                    max = 1,
                    step = 0.05,
                    isPercent = true,
                    get = function(info) return CLN.db.profile.idleFadeOpacity or 0.1 end,
                    set = function(info, value)
                        CLN.db.profile.idleFadeOpacity = value
                    end,
                },
                showQuestTypeBadges = {
                    order = 5,
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Quest Type Badges',
                    desc = 'Show type icons and color-coding for quest, gossip, and item entries in the queue.',
                    get = function(info) return CLN.db.profile.showQuestTypeBadges end,
                    set = function(info, value)
                        CLN.db.profile.showQuestTypeBadges = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                    end,
                },
                showSubtitles = {
                    order = 6,
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Subtitles',
                    desc = 'Display subtitle text below the NPC portrait during voiceover playback.',
                    get = function(info) return CLN.db.profile.showSubtitles end,
                    set = function(info, value)
                        CLN.db.profile.showSubtitles = value
                        if (not value) and CLN.ReplayFrame and CLN.ReplayFrame.HideSubtitle then
                            CLN.ReplayFrame:HideSubtitle()
                        end
                    end,
                },
                subtitleFontScale = {
                    order = 7,
                    type = 'range',
                    width = 'double',
                    name = 'Subtitle Text Size',
                    desc = 'Adjust the size of subtitle text.',
                    min = 0.5,
                    max = 2.0,
                    step = 0.05,
                    disabled = function() return not CLN.db.profile.showSubtitles end,
                    get = function(info)
                        return CLN.db.profile.subtitleFontScale or 1.0
                    end,
                    set = function(info, value)
                        CLN.db.profile.subtitleFontScale = value
                        -- Apply font change live
                        if CLN.ReplayFrame and CLN.ReplayFrame.SubtitleText then
                            local fontScale = math.max(8, math.floor(12 * value))
                            CLN.ReplayFrame.SubtitleText:SetFont("Fonts\\FRIZQT__.TTF", fontScale, "")
                        end
                        -- Re-show subtitle if currently playing
                        local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                        if CLN.db.profile.showSubtitles and cur and cur.title and CLN.ReplayFrame and CLN.ReplayFrame.ShowSubtitle then
                            CLN.ReplayFrame:ShowSubtitle(cur.title)
                        end
                    end,
                },
                queueHistoryMaxEntries = {
                    order = 8,
                    type = 'range',
                    width = 'double',
                    name = 'Replay History Length',
                    desc = 'How many completed voiceovers to keep in the replay history. Set to 0 to disable history.',
                    min = 0,
                    max = 50,
                    step = 1,
                    get = function(info) return CLN.db.profile.queueHistoryMaxEntries or 20 end,
                    set = function(info, value)
                        CLN.db.profile.queueHistoryMaxEntries = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                    end,
                },
                historyTTLMinutes = {
                    order = 9,
                    type = 'range',
                    width = 'double',
                    name = 'History Auto-Cleanup (minutes)',
                    desc = 'Remove history entries older than this many minutes. Keeps the replay list from growing stale.',
                    min = 1,
                    max = 60,
                    step = 1,
                    get = function(info) return CLN.db.profile.historyTTLMinutes or 5 end,
                    set = function(info, value)
                        CLN.db.profile.historyTTLMinutes = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.PruneOldHistory then CLN.ReplayFrame:PruneOldHistory() end
                        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                    end,
                },
            },
        },

        -- ═══════════════════════════════════════════════
        -- FRAME LAYOUT — Positioning, sizing, edit mode
        -- ═══════════════════════════════════════════════
        FrameLayout = {
            order = 30,
            type = 'group',
            name = 'Frame Layout',
            desc = 'Position, resize, and adjust the voiceover frame and play button.',
            inline = true,
            args = {
                editMode = {
                    order = 1,
                    type = 'toggle',
                    width = 'full',
                    name = 'Edit Mode',
                    desc = 'Enable edit mode to move and resize the voiceover frame. Disable when done.',
                    get = function(info)
                        return CLN.ReplayFrame and CLN.ReplayFrame._editMode or false
                    end,
                    set = function(info, value)
                        if not CLN.ReplayFrame then return end
                        if value then
                            CLN.ReplayFrame:ShowForEdit()
                        else
                            CLN.ReplayFrame:SetEditMode(false)
                            CLN.ReplayFrame._forceShow = false
                            if CLN.ReplayFrame.UpdateDisplayFrameState then
                                CLN.ReplayFrame:UpdateDisplayFrameState()
                            end
                        end
                    end,
                },
                editModeGlowHints = {
                    order = 2,
                    type = 'toggle',
                    width = 'full',
                    name = 'Edit Mode Glow Hints',
                    desc = 'Show a subtle glow pulse around the frame in edit mode to help you find it.',
                    get = function(info) return CLN.db.profile.editModeGlowHints end,
                    set = function(info, value) CLN.db.profile.editModeGlowHints = value end,
                },
                queueTextScale = {
                    order = 3,
                    type = 'range',
                    width = 'double',
                    name = 'Queue Text Size',
                    desc = 'Adjust the text size of queue entries and headers in the voiceover frame.',
                    min = 0.75,
                    max = 1.5,
                    step = 0.05,
                    get = function(info)
                        return CLN.db.profile.queueTextScale or 1.0
                    end,
                    set = function(info, value)
                        CLN.db.profile.queueTextScale = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.ApplyQueueTextScale then CLN.ReplayFrame:ApplyQueueTextScale() end
                    end,
                },
                frameScale = {
                    order = 4,
                    type = 'range',
                    width = 'double',
                    name = 'Frame Scale',
                    desc = 'Scale the entire voiceover frame up or down. Useful for high-resolution displays.',
                    min = 0.5,
                    max = 2.0,
                    step = 0.05,
                    get = function(info)
                        return CLN.db.profile.frameScale or 1.0
                    end,
                    set = function(info, value)
                        value = math.max(0.5, math.min(2.0, value))
                        CLN.db.profile.frameScale = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.DisplayFrame then
                            CLN.ReplayFrame.DisplayFrame:SetScale(value)
                        end
                    end,
                },
                npcModelFrameHeight = {
                    order = 5,
                    type = 'range',
                    width = 'double',
                    name = 'Portrait Height',
                    desc = 'Height of the NPC portrait area in pixels. Larger values show more of the NPC model.',
                    min = 50,
                    max = 300,
                    step = 5,
                    get = function(info)
                        return CLN.db.profile.npcModelFrameHeight or 140
                    end,
                    set = function(info, value)
                        CLN.db.profile.npcModelFrameHeight = value
                        if CLN.ReplayFrame then
                            CLN.ReplayFrame.npcModelFrameHeight = value
                            if CLN.ReplayFrame.ModelContainer then
                                CLN.ReplayFrame.ModelContainer:SetHeight(value)
                            end
                            if CLN.ReplayFrame.NpcModelFrame then
                                CLN.ReplayFrame.NpcModelFrame:SetHeight(value)
                            end
                        end
                    end,
                },
                resetFramePos = {
                    order = 6,
                    type = 'execute',
                    name = 'Reset Voiceover Frame Position',
                    desc = 'Reset the voiceover frame to its default position on screen.',
                    func = function() CLN.ReplayFrame:ResetFramePosition() end,
                },
                playButtonSpacer = {
                    order = 6.5,
                    type = 'header',
                    name = 'Play Button',
                },
                buttonPosX = {
                    order = 7,
                    type = 'range',
                    width = 'double',
                    name = 'Play Button X Offset',
                    desc = 'Horizontal offset for the play button on quest/gossip frames.',
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function(info) return CLN.db.profile.buttonPosX or 0 end,
                    set = function(info, value)
                        CLN.db.profile.buttonPosX = value
                        CLN.PlayButton:UpdateButtonPositions()
                    end,
                },
                buttonPosY = {
                    order = 8,
                    type = 'range',
                    width = 'double',
                    name = 'Play Button Y Offset',
                    desc = 'Vertical offset for the play button on quest/gossip frames.',
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function(info) return CLN.db.profile.buttonPosY or 0 end,
                    set = function(info, value)
                        CLN.db.profile.buttonPosY = value
                        CLN.PlayButton:UpdateButtonPositions()
                    end,
                },
                resetButtonPosition = {
                    order = 9,
                    type = 'execute',
                    name = 'Reset Play Button Position',
                    desc = 'Reset the play button to its default position on dialog frames.',
                    func = function()
                        CLN.db.profile.buttonPosX = -15
                        CLN.db.profile.buttonPosY = -30
                        CLN.PlayButton:UpdateButtonPositions()
                    end,
                },
            },
        },

        -- ═══════════════════════════════════════════════
        -- ACCESSIBILITY — High-contrast and keyboard nav
        -- ═══════════════════════════════════════════════
        Accessibility = {
            order = 35,
            type = 'group',
            name = 'Accessibility',
            desc = 'High-contrast mode and keyboard navigation settings.',
            inline = true,
            args = {
                highContrastMode = {
                    order = 1,
                    type = 'toggle',
                    name = 'High-Contrast Mode',
                    desc = 'Brighten colors and add text type badges ([Q] Quest, [G] Gossip, [I] Item) for colorblind users. Also activates when WoW\'s colorblind mode is enabled.',
                    width = 'full',
                    get = function(info) return CLN.db.profile.highContrastMode end,
                    set = function(info, value)
                        CLN.db.profile.highContrastMode = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                    end,
                },
                keyboardNavHint = {
                    order = 2,
                    type = 'description',
                    name = '\n|cFFFFD100Keyboard Navigation:|r  Tab into queue list, Up/Down arrows to navigate, Enter/Space to activate, Escape to deselect, Home/End to jump.',
                    fontSize = 'medium',
                },
            },
        },
        -- ═══════════════════════════════════════════════
        -- ADVANCED — NPC model rendering settings
        -- ═══════════════════════════════════════════════
        Advanced = {
            order = 40,
            type = 'group',
            name = 'Advanced',
            desc = 'NPC portrait rendering and camera behavior.',
            inline = true,
            args = {
                renderBackend = {
                    order = 1,
                    type = 'select',
                    width = 'double',
                    name = 'NPC Model Renderer',
                    desc = 'Which renderer draws the NPC portrait.\n\n• Auto — uses the best option for your game version\n• ModelScene — modern renderer (Retail)\n• PlayerModel — classic/legacy renderer',
                    values = function()
                        return {
                            auto = 'Auto (recommended)',
                            scene = 'ModelScene (modern)',
                            player = 'PlayerModel (legacy)',
                        }
                    end,
                    hidden = function()
                        return not (CLN and CLN.ReplayFrame and CLN.ReplayFrame.IsModelSceneAvailable and CLN.ReplayFrame:IsModelSceneAvailable())
                    end,
                    get = function(info)
                        return CLN.db.profile.renderBackend or 'auto'
                    end,
                    set = function(info, value)
                        CLN.db.profile.renderBackend = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.RebuildModelHost then
                            CLN.ReplayFrame:RebuildModelHost()
                        end
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
                            CLN.ReplayFrame:UpdateDisplayFrameState()
                        end
                    end,
                },
                advancedCameraFitting = {
                    order = 2,
                    type = 'toggle',
                    width = 'full',
                    name = 'Enhanced Portrait Framing',
                    desc = 'Use improved camera positioning for better NPC portrait framing. Disable if you see visual jitter.',
                    get = function(info)
                        return CLN.db.profile.advancedCameraFitting
                    end,
                    set = function(info, value)
                        CLN.db.profile.advancedCameraFitting = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.RebuildModelHost then
                            CLN.ReplayFrame:RebuildModelHost()
                        end
                        if CLN.ReplayFrame and CLN.ReplayFrame.ApplyDefaultFit then
                            local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                            if cur and (CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame.IsShown and CLN.ReplayFrame.NpcModelFrame:IsShown()) then
                                CLN.ReplayFrame:ApplyDefaultFit(cur.displayID)
                            end
                        end
                    end,
                },
                disableCameraAnimations = {
                    order = 3,
                    type = 'toggle',
                    width = 'full',
                    name = 'Disable Portrait Animations',
                    desc = 'Stop camera zoom and pan effects on the NPC portrait. The NPC model still animates normally.',
                    get = function(info)
                        return CLN.db.profile.disableCameraAnimations
                    end,
                    set = function(info, value)
                        CLN.db.profile.disableCameraAnimations = value
                        if CLN.ReplayFrame then
                            if CLN.ReplayFrame.AnimStop then
                                CLN.ReplayFrame:AnimStop('zoom')
                                CLN.ReplayFrame:AnimStop('pan')
                            end
                            if CLN.ReplayFrame._UpdateModelOnUpdateHook then
                                CLN.ReplayFrame:_UpdateModelOnUpdateHook()
                            end
                        end
                    end,
                },
            },
        },

        -- ═══════════════════════════════════════════════════
        -- NATIVE VOICED NPCS — Pause-for whitelist management
        -- ═══════════════════════════════════════════════════
        NativeVoicedNpcs = {
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
                        if CLN.Logger then
                            CLN.Logger:info("Cleared Never Ask list.", false, (CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.loader) or "misc")
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
            },
        },

        -- ═══════════════════════════════════════════════
        -- DATA COLLECTION — For community contributors
        -- ═══════════════════════════════════════════════
        DataCollection = {
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
        },

        -- ═══════════════════════════════════════════════
        -- DEVELOPER & DEBUG — For developers and testing
        -- ═══════════════════════════════════════════════
        DeveloperDebug = {
            order = 90,
            type = 'group',
            name = 'Developer & Debug',
            desc = 'Diagnostic tools for addon developers and testers.',
            inline = true,
            args = {
                slashInfo = {
                    order = 0,
                    type = 'description',
                    width = 'full',
                    name = 'Slash commands:  /clnlogs — Logs window    /clndebug — Debug window',
                    fontSize = 'small',
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
                        if CLN.ReplayFrame and CLN.ReplayFrame.SetNoAnimDebug then
                            CLN.ReplayFrame:SetNoAnimDebug(value)
                            if CLN.ReplayFrame._UpdateModelOnUpdateHook then
                                CLN.ReplayFrame:_UpdateModelOnUpdateHook()
                            end
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
                        local C = CLN and CLN.Utils and CLN.Utils.LogCategories
                        local values = {
                            all = 'All Categories',
                            none = 'None (Disable All)',
                        }
                        if C then
                            values[C.camera] = 'Camera Only'
                            values[C.framing] = 'Framing Only'
                            values[C.projection] = 'Projection Only'
                            values[C.host] = 'Host/Backend Only'
                            values[C.loader] = 'Loader Only'
                            values[C.animation] = 'Animation Only'
                            values[C.emotes] = 'Emotes Only'
                        end
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
                showGossipEditor = {
                    order = 7,
                    type = 'execute',
                    name = 'Open Gossip Editor',
                    desc = 'Open the Gossip Editor window for editing and fixing collected NPC gossip lines.',
                    func = function()
                        if CLN.Editor and CLN.Editor.Frame then
                            if CLN.Editor.Frame:IsShown() then
                                CLN.Editor.Frame:Hide()
                            else
                                CLN.Editor.Frame:Show()
                            end
                        end
                    end,
                },
                printLoadedVoiceoverPackMetadata = {
                    order = 8,
                    type = 'execute',
                    name = 'Print Voiceover Pack Info',
                    desc = 'Print metadata and statistics for all loaded voiceover packs.',
                    func = function() CLN:PrintLoadedVoiceoverPacks() end,
                },
            },
        },
    },
}

function Options:SetupOptions()
    config:RegisterOptions("Chatty Little Npc", options, CLN.db)
    -- After any profile switch, refresh the settings panel controls and
    -- re-apply all frame-driven settings (position, scale, heights, etc.).
    local function onProfileChange()
        config:Refresh()
        if CLN.ReplayFrame and CLN.ReplayFrame.ApplyProfileSettings then
            CLN.ReplayFrame:ApplyProfileSettings()
        end
    end
    CLN.db:RegisterCallback("OnProfileChanged", onProfileChange)
    CLN.db:RegisterCallback("OnProfileCopied",  onProfileChange)
    CLN.db:RegisterCallback("OnProfileReset",   onProfileChange)
end

function Options:OpenSettings()
    config:Open()
end
