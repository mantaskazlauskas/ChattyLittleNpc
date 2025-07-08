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
        DebuggingImprovements = {
            type = 'group',
            name = 'Debugging and Improvements',
            inline = true,
            args = {
                printMissingFiles = {
                    type = 'toggle',
                    name = 'Print Missing Files',
                    desc = 'Toggle to print missing voiceover files.',
                    get = function(info) return CLN.db.profile.printMissingFiles end,
                    set = function(info, value) CLN.db.profile.printMissingFiles = value end,
                },
                logNpcTexts = {
                    type = 'toggle',
                    name = 'Track NPC data',
                    desc = 'Toggle to save all the texts that an npc has to saved variables. (Enable if you want to contribute to addon development by helping to gather data for voiceover generation. Contact us on discord if you want to help.)',
                    get = function(info) return CLN.db.profile.logNpcTexts end,
                    set = function(info, value)
                        CLN.db.profile.logNpcTexts = value
                        if (not value) then
                            CLN.db.profile.printNpcTexts = false
                        end
                    end,
                },
                overwriteExistingGossipValues = {
                    type = 'toggle',
                    name = 'Overwrite existing values.',
                    desc = 'Overwrite existing values of gathered npc texts when interacting not the first time.',
                    get = function(info) return CLN.db.profile.overwriteExistingGossipValues end,
                    set = function(info, value) CLN.db.profile.overwriteExistingGossipValues = value end,
                },
                printNpcTexts = {
                    type = 'toggle',
                    name = 'Print NPC data (if tracking enabled)',
                    desc = 'Toggle to print the data that is being collected by npc dialog tracker (if it is enabled).',
                    get = function(info) return CLN.db.profile.printNpcTexts end,
                    set = function(info, value) CLN.db.profile.printNpcTexts = value end,
                },
                debugMode = {
                    type = 'toggle',
                    name = 'Print Debug Messages',
                    desc = 'Toggle to print debug messages.',
                    get = function(info) return CLN.db.profile.debugMode end,
                    set = function(info, value) CLN.db.profile.debugMode = value end,
                },
                showGossipEditor = {
                    type = 'toggle',
                    name = 'Show Gossip Editor',
                    desc = 'Toggle to show the Gossip Editor window (used for editing/fixing collected npc gossip lines).',
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
                    name = 'Print VO Pack metadata',
                    desc = 'Print what VO packs were loaded, what kind of voiceovers they support and how many voiceovers they have.',
                    func = function() CLN:PrintLoadedVoiceoverPacks() end,
                },
            },
        },
        ReplayFrame = {
            type = 'group',
            name = 'Replay Frame',
            inline = true,
            args = {
                resetFramePos = {
                    type = 'execute',
                    name = 'Reset Replay Frame Position',
                    desc = 'Reset the replay frame position to its default values.',
                    func = function() CLN.ReplayFrame:ResetFramePosition() end,
                },
                showReplayFrame = {
                    type = 'toggle',
                    name = 'Show Replay Window',
                    desc = 'Toggle to show the replay window.',
                    get = function(info) return CLN.db.profile.showReplayFrame end,
                    set = function(info, value) CLN.db.profile.showReplayFrame = value end,
                },
            },
        },
        PlaybackOptions = {
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
                stopVoiceoverAfterDialogWindowClose = {
                    type = 'toggle',
                    name = 'Stop on dialog window close',
                    desc = 'Only play voiceover while the npc dialog window is open, and auto stop voiceover after the dialog window is closed. (Quest queueing will be disabled)',
                    get = function(info) return CLN.db.profile.stopVoiceoverAfterDialogWindowClose end,
                    set = function(info, value)
                        CLN.db.profile.stopVoiceoverAfterDialogWindowClose = value
                        if (value) then
                            CLN.db.profile.enableQuestPlaybackQueueing = false
                        end
                    end
                },
                enableQuestPlaybackQueueing = {
                    type = 'toggle',
                    name = 'Enable Quest Playback Queueing',
                    desc = 'Toggle to enable or disable quest playback queueing. (Stop on dialog window close will be disabled)',
                    get = function(info) return CLN.db.profile.enableQuestPlaybackQueueing end,
                    set = function(info, value)
                        CLN.db.profile.enableQuestPlaybackQueueing = value
                        if (value) then
                            CLN.db.profile.stopVoiceoverAfterDialogWindowClose = false
                        end
                    end
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
        },
        Integrations = {
            type = 'group',
            name = 'Integrations',
            inline = true,
            args = {
                ShowReplayFrameIfDialogueUIAddonIsLoaded = {
                    type = 'toggle',
                    name = 'Show Floating head frame with DialogueUI frame',
                    desc = 'When using DialogueUI addon, toggle if you want to see the floating head frame at the same time as DialogueUI frame.',
                    get = function(info) return CLN.db.profile.ShowReplayFrameIfDialogueUIAddonIsLoaded end,
                    set = function(info, value) CLN.db.profile.ShowReplayFrameIfDialogueUIAddonIsLoaded = value end,
                },
            }
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