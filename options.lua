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
