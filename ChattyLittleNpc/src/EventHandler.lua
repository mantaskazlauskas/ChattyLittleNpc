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
    if self._historyPruneTimer then
        timer:CancelTimer(self._historyPruneTimer)
        self._historyPruneTimer = nil
    end
end

-- Suspend watcher and history-prune timers (called during pause)
function EventHandler:SuspendTimers()
    if self.watcherTimer then
        timer:CancelTimer(self.watcherTimer)
        self.watcherTimer = nil
    end
    if self._historyPruneTimer then
        timer:CancelTimer(self._historyPruneTimer)
        self._historyPruneTimer = nil
    end
end

-- Resume watcher and history-prune timers (called on unpause)
function EventHandler:ResumeTimers()
    if not self.watcherTimer then
        self:StartWatcher()
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
        if CLN.VoiceoverPlayer:GetPlaybackState(cp) == CLN.VoiceoverPlayer.State.PAUSED_NATIVE then return end

        local handle = cp.soundHandle
        -- Raw check: does C_Sound actually confirm this handle is playing right now?
        local rawPlaying = handle and cp.isPlaying and cp:isPlaying() or false

        -- Stamp last-confirmed-playing time ONLY when C_Sound truly confirms it;
        -- this breaks the feedback loop (IsEffectivelyPlaying reads the stamp,
        -- so stamping based on IsEffectivelyPlaying would self-reinforce forever)
        if rawPlaying then
            cp._lastConfirmedPlayingAt = GetTime()
        end

        -- Use IsEffectivelyPlaying (with grace period) to avoid false stop detection
        -- during dialog transitions where C_Sound.IsPlaying briefly returns false
        local isPlaying = CLN.VoiceoverPlayer.IsEffectivelyPlaying
            and CLN.VoiceoverPlayer:IsEffectivelyPlaying()
            or rawPlaying

        -- If a new handle starts playing, clear the latch
        if handle and isPlaying and self._stopLatchHandle and self._stopLatchHandle ~= handle then
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("Watcher: clearing stop latch for new handle " .. tostring(handle), false, CLN.Utils.LogCategories.loader)
            end
            self._stopLatchHandle = nil
        end

        -- Only emit stop once per handle, and only when we have a valid handle
        if handle and not isPlaying then
            if self._stopLatchHandle ~= handle then
                if CLN.db.profile.debugMode and CLN.Logger then
                    CLN.Logger:debug("Watcher: VOICEOVER_STOP for handle " .. tostring(handle), false, CLN.Utils.LogCategories.loader)
                end
                self._stopLatchHandle = handle
                CLN:SendMessage("VOICEOVER_STOP", cp)
            end
            return
        end
    end)

    -- Periodic history cleanup (every 60s) so stale entries are pruned
    -- even when no new sounds play.
    self._historyPruneTimer = timer:ScheduleRepeatingTimer(60, function()
        if CLN.ReplayFrame and CLN.ReplayFrame.PruneOldHistory then
            local before = CLN.ReplayFrame._replayHistory and #CLN.ReplayFrame._replayHistory or 0
            CLN.ReplayFrame:PruneOldHistory()
            local after = CLN.ReplayFrame._replayHistory and #CLN.ReplayFrame._replayHistory or 0
            if after < before and CLN.ReplayFrame.MarkQueueDirty then
                CLN.ReplayFrame:MarkQueueDirty()
            end
        end
    end)
end

-- EVENT HANDLERS
function EventHandler:ADDON_LOADED()
    if CLN and CLN.Logger then CLN.Logger:debug("ADDON_LOADED", false, CLN.Utils.LogCategories.loader) end

    CLN.NpcDialogTracker:InitializeTables()

    -- Initialize and prune the persistent NPC metadata cache
    if CLN.NpcMetadataCache then
        CLN.NpcMetadataCache:Initialize()
        CLN.NpcMetadataCache:Prune(30)
    end
end

