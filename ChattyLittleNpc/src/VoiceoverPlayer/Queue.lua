-- VoiceoverPlayer/Queue.lua - The quest queue, its display list and playback history.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local VoiceoverPlayer = CLN.VoiceoverPlayer
local send = VoiceoverPlayer._send

-- ============================================================================
-- Queue Integrity Helpers
-- ============================================================================
--- Check if currentlyPlaying matches the quest/phase and is actively held.
---@param questId number
---@param phase string
---@return boolean
function VoiceoverPlayer:IsCurrentQuestPhaseActive(questId, phase)
    if not (questId and phase) then return false end
    local cp = VoiceoverPlayer.currentlyPlaying
    if not cp or cp.questId ~= questId or cp.phase ~= phase then
        return false
    end

    return self:IsPlaybackActive(cp)
end

--- Check if a quest/phase combo is already queued.
---@param questId number
---@param phase string
---@return boolean isQueued, number index
function VoiceoverPlayer:IsQuestPhaseQueued(questId, phase)
    if not (questId and phase) then return false end
    -- Check currently playing item too (not just the queue)
    if self:IsCurrentQuestPhaseActive(questId, phase) then
        return true, 0
    end
    for i, q in ipairs(CLN.questsQueue) do
        if q.questId == questId and q.phase == phase then
            return true, i
        end
    end
    return false
end

--- Build a stable identity key for a queue/current-playback entry.
---@param entry table|nil
---@return string|nil
function VoiceoverPlayer:GetQueueEntryKey(entry)
    if not entry then return nil end
    if entry.questId and entry.phase then
        return "quest|" .. tostring(entry.questId) .. "|" .. tostring(entry.phase)
    end
    if entry.npcId and entry.entryType and entry.title then
        return "nonquest|"
            .. tostring(entry.entryType) .. "|"
            .. tostring(entry.npcId) .. "|"
            .. tostring(entry.gender or "") .. "|"
            .. tostring(entry.title)
    end
    return nil
end

--- Deduplicate the queue, removing entries that match currently playing or are duplicated.
function VoiceoverPlayer:DeduplicateQueue()
    if not CLN.questsQueue then return end
    local seen = {}
    local cp = VoiceoverPlayer.currentlyPlaying
    local removedAny = false
    local currentKey = self:GetQueueEntryKey(cp)
    if currentKey then
        seen[currentKey] = true
    end
    for i = #CLN.questsQueue, 1, -1 do
        local q = CLN.questsQueue[i]
        local key = self:GetQueueEntryKey(q)
        if key and seen[key] then
            table.remove(CLN.questsQueue, i)
            removedAny = true
        elseif key then
            seen[key] = true
        end
    end
    if removedAny then
        self:NotifyQueueDirty()
    end
end

--- Remove a queued quest entry by identity.
---@param questId number|nil
---@param phase string|nil
---@return boolean removed
function VoiceoverPlayer:RemoveQueuedQuestEntry(questId, phase)
    if not (questId and phase and CLN.questsQueue) then return false end
    for i, q in ipairs(CLN.questsQueue) do
        if q.questId == questId and q.phase == phase then
            table.remove(CLN.questsQueue, i)
            return true
        end
    end
    return false
end

function VoiceoverPlayer:GetDisplayEntries()
    local entries = {}
    local cp = self.currentlyPlaying
    local currentState = self:GetPlaybackState(cp)
    local currentKey = nil

    if cp and not cp._historyPushed and (cp.title or cp.questId) and self:IsPlaybackStateActive(currentState) then
        currentKey = self:GetQueueEntryKey(cp)
        table.insert(entries, {
            kind = "current",
            state = currentState,
            isPlaying = true,
            questId = cp.questId,
            phase = cp.phase,
            npcId = cp.npcId,
            title = cp.title,
            gender = cp.gender,
            displayID = cp.displayID,
            entryType = cp.entryType or (cp.questId and "quest" or "unknown"),
        })
    end

    if CLN.questsQueue then
        for i, q in ipairs(CLN.questsQueue) do
            local queueKey = self:GetQueueEntryKey(q)
            if not (currentKey and queueKey and currentKey == queueKey) then
                local state = self:GetPlaybackState(q)
                if state == self.State.IDLE then
                    state = self.State.QUEUED
                end
                local duration, hasPackDuration = self:GetQueuedEntryDuration(q)
                table.insert(entries, {
                    duration = duration,
                    hasPackDuration = hasPackDuration,
                    kind = "queue",
                    state = state,
                    queueIndex = i,
                    questId = q.questId,
                    phase = q.phase,
                    npcId = q.npcId,
                    title = q.title,
                    gender = q.gender,
                    displayID = q.displayID,
                    entryType = q.entryType or ((q.questId and q.phase) and "quest" or "unknown"),
                })
            end
        end
    end

    return entries
end

