---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")

-- Load the EventHandler module
local EventHandler = LibStub("AceAddon-3.0"):GetAddon("EventHandler")
EventHandler:SetChattyLittleNpcReference(ChattyLittleNpc)

-- Load the Options module
local Options = LibStub("AceAddon-3.0"):GetAddon("Options")
Options:SetChattyLittleNpcReference(ChattyLittleNpc)


ChattyLittleNpc.PlayButton = ChattyLittleNpc.PlayButton
ChattyLittleNpc.ReplayFrame = ChattyLittleNpc.ReplayFrame
ChattyLittleNpc.NpcDialogTracker = ChattyLittleNpc.NpcDialogTracker
ChattyLittleNpc.Voiceovers = ChattyLittleNpc.Voiceovers
ChattyLittleNpc.MD5 = ChattyLittleNpc.MD5
ChattyLittleNpc.Base64 = ChattyLittleNpc.Base64
ChattyLittleNpc.Utils = ChattyLittleNpc.Utils

ChattyLittleNpc.locale = nil
ChattyLittleNpc.gameVersion = nil
ChattyLittleNpc.useNamespaces = nil
ChattyLittleNpc.expansions = { "Battle_for_Azeroth", "Cataclysm", "Vanilla", "Dragonflight", "Legion", "Mists_of_Pandaria", "Shadowlands", "The_Burning_Crusade", "The_War_Within", "Warlords_of_Draenor", "Wrath_of_the_Lich_King" }
ChattyLittleNpc.loadedVoiceoverPacks = {}
ChattyLittleNpc.questsQueue = {}
ChattyLittleNpc.currentItemInfo = {
    ItemID = nil,
    ItemName = nil,
    ItemText = nil
}

local defaults = {
    profile = {
        autoPlayVoiceovers = true,
        playVoiceoverAfterDelay = 0,
        printMissingFiles = false,
        logNpcTexts = false,
        printNpcTexts = false,
        showReplayFrame = true,
        framePos = { -- Default positiond
            point = "CENTER",
            relativeTo = nil,
            relativePoint = "CENTER",
            xOfs = 500,
            yOfs = 0
        },
        buttonPosX = -15,
        buttonPosY = -30,
        enableQuestPlaybackQueueing = true,
        stopVoiceoverAfterDialogWindowClose = false,
        debugMode = false
    }
}

function ChattyLittleNpc:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ChattyLittleNpcDB", defaults, true)

    self.locale = GetLocale()
    self.gameVersion = select(4, GetBuildInfo())
    self.useNamespaces = self.gameVersion >= 90000 -- namespaces were added in starting Shadowlands

    if (self.db.profile.debugMode) then
        local version, build, date, tocVersion = GetBuildInfo()
        self:Print("Game Version:", version)
        self:Print("Build Number:", build)
        self:Print("Build Date:", date)
        self:Print("TOC Version:", tocVersion)
    end
end

function ChattyLittleNpc:OnEnable()
    EventHandler:RegisterEvents()

    if self.ReplayFrame.displayFrame then
        self.ReplayFrame:LoadFramePosition()
    end

    local detailsFrame = QuestMapFrame and QuestMapFrame.DetailsFrame
    if detailsFrame then
        self.PlayButton:AttachPlayButton("TOPRIGHT", detailsFrame, "TOPRIGHT", -20, -10, "ChattyNPCPlayButton")
    end

    if QuestLogFrame then
        self.PlayButton:AttachPlayButton("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -140, -40, "ChattyNPCQuestLogFramePlayButton")
    end

    if QuestLogDetailFrame then
        self.PlayButton:AttachPlayButton("TOPRIGHT", QuestLogDetailFrame, "TOPRIGHT", -140, -40, "ChattyNPCQuestLogDetailFramePlayButton")
    end

    if GossipFrame then
        self.PlayButton:CreateGossipButton()
    end

    if QuestFrame then
        self.PlayButton:CreatePlayQuestVoiceoverButton()
    end

    hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
    QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
    QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)

    self:GetLoadedExpansionVoiceoverPacks()
end

function ChattyLittleNpc:OnDisable()
    EventHandler:UnregisterEvents()
end

--[[
    Retrieves information about a specified unit.

    @param unit (string) - The identifier of the unit to retrieve information for.
]]
function ChattyLittleNpc:GetUnitInfo(unit)
    local unitName = select(1, UnitName(unit)) or ""
    local sex = UnitSex(unit) -- 1 = neutral, 2 = male, 3 = female
    local sexStr = (sex == 1 and "Neutral") or (sex == 2 and "Male") or (sex == 3 and "Female") or ""
    local race = UnitRace(unit) or ""

    local unitGuid = UnitGUID(unit)
    local unitType = nil
    local unitId = nil
    if unitGuid then
        unitType = select(1, strsplit("-", unitGuid))
        if unitType == "Creature" or unitType == "Vehicle" or unitType == "GameObject" then
            local idString = select(6, strsplit("-", unitGuid))
            unitId = tonumber(idString)
        end
    end

    return unitName, sexStr, race, unitGuid, unitType, unitId
end

-- Retrieves the title of a quest given its quest ID.
-- @param questID number: The unique identifier for the quest.
-- @return string: The title of the quest.
function ChattyLittleNpc:GetTitleForQuestID(questID)
    if self.useNamespaces then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif QuestUtils_GetQuestName then
        return QuestUtils_GetQuestName(questID)
    end
end

--[[
    Retrieves the list of loaded expansion voiceover packs for the ChattyLittleNpc addon.

    @return table: A table containing the loaded expansion voiceover packs.
]]
function ChattyLittleNpc:GetLoadedExpansionVoiceoverPacks()
    for _, expansion in ipairs(self.expansions) do
        local voiceoverPackName = "ChattyLittleNpc_" .. expansion
        local isLoaded = C_AddOns.IsAddOnLoaded(voiceoverPackName)
        if isLoaded then
            table.insert(self.loadedVoiceoverPacks, expansion)
            if(self.db.profile.debugMode) then
                self:Print("Loaded voiceover pack:", expansion)
            end
        end
    end
end

--[[
    Handles the start of playback for a given quest phase.

    @param questPhase (number) - The phase of the quest for which playback is starting.
]]
function ChattyLittleNpc:HandlePlaybackStart(questPhase)
    local questId = GetQuestID()
    local npcId = select(6, self:GetUnitInfo("npc"))
    local gender = select(2, self:GetUnitInfo("npc"))
    if questId > 0 then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.Voiceovers:PlayQuestSound(questId, questPhase, npcId, gender)
        end)
    end
end


--[[
    Handles the start of gossip playback.

    @param text string: The text of the gossip.
    @param soundType number: The type of sound associated with the gossip.
    @param id number: The ID of the gossip.
    @param gender number: The gender associated with the gossip.
]]
function ChattyLittleNpc:HandleGossipPlaybackStart(text, soundType, id, gender)
    local idAsNumber = tonumber(id)
    if idAsNumber and idAsNumber > 0 and text then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.Voiceovers:PlayNonQuestSound(id, soundType, text, gender)
        end)
    end
end

ChattyLittleNpc:OnInitialize()