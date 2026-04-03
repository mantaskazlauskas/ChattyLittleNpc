---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Simple easing helpers
local function easeOutCubic(t)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function applyClamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Small numeric epsilon for no-op detection
local EPS = 1e-3
local function approxEqual(a, b, eps)
    eps = eps or EPS
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    return math.abs(a - b) <= eps
end

-- Ensure anim table
local function ensureAnimTable(self)
    if not self._anims then self._anims = {} end
end

function ReplayFrame:BreathingCameraUpdate(elapsed)
    if self:_CameraAnimsDisabled() then
        return
    end
    if not elapsed or elapsed <= 0 then return end
    ensureAnimTable(self)
    local B = self.Config and self.Config.Breathing
    -- Phase always advances so the sine wave stays time-accurate
    self._breathPhase = (self._breathPhase or 0) + elapsed
    if #self._anims > 0 then
        self._breathBaseZoom = nil
        self._breathBaseZ = nil
        self._breathLastAppliedZoom = nil
        self._breathLastAppliedZ = nil
        self._breathThrottleAccum = nil
        return
    end

    -- Throttle expensive work (trait lookup, sin, pcalls) to ~30 Hz
    local thr = self.Config and self.Config.Throttle
    self._breathThrottleAccum = (self._breathThrottleAccum or 0) + elapsed
    if self._breathThrottleAccum < (thr and thr.breathingInterval or 0.033) then return end
    self._breathThrottleAccum = 0

    local m = self.NpcModelFrame
    if not m then return end

    local traits = self.GetPersonalityTraits and self:GetPersonalityTraits() or { energy = 0.5, driftAmplitudeScale = 1 }
    local energyScale = (B and B.energyBase or 0.5) + (tonumber(traits.energy) or 0.5)
    local driftScale = tonumber(traits.driftAmplitudeScale) or 1
    local ampScale = math.max(B and B.ampClampMin or 0.5, math.min(B and B.ampClampMax or 1.5, energyScale * driftScale))
    local period = (B and B.periodBase or 6) - ((tonumber(traits.energy) or 0.5) * (B and B.periodEnergyScale or 2))
    period = math.max(B and B.periodClampMin or 4, math.min(B and B.periodClampMax or 6, period))
    local omega = (math.pi * 2) / period

    local liveZoom
    if m.GetPortraitZoom then
        local ok, z = pcall(m.GetPortraitZoom, m)
        if ok and type(z) == "number" then liveZoom = z end
    end
    if self._breathBaseZoom == nil then
        self._breathBaseZoom = liveZoom or self._currentZoom or (self.Config and self.Config.DEFAULT_ZOOM or 0.65)
    elseif liveZoom ~= nil and self._breathLastAppliedZoom ~= nil and not approxEqual(liveZoom, self._breathLastAppliedZoom) then
        self._breathBaseZoom = liveZoom
    end

    local snap = m._lastCamSnapshot
    local liveTz = (snap and type(snap.tz) == "number") and snap.tz or nil
    if self._breathBaseZ == nil then
        self._breathBaseZ = liveTz
        if self._breathBaseZ == nil then
            self._breathBaseZ = (self._currentZOffset ~= nil) and self._currentZOffset or (self.modelZOffset or 0)
        end
    elseif liveTz ~= nil and self._breathLastAppliedZ ~= nil and not approxEqual(liveTz, self._breathLastAppliedZ) then
        self._breathBaseZ = liveTz
    end

    local phase = self._breathPhase
    local zoomOffset = math.sin(phase * omega) * (B and B.zoomAmplitude or 0.004) * ampScale
    local panOffset = math.sin((phase * omega) + (B and B.panPhaseOffset or 1.2)) * (B and B.panAmplitude or 0.002) * ampScale
    local targetZoom = applyClamp((self._breathBaseZoom or (self.Config and self.Config.DEFAULT_ZOOM or 0.65)) + zoomOffset, 0, 1.5)
    local targetZ = (self._breathBaseZ or 0) + panOffset

    if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, targetZoom) end
    if m.SetPosition then pcall(m.SetPosition, m, 0, 0, targetZ) end
    self._breathLastAppliedZoom = targetZoom
    self._breathLastAppliedZ = targetZ
    self._currentZoom = targetZoom
    self._currentZOffset = targetZ
end

-- Public: stop all animations of a given kind ("zoom"|"pan")
function ReplayFrame:AnimStop(kind)
    if self:_CameraAnimsDisabled() then
        -- Ensure updater detaches since nothing should animate
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return
    end
    ensureAnimTable(self)
    local out = {}
    for _, a in ipairs(self._anims) do
        if a.kind ~= kind then table.insert(out, a) end
    end
    self._anims = out
    if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
end

