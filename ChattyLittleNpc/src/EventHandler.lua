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
    -- Latch to avoid sending VOICEOVER_STOP repeatedly for the same sound handle
    self._stopLatchHandle = nil
    self:ScheduleRepeatingTimer(function()
        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        if not cp then return end

        local handle = cp.soundHandle
        local isPlaying = cp.isPlaying and cp:isPlaying() or false

        -- If a new handle starts playing, clear the latch
        if handle and isPlaying and self._stopLatchHandle and self._stopLatchHandle ~= handle then
            if CLN and CLN.Utils and CLN.Utils.LogDebug then
                CLN.Utils:LogDebug("Watcher: clearing stop latch for new handle " .. tostring(handle))
            end
            self._stopLatchHandle = nil
        end

        -- Only emit stop once per handle, and only when we have a valid handle
        if handle and not isPlaying then
            if self._stopLatchHandle ~= handle then
                if CLN and CLN.Utils and CLN.Utils.LogDebug then
                    CLN.Utils:LogDebug("Watcher: VOICEOVER_STOP for handle " .. tostring(handle))
                end
                self._stopLatchHandle = handle
                self:SendMessage("VOICEOVER_STOP", cp)
            end
            return
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
    local _, gender, _, _, unitType, unitId = CLN:GetUnitInfo("npc")
    local text = C_GossipInfo.GetText()
    if (not unitId or not unitType or not text) then
        CLN.Utils:LogDebug("No unitId, unitType or text found for gossip.")
        return
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleGossipText()
    end

    local hashes = CLN.Utils:GetHashes(unitId, text)
    local filePath = CLN.Utils:GetPathToNonQuestFile(unitId, "Gossip", hashes, gender)
    if not filePath or CLN.Utils:IsNilOrEmpty(filePath) then
        CLN.Utils:LogDebug("No file path found for gossip voiceover.")
        return
    end

    CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.GossipButton ,function()
        CLN.VoiceoverPlayer:PlayNonQuestSound(unitId, "Gossip", text, gender)
    end)

    if (CLN.db.profile.autoPlayVoiceovers) then
        local type = "Gossip"

        if (unitType == "GameObject") then
            type = "GameObject"
        end

        CLN:HandleGossipPlaybackStart(unitId, text, type, gender)
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
            itemId = tonumber(itemId) or 0
        end
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleItemTextReady(itemId, itemText, itemName)
    end

    CLN:HandleGossipPlaybackStart(itemId, itemText, unitType)
end

function EventHandler:OnVoiceoverStop(event, stoppedVoiceover)
    -- Deduplicate rapid repeated stops for the same handle
    local stoppedHandle = stoppedVoiceover and stoppedVoiceover.soundHandle
    local now = (type(GetTime) == "function") and GetTime() or 0
    if stoppedHandle then
        if self._lastStoppedHandle == stoppedHandle and self._lastStoppedTime and (now - self._lastStoppedTime) < 1.0 then
            if CLN and CLN.Utils and CLN.Utils.LogDebug then
                CLN.Utils:LogDebug("OnVoiceoverStop: deduped for handle " .. tostring(stoppedHandle))
            end
            return
        end
        self._lastStoppedHandle = stoppedHandle
        self._lastStoppedTime = now
    end

    for i, quest in ipairs(CLN.questsQueue) do
        if (quest.questId == stoppedVoiceover.questId and quest.phase == stoppedVoiceover.phase) then
            CLN.Utils:LogDebug("Removing quest from queue:" .. quest.questId)
            table.remove(CLN.questsQueue, i)
            if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
            break
        end
    end

    if (#CLN.questsQueue > 0) then
        CLN.Utils:LogDebug("Playing next quest in queue.")
        -- Ensure previous emote/animation state is clean before starting next
        if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
            CLN.ReplayFrame:ResetAnimationState()
        end
        local nextQuest = CLN.questsQueue[1]
        CLN.VoiceoverPlayer.queueProcessed = false
        CLN.VoiceoverPlayer:PlayQuestSound(nextQuest.questId, nextQuest.phase, nextQuest.npcId)
    else
        -- Nothing left in the queue; clear current if it matches the stopped handle
        local curr = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        local currHandle = curr and curr.soundHandle or nil
        local stillPlaying = curr and curr.isPlaying and curr:isPlaying() or false
        if not stillPlaying or (stoppedHandle and currHandle == stoppedHandle) then
            CLN.Utils:LogDebug("No more quests in queue, clearing currentlyPlaying and closing UI.")
	        CLN.VoiceoverPlayer.currentlyPlaying = CLN.VoiceoverPlayer:GetCurrentlyPlayingObject()
            CLN.VoiceoverPlayer.queueProcessed = true
        end
        -- Conversation stopped; refresh UI and let FSM drive farewell/hide
        if CLN.ReplayFrame and CLN.ReplayFrame.UpdateDisplayFrameState then
            CLN.ReplayFrame:UpdateDisplayFrameState()
        end
        if CLN.ReplayFrame and CLN.ReplayFrame.OnConversationStop then
            CLN.ReplayFrame:OnConversationStop()
        end
    end
end

function EventHandler:QUEST_FINISHED()
    CLN.Utils:LogDebug("QUEST_FINISHED")
    if (CLN.db.profile.stopVoiceoverAfterDialogWindowClose and CLN.VoiceoverPlayer.currentlyPlaying) then
        CLN.Utils:LogDebug("Stopping currently playing voiceover on quest finished.")
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:GOSSIP_CLOSED()
    CLN.Utils:LogDebug("GOSSIP_CLOSED")
    CLN.PlayButton:ClearButtons()

    if (CLN.db.profile.stopVoiceoverAfterDialogWindowClose and CLN.VoiceoverPlayer.currentlyPlaying) then
        CLN.Utils:LogDebug("Stopping currently playing voiceover on gossip closed.")
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:CINEMATIC_START()
    CLN.Utils:LogDebug("CINEMATIC_START")
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        CLN.Utils:LogDebug("Stopping currently playing voiceover on cinematic start.")
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:PLAY_MOVIE()
    CLN.Utils:LogDebug("PLAY_MOVIE")
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        CLN.Utils:LogDebug("Stopping currently playing voiceover on movie play.")
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

-- Initialize the EventHandler module
EventHandler:OnInitialize()

-- Start the watcher
EventHandler:StartWatcher()