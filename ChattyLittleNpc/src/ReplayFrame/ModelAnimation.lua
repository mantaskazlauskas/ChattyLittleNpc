---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

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

-- Public: stop all animations of a given kind ("zoom"|"pan")
function ReplayFrame:AnimStop(kind)
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
    ensureAnimTable(self)
    -- Skip creating an animation if there is effectively no delta
    if approxEqual(from, to) then
        if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
            CLN.Utils:LogAnimDebug("_AnimStart skipped no-op: " .. tostring(kind) .. " from=" .. tostring(from) .. " to=" .. tostring(to))
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
    
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
        CLN.Utils:LogAnimDebug("_AnimStart: " .. tostring(kind) .. " from=" .. tostring(from) .. " to=" .. tostring(to) .. " dur=" .. tostring(anim.dur))
    end
    
    table.insert(self._anims, anim)
    if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
    return anim
end

-- Public: animate zoom to target in [0..1]
function ReplayFrame:AnimZoomTo(target, duration, opts)
    local m = self.NpcModelFrame
    local from = self._currentZoom or 0.65
    if m and m.GetPortraitZoom then
        local ok, z = pcall(m.GetPortraitZoom, m)
        if ok and type(z) == "number" then from = z end
    end
    target = applyClamp(target or 0.65, 0, 1)
    
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
        CLN.Utils:LogAnimDebug("AnimZoomTo: from=" .. tostring(from) .. " to=" .. tostring(target) .. " dur=" .. tostring(duration or 0.5))
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
    return self:_AnimStart("zoom", from, target, duration or 0.5, opts)
end

-- Public: animate vertical pan (Z) to target
function ReplayFrame:AnimPanTo(targetZ, duration, opts)
    local m = self.NpcModelFrame
    local fromZ = (self._currentZOffset ~= nil) and self._currentZOffset or (self.modelZOffset or 0)
    if m and m.GetPosition then
        -- PlayerModel doesn't provide GetPosition reliably; keep our cached value
    end
    
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug() then
        CLN.Utils:LogAnimDebug("AnimPanTo: from=" .. tostring(fromZ) .. " to=" .. tostring(targetZ) .. " dur=" .. tostring(duration or 0.25))
    end
    
    -- Skip no-op pans
    if approxEqual(fromZ, targetZ) then
        self._currentZOffset = targetZ
        if m and m.SetPosition then pcall(m.SetPosition, m, 0, 0, targetZ) end
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return nil
    end

    self:AnimStop("pan")
    return self:_AnimStart("pan", fromZ, targetZ, duration or 0.25, opts)
end

-- Public: update all running animations; called each OnUpdate
function ReplayFrame:AnimUpdate(elapsed)
    if not elapsed or elapsed <= 0 then return end
    ensureAnimTable(self)
    if #self._anims == 0 then 
        if self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
        return 
    end
    
    local shouldLog = CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug()
    if shouldLog and #self._anims > 0 then 
        CLN.Utils:LogAnimDebug("AnimUpdate processing " .. tostring(#self._anims) .. " animations")
    end
    
    local m = self.NpcModelFrame
    local remain = {}
    for _, a in ipairs(self._anims) do
        a.t = a.t + elapsed
        local d = a.dur
        local rt = (a.t >= d) and 1 or (a.t / d)
        local e
        if a.easing == "linear" then e = rt else e = easeOutCubic(rt) end
        local v = a.from + (a.to - a.from) * e
        if a.kind == "zoom" then
            if m and m.SetPortraitZoom then 
                pcall(m.SetPortraitZoom, m, applyClamp(v, 0, 1))
                if shouldLog then 
                    CLN.Utils:LogAnimDebug("AnimUpdate zoom: " .. tostring(applyClamp(v, 0, 1)) .. " (progress: " .. tostring(rt) .. ")")
                end
            end
            self._currentZoom = applyClamp(v, 0, 1)
        elseif a.kind == "pan" then
            if m and m.SetPosition then 
                pcall(m.SetPosition, m, 0, 0, v)
                if shouldLog then 
                    CLN.Utils:LogAnimDebug("AnimUpdate pan: " .. tostring(v) .. " (progress: " .. tostring(rt) .. ")")
                end
            end
            self._currentZOffset = v
        end
        if rt >= 1 then
            -- complete
            if shouldLog then 
                CLN.Utils:LogAnimDebug("Animation " .. tostring(a.kind) .. " completed")
            end
            if a.onComplete then
                pcall(a.onComplete)
            end
        else
            table.insert(remain, a)
        end
    end
    self._anims = remain
    if #self._anims == 0 and self._UpdateModelOnUpdateHook then self:_UpdateModelOnUpdateHook() end
end
