---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Emote registry and helpers

-- Lightweight emote lifecycle events (optional):
-- Emits CLN_EMOTE_STARTED, CLN_EMOTE_COMPLETE, CLN_EMOTE_CANCELLED via AceEvent if available.
-- Also supports local listeners via ReplayFrame:OnEmote(event, fn).
function ReplayFrame:_EmitEmoteEvent(event, payload)
    local ev = tostring(event or "")
    if ev == "" then return end
    -- AceEvent broadcast (addon-wide)
    if CLN and CLN.SendMessage then
        pcall(CLN.SendMessage, CLN, "CLN_" .. ev, payload, self)
    end
    -- Local listeners on this frame
    if self._emoteEventHandlers and self._emoteEventHandlers[ev] then
        for _, fn in ipairs(self._emoteEventHandlers[ev]) do
            pcall(fn, payload, self)
        end
    end
end

function ReplayFrame:OnEmote(event, fn)
    if type(fn) ~= "function" then return end
    local ev = tostring(event or "")
    if ev == "" then return end
    self._emoteEventHandlers = self._emoteEventHandlers or {}
    self._emoteEventHandlers[ev] = self._emoteEventHandlers[ev] or {}
    table.insert(self._emoteEventHandlers[ev], fn)
    return fn
end

-- Remove a previously registered local listener for an emote event
function ReplayFrame:OffEmote(event, fn)
    local ev = tostring(event or "")
    if ev == "" or type(fn) ~= "function" then return end
    local handlers = self._emoteEventHandlers and self._emoteEventHandlers[ev]
    if not handlers then return end
    for i = #handlers, 1, -1 do
        if handlers[i] == fn then
            table.remove(handlers, i)
            break
        end
    end
end

-- Register a one-shot local listener that auto-unregisters after the first call
function ReplayFrame:OnceEmote(event, fn)
    if type(fn) ~= "function" then return end
    local selfRef
    local wrapper = function(payload)
        -- ensure we remove before invoking to avoid reentrancy issues
        if selfRef then selfRef:OffEmote(event, wrapper) end
        fn(payload)
    end
    selfRef = self
    return self:OnEmote(event, wrapper)
end

-- Global camera default (kept consistent across modules)
ReplayFrame.Config = ReplayFrame.Config or {
    DEFAULT_ZOOM = 0.65,
    Camera = {
        TALK_ZOOM = 0.60, -- slightly more zoomed out for talk
        IDLE_ZOOM = 0.60, -- slightly more zoomed out for idle
        WAVE_ZOOM = 0.3,
        HAND_FOCUS_DELTA = -0.25, -- legacy/fallback delta
    TALK_PAN_Z = -0.12,       -- absolute Z for talk pan (higher)
    IDLE_PAN_Z = -0.12,       -- absolute Z for idle pan (higher)
    },
    Timings = {
        recentlyStartedWindow = 0.6,
        stopHideDelay = 0.6,
        waveLateStart = 2.0,
    waveAfterModelVisible = 1.2, -- extra grace to allow waving shortly after model shows
    oneShotWatchTimeout = 2.0, -- fallback timeout for non-looping emote watcher
    },
    Loop = {
    talkChance = 0.92,
    talkMin = 1.8,
    talkMax = 3.2,
    idleMin = 0.25,
    idleMax = 0.6,
    },
}

-- Utility: get current portrait zoom (cached or queried)
local function getCurrentZoom(self)
    if self._currentZoom then return self._currentZoom end
    if self.NpcModelFrame and self.NpcModelFrame.GetPortraitZoom then
        local ok, z = pcall(self.NpcModelFrame.GetPortraitZoom, self.NpcModelFrame)
        if ok and type(z) == "number" then return z end
    end
    return (ReplayFrame.Config and ReplayFrame.Config.DEFAULT_ZOOM) or 0.65
end

-- Utility: get baseline Z offset
local function getBaseZ(self)
    return (self.modelZOffset ~= nil) and self.modelZOffset or (self._currentZOffset or 0)
end

-- Utility: clamp to [0..1]
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Camera targets per state (can be overridden on the frame)
local function getTalkZoom(self)
    return clamp01((self.talkZoom ~= nil) and self.talkZoom or (ReplayFrame.Config and ReplayFrame.Config.Camera and ReplayFrame.Config.Camera.TALK_ZOOM) or (ReplayFrame.Config and ReplayFrame.Config.DEFAULT_ZOOM) or 0.65)
