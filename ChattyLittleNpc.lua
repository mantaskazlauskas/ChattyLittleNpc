---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")
ChattyLittleNpc.PlayButton = ChattyLittleNpc.PlayButton
ChattyLittleNpc.ReplayFrame = ChattyLittleNpc.ReplayFrame
ChattyLittleNpc.Options = ChattyLittleNpc.Options
ChattyLittleNpc.NpcDialogTracker = ChattyLittleNpc.NpcDialogTracker
ChattyLittleNpc.Voiceovers = ChattyLittleNpc.Voiceovers
ChattyLittleNpc.MD5 = ChattyLittleNpc.MD5
ChattyLittleNpc.Base64 = ChattyLittleNpc.Base64

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
        enableQuestPlaybackQueueing = true
    }
}

ChattyLittleNpc.locale = nil
ChattyLittleNpc.gameVersion = nil
ChattyLittleNpc.useNamespaces = nil
ChattyLittleNpc.expansions = { "Battle_for_Azeroth", "Cataclysm", "Classic", "Dragonflight", "Legion", "Mists_of_Pandaria", "Shadowlands", "The_Burning_Crusade", "The_War_Within", "Warlords_of_Draenor", "Wrath_of_the_Lich_King" }
ChattyLittleNpc.loadedVoiceoverPacks = {}
ChattyLittleNpc.questsQueue = {}
ChattyLittleNpc.currentItemInfo = {
    ItemID = nil,
    ItemName = nil,
    ItemText = nil
}

function ChattyLittleNpc:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ChattyLittleNpcDB", defaults, true)
    self.Options:SetupOptions()

    self.locale = GetLocale()
    self.gameVersion = select(4, GetBuildInfo())
    self.useNamespaces = self.gameVersion >= 90000 -- namespaces were added in starting Shadowlands
end

function ChattyLittleNpc:OnEnable()
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("GOSSIP_CLOSED")
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("QUEST_FINISHED")
    self:RegisterEvent("ITEM_TEXT_READY")

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
    if self.db.profile.enableQuestPlaybackQueueing then
        self.Voiceovers:StartSoundMonitor()
    end
end

function ChattyLittleNpc:OnDisable()
    self:UnregisterEvent("ADDON_LOADED")
    self:UnregisterEvent("GOSSIP_SHOW")
    self:UnregisterEvent("GOSSIP_CLOSED")
    self:UnregisterEvent("QUEST_GREETING")
    self:UnregisterEvent("QUEST_DETAIL")
    self:UnregisterEvent("QUEST_PROGRESS")
    self:UnregisterEvent("QUEST_COMPLETE")
    self:UnregisterEvent("QUEST_FINISHED")
    self:UnregisterEvent("ITEM_TEXT_READY")
end

function ChattyLittleNpc:CleanText(text)
    text = text:gsub("\n\n", " ")
    text = text:gsub("\r\n", " ")
    text = text:gsub("<HTML>", "")
    text = text:gsub("</HTML>", "")
    text = text:gsub("<BODY>", "")
    text = text:gsub("</BODY>", "")
    text = text:gsub("<BR/>", "")
    text = text:gsub("<p>", "")
    text = text:gsub("</p>", "")
    text = text:gsub("<p align=\"center\">", "")
    text = text:gsub(UnitName("player"), "Hero")
    text = text:gsub(UnitClass("player"), "Hero")
    text = text:gsub(UnitRace("player"), "Hero")
    return text
end

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

function ChattyLittleNpc:GetTitleForQuestID(questID)
    if self.useNamespaces then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif QuestUtils_GetQuestName then
        return QuestUtils_GetQuestName(questID)
    end
end

function ChattyLittleNpc:GetLoadedExpansionVoiceoverPacks()
    for _, expansion in ipairs(self.expansions) do
        local voiceoverPackName = "ChattyLittleNpc_" .. expansion
        local isLoaded = C_AddOns.IsAddOnLoaded(voiceoverPackName)
        if isLoaded then
            table.insert(self.loadedVoiceoverPacks, expansion)
        end
    end
end

function ChattyLittleNpc:ADDON_LOADED()
    self.NpcDialogTracker:InitializeTables()
end

function ChattyLittleNpc:GOSSIP_SHOW()
    if self.db.profile.autoPlayVoiceovers then
        local gossipText = C_GossipInfo.GetText()
        local _, gender, _, _, unitType, unitId = self:GetUnitInfo("npc")
        local soundType = "Gossip"
        if unitType == "GameObject" then
            soundType = "GameObject"
        end
        self:HandleGossipPlaybackStart(gossipText, soundType, unitId, gender)
    end

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleGossipText()
    end
end

function ChattyLittleNpc:GOSSIP_CLOSED()

end

function ChattyLittleNpc:QUEST_GREETING()
    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_GREETING")
    end
end

function ChattyLittleNpc:QUEST_DETAIL()
    if self.db.profile.autoPlayVoiceovers then
        self:HandlePlaybackStart("Desc")
    end

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_DETAIL")
    end
end

function ChattyLittleNpc:QUEST_PROGRESS()
    if self.db.profile.autoPlayVoiceovers then
        self:HandlePlaybackStart("Prog")
    end

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_PROGRESS")
    end
end

function ChattyLittleNpc:QUEST_COMPLETE()
    if self.db.profile.autoPlayVoiceovers then
        self:HandlePlaybackStart("Comp")
    end

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_COMPLETE")
    end
end

function ChattyLittleNpc:QUEST_FINISHED()

end

function ChattyLittleNpc:ITEM_TEXT_READY()
    local itemName = ItemTextGetItem()
    local itemText = ItemTextGetText()
    local itemId = C_Item.GetItemInfoInstant(itemName)
    local unitGuid = UnitGUID('npc')
    local unitType = "Item"
    if not itemId and itemName and itemText and unitGuid then
        unitType = select(1, string.split('-', unitGuid))
        if unitType == "GameObject" then
            itemId = select(6, string.split("-", unitGuid));
            print("Item ID: " .. itemId)
        end
    end
    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleItemTextReady(itemId, itemText, itemName)
    end
    self:HandleGossipPlaybackStart(itemText, unitType ,itemId)
end

function ChattyLittleNpc:HandlePlaybackStart(questPhase)
    local questId = GetQuestID()
    local gender = select(2, self:GetUnitInfo("npc"))
    if questId > 0 then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.Voiceovers:PlayQuestSound(questId, questPhase, gender)
        end)
    end
end

function ChattyLittleNpc:HandleGossipPlaybackStart(text, soundType, id, gender)
    local idAsNumber = tonumber(id)
    if idAsNumber and idAsNumber > 0 and text then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.Voiceovers:PlayNonQuestSound(id, soundType, text, gender)
        end)
    end
end