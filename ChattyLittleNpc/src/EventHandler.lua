---@class EventHandler
local EventHandler = {}

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- Register this module with the main addon
CLN.EventHandler = EventHandler

-- Create event system and timer instances
local events = ChattyLittleNpc.EventSystem:New()
local timer = ChattyLittleNpc.TimerUtil

-- Initialize the EventHandler module
function EventHandler:OnInitialize()

end

-- Register all events for ChattyLittleNpc
function EventHandler:RegisterEvents()
    events:RegisterEvent("ADDON_LOADED", function() self:ADDON_LOADED() end)
    events:RegisterEvent("GOSSIP_SHOW", function() self:GOSSIP_SHOW() end)
    events:RegisterEvent("GOSSIP_CLOSED", function() self:GOSSIP_CLOSED() end)
    events:RegisterEvent("QUEST_GREETING", function() self:QUEST_GREETING() end)
    events:RegisterEvent("QUEST_DETAIL", function() self:QUEST_DETAIL() end)
    events:RegisterEvent("QUEST_PROGRESS", function() self:QUEST_PROGRESS() end)
    events:RegisterEvent("QUEST_COMPLETE", function() self:QUEST_COMPLETE() end)
    events:RegisterEvent("QUEST_FINISHED", function() self:QUEST_FINISHED() end)
    events:RegisterEvent("ITEM_TEXT_READY", function() self:ITEM_TEXT_READY() end)
    events:RegisterEvent("CINEMATIC_START", function() self:CINEMATIC_START() end)
    events:RegisterEvent("PLAY_MOVIE", function() self:PLAY_MOVIE() end)
    events:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:PLAYER_REGEN_DISABLED() end)
    events:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:PLAYER_REGEN_ENABLED() end)
    CLN:RegisterMessage("VOICEOVER_STOP", function(...) self:OnVoiceoverStop(...) end)
end

-- Unregister all events for ChattyLittleNpc
function EventHandler:UnregisterEvents()
    events:UnregisterEvent("ADDON_LOADED")
    events:UnregisterEvent("GOSSIP_SHOW")
    events:UnregisterEvent("GOSSIP_CLOSED")
    events:UnregisterEvent("QUEST_GREETING")
    events:UnregisterEvent("QUEST_DETAIL")
    events:UnregisterEvent("QUEST_PROGRESS")
    events:UnregisterEvent("QUEST_COMPLETE")
    events:UnregisterEvent("QUEST_FINISHED")
    events:UnregisterEvent("ITEM_TEXT_READY")
    events:UnregisterEvent("CINEMATIC_START")
    events:UnregisterEvent("PLAY_MOVIE")
    events:UnregisterEvent("PLAYER_REGEN_DISABLED")
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    CLN:UnregisterMessage("VOICEOVER_STOP")
    -- Cancel the watcher timer to prevent callbacks on stale state
    if self.watcherTimer then
        timer:CancelTimer(self.watcherTimer)
        self.watcherTimer = nil
    end
end

-- Register a job that triggers events
function EventHandler:StartWatcher()
    -- Latch to avoid sending VOICEOVER_STOP repeatedly for the same sound handle
    self._stopLatchHandle = nil
    self.watcherTimer = timer:ScheduleRepeatingTimer(0.5, function()
        local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        if not cp then return end

        local handle = cp.soundHandle
        local isPlaying = cp.isPlaying and cp:isPlaying() or false

        -- If a new handle starts playing, clear the latch
        if handle and isPlaying and self._stopLatchHandle and self._stopLatchHandle ~= handle then
            if CLN and CLN.Logger then
                CLN.Logger:debug("Watcher: clearing stop latch for new handle " .. tostring(handle), false, CLN.Utils.LogCategories.loader)
            end
            self._stopLatchHandle = nil
        end

        -- Only emit stop once per handle, and only when we have a valid handle
        if handle and not isPlaying then
            if self._stopLatchHandle ~= handle then
                if CLN and CLN.Logger then
                    CLN.Logger:debug("Watcher: VOICEOVER_STOP for handle " .. tostring(handle), false, CLN.Utils.LogCategories.loader)
                end
                self._stopLatchHandle = handle
                CLN:SendMessage("VOICEOVER_STOP", cp)
            end
            return
        end
    end)
end

-- EVENT HANDLERS
function EventHandler:ADDON_LOADED()
    if CLN and CLN.Logger then CLN.Logger:debug("ADDON_LOADED", false, CLN.Utils.LogCategories.loader) end

    CLN.NpcDialogTracker:InitializeTables()
end

function EventHandler:GOSSIP_SHOW()
    if CLN and CLN.Logger then CLN.Logger:debug("GOSSIP_SHOW", false, CLN.Utils.LogCategories.loader) end

    local parentFrame = _G["DUIQuestFrame"] or GossipFrame
    local _, gender, _, _, unitType, unitId = CLN:GetUnitInfo("npc")
    local text = C_GossipInfo.GetText()
    if (not unitId or not unitType or not text) then
        if CLN and CLN.Logger then CLN.Logger:debug("No unitId, unitType or text found for gossip.", false, CLN.Utils.LogCategories.loader) end
        return
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleGossipText()
    end

    local hashes = CLN.Utils:GetHashes(unitId, text)
    local filePath = CLN.Utils:GetPathToNonQuestFile(unitId, "Gossip", hashes, gender)
    if not filePath or CLN.Utils:IsNilOrEmpty(filePath) then
        if CLN and CLN.Logger then CLN.Logger:debug("No file path found for gossip voiceover.", false, CLN.Utils.LogCategories.loader) end
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
    if CLN and CLN.Logger then CLN.Logger:debug("QUEST_GREETING", false, CLN.Utils.LogCategories.loader) end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_GREETING")
    end