end

local function getIdleZoom(self)
    return clamp01((self.idleZoom ~= nil) and self.idleZoom or (ReplayFrame.Config and ReplayFrame.Config.Camera and ReplayFrame.Config.Camera.IDLE_ZOOM) or (ReplayFrame.Config and ReplayFrame.Config.DEFAULT_ZOOM) or 0.65)
end

-- Cancel any running emote
function ReplayFrame:CancelEmote()
    local old = self._emoteName
    self._emoteActive = false
    self._emoteName = nil
    self._emoteData = nil
    -- Mark any sequence runner as inactive; closures check these flags
    self._emoteSeqActive = false
    -- Notify cancellation
    self:_EmitEmoteEvent("EMOTE_CANCELLED", { name = old })
end

-- Public: Play an emote by name
function ReplayFrame:PlayEmote(name, opts)
    opts = opts or {}
    name = tostring(name or "")
    if name == "wave" then
        return self:PlayWaveEmote(opts)
    elseif name == "hello" then
        return self:PlayHelloEmote(opts)
    elseif name == "bye" or name == "goodbye" or name == "farewell" then
        return self:PlayByeEmote(opts)
    elseif name == "nod" or name == "yes" then
        return self:PlayNodEmote(opts)
    elseif name == "no" or name == "shake" or name == "headshake" then
        return self:PlayHeadShakeEmote(opts)
    elseif name == "talk" then
        return self:PlayTalkEmote(opts)
    elseif name == "idle" then
        return self:PlayIdleEmote(opts)
    end
    return false
end

-- =============================
-- Emote Sequence Runner
-- =============================

