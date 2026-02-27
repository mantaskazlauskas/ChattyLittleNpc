---@class Options
local Options = {}

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- Register this module with the main addon
CLN.Options = Options

-- Create config system instance
local config = ChattyLittleNpc.ConfigSystem:New()

local options = {
    name = "Chatty Little Npc",
    handler = CLN,
    type = 'group',
    args = {
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
                playVoiceoverAfterDelay = {
                    order = 3,
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
                    order = 4,
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
                    order = 5,
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Play Button on Dialogs',
                    desc = 'Show a play button next to quest and gossip dialog frames for manual playback.',
                    get = function(info) return CLN.db.profile.showSpeakButton end,
                    set = function(info, value) CLN.db.profile.showSpeakButton = value end,
                },
                nativeVOMode = {
                    order = 6,
                    type = 'select',
                    width = 'full',
                    name = 'Native NPC Voiceover Handling',
                    desc = 'How to handle native NPC voiced speech while addon VO is playing.\n\n'
                        .. '|cFFFFFFFFOff|r — Ignore NPC speech entirely.\n'
                        .. '|cFFFFFFFFAll|r — Pause addon VO on any NPC speech (may false-positive on unvoiced text).\n'
                        .. '|cFFFFFFFFWhitelist|r — Only pause for NPCs you\'ve confirmed have voice acting. '
                        .. 'When you pause playback, a popup asks if you want to add recently speaking NPCs to the list.',
                    values = { off = "Off", all = "All NPC Speech", whitelist = "Whitelist (Recommended)" },
                    get = function(info) return CLN.db.profile.nativeVOMode or "off" end,
                    set = function(info, value) CLN.db.profile.nativeVOMode = value end,
                },
                resetDismissedNpcs = {
                    order = 7,
                    type = 'execute',
                    name = 'Re-ask Dismissed NPCs',
                    desc = 'Clear the dismissed NPC list so the whitelist popup will ask about them again next time you pause.',
                    func = function()
                        if CLN.ReplayFrame and CLN.ReplayFrame.ResetDismissedNpcs then
                            CLN.ReplayFrame:ResetDismissedNpcs()
                        end
                    end,
                },
                clearVOWhitelist = {
                    order = 8,
                    type = 'execute',
                    name = 'Clear NPC Whitelist',
                    desc = 'Remove all NPCs from the voice-over whitelist. You will be asked again when you pause.',
                    confirm = true,
                    confirmText = 'Clear all whitelisted NPCs? You will need to re-add them via the popup.',
                    func = function()
                        CLN.db.profile.nativeVOWhitelist = {}
                        CLN.db.profile.nativeVODismissed = {}
                        if CLN.Logger then
                            CLN.Logger:info("Cleared NPC whitelist and dismissed list.", false, (CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.loader) or "misc")
                        end
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
                alwaysShowReplayFrame = {
                    order = 2,
                    type = 'toggle',
                    width = 'full',
                    name = 'Always Visible',
                    desc = 'Keep the voiceover frame visible even when no voiceover is playing.',
                    get = function(info) return CLN.db.profile.alwaysShowReplayFrame end,
                    set = function(info, value)
                        CLN.db.profile.alwaysShowReplayFrame = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateVisibility then
                            CLN.ReplayFrame:UpdateVisibility()
                        end
                    end,
                },
                compactMode = {
                    order = 3,
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
                showProgressBar = {
                    order = 5,
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Progress Bar',
                    desc = 'Display a progress bar showing how far along the current voiceover is.',
                    get = function(info) return CLN.db.profile.showProgressBar end,
                    set = function(info, value)
                        CLN.db.profile.showProgressBar = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateProgressBar then
                            CLN.ReplayFrame:UpdateProgressBar()
                        end
                    end,
                },
                showQuestTypeBadges = {
                    order = 6,
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
                    order = 7,
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
                    order = 8,
                    type = 'range',
                    width = 'double',
                    name = 'Subtitle Text Size',
                    desc = 'Adjust the size of subtitle text.',
                    min = 0.5,
                    max = 2.0,
                    step = 0.05,
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
                    order = 9,
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
                    name = 'Reset Frame Position',
                    desc = 'Reset the voiceover frame to its default position on screen.',
                    func = function() CLN.ReplayFrame:ResetFramePosition() end,
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
        -- ADVANCED — NPC model rendering settings
        -- ═══════════════════════════════════════════════
        -- Accessibility
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
        -- Advanced
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
                    desc = 'Also print debug logs in the chat window. Logs window always captures everything regardless.',
                    disabled = function() return not CLN.db.profile.debugMode end,
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
                    type = 'toggle',
                    width = 'full',
                    name = 'Show Gossip Editor',
                    desc = 'Open the Gossip Editor window for editing and fixing collected NPC gossip lines.',
                    get = function(info) return CLN.Editor.Frame:IsShown() end,
                    set = function(info, value)
                        if value then
                            CLN.Editor.Frame:Show()
                        else
                            CLN.Editor.Frame:Hide()
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
end

function Options:OpenSettings()
    config:Open()
end
