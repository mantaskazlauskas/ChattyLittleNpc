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
    -- Native NPC voiceover detection (experimental)
    events:RegisterEvent("CHAT_MSG_MONSTER_SAY", function(...) self:OnNpcChatMessage(...) end)
    events:RegisterEvent("CHAT_MSG_MONSTER_YELL", function(...) self:OnNpcChatMessage(...) end)
    events:RegisterEvent("CHAT_MSG_MONSTER_WHISPER", function(...) self:OnNpcChatMessage(...) end)
    events:RegisterEvent("CHAT_MSG_MONSTER_EMOTE", function(...) self:OnNpcChatMessage(...) end)
    events:RegisterEvent("TALKINGHEAD_REQUESTED", function() self:OnTalkingHeadRequested() end)
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
    events:UnregisterEvent("CHAT_MSG_MONSTER_SAY")
    events:UnregisterEvent("CHAT_MSG_MONSTER_YELL")
    events:UnregisterEvent("CHAT_MSG_MONSTER_WHISPER")
    events:UnregisterEvent("CHAT_MSG_MONSTER_EMOTE")
    events:UnregisterEvent("TALKINGHEAD_REQUESTED")
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

        -- Skip watcher logic while paused for native VO (handle is nil, resume timer is pending)
        if cp._pausedForNativeVO then return end

        local handle = cp.soundHandle
        -- Use IsEffectivelyPlaying (with grace period) to avoid false stop detection
        -- during dialog transitions where C_Sound.IsPlaying briefly returns false
        local isPlaying = CLN.VoiceoverPlayer.IsEffectivelyPlaying
            and CLN.VoiceoverPlayer:IsEffectivelyPlaying()
            or (cp.isPlaying and cp:isPlaying() or false)

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
            local did = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.DESC, select(6, CLN:GetUnitInfo("npc")), did)
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
            local did = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.PROG, select(6, CLN:GetUnitInfo("npc")), did)
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
            local did = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.COMP, select(6, CLN:GetUnitInfo("npc")), did)
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

    -- Push to replay history
    if stoppedVoiceover and (stoppedVoiceover.title or stoppedVoiceover.questId) and CLN.ReplayFrame and CLN.ReplayFrame.PushHistory then
        -- Title may be nil if C_QuestLog wasn't ready at playback start; retry now
        local title = stoppedVoiceover.title
        if not title and stoppedVoiceover.questId then
            title = CLN:GetTitleForQuestID(stoppedVoiceover.questId)
        end
        CLN.ReplayFrame:PushHistory({
            title = title,
            npcId = stoppedVoiceover.npcId,
            questId = stoppedVoiceover.questId,
            phase = stoppedVoiceover.phase,
            entryType = stoppedVoiceover.entryType or (stoppedVoiceover.questId and "quest" or "unknown"),
            gender = stoppedVoiceover.gender,
            displayID = stoppedVoiceover.displayID,
            completedAt = GetTime and GetTime() or 0,
        })
    end

    -- Try to remove the stopped voiceover from the queue (it may already have
    -- been removed at play-start by PlayQuestSound, which is the normal case).
    if stoppedVoiceover.questId then
        for i, quest in ipairs(CLN.questsQueue) do
            if (quest.questId == stoppedVoiceover.questId and quest.phase == stoppedVoiceover.phase) then
                if CLN and CLN.Logger then CLN.Logger:debug("Removing quest from queue:" .. tostring(quest.questId), false, CLN.Utils.LogCategories.loader) end
                table.remove(CLN.questsQueue, i)
                if CLN.ReplayFrame and CLN.ReplayFrame.MarkQueueDirty then CLN.ReplayFrame:MarkQueueDirty() end
                break
            end
        end
    end

    -- Advance the queue regardless of whether the stopped item was found in it;
    -- PlayQuestSound removes the item from the queue at play-start (line 197),
    -- so the currently-playing sound is almost never in questsQueue when it stops.
    if CLN.VoiceoverPlayer._paused then
        -- Queue is frozen while paused; don't advance
        if CLN and CLN.Logger then CLN.Logger:debug("Queue paused, skipping advancement.", false, CLN.Utils.LogCategories.loader) end
    elseif #CLN.questsQueue > 0 then
        -- Deduplicate before advancing to avoid playing the same thing twice
        CLN.VoiceoverPlayer:DeduplicateQueue()
        if #CLN.questsQueue > 0 then
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
            CLN.VoiceoverPlayer:PlayQuestSound(nextQuest.questId, nextQuest.phase, nextQuest.npcId, nextQuest.displayID)
        end
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
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true, true)
    end
