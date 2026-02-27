---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Tiny HostCamera interface: unify zoom/pan/yaw + minimal framing API across backends.
-- Contract (host should provide):
--   SetPortraitZoom(number), GetPortraitZoom() -> number
--   SetPosition(x, y, z)  -- we use z as vertical pan target
--   SetRotation(radians)  -- yaw
--   SetCamera(distance, yaw, pitch)
--   SetTarget({x=?,y=?,z=?})
--   GetFovV() -> radians, GetAspect() -> number
--   GetActorScale()/SetActorScale(number)
--   GetActorYaw()/SetActorYaw(number)
--   ProjectFit(scale?, center?)
-- Optional nice-to-haves: FitDefault, ShowUpper, ZoomToHeightFactor

ReplayFrame.HostCamera = ReplayFrame.HostCamera or {}
local HC = ReplayFrame.HostCamera

local function has(fn)
    return type(fn) == "function"
end

local function debugf(fmt, ...)
    local U = CLN and CLN.Utils
    if not (U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug("camera") and U.LogAnimDebug) then return end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    pcall(U.LogAnimDebug, U, "camera", ok and msg or tostring(fmt))
end

-- Normalize a host by attaching shims for any missing methods and agreeing on semantics.
function HC.Attach(host)
    if not host then return host end

    -- SetPosition should pan target Z while preserving X/Y when omitted
    -- Mark as internal pan so SetTarget doesn't block auto-framing
    if not has(host.SetPosition) and has(host.SetTarget) then
        host.SetPosition = function(self, x, y, z)
            local tz = tonumber(z)
            if tz == nil then return end
            local tx = (self._targetX ~= nil) and self._targetX or 0
            local ty = (self._targetY ~= nil) and self._targetY or 0
            self._internalPanActive = true
            pcall(self.SetTarget, self, { x = tx, y = ty, z = tz })
            self._internalPanActive = nil
        end
    end

    -- SetRotation should map to actor yaw if no native rotation
    if not has(host.SetRotation) and has(host.SetActorYaw) then
        host.SetRotation = function(self, r) self:SetActorYaw(tonumber(r) or 0) end
    end

    -- Provide a generic ProjectFit if missing
    if not has(host.ProjectFit) then
        host.ProjectFit = function(self, scale, targetCenter)
            if scale ~= nil and has(self.SetActorScale) then self:SetActorScale(scale) end
            if targetCenter ~= nil and has(self.SetTarget) then self:SetTarget(targetCenter) end
            if has(self.SetCamera) then self:SetCamera(self._distance or 2.5, self._yaw or 0, self._pitch or 0) end
            debugf("ProjectFit(shim): s=%s target=%s", tostring(scale), tostring(targetCenter))
        end
    end

    -- Generic FitDefault shim if not provided (may be overridden below by FramerScene)
    -- Frames the model as an upper-body bust (head/shoulders) facing forward.
    if not has(host.FitDefault) then
        host.FitDefault = function(self, _padding)
            -- ModelScene hosts have bounds-based framing; delegate to it
            local isScene = self._backend and self._backend.kind == "scene"
            if isScene and has(self.FrameFullBodyFront) then
                return self:FrameFullBodyFront(tonumber(_padding) or 0.12)
            end
            -- PlayerModel fallback: bust portrait zoom + position + rotation
            if has(self.SetPortraitZoom) then self:SetPortraitZoom(0.70) end
            if has(self.SetPosition) then self:SetPosition(0, 0, 0.08) end
            if has(self.SetRotation) then self:SetRotation(0) end
            debugf("FitDefault(shim)")
        end
    end

    -- Simple ShowUpper/ZoomToHeightFactor shims (defer to FitDefault or portrait zoom if bounds unknown)
    if not has(host.ShowUpper) then
        host.ShowUpper = function(self, _frac, _padding)
            if has(self.FitDefault) then return self:FitDefault(_padding) end
        end
    end
    if not has(host.ZoomToHeightFactor) then
        host.ZoomToHeightFactor = function(self, k, _padding)
            local K = tonumber(k) or 1.0
            if has(self.SetPortraitZoom) and has(self.GetPortraitZoom) then
                local p = self:GetPortraitZoom() or 0.65
                local newP = math.max(0.01, math.min(1.5, p / math.max(0.01, K)))
                self:SetPortraitZoom(newP)
                debugf("ZoomToHeightFactor(shim): k=%.3f p=%.3f->%.3f", K, p, newP)
            else
                if has(self.FitDefault) then self:FitDefault(_padding) end
            end
        end
    end

    -- Ensure portrait zoom getters/setters exist; as last resort, map through actor scale
    if not has(host.SetPortraitZoom) and has(host.SetActorScale) then
        host.SetPortraitZoom = function(self, v)
            local base = 0.65
            local zoom = tonumber(v) or base
            self._zoom = zoom
            local s = base / math.max(0.01, zoom)
            self:SetActorScale(s)
        end
    end
    if not has(host.GetPortraitZoom) and has(host.GetActorScale) then
        host.GetPortraitZoom = function(self)
            local base = 0.65
            local s = tonumber(self:GetActorScale()) or 1.0
            return base / math.max(0.01, s)
        end
    end

    -- Friendly one-shot helper some code may use
    function host:HostCameraSet(zoom, z, yaw)
        if zoom ~= nil and has(self.SetPortraitZoom) then self:SetPortraitZoom(zoom) end
        if z ~= nil and has(self.SetPosition) then self:SetPosition(0, 0, z) end
        if yaw ~= nil and has(self.SetRotation) then self:SetRotation(yaw) end
    end

    -- If advanced camera fitting is enabled and this is a ModelScene backend,
    -- delegate fit helpers to FramerScene for better results.
    local useAdvanced = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.advancedCameraFitting) and true or false
    local isScene = host._backend and host._backend.kind == "scene"
    if useAdvanced and isScene and ReplayFrame and ReplayFrame.FramerScene then
        local FS = ReplayFrame.FramerScene
        host.FitDefault = function(self, padding)
            return FS.FitDefault(self, self._lastDisplayID, padding)
        end
        host.ShowUpper = function(self, frac, padding)
            return FS.ShowUpper(self, self._lastDisplayID, frac, padding)
        end
        host.ZoomToHeightFactor = function(self, k, padding)
            return FS.ZoomToHeightFactor(self, k, padding)
        end
        host.ProjectFit = function(self, scale, center)
            return FS.ProjectFit(self, scale, center)
        end
    debugf("Advanced FramerScene delegates attached")
    end

    return host
end

return HC
