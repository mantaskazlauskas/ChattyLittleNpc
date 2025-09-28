---@class Options: table, AceConsole-3.0
local Options = LibStub("AceAddon-3.0"):NewAddon("Options", "AceConsole-3.0")

---@class ChattyLittleNpc: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0
local CLN

-- Store a reference to ChattyLittleNpc
function Options:SetChattyLittleNpcReference(reference)
    CLN = reference
end

local options = {
    name = "Chatty Little Npc",
    handler = CLN,
    type = 'group',
    args = {
        Debugging = {
            order = 100,
            type = 'group',
            name = 'Debugging',
            inline = true,
            args = {
                debugMode = {
                    type = 'toggle',
                    name = 'Enable Debug Logging',
                    desc = 'Enable debug messages. Use the Logs window (/clnlogs) to view; enable Chat Mirroring to see in chat.',
                    get = function(info) return CLN.db.profile.debugMode end,
                    set = function(info, value) 
                        CLN.db.profile.debugMode = value 
                    end,
                },
                logToChat = {
                    type = 'toggle',
                    name = 'Mirror logs to chat',
                    desc = 'Also print logs in chat. Off keeps chat clean while Logs window captures everything.',
                    disabled = function() return not CLN.db.profile.debugMode end,
                    get = function(info) return CLN.db.profile.logToChat end,
                    set = function(info, value)
                        CLN.db.profile.logToChat = value
                    end,
                },
                printMissingFiles = {
                    type = 'toggle',
                    name = 'Show Missing Files',
                    desc = 'Log missing voiceover files as warnings. Requires debug mode.',
                    disabled = function() return not CLN.db.profile.debugMode end,
                    get = function(info) return CLN.db.profile.printMissingFiles end,
                    set = function(info, value) CLN.db.profile.printMissingFiles = value end,
                },
                debugNoAnim = {
                    type = 'toggle',
                    name = 'Freeze Animations (Debug Camera)',
                    desc = 'Freeze all model/emote animations to debug camera framing. Camera logs remain active.',
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
                    type = 'toggle',
                    name = 'Animation Debug Logs',
                    desc = 'Enable detailed animation/camera debug logs. Use category filter below to reduce noise.',
                    disabled = function() return not CLN.db.profile.debugMode end,
                    get = function(info) return CLN.db.profile.debugAnimations end,
                    set = function(info, value) CLN.db.profile.debugAnimations = value end,
                },
                debugAnimCategories = {
                    type = 'select',
                    name = 'Animation Log Filter',
                    desc = 'Choose which animation debug categories to show. "All" shows everything, "None" disables all animation logs.',
                    values = function()
                        local C = CLN and CLN.Utils and CLN.Utils.LogCategories
                        local values = { 
                            all = 'All Categories',
                            none = 'None (Disable All)'
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
                            -- Count enabled categories
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
                            return 'all' -- multiple selected, show as "all"
                        end
                        return 'all'
                    end,
                    set = function(_, value)
                        if value == 'all' then
                            CLN.db.profile.debugAnimCategories = 'all'
                        elseif value == 'none' then
                            CLN.db.profile.debugAnimCategories = {}
                        else
                            -- Single category selection
                            local cats = {}
                            cats[value] = true
                            CLN.db.profile.debugAnimCategories = cats
                        end
                    end,
                },
                allowKeyPropagation = {
                    type = 'toggle',
                    name = 'Allow Key Propagation (Advanced)',
                    desc = 'Enable usage of SetPropagateKeyboardInput on internal debug/overlay frames. This can reduce stuck-focus issues but may trigger Blizzard taint errors. Leave OFF unless you understand the risk.',
                    disabled = function() return not CLN.db.profile.debugMode end,
                    get = function() return CLN.db.profile.allowKeyPropagation end,
                    set = function(_, v) CLN.db.profile.allowKeyPropagation = v and true or false end,
                },
            },
        },
        DataCollection = {
            order = 110,
            type = 'group',
            name = 'Data Collection',
            inline = true,
            args = {
                logNpcTexts = {
                    type = 'toggle',
                    name = 'Track NPC Data',
                    desc = 'Save all NPC texts to saved variables for voiceover generation. Contact us on Discord if you want to help contribute data.',
                    get = function(info) return CLN.db.profile.logNpcTexts end,
                    set = function(info, value)
                        CLN.db.profile.logNpcTexts = value
                        if (not value) then
                            CLN.db.profile.printNpcTexts = false
                        end
                    end,
                },
                printNpcTexts = {
                    type = 'toggle',
                    name = 'Log Collected Data',
                    desc = 'Print the NPC data being collected (if tracking is enabled).',
                    disabled = function() return not CLN.db.profile.logNpcTexts end,
                    get = function(info) return CLN.db.profile.printNpcTexts end,
                    set = function(info, value) CLN.db.profile.printNpcTexts = value end,
                },
                overwriteExistingGossipValues = {
                    type = 'toggle',
                    name = 'Overwrite Existing Data',
                    desc = 'Overwrite existing NPC text data when interacting again.',
                    disabled = function() return not CLN.db.profile.logNpcTexts end,
                    get = function(info) return CLN.db.profile.overwriteExistingGossipValues end,
                    set = function(info, value) CLN.db.profile.overwriteExistingGossipValues = value end,
                },
            },
        },
        DeveloperTools = {
            order = 120,
            type = 'group',
            name = 'Developer Tools',
            inline = true,
            args = {
                showGossipEditor = {
                    type = 'toggle',
                    name = 'Show Gossip Editor',
                    desc = 'Toggle the Gossip Editor window for editing/fixing collected NPC gossip lines.',
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
                    type = 'execute',
                    name = 'Print VO Pack Info',
                    desc = 'Print loaded voiceover pack metadata and statistics.',
                    func = function() CLN:PrintLoadedVoiceoverPacks() end,
                },
            },
        },
        ReplayFrame = {
            order = 10,
            type = 'group',
            name = 'Replay Frame',
            inline = true,
            args = {
                advancedCameraFitting = {
                    type = 'toggle',
                    name = 'Advanced Camera Fitting (ModelScene)',
                    desc = 'Use projector-based fitting for better framing in ModelScene backend. Disable if you see jitter or prefer the classic fit.',
                    get = function(info)
                        return CLN.db.profile.advancedCameraFitting
                    end,
                    set = function(info, value)
                        CLN.db.profile.advancedCameraFitting = value
                        -- Rebuild host to switch fit delegates and reapply default fit if visible
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
                    type = 'toggle',
                    name = 'Disable Camera Animations',
                    desc = 'Stop camera zoom/pan easing during playback; model/emote animations still run.',
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
                renderBackend = {
                    type = 'select',
                    name = 'Render Backend',
                    desc = 'Choose which model renderer to use for the floating head. Auto prefers ModelScene if available; PlayerModel is the legacy fallback.',
                    values = function()
                        return { auto = 'Auto (prefer ModelScene)', scene = 'ModelScene (Retail)', player = 'PlayerModel (Legacy)' }
                    end,
                    hidden = function()
                        -- Only show when ModelScene is available in client
                        return not (CLN and CLN.ReplayFrame and CLN.ReplayFrame.IsModelSceneAvailable and CLN.ReplayFrame:IsModelSceneAvailable())
                    end,
                    get = function(info)
                        return CLN.db.profile.renderBackend or 'auto'
                    end,
                    set = function(info, value)
                        CLN.db.profile.renderBackend = value
                        -- Rebuild model host with new backend and refresh
                        if CLN.ReplayFrame and CLN.ReplayFrame.RebuildModelHost then
                            CLN.ReplayFrame:RebuildModelHost()
                        end
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
                            CLN.ReplayFrame:UpdateDisplayFrameState()
                        end
                    end,
                },
                -- Edit Mode specific settings removed
                queueTextScale = {
                    type = 'range',
                    name = 'Queue Text Scale',
                    desc = 'Scale the header and queue row text size.',
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
                compactMode = {
                    type = 'toggle',
                    name = 'Compact Mode (hide NPC model)',
                    desc = 'Hide the NPC model and shrink the queue frame width.',
                    get = function(info) return CLN.db.profile.compactMode end,
                    set = function(info, value)
                        CLN.db.profile.compactMode = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
                    end,
                },
                resetFramePos = {
                    type = 'execute',
                    name = 'Reset Replay Frame Position',
                    desc = 'Reset the replay frame position to its default values.',
                    func = function() CLN.ReplayFrame:ResetFramePosition() end,
                },
                editMode = {
                    type = 'toggle',
                    name = 'Edit Mode',
                    desc = 'Toggle edit mode for the replay frame. When enabled, you can move and resize the frame.',
                    get = function(info) 
                        return CLN.ReplayFrame and CLN.ReplayFrame._editMode or false
                    end,
                    set = function(info, value)
                        if not CLN.ReplayFrame then return end
                        if value then
                            -- Enter edit mode
                            CLN.ReplayFrame:ShowForEdit()
                        else
                            -- Exit edit mode
                            CLN.ReplayFrame:SetEditMode(false)
                            CLN.ReplayFrame._forceShow = false
                            if CLN.ReplayFrame.UpdateDisplayFrameState then
                                CLN.ReplayFrame:UpdateDisplayFrameState()
                            end
                        end
                    end,
                },
                showReplayFrame = {
                    type = 'toggle',
                    name = 'Show Floating Head Frame (voiceover queue)',
                    desc = 'Toggle to show the floating head frame (voiceover queue)',
                    get = function(info) return CLN.db.profile.showReplayFrame end,
                    set = function(info, value)
                        CLN.db.profile.showReplayFrame = value
                        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then CLN.ReplayFrame:UpdateDisplayFrameState() end
                    end,
                },
            },
        },
        PlaybackOptions = {
            order = 20,
            type = 'group',
            name = 'Playback Options',
            inline = true,
            args = {
                autoPlayVoiceovers = {
                    type = 'toggle',
                    name = 'Play on dialog window open',
                    desc = 'Toggle to play voiceovers when opening the gossip or quest window.',
                    get = function(info) return CLN.db.profile.autoPlayVoiceovers end,
                    set = function(info, value) CLN.db.profile.autoPlayVoiceovers = value end,
                },
                questPlaybackMode = {
                    type = 'select',
                    name = 'Quest Playback Mode',
                    desc = 'How quest voiceovers behave: Queue (play sequentially), Stop On Close (interrupt when window closes), or Manual (only on button press).',
                    values = {
                        queue = 'Queue (sequential, uninterrupted)',
                        stopOnClose = 'Stop On Close (interrupt when dialog closes)',
                        manual = 'Manual (never auto queue, only play button)'
                    },
                    get = function() return CLN.db.profile.questPlaybackMode or 'queue' end,
                    set = function(_, value)
                        CLN.db.profile.questPlaybackMode = value
                        if CLN._SyncLegacyQuestPlaybackFlags then CLN:_SyncLegacyQuestPlaybackFlags() end
                    end,
                },
                playVoiceoverAfterDelay = {
                    type = 'range',
                    name = 'Play Voiceover After A Delay',
                    desc = 'Set the delay (in seconds) before playing voiceovers after talking with questgiver.',
                    min = 0,
                    max = 3,
                    step = 0.1,
                    get = function(info) return CLN.db.profile.playVoiceoverAfterDelay end,
                    set = function(info, value) CLN.db.profile.playVoiceoverAfterDelay = value end,
                },
                audioChannel = {
                    type = 'select',
                    name = 'Audio Channels',
                    desc = 'Select the audio channel for voiceover playback.',
                    values = {
                        MASTER = 'MASTER',
                        DIALOG = 'DIALOG',
                        AMBIENCE = 'AMBIENCE',
                        MUSIC = 'MUSIC',
                        SFX = 'SFX',
                    },
                    get = function(info) return CLN.db.profile.audioChannel end,
                    set = function(info, value) CLN.db.profile.audioChannel = value end,
                },
                showSpeakButton = {
                    type = 'toggle',
                    name = 'Enable Speak/Play button for dialogs',
                    desc = 'Toggle to enable or disable Speak/Play button on next to the dialog frame.',
                    get = function(info) return CLN.db.profile.showSpeakButton end,
                    set = function(info, value) CLN.db.profile.showSpeakButton = value end,
                },
            },
        },
        QuestFrameButtonOptions = {
            order = 30,
            type = 'group',
            name = 'Quest And Gossip Frame Button Options',
            inline = true,
            args = {
                buttonPosX = {
                    type = 'range',
                    name = 'Button X Position',
                    desc = 'Set the X coordinate for the button position relative to the frame.',
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
                    type = 'range',
                    name = 'Button Y Position',
                    desc = 'Set the Y coordinate for the button position relative to the frame.',
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
                    type = 'execute',
                    name = 'Reset Button Positions',
                    desc = 'Reset the X and Y positions to their default values.',
                    func = function()
                        CLN.db.profile.buttonPosX = -15  -- Default X position
                        CLN.db.profile.buttonPosY = -30  -- Default Y position
                        CLN.PlayButton:UpdateButtonPositions()
                    end,
                },
            },
        }
    },
}

function Options:SetupOptions()
    if (not self.optionsFrame) then
        LibStub("AceConfig-3.0"):RegisterOptionsTable("ChattyLittleNpc", options)
        self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ChattyLittleNpc", "Chatty Little Npc")
    end
end

-- Initialize the Options module
Options:SetupOptions()

-- Helper for other modules to open the Settings category
function Options:OpenSettings()
    local dlg = LibStub("AceConfigDialog-3.0", true)
    if dlg and dlg.Open then
        dlg:Open("ChattyLittleNpc")
        return
    end
    if InterfaceOptionsFrame_OpenToCategory and self.optionsFrame then
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end