---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Finite State Machine for reliable animation control
-- States: idle -> wave? -> talk -> idle

-- Exported state constants (use these across modules to avoid string typos)
ReplayFrame.State = ReplayFrame.State or {
    IDLE = "idle",
    WAVE = "wave",
    TALK = "talk",
    BOW  = "bow",
    POINT = "point",
}
local S = ReplayFrame.State

-- Small helper: now()
local function now()
    return (GetTime and GetTime()) or 0
end

-- Public: initialize FSM (idempotent)
function ReplayFrame:InitStateMachine()
    if self._fsm then return end

    self._fsm = {
        state = S.IDLE,
        enteredAt = now(),
        lastHandle = nil,
        lastPlaying = false,
        lastMsg = nil,
        -- transient timers
        hideAt = nil,
    }

    -- Local shorthand for Director helper funcs if available
    self._fsmLooksLikeGreeting = function(msg)
        return self.Director and self.Director.LooksLikeGreeting and self.Director:LooksLikeGreeting(msg) or false
    end
    self._fsmCanWave = function()
        return self.Director and self.Director.CanWave and self.Director:CanWave() or true
    end
    self._fsmHasInteractedRecently = function()
        return self.Director and self.Director.HasInteractedRecently and self.Director:HasInteractedRecently() or false
    end
    self._fsmMarkInteracted = function()
        if self.Director and self.Director.MarkInteracted then self.Director:MarkInteracted() end
    end
    -- Farewell support removed

    -- State actions
    -- Define with self as first parameter because callers use colon syntax (self:_fsm_enter(...))
    self._fsm_enter = function(self, newState)
        local fsm = self._fsm
        if fsm.state == newState then 
            return 
        end
        -- onExit current
        if fsm.state == S.TALK then
            if self.StopEmoteLoop then self:StopEmoteLoop() end
        end
        if fsm.state == S.WAVE or fsm.state == S.BOW or fsm.state == S.POINT then
            if self.CancelEmote then self:CancelEmote() end
        end

        -- transition
        fsm.state = newState
        fsm.enteredAt = now()

        -- onEnter new
        if newState == S.IDLE then
            if self.CancelEmote then self:CancelEmote() end
            if self.StopEmoteLoop then self:StopEmoteLoop() end
            if self.AnimStop then self:AnimStop("zoom"); self:AnimStop("pan") end
            if self.PlayIdleEmote then self:PlayIdleEmote({ duration = 0 }) end
            if self.SetIdleLoop then self:SetIdleLoop() end
            fsm.hideAt = nil
            self:_processPendingContext()
        elseif newState == S.WAVE then
            if self.StopEmoteLoop then self:StopEmoteLoop() end
            if self.AnimStop then self:AnimStop("zoom"); self:AnimStop("pan") end
            local ok = false
            if self.PlayEmote then
                self:OnceEmote("EMOTE_STARTED", function(payload)
                    if not payload or payload.name ~= "hello" then return end
                    if self.Director and self.Director.MarkWaved then
                        self.Director:MarkWaved()
                    end
                end)
                self:OnceEmote("EMOTE_COMPLETE", function(payload)
                    if not payload or payload.name ~= "hello" then return end
                    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                    if cur and cur.isPlaying and cur:isPlaying() and self._fsm and self._fsm.lastHandle == cur.soundHandle then
                        self:_fsm_enter(S.TALK)
                    else
                        self:_fsm_enter(S.IDLE)
                    end
                    self:_processPendingContext()
                end)
                ok = self:PlayEmote("hello", { duration = 1.5, waveZoom = 0.3, waveOutDur = 0.2, zoomBackDur = 0.5 })
            end
            if not ok then
                self:_fsm_enter(S.TALK)
            end
        elseif newState == S.BOW then
            if self.StopEmoteLoop then self:StopEmoteLoop() end
            if self.AnimStop then self:AnimStop("zoom"); self:AnimStop("pan") end
            local ok = false
            if self.PlayEmote then
                self:OnceEmote("EMOTE_COMPLETE", function(payload)
                    if not payload or payload.name ~= "bow" then return end
                    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                    if cur and cur.isPlaying and cur:isPlaying() and self._fsm and self._fsm.lastHandle == cur.soundHandle then
                        self:_fsm_enter(S.TALK)
                    else
                        self:_fsm_enter(S.IDLE)
                    end
                    self:_processPendingContext()
                end)
                ok = self:PlayEmote("bow", { duration = 1.8 })
            end
            if not ok then
                self:_fsm_enter(S.TALK)
            end
        elseif newState == S.POINT then
            -- Brief emphasis gesture, auto-returns to TALK
            if self.StopEmoteLoop then self:StopEmoteLoop() end
            if self.AnimStop then self:AnimStop("zoom"); self:AnimStop("pan") end
            local ok = false
            if self.PlayEmote then
                self:OnceEmote("EMOTE_COMPLETE", function(payload)
                    if not payload or payload.name ~= "point" then return end
                    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                    if cur and cur.isPlaying and cur:isPlaying() and self._fsm and self._fsm.lastHandle == cur.soundHandle then
                        self:_fsm_enter(S.TALK)
                    else
                        self:_fsm_enter(S.IDLE)
                    end
                end)
                ok = self:PlayEmote("point", { duration = 1.2 })
            end
            if not ok then
                self:_fsm_enter(S.TALK)
            end
        elseif newState == S.TALK then
            if self.StartEmoteLoop then self:StartEmoteLoop() end
        end
    end

    -- A tiny guard flag to indicate FSM drives animations now
    self._fsmActive = true
