---@class EventHandler: table, AceEvent-3.0, AceTimer-3.0
local EventHandler = LibStub("AceAddon-3.0"):NewAddon("EventHandler", "AceEvent-3.0", "AceTimer-3.0")

---@class ChattyLittleNpc: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0
local CLN

-- Set the reference to ChattyLittleNpc
function EventHandler:SetChattyLittleNpcReference(reference)
    CLN = reference
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
    self:RegisterEvent("CINEMATIC_START")
    self:RegisterEvent("PLAY_MOVIE")
    -- self:RegisterEvent("CHAT_MSG_MONSTER_SAY")
    -- self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
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
    self:UnregisterEvent("CINEMATIC_START")
    self:UnregisterEvent("PLAY_MOVIE")
    self:UnregisterMessage("VOICEOVER_STOP")
end

-- Register a job that triggers events
function EventHandler:StartWatcher()
    self:ScheduleRepeatingTimer(function()
        local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
        if (currentlyPlaying and not currentlyPlaying.isPlaying) then
            self:SendMessage("VOICEOVER_STOP", currentlyPlaying)
            return
        end

        if (currentlyPlaying and currentlyPlaying.soundHandle and currentlyPlaying.isPlaying) then
            if (not C_Sound.IsPlaying(currentlyPlaying.soundHandle)) then
                currentlyPlaying.isPlaying = false
                self:SendMessage("VOICEOVER_STOP", currentlyPlaying)
                return
            end
        end
    end, 0.5)
end

-- EVENT HANDLERS
function EventHandler:ADDON_LOADED()
    CLN.Utils:LogDebug("ADDON_LOADED")

    CLN.NpcDialogTracker:InitializeTables()
end

function EventHandler:GOSSIP_SHOW()
    CLN.Utils:LogDebug("GOSSIP_SHOW")

    local parentFrame = _G["DUIQuestFrame"] or GossipFrame
    local unitId = select(6, CLN:GetUnitInfo("npc"))
    local gossipText = C_GossipInfo.GetText()
    local hashes = CLN.Utils:GetHashes(unitId, gossipText)

    if (hashes) then
        for _, hash in ipairs(hashes) do
            local fileName = unitId .. "_".. "Gossip" .."_" .. hash .. ".ogg"
            for _, packData in pairs(CLN.VoiceoverPacks) do
                local fileNameFound = CLN.Utils:ContainsString(packData.Voiceovers, fileName)
                if (fileNameFound) then
                    CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.GossipButton ,function()
                        CLN.VoiceoverPlayer:PlayNonQuestSound(unitId, "Gossip", gossipText)
                    end)
                end
            end
        end
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        local gossipText = C_GossipInfo.GetText()
        local _, _, _, _, unitType, unitId = CLN:GetUnitInfo("npc")
        local soundType = "Gossip"

        if (unitType == "GameObject") then
            soundType = "GameObject"
        end

        CLN:HandleGossipPlaybackStart(gossipText, soundType, unitId)
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleGossipText()
    end
end

function EventHandler:QUEST_GREETING()
    CLN.Utils:LogDebug("QUEST_GREETING")

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_GREETING")
    end
end

function EventHandler:QUEST_DETAIL()
    CLN.Utils:LogDebug("QUEST_DETAIL")

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), "Desc", select(6, CLN:GetUnitInfo("npc")))
        end)
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        CLN:HandlePlaybackStart("Desc")
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_DETAIL")
    end
end

function EventHandler:QUEST_PROGRESS()
    CLN.Utils:LogDebug("QUEST_PROGRESS")

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), "Prog", select(6, CLN:GetUnitInfo("npc")))
        end)
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        CLN:HandlePlaybackStart("Prog")
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_PROGRESS")
    end
end

function EventHandler:QUEST_COMPLETE()
    CLN.Utils:LogDebug("QUEST_COMPLETE")

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), "Comp", select(6, CLN:GetUnitInfo("npc")))
        end)
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        CLN:HandlePlaybackStart("Comp")
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_COMPLETE")
    end
