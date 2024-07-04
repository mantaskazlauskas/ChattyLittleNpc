local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

function ChattyLittleNpc:HandleSlashCommands(msg)
    if msg == "stop-playback-on-close" then
        self.db.profile.playVoiceoversOnClose = false
        print("|cffffff00Chatty Little NPC:|r NPC voiceovers on dialog close are now disabled")
    elseif msg == "continue-playback-on-close" then
        self.db.profile.playVoiceoversOnClose = true
        print("|cffffff00Chatty Little NPC:|r NPC voiceovers on dialog close are now enabled")
    elseif msg == "print-missing-files" then
        self.db.profile.printMissingFiles = true
        print("|cffffff00Chatty Little NPC:|r Print the file name of missing files when talking to NPCs enabled")
    elseif msg == "help" then
        print("|cffffff00Available commands for ChattyLittleNPC:|r")
        print("|cffffff00/clnpc stop-playback-on-close|r - Disable NPC voiceovers on dialog close")
        print("|cffffff00/clnpc continue-playback-on-close|r - Enable NPC voiceovers after dialog close")
        print("|cffffff00/clnpc print-missing-files|r - Print file name if it is missing when talking to an npc")
    else
        print("|cffffff00Invalid command. Type /clnpc help for a list of commands.|r")
    end
end

ChattyLittleNpc:RegisterChatCommand("clnpc", "HandleSlashCommands")