end

-- Public: feed playback start/stop to FSM
function ReplayFrame:FSM_OnPlaybackStart(cur)
    -- Skip frame manipulation during combat lockdown to avoid taint
    if InCombatLockdown and InCombatLockdown() then return end
    self:InitStateMachine()
    local fsm = self._fsm
    if not cur then 
        if self.Debug then self:Debug("FSM_OnPlaybackStart called with no current playback") end
        return 
    end
    
    -- Smart debouncing: check if this is a duplicate call for the same content
    local currentContext = {
        soundHandle = cur.soundHandle,
        title = cur.title,
        npcId = cur.npcId,
        startTime = cur.startTime
    }
    
    -- Check if we already processed this exact same content recently
    if fsm.lastProcessedContext then
        local isSameHandle = fsm.lastProcessedContext.soundHandle == currentContext.soundHandle
        local isSameTitle = fsm.lastProcessedContext.title == currentContext.title
        local isSameNpc = fsm.lastProcessedContext.npcId == currentContext.npcId
        local timeSinceLastProcess = now() - (fsm.lastProcessedTime or 0)
        
    if self.Debug then self:Debug("Debounce check - sameHandle:", isSameHandle, "sameTitle:", isSameTitle, "sameNpc:", isSameNpc, "timeSince:", timeSinceLastProcess) end
        
        -- If it's the exact same content within a short window, skip processing
        if isSameHandle and isSameTitle and isSameNpc and timeSinceLastProcess < 0.5 then
            if self.Debug then self:Debug("Skipping duplicate FSM_OnPlaybackStart call for same content") end
            return
        end
        
    -- If it's different content or enough time has passed, allow processing
    -- But if we're currently in WAVE state for different content, let it complete first
    if (fsm.state == S.WAVE or fsm.state == S.BOW) and not isSameHandle then
            if self.Debug then self:Debug("Current state:", fsm.state, "is busy with different content, deferring") end
            -- Store for later processing when current animation completes
            fsm.pendingContext = currentContext
            return
        end
    end
    
    -- Update our processing context
    fsm.lastProcessedContext = currentContext
    fsm.lastProcessedTime = now()
    fsm.pendingContext = nil
    
    if self.Debug then self:Debug("FSM_OnPlaybackStart processing - title:", cur.title or "nil", "handle:", cur.soundHandle) end
    
    -- If switching handle, clear one-shot watcher and any active emote to avoid overlap
    if fsm.lastHandle and fsm.lastHandle ~= cur.soundHandle then
        self._watchAnimActive = false
        self._watchAnimId = nil
        self._watchStartedAt = nil
        self._watchTimeout = nil
        if self.CancelEmote then self:CancelEmote() end
    end
    -- update handle & last message; clear tick-stop debounce so re-used handles work
    fsm._lastTickStopHandle = nil
    fsm.lastHandle = cur.soundHandle
    fsm.lastMsg = cur.title

    -- Decide wave vs talk
    local recentlyStarted = false
    local dt, wnd = nil, nil
    if cur.startTime and GetTime then
        dt = now() - (cur.startTime or 0)
        wnd = (self.Timings and self.Timings.waveLateStart) or 2.0
        recentlyStarted = dt >= 0 and dt < wnd
    end
    -- Additional grace: if the model only just became visible, allow a wave shortly after
    local modelGrace = false
    if self._modelBecameVisibleAt and GetTime then
        local visDt = now() - (self._modelBecameVisibleAt or 0)
        local visWnd = (self.Timings and self.Timings.waveAfterModelVisible) or 1.2
        modelGrace = visDt >= 0 and visDt < visWnd
        if CLN.Utils and CLN.Utils.LogAnimDebug then 
            local cat = CLN.Utils.LogCategories and CLN.Utils.LogCategories.framing or "framing"
            CLN.Utils:LogAnimDebug(cat, "Visibility timing - visDt: " .. tostring(visDt) .. ", visWnd: " .. tostring(visWnd) .. ", modelGrace: " .. tostring(modelGrace))
        end
    end
    if self.Debug then self:Debug("Timing check - dt:", dt, "window:", wnd, "recentlyStarted:", recentlyStarted) end
    
    local hasInteractedRecently = self._fsmHasInteractedRecently()
    local canWave = (not hasInteractedRecently) and (recentlyStarted or modelGrace) and self._fsmCanWave()
    local shouldWave = self._fsmLooksLikeGreeting(cur.title)

    -- Reverence detection: bow takes priority over wave for formal/royal NPC text
    local shouldBow = false
    if canWave and self.GetReverenceConfidence then
        local revConf = self:GetReverenceConfidence(cur.title or "", 15)
        shouldBow = revConf > 0.5
    end
    
    if self.Debug then self:Debug("Wave decision - hasInteractedRecently:", hasInteractedRecently, "canWave:", canWave, "shouldWave:", shouldWave, "shouldBow:", shouldBow) end

    if shouldBow and canWave and self:ModelHasAnimation((self.AnimIds and self.AnimIds.BOW) or 66) then
        self:_fsm_enter(S.BOW)
    elseif shouldWave and canWave then
        self:_fsm_enter(S.WAVE)
    else
        self:_fsm_enter(S.TALK)
    end

    -- Mark interaction after deciding/starting state so it doesn't block the wave gate
    self._fsmMarkInteracted()
