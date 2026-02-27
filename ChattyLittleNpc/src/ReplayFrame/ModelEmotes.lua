---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Emote registry and helpers

-- Lightweight emote lifecycle events (optional):
-- Emits CLN_EMOTE_STARTED, CLN_EMOTE_COMPLETE, CLN_EMOTE_CANCELLED via CLN:SendMessage.
-- Also supports local listeners via ReplayFrame:OnEmote(event, fn).
function ReplayFrame:_EmitEmoteEvent(event, payload)
    local ev = tostring(event or "")
    if ev == "" then return end
    -- Addon-wide broadcast via shared event bus
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
    Camera = { },
    Timings = {
        recentlyStartedWindow = 0.6,
        stopHideDelay = 0.6,
        waveLateStart = 2.0,
    waveAfterModelVisible = 1.2, -- extra grace to allow waving shortly after model shows
    oneShotWatchTimeout = 2.0, -- fallback timeout for non-looping emote watcher
    },
    Loop = {
    talkChance = 0.97,
    talkMin = 3.5,
    talkMax = 7.5,
    idleMin = 0.15,
    idleMax = 0.35,
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

-- Animation ID constants for named emotes
ReplayFrame.AnimIds = ReplayFrame.AnimIds or {
    IDLE       = 0,
    TALK       = 60,
    TALK_EXCLM = 64,
    TALK_QUEST = 65,
    BOW        = 66,
    WAVE       = 67,
    CHEER      = 68,
    DANCE      = 69,
    KNEEL      = 70,
    POINT      = 25,
    SALUTE     = 113,
    YES        = 185,
    NO         = 186,
}

-- Check if the current model supports a given animation ID.
-- Uses HasAnimation() WoW API when available; returns true as fallback.
function ReplayFrame:ModelHasAnimation(animId)
    if animId == nil then return false end
    local m = self.NpcModelFrame
    if not m then return false end
    if m.HasAnimation then
        local ok, result = pcall(m.HasAnimation, m, animId)
        if ok then return result end
    end
    -- API unavailable — assume supported to avoid blocking
    return true
end
-- Deprecated helpers for absolute zoom removed; percent-based APIs are used throughout

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
    -- Guard: if an emote is already active, cancel it before starting a new one to avoid overlap
    if self._emoteActive then
        self:CancelEmote()
    end
    if name == "wave" then
        return self:PlayWaveEmote(opts)
    elseif name == "hello" then
        return self:PlayHelloEmote(opts)
    elseif name == "bow" or name == "kneel" then
        return self:PlayBowEmote(opts)
    elseif name == "point" or name == "salute" then
        return self:PlayPointEmote(opts)
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
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.emotes) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.emotes, "_StartEmoteSequence skipped due to debug no-op")
        end
        return false
    end
    if not (steps and type(steps) == "table" and #steps > 0) then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.emotes) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.emotes, "_StartEmoteSequence failed - invalid steps: " .. tostring(steps))
        end
        return false
    end
    local m = self.NpcModelFrame
    if not m then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.emotes) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.emotes, "_StartEmoteSequence failed - no NpcModelFrame")
        end
        return false
    end

    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.emotes) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.emotes, "Emote sequence start: steps=" .. tostring(#steps))
    end

    -- Cancel any prior running emote to avoid overlapping sequences
    if self._emoteActive then
        self:CancelEmote()
    end
    self._emoteSeqActive = true
    self._emoteSeqIndex = 0
    -- Generation token: stale C_Timer callbacks from cancelled sequences
    -- see _emoteSeqActive==true (re-set by new sequence) and would corrupt
    -- _emoteSeqIndex. The token lets callbacks detect they belong to a prior run.
    self._emoteSeqToken = (self._emoteSeqToken or 0) + 1
    local seqToken = self._emoteSeqToken

    local function stillActive()
        return self._emoteSeqActive and self._emoteActive and (self._emoteName ~= nil) and seqToken == self._emoteSeqToken
    end

    local function applyStep(step)
        if not self._emoteSeqActive or seqToken ~= self._emoteSeqToken then return end
        
        -- Camera transitions handled by animation system
        if step.zoom ~= nil and self.AnimZoomTo then
            self:AnimZoomTo(step.zoom, step.zoomDur or 0.4, { easing = step.zoomEase or "easeOutCubic" })
        end
        -- Named emote preset (Talk/Wave/Idle)
        if step.preset and step.preset ~= "" and self.ApplyEmotePreset then
            local dur = step.zoomDur
            self:ApplyEmotePreset(step.preset, dur or 0, { easing = step.zoomEase or "easeOutCubic", panDur = step.panDur })
        end
        -- Model-relative range zoom (takes precedence over raw zoom when provided)
        if step.rangeP0 ~= nil and step.rangeP1 ~= nil then
            local p0, p1 = step.rangeP0, step.rangeP1
            local dur = step.zoomDur
            if dur and dur > 0 and self.AnimZoomToRangePercent then
                self:AnimZoomToRangePercent(p0, p1, dur, { easing = step.zoomEase or "easeOutCubic" })
            elseif self.ShowRangePercent then
                self:ShowRangePercent(p0, p1, {})
            end
        end
        -- Pan: prefer model-relative percent when provided
        if step.panPercent ~= nil and self.AnimPanToPercent then
            self:AnimPanToPercent(step.panPercent, step.panDur or 0.25, { easing = step.panEase or "easeOutCubic" })
        elseif step.panZ ~= nil and self.AnimPanTo then
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
                    if self._emoteSeqActive and seqToken == self._emoteSeqToken and m and m.SetAnimation then pcall(m.SetAnimation, m, 67) end
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
        if not self._emoteSeqActive or seqToken ~= self._emoteSeqToken then return end
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
                    if self._emoteSeqActive and seqToken == self._emoteSeqToken then nextStep() end
                end)
            end
        else
            if C_Timer and C_Timer.After then
                C_Timer.After(hold, function()
                    if self._emoteSeqActive and seqToken == self._emoteSeqToken then nextStep() end
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
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    -- Accept either absolute or percent-based animation helpers
    local hasZoom = (self.AnimZoomTo ~= nil) or (self.AnimZoomToRangePercent ~= nil) or (self.ShowRangePercent ~= nil)
    local hasPan = (self.AnimPanTo ~= nil) or (self.AnimPanToPercent ~= nil)
    if not (m and hasZoom and hasPan) then 
        return false 
    end
    -- Skip entirely if the model isn't visible
    if not m:IsShown() then
        return false
    end

    local duration = tonumber(opts.duration) or 1.5
    local waveOutDur = (opts.waveOutDur ~= nil) and opts.waveOutDur or 0.2
    local zoomBackDur = (opts.zoomBackDur ~= nil) and opts.zoomBackDur or 0.5
    -- Use EmoteBuilder's standardized completion chaining
    local emoteName = tostring(opts.emoteName or "wave")

    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name(emoteName)
        :preset("Wave", { duration = waveOutDur, panDur = 0.15 })
        :anim(67)
        :hold(duration)
        :preset("Talk", { duration = zoomBackDur, panDur = 0.25 })
        :hold(0.05)
        :onComplete(function()
        -- Defer to FSM's EMOTE_COMPLETE handler to enter TALK and start loop.
        -- Avoid starting loop here to prevent duplicate PlayTalkEmote calls.
    end)
    :run()) or false
