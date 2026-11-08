-- Options/Playback.lua - Playback behaviour.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local sections = CLN.OptionsDefinition.args

-- ═══════════════════════════════════════════════
-- PLAYBACK — Core functionality users care about
-- ═══════════════════════════════════════════════
sections.Playback = {
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
        showQuestInfoPanel = {
            order = 6.5,
            type = 'toggle',
            width = 'full',
            name = 'Show Quest Info Panel',
            desc = 'Show a small collapsible panel beside quest dialogs with the quest ID, dialog stage, NPC ID and whether a voiceover exists. Handy when reporting missing voiceovers.',
            get = function(info) return CLN.db.profile.showQuestInfoPanel end,
            set = function(info, value)
                CLN.db.profile.showQuestInfoPanel = value
                if not value and CLN.QuestInfoPanel then CLN.QuestInfoPanel:Hide() end
            end,
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
        gossipCooldownSeconds = {
            order = 8,
            type = 'select',
            width = 'double',
            name = 'Gossip Cooldown',
            desc = 'How long the same gossip line stays silent after it finished playing. '
                .. 'Short cooldowns stop repeated lines when clicking quickly through dialog options (e.g. guards).',
            values = {
                [5] = '5 seconds',
                [10] = '10 seconds',
                [30] = '30 seconds',
                [60] = '1 minute',
                [300] = '5 minutes',
                [0] = 'Until reload',
            },
            sorting = { 5, 10, 30, 60, 300, 0 },
            disabled = function() return not CLN.db.profile.gossipCooldownEnabled end,
            get = function(info) return CLN.db.profile.gossipCooldownSeconds or 10 end,
            set = function(info, value) CLN.db.profile.gossipCooldownSeconds = value end,
        },
        gossipQueueMode = {
            order = 9,
            type = 'select',
            width = 'double',
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
            name = 'Play / Stop Voiceover',
            desc = 'Key to trigger, resume, or stop voiceover playback. Click the button then press the desired key (modifiers like Ctrl/Alt/Shift are supported). Right-click or press Escape to clear.\n\nController buttons can be bound in the game\'s Key Bindings menu under AddOns > Chatty Little NPC.',
            get = function()
                return CLN.Keybinds:GetKeyText()
            end,
            set = function(_, key)
                CLN.Keybinds:SetKeyboardKey(key)
            end,
        },
    },
}
