---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

local M = {}
ReplayFrame.ModelSceneRenderer = M

local function safeCall(obj, method, ...)
    if not (obj and method and obj[method]) then return nil end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

-- Create a ModelScene + Actor backend or return nil on failure
function M.Create(parent)
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, parent)
    if not (ok and scene) then return nil end
    -- Ensure the scene fills its parent host and renders above siblings
    if scene.SetAllPoints then
        if parent then
            pcall(scene.SetAllPoints, scene, parent)
        else
            pcall(scene.SetAllPoints, scene)
        end
    end
    -- Never block mouse; let clicks pass through the scene area
    if scene.EnableMouse then pcall(scene.EnableMouse, scene, false) end
    if scene.SetFrameStrata then
        local strata = (parent and parent.GetFrameStrata and parent:GetFrameStrata()) or "HIGH"
        pcall(scene.SetFrameStrata, scene, strata)
    end
    if scene.SetFrameLevel and parent and parent.GetFrameLevel then
        pcall(scene.SetFrameLevel, scene, (parent:GetFrameLevel() or 0) + 1)
    end
    local actor
    if scene.CreateActor then
        local okA, a = pcall(scene.CreateActor, scene, "ModelSceneActorTemplate")
        if okA and a then actor = a end
        if not actor then
            local okB, b = pcall(scene.CreateActor, scene)
            if okB and b then actor = b end
        end
    end
    if not actor and scene.GetPlayerActor then
        local okP, a = pcall(scene.GetPlayerActor, scene)
        if okP and a then actor = a end
    end
    if not actor then
        local U = CLN and CLN.Utils
        if U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug("host") and U.LogAnimDebug then
            U:LogAnimDebug("host", "ModelSceneRenderer: failed to create/get actor")
        end
        return nil
    end
    if scene.Show then pcall(scene.Show, scene) end
    if actor.Show then pcall(actor.Show, actor) end
    if actor.SetUseCenterForOrigin then pcall(actor.SetUseCenterForOrigin, actor, true) end
    -- Some UIs toggle desaturation on actors (e.g., previews); ensure it's off by default
    if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
    if scene.SetCameraNearClip then pcall(scene.SetCameraNearClip, scene, 0.1) end
    if scene.SetCameraFarClip then pcall(scene.SetCameraFarClip, scene, 100) end
    if scene.SetCameraFieldOfView then pcall(scene.SetCameraFieldOfView, scene, 0.8) end
    if scene.SetLightVisible then pcall(scene.SetLightVisible, scene, true) end
    if scene.SetLightDiffuseColor then pcall(scene.SetLightDiffuseColor, scene, 1, 1, 1) end
    if scene.SetLightAmbientColor then pcall(scene.SetLightAmbientColor, scene, 0.6, 0.6, 0.6) end
    if scene.SetLightType and _G.LE_MODEL_LIGHT_TYPE_DIRECTIONAL then
        pcall(scene.SetLightType, scene, _G.LE_MODEL_LIGHT_TYPE_DIRECTIONAL)
    end
    if scene.SetLightDirection then pcall(scene.SetLightDirection, scene, 0, -1, -0.5) end
    return { kind = "scene", frame = scene, actor = actor }
end

