---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Finite State Machine for reliable animation control
-- States: idle -> wave? -> talk -> farewell? -> idle

-- Exported state constants (use these across modules to avoid string typos)
ReplayFrame.State = ReplayFrame.State or {
    IDLE = "idle",
    WAVE = "wave",
    TALK = "talk",
    FAREWELL = "farewell",
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
    self._fsmLooksLikeFarewell = function(msg)
        return self.Director and self.Director.LooksLikeFarewell and self.Director:LooksLikeFarewell(msg) or false
    end
    self._fsmCanPlayBye = function()
        return self.Director and self.Director.CanPlayBye and self.Director:CanPlayBye() or true
    end

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
        if fsm.state == S.WAVE then
            -- cancel any pending emote sequence
            if self.CancelEmote then self:CancelEmote() end
        end
        if fsm.state == S.FAREWELL then
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
            -- Let idle emote own absolute camera targets
            if self.PlayIdleEmote then self:PlayIdleEmote({ duration = 0 }) end
            if self.SetIdleLoop then self:SetIdleLoop() end
            fsm.hideAt = nil
            
            -- Check if we have pending context to process after entering idle
            self:_processPendingContext()
        elseif newState == S.WAVE then
            -- Stop any conversation loop/camera that might override wave choreography
            if self.StopEmoteLoop then self:StopEmoteLoop() end
            if self.AnimStop then self:AnimStop("zoom"); self:AnimStop("pan") end
            -- play hello and transition on EMOTE_COMPLETE
            local ok = false
            if self.PlayEmote then
                -- Register one-shot listeners using OnceEmote
                self:OnceEmote("EMOTE_STARTED", function(payload)
                    if not payload or payload.name ~= "hello" then return end
                    if self.Director and self.Director.MarkWaved then
                        self.Director:MarkWaved()
                    end
                end)
                self:OnceEmote("EMOTE_COMPLETE", function(payload)
                    if not payload or payload.name ~= "hello" then return end
                    -- Guard that playback is still current
                    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                    if cur and cur.isPlaying and cur:isPlaying() and self._fsm and self._fsm.lastHandle == cur.soundHandle then
                        self:_fsm_enter(S.TALK)
                    else
                        self:_fsm_enter(S.IDLE)
                    end
                    -- Process any pending context after wave completes
                    self:_processPendingContext()
                end)
                ok = self:PlayEmote("hello", { duration = 1.5, waveZoom = 0.3, waveOutDur = 0.2, zoomBackDur = 0.5 })
            else
                -- no PlayEmote available; fall back below
            end
            if not ok then
                -- fallback directly to talk
                self:_fsm_enter(S.TALK)
            end
        elseif newState == S.TALK then
            -- Let the conversation loop drive both animation and absolute camera targets
            if self.StartEmoteLoop then self:StartEmoteLoop() end
        elseif newState == S.FAREWELL then
            -- Play a short bye/hello emote and schedule hide
            local msg = self._fsm and self._fsm.lastMsg or ""
            local emote = (msg and msg:lower():find("hello") or msg:lower():find("greetings") or msg:lower():find("well met")) and "hello" or "bye"
            local duration = (emote == "bye") and 1.2 or 1.5
            if self.ModelContainer then self.ModelContainer:Show() end
            if self.NpcModelFrame then self.NpcModelFrame:Show() end
            if self.PlayEmote then
                local handled = false
                self:OnEmote("EMOTE_COMPLETE", function(payload)
                    if handled then return end
                    if not payload or payload.name ~= emote then return end
                    handled = true
                    self:_fsm_enter(S.IDLE)
                    -- schedule hide if nothing resumed
                    local t = now() + 0.6
                    if self._fsm then self._fsm.hideAt = t end
                    -- Process any pending context after farewell completes
                    self:_processPendingContext()
                end)
                self:PlayEmote(emote, { duration = duration })
            else
                self:_fsm_enter(S.IDLE)
            end
        end
    end

    -- A tiny guard flag to indicate FSM drives animations now
    self._fsmActive = true
end

-- Public: feed playback start/stop to FSM
function ReplayFrame:FSM_OnPlaybackStart(cur)
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
        -- But if we're currently in WAVE or FAREWELL state for different content, let it complete first
        if (fsm.state == S.WAVE or fsm.state == S.FAREWELL) and not isSameHandle then
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
    
    -- update handle & last message
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
            CLN.Utils:LogAnimDebug("Visibility timing - visDt: " .. tostring(visDt) .. ", visWnd: " .. tostring(visWnd) .. ", modelGrace: " .. tostring(modelGrace))
        end
    end
    if self.Debug then self:Debug("Timing check - dt:", dt, "window:", wnd, "recentlyStarted:", recentlyStarted) end
    
    local hasInteractedRecently = self._fsmHasInteractedRecently()
    local canWave = (not hasInteractedRecently) and (recentlyStarted or modelGrace) and self._fsmCanWave()
    local shouldWave = self._fsmLooksLikeGreeting(cur.title)
    
    if self.Debug then self:Debug("Wave decision - hasInteractedRecently:", hasInteractedRecently, "canWave:", canWave, "shouldWave:", shouldWave) end

    if shouldWave and canWave then
        self:_fsm_enter(S.WAVE)
    else
        self:_fsm_enter(S.TALK)
    end

    -- Mark interaction after deciding/starting state so it doesn't block the wave gate
    self._fsmMarkInteracted()
end

function ReplayFrame:FSM_OnPlaybackStop(lastMsg)
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

    -- Farewell decision
    if lastMsg and self._fsmLooksLikeFarewell(lastMsg) and self._fsmCanPlayBye() then
    if self.Debug then self:Debug("Entering FAREWELL state") end
        self:_fsm_enter(S.FAREWELL)
    else
    if self.Debug then self:Debug("Entering IDLE state") end
        self:_fsm_enter(S.IDLE)
        -- schedule hide shortly if nothing is playing
        local delay = (self.Timings and self.Timings.stopHideDelay) or 0.6
        fsm.hideAt = now() + delay
    end
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
        self:FSM_OnPlaybackStart(pendingCur)
    else
    if self.Debug then self:Debug("Pending context is no longer playing, discarding") end
        fsm.pendingContext = nil
    end
end

-- Public: per-frame tick; handles deferred hides and safety checks
function ReplayFrame:FSM_Tick()
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

    -- Safety: if state is talk but playback handle changed/ended, transition appropriately
    if fsm.state == S.TALK then
        if (not playing) or (cur and fsm.lastHandle and cur.soundHandle ~= fsm.lastHandle) then
            -- Treat as stop for our previous handle
            self:FSM_OnPlaybackStop(fsm.lastMsg)
        end
    end
end
