---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

local M = {}
ReplayFrame.PlayerModelRenderer = M

local function safeCall(obj, method, ...)
    if not (obj and method and obj[method]) then return nil end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

local function debugf(category, fmt, ...)
    local U = CLN and CLN.Utils
    local cat = (CLN and CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories[category]) or category or (CLN and CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.modelFrame) or "modelFrame"
    if not (U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug(cat) and U.LogAnimDebug) then return end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    if not ok then msg = tostring(fmt) end
    pcall(U.LogAnimDebug, U, cat, msg)
end

-- Create a PlayerModel backend (frame)
function M.Create(parent)
    local pm = CreateFrame("PlayerModel", nil, parent)
    pm:SetAllPoints(parent)
    -- Don't intercept mouse clicks; keep background click-through
    if pm.EnableMouse then pcall(pm.EnableMouse, pm, false) end
    debugf("host", "PlayerModelRenderer.Create: frame=%s parent=%s", tostring(pm), tostring(parent))
    return { kind = "player", frame = pm }
end

-- Attach a PlayerModel-like API to host that wraps the backend PlayerModel
function M.Attach(host, backend)
    host._backend = backend
    host._zoom = host._zoom or 0.65
    host._lastAnimId = nil
    -- Framing emulation fields
    host._fovV = host._fovV or math.rad(60) -- fixed 60° vertical FOV
    host._distance = host._distance or 2.5
    host._scale = host._scale or 1.0
    host._targetZ = host._targetZ or 0
    host._yaw = host._yaw or 0

    function host:ClearModel()
    debugf("host", "PlayerModel.ClearModel()")
    host._pRef = nil
    host._zRef = nil
    safeCall(backend.frame, "ClearModel")
    end

    function host:SetDisplayInfo(displayID)
    host._currentDisplayID = displayID
        host._pRef = nil  -- reset per-host ProjectFit refs for new model
        host._zRef = nil
        debugf("loader", "PlayerModel.SetDisplayInfo(%s)", tostring(displayID))
        safeCall(backend.frame, "SetDisplayInfo", displayID)
    end

    function host:SetPortraitZoom(v)
        self._zoom = tonumber(v) or self._zoom or 0.65
        safeCall(backend.frame, "SetPortraitZoom", self._zoom)
    end

    function host:GetPortraitZoom()
        return self._zoom or 0.65
    end

    function host:SetPosition(x, y, z)
        self._targetZ = z or self._targetZ or 0
        safeCall(backend.frame, "SetPosition", x, y, z)
        -- Keep snapshot in sync so breathing animation preserves the Z offset
        if self._lastCamSnapshot then self._lastCamSnapshot.tz = z end
    end

    function host:SetRotation(rad)
        safeCall(backend.frame, "SetRotation", rad)
    end

    function host:SetAnimation(animId)
        self._lastAnimId = animId
    -- Respect ReplayFrame debug no-op animation mode
    local r = ReplayFrame
    if r and r:_NoAnimDebugEnabled() then return end
    safeCall(backend.frame, "SetAnimation", animId)
    end

    function host:GetAnimation()
        return safeCall(backend.frame, "GetAnimation") or self._lastAnimId
    end

    function host:SetSheathed(b)
        safeCall(backend.frame, "SetSheathed", b and true or false)
    end

    function host:SetPaused(b)
        safeCall(backend.frame, "SetPaused", b and true or false)
    end

    function host:SetUnit(unit)
    debugf("loader", "PlayerModel.SetUnit(%s)", tostring(unit))
    host._pRef = nil
    host._zRef = nil
    safeCall(backend.frame, "SetUnit", unit)
    end

    -- Compatibility stubs used by presets/code calling scene-style helpers
    function host:PointCameraAtHead() end
    function host:FrameFullBodyFront()
        -- Upper 2/3 shot: full-body zoom + negative z to crop feet/lower legs.
        -- _lastCamSnapshot.tz tells the breathing animation to preserve our offset.
        local z = -0.15
        if self.SetPortraitZoom then self:SetPortraitZoom(0.01) end
        if self.SetPosition then self:SetPosition(0, 0, z) end
        if self.SetRotation then self:SetRotation(0) end
        self._lastCamSnapshot = self._lastCamSnapshot or {}
        self._lastCamSnapshot.tz = z
    end
    function host:FitDefault()
        return self:FrameFullBodyFront()
    end
    function host:FlipFacing() end
    function host:AutoFitToFrame() end
    function host:OnModelLoadedOnce(cb)
        if type(cb) == "function" then cb(self) end
    end

    function host:ApplyPreset(presetName)
        local name = tostring(presetName or "FullBody")
        local P = ReplayFrame and ReplayFrame.PlayerPresets
        if P and P[name] then return P[name](self) end
        -- Fallbacks
        if name == "FullBody" then return self:FrameFullBodyFront(0.1) end
    end

    -- Positioning API stubs (PlayerModel lacks true 3D camera;
    -- best-effort emulation via portrait zoom + SetPosition offset)
    function host:SetModelPosition(anchor, xPct, yPct)
        -- PlayerModel has no 3D projection; store state for API parity
        self._positioning = {
            anchor = anchor or "BOTTOM",
            xPct   = tonumber(xPct) or 0.5,
            yPct   = tonumber(yPct) or 0,
        }
        -- Best-effort: map yPct to vertical offset
        local y = tonumber(yPct) or 0
        local z = -(y - 0.3) * 0.5  -- heuristic: 0.3 is roughly "natural"
        self:SetPosition(0, 0, z)
        return true
    end

    function host:ReapplyModelPosition()
        if not self._positioning then return false end
        return self:SetModelPosition(self._positioning.anchor, self._positioning.xPct, self._positioning.yPct)
    end

    function host:ClearModelPosition()
        if self._positioning then
            self._positioning = nil
            self._userControlledCamera = false
        end
    end

    -- Tiny Framing API (emulated for PlayerModel)
    function host:GetBounds()
        -- PlayerModel lacks reliable bounds; return nil to signal unknown
        return nil
    end

    function host:GetActorScale()
        return self._scale or 1.0
    end

    function host:SetActorScale(s)
        self._scale = tonumber(s) or 1.0
        -- Map actor scale proportionally to portrait zoom (heuristic)
        -- Keep zoom in [0, 1.5] range; base = 0.65
        local base = 0.65
        local zoom = math.max(0.0, math.min(1.5, base / math.max(0.1, self._scale)))
        self:SetPortraitZoom(zoom)
    end

    function host:GetActorYaw()
        return self._yaw or 0
    end

    function host:SetActorYaw(yaw)
        self._yaw = tonumber(yaw) or 0
        self:SetRotation(self._yaw)
    end

    function host:SetCamera(distance, yaw, pitch)
        -- PlayerModel has no real camera; emulate by storing and tweaking zoom/offset
        self._distance = tonumber(distance) or self._distance or 2.5
        self._yaw = tonumber(yaw) or self._yaw or 0
        -- pitch isn't supported; ignore but store
        self._pitch = tonumber(pitch) or self._pitch or 0
        -- Map distance to zoom inversely: more distance -> smaller zoom
        -- Choose simple linear map around typical distances
        local zoom = math.max(0.0, math.min(1.5, 3.2 - 0.4 * self._distance))
        self:SetPortraitZoom(zoom)
        -- Keep target z via SetPosition (x=y=0)
        self:SetPosition(0, 0, self._targetZ or 0)
        -- Apply yaw via rotation
        self:SetRotation(self._yaw)
    end

    function host:GetFovV()
        return self._fovV or math.rad(60)
    end

    function host:GetAspect()
        local w, h = self:GetSize()
        if not (w and h) or h == 0 then return 1.0 end
        return w / h
    end

    function host:SetTarget(vec3)
        vec3 = vec3 or {}
        self._targetZ = tonumber(vec3.z) or self._targetZ or 0
        self:SetPosition(0, 0, self._targetZ)
    end

    function host:ProjectFit(scale, targetCenter)
        -- Apply center first to get targetZ
        if targetCenter ~= nil then self:SetTarget(targetCenter) end
        -- If we have metadata for current displayID, use proportional mapping
        local meta
        if ReplayFrame and ReplayFrame.GetModelMeta then
            meta = ReplayFrame:GetModelMeta(host._currentDisplayID, nil, false)
        end
        if meta and meta.scaleD10 and meta.center then
            -- Record reference zoom per-host (NOT in shared meta) to avoid
            -- contaminating metadata when two hosts render the same displayID.
            host._pRef = host._pRef or self:GetPortraitZoom() or 0.65
            host._zRef = host._zRef or (targetCenter and targetCenter.z) or self._targetZ or 0
            -- Compute zoom proportional to scale
            local targetScale = tonumber(scale) or self._scale or 1.0
            targetScale = math.max(0.05, math.min(10, targetScale))
            local pRef = host._pRef
            local sRef = tonumber(meta.scaleD10) or 1.0
            local zoom = math.max(0.0, math.min(1.5, pRef * (sRef / targetScale)))
            self:SetPortraitZoom(zoom)
            -- Adjust Z so that center.z tracks with scale (Δz scaled by 1/scale)
            local cz = (targetCenter and targetCenter.z) or self._targetZ or 0
            local z = (host._zRef or 0) + ((cz - (meta.center.z or 0)) / targetScale)
            self:SetPosition(0, 0, z)
            -- Keep yaw and emulated distance mapping
            self:SetRotation(self._yaw or 0)
            return
        end
        -- Fallback generic mapping
        if scale ~= nil then self:SetActorScale(scale) end
        self:SetCamera(self._distance or 2.5, self._yaw or 0, self._pitch or 0)
    end

    -- Keep backend visibility in sync with the host so it actually renders when shown
    if host.HookScript then
        host:HookScript("OnShow", function()
            if backend.frame and backend.frame.Show then pcall(backend.frame.Show, backend.frame) end
        end)
        host:HookScript("OnHide", function()
            if backend.frame and backend.frame.Hide then pcall(backend.frame.Hide, backend.frame) end
        end)
    end
end