-- ============================================================================
-- Centralized History Push
-- ============================================================================
--- Push a record to replay history. Accepts a currentlyPlaying object, a queue
--- entry, a suspended-playback table, or any table with at least a title or
--- questId.  Normalizes the fields so callers don't need to worry about shape.
---@param record table Any voiceover record (currentlyPlaying, queue item, etc.)
function VoiceoverPlayer:PushToHistory(record)
    if not record then return end
    if record._historyPushed then return end
    -- Resolve title: prefer explicit, fall back to questId lookup
    local title = record.title
    if not title and record.questId then
        title = CLN.GetTitleForQuestID and CLN:GetTitleForQuestID(record.questId) or nil
    end
    -- Must have *something* identifiable
    if not title and not record.questId then return end

    record._historyPushed = true
    local historyEntry = {
        title = title,
        npcId = record.npcId,
        questId = record.questId,
        phase = record.phase,
        entryType = record.entryType or (record.questId and "quest" or "unknown"),
        state = record.state or self:GetPlaybackState(record),
        gender = record.gender,
        displayID = record.displayID,
        libraryEntry = record._libraryEntry,
        completedAt = GetTime and GetTime() or 0,
    }
    -- Enrich with cached metadata so replays have full model info
    CLN.NpcMetadataCache:Enrich(historyEntry)
    send("HISTORY_ADDED", historyEntry)
end

-- Grace period: consider a sound "still playing" if it started recently,
-- even when C_Sound.IsPlaying briefly returns false during frame transitions.
-- ============================================================================
-- Centralized Queue Advancement (Phase 1)
-- ============================================================================
--- Single canonical path for popping the next queued item and playing it.
--- Falls back to suspended playback, then to idle + UI refresh.
--- All callers that need "play the next thing" should call this.
function VoiceoverPlayer:AdvanceQueue()
    self:DeduplicateQueue()

    -- Iterative skip of unknown entries (avoids deep recursion on malformed queues)
    while #CLN.questsQueue > 0 do
        local nextItem = CLN.questsQueue[1]
        if nextItem.questId and nextItem.phase then
            -- Clean animation state before starting next item
            send("ANIMATION_RESET")
            -- PlayQuestSound handles its own queue removal on success
            self:PlayQuestSound(nextItem.questId, nextItem.phase, nextItem.npcId, nextItem.displayID, nextItem.gender, nextItem.creatureType)
            return
        elseif nextItem.npcId and nextItem.title and nextItem.entryType then
            send("ANIMATION_RESET")
            table.remove(CLN.questsQueue, 1)
            self:NotifyQueueDirty()
            self:PlayNonQuestSound(nextItem.npcId, nextItem.entryType, nextItem.title, nextItem.gender, nextItem.displayID, nextItem.creatureType)
            return
        else
            -- Unknown entry; discard and try next
            CLN.Logger:debug("AdvanceQueue: discarding unknown entry", false, CLN.Utils.LogCategories.loader)
            table.remove(CLN.questsQueue, 1)
            self:NotifyQueueDirty()
        end
    end

    -- Queue is empty
    if self:HasSuspendedPlayback() then
        self:ResumeSuspendedPlayback()
    else
        self:NotifyDisplayDirty()
    end
end

--- Drop queued items by index range, pushing each to history as DROPPED.
--- Indices are 1-based and inclusive. Removes in reverse to avoid shifting.
---@param startIdx number First queue index to drop (inclusive)
---@param endIdx number Last queue index to drop (inclusive)
function VoiceoverPlayer:DropQueuedRange(startIdx, endIdx)
    if not CLN.questsQueue then return end
    local lo = math.max(startIdx or 1, 1)
    local hi = math.min(endIdx or #CLN.questsQueue, #CLN.questsQueue)
    for i = hi, lo, -1 do
        local item = CLN.questsQueue[i]
        if item then
            self:SetPlaybackState(item, self.State.DROPPED)
            self:PushToHistory(item)
        end
        table.remove(CLN.questsQueue, i)
    end
    self:NotifyQueueDirty()
end

--- Play a specific queued item right now: drop everything before it and stop
--- whatever is playing. This is what clicking a queued line does.
---@param queueIndex number 1-based index of the item to play
function VoiceoverPlayer:PlayQueuedItemAtIndex(queueIndex)
    if not CLN.questsQueue or queueIndex < 1 or queueIndex > #CLN.questsQueue then return end

    -- Drop everything before the target
    if queueIndex > 1 then
        self:DropQueuedRange(1, queueIndex - 1)
    end

    -- The target is now at index 1. Take it out of the queue first, or
    -- PlayQuestSound would treat it as a duplicate of itself.
    local item = table.remove(CLN.questsQueue, 1)
    self:NotifyQueueDirty()
    if not item then return end

    local isQuest = item.questId and item.phase
    local isNonQuest = item.npcId and item.title and item.entryType
    if not (isQuest or isNonQuest) then return end

    -- Clear the current line so the queueing and interruption rules don't
    -- apply: the user asked for this one specifically.
    local stoppedTitle = self.currentlyPlaying and self.currentlyPlaying.title
    self:CancelNativeVOResume()
    self:_ResumeTimersIfUserPaused()
    self:StopCurrentSound()
    self._lastForceStopTime = nil

    if isQuest then
        self:PlayQuestSound(item.questId, item.phase, item.npcId, item.displayID, item.gender, item.creatureType)
    else
        self:PlayNonQuestSound(item.npcId, item.entryType, item.title, item.gender, item.displayID, item.creatureType, { skipCooldown = true })
    end

    -- No file for this line: carry on rather than leaving playback stopped.
    -- The watcher can't advance a queue with nothing playing, so keep trying
    -- for as long as each attempt removes an entry.
    local function started()
        return self.currentlyPlaying and self.currentlyPlaying.soundHandle
    end
    if started() then return end
    repeat
        local before = #CLN.questsQueue
        self:AdvanceQueue()
    until started() or before == 0 or #CLN.questsQueue >= before

    -- Nothing left to play, and the watcher won't report it with no sound handle
    if not started() then
        send("CONVERSATION_ENDED", stoppedTitle)
    end
end
