---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")
ChattyLittleNpc.PlayButton = ChattyLittleNpc.PlayButton
ChattyLittleNpc.ReplayFrame = ChattyLittleNpc.ReplayFrame

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

local lastSoundHandle = nil
ChattyLittleNpc.currentQuestId = nil
ChattyLittleNpc.currentPhase = nil
ChattyLittleNpc.currentQuestTitle = nil
local expansions = { "Battle_for_Azeroth", "Cataclysm", "Classic", "Dragonflight", "Legion", "Mists_of_Pandaria", "Shadowlands", "The_Burning_Crusade", "The_War_Within", "Warlords_of_Draenor", "Wrath_of_the_Lich_King" }

function ChattyLittleNpc:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ChattyLittleNpcDB", defaults, true)
    self:RegisterChatCommand("chattylittlenpc", "HandleSlashCommands")
    self:SetupOptions()
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

function ChattyLittleNpc:StopCurrentSound()
    if lastSoundHandle and type(lastSoundHandle) == "number" then
        StopSound(lastSoundHandle)
        lastSoundHandle = nil
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

    for _, folder in ipairs(expansions) do
        soundPath = basePath .. folder .. "\\" .. "voiceovers" .. "\\" .. fileName
        success, newSoundHandle = PlaySoundFile(soundPath, "Master")
        if success then
            lastSoundHandle = newSoundHandle
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
    local questId = GetQuestID()
    self:PlayQuestSound(questId, "Desc")
end

function ChattyLittleNpc:QUEST_PROGRESS()
    local questId = GetQuestID()
    self:PlayQuestSound(questId, "Prog")
end

function ChattyLittleNpc:QUEST_COMPLETE()
    local questId = GetQuestID()
    self:PlayQuestSound(questId, "Comp")
end

function ChattyLittleNpc:GOSSIP_CLOSED()
    if not self.db.profile.playVoiceoversOnClose then
        self:StopCurrentSound()
        if self.ReplayFrame then self.ReplayFrame:Hide() end
    end
end

function ChattyLittleNpc:QUEST_FINISHED()
    if not self.db.profile.playVoiceoversOnClose then
        self:StopCurrentSound()
        if self.ReplayFrame then self.ReplayFrame:Hide() end
    end
end