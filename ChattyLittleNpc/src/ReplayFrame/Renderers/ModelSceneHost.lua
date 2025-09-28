---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

local M = {}
ReplayFrame.ModelSceneHost = M

-- Small helpers
local function now()
    if type(GetTimePreciseSec) == "function" then return GetTimePreciseSec() end
    if type(GetTime) == "function" then return GetTime() end
    return 0
end

local function _frameName(f)
    if not f then return "<nil>" end
    local n = (f.GetName and f:GetName()) or nil
    return n or tostring(f)
end

-- Access to all ModelScene modules
local function getModules()
    local modules = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
    if modules then
    -- Diagnostics available; avoid printing to chat
    else
    -- No modules found; avoid chat prints
    end
    return modules
end

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
    
    -- Basic scene setup
    safeCall(scene, "SetAllPoints", parent)
    if scene.EnableMouse then pcall(scene.EnableMouse, scene, false) end
    if scene.SetFrameStrata then
        local strata = (parent and parent.GetFrameStrata and parent:GetFrameStrata()) or "HIGH"
        pcall(scene.SetFrameStrata, scene, strata)
    end
    if scene.SetFrameLevel and parent and parent.GetFrameLevel then
        pcall(scene.SetFrameLevel, scene, (parent:GetFrameLevel() or 0) + 1)
    end
    -- Log initial layering
    local pstrata = "?"
    local plevel = "?"
    if parent then
        if parent.GetFrameStrata then pstrata = parent:GetFrameStrata() or pstrata end
        if parent.GetFrameLevel then plevel = parent:GetFrameLevel() or plevel end
    end
    local sstrata = (scene.GetFrameStrata and scene:GetFrameStrata()) or "?"
    local slevel = (scene.GetFrameLevel and scene:GetFrameLevel()) or "?"
    
    -- Create actor
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
    if not actor then return nil end
    
    -- Basic actor setup
    if scene.Show then pcall(scene.Show, scene) end
    if scene.SetAlpha then pcall(scene.SetAlpha, scene, 1) end
    if actor.Show then pcall(actor.Show, actor) end
    if actor.SetAlpha then pcall(actor.SetAlpha, actor, 1) end
    if actor.SetPosition then pcall(actor.SetPosition, actor, 0, 0, 0) end
    if actor.SetModelScale then pcall(actor.SetModelScale, actor, 1.0) end
    if actor.SetUseCenterForOrigin then pcall(actor.SetUseCenterForOrigin, actor, true) end
    if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
    
    -- Lighting setup
    if scene.SetCameraNearClip then pcall(scene.SetCameraNearClip, scene, 0.1) end
    if scene.SetCameraFarClip then pcall(scene.SetCameraFarClip, scene, 100) end
    if scene.SetCameraFieldOfView then pcall(scene.SetCameraFieldOfView, scene, 0.8) end
    -- No chat logging for camera init
    if scene.SetLightVisible then pcall(scene.SetLightVisible, scene, true) end
    if scene.SetLightDiffuseColor then pcall(scene.SetLightDiffuseColor, scene, 1, 1, 1) end
    if scene.SetLightAmbientColor then pcall(scene.SetLightAmbientColor, scene, 0.6, 0.6, 0.6) end
    if scene.SetLightType and _G.LE_MODEL_LIGHT_TYPE_DIRECTIONAL then
        pcall(scene.SetLightType, scene, _G.LE_MODEL_LIGHT_TYPE_DIRECTIONAL)
    end
    if scene.SetLightDirection then pcall(scene.SetLightDirection, scene, 0, -1, -0.5) end
    
    return { kind = "scene", frame = scene, actor = actor }
end

