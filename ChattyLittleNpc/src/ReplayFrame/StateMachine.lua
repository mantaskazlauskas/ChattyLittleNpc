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
    self._fsm_enter = function(newState)
        local fsm = self._fsm
        if fsm.state == newState then return end
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
            if self.SetIdleLoop then self:SetIdleLoop() end
            fsm.hideAt = nil
    elseif newState == S.WAVE then
            -- play wave/hello and return to talk on complete
            local ok = false
            if self.PlayEmote then
                ok = self:PlayEmote("hello", {
                    duration = 1.5,
                    waveZoom = 0.3,
                    waveOutDur = 0.2,
                    zoomBackDur = 0.5,
                    onComplete = function()
                        -- Guard that playback is still current
                        local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                        if cur and cur.isPlaying and cur:isPlaying() and self._fsm and self._fsm.lastHandle == cur.soundHandle then
                self:_fsm_enter(S.TALK)
                        else
                self:_fsm_enter(S.IDLE)
                        end
                    end
                })
            end
            if not ok then
                -- fallback directly to talk
        self:_fsm_enter(S.TALK)
            end
    elseif newState == S.TALK then
            -- Ensure camera in talk preset
            local cz = (self.Camera and self.Camera.TALK_ZOOM) or (self.DEFAULT_ZOOM or 0.65)
            if self.AnimZoomTo then self:AnimZoomTo(cz, 0.5, { easing = "easeOutCubic" }) end
            if self.AnimPanTo then
                local z = (self.modelZOffset ~= nil) and self.modelZOffset or (self._currentZOffset or 0)
                self:AnimPanTo(z, 0.25, { easing = "easeOutCubic" })
            end
            -- Set talk animation now, then start loop
            local m = self.NpcModelFrame
            local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            if m and m.SetAnimation and cur then
                local talkId = 60
                if self.ChooseTalkAnimIdForText and cur.title then
                    talkId = self:ChooseTalkAnimIdForText(cur.title)
                end
                pcall(m.SetAnimation, m, talkId)
                if m.SetSheathed then pcall(m.SetSheathed, m, true) end
        self._animState = S.TALK -- note: other modules use "talk" string; keep mapping consistent
                self._lastTalkId = talkId
            end
            if self.PlayEmote then self:PlayEmote("talk") end
            if self.StartEmoteLoop then self:StartEmoteLoop() end
    elseif newState == S.FAREWELL then
            -- Play a short bye/hello emote and schedule hide
            local msg = self._fsm and self._fsm.lastMsg or ""
            local emote = (msg and msg:lower():find("hello") or msg:lower():find("greetings") or msg:lower():find("well met")) and "hello" or "bye"
            local duration = (emote == "bye") and 1.2 or 1.5
            if self.ModelContainer then self.ModelContainer:Show() end
            if self.NpcModelFrame then self.NpcModelFrame:Show() end
            if self.PlayEmote then
                self:PlayEmote(emote, {
                    duration = duration,
                    onComplete = function()
            self:_fsm_enter(S.IDLE)
                        -- schedule hide if nothing resumed
                        local t = now() + 0.6
                        if self._fsm then self._fsm.hideAt = t end
                    end
                })
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
    if not cur then return end
    -- update handle & last message
    fsm.lastHandle = cur.soundHandle
    fsm.lastMsg = cur.title
    self._fsmMarkInteracted()

    -- Decide wave vs talk
    local recentlyStarted = false
    if cur.startTime and GetTime then
        local dt = now() - (cur.startTime or 0)
        local wnd = (self.Timings and self.Timings.waveLateStart) or 2.0
        recentlyStarted = dt >= 0 and dt < wnd
    end
    local canWave = (not self._fsmHasInteractedRecently()) and recentlyStarted and self._fsmCanWave()
    local shouldWave = self._fsmLooksLikeGreeting(cur.title)

    if shouldWave and canWave then
        self:_fsm_enter(S.WAVE)
    else
        self:_fsm_enter(S.TALK)
    end
end

function ReplayFrame:FSM_OnPlaybackStop(lastMsg)
    self:InitStateMachine()
    local fsm = self._fsm
    fsm.lastMsg = lastMsg

    -- Farewell decision
    if lastMsg and self._fsmLooksLikeFarewell(lastMsg) and self._fsmCanPlayBye() then
        self:_fsm_enter(S.FAREWELL)
    else
    self:_fsm_enter(S.IDLE)
        -- schedule hide shortly if nothing is playing
    local delay = (self.Timings and self.Timings.stopHideDelay) or 0.6
    fsm.hideAt = now() + delay
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
