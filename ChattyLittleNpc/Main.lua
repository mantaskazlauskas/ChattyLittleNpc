---@class ChattyLittleNpc: table, AceAddon-3.0, AceConsole-3.0, AceEvent-3.0
local CLN = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")

---@class EventHandler
local EventHandler = LibStub("AceAddon-3.0"):GetAddon("EventHandler")
EventHandler:SetChattyLittleNpcReference(CLN)

---@class Options
local Options = LibStub("AceAddon-3.0"):GetAddon("Options")
Options:SetChattyLittleNpcReference(CLN)

CLN.locale = nil
CLN.gameVersion = nil
CLN.useNamespaces = nil
CLN.expansions = { "Battle_for_Azeroth_voiceovers", "Cataclysm_voiceovers", "Vanilla_voiceovers", "Dragonflight_voiceovers", "Legion_voiceovers", "Mists_of_Pandaria_voiceovers", "Shadowlands_voiceovers", "The_Burning_Crusade_voiceovers", "The_War_Within_voiceovers", "Warlords_of_Draenor_voiceovers", "Wrath_of_the_Lich_King_voiceovers" }
CLN.loadedVoiceoverPacks = {}
CLN.VoiceoverPacks = {}
CLN.questsQueue = {}
CLN.isDUIAddonLoaded = false
CLN.isElvuiAddonLoaded = false
CLN.currentItemInfo = {
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
        overwriteExistingGossipValues = false,
        showGossipEditor = false,
        showReplayFrame = true,
        showSpeakButton = true,
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
        audioChannel = "MASTER",
        debugMode = false,
        ShowReplayFrameIfDialogueUIAddonIsLoaded = false
    }
}

function CLN:OnInitialize()
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

function CLN:OnEnable()
    EventHandler:RegisterEvents()

    if (self.ReplayFrame.DisplayFrame) then
        self.ReplayFrame:LoadFramePosition()
    end

    self.PlayButton:AttachQuestLogAndDetailsButtons()

    if type(QuestMapFrame_UpdateAll) == "function" then
        hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
    end

    if (QuestMapFrame) then
        QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
        QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)
    end

    self:GetLoadedExpansionVoiceoverPacks()
    self:GetLoadedAddonsForIntegrations()

    if (self.db.profile.logNpcTexts) then
        self.NpcDialogTracker:GatherTooltipInfo()
    end
end

function CLN:OnDisable()
    EventHandler:UnregisterEvents()
end

--[[
    Retrieves information about a specified unit.

    @param unit (string) - The identifier of the unit to retrieve information for.
]]
function CLN:GetUnitInfo(unit)
    local unitName = select(1, UnitName(unit)) or ""
    local sex = UnitSex(unit) -- 1 = neutral, 2 = male, 3 = female
    local sexStr = (sex == 1 and "Neutral") or (sex == 2 and "Male") or (sex == 3 and "Female") or ""
    local race = UnitRace(unit) or ""

    local unitGuid = UnitGUID(unit)
    local unitType = nil
    local unitId = nil

    if (unitGuid) then
        unitType = select(1, strsplit("-", unitGuid))
        if (unitType == "Creature" or unitType == "Vehicle" or unitType == "GameObject") then
            local idString = select(6, strsplit("-", unitGuid))
            unitId = tonumber(idString)
        end
    end

    return unitName, sexStr, race, unitGuid, unitType, unitId
end

--[[
    Retrieves the title of a quest given its quest ID.
    
    @param questID number: The unique identifier for the quest.
    @return string: The title of the quest.
]]
function CLN:GetTitleForQuestID(questID)
    if (self.useNamespaces) then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif (QuestUtils_GetQuestName) then
        return QuestUtils_GetQuestName(questID)
    end
end

--[[
    Retrieves the list of loaded expansion voiceover packs for the ChattyLittleNpc addon.

    @return table: A table containing the loaded expansion voiceover packs.
]]
function CLN:GetLoadedExpansionVoiceoverPacks()
    for _, expansion in ipairs(self.expansions) do
        local voiceoverPackName = "ChattyLittleNpc_" .. expansion
        local isLoaded = C_AddOns.IsAddOnLoaded(voiceoverPackName)
        if (isLoaded) then
            table.insert(self.loadedVoiceoverPacks, expansion)
            if (self.db.profile.debugMode) then
                self:Print("Loaded voiceover pack:", expansion)
            end

            local addon = LibStub("AceAddon-3.0"):GetAddon(voiceoverPackName, true)
            if addon then
                self.VoiceoverPacks[voiceoverPackName] = addon
            end
        end      
    end

    if (self.db.profile.debugMode) then
        self:PrintLoadedVoiceoverPacks()
    end
end

function CLN:PrintLoadedVoiceoverPacks()
    for packName, packData in pairs(self.VoiceoverPacks) do
        if packData.Metadata then
            self:Print("Metadata for", "|cffffd700" .. packName .. "|r", ":")
            self.Utils:PrintTable(packData.Metadata)
        end
        if packData.Voiceovers then
            self:Print("VO count ", "|cffffd700" .. packName .. "|r", ":", #packData.Voiceovers)
        end
    end
end

--[[
    Handles the start of playback for a given quest phase.

    @param questPhase (number) - The phase of the quest for which playback is starting.
]]
function CLN:HandlePlaybackStart(questPhase)
    local questId = GetQuestID()
    local npcId = select(6, self:GetUnitInfo("npc"))
    local gender = select(2, self:GetUnitInfo("npc"))
    
    if (questId > 0) then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.VoiceoverPlayer:PlayQuestSound(questId, questPhase, npcId)
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
function CLN:HandleGossipPlaybackStart(text, soundType, id)
    local idAsNumber = tonumber(id)
    if (idAsNumber and idAsNumber > 0 and text) then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.VoiceoverPlayer:PlayNonQuestSound(id, soundType, text)
        end)
    end
end

function CLN:GetLoadedAddonsForIntegrations()
    self.isDUIAddonLoaded = C_AddOns.IsAddOnLoaded("DialogueUI")
    if (self.db.profile.debugMode) then
        self:Print("DUI Addon Loaded:", self.isDUIAddonLoaded)
    end

    self.isElvuiAddonLoaded = C_AddOns.IsAddOnLoaded("ElvUI")
    if (self.db.profile.debugMode) then
        self:Print("ElvUI Addon Loaded:", self.isElvuiAddonLoaded)
    end

    if (self.isElvuiAddonLoaded) then
        self.PlayButton:AttachQuestLogAndDetailsButtons()
    end
end

CLN:OnInitialize()