-- Internal: start a generic animation
function ReplayFrame:_AnimStart(kind, from, to, duration, opts)
    if self:_CameraAnimsDisabled() then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "_AnimStart skipped due to debug no-op: " .. tostring(kind))
        end
        return nil
    end
    ensureAnimTable(self)
    -- Skip creating an animation if there is effectively no delta
    if approxEqual(from, to) then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "_AnimStart skipped no-op: " .. tostring(kind) .. " from=" .. tostring(from) .. " to=" .. tostring(to))
        end
        return nil
    end
    local anim = {
        kind = kind,
        from = from,
        to = to,
        dur = math.max(0.01, duration or 0.25),
        t = 0,
        easing = (opts and opts.easing) or "easeOutCubic",
        onComplete = opts and opts.onComplete,
    }
    
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "_AnimStart: " .. tostring(kind) .. " from=" .. tostring(from) .. " to=" .. tostring(to) .. " dur=" .. tostring(anim.dur))
    end
    
    table.insert(self._anims, anim)
    if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
    return anim
end

-- Public: animate zoom to target in [0..1.5]
function ReplayFrame:AnimZoomTo(target, duration, opts)
    if self:_CameraAnimsDisabled() then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "AnimZoomTo skipped due to debug no-op")
        end
        return nil
    end
    local Cam = self.Config and self.Config.Camera
    local m = self.NpcModelFrame
    local from = self._currentZoom or (self.Config and self.Config.DEFAULT_ZOOM or 0.65)
    if m and m.GetPortraitZoom then
        local ok, z = pcall(m.GetPortraitZoom, m)
        if ok and type(z) == "number" then from = z end
    end
    target = applyClamp(target or (self.Config and self.Config.DEFAULT_ZOOM or 0.65), 0, 1.5)
    
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "AnimZoomTo: from=" .. tostring(from) .. " to=" .. tostring(target) .. " dur=" .. tostring(duration or 0.5))
    end
    
    -- If already at target (within epsilon), avoid starting a redundant animation
    if approxEqual(from, target) then
        -- Ensure our cache is correct and detach updater if nothing else is running
        self._currentZoom = target
        if m and m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, target) end
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return nil
    end

    self:AnimStop("zoom")
    return self:_AnimStart("zoom", from, target, duration or (Cam and Cam.defaultZoomDur or 0.5), opts)
end

-- Public: animate vertical pan (Z) to target
function ReplayFrame:AnimPanTo(targetZ, duration, opts)
    if self:_CameraAnimsDisabled() then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
            CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "AnimPanTo skipped due to debug no-op")
        end
        return nil
    end
    local m = self.NpcModelFrame
    local fromZ = (self._currentZOffset ~= nil) and self._currentZOffset or (self.modelZOffset or 0)
    -- Prefer the host's camera snapshot as ground truth for the current Z.
    -- _currentZOffset may be stale (e.g. modelZOffset = -0.08 from setup) while
    -- the camera was repositioned to faceZ by FrameFullBodyFront / _ApplyCamera.
    -- Using the snapshot avoids a large first-frame delta in the SetTarget shim.
    if m and m._lastCamSnapshot and m._lastCamSnapshot.tz ~= nil then
        fromZ = m._lastCamSnapshot.tz
    end
    
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.animation) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.animation, "AnimPanTo: from=" .. tostring(fromZ) .. " to=" .. tostring(targetZ) .. " dur=" .. tostring(duration or 0.25))
    end
    
    -- Skip no-op pans
    if approxEqual(fromZ, targetZ) then
        self._currentZOffset = targetZ
        if m and m.SetPosition then pcall(m.SetPosition, m, 0, 0, targetZ) end
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return nil
    end

    self:AnimStop("pan")
    return self:_AnimStart("pan", fromZ, targetZ, duration or (self.Config and self.Config.Camera and self.Config.Camera.defaultPanDur or 0.25), opts)
end

-- Public: update all running animations; called each OnUpdate
function ReplayFrame:AnimUpdate(elapsed)
    if self:_CameraAnimsDisabled() then
        -- Ensure updater detaches
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return
    end
    if not elapsed or elapsed <= 0 then return end
    ensureAnimTable(self)
    if self.BreathingCameraUpdate then self:BreathingCameraUpdate(elapsed) end
    if #self._anims == 0 then 
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return 
    end
    
    local shouldLog = false
    
    local m = self.NpcModelFrame
    local remain = {}
    local completions
    for _, a in ipairs(self._anims) do
        a.t = a.t + elapsed
        local d = a.dur
        local rt = (a.t >= d) and 1 or (a.t / d)
        local e
        if a.easing == "linear" then e = rt else e = easeOutCubic(rt) end
        local v = a.from + (a.to - a.from) * e
        if a.kind == "zoom" then
            if m and m.SetPortraitZoom then 
                pcall(m.SetPortraitZoom, m, applyClamp(v, 0, 1.5))
            end
            self._currentZoom = applyClamp(v, 0, 1.5)
        elseif a.kind == "pan" then
            if m and m.SetPosition then 
                pcall(m.SetPosition, m, 0, 0, v)
            end
            self._currentZOffset = v
        end
        if rt >= 1 then
            -- Defer onComplete until after self._anims is updated to avoid
            -- callbacks that call AnimPanTo/AnimZoomTo having their new
            -- animation silently overwritten by the remain assignment below.
            if a.onComplete then
                if not completions then completions = {} end
                table.insert(completions, a.onComplete)
            end
        else
            table.insert(remain, a)
        end
    end
    self._anims = remain
    -- Fire deferred completions now that self._anims is safe to mutate
    if completions then
        for _, cb in ipairs(completions) do pcall(cb) end
    end
    if #self._anims == 0 and self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
end