-- Run a simple sequence where each step can specify target zoom and/or pan (Z) and durations.
-- Each step may also apply an animation id or a named emote animation.
-- steps: array of { zoom?, zoomDur?, panZ?, panDur?, animId?, animName?, hold? }
-- Note: completion is emitted via EMOTE_COMPLETE; external callbacks are deprecated.
function ReplayFrame:_StartEmoteSequence(steps, opts)
    if not (steps and type(steps) == "table" and #steps > 0) then 
        CLN.Utils:LogAnimDebug("_StartEmoteSequence failed - invalid steps: " .. tostring(steps))
        return false 
    end
    local m = self.NpcModelFrame
    if not m then 
        CLN.Utils:LogAnimDebug("_StartEmoteSequence failed - no NpcModelFrame")
        return false 
    end

    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
        CLN.Utils:LogAnimDebug("Emote sequence start: steps=" .. tostring(#steps))
    end

    self:CancelEmote()
    self._emoteSeqActive = true
    self._emoteSeqIndex = 0

    local function stillActive()
        return self._emoteSeqActive and self._emoteActive and (self._emoteName ~= nil)
    end

    local function applyStep(step)
        if not self._emoteSeqActive then return end
        
        -- Camera transitions handled by animation system
        if step.zoom ~= nil and self.AnimZoomTo then
            self:AnimZoomTo(step.zoom, step.zoomDur or 0.4, { easing = step.zoomEase or "easeOutCubic" })
        end
        if step.panZ ~= nil and self.AnimPanTo then
            self:AnimPanTo(step.panZ, step.panDur or 0.25, { easing = step.panEase or "easeOutCubic" })
        end
        -- Model animation - apply immediately for instant response
        if step.animId and m.SetAnimation then
            -- Prefer wrapper to reduce flicker for common talk/idle ids
            if self.SetModelAnim and (step.animId == 60 or step.animId == 64 or step.animId == 65 or step.animId == 0 or step.animId == 67 or step.animId == 185 or step.animId == 186) then
                self:SetModelAnim(step.animId)
            else
                pcall(m.SetAnimation, m, step.animId)
            end
            -- Some animations need a quick reapply to ensure they take
            if step.animId == 67 and C_Timer and C_Timer.After then
                C_Timer.After(0.01, function()
                    if self._emoteSeqActive and m and m.SetAnimation then pcall(m.SetAnimation, m, 67) end
                end)
            end
            -- Update state immediately
            -- State writes removed; FSM owns state. We only set animations.
        elseif step.animName then
            -- Use higher level for named emotes
            if step.animName == "talk" then
                self:PlayTalkEmote({})
            elseif step.animName == "idle" then
                self:PlayIdleEmote({})
            end
        end
    end

    local function nextStep()
        if not self._emoteSeqActive then return end
        self._emoteSeqIndex = (self._emoteSeqIndex or 0) + 1
        local step = steps[self._emoteSeqIndex]
        if not step then
            -- Sequence complete
            self._emoteSeqActive = false
            self._emoteActive = false
            local finishedName = self._emoteName
            self._emoteName = nil
            -- Emit completion if not already handled by builder.run
            if not (opts and opts.onComplete) then
                self:_EmitEmoteEvent("EMOTE_COMPLETE", { name = finishedName })
            else
                pcall(opts.onComplete)
            end
            return
        end
        applyStep(step)
        local hold = tonumber(step.hold) or 0
        if hold <= 0 then
            -- Immediate next step next frame
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if self._emoteSeqActive then nextStep() end
                end)
            end
        else
            if C_Timer and C_Timer.After then
                C_Timer.After(hold, function()
                    if self._emoteSeqActive then nextStep() end
                end)
            end
        end
    end

    -- Mark emote overall active for CancelEmote()
    self._emoteActive = true
    -- Begin
    nextStep()
    return true
end

-- Wave emote: declarative sequence of camera and animation steps
-- Options: duration (default 1.5), waveZoom (0.3), waveOutDur (0.2), zoomBackDur (0.5), lowerDelta (0.05)
function ReplayFrame:PlayWaveEmote(opts)
    local m = self.NpcModelFrame
    if not (m and self.AnimZoomTo and self.AnimPanTo) then 
        return false 
    end
    -- Skip entirely if the model isn't visible
    if not m:IsShown() then
        return false
    end

    local duration = tonumber(opts.duration) or 1.5
    local waveZoom = (opts.waveZoom ~= nil) and opts.waveZoom or (ReplayFrame.Config and ReplayFrame.Config.Camera and ReplayFrame.Config.Camera.WAVE_ZOOM) or 0.3
    local waveOutDur = (opts.waveOutDur ~= nil) and opts.waveOutDur or 0.2
    local zoomBackDur = (opts.zoomBackDur ~= nil) and opts.zoomBackDur or 0.5
    local lowerDelta = (opts.lowerDelta ~= nil) and opts.lowerDelta or (self.waveLowerDelta or 0.05)
    -- After waving, transition to the defined talk zoom, not merely the original zoom
    local targetAfterWave = getTalkZoom(self)
    local baseZ = getBaseZ(self)
    local cam = ReplayFrame.Config and ReplayFrame.Config.Camera or {}
    local handDelta = cam.HAND_FOCUS_DELTA or 0
    local wavePanZ = baseZ + handDelta - lowerDelta
    local afterPanZ = (cam and cam.TALK_PAN_Z) or baseZ
    -- Use EmoteBuilder's standardized completion chaining
    local emoteName = tostring(opts.emoteName or "wave")

    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name(emoteName)
        :zoom(waveZoom, waveOutDur)
    :pan(wavePanZ, 0.15)
        :anim(67)
        :hold(duration)
        :zoom(targetAfterWave, zoomBackDur)
    :pan(afterPanZ, 0.25)
        :hold(0.05)
    :onComplete(function()
        -- Defer to FSM's EMOTE_COMPLETE handler to enter TALK and start loop.
        -- Avoid starting loop here to prevent duplicate PlayTalkEmote calls.
    end)
    :run()) or false
end

-- Alias: Hello emote uses the same wave choreography with tuned defaults
function ReplayFrame:PlayHelloEmote(opts)
    opts = opts or {}
    if opts.duration == nil then opts.duration = 1.5 end
    if opts.waveZoom == nil then opts.waveZoom = 0.3 end
    if opts.waveOutDur == nil then opts.waveOutDur = 0.2 end
    if opts.zoomBackDur == nil then opts.zoomBackDur = 0.5 end
    opts.emoteName = opts.emoteName or "hello"
    return self:PlayWaveEmote(opts)
end

-- Targeted Bye/Farewell emote: a slightly snappier wave
function ReplayFrame:PlayByeEmote(opts)
    opts = opts or {}
    if opts.duration == nil then opts.duration = 1.2 end
    if opts.waveZoom == nil then opts.waveZoom = 0.3 end
    if opts.waveOutDur == nil then opts.waveOutDur = 0.15 end
    if opts.zoomBackDur == nil then opts.zoomBackDur = 0.4 end
    if opts.lowerDelta == nil then opts.lowerDelta = (self.waveLowerDelta or 0.04) end
    opts.emoteName = opts.emoteName or "bye"
    return self:PlayWaveEmote(opts)
end

-- Nod (YES) emote: small zoom-in and quick nod using animation id 185 (EmoteYes).
-- Options: duration (default 0.9), zoomIn (default +0.08), lowerDelta (default 0.02)
function ReplayFrame:PlayNodEmote(opts)
    local m = self.NpcModelFrame
    if not (m and self.AnimZoomTo and self.AnimPanTo) then return false end
    if not m:IsShown() then return false end
    opts = opts or {}
    local duration = tonumber(opts.duration) or 0.9
    local zoomIn = (opts.zoomIn ~= nil) and opts.zoomIn or 0.08
    local lowerDelta = (opts.lowerDelta ~= nil) and opts.lowerDelta or 0.02

    local baseZoom = getCurrentZoom(self)
    local targetZoom = math.min(1, math.max(0, baseZoom + zoomIn))
    local baseZ = getBaseZ(self)

    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name("nod")
        :zoom(targetZoom, 0.2)
        :pan(baseZ - lowerDelta, 0.15)
    :anim(185)
        :hold(duration)
        :zoom(baseZoom, 0.25)
        :pan(baseZ, 0.15)
        :onComplete(function()
            -- Let animation system handle next steps after nod
            local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            if cur and cur.isPlaying and cur:isPlaying() and self.StartEmoteLoop and self.NpcModelFrame and self.NpcModelFrame:IsShown() then
                self:StartEmoteLoop()
            end
        end)
    :run()) or false