end

function EventHandler:ITEM_TEXT_READY()
    CLN.Utils:LogDebug("ITEM_TEXT_READY")

    local itemName = ItemTextGetItem()
    local itemText = ItemTextGetText()
    local itemId = C_Item.GetItemInfoInstant(itemName)
    local unitGuid = UnitGUID('npc')
    local unitType = "Item"

    if (CLN.db.profile.debugMode) then
        CLN:Print("Item Name:", itemName)
        CLN:Print("Item Text:", itemText)
        CLN:Print("Item ID:", itemId)
        CLN:Print("Unit GUID:", unitGuid)
    end

    if (_G["ItemTextFrame"]) then
        CLN.PlayButton:CreatePlayVoiceoverButton(_G["ItemTextFrame"], CLN.PlayButton.ItemTextButton, function()
            CLN.VoiceoverPlayer:PlayNonQuestSound(itemId, unitType, itemText)
        end)
    end

    if (not itemId and itemName and itemText and unitGuid) then
        unitType = select(1, string.split('-', unitGuid))
        if (unitType == "GameObject") then
            itemId = select(6, string.split("-", unitGuid));
        end
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleItemTextReady(itemId, itemText, itemName)
    end

    CLN:HandleGossipPlaybackStart(itemText, unitType ,itemId)
end

function EventHandler:OnVoiceoverStop(event, stoppedVoiceover)
    for i, quest in ipairs(CLN.questsQueue) do
        if (quest.questId == stoppedVoiceover.questId and quest.phase == stoppedVoiceover.phase) then
            CLN.Utils:LogDebug("Removing quest from queue:" .. quest.questId)
            table.remove(CLN.questsQueue, i)
            break
        end
    end

    if (#CLN.questsQueue > 0) then
        local nextQuest = CLN.questsQueue[1]
        CLN.VoiceoverPlayer:PlayQuestSound(nextQuest.questId, nextQuest.phase, nextQuest.npcId)
    else
        CLN.VoiceoverPlayer.currentlyPlaying = nil
        CLN.ReplayFrame:UpdateDisplayFrameState()
    end
end

function EventHandler:QUEST_FINISHED()
    CLN.Utils:LogDebug("QUEST_FINISHED")
    if (CLN.db.profile.stopVoiceoverAfterDialogWindowClose and CLN.VoiceoverPlayer.currentlyPlaying) then
        CLN.VoiceoverPlayer.currentlyPlaying.isPlaying = false
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:GOSSIP_CLOSED()
    CLN.Utils:LogDebug("GOSSIP_CLOSED")
    CLN.PlayButton:ClearButtons()

    if (CLN.db.profile.stopVoiceoverAfterDialogWindowClose and CLN.VoiceoverPlayer.currentlyPlaying) then
        CLN.VoiceoverPlayer.currentlyPlaying.isPlaying = false
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:CINEMATIC_START()
    CLN.Utils:LogDebug("CINEMATIC_START")
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.isPlaying) then
        CLN.VoiceoverPlayer.currentlyPlaying.isPlaying = false
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:PLAY_MOVIE()
    CLN.Utils:LogDebug("PLAY_MOVIE")
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.isPlaying) then
        CLN.VoiceoverPlayer.currentlyPlaying.isPlaying = false
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

-- function EventHandler:CHAT_MSG_MONSTER_SAY(self, event, msg)
--     ChattyLittleNpc:Print("CHAT_MSG_MONSTER_SAY",event, msg)
-- end

-- function EventHandler:CHAT_MSG_MONSTER_YELL(self, event, msg)
--     ChattyLittleNpc:Print("CHAT_MSG_MONSTER_YELL", event, msg)
-- end

-- Initialize the EventHandler module
EventHandler:OnInitialize()

-- Start the watcher
EventHandler:StartWatcher()