end

function EventHandler:GOSSIP_CLOSED()
    if CLN and CLN.Logger then CLN.Logger:debug("GOSSIP_CLOSED", false, CLN.Utils.LogCategories.loader) end
    CLN.PlayButton:ClearButtons()

    local mode = CLN.db.profile.questPlaybackMode or "queue"
    if (mode == "stopOnClose" and CLN.VoiceoverPlayer.currentlyPlaying) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on gossip closed.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true, true)
    end
end

function EventHandler:CINEMATIC_START()
    if CLN and CLN.Logger then CLN.Logger:debug("CINEMATIC_START", false, CLN.Utils.LogCategories.loader) end
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on cinematic start.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true, true)
    end
end

function EventHandler:PLAY_MOVIE()
    if CLN and CLN.Logger then CLN.Logger:debug("PLAY_MOVIE", false, CLN.Utils.LogCategories.loader) end
    if (CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()) then
        if CLN and CLN.Logger then CLN.Logger:debug("Stopping currently playing voiceover on movie play.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:ForceStopCurrentSound(true, true)
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

-- ============================================================================
-- Native NPC Voiceover Detection (Experimental)
-- ============================================================================

-- Estimate how long a spoken line of text takes at ~80 words per minute.
---@param text string
---@return number seconds
local function EstimateVODuration(text)
    if not text or #text == 0 then return 3 end
    -- ~65 WPM ≈ 11.2 chars/sec for English (slower NPCs).  Add 1.5 s buffer.
    return math.max(2, #text / 11.2 + 1.5)
end

--- Fires for CHAT_MSG_MONSTER_SAY / YELL / WHISPER / EMOTE.
--- Pauses addon voiceover when a whitelisted NPC speaks (or all NPCs in "all" mode).
--- Note: EventSystem dispatches (event, ...) so the first arg here is the event name.
function EventHandler:OnNpcChatMessage(event, text, npcName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    -- Extract NPC ID from GUID when available (format: "Creature-0-...-NPCID-...")
    local npcId = nil
    -- Try the event guid first, then fall back to nearby unit GUIDs
    local resolvedGuid = guid
    if (not resolvedGuid or resolvedGuid == "") and UnitGUID then
        -- Try "npc" unit (quest dialog NPC) or "target" as fallbacks
        local npcGuid = UnitGUID("npc")
        local targetGuid = UnitGUID("target")
        -- Match by name to avoid attributing to the wrong unit
        if npcGuid and UnitName and UnitName("npc") == npcName then
            resolvedGuid = npcGuid
        elseif targetGuid and UnitName and UnitName("target") == npcName then
            resolvedGuid = targetGuid
        end
    end
    if resolvedGuid and type(resolvedGuid) == "string" then
        local idStr = select(6, strsplit("-", resolvedGuid))
        npcId = tonumber(idStr)
    end

    -- Always log NPC messages when debug mode is on (regardless of mode)
    if CLN.db.profile.debugMode and CLN.Logger then
        CLN.Logger:debug(
            "NPC_MSG event=" .. tostring(event)
            .. " npc=" .. tostring(npcName)
            .. " npcId=" .. tostring(npcId)
            .. " text=" .. tostring(text and text:sub(1, 60) or "nil")
            .. " isSubtitle=" .. tostring(isSubtitle)
            .. " hideSender=" .. tostring(hideSenderInLetterbox)
            .. " lineID=" .. tostring(lineID)
            .. " guid=" .. tostring(guid),
            false, CLN.Utils.LogCategories.loader)
    end

    -- Always collect recent NPC speeches (for whitelist popup), skip emotes
    if event ~= "CHAT_MSG_MONSTER_EMOTE" then
        self:RecordNpcSpeech(npcId, npcName, text, event)
    end

    -- Extend pending whitelist popup timer if NPC is still talking
    if self._whitelistPopupTimer and text then
        self:ExtendWhitelistPopupTimer(text)
    end

    -- Only pause for whitelisted NPCs; "off" does nothing
    local mode = CLN.db.profile.nativeVOMode or "off"
    if mode == "off" then return end

    -- Skip emotes — they're ambient flavor text, almost never voiced
    if event == "CHAT_MSG_MONSTER_EMOTE" then return end

    -- Don't pause if nothing is playing (check both active and already-paused state)
    local cp = CLN.VoiceoverPlayer.currentlyPlaying
    local isActive = cp and cp.soundHandle and cp:isPlaying()
    local isPaused = cp and cp._pausedForNativeVO
    if not (isActive or isPaused) then return end

    -- Don't pause VO that's been playing a long time (likely almost finished)
    if isActive and cp.startTime and GetTime then
        local elapsed = GetTime() - cp.startTime
        local minPlayingThreshold = 15 -- seconds: skip pause if VO played this long
        if elapsed > minPlayingThreshold then
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Skipping pause — addon VO already played " .. string.format("%.0f", elapsed) .. "s (threshold " .. minPlayingThreshold .. "s)",
                    false, CLN.Utils.LogCategories.loader)
            end
            return
        end
    end

    -- Whitelist check: only pause for NPCs the user has explicitly confirmed
    local wl = CLN.db.profile.nativeVOWhitelist
    if not wl then return end
    local matched = (npcId and wl[npcId]) or (npcName and wl[npcName])
    if not matched then
        if CLN.db.profile.debugMode and CLN.Logger then
            CLN.Logger:debug("NPC not whitelisted, skipping pause: " .. tostring(npcName) .. " (id=" .. tostring(npcId) .. ")", false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    -- Auto-learn new creature IDs for already-whitelisted NPCs
    if npcId and not wl[npcId] and npcName and wl[npcName] then
        wl[npcId] = true
    end

    -- Already paused? Extend the timer instead of double-pausing
    if isPaused then
        local dur = EstimateVODuration(text)
        if CLN.VoiceoverPlayer._nativeVOResumeTimer then
            CLN.VoiceoverPlayer._nativeVOResumeTimer:Cancel()
        end
        CLN.VoiceoverPlayer._nativeVOResumeTimer = C_Timer.NewTimer(dur, function()
            CLN.VoiceoverPlayer:ResumeAfterNativeVO()
        end)
        if CLN and CLN.Logger then
            CLN.Logger:debug("Extended native VO pause for " .. tostring(npcName) .. " (+" .. string.format("%.1f", dur) .. "s)", false, CLN.Utils.LogCategories.loader)
        end
        return
    end

    local duration = EstimateVODuration(text)
    if CLN and CLN.Logger then
        CLN.Logger:debug("Native VO detected from " .. tostring(npcName) .. " (id=" .. tostring(npcId) .. ", " .. tostring(event) .. ") — pausing for ~" .. string.format("%.1f", duration) .. "s",
            false, CLN.Utils.LogCategories.loader)
    end
    CLN.VoiceoverPlayer:PauseForNativeVO(duration)
end

--- Fires for TALKINGHEAD_REQUESTED. Talking heads always have voiceover.
function EventHandler:OnTalkingHeadRequested()
    if CLN.db.profile.debugMode and CLN.Logger then
        CLN.Logger:debug("TALKINGHEAD_REQUESTED fired", false, CLN.Utils.LogCategories.loader)
    end
    local mode = CLN.db.profile.nativeVOMode or "off"
    if mode == "off" then return end
    local cp = CLN.VoiceoverPlayer.currentlyPlaying
    if not (cp and cp.soundHandle and cp:isPlaying()) then return end

    -- Talking heads typically last 5-15 seconds; use a conservative default
    local duration = 8
    if CLN and CLN.Logger then
        CLN.Logger:debug("Talking Head detected — pausing addon VO for ~" .. duration .. "s", false, CLN.Utils.LogCategories.loader)
    end
    CLN.VoiceoverPlayer:PauseForNativeVO(duration)
end

-- ============================================================================
-- Recent NPC Speech Buffer (for whitelist popup)
-- ============================================================================

local SPEECH_BUFFER_MAX = 20
local SPEECH_BUFFER_TTL = 30 -- seconds

--- Record an NPC speech event into the recent buffer.
function EventHandler:RecordNpcSpeech(npcId, npcName, text, event)
    if not self._recentNpcSpeeches then self._recentNpcSpeeches = {} end
    local now = GetTime and GetTime() or 0

    -- Prune old entries
    local buf = self._recentNpcSpeeches
    local cutoff = now - SPEECH_BUFFER_TTL
    for i = #buf, 1, -1 do
        if buf[i].timestamp < cutoff then table.remove(buf, i) end
    end

    -- Add new entry
    table.insert(buf, {
        npcId = npcId,
        npcName = npcName or "Unknown",
        text = text or "",
        event = event,
        timestamp = now,
    })

    -- Cap size
    while #buf > SPEECH_BUFFER_MAX do table.remove(buf, 1) end
end

--- Get unique NPCs from recent speeches that aren't already whitelisted or dismissed.
--- Groups by name and collects all seen IDs (same NPC can have multiple creature IDs).
---@return table[] Array of { npcName, npcIds={id1,id2,...}, text } for popup display
function EventHandler:GetUnaskedRecentNpcs()
    if not self._recentNpcSpeeches then return {} end
    local wl = CLN.db.profile.nativeVOWhitelist or {}
    local dismissed = CLN.db.profile.nativeVODismissed or {}
    local now = GetTime and GetTime() or 0
    local cutoff = now - SPEECH_BUFFER_TTL

    -- Group by npcName, collect all unique IDs and most recent text
    local byName = {}
    local order = {}
    for i = #self._recentNpcSpeeches, 1, -1 do
        local entry = self._recentNpcSpeeches[i]
        if entry.timestamp >= cutoff then
            local name = entry.npcName or "Unknown"
            if not byName[name] then
                byName[name] = { npcName = name, npcIds = {}, text = entry.text, _idSet = {} }
                table.insert(order, name)
            end
            if entry.npcId and not byName[name]._idSet[entry.npcId] then
                byName[name]._idSet[entry.npcId] = true
                table.insert(byName[name].npcIds, entry.npcId)
            end
        end
    end

    local result = {}
    for _, name in ipairs(order) do
        local info = byName[name]
        -- Skip if already whitelisted or dismissed (check name + any known ID)
        local isWhitelisted = wl[name]
        local isDismissed = dismissed[name]
        if not isWhitelisted and not isDismissed then
            for _, id in ipairs(info.npcIds) do
                if wl[id] then isWhitelisted = true; break end
                if dismissed[id] then isDismissed = true; break end
            end
        end
        if not isWhitelisted and not isDismissed then
            info._idSet = nil -- clean up temp
            table.insert(result, info)
        end
    end
    return result
end

-- ============================================================================
-- Whitelist Popup Scheduling
-- ============================================================================

--- Schedule the whitelist popup after NPC speech settles.
--- Called from VoiceoverPlayer:PausePlayback when user pauses.
function EventHandler:ScheduleWhitelistPopup()
    local mode = CLN.db.profile.nativeVOMode or "off"
    if mode ~= "whitelist" then return end

    local npcs = self:GetUnaskedRecentNpcs()
    if #npcs == 0 then return end

    -- Start with a 3s base delay; will be extended by incoming speech
    self._whitelistPopupDelay = 3
    self:ResetWhitelistPopupTimer()
end

--- Extend the popup timer when new NPC speech arrives during the wait.
function EventHandler:ExtendWhitelistPopupTimer(text)
    if not self._whitelistPopupTimer then return end
    local dur = EstimateVODuration(text)
    self._whitelistPopupDelay = dur + 2 -- speech duration + settle buffer
    self:ResetWhitelistPopupTimer()
end

--- Reset (restart) the popup timer with the current delay.
function EventHandler:ResetWhitelistPopupTimer()
    if self._whitelistPopupTimer then
        self._whitelistPopupTimer:Cancel()
    end
    local delay = self._whitelistPopupDelay or 3
    self._whitelistPopupTimer = C_Timer.NewTimer(delay, function()
        self._whitelistPopupTimer = nil
        self._whitelistPopupDelay = nil
        self:ShowWhitelistPopup()
    end)
end

--- Cancel any pending popup timer.
function EventHandler:CancelWhitelistPopupTimer()
    if self._whitelistPopupTimer then
        self._whitelistPopupTimer:Cancel()
        self._whitelistPopupTimer = nil
    end
    self._whitelistPopupDelay = nil
end

--- Show the whitelist popup with un-asked NPCs.
function EventHandler:ShowWhitelistPopup()
    local npcs = self:GetUnaskedRecentNpcs()
    if #npcs == 0 then return end

    if CLN.db.profile.debugMode and CLN.Logger then
        CLN.Logger:debug("Showing whitelist popup with " .. #npcs .. " NPC(s)", false, CLN.Utils.LogCategories.loader)
    end

    if CLN.ReplayFrame and CLN.ReplayFrame.ShowNativeVOWhitelistPopup then
        CLN.ReplayFrame:ShowNativeVOWhitelistPopup(npcs)
    end
end