end

function EventHandler:QUEST_DETAIL()
    if CLN and CLN.Logger then CLN.Logger:debug("QUEST_DETAIL", false, CLN.Utils.LogCategories.loader) end

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.DESC, select(6, CLN:GetUnitInfo("npc")))
        end)
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        CLN:HandlePlaybackStart(CLN.Utils.QuestPhases.DESC)
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_DETAIL")
    end
end

function EventHandler:QUEST_PROGRESS()
    if CLN and CLN.Logger then CLN.Logger:debug("QUEST_PROGRESS", false, CLN.Utils.LogCategories.loader) end

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.PROG, select(6, CLN:GetUnitInfo("npc")))
        end)
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        CLN:HandlePlaybackStart(CLN.Utils.QuestPhases.PROG)
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_PROGRESS")
    end
end

function EventHandler:QUEST_COMPLETE()
    if CLN and CLN.Logger then CLN.Logger:debug("QUEST_COMPLETE", false, CLN.Utils.LogCategories.loader) end

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.COMP, select(6, CLN:GetUnitInfo("npc")))
        end)
    end

    if (CLN.db.profile.autoPlayVoiceovers) then
        CLN:HandlePlaybackStart(CLN.Utils.QuestPhases.COMP)
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleQuestTexts("QUEST_COMPLETE")
    end
end

function EventHandler:ITEM_TEXT_READY()
    if CLN and CLN.Logger then CLN.Logger:debug("ITEM_TEXT_READY", false, CLN.Utils.LogCategories.loader) end

    local itemName = ItemTextGetItem()
    local itemText = ItemTextGetText()
    local itemId = C_Item.GetItemInfoInstant(itemName)
    local unitGuid = UnitGUID('npc')
    local unitType = "Item"

    if (CLN.db.profile.debugMode) then
        if CLN and CLN.Logger then
            CLN.Logger:debug("Item Name: " .. tostring(itemName), false, CLN.Utils.LogCategories.ui)
            CLN.Logger:debug("Item Text: " .. tostring(itemText), false, CLN.Utils.LogCategories.ui)
            CLN.Logger:debug("Item ID: " .. tostring(itemId), false, CLN.Utils.LogCategories.ui)
            CLN.Logger:debug("Unit GUID: " .. tostring(unitGuid), false, CLN.Utils.LogCategories.ui)
        end
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
            if CLN and CLN.Logger then
                CLN.Logger:debug("OnVoiceoverStop: deduped for handle " .. tostring(stoppedHandle), false, CLN.Utils.LogCategories.loader)
            end
            return
        end
        self._lastStoppedHandle = stoppedHandle
        self._lastStoppedTime = now
    end

    local removedFromQueue = false
    if stoppedVoiceover.questId then
        for i, quest in ipairs(CLN.questsQueue) do
            if (quest.questId == stoppedVoiceover.questId and quest.phase == stoppedVoiceover.phase) then
                if CLN and CLN.Logger then CLN.Logger:debug("Removing quest from queue:" .. tostring(quest.questId), false, CLN.Utils.LogCategories.loader) end
                table.remove(CLN.questsQueue, i)
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                removedFromQueue = true
                break
            end
        end
    end

    if removedFromQueue and (#CLN.questsQueue > 0) then
        if CLN and CLN.Logger then CLN.Logger:debug("Playing next quest in queue.", false, CLN.Utils.LogCategories.loader) end
        -- Ensure previous emote/animation state is clean before starting next
        if CLN.ReplayFrame and CLN.ReplayFrame.ResetAnimationState then
            local ok, err = pcall(CLN.ReplayFrame.ResetAnimationState, CLN.ReplayFrame)
            if (not ok) and CLN and CLN.Logger then
                CLN.Logger:warn("ResetAnimationState failed: " .. tostring(err), false, CLN.Utils.LogCategories.animation)
            end
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
            if CLN and CLN.Logger then CLN.Logger:debug("No more quests in queue, clearing currentlyPlaying and closing UI.", false, CLN.Utils.LogCategories.loader) end
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
    if CLN and CLN.Logger then CLN.Logger:debug("QUEST_FINISHED", false, CLN.Utils.LogCategories.loader) end
    local mode = CLN.db.profile.questPlaybackMode or "queue"
    if (mode == "stopOnClose" and CLN.VoiceoverPlayer.currentlyPlaying) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on quest finished.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:GOSSIP_CLOSED()
    if CLN and CLN.Logger then CLN.Logger:debug("GOSSIP_CLOSED", false, CLN.Utils.LogCategories.loader) end
    CLN.PlayButton:ClearButtons()

    local mode = CLN.db.profile.questPlaybackMode or "queue"
    if (mode == "stopOnClose" and CLN.VoiceoverPlayer.currentlyPlaying) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on gossip closed.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:CINEMATIC_START()
    if CLN and CLN.Logger then CLN.Logger:debug("CINEMATIC_START", false, CLN.Utils.LogCategories.loader) end
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on cinematic start.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:PLAY_MOVIE()
    if CLN and CLN.Logger then CLN.Logger:debug("PLAY_MOVIE", false, CLN.Utils.LogCategories.loader) end
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on movie play.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true)
    end
end

function EventHandler:PLAYER_REGEN_DISABLED()
    -- Combat started
    CLN._inCombat = true
    if CLN.ReplayFrame and CLN.ReplayFrame.OnCombatStart then
        CLN.ReplayFrame:OnCombatStart()
    end
end

function EventHandler:PLAYER_REGEN_ENABLED()
    -- Combat ended
    CLN._inCombat = false
    if CLN.ReplayFrame and CLN.ReplayFrame.OnCombatEnd then
        CLN.ReplayFrame:OnCombatEnd()
    end
end
