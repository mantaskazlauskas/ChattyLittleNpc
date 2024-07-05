---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")
ChattyLittleNpc.PlayButton = ChattyLittleNpc.PlayButton
ChattyLittleNpc.ReplayFrame = ChattyLittleNpc.ReplayFrame
ChattyLittleNpc.Options = ChattyLittleNpc.Options

local defaults = {
    profile = {
        playVoiceoversOnClose = true,
        printMissingFiles = false,
        framePos = { -- Default position
            point = "CENTER",
            relativeTo = nil,
            relativePoint = "CENTER",
            xOfs = 500,
            yOfs = 0
        }
    }
}

ChattyLittleNpc.lastSoundHandle = nil
ChattyLittleNpc.currentQuestId = nil
ChattyLittleNpc.currentPhase = nil
ChattyLittleNpc.currentQuestTitle = nil
ChattyLittleNpc.dialogState = nil
ChattyLittleNpc.expansions = { "Battle_for_Azeroth", "Cataclysm", "Classic", "Dragonflight", "Legion", "Mists_of_Pandaria", "Shadowlands", "The_Burning_Crusade", "The_War_Within", "Warlords_of_Draenor", "Wrath_of_the_Lich_King" }

function ChattyLittleNpc:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ChattyLittleNpcDB", defaults, true)
    self:RegisterChatCommand("clnpc", "HandleSlashCommands")
    self.Options:SetupOptions()
end

function ChattyLittleNpc:OnEnable()
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("GOSSIP_CLOSED")
    self:RegisterEvent("QUEST_FINISHED")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")

    if self.ReplayFrame.displayFrame then
        self.ReplayFrame:LoadFramePosition()
    end

    local detailsFrame = QuestMapFrame and QuestMapFrame.DetailsFrame
    if detailsFrame then
        self.PlayButton:AttachPlayButton(detailsFrame)
    end
    hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
    QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
    QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)
end

function ChattyLittleNpc:OnDisable()
    self:UnregisterEvent("QUEST_DETAIL")
    self:UnregisterEvent("GOSSIP_CLOSED")
    self:UnregisterEvent("QUEST_FINISHED")
    self:UnregisterEvent("QUEST_PROGRESS")
    self:UnregisterEvent("QUEST_COMPLETE")
end

function ChattyLittleNpc:IsDialogEnabled()
    local isDialogEnabled = GetCVar("Sound_EnableDialog");
    return isDialogEnabled
end

function ChattyLittleNpc:MuteDialogSound()
    SetCVar("Sound_EnableDialog", 0)
end

function ChattyLittleNpc:SaveDialogState()
    self.dialogState = nil
    self.dialogState = self:IsDialogEnabled()
end

function ChattyLittleNpc:ResetDialogToLastState()
    if (self.dialogState ~= nil) then
        SetCVar("Sound_EnableDialog", self.dialogState)
    end

    self.dialogState = nil
end

function ChattyLittleNpc:StopCurrentSound()
    if self.lastSoundHandle and type(self.lastSoundHandle) == "number" then
        StopSound(self.lastSoundHandle)
        self.lastSoundHandle = nil
    end
end

function ChattyLittleNpc:GetTitleForQuestID(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif QuestUtils_GetQuestName then
        return QuestUtils_GetQuestName(questID)
    end
end

function ChattyLittleNpc:PlayQuestSound(questId, phase)
    self:StopCurrentSound()
    self.currentQuestId = questId
    self.currentPhase = phase

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = questId .. "_" .. phase .. ".mp3"
    local soundPath, success, newSoundHandle

    success = false

    for _, folder in ipairs(self.expansions) do
        soundPath = basePath .. folder .. "\\" .. "voiceovers" .. "\\" .. fileName
        success, newSoundHandle = PlaySoundFile(soundPath, "Master")
        if success then
            self.lastSoundHandle = newSoundHandle
            local questTitle = self:GetTitleForQuestID(questId)
            ChattyLittleNpc.currentQuestTitle = questTitle
            local suffix = ""
            if phase == "Desc" then
                suffix = "(description)"
            elseif phase == "Prog" then
                suffix = "(progression)"
            elseif phase == "Comp" then
                suffix = "(completion)"
            end

            self.ReplayFrame:ShowDisplayFrame()
            break
        end
    end

    if not success and self.db.profile.printMissingFiles then
        print("Missing voiceover file: " .. fileName)
    end
end

function ChattyLittleNpc:QUEST_DETAIL()
    ChattyLittleNpc:HandlePlaybackStart("Desc")
end

function ChattyLittleNpc:QUEST_PROGRESS()
    ChattyLittleNpc:HandlePlaybackStart("Prog")
end

function ChattyLittleNpc:QUEST_COMPLETE()
    ChattyLittleNpc:HandlePlaybackStart("Comp")
end

function ChattyLittleNpc:GOSSIP_CLOSED()
    ChattyLittleNpc:HandlePlaybackStop()
end

function ChattyLittleNpc:QUEST_FINISHED()
    ChattyLittleNpc:HandlePlaybackStop()
end


function ChattyLittleNpc:HandlePlaybackStart(questPhase)
    self:SaveDialogState()
    if (self.dialogState) then
        self:MuteDialogSound()
    end

    local questId = GetQuestID()
    self:PlayQuestSound(questId, questPhase)
end

function ChattyLittleNpc:HandlePlaybackStop()
    self:ResetDialogToLastState()
    if not self.db.profile.playVoiceoversOnClose then
        self:StopCurrentSound()
        if self.ReplayFrame then self.ReplayFrame:Hide() end
    end
end