-- Attach a lean API that delegates to modules
function M.Attach(host, backend)
    host._backend = backend
    host._lastAnimId = nil
    host._zoom = host._zoom or 0.65
    host._camBaseZ = host._camBaseZ or 1.0
    host._camDist = host._camDist or 2.5
    host._frontYaw = host._frontYaw or 0
    host._autoFaceCamera = host._autoFaceCamera ~= false
    host._lastCamSnapshot = nil
    -- _userControlledCamera deprecated; always scripted camera (debug may still set it)
    -- Legacy session/version tracking removed; simplified host uses direct framing
    
    local MS = getModules()
    
    -- Initialize animation controller
    if MS and MS.AnimationController and not host._animCtrl then
        host._animCtrl = MS.AnimationController.new()
    end
    
    -- Host logger using Diagnostics
    function host:_DebugLog(category, fmt, ...)
        if MS and MS.Diagnostics and MS.Diagnostics.log then
            MS.Diagnostics.log(category, fmt, ...)
        end
    end

    -- Centralized snapshot update to keep camera state coherent
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
    -- sessionId retained only for debug display; not used for version invalidation anymore
    if not s.sessionId and self._sessionId then s.sessionId = self._sessionId end
        self._lastCamSnapshot = s
    end

    -- Removed debounced auto-framing + versioning; simplified direct framing is used.
    
    -- Basic model operations
    ---Clear current model from the actor
    function host:ClearModel()
        if backend.actor and backend.actor.ClearModel then 
            pcall(backend.actor.ClearModel, backend.actor) 
        end
    end
    
    ---Load a model by creature display ID
    ---@param displayID number
    function host:SetDisplayInfo(displayID)
        if not (backend.actor and backend.actor.SetModelByCreatureDisplayID) then
            if CLN and CLN.Logger then
                CLN.Logger:error("ModelSceneHost: actor lacks SetModelByCreatureDisplayID (falling back)", false, CLN.Utils.LogCategories.host)
            end
            -- Attempt dynamic fallback to PlayerModel renderer if host provides helper
            if self.FallbackToPlayer then
                self:FallbackToPlayer("missing-SetModelByCreatureDisplayID", { displayID = displayID })
            end
            return
        end
        
    self:_DebugLog("host", "SetDisplayInfo called with displayID=%s", tostring(displayID))
        local hasTicker = (C_Timer and C_Timer.NewTicker) and true or false
        local hasAfter = (C_Timer and C_Timer.After) and true or false
        local hasIsLoaded = backend.actor and backend.actor.IsLoaded and true or false
    self:_DebugLog("host", "SetDisplayInfo env ticker=%s after=%s isLoadedFn=%s", tostring(hasTicker), tostring(hasAfter), tostring(hasIsLoaded))
        -- Duplicate-call detection (log-only)
        if self._lastRequestKind == "displayID" and self._lastRequestArg == displayID then
            local dt = now() - (self._lastRequestAt or 0)
            if dt < 1.0 then
                self:_DebugLog("host", "SetDisplayInfo duplicate within %.2fs for id=%s", dt, tostring(displayID))
            end
        end
        self._lastRequestKind, self._lastRequestArg, self._lastRequestAt = "displayID", displayID, now()
        
    -- Cancel previous load session
        if self._lastLoadSession and self._lastLoadSession.cancel then 
            self:_DebugLog("host", "Cancel previous session kind=%s arg=%s", tostring(self._lastLoadSession.kind), tostring(self._lastLoadSession.arg))
            pcall(self._lastLoadSession.cancel) 
        end
    -- Reset camera state for fresh model
    self._lastCamSnapshot = nil
    -- Reset any transient legacy state (versioning removed)
        
        -- Delegate to Loader module
        if MS and MS.Loader and MS.Loader.loadByDisplayID then
            self:_DebugLog("loader", "Using Loader.loadByDisplayID for id=%s", tostring(displayID))
            local session = MS.Loader.loadByDisplayID(backend.actor, displayID, {
                intervalMs = 50, 
                timeoutMs = 3000, 
                maxAttempts = 2, 
                respectAnimationIntent = true 
            })
            self._lastLoadSession = session
            if session then
                session.kind = "displayID"
                session.arg = displayID
                self:_DebugLog("loader", "Loader session created; has cancel=%s", tostring(session.cancel ~= nil))
            else
                self:_DebugLog("loader", "Failed to create loader session")
            end
        elseif MS and type(MS.loadByDisplayID) == "function" then
            self:_DebugLog("loader", "Using ModelScene.loadByDisplayID for id=%s", tostring(displayID))
            local session = MS.loadByDisplayID(backend.actor, displayID, {
                intervalMs = 50,
                timeoutMs = 3000,
                maxAttempts = 2,
                respectAnimationIntent = true,
            })
            self._lastLoadSession = session
            if session then
                session.kind = "displayID"
                session.arg = displayID
                self:_DebugLog("loader", "Loader session created (direct fn); has cancel=%s", tostring(session.cancel ~= nil))
            else
                self:_DebugLog("loader", "Failed to create loader session (direct fn)")
            end
        else
            self:_DebugLog("loader", "Loader module not available; using fallback")
            -- Fallback: direct call
            local ok = pcall(backend.actor.SetModelByCreatureDisplayID, backend.actor, displayID, false)
            if not ok then 
                ok = pcall(backend.actor.SetModelByCreatureDisplayID, backend.actor, displayID) 
            end
            self:_DebugLog("loader", "Direct fallback call success=%s", tostring(ok))
            if MS and MS.Stabilizer then
                MS.Stabilizer.stabilize(backend.actor, { respectAnimationIntent = true })
            end
        end
        -- Watchdog: after timeout window, report if still not loaded
        if C_Timer and C_Timer.After then
            local token = {}
            self._loadWatchdogToken = token
            local arg = displayID
            local timeoutSec = self._loadTimeoutSec or 3.2
            C_Timer.After(timeoutSec, function()
                if self._loadWatchdogToken ~= token then return end
                -- If backend already changed (e.g., fallback) abort
                if self._backend and self._backend.kind ~= "scene" then return end
                local loadedFlag = "err"
                local isLoaded = false
                if backend.actor and backend.actor.IsLoaded then
                    local okL, v = pcall(backend.actor.IsLoaded, backend.actor)
                    if okL then
                        loadedFlag = v
                        isLoaded = (v == true)
                    end
                end
                local sk = self._lastLoadSession and self._lastLoadSession.kind or "?"
                local sa = self._lastLoadSession and self._lastLoadSession.arg or "?"
                self:_DebugLog("host", string.format("watchdog[displayID] %.1fs loaded=%s session=%s %s", timeoutSec, tostring(loadedFlag), tostring(sk), tostring(sa)))
                if (not isLoaded) and self.FallbackToPlayer then
                    if CLN and CLN.Logger then
                        CLN.Logger:warn("ModelSceneHost watchdog timeout: falling back to PlayerModel backend", false, CLN.Utils.LogCategories.host)
                    end
                    self:FallbackToPlayer("load-timeout-displayID", { displayID = displayID })
                end
                if self._DumpState then self:_DumpState("watchdog/displayID") end
            end)
        end
        
        -- Direct frame (simplified)
        self:FrameFullBodyFront(0.12)
        
        -- Post-load callback
        if self.OnModelLoadedOnce then
            self:OnModelLoadedOnce(function(h)
                self:_DebugLog("host", "OnModelLoadedOnce fired (displayID)")
                if h and h._animCtrl and h._animCtrl.apply then
                    h._animCtrl:apply(backend.actor)
                end
                h:FrameFullBodyFront(0.12)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.15, function()
                        if h._DumpState then h:_DumpState("post-load/displayID") end
                    end)
                end
            end)
        end
    end
    
    function host:SetUnit(unit)
        if not (backend.actor and backend.actor.SetModelByUnit) then return end
        
        -- Cancel previous load session
        if self._lastLoadSession and self._lastLoadSession.cancel then 
            self:_DebugLog("host", "Cancel previous session kind=%s arg=%s", tostring(self._lastLoadSession.kind), tostring(self._lastLoadSession.arg))
            pcall(self._lastLoadSession.cancel) 
        end
    -- Reset camera state for fresh unit
    self._lastCamSnapshot = nil
    self._sessionId = string.format("unit:%s@%.3f", tostring(unit), now())
        
        local isPlayer = UnitIsPlayer and UnitIsPlayer(unit) or false
    self:_DebugLog("host", "SetUnit called unit=%s isPlayer=%s", tostring(unit), tostring(isPlayer))
        local hasTicker = (C_Timer and C_Timer.NewTicker) and true or false
        local hasAfter = (C_Timer and C_Timer.After) and true or false
        local hasIsLoaded = backend.actor and backend.actor.IsLoaded and true or false
    self:_DebugLog("host", "SetUnit env ticker=%s after=%s isLoadedFn=%s", tostring(hasTicker), tostring(hasAfter), tostring(hasIsLoaded))
        -- Duplicate-call detection (log-only)
        if self._lastRequestKind == "unit" and self._lastRequestArg == unit then
            local dt = now() - (self._lastRequestAt or 0)
            if dt < 1.0 then
                self:_DebugLog("host", "SetUnit duplicate within %.2fs for unit=%s", dt, tostring(unit))
            end
        end
        self._lastRequestKind, self._lastRequestArg, self._lastRequestAt = "unit", unit, now()
        
        if isPlayer then
            -- Enable transmog for players
            if backend.actor.SetUseTransmogChoices then 
                pcall(backend.actor.SetUseTransmogChoices, backend.actor, true) 
            end
            if backend.actor.SetUseTransmogSkin then 
                pcall(backend.actor.SetUseTransmogSkin, backend.actor, true) 
            end
            if backend.actor.SetAutoDress then 
                pcall(backend.actor.SetAutoDress, backend.actor, true) 
            end
        end
        
        -- Delegate to Loader module
        if MS then
            local session
            if not isPlayer and UnitCreatureDisplayID then
                -- Try displayID path for NPCs
                local ok, displayID = pcall(UnitCreatureDisplayID, unit)
                if ok and type(displayID) == "number" and displayID > 0 then
                    if MS.Loader and MS.Loader.loadByDisplayID then
                        self:_DebugLog("loader", "SetUnit using Loader.loadByDisplayID for NPC unit=%s id=%s", tostring(unit), tostring(displayID))
                        session = MS.Loader.loadByDisplayID(backend.actor, displayID, {
                            intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                        })
                    elseif type(MS.loadByDisplayID) == "function" then
                        self:_DebugLog("loader", "SetUnit using ModelScene.loadByDisplayID for NPC unit=%s id=%s", tostring(unit), tostring(displayID))
                        session = MS.loadByDisplayID(backend.actor, displayID, {
                            intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                        })
                    end
                end
            end
            if not session then
                if MS.Loader and MS.Loader.loadByUnit then
                    self:_DebugLog("loader", "SetUnit using Loader.loadByUnit for unit=%s", tostring(unit))
                    session = MS.Loader.loadByUnit(backend.actor, unit, {
                        intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                    })
                elseif type(MS.loadByUnit) == "function" then
                    self:_DebugLog("loader", "SetUnit using ModelScene.loadByUnit for unit=%s", tostring(unit))
                    session = MS.loadByUnit(backend.actor, unit, {
                        intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                    })
                end
            end
            self._lastLoadSession = session
            if session then
                session.kind = "unit"
                session.arg = unit
                self:_DebugLog("loader", "Loader session created (unit); has cancel=%s", tostring(session.cancel ~= nil))
            end
        end
        -- Watchdog: after timeout window, report if still not loaded
        if C_Timer and C_Timer.After then
            local token = {}
            self._loadWatchdogToken = token
            local arg = unit
            local timeoutSec = self._loadTimeoutSec or 3.2
            C_Timer.After(timeoutSec, function()
                if self._loadWatchdogToken ~= token then return end
                if self._backend and self._backend.kind ~= "scene" then return end
                local loadedFlag = "err"
                local isLoaded = false
                if backend.actor and backend.actor.IsLoaded then
                    local okL, v = pcall(backend.actor.IsLoaded, backend.actor)
                    if okL then
                        loadedFlag = v
                        isLoaded = (v == true)
                    end
                end
                local sk = self._lastLoadSession and self._lastLoadSession.kind or "?"
                local sa = self._lastLoadSession and self._lastLoadSession.arg or "?"
                self:_DebugLog("host", string.format("watchdog[unit] %.1fs loaded=%s session=%s %s", timeoutSec, tostring(loadedFlag), tostring(sk), tostring(sa)))
                if (not isLoaded) and self.FallbackToPlayer then
                    if CLN and CLN.Logger then
                        CLN.Logger:warn("ModelSceneHost watchdog timeout (unit): falling back to PlayerModel backend", false, CLN.Utils.LogCategories.host)
                    end
                    self:FallbackToPlayer("load-timeout-unit", { unit = unit })
                end
                if self._DumpState then self:_DumpState("watchdog/unit") end
            end)
        end
        
        -- Immediate direct framing (legacy auto-frame/debounce removed)
        self:FrameFullBodyFront(0.12)
        
        -- Post-load: ensure animation controller and camera are applied once content is ready
        if self.OnModelLoadedOnce then
            self:OnModelLoadedOnce(function(h)
                self:_DebugLog("host", "OnModelLoadedOnce fired (unit)")
                if h and h._animCtrl and h._animCtrl.apply then
                    h._animCtrl:apply(backend.actor)
                end
                if h and h.FaceCamera then h:FaceCamera() end
                h:FrameFullBodyFront(0.12)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.15, function()
                        if h._DumpState then h:_DumpState("post-load/unit") end
                    end)
                end
            end)
        end
    end
    
    -- Animation
    function host:SetAnimation(animId)
        self._lastAnimId = animId
        if self._animCtrl and self._animCtrl.setDesired then
            self._animCtrl:setDesired(animId)
        end
        
        -- Respect debug no-op mode
        local r = ReplayFrame
        if r and r._NoAnimDebugEnabled and r:_NoAnimDebugEnabled() then return end
        
        if backend.actor and backend.actor.SetAnimation then
            local okLoaded = not backend.actor.IsLoaded or backend.actor:IsLoaded()
            if okLoaded then
                pcall(backend.actor.SetAnimation, backend.actor, animId)
            end
        end
    end
    
    function host:GetAnimation()
        return self._lastAnimId
    end
    
    -- Camera and positioning
    function host:SetPortraitZoom(v)
        self._zoom = tonumber(v) or self._zoom or 0.65
        local d = math.max(1.2, 3.2 - (self._zoom * 2.6))
        self._camDist = d
    self:PointCameraAtHead()
    end
    
    function host:GetPortraitZoom()
        return self._zoom or 0.65
    end
    
    function host:PointCameraAtHead()
        if backend.kind ~= "scene" or not backend.frame then return end
        -- Prefer last known target from framing/pan; else use current bounds center; else origin Z
        local s = self._lastCamSnapshot or {}
        local b = self:GetBounds()
        local baseX = s.tx or (b and b.center and b.center.x) or 0
        local baseY = s.ty or (b and b.center and b.center.y) or 0
        local baseZ = s.tz or (b and b.center and b.center.z) or (self._camBaseZ or 1.0)
        self._camBaseZ = baseZ
        local d = self._camDist or 2.5
        local px, py, pz = baseX, baseY + d, baseZ
        local tx, ty, tz = baseX, baseY, baseZ
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
    -- Persist snapshot for subsequent operations (zoom/pan)
    self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz })
    end
    
    function host:FaceCamera()
        -- Preserve user camera placement; only rotate actor to face forward
        if self._autoFaceCamera ~= false and backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, self._frontYaw or 0)
        end
    end

    -- Enable panning for ModelScene host by explicitly setting camera target
    function host:SetTarget(vec3)
        if backend.kind ~= "scene" or not backend.frame then return end
        vec3 = vec3 or {}
    -- target adjustment (debug/manual)
        -- Current camera pos/target (from last basis if getters missing)
        local px, py, pz = 0, (self._camDist or 2.5), (self._camBaseZ or 1.0)
        if backend.frame.GetCameraPosition then
            local ok, x, y, z = pcall(backend.frame.GetCameraPosition, backend.frame)
            if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
                px, py, pz = x, y, z
            end
        elseif self._lastCam then
            px = self._lastCam.px or px
            py = self._lastCam.py or py
            pz = self._lastCam.pz or pz
        end
        local s = self._lastCamSnapshot or {}
        local prevTx = s.tx; local prevTy = s.ty; local prevTz = s.tz
        if not (prevTx and prevTy and prevTz) then
            local b = self:GetBounds()
            if b and b.center then prevTx, prevTy, prevTz = b.center.x, b.center.y, b.center.z end
        end
        prevTx = prevTx or 0; prevTy = prevTy or 0; prevTz = prevTz or (self._camBaseZ or 1.0)
        local tx = (vec3.x ~= nil) and vec3.x or prevTx
        local ty = (vec3.y ~= nil) and vec3.y or prevTy
        local tz = (vec3.z ~= nil) and vec3.z or prevTz
        -- Translate camera by the same delta as target change (true pan)
        local dx, dy, dz = (tx - prevTx), (ty - prevTy), (tz - prevTz)
        px, py, pz = px + dx, py + dy, pz + dz
        self._camBaseZ = tz
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
    -- Update clip planes to avoid clipping during close pans
    if self._lastBounds then self:_UpdateClipPlanesForFit(self._camDist or 2.5, self._lastBounds, 0.12) end
    -- Persist snapshot
    self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz })
    end
    
    function host:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        if backend.kind ~= "scene" or not backend.frame then return end
        
        if backend.frame.SetCameraPosition then
            pcall(backend.frame.SetCameraPosition, backend.frame, px, py, pz)
        end
        
        -- Delegate to CameraController if available
        -- Build camera basis once
        local function normalize(x, y, z)
            local len = math.sqrt((x or 0)^2 + (y or 0)^2 + (z or 0)^2)
            if len <= 1e-6 then return 0, 0, 0 end
            return x / len, y / len, z / len
        end
        local function cross(ax, ay, az, bx, by, bz)
            return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
        end
        local fx, fy, fz = normalize((tx or 0) - (px or 0), (ty or 0) - (py or 0), (tz or 0) - (pz or 0))
        if fx == 0 and fy == 0 and fz == 0 then fx, fy, fz = 0, 1, 0 end
        local upRefX, upRefY, upRefZ = 0, 0, 1
        if math.abs(fx * upRefX + fy * upRefY + fz * upRefZ) > 0.999 then upRefX, upRefY, upRefZ = 0, 1, 0 end
        local rx, ry, rz = cross(upRefX, upRefY, upRefZ, fx, fy, fz)
        rx, ry, rz = normalize(rx, ry, rz)
        local ux, uy, uz = cross(fx, fy, fz, rx, ry, rz)
        -- Store last camera basis for debugging
        self._lastCam = { px = px, py = py, pz = pz, tx = tx, ty = ty, tz = tz, fx = fx, fy = fy, fz = fz, rx = rx, ry = ry, rz = rz, ux = ux, uy = uy, uz = uz }
    self:_DebugLog("camera", "Camera set pos=(%.2f,%.2f,%.2f) tgt=(%.2f,%.2f,%.2f) f=(%.2f,%.2f,%.2f) r=(%.2f,%.2f,%.2f) u=(%.2f,%.2f,%.2f)", px, py, pz, tx, ty, tz, fx, fy, fz, rx, ry, rz, ux, uy, uz)
        
        if MS and MS.CameraController and MS.CameraController.setOrientation then
            MS.CameraController.setOrientation(backend.frame, rx, ry, rz, ux, uy, uz, fx, fy, fz)
        elseif backend.frame.SetCameraOrientationByAxisVectors then
            -- Direct fallback
            pcall(backend.frame.SetCameraOrientationByAxisVectors, backend.frame, rx, ry, rz, ux, uy, uz, fx, fy, fz)
        end
        -- Log current camera clips/FOV, if getters exist
        local nclip, fclip, fovv
        if backend.frame.GetCameraNearClip then local ok, v = pcall(backend.frame.GetCameraNearClip, backend.frame); if ok then nclip = v end end
        if backend.frame.GetCameraFarClip then local ok, v = pcall(backend.frame.GetCameraFarClip, backend.frame); if ok then fclip = v end end
        if backend.frame.GetCameraFieldOfView then local ok, v = pcall(backend.frame.GetCameraFieldOfView, backend.frame); if ok then fovv = v end end
        if nclip or fclip or fovv then
            self:_DebugLog("camera", "Params near=%s far=%s fov=%.3f rad (%.1f deg)", tostring(nclip or "?"), tostring(fclip or "?"), tonumber(fovv or 0) or 0, (tonumber(fovv or 0) or 0) * 180 / math.pi)
        end
    end

    -- Compute and apply clip planes for the current fit
    function host:_UpdateClipPlanesForFit(d, bounds, paddingFrac)
        if backend.kind ~= "scene" or not backend.frame then return end
        bounds = bounds or self._lastBounds or self:GetBounds()
        paddingFrac = tonumber(paddingFrac) or 0.12
        if not bounds then return end
        -- approximate radius with padding
        local sx, sy, sz = bounds.size.x or 0, bounds.size.y or 0, bounds.size.z or 0
        local padX, padY, padZ = sx * paddingFrac, sy * paddingFrac, sz * paddingFrac
        local rx, ry, rz = (sx + 2*padX) * 0.5, (sy + 2*padY) * 0.5, (sz + 2*padZ) * 0.5
        local R = math.sqrt(rx*rx + ry*ry + rz*rz)
        d = tonumber(d) or (self._camDist or 2.5)
        local near = math.max(0.01, d - R * 1.5)
        local far = math.max(near * 2.5, d + R * 1.5)
        if backend.frame.SetCameraNearClip then pcall(backend.frame.SetCameraNearClip, backend.frame, near) end
        if backend.frame.SetCameraFarClip then pcall(backend.frame.SetCameraFarClip, backend.frame, far) end
    end

    -- Refit distance only, preserving current target; used on resize
    -- Removed FitDistanceForCurrentTarget (legacy); direct framing recomputes fully.
    
    -- Immediate framing implementation (called by coordinator)
    -- Simplified direct framing (mirrors minimal renderer logic)
    function host:FrameFullBodyFront(paddingFrac)
        local pad = tonumber(paddingFrac) or 0.12
        local b = self:GetBounds()
        if not b then
            self:_DebugLog("framing", "No bounds yet for direct frame; skipping")
            return
        end
        local vfov = self:GetFovV()
        local aspect = self:GetAspect()
        local hfov = 2 * math.atan(math.tan(vfov * 0.5) * math.max(1e-3, aspect))
        local halfH = (b.size.z * 0.5) * (1 + pad)
        local halfW = (b.size.x * 0.5) * (1 + pad)
        local distV = halfH / math.max(1e-5, math.tan(vfov * 0.5))
        local distH = halfW / math.max(1e-5, math.tan(hfov * 0.5))
        local dist = math.max(0.5, distV, distH)
        local compBias = self._compBias or 0.25
        local halfView = dist * math.tan(vfov * 0.5)
        local slack = math.max(0, halfView - (b.size.z * 0.5))
        local tz = b.center.z + compBias * slack
        local px, py, pz = b.center.x, b.center.y + dist, tz
        local tx, ty = b.center.x, b.center.y
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        self._camDist = dist
        self._camBaseZ = b.center.z
        self:_UpdateSnapshot({ px = px, py = py, pz = pz, tx = tx, ty = ty, tz = tz, dist = dist })
        self._lastBounds = b
        if self._autoFaceCamera ~= false and backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, self._frontYaw or 0)
        end
        self:_DebugLog("framing", "Direct frame dist=%.2f pad=%.2f size=(%.2f,%.2f,%.2f)", dist, pad, b.size.x, b.size.y, b.size.z)
    end
    
    -- Utility methods
    function host:GetBounds()
    if not backend.actor then return nil end
        local minX, minY, minZ, maxX, maxY, maxZ
        
        if backend.actor.GetActiveBoundingBox then
            local ok, a, b, c, d, e, f = pcall(backend.actor.GetActiveBoundingBox, backend.actor)
            if ok and type(a) == "table" and type(b) == "table" then
                minX, minY, minZ = tonumber(a.x) or 0, tonumber(a.y) or 0, tonumber(a.z) or 0
                maxX, maxY, maxZ = tonumber(b.x) or 0, tonumber(b.y) or 0, tonumber(b.z) or 0
            elseif ok and type(a) == "number" then
                minX, minY, minZ, maxX, maxY, maxZ = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0, tonumber(e) or 0, tonumber(f) or 0
            end
        end
        
    if not minX then return nil end
        if minX > maxX then minX, maxX = maxX, minX end
        if minY > maxY then minY, maxY = maxY, minY end
        if minZ > maxZ then minZ, maxZ = maxZ, minZ end
        local cx, cy, cz = (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5
        local sx, sy, sz = math.abs(maxX - minX), math.abs(maxY - minY), math.abs(maxZ - minZ)
        local eps = 1e-3
        if sx < eps then sx = eps end
        if sy < eps then sy = eps end
        if sz < eps then sz = eps end
    local out = { 
            center = { x = cx, y = cy, z = cz }, 
            size = { x = sx, y = sy, z = sz },
            min = { x = minX, y = minY, z = minZ },
            max = { x = maxX, y = maxY, z = maxZ }
    }
    self._lastBounds = out
    return out
    end
    
    function host:GetFovV()
        local f
        if backend.frame and backend.frame.GetCameraFieldOfView then
            local ok, v = pcall(backend.frame.GetCameraFieldOfView, backend.frame)
            if ok and type(v) == "number" then f = v end
        end
        if not f or f <= 0 then f = 0.8 end
        -- If value looks like degrees, convert to radians
        if f > 3.5 then f = f * math.pi / 180 end
        -- Clamp to a sane range in radians
        if f < 0.1 then f = 0.1 elseif f > 2.8 then f = 2.8 end
        return f
    end
    
    function host:GetAspect()
        local w, h = self:GetSize()
        if not (w and h) or h == 0 then return 1.0 end
        return w / h
    end
    
    -- Additional compatibility methods
    function host:SetSheathed(b) end -- Not supported on ModelScene
    function host:SetPaused(b)
        if backend.actor and backend.actor.SetPaused then 
            pcall(backend.actor.SetPaused, backend.actor, b and true or false) 
        end
    end
    
    function host:SetActorYaw(yaw)
        self._frontYaw = tonumber(yaw) or 0
        if backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, self._frontYaw)
        end
    end
    
    function host:GetActorYaw()
        if backend.actor and backend.actor.GetYaw then
            local ok, yaw = pcall(backend.actor.GetYaw, backend.actor)
            if ok and type(yaw) == "number" then return yaw end
        end
        return self._frontYaw or 0
    end
    
    -- Load monitoring
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
    
    -- Keep scene visibility in sync with host
    if host.HookScript then
        host:HookScript("OnShow", function()
            local f, a = backend.frame, backend.actor
            host:_DebugLog("host", "OnShow (frame+actor shown)")
            if f and f.Show then pcall(f.Show, f) end
            if a and a.Show then pcall(a.Show, a) end
            if host.GetSize then
                local w, h = host:GetSize(); host:_DebugLog("host", "size on show = %.1fx%.1f", tonumber(w) or -1, tonumber(h) or -1)
                -- [Trigger] and [Size] snapshot at show time
                local sF = host.GetEffectiveScale and host:GetEffectiveScale() or 1
                local sU = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
                local aspect = (h and h > 0) and ((tonumber(w) or 0) / (tonumber(h) or 1)) or 1
                host:_DebugLog("framing", string.format("[Trigger] OnShow (autoFace=%s)", tostring(host._autoFaceCamera ~= false)))
                host:_DebugLog("framing", string.format("[Size] frame=%.1fx%.1f aspect=%.6f scale(frame)=%.4f scale(UI)=%.4f", tonumber(w) or -1, tonumber(h) or -1, aspect or -1, tonumber(sF) or 1, tonumber(sU) or 1))
            end
            if a and a.IsLoaded then
                local okL, v = pcall(a.IsLoaded, a)
                if okL and v then
                    -- Even if user had previously controlled camera, we now standardize framing
                    host:FrameFullBodyFront(0.12)
                end
            end
            if host._DumpState then host:_DumpState("OnShow") end
        end)
        host:HookScript("OnHide", function()
            local f, a = backend.frame, backend.actor
            host:_DebugLog("host", "OnHide (frame+actor hidden)")
            if a and a.Hide then pcall(a.Hide, a) end
            if f and f.Hide then pcall(f.Hide, f) end
        end)
        host:HookScript("OnSizeChanged", function(_, w, h)
            host:_DebugLog("host", "OnSizeChanged -> %.1fx%.1f", tonumber(w) or -1, tonumber(h) or -1)
            -- [Trigger] and [Size] details for live viewport & scales
            local sF = host.GetEffectiveScale and host:GetEffectiveScale() or 1
            local sU = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            local aspect = (h and h > 0) and ((tonumber(w) or 0) / (tonumber(h) or 1)) or 1
            host:_DebugLog("framing", string.format("[Trigger] OnSizeChanged (autoFace=%s)", tostring(host._autoFaceCamera ~= false)))
            host:_DebugLog("framing", string.format("[Size] frame=%.1fx%.1f aspect=%.6f scale(frame)=%.4f scale(UI)=%.4f", tonumber(w) or -1, tonumber(h) or -1, aspect or -1, tonumber(sF) or 1, tonumber(sU) or 1))
            -- If something is loaded, re-frame to fit
            if backend.actor and backend.actor.IsLoaded then
                local okL, v = pcall(backend.actor.IsLoaded, backend.actor)
                if okL and v then
                    host:FrameFullBodyFront(0.12)
                end
            end
            if host._DumpState then host:_DumpState("OnSizeChanged") end
        end)
    end

    -- Rich state dump for troubleshooting
    function host:_DumpState(label)
        label = label or "dump"
        local f, a = backend.frame, backend.actor
    local w, h = -1, -1
    if self.GetSize then w, h = self:GetSize() end
        local sStrata = f and f.GetFrameStrata and f:GetFrameStrata() or "?"
        local sLevel = f and f.GetFrameLevel and f:GetFrameLevel() or "?"
        local sShown = f and f.IsShown and f:IsShown() or false
        local sVisible = f and f.IsVisible and f:IsVisible() or false
        local sAlpha = f and f.GetAlpha and f:GetAlpha() or "?"
        local aShown = a and a.IsShown and a:IsShown() or false
        local aAlpha = a and a.GetAlpha and a:GetAlpha() or "?"
        local aLoaded = false; if a and a.IsLoaded then local okL, v = pcall(a.IsLoaded, a); aLoaded = okL and v or false end
        local yaw, pitch, roll = "?", "?", "?"
        if a then
            if a.GetYaw then local ok, v = pcall(a.GetYaw, a); if ok then yaw = v end end
            if a.GetPitch then local ok, v = pcall(a.GetPitch, a); if ok then pitch = v end end
            if a.GetRoll then local ok, v = pcall(a.GetRoll, a); if ok then roll = v end end
        end
        local posX, posY, posZ = "?","?","?"
        if a and a.GetPosition then local okP, x, y, z = pcall(a.GetPosition, a); if okP then posX, posY, posZ = x, y, z end end
        local scale = "?"
        if a and a.GetModelScale then local okS, s = pcall(a.GetModelScale, a); if okS then scale = s end end
        local b = self:GetBounds()
        local cam = self._lastCam or {}
    self:_DebugLog("host", "DUMP[%s] size=%.1fx%.1f scene(shown=%s vis=%s strata=%s lvl=%s alpha=%s) actor(loaded=%s shown=%s alpha=%s pos=(%s,%s,%s) scale=%s yaw=%s pitch=%s roll=%s)", label, tonumber(w) or -1, tonumber(h) or -1, tostring(sShown), tostring(sVisible), tostring(sStrata), tostring(sLevel), tostring(sAlpha), tostring(aLoaded), tostring(aShown), tostring(aAlpha), tostring(posX), tostring(posY), tostring(posZ), tostring(scale), tostring(yaw), tostring(pitch), tostring(roll))
        if b then
            self:_DebugLog("host", "DUMP[%s] bounds c=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f) min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)", label, b.center.x or 0, b.center.y or 0, b.center.z or 0, b.size.x or 0, b.size.y or 0, b.size.z or 0, b.min.x or 0, b.min.y or 0, b.min.z or 0, b.max.x or 0, b.max.y or 0, b.max.z or 0)
        else
            self:_DebugLog("host", "DUMP[%s] bounds=nil", label)
        end
        if next(cam) then
            self:_DebugLog("camera", "DUMP[%s] cam pos=(%.2f,%.2f,%.2f) tgt=(%.2f,%.2f,%.2f) f=(%.2f,%.2f,%.2f) r=(%.2f,%.2f,%.2f) u=(%.2f,%.2f,%.2f)", label, cam.px or 0, cam.py or 0, cam.pz or 0, cam.tx or 0, cam.ty or 0, cam.tz or 0, cam.fx or 0, cam.fy or 0, cam.fz or 0, cam.rx or 0, cam.ry or 0, cam.rz or 0, cam.ux or 0, cam.uy or 0, cam.uz or 0)
        end
        -- Parent info
    local p = nil
    if self.GetParent then p = self:GetParent() end
        if p then
            local pStrata = p.GetFrameStrata and p:GetFrameStrata() or "?"
            local pLevel = p.GetFrameLevel and p:GetFrameLevel() or "?"
            local pShown = p.IsShown and p:IsShown() or false
            local pVisible = p.IsVisible and p:IsVisible() or false
            self:_DebugLog("host", "DUMP[%s] parent=%s strata=%s lvl=%s shown=%s vis=%s", label, _frameName(p), tostring(pStrata), tostring(pLevel), tostring(pShown), tostring(pVisible))
        end
        -- Profile flags of interest
        local adv = CLN and CLN.db and CLN.db.profile and CLN.db.profile.advancedCameraFitting
    self:_DebugLog("host", "DUMP[%s] advancedCameraFitting=%s", label, tostring(adv))
    end
end

return M
