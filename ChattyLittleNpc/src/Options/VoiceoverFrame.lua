-- Options/VoiceoverFrame.lua - Voiceover window appearance and queue.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local sections = CLN.OptionsDefinition.args

-- ═══════════════════════════════════════════════════
-- VOICEOVER FRAME — The NPC portrait + queue panel
-- ═══════════════════════════════════════════════════
sections.VoiceoverFrame = {
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
                CLN.ReplayFrame:UpdateDisplayFrameState()
            end,
        },
        frameStyle = {
            order = 1.5,
            type = 'select',
            width = 'double',
            name = 'Frame Style',
            desc = 'Look of the conversation frame and the NPC portrait.\n\n• Minimal — frameless, like the objectives tracker\n• Panel — dark panel with a framed portrait and nameplate\n• Cinematic — head-and-shoulders portrait with a large name',
            values = function()
                local values = {}
                for key, style in pairs(CLN.ReplayFrame.FrameStyles or {}) do
                    values[key] = style.label
                end
                return values
            end,
            sorting = { 'minimal', 'panel', 'cinematic' },
            get = function() return CLN.db.profile.frameStyle or 'minimal' end,
            set = function(_, value)
                CLN.db.profile.frameStyle = value
                CLN.ReplayFrame:ApplyFrameStyle()
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
                CLN.ReplayFrame:UpdateDisplayFrameState()
                -- Show/hide the portrait now rather than at the next voiceover
                CLN.ReplayFrame:CheckAndShowModel()
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
        showIdleFadeCountdown = {
            order = 4.3,
            type = 'toggle',
            width = 'full',
            name = 'Show Fade Countdown',
            desc = 'Show the seconds left until the frame fades, in the top-right of the voiceover frame.',
            disabled = function() return (CLN.db.profile.idleFadeOpacity or 0.1) >= 1 end,
            get = function(info) return CLN.db.profile.showIdleFadeCountdown ~= false end,
            set = function(info, value) CLN.db.profile.showIdleFadeCountdown = value end,
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
                CLN.ReplayFrame:MarkQueueDirty()
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
                CLN.ReplayFrame:MarkQueueDirty()
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
                CLN.ReplayFrame:PruneOldHistory()
                CLN.ReplayFrame:MarkQueueDirty()
            end,
        },
    },
}