end

-- Head shake (NO) emote: small zoom-in and quick head shake using animation id 186 (EmoteNo).
-- Options: duration (default 1.1), zoomIn (default +0.08), lowerDelta (default 0.02)
function ReplayFrame:PlayHeadShakeEmote(opts)
    local m = self.NpcModelFrame
    if not (m and self.AnimZoomTo and self.AnimPanTo) then return false end
    if not m:IsShown() then return false end
    opts = opts or {}
    local duration = tonumber(opts.duration) or 1.1
    local zoomIn = (opts.zoomIn ~= nil) and opts.zoomIn or 0.08
    local lowerDelta = (opts.lowerDelta ~= nil) and opts.lowerDelta or 0.02

    local baseZoom = getCurrentZoom(self)
    local targetZoom = math.min(1, math.max(0, baseZoom + zoomIn))
    local baseZ = getBaseZ(self)

    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name("headshake")
        :zoom(targetZoom, 0.2)
        :pan(baseZ - lowerDelta, 0.15)
    :anim(186)
        :hold(duration)
        :zoom(baseZoom, 0.25)
        :pan(baseZ, 0.15)
        :onComplete(function()
            -- Let animation system handle next steps after head shake
            local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            if cur and cur.isPlaying and cur:isPlaying() and self.StartEmoteLoop and self.NpcModelFrame and self.NpcModelFrame:IsShown() then
                self:StartEmoteLoop()
            end
        end)
    :run()) or false
end

-- =============================
-- EmoteBuilder DSL
-- =============================

ReplayFrame.EmoteBuilder = ReplayFrame.EmoteBuilder or {}

function ReplayFrame.EmoteBuilder:new()
    local o = {
        r = ReplayFrame,
        steps = {},
        cur = {},
    _name = nil,
    _internalOnComplete = nil,
    }
    setmetatable(o, { __index = self })
    return o
end

-- Set the emote name for state tracking
function ReplayFrame.EmoteBuilder:name(emoteName)
    self._name = tostring(emoteName or "")
    return self
end

-- Optional internal completion handler set by the emote implementation.
-- This will execute before EMOTE_COMPLETE is emitted.
function ReplayFrame.EmoteBuilder:onComplete(fn)
    if type(fn) == "function" then
        self._internalOnComplete = fn
    else
        self._internalOnComplete = nil
    end
    return self
end

-- Camera zoom target [0..1]
function ReplayFrame.EmoteBuilder:zoom(target, duration, easing)
    self.cur.zoom = target
    if duration ~= nil then self.cur.zoomDur = duration end
    if easing ~= nil then self.cur.zoomEase = easing end
    return self
end

