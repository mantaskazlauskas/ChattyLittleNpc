---@class EventHandler
local EventHandler = LibStub("AceAddon-3.0"):NewAddon("EventHandler", "AceEvent-3.0", "AceTimer-3.0")

local ChattyLittleNpc

-- Set the reference to ChattyLittleNpc
function EventHandler:SetChattyLittleNpcReference(reference)
    ChattyLittleNpc = reference
end

-- Initialize the EventHandler module
function EventHandler:OnInitialize()

end

-- Register all events for ChattyLittleNpc
function EventHandler:RegisterEvents()
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("GOSSIP_CLOSED")
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("QUEST_FINISHED")
    self:RegisterEvent("ITEM_TEXT_READY")
    self:RegisterMessage("VOICEOVER_STOP", "OnVoiceoverStop")
end

-- Unregister all events for ChattyLittleNpc
function EventHandler:UnregisterEvents()
    self:UnregisterEvent("ADDON_LOADED")
    self:UnregisterEvent("GOSSIP_SHOW")
    self:UnregisterEvent("GOSSIP_CLOSED")
    self:UnregisterEvent("QUEST_GREETING")
    self:UnregisterEvent("QUEST_DETAIL")
    self:UnregisterEvent("QUEST_PROGRESS")
    self:UnregisterEvent("QUEST_COMPLETE")
    self:UnregisterEvent("QUEST_FINISHED")
    self:UnregisterEvent("ITEM_TEXT_READY")
    self:UnregisterMessage("VOICEOVER_STOP")
end

-- Register a job that triggers events
function EventHandler:StartWatcher()
    self:ScheduleRepeatingTimer(function()
        local currentlyPlaying = ChattyLittleNpc.Voiceovers.currentlyPlaying
        if currentlyPlaying and not currentlyPlaying.isPlaying then
            self:SendMessage("VOICEOVER_STOP", currentlyPlaying)
            return
        end

        if currentlyPlaying and currentlyPlaying.soundHandle and currentlyPlaying.isPlaying then
            if not C_Sound.IsPlaying(currentlyPlaying.soundHandle) then
                currentlyPlaying.isPlaying = false
                self:SendMessage("VOICEOVER_STOP", currentlyPlaying)
                return
            end
        end
    end, 0.5)
end

-- EVENT HANDLERS
function EventHandler:ADDON_LOADED()
    ChattyLittleNpc.NpcDialogTracker:InitializeTables()
end

function EventHandler:GOSSIP_SHOW()
    if ChattyLittleNpc.db.profile.autoPlayVoiceovers then
        local gossipText = C_GossipInfo.GetText()
        local _, gender, _, _, unitType, unitId = ChattyLittleNpc:GetUnitInfo("npc")
        local soundType = "Gossip"
        if unitType == "GameObject" then
            soundType = "GameObject"
        end
        ChattyLittleNpc:HandleGossipPlaybackStart(gossipText, soundType, unitId, gender)
    end

    if ChattyLittleNpc.db.profile.logNpcTexts then
        ChattyLittleNpc.NpcDialogTracker:HandleGossipText()
    end
end

function EventHandler:QUEST_GREETING()
    if ChattyLittleNpc.db.profile.logNpcTexts then
        ChattyLittleNpc.NpcDialogTracker:HandleQuestTexts("QUEST_GREETING")
    end
end

function EventHandler:QUEST_DETAIL()
    if ChattyLittleNpc.db.profile.autoPlayVoiceovers then
        ChattyLittleNpc:HandlePlaybackStart("Desc")
    end

    if ChattyLittleNpc.db.profile.logNpcTexts then
        ChattyLittleNpc.NpcDialogTracker:HandleQuestTexts("QUEST_DETAIL")
    end
end

function EventHandler:QUEST_PROGRESS()
    if ChattyLittleNpc.db.profile.autoPlayVoiceovers then
        ChattyLittleNpc:HandlePlaybackStart("Prog")
    end

    if ChattyLittleNpc.db.profile.logNpcTexts then
        ChattyLittleNpc.NpcDialogTracker:HandleQuestTexts("QUEST_PROGRESS")
    end
end

function EventHandler:QUEST_COMPLETE()
    if ChattyLittleNpc.db.profile.autoPlayVoiceovers then
        ChattyLittleNpc:HandlePlaybackStart("Comp")
    end

    if ChattyLittleNpc.db.profile.logNpcTexts then
        ChattyLittleNpc.NpcDialogTracker:HandleQuestTexts("QUEST_COMPLETE")
    end
end

function EventHandler:ITEM_TEXT_READY()
    local itemName = ItemTextGetItem()
    local itemText = ItemTextGetText()
    local itemId = C_Item.GetItemInfoInstant(itemName)
    local unitGuid = UnitGUID('npc')
    local unitType = "Item"

    if (ChattyLittleNpc.db.profile.debugMode) then
        ChattyLittleNpc:Print("Item Name:", itemName)
        ChattyLittleNpc:Print("Item Text:", itemText)
        ChattyLittleNpc:Print("Item ID:", itemId)
        ChattyLittleNpc:Print("Unit GUID:", unitGuid)
    end

    if not itemId and itemName and itemText and unitGuid then
        unitType = select(1, string.split('-', unitGuid))
        if unitType == "GameObject" then
            itemId = select(6, string.split("-", unitGuid));
        end
    end
    if ChattyLittleNpc.db.profile.logNpcTexts then
        ChattyLittleNpc.NpcDialogTracker:HandleItemTextReady(itemId, itemText, itemName)
    end
    ChattyLittleNpc:HandleGossipPlaybackStart(itemText, unitType ,itemId)
end

function EventHandler:OnVoiceoverStop(event, stoppedVoiceover)
    for i, quest in ipairs(ChattyLittleNpc.questsQueue) do
        if quest.questId == stoppedVoiceover.questId and quest.phase == stoppedVoiceover.phase then
            if (ChattyLittleNpc.db.profile.debugMode) then
                ChattyLittleNpc:Print("Removing quest from queue:", quest.questId)
            end

            table.remove(ChattyLittleNpc.questsQueue, i)
            break
        end
    end

    if #ChattyLittleNpc.questsQueue > 0 then
        local nextQuest = ChattyLittleNpc.questsQueue[1]
        ChattyLittleNpc.Voiceovers:PlayQuestSound(nextQuest.questId, nextQuest.phase, nextQuest.npcId, nextQuest.gender)
    else
        ChattyLittleNpc.currentItemInfo = {}
        ChattyLittleNpc.ReplayFrame:UpdateDisplayFrame()
    end
end

function EventHandler:QUEST_FINISHED()
    if ChattyLittleNpc.db.profile.stopVoiceoverAfterDialogWindowClose and ChattyLittleNpc.Voiceovers.currentlyPlaying then
        ChattyLittleNpc.Voiceovers.StopCurrentSound()
        ChattyLittleNpc.Voiceovers.currentlyPlaying.isPlaying = false
    end
end

function EventHandler:GOSSIP_CLOSED()
    if ChattyLittleNpc.db.profile.stopVoiceoverAfterDialogWindowClose and ChattyLittleNpc.Voiceovers.currentlyPlaying then
        ChattyLittleNpc.Voiceovers.StopCurrentSound()
        ChattyLittleNpc.Voiceovers.currentlyPlaying.isPlaying = false
    end
end

-- Initialize the EventHandler module
EventHandler:OnInitialize()

-- Start the watcher
EventHandler:StartWatcher()