function EventHandler:GOSSIP_SHOW()
    if CLN and CLN.Logger then CLN.Logger:debug("GOSSIP_SHOW", false, CLN.Utils.LogCategories.loader) end

    local parentFrame = _G["DUIQuestFrame"] or GossipFrame
    local _, gender, _, _, unitType, unitId, creatureType = CLN:GetUnitInfo("npc")
    local text = C_GossipInfo.GetText()
    if (not unitId or not unitType or not text) then
        if CLN and CLN.Logger then CLN.Logger:debug("No unitId, unitType or text found for gossip.", false, CLN.Utils.LogCategories.loader) end
        return
    end

    if (CLN.db.profile.logNpcTexts) then
        CLN.NpcDialogTracker:HandleGossipText()
    end

    -- Capture NPC metadata for the persistent cache (even without voiceover)
    if CLN.NpcMetadataCache then
        CLN.NpcMetadataCache:CaptureFromUnit()
    end
    local hashes = CLN.Utils:GetHashes(unitId, text)
    local filePath = CLN.Utils:GetPathToNonQuestFile(unitId, "Gossip", hashes, gender)
    if not filePath or CLN.Utils:IsNilOrEmpty(filePath) then
        if CLN and CLN.Logger then CLN.Logger:debug("No file path found for gossip voiceover.", false, CLN.Utils.LogCategories.loader) end
        return
    end

    local displayID = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil

    local soundType = (unitType == "GameObject") and "GameObject" or "Gossip"

    CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.GossipButton ,function()
        CLN.VoiceoverPlayer:PlayNonQuestSound(unitId, soundType, text, gender, displayID, creatureType)
    end)

    if (CLN.db.profile.autoPlayVoiceovers) then
        local gossipMode = CLN.db.profile.gossipPlaybackMode or "queue"
        if gossipMode == "manual" then
            if CLN and CLN.Logger then CLN.Logger:debug("Gossip auto-play skipped (manual mode).", false, CLN.Utils.LogCategories.loader) end
        else
            CLN:HandleGossipPlaybackStart(unitId, text, soundType, gender, creatureType)
        end
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

    -- Capture NPC metadata for the persistent cache
    if CLN.NpcMetadataCache then CLN.NpcMetadataCache:CaptureFromUnit() end

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            local did = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
            local _, gen, _, _, _, nid, ct = CLN:GetUnitInfo("npc")
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.DESC, nid, did, gen, ct)
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

    -- Capture NPC metadata for the persistent cache
    if CLN.NpcMetadataCache then CLN.NpcMetadataCache:CaptureFromUnit() end

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            local did = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
            local _, gen, _, _, _, nid, ct = CLN:GetUnitInfo("npc")
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.PROG, nid, did, gen, ct)
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

    -- Capture NPC metadata for the persistent cache
    if CLN.NpcMetadataCache then CLN.NpcMetadataCache:CaptureFromUnit() end

    if (_G["QuestFrame"]) then
        local parentFrame = _G["DUIQuestFrame"] or _G["QuestFrame"]
        CLN.PlayButton:CreatePlayVoiceoverButton(parentFrame, CLN.PlayButton.QuestButton, function()
            local did = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
            local _, gen, _, _, _, nid, ct = CLN:GetUnitInfo("npc")
            CLN.VoiceoverPlayer:PlayQuestSound(GetQuestID(), CLN.Utils.QuestPhases.COMP, nid, did, gen, ct)
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

    local displayID = (UnitCreatureDisplayID and UnitExists and UnitExists("npc")) and UnitCreatureDisplayID("npc") or nil
    if (_G["ItemTextFrame"]) then
        CLN.PlayButton:CreatePlayVoiceoverButton(_G["ItemTextFrame"], CLN.PlayButton.ItemTextButton, function()
            CLN.VoiceoverPlayer:PlayNonQuestSound(itemId, unitType, itemText, nil, displayID)
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

    if type(itemId) == "number" then
        CLN:HandleGossipPlaybackStart(itemId, itemText, unitType)
    end
end

function EventHandler:OnVoiceoverStop(event, stoppedVoiceover)
    -- Deduplicate rapid repeated stops for the same handle
    local stoppedHandle = stoppedVoiceover and stoppedVoiceover.soundHandle
    local now = (type(GetTime) == "function") and GetTime() or 0
    if stoppedHandle then
        if self._lastStoppedHandle == stoppedHandle and self._lastStoppedTime and (now - self._lastStoppedTime) < 1.0 then
            if CLN.db.profile.debugMode and CLN.Logger then
                CLN.Logger:debug("OnVoiceoverStop: deduped for handle " .. tostring(stoppedHandle), false, CLN.Utils.LogCategories.loader)
            end
            return
        end
        self._lastStoppedHandle = stoppedHandle
        self._lastStoppedTime = now
    end

    -- Push to replay history (centralized helper handles title resolution)
    if stoppedVoiceover then
        CLN.VoiceoverPlayer:SetPlaybackState(stoppedVoiceover, CLN.VoiceoverPlayer.State.COMPLETED)
        CLN.VoiceoverPlayer:PushToHistory(stoppedVoiceover)
    end

    -- Record gossip cooldown only when the sound finishes naturally.
    -- Interrupted gossip (paused, skipped, force-stopped) never reaches here
    -- because those paths clear currentlyPlaying before the watcher fires.
    if stoppedVoiceover and stoppedVoiceover.entryType == "Gossip"
        and stoppedVoiceover.npcId and stoppedVoiceover.title then
        local hashes = CLN.Utils:GetHashes(stoppedVoiceover.npcId, stoppedVoiceover.title)
        CLN.VoiceoverPlayer:RecordGossipCooldown(hashes)
    end

    -- Try to remove the stopped voiceover from the queue (it may already have
    -- been removed at play-start by PlayQuestSound, which is the normal case).
    if stoppedVoiceover and stoppedVoiceover.questId then
        CLN.VoiceoverPlayer:RemoveQueuedQuestEntry(stoppedVoiceover.questId, stoppedVoiceover.phase)
    end

    -- Advance the queue via the player's single canonical path.
    -- The player handles: paused freeze, dedupe, pop-and-play, suspended
    -- fallback, and idle/UI cleanup.
    if CLN.VoiceoverPlayer:IsPaused() then
        -- Queue is frozen while paused; don't advance but still refresh UI
        -- so the stopped sound updates its visual state
        if CLN and CLN.Logger then CLN.Logger:debug("Queue paused, skipping advancement.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer:NotifyQueueDirty()
    elseif #CLN.questsQueue > 0 then
        if CLN and CLN.Logger then CLN.Logger:debug("Playing next quest in queue.", false, CLN.Utils.LogCategories.loader) end
        CLN.VoiceoverPlayer.queueProcessed = false
        -- Clear currentlyPlaying so AdvanceQueue → PlayQuestSound doesn't see
        -- the finished record as "effectively playing" and queue instead of play.
        CLN.VoiceoverPlayer.currentlyPlaying = CLN.VoiceoverPlayer:GetCurrentlyPlayingObject()
        CLN.VoiceoverPlayer:AdvanceQueue()
    else
        -- Nothing left in the queue
        if CLN.VoiceoverPlayer:HasSuspendedPlayback() then
            if CLN and CLN.Logger then CLN.Logger:debug("Queue empty, resuming suspended playback.", false, CLN.Utils.LogCategories.loader) end
            CLN.VoiceoverPlayer:ResumeSuspendedPlayback()
        else
            -- No suspended playback; clear current if it matches the stopped handle
            local curr = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
            local currHandle = curr and curr.soundHandle or nil
            local stillPlaying = curr and curr.isPlaying and curr:isPlaying() or false
            if not stillPlaying or (stoppedHandle and currHandle == stoppedHandle) then
                if CLN and CLN.Logger then CLN.Logger:debug("No more quests in queue, clearing currentlyPlaying and closing UI.", false, CLN.Utils.LogCategories.loader) end
                CLN.VoiceoverPlayer.currentlyPlaying = CLN.VoiceoverPlayer:GetCurrentlyPlayingObject()
                CLN.VoiceoverPlayer.queueProcessed = true
            end
            -- Conversation stopped; refresh UI and let FSM drive farewell/hide
            CLN.VoiceoverPlayer:NotifyDisplayDirty()
            if CLN.ReplayFrame and CLN.ReplayFrame.OnConversationStop then
                CLN.ReplayFrame:OnConversationStop()
            end
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
    -- In queue mode, refresh UI so frame/model recover after dialog close
    CLN.VoiceoverPlayer:NotifyDisplayDirty()
end

function EventHandler:GOSSIP_CLOSED()
    if CLN and CLN.Logger then CLN.Logger:debug("GOSSIP_CLOSED", false, CLN.Utils.LogCategories.loader) end
    CLN.PlayButton:ClearButtons()

    local mode = CLN.db.profile.gossipPlaybackMode or "queue"
    if mode == "stopOnClose" or mode == "manual" then
        -- Only stop gossip/non-quest VO; leave quest playback untouched.
        -- Don't clear the queue — quest items should survive gossip close.
        local cp = CLN.VoiceoverPlayer.currentlyPlaying
        if cp and cp.entryType ~= "quest" then
            if CLN and CLN.Logger then CLN.Logger:debug("Stopping gossip voiceover on gossip closed.", false, CLN.Utils.LogCategories.loader) end
            CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true)
        end
    end
    -- In queue mode, refresh UI so frame/model recover after dialog close
    CLN.VoiceoverPlayer:NotifyDisplayDirty()
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

-- Extra settle buffer (seconds) added to native VO resume timers to handle
-- gaps between multi-line NPC conversations.
local NATIVE_VO_SETTLE_SEC = 8

-- Estimate how long a spoken line of text takes (~75 WPM / 12.9 chars/sec).
---@param text string
---@return number seconds
local function EstimateVODuration(text)
    return CLN.Utils.EstimateVODuration(text)
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

    -- Always collect recent NPC speeches (for whitelist popup), skip emotes.
    -- Subtitle messages (isSubtitle=true) represent WoW's native voice acting and are
    -- especially relevant for the whitelist popup since they confirm the NPC is voiced.
    if event ~= "CHAT_MSG_MONSTER_EMOTE" then
        self:RecordNpcSpeech(npcId, npcName, text, event)
    end

    -- Extend pending whitelist popup timer if NPC is still talking
    if self._whitelistPopupTimer and text then
        self:ExtendWhitelistPopupTimer(text)
    end

    local mode = CLN.db.profile.nativeVOMode or "off"
    if mode == "off" then return end

    -- Subtitle messages (isSubtitle=true) indicate cinematic/narrative text and often
    -- accompany native voice acting, but they must still respect the whitelist so only
    -- user-confirmed NPCs can interrupt addon voiceover.
    -- They now fall through to the same whitelist-checked path as regular NPC chat.

    -- Skip emotes — they're ambient flavor text, almost never voiced
    if event == "CHAT_MSG_MONSTER_EMOTE" then return end

    -- Don't pause if nothing is playing (check both active and already-paused state)
    local cp = CLN.VoiceoverPlayer.currentlyPlaying
    local isActive = cp and cp.soundHandle and cp:isPlaying()
    local isPaused = CLN.VoiceoverPlayer:IsNativeVOPauseActive()
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
        -- Also contribute the new ID for community collection
        if CLN.ContributeVoicedNpc then
            CLN:ContributeVoicedNpc(npcName, { npcId })
        end
    end

    -- Already paused? Extend the timer instead of double-pausing
    if isPaused then
        local dur = EstimateVODuration(text) + NATIVE_VO_SETTLE_SEC
        CLN.VoiceoverPlayer:ExtendNativeVOPause(dur)
        if CLN.db.profile.debugMode and CLN.Logger then
            CLN.Logger:debug("Extended native VO pause for " .. tostring(npcName) .. " (+" .. string.format("%.1f", dur) .. "s)", false, CLN.Utils.LogCategories.loader)
        end
        -- Surface any new (unknown) NPCs detected during extended pause
        self:ScheduleWhitelistPopup()
        return
    end

    local duration = EstimateVODuration(text) + NATIVE_VO_SETTLE_SEC
    if CLN.db.profile.debugMode and CLN.Logger then
        CLN.Logger:debug("Native VO detected from " .. tostring(npcName) .. " (id=" .. tostring(npcId) .. ", " .. tostring(event) .. ") — pausing for ~" .. string.format("%.1f", duration) .. "s",
            false, CLN.Utils.LogCategories.loader)
    end
    CLN.VoiceoverPlayer:PauseForNativeVO(duration)

    -- Surface any new (unknown) NPCs speaking alongside the whitelisted NPC
    self:ScheduleWhitelistPopup()
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
    if CLN.db.profile.debugMode and CLN.Logger then
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

    -- Base the initial delay on the most recent speech so the popup doesn't
    -- fire in the middle of a multi-line NPC conversation.  NPC lines are
    -- typically 3-8 s apart, so we need more than the old flat 3 s.
    local buf = self._recentNpcSpeeches
    local lastEntry = buf and buf[#buf]
    local initialDelay
    if lastEntry and lastEntry.text and #lastEntry.text > 0 then
        initialDelay = EstimateVODuration(lastEntry.text) + 5
    else
        initialDelay = 8
    end

    self._whitelistPopupDelay = initialDelay
    self:ResetWhitelistPopupTimer()
end

--- Extend the popup timer when new NPC speech arrives during the wait.
function EventHandler:ExtendWhitelistPopupTimer(text)
    if not self._whitelistPopupTimer then return end
    local dur = EstimateVODuration(text)
    self._whitelistPopupDelay = dur + 5 -- speech duration + settle buffer for multi-line conversations
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
