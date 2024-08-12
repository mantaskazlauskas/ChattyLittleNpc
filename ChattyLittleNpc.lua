---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")
ChattyLittleNpc.PlayButton = ChattyLittleNpc.PlayButton
ChattyLittleNpc.ReplayFrame = ChattyLittleNpc.ReplayFrame
ChattyLittleNpc.Options = ChattyLittleNpc.Options
ChattyLittleNpc.NpcDialogTracker = ChattyLittleNpc.NpcDialogTracker

local defaults = {
    profile = {
        playVoiceoversOnClose = true,
        playVoiceoverAfterDelay = 0,
        printMissingFiles = false,
        logNpcTexts = false,
        printNpcTexts = false,
        showReplayFrame = true,
        framePos = { -- Default position
            point = "CENTER",
            relativeTo = nil,
            relativePoint = "CENTER",
            xOfs = 500,
            yOfs = 0
        }
    }
}

ChattyLittleNpc.locale = nil
ChattyLittleNpc.gameVersion = nil
ChattyLittleNpc.useNamespaces = nil
ChattyLittleNpc.lastSoundHandle = nil
ChattyLittleNpc.currentQuestId = nil
ChattyLittleNpc.currentPhase = nil
ChattyLittleNpc.currentQuestTitle = nil
ChattyLittleNpc.expansions = { "Battle_for_Azeroth", "Cataclysm", "Classic", "Dragonflight", "Legion", "Mists_of_Pandaria", "Shadowlands", "The_Burning_Crusade", "The_War_Within", "Warlords_of_Draenor", "Wrath_of_the_Lich_King" }
ChattyLittleNpc.loadedVoiceoverPacks = {}
ChattyLittleNpc.currentItemInfo = {
    ItemID = nil,
    ItemName = nil,
    ItemText = nil
}


hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot, onSelf)
    ChattyLittleNpc.currentItemInfo.ItemID = nil
    ChattyLittleNpc.currentItemInfo.ItemName = nil
    ChattyLittleNpc.currentItemInfo.ItemText = nil
    local itemID = C_Container.GetContainerItemID(bag, slot)
    if itemID then
        local itemName = select(1 ,C_Item.GetItemInfo(itemID))
        ChattyLittleNpc.currentItemInfo.ItemID = itemID
        ChattyLittleNpc.currentItemInfo.ItemName = itemName
        local itemText = ItemTextGetText()
        if(itemText) then
            ChattyLittleNpc.currentItemInfo.ItemText = itemText
        end
    end
end)

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

    hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
    QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
    QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)

    self:GetLoadedExpansionVoiceoverPacks()
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

function ChattyLittleNpc:StopCurrentSound()
    if self.lastSoundHandle and type(self.lastSoundHandle) == "number" then
        StopSound(self.lastSoundHandle)
        self.lastSoundHandle = nil
    end

    self.ReplayFrame.currentPlayingQuest = nil
    self.ReplayFrame:UpdateDisplayFrame()
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

function ChattyLittleNpc:PlayQuestSound(questId, phase, npcGender)
    self:StopCurrentSound()
    self.currentQuestId = questId
    self.currentPhase = phase

    local basePath = "Interface\\AddOns\\ChattyLittleNpc_"
    local fileName = questId .. "_" .. phase .. ".mp3"
    local success, newSoundHandle

    local suffix = ""
    if phase == "Desc" then
        suffix = " (description"
    elseif phase == "Prog" then
        suffix = " (progression"
    elseif phase == "Comp" then
        suffix = " (completion"
    end

    success = false
    for _, folder in ipairs(self.loadedVoiceoverPacks) do
        local corePathToVoiceovers = basePath .. folder .. "\\" .. "voiceovers" .. "\\"
        local soundPath = ChattyLittleNpc:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
        local retryCount = 0
        repeat
            if success == nil then
                if retryCount == 1 then
                    soundPath = self:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 2 then
                    soundPath = self:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
                elseif retryCount == 3 then
                    soundPath = self:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
                end
                retryCount = retryCount + 1
            end
            success, newSoundHandle = PlaySoundFile(soundPath, "Master")
        until success or retryCount > 3  -- Retry until success or tried all voiceover directories

        if success then
            self.lastSoundHandle = newSoundHandle
            self.currentQuestTitle = self:GetTitleForQuestID(questId)
            self.ReplayFrame:AddQuestToQueue(questId, self.currentQuestTitle .. suffix .. ")", phase, npcGender)
            self.ReplayFrame:ShowDisplayFrame()
            break
        end
    end

    if not success and self.db.profile.printMissingFiles then
        self.currentQuestTitle = self:GetTitleForQuestID(questId)
        self.ReplayFrame:AddQuestToQueue(questId, self.currentQuestTitle .. suffix .. ", voiceover missing)", phase, npcGender)
        print("Missing voiceover file: " .. fileName)
    end

    self.ReplayFrame.currentPlayingQuest = questId .. phase -- Track the currently playing quest
    self.ReplayFrame:UpdateDisplayFrame()
end

function ChattyLittleNpc:GetVoiceoversPath(corePathToVoiceovers, fileName, npcGender)
    if npcGender and (strlower(npcGender) == "male" or strlower(npcGender) == "female") then
        return corePathToVoiceovers .. strlower(npcGender) .. "\\".. fileName
    else
        return self:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
    end
end

function ChattyLittleNpc:GetFemaleVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. "female" .. "\\".. fileName
end

function ChattyLittleNpc:GetMaleVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. "male" .. "\\".. fileName
end

function ChattyLittleNpc:GetOldVoiceoversPath(corePathToVoiceovers, fileName)
    return corePathToVoiceovers .. fileName -- try the old directory if user didnt update voiceovers
end

function ChattyLittleNpc:ADDON_LOADED()
    self.NpcDialogTracker:InitializeTables()
end

function ChattyLittleNpc:GOSSIP_SHOW()
    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleGossipText()
    end
end

function ChattyLittleNpc:GOSSIP_CLOSED()
    self:HandlePlaybackStop()
end

function ChattyLittleNpc:QUEST_GREETING()
    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_GREETING")
    end
end

function ChattyLittleNpc:QUEST_DETAIL()
    self:HandlePlaybackStart("Desc")

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_DETAIL")
    end
end

function ChattyLittleNpc:QUEST_PROGRESS()
    self:HandlePlaybackStart("Prog")

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_PROGRESS")
    end
end

function ChattyLittleNpc:QUEST_COMPLETE()
    self:HandlePlaybackStart("Comp")

    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleQuestTexts("QUEST_COMPLETE")
    end
end

function ChattyLittleNpc:QUEST_FINISHED()
    self:HandlePlaybackStop()
end

function ChattyLittleNpc:ITEM_TEXT_READY()
    if self.db.profile.logNpcTexts then
        self.NpcDialogTracker:HandleItemTextReady()
    end
end

function ChattyLittleNpc:HandlePlaybackStart(questPhase)
    local questId = GetQuestID()
    local gender = select(2, self:GetUnitInfo("npc"))
    if questId > 0 then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self:PlayQuestSound(questId, questPhase, gender)
        end)
    end
end

function ChattyLittleNpc:HandlePlaybackStop()
    if not self.db.profile.playVoiceoversOnClose then
        self:StopCurrentSound()
        if self.ReplayFrame then
            self.ReplayFrame.displayFrame:Hide()
        end
    end
end