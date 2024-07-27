---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local Options = {}
ChattyLittleNpc.Options = Options

local options = {
    name = "Chatty Little Npc",
    handler = ChattyLittleNpc,
    type = 'group',
    args = {
        useMaleVoice = {
            type = 'toggle',
            name = 'Use Male Voice',
            desc = 'Toggle to play voiceovers in a male voice.',
            get = function(info) return ChattyLittleNpc.db.profile.useMaleVoice end,
            set = function(info, value)
                ChattyLittleNpc.db.profile.useMaleVoice = value
                if value then
                    ChattyLittleNpc.db.profile.useFemaleVoice = false
                    ChattyLittleNpc.db.profile.useBothVoices = false
                end
            end,
        },
        useFemaleVoice = {
            type = 'toggle',
            name = 'Use Female Voice',
            desc = 'Toggle to play voiceovers in a female voice.',
            get = function(info) return ChattyLittleNpc.db.profile.useFemaleVoice end,
            set = function(info, value)
                ChattyLittleNpc.db.profile.useFemaleVoice = value
                if value then
                    ChattyLittleNpc.db.profile.useMaleVoice = false
                    ChattyLittleNpc.db.profile.useBothVoices = false
                end
            end,
        },
        useBothVoices = {
            type = 'toggle',
            name = 'Use Both Voices',
            desc = 'Toggle to play voiceovers in male and female voices if possible.',
            get = function(info) return ChattyLittleNpc.db.profile.useBothVoices end,
            set = function(info, value)
                ChattyLittleNpc.db.profile.useBothVoices = value
                if value then
                    ChattyLittleNpc.db.profile.useMaleVoice = false
                    ChattyLittleNpc.db.profile.useFemaleVoice = false
                end
            end,
        },
        playVoiceoversOnClose = {
            type = 'toggle',
            name = 'Play Voiceovers On Close',
            desc = 'Toggle to play voiceovers when closing the gossip or quest window.',
            get = function(info) return ChattyLittleNpc.db.profile.playVoiceoversOnClose end,
            set = function(info, value) ChattyLittleNpc.db.profile.playVoiceoversOnClose = value end,
        },
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
        resetFramePos = {
            type = 'execute',
            name = 'Reset Replay Frame Position',
            desc = 'Reset the replay frame position to its default values.',
            func = function() ChattyLittleNpc.ReplayFrame:ResetFramePosition() end,
        },
    },
}

function Options:SetupOptions()
    if not self.optionsFrame then
        LibStub("AceConfig-3.0"):RegisterOptionsTable("ChattyLittleNpc", options)
        self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ChattyLittleNpc", "Chatty Little Npc")
    end
end

Options:SetupOptions()