end

function ReplayFrame:FSM_OnPlaybackStop(lastMsg)
    -- Skip frame manipulation during combat lockdown to avoid taint
    if InCombatLockdown and InCombatLockdown() then return end
    self:InitStateMachine()
    local fsm = self._fsm
    
    -- Smart debouncing for stop events
    local stopContext = {
        lastMsg = lastMsg,
        stopTime = now()
    }
    
    -- Avoid duplicate stop processing
    if fsm.lastStopContext then
        local isSameMsg = fsm.lastStopContext.lastMsg == stopContext.lastMsg
        local timeSinceLastStop = now() - (fsm.lastStopTime or 0)
        
    if self.Debug then self:Debug("Stop debounce check - sameMsg:", isSameMsg, "timeSince:", timeSinceLastStop) end
        
        if isSameMsg and timeSinceLastStop < 0.3 then
            if self.Debug then self:Debug("Skipping duplicate FSM_OnPlaybackStop call") end
            return
        end
    end
    
    fsm.lastStopContext = stopContext
    fsm.lastStopTime = now()
    
    if self.Debug then self:Debug("FSM_OnPlaybackStop processing - lastMsg:", lastMsg or "nil") end
    
    fsm.lastMsg = lastMsg

    -- Always go to IDLE on stop; farewell support removed
    if self.Debug then self:Debug("Entering IDLE state") end
    self:_fsm_enter(S.IDLE)
    -- schedule hide shortly if nothing is playing
    local delay = (self.Timings and self.Timings.stopHideDelay) or 0.6
    fsm.hideAt = now() + delay
end

-- Helper function to process pending context after animation completes
function ReplayFrame:_processPendingContext()
    local fsm = self._fsm
    if not fsm or not fsm.pendingContext then return end
    
    if self.Debug then self:Debug("Processing pending context for handle:", fsm.pendingContext.soundHandle) end
    
    -- Create a temporary current object from pending context
    local pendingCur = {
        soundHandle = fsm.pendingContext.soundHandle,
        title = fsm.pendingContext.title,
        npcId = fsm.pendingContext.npcId,
        startTime = fsm.pendingContext.startTime,
        isPlaying = function() 
            -- Check if this sound is still the currently playing one
            local actualCur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            return actualCur and actualCur.soundHandle == fsm.pendingContext.soundHandle and actualCur:isPlaying()
        end
    }
    
    -- Only process if the pending content is still actually playing
    if pendingCur:isPlaying() then
    if self.Debug then self:Debug("Pending context is still playing, processing now") end
        local ctx = fsm.pendingContext
        fsm.pendingContext = nil
        self:FSM_OnPlaybackStart(ctx)
    else
    if self.Debug then self:Debug("Pending context is no longer playing, discarding") end
        fsm.pendingContext = nil
    end
end

-- Public: per-frame tick; handles deferred hides and safety checks
function ReplayFrame:FSM_Tick()
    -- Skip frame manipulation during combat lockdown to avoid taint
    if InCombatLockdown and InCombatLockdown() then return end
    if not self._fsm then return end
    local fsm = self._fsm
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local playing = cur and cur.isPlaying and cur:isPlaying() or false

    -- Late hide if nothing resumed
    if (not playing) and fsm.hideAt and now() >= fsm.hideAt then
        fsm.hideAt = nil
        if self.ModelContainer then self.ModelContainer:Hide() end
        if self.NpcModelFrame then self.NpcModelFrame:Hide() end
    end

    -- Safety: if state is talk/bow/point but playback handle changed/ended, transition appropriately
    if fsm.state == S.TALK or fsm.state == S.BOW or fsm.state == S.POINT then
        if (not playing) or (cur and fsm.lastHandle and cur.soundHandle ~= fsm.lastHandle) then
            -- Debounce: avoid calling stop repeatedly for the same stale handle
            local staleHandle = fsm.lastHandle
            if staleHandle ~= fsm._lastTickStopHandle then
                fsm._lastTickStopHandle = staleHandle
                self:FSM_OnPlaybackStop(fsm.lastMsg)
            end
        end
    end
end
