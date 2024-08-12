---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local Options = {}
ChattyLittleNpc.Options = Options

local options = {
    name = "Chatty Little Npc",
    handler = ChattyLittleNpc,
    type = 'group',
    args = {
        debuggingImprovements = {
            type = 'group',
            name = 'Debugging and Improvements',
            inline = true,
            args = {
                printMissingFiles = {
                    type = 'toggle',
                    name = 'Print Missing Files',
                    desc = 'Toggle to print missing voiceover files.',
                    get = function(info) return ChattyLittleNpc.db.profile.printMissingFiles end,
                    set = function(info, value) ChattyLittleNpc.db.profile.printMissingFiles = value end,
                },
                logNpcTexts = {
                    type = 'toggle',
                    name = 'Track NPC data',
                    desc = 'Toggle to save all the texts that an npc has to saved variables. (Enable if you want to contribute to addon development by helping to gather data for voiceover generation. Contact us on discord if you want to help.)',
                    get = function(info) return ChattyLittleNpc.db.profile.logNpcTexts end,
                    set = function(info, value)
                        ChattyLittleNpc.db.profile.logNpcTexts = value
                        if not value then
                            ChattyLittleNpc.db.profile.printNpcTexts = false
                        end
                    end,
                },
                printNpcTexts = {
                    type = 'toggle',
                    name = 'Print NPC data (if tracking enabled)',
                    desc = 'Toggle to print the data that is being collected by npc dialog tracker (if it is enabled).',
                    get = function(info) return ChattyLittleNpc.db.profile.printNpcTexts end,
                    set = function(info, value) ChattyLittleNpc.db.profile.printNpcTexts = value end,
                },
            },
        },
        replayFrame = {
            type = 'group',
            name = 'Replay Frame',
            inline = true,
            args = {
                resetFramePos = {
                    type = 'execute',
                    name = 'Reset Replay Frame Position',
                    desc = 'Reset the replay frame position to its default values.',
                    func = function() ChattyLittleNpc.ReplayFrame:ResetFramePosition() end,
                },
                showReplayFrame = {
                    type = 'toggle',
                    name = 'Show Replay Window',
                    desc = 'Toggle to show the replay window.',
                    get = function(info) return ChattyLittleNpc.db.profile.showReplayFrame end,
                    set = function(info, value) ChattyLittleNpc.db.profile.showReplayFrame = value end,
                },
            },
        },
        playbackOptions = {
            type = 'group',
            name = 'Playback Options',
            inline = true,
            args = {
                playVoiceoversOnClose = {
                    type = 'toggle',
                    name = 'Play Voiceovers On Close',
                    desc = 'Toggle to play voiceovers when closing the gossip or quest window.',
                    get = function(info) return ChattyLittleNpc.db.profile.playVoiceoversOnClose end,
                    set = function(info, value) ChattyLittleNpc.db.profile.playVoiceoversOnClose = value end,
                },
                playVoiceoverAfterDelay = {
                    type = 'range',
                    name = 'Play Voiceover After A Delay',
                    desc = 'Set the delay (in seconds) before playing voiceovers after talking with questgiver.',
                    min = 0,
                    max = 3,
                    step = 0.1,
                    get = function(info) return ChattyLittleNpc.db.profile.playVoiceoverAfterDelay end,
                    set = function(info, value) ChattyLittleNpc.db.profile.playVoiceoverAfterDelay = value end,
                },
            },
        },
    },
}

function Options:SetupOptions()
    if not self.optionsFrame then
        LibStub("AceConfig-3.0"):RegisterOptionsTable("ChattyLittleNpc", options)
        self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ChattyLittleNpc", "Chatty Little Npc")
    end
end