-- Vertical pan (Z)
function ReplayFrame.EmoteBuilder:pan(targetZ, duration, easing)
    self.cur.panZ = targetZ
    if duration ~= nil then self.cur.panDur = duration end
    if easing ~= nil then self.cur.panEase = easing end
    return self
end

-- Set animation by id or name ("talk", "idle")
function ReplayFrame.EmoteBuilder:anim(idOrName)
    if type(idOrName) == "number" then
        self.cur.animId = idOrName
        self.cur.animName = nil
    else
        self.cur.animName = tostring(idOrName)
        self.cur.animId = nil
    end
    return self
end

-- Optional variant for animations that support it (e.g., SetAnimation(id, variant))
function ReplayFrame.EmoteBuilder:animVariant(variant)
    self.cur.animVar = tonumber(variant)
    return self
end

-- Finalize the current step with an optional hold, then start a new step
function ReplayFrame.EmoteBuilder:hold(seconds)
    self.cur.hold = tonumber(seconds) or 0
    return self:next()
end

-- Finalize the current step (no hold)
function ReplayFrame.EmoteBuilder:next()
    if self.cur and (next(self.cur) ~= nil) then
        table.insert(self.steps, self.cur)
    end
    self.cur = {}
    return self
end

-- Run the sequence on the ReplayFrame
function ReplayFrame.EmoteBuilder:run(opts)
    local r = self.r
    if self.cur and (next(self.cur) ~= nil) then
        table.insert(self.steps, self.cur)
        self.cur = {}
    end
    
    -- Minimal logging only when debug is explicitly enabled
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
        CLN.Utils:LogAnimDebug("EmoteBuilder run: steps=" .. tostring(#self.steps) .. ", name=" .. tostring(self._name))
    end
    
    if self._name and self._name ~= "" then
        r._emoteName = self._name
        -- Do not override top-level _animState here; FSM owns state. Per-step animId applies directly.
    end
    r._emoteActive = true
    -- Broadcast started
    r:_EmitEmoteEvent("EMOTE_STARTED", { name = self._name })
    -- Always run internal completion first (if present), then emit EMOTE_COMPLETE
    local runOpts = {}
    runOpts.onComplete = function()
        if self._internalOnComplete then pcall(self._internalOnComplete, r) end
        r:_EmitEmoteEvent("EMOTE_COMPLETE", { name = self._name })
        -- Clear emote state to let animation system take over
        r._emoteActive = false
        r._emoteName = nil
    end
    
    local result = r:_StartEmoteSequence(self.steps, runOpts)
    return result
end

-- Simple talk emote: choose appropriate talk animation id and apply; duration controlled by caller
function ReplayFrame:PlayTalkEmote(opts)
    local m = self.NpcModelFrame
    if not m then return false end
    opts = opts or {}
    -- Absolute camera targets for TALK
    local cam = ReplayFrame.Config and ReplayFrame.Config.Camera or {}
    local talkPanZ = (cam and cam.TALK_PAN_Z) or getBaseZ(self)
    local talkZoom = getTalkZoom(self)
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local talkId = 60
    if self.ChooseTalkAnimIdForText and cur and cur.title then
        talkId = self:ChooseTalkAnimIdForText(cur.title)
    end
    if m.SetSheathed then pcall(m.SetSheathed, m, true) end
    -- Use central setter to avoid redundant flicker and keep state consistent
    if self.SetModelAnim then self:SetModelAnim(talkId) elseif m.SetAnimation then pcall(m.SetAnimation, m, talkId) end

    -- Duration control via our emote system so we can emit completion events precisely
    local duration = tonumber(opts.duration) or 0
    -- Optional: callers may supply a specific variant via opts.talkVariant; we don't set by default
    local variant = tonumber(opts.talkVariant)
    
    -- Only use EmoteBuilder if we have a meaningful duration, otherwise just use direct animation
    if duration and duration > 0 then
        local builder = self.EmoteBuilder and self.EmoteBuilder:new()
        if not builder then 
            -- Fallback: animation already set above
            return true
        end
        builder:name("talk"):zoom(talkZoom, 0.5):pan(talkPanZ, 0.25):anim(talkId)
        -- Avoid passing variant unless explicitly requested; many models don't support it
        if variant then builder:animVariant(variant) end
        if duration > 0 then builder:hold(duration) end
        local ok = builder:run() or false
        return ok
    else
        -- For zero or no duration, just use the direct animation we already set
        -- Move camera absolutely to TALK targets
        if self.AnimZoomTo then self:AnimZoomTo(talkZoom, 0.5, { easing = "easeOutCubic" }) end
        if self.AnimPanTo then self:AnimPanTo(talkPanZ, 0.25, { easing = "easeOutCubic" }) end
        return true
    end
end

-- Simple idle emote: set to stand/idle
function ReplayFrame:PlayIdleEmote(opts)
    local m = self.NpcModelFrame
    if not m then return false end
    opts = opts or {}
    -- Absolute camera targets for IDLE
    local cam = ReplayFrame.Config and ReplayFrame.Config.Camera or {}
    local idlePanZ = (cam and cam.IDLE_PAN_Z) or getBaseZ(self)
    local idleZoom = getIdleZoom(self)
    if m.SetSheathed then pcall(m.SetSheathed, m, true) end

    local duration = tonumber(opts.duration) or 0
    if duration > 0 then
        local builder = self.EmoteBuilder and self.EmoteBuilder:new()
        if not builder then return false end
        builder:name("idle"):zoom(idleZoom, 0.5):pan(idlePanZ, 0.25):anim(0)
        builder:hold(duration)
        local ok = builder:run() or false
        -- State writes removed; FSM owns state
        return ok
    else
        -- Direct idle animation, let system handle what comes next
        if self.SetModelAnim then self:SetModelAnim(0) elseif m.SetAnimation then pcall(m.SetAnimation, m, 0) end
        -- Move camera absolutely to IDLE targets
        if self.AnimZoomTo then self:AnimZoomTo(idleZoom, 0.5, { easing = "easeOutCubic" }) end
        if self.AnimPanTo then self:AnimPanTo(idlePanZ, 0.25, { easing = "easeOutCubic" }) end
        return true
    end
end

-- Conversation emote loop: 80% talk / 20% idle by RNG
function ReplayFrame:StartEmoteLoop(opts)
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    if not (cur and cur.soundHandle and cur.isPlaying and cur:isPlaying()) then return end
    -- Guard: don't start another loop if already active for this handle
    if self._emoteLoopActive and self._emoteLoopHandle == cur.soundHandle then return end
    
    -- Cancel any conflicting animation first
    if self._emoteActive and self._emoteName and self._emoteName ~= "talk" then
        self:CancelEmote()
    end
    
    self._emoteLoopActive = true
    self._emoteLoopHandle = cur.soundHandle
    if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
    -- Reset loop scheduling token and cancel any pending timer
    self._emoteLoopToken = (self._emoteLoopToken or 0) + 1
    if self._emoteLoopTimer and self._emoteLoopTimer.Cancel then
        pcall(function() self._emoteLoopTimer:Cancel() end)
    end
    self._emoteLoopTimer = nil

    -- Camera will be set by PlayTalkEmote/PlayIdleEmote on each segment

    -- Store config for the loop; use sane defaults
    opts = opts or {}
    local L = (ReplayFrame.Config and ReplayFrame.Config.Loop) or {}
    self._loopTalkChance = tonumber(opts.talkChance or self.talkChance) or L.talkChance or 0.95
    self._loopTalkMin = tonumber(opts.talkMinDuration or self.talkMinDuration) or L.talkMin or 3.5
    self._loopTalkMax = tonumber(opts.talkMaxDuration or self.talkMaxDuration) or L.talkMax or 6.5
    self._loopIdleMin = tonumber(opts.idleMinDuration or self.idleMinDuration) or L.idleMin or 0.2
    self._loopIdleMax = tonumber(opts.idleMaxDuration or self.idleMaxDuration) or L.idleMax or 0.5
    self._loopLastWasIdle = false

    -- Ensure the first segment is TALK to avoid any initial idle
    self._emoteFirstSegmentForced = true
    -- Immediately start with talk animation to avoid idle delay (no sequence/hold)
    self:PlayTalkEmote({ duration = 0 })
    self._emoteSegType = "talk"
    
    -- Also ensure animation via central setter as fallback
    local m = self.NpcModelFrame
    if m then
        local talkId = 60
        if self.ChooseTalkAnimIdForText and cur and cur.title then
            talkId = self:ChooseTalkAnimIdForText(cur.title)
        end
        if self.SetModelAnim then self:SetModelAnim(talkId) elseif m.SetAnimation then pcall(m.SetAnimation, m, talkId) end
        if m.SetSheathed then pcall(m.SetSheathed, m, true) end
    end

    -- Start the first segment immediately; subsequent transitions are timer-driven
    if self._EmoteLoop_PickAndStartSegment then
        self:_EmoteLoop_PickAndStartSegment(GetTime and GetTime() or 0)
    end
end

-- Internal: Emote loop helpers
function ReplayFrame:_EmoteLoop_StillValid()
    local now = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    return self._emoteLoopActive and now and now.soundHandle == self._emoteLoopHandle and now.isPlaying and now:isPlaying()
end

function ReplayFrame:_EmoteLoop_PickAndStartSegment(now)
    if not self:_EmoteLoop_StillValid() then return end
    local talkChance = self._loopTalkChance or 0.95
    local talkMin, talkMax = self._loopTalkMin or 3.5, self._loopTalkMax or 6.5
    local idleMin, idleMax = self._loopIdleMin or 0.2, self._loopIdleMax or 0.5

    -- Prefer talking; inject short idle rarely and never twice in a row
    local chooseIdle
    if self._emoteFirstSegmentForced then
        chooseIdle = false
        self._emoteFirstSegmentForced = false
    else
        chooseIdle = (not self._loopLastWasIdle) and (math.random() > talkChance)
    end
    local dur
    if not chooseIdle then
        dur = math.random() * (talkMax - talkMin) + talkMin
        self._loopLastWasIdle = false
        self:PlayTalkEmote({ duration = 0 }) -- start immediately; duration driven by end time below
        self._emoteSegType = "talk"
    else
        dur = math.random() * (idleMax - idleMin) + idleMin
        self._loopLastWasIdle = true
        self:PlayIdleEmote({ duration = 0 })
        self._emoteSegType = "idle"
    end
    local nowT = now or (GetTime and GetTime() or 0)
    -- Switch to timer-based scheduling; do not rely on per-frame polling
    self._emoteSegEndTime = nil
    
    -- Safety check: ensure model has an animation set
    local m = self.NpcModelFrame
    if m then
        if not chooseIdle then
            -- Force set talk animation in case PlayTalkEmote didn't work
            local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            local talkId = 60
            if self.ChooseTalkAnimIdForText and cur and cur.title then
                talkId = self:ChooseTalkAnimIdForText(cur.title)
            end
            if self.SetModelAnim then self:SetModelAnim(talkId) elseif m.SetAnimation then pcall(m.SetAnimation, m, talkId) end
        else
            if self.SetModelAnim then self:SetModelAnim(0) elseif m.SetAnimation then pcall(m.SetAnimation, m, 0) end
        end
    end
    -- Schedule next segment via timer
    if self._EmoteLoop_ScheduleNext then
        self:_EmoteLoop_ScheduleNext(dur)
    end
end

function ReplayFrame:StopEmoteLoop()
    self._emoteLoopActive = false
    self._emoteLoopHandle = nil
    self._emoteSegEndTime = nil
    self._emoteSegType = nil
    self._loopLastWasIdle = nil
    self._emoteFirstSegmentForced = nil
    -- Invalidate and cancel any pending timer
    self._emoteLoopToken = (self._emoteLoopToken or 0) + 1
    if self._emoteLoopTimer and self._emoteLoopTimer.Cancel then
        pcall(function() self._emoteLoopTimer:Cancel() end)
    end
    self._emoteLoopTimer = nil
    if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
end

-- Schedule the next emote loop tick using C_Timer, with cancellation via token
function ReplayFrame:_EmoteLoop_ScheduleNext(dur)
    local tok = (self._emoteLoopToken or 0)
    local function cb()
        -- Ignore if loop stopped or token changed
        if not self:_EmoteLoop_StillValid() then return end
        if tok ~= (self._emoteLoopToken or 0) then return end
        if self._EmoteLoop_PickAndStartSegment then
            self:_EmoteLoop_PickAndStartSegment(GetTime and GetTime() or 0)
        end
    end
    if C_Timer and C_Timer.NewTimer then
        if self._emoteLoopTimer and self._emoteLoopTimer.Cancel then
            pcall(function() self._emoteLoopTimer:Cancel() end)
        end
        self._emoteLoopTimer = C_Timer.NewTimer(dur, cb)
    elseif C_Timer and C_Timer.After then
        -- After cannot be cancelled; token check in cb prevents stale execution
        C_Timer.After(dur, cb)
    end
end