-- Attach the full scene-based API and camera utilities to host
function M.Attach(host, backend)
    host._backend = backend
    host._lastAnimId = nil
    do
        local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
        if MS and MS.AnimationController and not host._animCtrl then
            host._animCtrl = MS.AnimationController.new()
        end
    end
    host._zoom = host._zoom or 0.65
    host._camBaseZ = host._camBaseZ or 1.0
    host._camDist = host._camDist or 2.5
    -- Track camera side per-axis to avoid unintuitive flips when solver switches axes
    host._camDirY = (host._camDirY ~= nil) and host._camDirY or (host._camDir ~= nil and host._camDir or 1)
    host._camDirX = (host._camDirX ~= nil) and host._camDirX or 1
    -- Positive compBias shifts the look-at up (higher tz), moving content down on screen for headroom
    host._compBias = host._compBias ~= nil and host._compBias or 0.25
    -- host._frontYaw is nil until set by solver or user
        host._autoFaceCamera = host._autoFaceCamera ~= false  -- Default enabled

        -- Provide atan2 fallback if not available in this runtime
        local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
        -- Forward declare bounds helper used in delayed callbacks
        local _getBounds

    -- Host-scoped logger that adds session tagging when available
    function host:_DebugLog(category, fmt, ...)
        local U = CLN and CLN.Utils
        if not (U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug(category)) then return end
        local ok, res = pcall(string.format, tostring(fmt), ...)
        local msg = ok and res or tostring(fmt)
        if U.LogAnimDebugEx then
            pcall(U.LogAnimDebugEx, U, category or nil, msg, self._sessionId)
        elseif U.LogAnimDebug then
            pcall(U.LogAnimDebug, U, category or nil, msg)
        end
    end

    -- Centralized snapshot update to keep state consistent and finite
    function host:_UpdateSnapshot(fields)
        local s = self._lastCamSnapshot or {}
        if type(fields) == "table" then
            for k, v in pairs(fields) do
                if type(v) == "number" then
                    if v == v and v ~= 1/0 and v ~= -1/0 then s[k] = v end
                else
                    s[k] = v
                end
            end
        end
        if not s.sessionId then s.sessionId = self._sessionId end
        self._lastCamSnapshot = s
    end

    -- Model versioning to ignore stale async callbacks / frames
    function host:_BumpModelVersion()
        self._modelVersion = (self._modelVersion or 0) + 1
        self:_DebugLog("framing", "model version -> %d (session=%s)", self._modelVersion, tostring(self._sessionId))
        -- Cancel any pending auto-frame when a new model starts
        if self._frameTimer and self._frameTimer.Cancel then pcall(self._frameTimer.Cancel, self._frameTimer) end
        self._frameTimer = nil
        self._framePendingPad = nil
        self._framePendingReason = nil
    end

    -- Debounced/coalesced auto-framing coordinator
    function host:_RequestAutoFrame(paddingFrac, opts)
        opts = opts or {}
        local force = opts.force and true or false
        local reason = tostring(opts.reason or "auto")
    self:_DebugLog("framing", string.format("[Trigger] _RequestAutoFrame reason=%s (autoFace=%s userControlled=%s)", reason, tostring(self._autoFaceCamera ~= false), tostring(self._userControlledCamera or false)))
        if (not force) and self._userControlledCamera then
            self:_DebugLog("framing", "skip auto-frame (user-controlled) reason=%s", reason)
            return
        end
        self._framePendingPad = tonumber(paddingFrac) or self._framePendingPad or 0.12
        self._framePendingReason = reason
        local versionAtRequest = self._modelVersion or 0
        -- Coalesce bursts onto a single next-frame timer
        if self._frameTimer then return end
    local tries, stable, lastSig = 0, 0, nil
    local step -- forward declaration for timer closures
    local function scheduleNext(delay)
            if not (C_Timer and (C_Timer.After or C_Timer.NewTimer)) then return false end
            if C_Timer.After then
                self._frameTimer = true -- placeholder to block re-entry until callback
                C_Timer.After(delay, function()
                    self._frameTimer = nil
                    step()
                end)
                return true
            else
                local t = C_Timer.NewTimer(delay, function() self._frameTimer = nil; step() end)
                self._frameTimer = t
                return true
            end
        end
    step = function()
            -- Abort if model changed
            if (self._modelVersion or 0) ~= versionAtRequest then
                self:_DebugLog("framing", "abort pending frame (version changed) reason=%s", reason)
                return
            end
            local a = backend and backend.actor
            if not a then return end
            -- Check loaded state
            local isLoaded = true
            if a.IsLoaded then
                local okL, l = pcall(a.IsLoaded, a)
                isLoaded = okL and l or false
            end
            local cx, cy, cz, sx, sy, sz = _getBounds(a)
            local sig = (cx and string.format("%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", cx, cy or 0, cz or 0, sx or 0, sy or 0, sz or 0)) or "nil"
            if not isLoaded or not cx then
                tries = tries + 1
                if tries >= 20 and cx then
                    self:_DebugLog("framing", "proceed without full stability (tries=%d) reason=%s", tries, reason)
                    self:FrameFullBodyFront_ClosedForm(self._framePendingPad)
                    return
                end
                if scheduleNext(0.05) then return end
                -- No timer API; fallback immediate
                self:FrameFullBodyFront_ClosedForm(self._framePendingPad)
                return
            end
            if lastSig == sig then stable = stable + 1 else stable = 0; lastSig = sig end
            if stable >= 1 or tries >= 10 then
                self:_DebugLog("framing", "perform frame (stable=%d tries=%d) reason=%s", stable, tries, reason)
                self:FrameFullBodyFront_ClosedForm(self._framePendingPad)
                return
            end
            tries = tries + 1
            if scheduleNext(0.05) then return end
            -- Fallback immediate if no timers
            self:FrameFullBodyFront_ClosedForm(self._framePendingPad)
        end
        -- Next-frame coalescing
        if not scheduleNext(0) then
            -- If timers unavailable, run now
            step()
        end
    end

    -- Helper: log what asset the actor actually loaded (fileID/path/unitGUID)
    function host:_LogLoadedModelAsset(tag)
        local a = backend and backend.actor
        if not a then return end
        local okF, fid = pcall(a.GetModelFileID, a)
        local okP, path = pcall(a.GetModelPath, a)
        local okG, guid = pcall(a.GetModelUnitGUID, a)
        self:_DebugLog("host", "ModelLoaded[%s]: fileID=%s path=%s unitGUID=%s",
            tostring(tag or "?"), tostring(okF and fid or nil), tostring(okP and path or nil), tostring(okG and guid or nil))
    end

    -- Helper: comprehensive actor state reset for reliable texture loading
    function host:_PrepareActorForModelLoad(actor)
        if not actor then return end
        
        -- Clear any existing model and state
        if actor.ClearModel then pcall(actor.ClearModel, actor) end
        
        -- Reset transmog/dress flags to prevent player customization interference
        if actor.SetUseTransmogChoices then pcall(actor.SetUseTransmogChoices, actor, false) end
        if actor.SetUseTransmogSkin then pcall(actor.SetUseTransmogSkin, actor, false) end
        if actor.SetAutoDress then pcall(actor.SetAutoDress, actor, false) end
        
        -- Reset visual state flags that can cause texture issues
        if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
        if actor.SetAlpha then pcall(actor.SetAlpha, actor, 1.0) end
        
        -- Clear any animation that might interfere with model loading
        if actor.SetAnimation then pcall(actor.SetAnimation, actor, 0) end
        
        -- Reset any model draw layers or visual effects
        if actor.SetShown then pcall(actor.SetShown, actor, true) end
        
        self:_DebugLog("host", "_PrepareActorForModelLoad: reset actor state for clean model load")
    end

    -- Helper: apply post-load texture stabilization
    function host:_StabilizeModelTextures(actor)
        if not actor then return end
        
        -- Critical: Set animation blend operation for proper texture rendering (matches Blizzard's approach)
        if actor.SetAnimationBlendOperation and _G.Enum and _G.Enum.ModelBlendOperation then
            pcall(actor.SetAnimationBlendOperation, actor, _G.Enum.ModelBlendOperation.None)
        end
        
        -- Ensure desaturation is explicitly disabled
        if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
        
        -- Ensure full opacity
        if actor.SetAlpha then pcall(actor.SetAlpha, actor, 1.0) end
        
        -- Reset to idle animation only if no explicit desired animation is set to avoid flicker
        if actor.SetAnimation then
            local desired = self and self._lastAnimId
            if desired == nil then
                pcall(actor.SetAnimation, actor, 0)
            end
        end
        
        self:_DebugLog("host", "_StabilizeModelTextures: applied post-load texture stabilization")
    end

    local function _normalize(x, y, z)
        local len = math.sqrt((x or 0)^2 + (y or 0)^2 + (z or 0)^2)
        if len <= 1e-6 then return 0, 0, 0, 0 end
        return x / len, y / len, z / len, len
    end
    local function _cross(ax, ay, az, bx, by, bz)
        return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    end

    -- Diagnostics facade
    local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
    local Diagnostics = MS and MS.Diagnostics

    -- Compute coverage stats and screen bbox for current camera via Diagnostics
    local function _coverageStats(cx, cy, cz, sx, sy, sz, frameW, frameH)
        if backend.kind ~= "scene" or not (backend.frame) then return 0, 0, nil, nil, nil, nil end
        if Diagnostics and Diagnostics.coverageStats then
            return Diagnostics.coverageStats(backend.frame, cx, cy, cz, sx, sy, sz, frameW, frameH)
        end
        return 0, 0, nil, nil, nil, nil
    end

    function host:_ScheduleCameraSnapshotLog(delay)
        delay = tonumber(delay) or 1.0
        if self._camLogTimer and self._camLogTimer.Cancel then
            pcall(self._camLogTimer.Cancel, self._camLogTimer)
        end
        if C_Timer and C_Timer.NewTimer then
            self._camLogTimer = C_Timer.NewTimer(delay, function()
                self._camLogTimer = nil
                if self._lastCamSnapshot then
                    local s = self._lastCamSnapshot
                    self:_DebugLog("camera", "CameraFinalDelayed: pos=(%.2f,%.2f,%.2f) target=(%.2f,%.2f,%.2f) vfov=%.3f hfov=%.3f bounds=(cx=%.2f,cz=%.2f,sx=%.2f,sz=%.2f) dist=%.3f pad=%.2f axis=%s",
                        s.px or 0, s.py or 0, s.pz or 0, s.tx or 0, s.ty or 0, s.tz or 0,
                        s.vfov or 0, s.hfov or 0, s.cx or 0, s.cz or 0, s.sx or 0, s.sz or 0, s.dist or 0, s.pad or 0, tostring(s.axis))
                    local fw, fh = self:GetSize()
                    if self._DebugCheckProjection then
                        -- Use fresh bounds if the actor has rotated since snapshot; fall back to snapshot if unavailable
                        local cx2, cy2, cz2, sx2, sy2, sz2 = _getBounds(backend.actor)
                        local useCx, useCy, useCz = cx2 or s.cx, cy2 or s.cy, cz2 or s.cz
                        local useSx, useSy, useSz = sx2 or s.sx, sy2 or s.sy, sz2 or s.sz
                        self:_DebugCheckProjection(useCx, useCy, useCz, useSx, useSy, useSz, fw, fh, s.pad)
                    end
                end
            end)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(delay, function()
                self._camLogTimer = nil
                if self._lastCamSnapshot then
                    local s = self._lastCamSnapshot
                    self:_DebugLog("camera", "CameraFinalDelayed: pos=(%.2f,%.2f,%.2f) target=(%.2f,%.2f,%.2f) vfov=%.3f hfov=%.3f bounds=(cx=%.2f,cz=%.2f,sx=%.2f,sz=%.2f) dist=%.3f pad=%.2f axis=%s",
                        s.px or 0, s.py or 0, s.pz or 0, s.tx or 0, s.ty or 0, s.tz or 0,
                        s.vfov or 0, s.hfov or 0, s.cx or 0, s.cz or 0, s.sx or 0, s.sz or 0, s.dist or 0, s.pad or 0, tostring(s.axis))
                    local fw, fh = self:GetSize()
                    if self._DebugCheckProjection then
                        -- Use fresh bounds if the actor has rotated since snapshot; fall back to snapshot if unavailable
                        local cx2, cy2, cz2, sx2, sy2, sz2 = _getBounds(backend.actor)
                        local useCx, useCy, useCz = cx2 or s.cx, cy2 or s.cy, cz2 or s.cz
                        local useSx, useSy, useSz = sx2 or s.sx, sy2 or s.sy, sz2 or s.sz
                        self:_DebugCheckProjection(useCx, useCy, useCz, useSx, useSy, useSz, fw, fh, s.pad)
                    end
                end
            end)
        end
    end

    function host:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        if backend.kind ~= "scene" or not backend.frame then return end
        if backend.frame.SetCameraPosition then
            pcall(backend.frame.SetCameraPosition, backend.frame, px, py, pz)
        end
    local fx, fy, fz = _normalize((tx or 0) - (px or 0), (ty or 0) - (py or 0), (tz or 0) - (pz or 0))
    if fx == 0 and fy == 0 and fz == 0 then fx, fy, fz = 0, 1, 0 end
    -- Build a right-handed camera basis:
    --   right = upRef × forward  (choosing right this way keeps a right-handed system)
    --   up    = forward × right
    -- Note: (forward × up) would produce a left-handed basis and can invert face winding.
    local upRefX, upRefY, upRefZ = 0, 0, 1
    if math.abs(fx * upRefX + fy * upRefY + fz * upRefZ) > 0.999 then upRefX, upRefY, upRefZ = 0, 1, 0 end
    -- right = upRef × forward
    local rx, ry, rz = _cross(upRefX, upRefY, upRefZ, fx, fy, fz)
    rx, ry, rz = _normalize(rx, ry, rz)
    -- up = forward × right
    local ux, uy, uz = _cross(fx, fy, fz, rx, ry, rz)
        -- API expects basis in (right, up, forward) order. Prefer CameraController when available.
        do
            local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
            if MS and MS.CameraController and MS.CameraController.setOrientation then
                MS.CameraController.setOrientation(backend.frame, rx, ry, rz, ux, uy, uz, fx, fy, fz)
            elseif backend.frame.SetCameraOrientationByAxisVectors then
                pcall(backend.frame.SetCameraOrientationByAxisVectors, backend.frame, rx, ry, rz, ux, uy, uz, fx, fy, fz)
            elseif backend.frame.SetCameraOrientationByYawPitchRoll then
            local yaw = atan2(fy, fx)
            local pitch = atan2(fz, math.sqrt(fx * fx + fy * fy))
            pcall(backend.frame.SetCameraOrientationByYawPitchRoll, backend.frame, yaw, pitch, 0)
            end
        end
    end

    function host:PointCameraAtHead()
        if backend.kind ~= "scene" or not backend.frame then return end
        local px, py, pz = 0, (host._camDirY or 1) * (host._camDist or 2.5), (host._camBaseZ or 1.0)
        local tx, ty, tz = 0, 0, (host._camBaseZ or 1.0)
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
    end

    -- Centralized near/far clip setters to prevent drift across call sites
    function host:_ApplyClips(d, depthHalf, pad)
        local scene = backend and backend.frame
        if not scene then return end
        d = tonumber(d) or (self._camDist or 2.5)
        depthHalf = tonumber(depthHalf) or 0
        pad = tonumber(pad) or 0
        local nearWanted = math.max(0.05, 0.02 * d)
        local farWanted = math.max(40, d + depthHalf + pad * 2 + 20)
        local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
        if MS and MS.CameraController and MS.CameraController.setNearClip then
            MS.CameraController.setNearClip(scene, nearWanted)
        elseif scene.SetCameraNearClip then
            pcall(scene.SetCameraNearClip, scene, nearWanted)
        end
        if scene.SetCameraFarClip then
            pcall(scene.SetCameraFarClip, scene, farWanted)
        end
    end

    function host:_ApplyClipsFromSnapshot()
        local s = self._lastCamSnapshot
        local scene = backend and backend.frame
        if not (scene and s) then return end
        local d = self._camDist or s.dist or 2.5
        local axisTag = tostring(self._camAxis or "Y+")
        local halfX = (s.sx and s.sx > 0) and (s.sx * 0.5) or 0
        local halfY = (s.sy and s.sy > 0) and (s.sy * 0.5) or 0
        local depthHalf = axisTag:match("^Y") and halfY or halfX
        local pad = tonumber(s.pad) or 0
        return self:_ApplyClips(d, depthHalf, pad)
    end

    local function _getVFOV(scene)
        if scene and scene.GetCameraFieldOfView then
            local ok, f = pcall(scene.GetCameraFieldOfView, scene)
            if ok and type(f) == "number" and f > 0.05 and f < 3.0 then return f end
        end
        return 0.8
    end

    _getBounds = function(actor)
        if not actor then return end
        local minX, minY, minZ, maxX, maxY, maxZ
        local function assign(a, b, c, d, e, f)
            if type(a) == "table" and type(b) == "table" then
                return a.x or 0, a.y or 0, a.z or 0, b.x or 0, b.y or 0, b.z or 0
            end
            if type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" and type(e) == "number" and type(f) == "number" then
                return a, b, c, d, e, f
            end
            return nil
        end
        -- Prefer tighter active bounds first, then fall back to max/model bounds
        if actor.GetActiveBoundingBox then
            local ok, a, b, c, d, e, f = pcall(actor.GetActiveBoundingBox, actor)
            if ok then
                local x1, y1, z1, x2, y2, z2 = assign(a, b, c, d, e, f)
                if x1 then minX, minY, minZ, maxX, maxY, maxZ = x1, y1, z1, x2, y2, z2 end
            end
        end
        if not minX and actor.GetMaxBoundingBox then
            local ok, a, b, c, d, e, f = pcall(actor.GetMaxBoundingBox, actor)
            if ok then
                local x1, y1, z1, x2, y2, z2 = assign(a, b, c, d, e, f)
                if x1 then minX, minY, minZ, maxX, maxY, maxZ = x1, y1, z1, x2, y2, z2 end
            end
        end
        if not minX and actor.GetModelBounds then
            local ok, a, b, c, d, e, f = pcall(actor.GetModelBounds, actor)
            if ok then
                local x1, y1, z1, x2, y2, z2 = assign(a, b, c, d, e, f)
                if x1 then minX, minY, minZ, maxX, maxY, maxZ = x1, y1, z1, x2, y2, z2 end
            end
        end
        if not minX then return end
        local cx, cy, cz = (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5
        local sx, sy, sz = math.abs(maxX - minX), math.abs(maxY - minY), math.abs(maxZ - minZ)
        return cx, cy, cz, sx, sy, sz
    end

    -- Public: return a simple bounds table for debug UI consumers
    function host:GetBounds()
        local cx, cy, cz, sx, sy, sz = _getBounds(backend.actor)
        if not cx then return nil end
        return { center = { x = cx, y = cy, z = cz }, size = { x = sx, y = sy, z = sz }, min = { x = cx - sx * 0.5, y = cy - sy * 0.5, z = cz - sz * 0.5 }, max = { x = cx + sx * 0.5, y = cy + sy * 0.5, z = cz + sz * 0.5 } }
    end

    -- Public: radians vertical FOV and aspect for debug UI
    function host:GetFovV()
        return _getVFOV(backend.frame)
    end
    function host:GetAspect()
        local w, h = self:GetSize(); if not (w and h) or h == 0 then return 1.0 end; return w / h
    end

    -- Public: set/look-at camera target; preserve current camera position when possible
    function host:SetTarget(vec3)
        if backend.kind ~= "scene" or not backend.frame then return end
        vec3 = vec3 or {}
        -- Mark that user is manually controlling camera to prevent auto-refits
        self._userControlledCamera = true
        -- Try to read current camera position
        local okP, px, py, pz = pcall(backend.frame.GetCameraPosition, backend.frame)
        if not okP then
            local s = self._lastCamSnapshot or {}
            px, py, pz = s.px or 0, s.py or (self._camDir or 1) * (self._camDist or 2.5), s.pz or (self._camBaseZ or 1.0)
        end
        local s = self._lastCamSnapshot or {}
        local tx = (vec3.x ~= nil) and vec3.x or s.tx or 0
        local ty = (vec3.y ~= nil) and vec3.y or s.ty or 0
        local tz = (vec3.z ~= nil) and vec3.z or s.tz or (self._camBaseZ or 1.0)
    self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
    self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz })
    end

    local function _horizontalFOV(vfov, aspect)
        local t = math.tan(vfov * 0.5) * math.max(1e-3, aspect or 1)
        return 2 * math.atan(t)
    end

    -- Projection helper via Diagnostics
    local function _projectPoint(scene, x, y, z)
        if Diagnostics and Diagnostics.projectPoint then
            return Diagnostics.projectPoint(scene, x, y, z)
        end
        return false
    end

    -- Guard helper to avoid propagating NaNs or infinities to camera state
    local function _finite(x, fb)
        if type(x) ~= "number" then return fb end
        if x ~= x or x == 1/0 or x == -1/0 then return fb end
        return x
    end

    -- Set actor yaw to face the camera based on axis/sign placement
    local function _applyActorFacing(axis, sign)
        -- Set an absolute facing based on axis/sign; do not accumulate across calls.
        -- If auto-facing is disabled, do nothing here and let user-controlled yaw persist.
        if host and host._autoFaceCamera == false then return end
        if not (backend.actor and backend.actor.SetYaw) then return end
        local yaw
        if axis == "Y" then
            -- Camera along ±Y: yaw is measured from +X; +Y => +pi/2, -Y => -pi/2
            yaw = (sign and sign > 0) and (math.pi * 0.5) or (-math.pi * 0.5)
        else
            -- Camera along ±X: +X => 0, -X => pi
            yaw = (sign and sign > 0) and 0 or math.pi
        end
        pcall(backend.actor.SetYaw, backend.actor, yaw)
        host._frontYaw = yaw
    host._yawFromSolver = true
        host:_DebugLog("camera", "_applyActorFacing: axis=%s sign=%d yaw=%.3f (absolute)",
            axis or "?", sign or 0, yaw or 0)
    end

    function host:_DebugCheckProjection(cx, cy, cz, sx, sy, sz, frameW, frameH, pad)
        if backend.kind ~= "scene" or not backend.frame then return end
        if Diagnostics and Diagnostics.debugProjection then
            return Diagnostics.debugProjection(self, backend.frame, cx, cy, cz, sx, sy, sz, frameW, frameH, pad)
        end
    end

    -- Projector-based centering helpers
    function host:_CenterHorizontally(minPX, maxPX, frameW, axis, sign, px, py, pz, tx, ty, tz, hfFix, dFix, cx, cy)
        if minPX == 1/0 or maxPX == -1/0 then return tx, ty end
        local midPixX = 0.5 * ((minPX or 0) + (maxPX or 0))
        local desiredX = (frameW or 0) * 0.5
        local dx_pixel = desiredX - midPixX
        if math.abs(dx_pixel) <= 2 then return tx, ty end
        local halfViewHFix = dFix * math.tan(hfFix * 0.5)
        local dx_world = dx_pixel * (2 * halfViewHFix / math.max(1, frameW or 1))
        if axis == "Y" then
            tx = _finite((tx or 0) + dx_world, cx)
        else
            ty = _finite((ty or 0) + dx_world, (cy or 0))
        end
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        _applyActorFacing(axis, sign)
        self._lastCamSnapshot = self._lastCamSnapshot or {}
        self._lastCamSnapshot.tx = tx
        self._lastCamSnapshot.ty = ty
        self:_DebugLog("framing", "centerH: midX=%.1f dx_px=%.1f dx_w=%.3f -> tx=%.2f ty=%.2f",
            midPixX or -1, dx_pixel or 0, dx_world or 0, tx or 0, ty or 0)
        return tx, ty
    end

    function host:_CenterVertically(minPY, maxPY, frameH, px, py, pz, tx, ty, tz, vfFix, dFix, cz, halfZ, compBias, coverageFn)
        if minPY == 1/0 or maxPY == -1/0 then return tz end
        local halfViewFix = dFix * math.tan(vfFix * 0.5)
        local midPix = 0.5 * ((minPY or 0) + (maxPY or 0))
        local desired = (frameH or 0) * 0.5
        local dz_world = (desired - midPix) * (2 * halfViewFix / math.max(1, frameH or 1))
        tz = _finite((tz or cz) - dz_world, cz)
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        self._lastCamSnapshot = self._lastCamSnapshot or {}
        self._lastCamSnapshot.tz = tz
        self._lastCamSnapshot.pz = pz
        self:_DebugLog("framing", "center: mid=%.1f dz=%.2f -> tz=%.2f (dFix=%.3f halfView=%.3f)", midPix or -1, (desired - midPix) * (2 * halfViewFix / math.max(1, frameH or 1)) or 0, tz, dFix or -1, halfViewFix or -1)

        -- Micro-pass with fresh coverage
        if type(coverageFn) == "function" then
            local minPX2, minPY2, maxPX2, maxPY2 = coverageFn()
            if minPY2 ~= 1/0 and maxPY2 ~= -1/0 then
                local midPix2 = 0.5 * ((minPY2 or 0) + (maxPY2 or 0))
                local dz2 = ((frameH or 0) * 0.5 - midPix2) * (2 * halfViewFix / math.max(1, frameH or 1))
                if math.abs(dz2) > 0.05 then
                    tz = _finite(tz - dz2, cz)
                    self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                    self._lastCamSnapshot.tz = tz
                    self._lastCamSnapshot.pz = pz
                    self:_DebugLog("framing", "center micro: dz2=%.3f -> tz=%.2f", dz2, tz)
                end
            end
        end

        -- Re-apply headroom to maintain composition bias
        local slackNow = math.max(0, halfViewFix - (halfZ or 0))
        local headroom = (compBias or 0) * slackNow
        if headroom and headroom > 1e-4 then
            local tz_hr = _finite(tz - headroom, cz)
            if math.abs(tz_hr - tz) > 1e-4 then
                tz = tz_hr
                self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                self._lastCamSnapshot.tz = tz
                self._lastCamSnapshot.pz = pz
                self:_DebugLog("framing", "headroom: slack=%.3f compBias=%.3f shift=%.3f -> tz=%.2f", slackNow, compBias or 0, headroom, tz)
            end
        end
        return tz
    end

    -- FOV helpers and memoization (per aspect bucket)
    function host:_GetRawFOV()
        local scene = backend and backend.frame
        if scene and scene.GetCameraFieldOfView then
            local ok, f = pcall(scene.GetCameraFieldOfView, scene)
            if ok and type(f) == "number" and f > 0.05 and f < 3.0 then return f end
        end
        return 0.8
    end

    function host:_FovMemoKey(aspect)
        local bucket = math.floor(math.max(0.01, aspect or 1) * 20 + 0.5) / 20 -- ~0.05 aspect buckets
        return string.format("a%.2f", bucket)
    end

    function host:_GetFovAssumption(aspect)
        self._fovMemo = self._fovMemo or {}
        local k = self:_FovMemoKey(aspect)
        local v = self._fovMemo[k]
        if v == nil then return false end -- default assume vertical-FOV
        return v and true or false
    end

    function host:_MemoizeFov(aspect, assumeHorizontal)
        self._fovMemo = self._fovMemo or {}
        local k = self:_FovMemoKey(aspect)
        self._fovMemo[k] = assumeHorizontal and true or false
    end

    function host:_FOVPairFromF(F, assumeHorizontal, aspect)
        local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
        local asp = tonumber(aspect) or self:GetAspect()
        if MS and MS.Framing and MS.Framing.FOVPair_FromF then
            local vf0, hf0 = MS.Framing.FOVPair_FromF(F, assumeHorizontal)
            if assumeHorizontal then
                local hf = _finite(hf0, 0.8)
                local vf = 2 * math.atan(math.tan(hf * 0.5) / math.max(1e-3, asp))
                self:_DebugLog("framing", string.format("[FOV] vfov=%.6f rad (%.2f°) hfov=%.6f rad (%.2f°) aspect=%.6f", vf or -1, math.deg(vf or 0), hf or -1, math.deg(hf or 0), asp or -1))
                return _finite(vf, 0.8), _finite(hf, 0.8)
            else
                local vf = _finite(vf0, 0.8)
                local hf = 2 * math.atan(math.tan(vf * 0.5) * math.max(1e-3, asp))
                self:_DebugLog("framing", string.format("[FOV] vfov=%.6f rad (%.2f°) hfov=%.6f rad (%.2f°) aspect=%.6f", vf or -1, math.deg(vf or 0), hf or -1, math.deg(hf or 0), asp or -1))
                return _finite(vf, 0.8), _finite(hf, 0.8)
            end
        end
        -- Fallback: local math using current aspect
        if assumeHorizontal then
            local hf = _finite(F, 0.8)
            local vf = 2 * math.atan(math.tan(hf * 0.5) / math.max(1e-3, asp))
            self:_DebugLog("framing", string.format("[FOV] vfov=%.6f rad (%.2f°) hfov=%.6f rad (%.2f°) aspect=%.6f", vf or -1, math.deg(vf or 0), hf or -1, math.deg(hf or 0), asp or -1))
            return _finite(vf, 0.8), _finite(hf, 0.8)
        else
            local vf = _finite(F, 0.8)
            local hf = 2 * math.atan(math.tan(vf * 0.5) * math.max(1e-3, asp))
            self:_DebugLog("framing", string.format("[FOV] vfov=%.6f rad (%.2f°) hfov=%.6f rad (%.2f°) aspect=%.6f", vf or -1, math.deg(vf or 0), hf or -1, math.deg(hf or 0), asp or -1))
            return _finite(vf, 0.8), _finite(hf, 0.8)
        end
    end

    -- Return inside coverage count for the current camera, using a simple AABB corner sampling
    local function _computeInsideCount(cx, cy, cz, sx, sy, sz, frameW, frameH)
        if backend.kind ~= "scene" or not backend.frame then return 0, 0 end
        if Diagnostics and Diagnostics.computeInsideCount then
            return Diagnostics.computeInsideCount(backend.frame, cx, cy, cz, sx, sy, sz, frameW, frameH)
        end
        return 0, 0
    end

    function host:FlipFacing()
        self._frontYaw = (self._frontYaw or 0) + math.pi
        if backend.kind == "scene" and backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, self._frontYaw)
        end
    end

    function host:FaceCamera()
        -- Skip if auto-facing is disabled
        if self._autoFaceCamera == false then return end
    self:_DebugLog("framing", string.format("[Trigger] FaceCamera (autoFace=%s userControlled=%s)", tostring(self._autoFaceCamera ~= false), tostring(self._userControlledCamera or false)))
        
        -- Calculate yaw to face current camera position
        if not (backend.frame and backend.actor) then return end
        
        -- Get camera position and actor position
        local camX, camY, camZ = 0, 0, 0
        if backend.frame.GetCameraPosition then
            local ok, x, y, z = pcall(backend.frame.GetCameraPosition, backend.frame)
            if ok and type(x) == "number" and type(y) == "number" then
                camX, camY = x, y
            end
        end
        
        local actorX, actorY = 0, 0
        if backend.actor.GetPosition then
            local ok, x, y, z = pcall(backend.actor.GetPosition, backend.actor)
            if ok and type(x) == "number" and type(y) == "number" then
                actorX, actorY = x, y
            end
        end
        
        -- Calculate direction vector from actor to camera
        local dx, dy = camX - actorX, camY - actorY
        local length = math.sqrt(dx * dx + dy * dy)
        
        if length > 1e-6 then  -- Avoid division by zero
            -- Calculate yaw angle to face camera (atan2 gives angle from +X axis)
            local targetYaw = atan2(dy, dx)
            self:SetActorYaw(targetYaw)
            self:_DebugLog("camera", "FaceCamera: cam=(%.2f,%.2f) actor=(%.2f,%.2f) yaw=%.3f", 
                camX, camY, actorX, actorY, targetYaw)
        else
            -- Fallback: use current camera axis for facing
            local axis = self._camAxis or "Y+"
            local yaw = 0
            if axis:match("Y%-") then yaw = math.pi
            elseif axis:match("X%+") then yaw = -math.pi * 0.5
            elseif axis:match("X%-") then yaw = math.pi * 0.5
            end
            self:SetActorYaw(yaw)
            self:_DebugLog("camera", "FaceCamera fallback: axis=%s yaw=%.3f", axis, yaw)
        end
    end

    function host:FrameFullBodyFront_ClosedForm(paddingFrac)
        if backend.kind ~= "scene" or not (backend.frame and backend.actor) then return end
        local pad = tonumber(paddingFrac) or 0.10
        
        -- Clear user control flag when explicitly refitting
        self._userControlledCamera = false
    -- [Trigger]
    self:_DebugLog("framing", string.format("[Trigger] FrameFullBodyFront_ClosedForm (autoFace=%s userControlled=%s)", tostring(self._autoFaceCamera ~= false), tostring(self._userControlledCamera or false)))

        -- Frame size & aspect
        local w, h = self:GetSize()
        if not (w and h and w > 0 and h > 0) then w, h = 300, 150 end
        local aspect = w / h
        do
            -- [Size] frame + UI scale snapshot
            local sF = self.GetEffectiveScale and self:GetEffectiveScale() or 1
            local sU = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            self:_DebugLog("framing", string.format("[Size] frame=%.1fx%.1f aspect=%.6f scale(frame)=%.4f scale(UI)=%.4f", w, h, aspect, tonumber(sF) or 1, tonumber(sU) or 1))
        end

        -- Track aspect changes; FOV convention is memoized per-aspect bucket so no global clear needed
        if self._lastAspect and aspect and math.abs(self._lastAspect - aspect) / math.max(1e-6, aspect) > 0.1 then
            self:_DebugLog("framing", "aspect changed %.3f -> %.3f; using per-aspect FOV memo", self._lastAspect or -1, aspect or -1)
        end
        self._lastAspect = aspect

    -- Helpers

    local function solveAxis(axis, vfov, hfov, halfX, halfY, halfZ)
            local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
            if MS and MS.Framing and MS.Framing.solveAxis then
                -- The module version doesn’t know pad; emulate existing pad-inflation here
                local wHalf, hHalf, depthHalf
                if axis == "Y" then
                    wHalf     = halfX * (1 + pad)
                    hHalf     = halfZ * (1 + pad)
                    depthHalf = halfY
                else
                    wHalf     = halfY * (1 + pad)
                    hHalf     = halfZ * (1 + pad)
                    depthHalf = halfX
                end
        self:_DebugLog("framing", string.format("[Fit/%s] pad=%.4f wHalf=%.4f hHalf=%.4f depthHalf=%.4f vfov=%.5f hfov=%.5f", tostring(axis), pad, wHalf, hHalf, depthHalf, vfov or -1, hfov or -1))
                local dV = hHalf / math.max(1e-4, math.tan(vfov * 0.5))
                local dH = wHalf / math.max(1e-4, math.tan(hfov * 0.5))
                local dRect = math.max(dV, dH)
                local nearWanted = math.max(0.05, 0.02 * dRect)
                local safety = 0.25
                local d = math.max(dRect, depthHalf + nearWanted + safety)
        self:_DebugLog("framing", string.format("[Fit/%s] dV=%.6f dH=%.6f usedRect=%.6f depthHalf=%.6f nearWanted=%.6f safety=%.3f finalD=%.6f", tostring(axis), dV, dH, dRect, depthHalf, nearWanted, safety, d))
                return d, dV, dH, depthHalf
            end
            -- Fallback: existing logic
            local wHalf, hHalf, depthHalf
            if axis == "Y" then
                wHalf     = halfX * (1 + pad)
                hHalf     = halfZ * (1 + pad)
                depthHalf = halfY
            else
                wHalf     = halfY * (1 + pad)
                hHalf     = halfZ * (1 + pad)
                depthHalf = halfX
            end
        self:_DebugLog("framing", string.format("[Fit/%s] pad=%.4f wHalf=%.4f hHalf=%.4f depthHalf=%.4f vfov=%.5f hfov=%.5f", tostring(axis), pad, wHalf, hHalf, depthHalf, vfov or -1, hfov or -1))
            local dV = hHalf / math.max(1e-4, math.tan(vfov * 0.5))
            local dH = wHalf / math.max(1e-4, math.tan(hfov * 0.5))
            local dRect = math.max(dV, dH)
            local nearWanted = math.max(0.05, 0.02 * dRect)
            local safety = 0.25
            local d = math.max(dRect, depthHalf + nearWanted + safety)
        self:_DebugLog("framing", string.format("[Fit/%s] dV=%.6f dH=%.6f usedRect=%.6f depthHalf=%.6f nearWanted=%.6f safety=%.3f finalD=%.6f", tostring(axis), dV, dH, dRect, depthHalf, nearWanted, safety, d))
            return d, dV, dH, depthHalf
        end

        -- Bounds
        local cx, cy, cz, sx, sy, sz = _getBounds(backend.actor)
        if not cx then
            -- Safe fallback aim (no NaNs)
            local distY = _finite(self._camDist or 2.5, 2.5)
            self:_ApplyCameraLookAt(0, (self._camDir and self._camDir < 0) and -distY or distY, _finite(self._camBaseZ or 1.0, 1.0), 0, 0, _finite(self._camBaseZ or 1.0, 1.0))
            self:_ApplyClips(distY, 0, pad)
            self._lastCamSnapshot = { px=0, py=distY, pz=(self._camBaseZ or 1.0), tx=0, ty=0, tz=(self._camBaseZ or 1.0), vfov=0, hfov=0, cx=0, cz=(self._camBaseZ or 1.0), sx=0, sz=0, dist=distY, pad=pad, axis="Y+", sessionId=self._sessionId }
            self:_ScheduleCameraSnapshotLog(1.0)
            return
        end

        -- Half extents (guarded)
        local halfX = (sx and sx > 0) and (sx * 0.5) or 1
        local halfY = (sy and sy > 0) and (sy * 0.5) or 0
        local halfZ = (sz and sz > 0) and (sz * 0.5) or 1

        self:_DebugLog("framing", "bounds: c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f) half=(%.2f,%.2f,%.2f)", cx or 0, cy or 0, cz or 0, sx or 0, sy or 0, sz or 0, halfX, halfY, halfZ)
        do
            local minX, minY, minZ = (cx or 0) - halfX, (cy or 0) - halfY, (cz or 0) - halfZ
            local maxX, maxY, maxZ = (cx or 0) + halfX, (cy or 0) + halfY, (cz or 0) + halfZ
            self:_DebugLog("framing", string.format("[Bounds] min=(%.4f,%.4f,%.4f) max=(%.4f,%.4f,%.4f) half=(x=%.4f,y=%.4f,z=%.4f) center=(%.4f,%.4f,%.4f)", minX, minY, minZ, maxX, maxY, maxZ, halfX, halfY, halfZ, cx or 0, cy or 0, cz or 0))
        end

        -- Read ambiguous FOV and create both interpretations
    local returnedF = self:_GetRawFOV()
    -- Per-aspect-bucket FOV convention memoization
    local bucketKey = self:_FovMemoKey(aspect)
    local defaultAssumeHorizontal = self:_GetFovAssumption(aspect)
    local vf_assumed, hf_assumed = self:_FOVPairFromF(returnedF, defaultAssumeHorizontal, aspect)
        self:_DebugLog("framing", "fov: raw=%.3f assumeH=%s -> vfov=%.3f hfov=%.3f", returnedF or -1, tostring(defaultAssumeHorizontal), vf_assumed or -1, hf_assumed or -1)

        -- Closed-form: try both axes, pick smaller d
        local dY, dV_Y, dH_Y, depthHalfY = solveAxis("Y", vf_assumed, hf_assumed, halfX, halfY, halfZ)
        local dX, dV_X, dH_X, depthHalfX = solveAxis("X", vf_assumed, hf_assumed, halfX, halfY, halfZ)
        local axis, d, dV_sel, dH_sel, depthHalf =
            (dY <= dX) and "Y" or "X",
            (dY <= dX) and dY  or dX,
            (dY <= dX) and dV_Y or dV_X,
            (dY <= dX) and dH_Y or dH_X,
            (dY <= dX) and depthHalfY or depthHalfX

        d = _finite(d, self._camDist or 2.5)

        self:_DebugLog("framing", "fit: axis=%s dV=%.3f dH=%.3f d=%.3f halfX=%.2f halfY=%.2f halfZ=%.2f aspect=%.3f",
            axis, dV_sel, dH_sel, d, halfX, halfY, halfZ, aspect)

        -- Initial target with composition bias
        -- Positive compBias adds headroom by moving the content down (increase tz)
        local compBias = (self._compBias ~= nil) and self._compBias or 0.25
        local halfView = d * math.tan(vf_assumed * 0.5)
        local extra    = math.max(0, halfView - halfZ)
        local tz       = _finite(cz + compBias * extra, cz)
        local tx, ty   = _finite(cx, cx), _finite(cy, 0)

        self:_DebugLog("framing", "aim0: cy=%.3f cz=%.3f halfView=%.3f halfZ=%.3f extra=%.3f compBias=%.3f tz=%.3f",
            cy or 0, cz, halfView, halfZ, extra, compBias, tz)

        -- Place camera along chosen axis with sign from self._camDir
        -- Choose side based on per-axis preference
        local sign = (axis == "Y")
            and (((self._camDirY and self._camDirY < 0) and -1) or 1)
            or (((self._camDirX and self._camDirX < 0) and -1) or 1)
        local px, py, yaw
        if axis == "Y" then
            px, py, yaw = cx, (cy or 0) + sign * d, (sign > 0) and 0 or math.pi
        else
            px, py, yaw = cx + sign * d, (cy or 0), (sign > 0) and (-math.pi * 0.5) or (math.pi * 0.5)
        end
        self:_DebugLog("framing", "place0: axis=%s sign=%d pos=(%.2f,%.2f,%.2f) target=(%.2f,%.2f,%.2f) yaw=%.2f", axis, sign, px or 0, py or 0, tz or 0, tx or 0, ty or 0, tz or 0, yaw or 0)

        -- Sanitize everything before apply
        px = _finite(px, cx);  py = _finite(py, (cy or 0))
        local pz = _finite(tz, cz)
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        _applyActorFacing(axis, sign)

    self:_ApplyClips(d, depthHalf, pad)

        -- [Cam] placement + clip planes
        do
            local upX, upY, upZ = 0, 0, 1
            local camX, camY, camZ = px or 0, py or 0, pz or 0
            local tgtX, tgtY, tgtZ = tx or 0, ty or 0, tz or 0
            self:_DebugLog("camera", string.format("[Cam] pos=(%.4f,%.4f,%.4f) tgt=(%.4f,%.4f,%.4f) up=(%.4f,%.4f,%.4f) vfov=%.5f hfov=%.5f aspect=%.6f", camX, camY, camZ, tgtX, tgtY, tgtZ, upX, upY, upZ, vf_assumed or -1, hf_assumed or -1, aspect or -1))
            local nearV, farV
            if backend.frame and backend.frame.GetCameraNearClip then local ok, v = pcall(backend.frame.GetCameraNearClip, backend.frame); if ok then nearV = v end end
            if backend.frame and backend.frame.GetCameraFarClip then local ok, v = pcall(backend.frame.GetCameraFarClip, backend.frame); if ok then farV = v end end
            self:_DebugLog("camera", string.format("[Cam] near=%.5f far=%.5f d=%.6f", tonumber(nearV) or -1, tonumber(farV) or -1, d or -1))
        end

    self._camAxis  = axis .. ((sign > 0) and "+" or "-")
    self._camDist  = d
    self._camBaseZ = cz
    if axis == "Y" then self._camDirY = sign else self._camDirX = sign end
        self._lastCamSnapshot = {
            px=px, py=py, pz=pz, tx=tx, ty=ty, tz=tz,
            vfov=_finite(vf_assumed, 0.8), hfov=_finite(hf_assumed, 0.8),
            cx=cx, cy=cy, cz=cz, sx=sx, sy=sy, sz=sz, dist=d, pad=pad, axis=self._camAxis, sessionId=self._sessionId
        }

        -- Probe projector coverage (without relying on it if it's not ready)
        local inside, total, minPX, minPY, maxPX, maxPY = _coverageStats(cx, cy, cz, sx, sy, sz, w, h)
        local projectorReady = (minPX ~= 1/0 and minPY ~= 1/0 and maxPX ~= -1/0 and maxPY ~= -1/0)

        if projectorReady then
            self:_DebugLog("framing", "bbox: min=(%.1f,%.1f) max=(%.1f,%.1f) frame=(%d,%d) inside=%d/%d",
                minPX, minPY, maxPX, maxPY, w, h, inside or 0, total or 0)
        else
            -- Optional first-paint cushion when projector is nil (keep it in the closed-form stage)
            local dCush = _finite(d * 1.03, d)
            if dCush ~= d then
                d = dCush
                local halfView2 = d * math.tan(vf_assumed * 0.5)
                local slack2    = math.max(0, halfView2 - halfZ)
                tz = _finite(cz + compBias * slack2, cz)
                if axis == "Y" then px, py = cx, (cy or 0) + sign * d else px, py = cx + sign * d, (cy or 0) end
                px=_finite(px,cx); py=_finite(py,(cy or 0)); pz=_finite(tz,cz)
                self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                _applyActorFacing(axis, sign)
                self:_ApplyClips(d, depthHalf, pad)
                self._camDist = d
                self._lastCamSnapshot.dist = d
                self._lastCamSnapshot.px, self._lastCamSnapshot.py, self._lastCamSnapshot.pz = px, py, pz
                self._lastCamSnapshot.tz = tz
            end
            self:_DebugLog("projection", "proj: not ready; deferring correction pass (A/B/C)")
        end

    -- If projector is ready, do exactly one correction pass (A/B/C)
        if projectorReady and total and total > 0 then
            -- (A) FOV convention correction, one shot
            if inside and inside < total then
                -- Save pre-swap state to allow revert if swap is worse
                local insideBefore = inside or 0
                local prev_vf, prev_hf = vf_assumed, hf_assumed
                local prev_axis, prev_d, prev_depthHalf = axis, d, depthHalf
                local prev_px, prev_py, prev_pz = px, py, pz
                local prev_tx, prev_ty, prev_tz = tx, ty, tz
                local prev_camAxis = self._camAxis
                local triedHorizontal = defaultAssumeHorizontal
                local vf2, hf2 = self:_FOVPairFromF(returnedF, not triedHorizontal, aspect) -- swap convention
                self:_DebugLog("framing", "FOV correction: swapping %s-FOV ↔ %s-FOV and re-solving (inside=%d/%d).",
                    triedHorizontal and "H" or "V", triedHorizontal and "V" or "H", inside or -1, total or -1)

                -- Re-solve and place again using the swapped pair
                dY, dV_Y, dH_Y, depthHalfY = solveAxis("Y", vf2, hf2, halfX, halfY, halfZ)
                dX, dV_X, dH_X, depthHalfX = solveAxis("X", vf2, hf2, halfX, halfY, halfZ)
                axis, d, dV_sel, dH_sel, depthHalf =
                    (dY <= dX) and "Y" or "X",
                    (dY <= dX) and dY  or dX,
                    (dY <= dX) and dV_Y or dV_X,
                    (dY <= dX) and dH_Y or dH_X,
                    (dY <= dX) and depthHalfY or depthHalfX
                d = _finite(d, self._camDist or 2.5)

                -- Recompute camera side sign for new axis after FOV swap
                if axis == "Y" then
                    sign = (self._camDirY and self._camDirY < 0) and -1 or 1
                else
                    sign = (self._camDirX and self._camDirX < 0) and -1 or 1
                end

                -- Aim again (bias kept)
                halfView = d * math.tan(vf2 * 0.5)
                extra    = math.max(0, halfView - halfZ)
                tz       = _finite(cz + compBias * extra, cz)
                if axis == "Y" then px, py, yaw = cx, (cy or 0) + sign * d, (sign > 0) and 0 or math.pi
                else px, py, yaw = cx + sign * d, (cy or 0), (sign > 0) and (-math.pi * 0.5) or (math.pi * 0.5) end
                px=_finite(px,cx); py=_finite(py,(cy or 0)); pz=_finite(tz,cz)
                self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                _applyActorFacing(axis, sign)
                self:_ApplyClips(d, depthHalf, pad)

                -- Snapshot + recompute coverage
                self._camAxis  = axis .. ((sign > 0) and "+" or "-")
                self._camDist  = d
                self._camBaseZ = cz
                if axis == "Y" then self._camDirY = sign else self._camDirX = sign end
                self._lastCamSnapshot = {
                    px=px, py=py, pz=pz, tx=tx, ty=ty, tz=tz,
                    vfov=_finite(vf2, 0.8), hfov=_finite(hf2, 0.8),
                    cx=cx, cy=cy, cz=cz, sx=sx, sy=sy, sz=sz, dist=d, pad=pad, axis=self._camAxis, sessionId=self._sessionId
                }
                inside, total, minPX, minPY, maxPX, maxPY = _coverageStats(cx, cy, cz, sx, sy, sz, w, h)
                self:_DebugLog("framing", "FOV post: bbox min=(%.1f,%.1f) max=(%.1f,%.1f) inside=%d/%d",
                    minPX or -1, minPY or -1, maxPX or -1, maxPY or -1, inside or -1, total or -1)

                -- Memoize convention per aspect bucket only if projector confirms full fit
                if (minPX ~= 1/0 and maxPX ~= -1/0) and inside == total then
                    self:_MemoizeFov(aspect, (not triedHorizontal)) -- we swapped and it worked
                else
                    -- If coverage got worse after swap, revert to previous placement and FOVs
                    if (inside or 0) < insideBefore then
                        self:_DebugLog("framing", "FOV swap worsened coverage (%d->%d); reverting to previous FOV/placement.", insideBefore or -1, inside or -1)
                        vf_assumed, hf_assumed = prev_vf, prev_hf
                        axis, d, depthHalf = prev_axis, prev_d, prev_depthHalf
                        px, py, pz, tx, ty, tz = prev_px, prev_py, prev_pz, prev_tx, prev_ty, prev_tz
                        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                        _applyActorFacing(axis, sign)
                        self._camAxis = prev_camAxis
                        if self._lastCamSnapshot then
                            self._lastCamSnapshot.px, self._lastCamSnapshot.py, self._lastCamSnapshot.pz = px, py, pz
                            self._lastCamSnapshot.tx, self._lastCamSnapshot.ty, self._lastCamSnapshot.tz = tx, ty, tz
                            self._lastCamSnapshot.vfov, self._lastCamSnapshot.hfov = _finite(vf_assumed, 0.8), _finite(hf_assumed, 0.8)
                            self._lastCamSnapshot.dist = d
                            self._lastCamSnapshot.axis = self._camAxis
                        end
                        inside = insideBefore
                    end
                end
            else
                -- If the first assumption already produced a full fit, memoize it
                if inside == total then
                    self:_MemoizeFov(aspect, defaultAssumeHorizontal)
                end
            end

            -- (B) One-shot distance scale if bbox overfills
            if (minPX ~= 1/0 and minPY ~= 1/0 and maxPX ~= -1/0 and maxPY ~= -1/0) then
                local curW = math.max(1, (maxPX or 0) - (minPX or 0))
                local curH = math.max(1, (maxPY or 0) - (minPY or 0))
                local scale = math.max(curW / math.max(1, w), curH / math.max(1, h), 1.0)
                if scale > 1.001 then
                    local d2 = _finite(self._camDist or d, d) * scale
                    self:_DebugLog("framing", "scale: overfill=%.3f -> factor=%.3f d:%.3f->%.3f", math.max(curW / math.max(1, w), curH / math.max(1, h)), scale, self._camDist or d, d2)
                    local vfFix = _finite(self._lastCamSnapshot and self._lastCamSnapshot.vfov or vf_assumed, vf_assumed)
                    local halfView2 = d2 * math.tan(vfFix * 0.5)
                    local slack2 = math.max(0, halfView2 - halfZ)
                    tz = _finite(cz + compBias * slack2, cz)
                    -- keep axis & sign
                    if axis == "Y" then px, py = cx, (cy or 0) + sign * d2 else px, py = cx + sign * d2, (cy or 0) end
                    px=_finite(px,cx); py=_finite(py,(cy or 0)); pz=_finite(tz,cz)
                    self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                    _applyActorFacing(axis, sign)
                    self:_ApplyClips(d2, depthHalf, pad)
                    self._camDist = d2
                    self._lastCamSnapshot.dist = d2
                    self._lastCamSnapshot.px, self._lastCamSnapshot.py, self._lastCamSnapshot.pz = px, py, pz
                    self._lastCamSnapshot.tz = tz
                    -- refresh coverage
                    inside, total, minPX, minPY, maxPX, maxPY = _coverageStats(cx, cy, cz, sx, sy, sz, w, h)
                    self:_DebugLog("framing", "bbox: min=(%.1f,%.1f) max=(%.1f,%.1f) frame=(%d,%d) inside=%d/%d",
                        minPX, minPY, maxPX, maxPY, w, h, inside or 0, total or 0)
                end

                -- (B2) One-shot horizontal centering using projector
                if (minPX ~= 1/0 and maxPX ~= -1/0) then
                    local s = self._lastCamSnapshot
                    local hfFix = _finite((s and s.hfov) or hf_assumed, hf_assumed)
                    local dFix = (axis == "Y") and math.abs((py or 0) - (ty or 0)) or math.abs((px or 0) - (tx or 0))
                    dFix = _finite(dFix, self._camDist or d)
                    tx, ty = self:_CenterHorizontally(minPX, maxPX, w, axis, sign, px, py, pz, tx, ty, tz, hfFix, dFix, cx, cy)
                    -- refresh coverage
                    inside, total, minPX, minPY, maxPX, maxPY = _coverageStats(cx, cy, cz, sx, sy, sz, w, h)
                end

                -- (C) One-shot vertical centering (exact), then reapply headroom
                local s = self._lastCamSnapshot
                local dFix = (axis == "Y") and math.abs((py or 0) - (ty or 0)) or math.abs((px or 0) - (tx or 0))
                dFix = _finite(dFix, self._camDist or d)
                local vfFix = _finite((s and s.vfov) or vf_assumed, vf_assumed)
                tz = self:_CenterVertically(minPY, maxPY, h, px, py, pz, tx, ty, (s and s.tz) or cz, vfFix, dFix, cz, halfZ, (self._compBias ~= nil and self._compBias or 0.25), function()
                    local _in2, _tot2, _minPX2, _minPY2, _maxPX2, _maxPY2 = _coverageStats(cx, cy, cz, sx, sy, sz, w, h)
                    return _minPX2, _minPY2, _maxPX2, _maxPY2
                end)
                -- Final coverage check after centering for debugging
                local finIn, finTot, finMinX, finMinY, finMaxX, finMaxY = _coverageStats(cx, cy, cz, sx, sy, sz, w, h)
                self:_DebugLog("framing", "center bbox: min=(%.1f,%.1f) max=(%.1f,%.1f) inside=%d/%d",
                    finMinX or -1, finMinY or -1, finMaxX or -1, finMaxY or -1, finIn or -1, finTot or -1)
            end
        end

        -- Optional dev diagnostics (delayed)
    local U = CLN and CLN.Utils
    if U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug(CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.projection or "projection") then
            local fw, fh = self:GetSize()
            self:_DebugCheckProjection(cx, cy, cz, sx, sy, sz, fw, fh, pad)
        end
        self:_ScheduleCameraSnapshotLog(1.0)
    end

    function host:FrameFullBodyFront(paddingFrac)
    -- Route through the debounced coordinator; explicit calls force an auto-frame
    self:_DebugLog("framing", string.format("[Trigger] FrameFullBodyFront (autoFace=%s userControlled=%s)", tostring(self._autoFaceCamera ~= false), tostring(self._userControlledCamera or false)))
    return self:_RequestAutoFrame(paddingFrac, { force = true, reason = "explicit" })
    end

    function host:ClearModel()
        if backend.actor and backend.actor.ClearModel then pcall(backend.actor.ClearModel, backend.actor) end
    end

    function host:SetDisplayInfo(displayID)
    local Loader = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
        local a = backend.actor
        if a and a.SetModelByCreatureDisplayID then
            -- Stamp a new session id for this model/display
            self._displayID = displayID
            local t = (type(GetTime) == "function") and GetTime() or 0
            self._sessionId = tostring(displayID or "") .. ":" .. tostring(math.floor(t * 1000))
            self:_BumpModelVersion()
            -- Cancel any previous loader session ticker
            if self._lastLoadSession and self._lastLoadSession.cancel then pcall(self._lastLoadSession.cancel) end
            -- Delegate loading through Loader for consistent policy and capture session metrics
            if Loader and Loader.loadByDisplayID then
                local session = Loader.loadByDisplayID(a, displayID, { intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true })
                self._lastLoadSession = session
                if self._lastLoadSession then
                    self._lastLoadSession.kind = "displayID"
                    self._lastLoadSession.arg = displayID
                end
            else
                -- Fallback to in-file path if module missing
                self:_PrepareActorForModelLoad(a)
                local ok = pcall(a.SetModelByCreatureDisplayID, a, displayID, false)
                if not ok then pcall(a.SetModelByCreatureDisplayID, a, displayID) end
                self:_StabilizeModelTextures(a)
                self._lastLoadSession = nil
            end
            -- Schedule an auto-frame; will coalesce with load callbacks
            self:_RequestAutoFrame(0.12, { reason = "setDisplay" })
            -- Monitor load; if it takes too long, retry once with same flags
            -- Keep lightweight local ticker solely for logging and camera refit
            do
                local tries = 0
                local function tick()
                    tries = tries + 1
                    local loaded = false
                    if a and a.IsLoaded then
                        local okL, l = pcall(a.IsLoaded, a)
                        loaded = okL and l or false
                    end
                    if loaded then
                        if self._LogLoadedModelAsset then self:_LogLoadedModelAsset("displayID:" .. tostring(displayID)) end
                        return true
                    end
                    if tries > 60 then return true end
                    return false
                end
                if C_Timer and C_Timer.NewTicker then
                    local ticker
                    ticker = C_Timer.NewTicker(0.05, function()
                        if tick() and ticker and ticker.Cancel then ticker:Cancel() end
                    end)
                elseif C_Timer and C_Timer.After then
                    local function loop()
                        if not tick() then C_Timer.After(0.05, loop) end
                    end
                    C_Timer.After(0.05, loop)
                end
            end
            if self.OnModelLoadedOnce then
                self:OnModelLoadedOnce(function(h)
                    if h and h._LogLoadedModelAsset then h:_LogLoadedModelAsset("displayID:" .. tostring(displayID)) end
                    -- Reassert no-desaturation after load and reapply stabilization (blend op, etc.)
                    local a2 = h and h._backend and h._backend.actor
                    if a2 and a2.SetDesaturated then pcall(a2.SetDesaturated, a2, false) end
                    if h and h._StabilizeModelTextures and a2 then h:_StabilizeModelTextures(a2) end
                    if h and h._RequestAutoFrame then h:_RequestAutoFrame(0.12, { reason = "onLoad" }) end
                    -- Ensure character faces camera after load unless solver already set absolute yaw
                    if h and h.FaceCamera and (h._autoFaceCamera ~= false) then
                        if h._yawFromSolver then
                            h:_DebugLog("camera", "FaceCamera skipped: using solver yaw=%.3f", h._frontYaw or 0)
                        else
                            h:FaceCamera()
                        end
                    end
                    -- Reapply desired animation intent post-load (if any)
                    if h and h._animCtrl and h._animCtrl.apply then
                        h._animCtrl:apply(a2)
                    end
                end)
            end
        else
            if CLN and CLN.Logger then
                CLN.Logger:error("ModelSceneRenderer: actor lacks SetModelByCreatureDisplayID", false, CLN.Utils.LogCategories.host)
            end
            return
        end
    end

    ---Set UI zoom level for portrait camera
    ---@param v number
    function host:SetPortraitZoom(v)
        -- Preserve current camera target; only adjust distance along current axis
        self._zoom = tonumber(v) or self._zoom or 0.65
        local z = self._zoom
        local d = math.max(1.2, 3.2 - (z * 2.6))
        self._camDist = d
        -- Mark that user is manually controlling camera when called from UI
        if self._fromDebugWindow then
            self._userControlledCamera = true
        end
        if backend.kind ~= "scene" or not backend.frame then return end
        -- Use last snapshot as the single source of truth
        local s = self._lastCamSnapshot or {}
        local tx = (s.tx ~= nil) and s.tx or 0
        local ty = (s.ty ~= nil) and s.ty or 0
        local tz = (s.tz ~= nil) and s.tz or (self._camBaseZ or 1.0)
        -- Infer axis/sign from last placement; default to +Y
        local axisTag = tostring(self._camAxis or ((self._camDir and self._camDir < 0) and "Y-" or "Y+"))
        local sign = axisTag:find("%-") and -1 or 1
        local px, py
        if axisTag:match("^Y") then
            px = tx
            py = ty + sign * d
        else
            px = tx + sign * d
            py = ty
        end
        local pz = tz
    self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
    -- Keep a coherent snapshot
    self:_UpdateSnapshot({ px = px, py = py, pz = pz, tx = tx, ty = ty, tz = tz, dist = d })
    -- Maintain clips using centralized helper
    self:_ApplyClipsFromSnapshot()
    end

    function host:GetPortraitZoom()
        return self._zoom or 0.65
    end

    ---Pan camera target vertically by z while preserving distance and target XY
    ---@param x number
    ---@param y number
    ---@param z number
    function host:SetPosition(x, y, z)
        -- Treat z as the absolute vertical target (pan) and preserve current target X/Y and distance
        local tz = tonumber(z)
        if tz == nil then return end
        -- Mark that user is manually controlling camera when called from UI
        if self._fromDebugWindow then
            self._userControlledCamera = true
        end
        if backend.kind ~= "scene" or not backend.frame then return end
        local s = self._lastCamSnapshot or {}
        local tx = (s.tx ~= nil) and s.tx or 0
        local ty = (s.ty ~= nil) and s.ty or 0
        local d  = self._camDist or s.dist or 2.5
        local axisTag = tostring(self._camAxis or ((self._camDir and self._camDir < 0) and "Y-" or "Y+"))
        local sign = axisTag:find("%-") and -1 or 1
        local px, py
        if axisTag:match("^Y") then
            px = tx
            py = ty + sign * d
        else
            px = tx + sign * d
            py = ty
        end
        -- Update baseZ so future head-aims use this level
        self._camBaseZ = tz
        local pz = tz
    self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
    -- Snapshot
    self:_UpdateSnapshot({ px = px, py = py, pz = pz, tx = tx, ty = ty, tz = tz })
    end

    ---Set actor yaw in radians
    ---@param rad number
    function host:SetRotation(rad)
        if backend.actor and backend.actor.SetYaw then pcall(backend.actor.SetYaw, backend.actor, rad or 0) end
    end

    ---Get current actor yaw in radians
    ---@return number
    function host:GetActorYaw()
        if backend.actor and backend.actor.GetYaw then
            local ok, yaw = pcall(backend.actor.GetYaw, backend.actor)
            if ok and type(yaw) == "number" then return yaw end
        end
        return self._frontYaw or 0
    end

    ---Set target yaw and mark user-controlled camera
    ---@param yaw number
    function host:SetActorYaw(yaw)
        local targetYaw = tonumber(yaw) or 0
        self._frontYaw = targetYaw
    self._yawFromSolver = false
        -- Mark that user is manually controlling camera
        self._userControlledCamera = true
        if backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, targetYaw)
        end
    end

    ---Play an animation by ID
    ---@param animId number
    function host:SetAnimation(animId)
        self._lastAnimId = animId
        if self._animCtrl and self._animCtrl.setDesired then
            self._animCtrl:setDesired(animId)
        end
        -- Respect ReplayFrame debug no-op animation mode
        local r = ReplayFrame
        if r and r._NoAnimDebugEnabled and r:_NoAnimDebugEnabled() then return end
        if backend.actor and backend.actor.SetAnimation then
            local okLoaded = backend.actor.IsLoaded and backend.actor:IsLoaded()
            if okLoaded or not backend.actor.IsLoaded then
                pcall(backend.actor.SetAnimation, backend.actor, animId)
            end
        end
    end

    ---Get last requested animation id
    ---@return number|nil
    function host:GetAnimation()
        return self._lastAnimId
    end

    function host:SetSheathed(b)
        -- Not generally supported on ModelScene actors; ignore
    end

    ---Pause or resume actor animations
    ---@param b boolean
    function host:SetPaused(b)
        if backend.actor and backend.actor.SetPaused then pcall(backend.actor.SetPaused, backend.actor, b and true or false) end
    end

    ---Load a unit model (player or NPC), with displayID preference for NPCs
    ---@param unit string
    function host:SetUnit(unit)
    local Loader = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
        if backend.actor and backend.actor.SetModelByUnit then
            -- Stamp a new session id for this unit-based model
            local t = (type(GetTime) == "function") and GetTime() or 0
            self._sessionId = tostring(unit or "unit") .. ":" .. tostring(math.floor(t * 1000))
            self:_BumpModelVersion()

            local isPlayer = UnitIsPlayer and UnitIsPlayer(unit) or false

            -- For player units, keep their native appearance and equipment to avoid missing textures
            if isPlayer then
                -- Let the engine use the player's customization and dress state
                if backend.actor.SetUseTransmogChoices then pcall(backend.actor.SetUseTransmogChoices, backend.actor, true) end
                if backend.actor.SetUseTransmogSkin then pcall(backend.actor.SetUseTransmogSkin, backend.actor, true) end
                if backend.actor.SetAutoDress then pcall(backend.actor.SetAutoDress, backend.actor, true) end
                -- Prefer: useNativeForm=true, includeItemMods=true, hideWeapons=false, autoDress=true
                local useNativeForm, includeItemMods, hideWeapons, autoDress = true, true, false, true
                self:_DebugLog("host", "SetUnit: unit=%s isPlayer=true flags(nat=%s,mods=%s,hide=%s,dress=%s)", tostring(unit), tostring(useNativeForm), tostring(includeItemMods), tostring(hideWeapons), tostring(autoDress))
                -- Use Loader but with respect for animation intent; player's transmog skin is enabled above
                if self._lastLoadSession and self._lastLoadSession.cancel then pcall(self._lastLoadSession.cancel) end
                if Loader and Loader.loadByUnit then
                    local session = Loader.loadByUnit(backend.actor, unit, { intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true })
                    self._lastLoadSession = session
                    if self._lastLoadSession then
                        self._lastLoadSession.kind = "unit"
                        self._lastLoadSession.arg = unit
                    end
                end
            else
                -- NPCs: try displayID path first for better texture support, fallback to SetUnit
                local displayID = nil
                if UnitCreatureDisplayID then
                    local ok, id = pcall(UnitCreatureDisplayID, unit)
                    if ok and type(id) == "number" and id > 0 then
                        displayID = id
                    end
                end
                
                if displayID and backend.actor.SetModelByCreatureDisplayID then
                    -- Use displayID path which typically has better texture support for NPCs
                    self:_DebugLog("host", "SetUnit: unit=%s isPlayer=false using displayID=%s", tostring(unit), tostring(displayID))
                    if self._lastLoadSession and self._lastLoadSession.cancel then pcall(self._lastLoadSession.cancel) end
                    if Loader and Loader.loadByDisplayID then
                        local session = Loader.loadByDisplayID(backend.actor, displayID, { intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true })
                        self._lastLoadSession = session
                        if self._lastLoadSession then
                            self._lastLoadSession.kind = "displayID"
                            self._lastLoadSession.arg = displayID
                        end
                    end
                else
                    -- Fallback to SetUnit for NPCs that don't have displayID or when displayID method fails
                    if self._lastLoadSession and self._lastLoadSession.cancel then pcall(self._lastLoadSession.cancel) end
                    if Loader and Loader.loadByUnit then
                        local session = Loader.loadByUnit(backend.actor, unit, { intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true })
                        self._lastLoadSession = session
                        if self._lastLoadSession then
                            self._lastLoadSession.kind = "unit"
                            self._lastLoadSession.arg = unit
                        end
                    end
                end
            end

        -- Schedule an auto-frame; will coalesce with load callbacks
        self:_RequestAutoFrame(0.12, { reason = "setUnit" })
            if self.OnModelLoadedOnce then
                self:OnModelLoadedOnce(function(h)
                    if h and h._LogLoadedModelAsset then h:_LogLoadedModelAsset("unit:" .. tostring(unit)) end
                    local a2 = h and h._backend and h._backend.actor
                    if a2 and a2.SetDesaturated then pcall(a2.SetDesaturated, a2, false) end
            if h and h._RequestAutoFrame then h:_RequestAutoFrame(0.12, { reason = "onLoad" }) end
                end)
            end
        end
    end

    function host:AutoFitToFrame()
        local a = backend.actor
        if not a then return end
        local minX, minY, minZ, maxX, maxY, maxZ
        local function assign(a1, b1, c1, d1, e1, f1)
            if type(a1) == "table" and type(b1) == "table" then
                return a1.x or 0, a1.y or 0, a1.z or 0, b1.x or 0, b1.y or 0, b1.z or 0
            end
            if type(a1) == "number" and type(b1) == "number" and type(c1) == "number" and type(d1) == "number" and type(e1) == "number" and type(f1) == "number" then
                return a1, b1, c1, d1, e1, f1
            end
            return nil
        end
        if a.GetActiveBoundingBox then
            local ok, a1, b1, c1, d1, e1, f1 = pcall(a.GetActiveBoundingBox, a)
            if ok then
                local x1, y1, z1, x2, y2, z2 = assign(a1, b1, c1, d1, e1, f1)
                if x1 then minX, minY, minZ, maxX, maxY, maxZ = x1, y1, z1, x2, y2, z2 end
            end
        elseif a.GetModelBounds then
            local ok, a1, b1, c1, d1, e1, f1 = pcall(a.GetModelBounds, a)
            if ok then
                local x1, y1, z1, x2, y2, z2 = assign(a1, b1, c1, d1, e1, f1)
                if x1 then minX, minY, minZ, maxX, maxY, maxZ = x1, y1, z1, x2, y2, z2 end
            end
        end
        if minX and maxX then
            local sizeZ = math.abs((maxZ or 0) - (minZ or 0))
            if sizeZ > 0 and a.SetScale then
                local targetScale = 1.0
                if sizeZ > 2.0 then targetScale = 2.0 / sizeZ end
                pcall(a.SetScale, a, targetScale)
            end
        end
        self:PointCameraAtHead()
    end

    function host:OnModelLoadedOnce(cb)
        if type(cb) ~= "function" then return end
        if not (backend.actor and backend.actor.IsLoaded) then return end
        local a = backend.actor
        local ok, loaded = pcall(a.IsLoaded, a)
        if ok and loaded then cb(self); return end
        local function tryOnce()
            local ok2, loaded2 = pcall(a.IsLoaded, a)
            if ok2 and loaded2 then cb(self); return true end
            return false
        end
        if C_Timer and C_Timer.NewTicker then
            local ticker
            ticker = C_Timer.NewTicker(0.05, function()
                if tryOnce() and ticker and ticker.Cancel then ticker:Cancel() end
            end)
        elseif C_Timer and C_Timer.After then
            local function loop()
                if not tryOnce() then C_Timer.After(0.05, loop) end
            end
            C_Timer.After(0.05, loop)
        end
    end

    function host:ApplyPreset(presetName)
        local name = tostring(presetName or "FullBody")
        local P = ReplayFrame and ReplayFrame.ScenePresets
        if P and P[name] then return P[name](self) end
        if name == "FullBody" then return self:FrameFullBodyFront(0.1) end
    end

    -- Keep scene visibility in sync with the host so the actor actually renders when shown
    if host.HookScript then
        host:HookScript("OnShow", function()
            local f, a = backend.frame, backend.actor
            -- Diagnostics: log visibility and z-order when becoming visible
            local U = CLN and CLN.Utils
            local catHost = CLN and CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.host or "host"
            if U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug(catHost) and U.LogAnimDebug then
                local strata = f and f.GetFrameStrata and f:GetFrameStrata() or "?"
                local lvl = f and f.GetFrameLevel and f:GetFrameLevel() or -1
                local pStrata = host and host.GetFrameStrata and host:GetFrameStrata() or "?"
                local pLvl = host and host.GetFrameLevel and host:GetFrameLevel() or -1
                pcall(U.LogAnimDebug, U, catHost, string.format("Host OnShow: host(shown=%s,vis=%s,strata=%s,level=%d) scene(shown=%s,vis=%s,strata=%s,level=%d) actor(shown=%s)",
                    tostring(host and host.IsShown and host:IsShown()), tostring(host and host.IsVisible and host:IsVisible()), tostring(pStrata), tonumber(pLvl) or -1,
                    tostring(f and f.IsShown and f:IsShown()), tostring(f and f.IsVisible and f:IsVisible()), tostring(strata), tonumber(lvl) or -1,
                    tostring(a and a.IsShown and a:IsShown())))
            end
            if f and f.Show then pcall(f.Show, f) end
            if a and a.Show then pcall(a.Show, a) end
        end)
        host:HookScript("OnHide", function()
            local f, a = backend.frame, backend.actor
            if a and a.Hide then pcall(a.Hide, a) end
            if f and f.Hide then pcall(f.Hide, f) end
            -- Cancel any pending delayed camera logs when hidden
            if self and self._camLogTimer and self._camLogTimer.Cancel then
                pcall(self._camLogTimer.Cancel, self._camLogTimer)
                self._camLogTimer = nil
            end
        end)
    end
end