end

-- Alias: Hello emote uses the same wave choreography with tuned defaults
function ReplayFrame:PlayHelloEmote(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    opts = opts or {}
    if opts.duration == nil then opts.duration = 1.5 end
    if opts.waveZoom == nil then opts.waveZoom = 0.3 end
    if opts.waveOutDur == nil then opts.waveOutDur = 0.2 end
    if opts.zoomBackDur == nil then opts.zoomBackDur = 0.5 end
    opts.emoteName = opts.emoteName or "hello"
    return self:PlayWaveEmote(opts)
end

-- PlayByeEmote removed (farewell support dropped)

-- Nod (YES) emote: small zoom-in and quick nod using animation id 185 (EmoteYes).
-- Options: duration (default 0.9), zoomIn (default +0.08), lowerDelta (default 0.02)
function ReplayFrame:PlayNodEmote(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    local hasZoom = (self.AnimZoomTo ~= nil) or (self.AnimZoomToRangePercent ~= nil)
    local hasPan = (self.AnimPanTo ~= nil) or (self.AnimPanToPercent ~= nil)
    if not (m and hasZoom and hasPan) then return false end
    if not m:IsShown() then return false end
    opts = opts or {}
    local duration = tonumber(opts.duration) or 0.9
    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name("nod")
        -- Quick zoom to head/shoulders, slight up focus for the head
        :range(0.65, 1.00, 0.2)
        :panPercent(0.85, 0.15)
        :anim(185)
        :hold(duration)
        -- Return to upper body talk view
        :range(0.50, 1.00, 0.25)
        :panPercent(0.75, 0.15)
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
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    local hasZoom = (self.AnimZoomTo ~= nil) or (self.AnimZoomToRangePercent ~= nil)
    local hasPan = (self.AnimPanTo ~= nil) or (self.AnimPanToPercent ~= nil)
    if not (m and hasZoom and hasPan) then return false end
    if not m:IsShown() then return false end
    opts = opts or {}
    local duration = tonumber(opts.duration) or 1.1
    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name("headshake")
        -- Quick zoom to head/shoulders, slight up focus for the head
        :range(0.65, 1.00, 0.2)
        :panPercent(0.85, 0.15)
        :anim(186)
        :hold(duration)
        -- Return to upper body talk view
        :range(0.50, 1.00, 0.25)
        :panPercent(0.75, 0.15)
        :onComplete(function()
            -- Let animation system handle next steps after head shake
            local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            if cur and cur.isPlaying and cur:isPlaying() and self.StartEmoteLoop and self.NpcModelFrame and self.NpcModelFrame:IsShown() then
                self:StartEmoteLoop()
            end
        end)
    :run()) or false
end

-- Bow emote: reverential gesture using animation 66 (bow) with HasAnimation gating.
-- Falls back to nod (185) if the model doesn't support bow.
function ReplayFrame:PlayBowEmote(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    local hasZoom = (self.AnimZoomTo ~= nil) or (self.AnimZoomToRangePercent ~= nil)
    local hasPan = (self.AnimPanTo ~= nil) or (self.AnimPanToPercent ~= nil)
    if not (m and hasZoom and hasPan) then return false end
    if not m:IsShown() then return false end
    opts = opts or {}
    local duration = tonumber(opts.duration) or 1.8

    local A = ReplayFrame.AnimIds or {}
    local bowId = A.BOW or 66
    -- HasAnimation gating: fall back to nod if bow unsupported
    if not self:ModelHasAnimation(bowId) then
        bowId = A.YES or 185
        if not self:ModelHasAnimation(bowId) then return false end
    end

    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name("bow")
        :preset("Bow", { duration = 0.3, panDur = 0.2 })
        :anim(bowId)
        :hold(duration)
        :preset("Talk", { duration = 0.4, panDur = 0.2 })
        :hold(0.05)
        :onComplete(function() end)
    :run()) or false
end

-- Point emote: brief emphasis gesture using animation 25 (point) with HasAnimation gating.
-- Falls back to talk-exclamation (64) if the model doesn't support point.
function ReplayFrame:PlayPointEmote(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    local hasZoom = (self.AnimZoomTo ~= nil) or (self.AnimZoomToRangePercent ~= nil)
    local hasPan = (self.AnimPanTo ~= nil) or (self.AnimPanToPercent ~= nil)
    if not (m and hasZoom and hasPan) then return false end
    if not m:IsShown() then return false end
    opts = opts or {}
    local duration = tonumber(opts.duration) or 1.2

    local A = ReplayFrame.AnimIds or {}
    local pointId = A.POINT or 25
    -- HasAnimation gating: fall back to exclamation talk if point unsupported
    if not self:ModelHasAnimation(pointId) then
        pointId = A.TALK_EXCLM or 64
        if not self:ModelHasAnimation(pointId) then return false end
    end

    return (self.EmoteBuilder and self.EmoteBuilder:new()
        :name("point")
        :preset("Point", { duration = 0.25, panDur = 0.15 })
        :anim(pointId)
        :hold(duration)
        :preset("Talk", { duration = 0.3, panDur = 0.2 })
        :hold(0.05)
        :onComplete(function() end)
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

-- Pan using model-relative vertical coordinate p∈[0,1]
function ReplayFrame.EmoteBuilder:panPercent(p, duration, easing)
    self.cur.panPercent = p
    if duration ~= nil then self.cur.panDur = duration end
    if easing ~= nil then self.cur.panEase = easing end
    return self
end

-- Specify a model-relative vertical coverage [p0,p1]; if duration>0 we animate zoom
function ReplayFrame.EmoteBuilder:range(p0, p1, duration, easing)
    self.cur.rangeP0 = p0
    self.cur.rangeP1 = p1
    if duration ~= nil then self.cur.zoomDur = duration end
    if easing ~= nil then self.cur.zoomEase = easing end
    return self
end

-- Apply a named preset (e.g., "Talk", "Wave", "Idle"); options may carry duration/easing
function ReplayFrame.EmoteBuilder:preset(name, options)
    self.cur.preset = tostring(name or "")
    if options and options.duration ~= nil then self.cur.zoomDur = options.duration end
    if options and options.easing ~= nil then self.cur.zoomEase = options.easing end
    if options and options.panDur ~= nil then self.cur.panDur = options.panDur end
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
    if r and r._NoAnimDebugEnabled and r:_NoAnimDebugEnabled() then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.emotes) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.emotes, "EmoteBuilder run skipped due to debug no-op")
        end
        return false
    end
    if self.cur and (next(self.cur) ~= nil) then
        table.insert(self.steps, self.cur)
        self.cur = {}
    end
    
    -- Minimal logging only when debug is explicitly enabled
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.emotes) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.emotes, "EmoteBuilder run: steps=" .. tostring(#self.steps) .. ", name=" .. tostring(self._name))
    end
    
    -- Defer _emoteActive, _emoteName, and EMOTE_STARTED until after
    -- _StartEmoteSequence's internal cancel to avoid a spurious
    -- STARTED→CANCELLED→re-STARTED cycle.
    local savedName = self._name
    local runOpts = {}
    runOpts.onComplete = function()
        if self._internalOnComplete then pcall(self._internalOnComplete, r) end
        r:_EmitEmoteEvent("EMOTE_COMPLETE", { name = savedName })
        -- Clear emote state to let animation system take over
        r._emoteActive = false
        r._emoteName = nil
        -- Release builder references to allow GC
        self._internalOnComplete = nil
        self.steps = nil
        self.r = nil
    end
    
    local result = r:_StartEmoteSequence(self.steps, runOpts)
    if result then
        r._emoteActive = true
        r._emoteName = savedName
        r:_EmitEmoteEvent("EMOTE_STARTED", { name = savedName })
    end
    return result
end

-- Simple talk emote: choose appropriate talk animation id and apply; duration controlled by caller
function ReplayFrame:PlayTalkEmote(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    if not m then return false end
    opts = opts or {}
    -- Percent-based camera targets for TALK: upper body
    local talkRange = { p0 = 0.50, p1 = 1.00 }
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
        builder:name("talk"):preset("Talk", { duration = 0.5, panDur = 0.25 }):anim(talkId)
        -- Avoid passing variant unless explicitly requested; many models don't support it
        if variant then builder:animVariant(variant) end
        if duration > 0 then builder:hold(duration) end
        local ok = builder:run() or false
        return ok
    else
        -- For zero or no duration, just use the direct animation we already set
    -- Move camera to TALK targets unless caller requested skip (e.g. emote loop re-entry)
    if not opts.skipCamera and self.ApplyEmotePreset then self:ApplyEmotePreset("Talk", 0.5, { panDur = 0.25, easing = "easeOutCubic" }) end
        return true
    end
end

-- Simple idle emote: set to stand/idle
function ReplayFrame:PlayIdleEmote(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return false end
    local m = self.NpcModelFrame
    if not m then return false end
    opts = opts or {}
    -- Percent-based camera targets for IDLE: full body
    local idleRange = { p0 = 0.00, p1 = 1.00 }
    if m.SetSheathed then pcall(m.SetSheathed, m, true) end

    local duration = tonumber(opts.duration) or 0
    if duration > 0 then
    local builder = self.EmoteBuilder and self.EmoteBuilder:new()
    if not builder then return false end
    builder:name("idle"):preset("Idle", { duration = 0.5, panDur = 0.25 }):anim(0)
        builder:hold(duration)
        local ok = builder:run() or false
        -- State writes removed; FSM owns state
        return ok
    else
        -- Direct idle animation, let system handle what comes next
        if self.SetModelAnim then self:SetModelAnim(0) elseif m.SetAnimation then pcall(m.SetAnimation, m, 0) end
    -- Move camera to IDLE targets unless caller requested skip (e.g. emote loop brief pause)
    if not opts.skipCamera and self.ApplyEmotePreset then self:ApplyEmotePreset("Idle", 0.5, { panDur = 0.25, easing = "easeOutCubic" }) end
        return true
    end
end

-- Conversation emote loop: 80% talk / 20% idle by RNG
function ReplayFrame:StartEmoteLoop(opts)
    if self._NoAnimDebugEnabled and self:_NoAnimDebugEnabled() then return end
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

    -- Start the first segment immediately; subsequent transitions are timer-driven
    -- (_emoteFirstSegmentForced forces talk, so no initial idle delay)
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
    -- Rare point gesture chance (~5%) during talk segments for emphatic text
    local chooseIdle
    local choosePoint = false
    if self._emoteFirstSegmentForced then
        chooseIdle = false
        self._emoteFirstSegmentForced = false
    else
        chooseIdle = (not self._loopLastWasIdle) and (math.random() > talkChance)
        -- Point gesture: only if not idle, not recently pointed, and model supports it
        if not chooseIdle and not self._loopLastWasPoint and math.random() < 0.05 then
            local cur2 = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            if cur2 and cur2.title and self.GetEmphasisConfidence then
                local emphConf = self:GetEmphasisConfidence(cur2.title)
                if emphConf > 0.3 and self.ModelHasAnimation and self:ModelHasAnimation((self.AnimIds and self.AnimIds.POINT) or 25) then
                    choosePoint = true
                end
            end
        end
    end
    local dur
    if choosePoint then
        dur = 1.4
        self._loopLastWasIdle = false
        self._loopLastWasPoint = true
        self:PlayPointEmote({ duration = 1.2 })
        self._emoteSegType = "point"
    elseif not chooseIdle then
        dur = math.random() * (talkMax - talkMin) + talkMin
        self._loopLastWasIdle = false
        self._loopLastWasPoint = false
        -- Emote loop re-entry: change animation only, camera already at Talk position
        self:PlayTalkEmote({ duration = 0, skipCamera = true })
        self._emoteSegType = "talk"
    else
        dur = math.random() * (idleMax - idleMin) + idleMin
        self._loopLastWasIdle = true
        self._loopLastWasPoint = false
        -- Brief idle pause in emote loop: change animation only, don't pan camera
        self:PlayIdleEmote({ duration = 0, skipCamera = true })
        self._emoteSegType = "idle"
    end
    local nowT = now or (GetTime and GetTime() or 0)
    -- Switch to timer-based scheduling; do not rely on per-frame polling
    self._emoteSegEndTime = nil
    
    -- Safety check: ensure model has an animation set (skip for point — emote handler owns it)
    local m = self.NpcModelFrame
    if m and not choosePoint then
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
    self._loopLastWasPoint = nil
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
        if not self._emoteLoopActive then return end
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
