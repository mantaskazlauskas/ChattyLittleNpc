---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

local M = {}
ReplayFrame.ModelSceneRenderer = M

-- Minimal deterministic ModelScene renderer.
-- All legacy multi-pass framing, projector correction, axis switching,
-- camera snapshot debouncing, and experimental flags have been removed.
-- This file should remain intentionally small and easy to reason about.

-- =========================================================================
-- Helpers
-- =========================================================================
local function safeCall(obj, method, ...)
    if not (obj and method and obj[method]) then return nil end
    local ok, res = pcall(obj[method], obj, ...); if ok then return res end; return nil
end

local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end

local function dbg(cat, fmt, ...)
    local U = CLN and CLN.Utils
    if not (U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug(cat)) then return end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    if ok and U.LogAnimDebug then pcall(U.LogAnimDebug, U, cat, msg) end
end

-- =========================================================================
-- Backend Creation
-- =========================================================================
function M.Create(parent)
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, parent)
    if not (ok and scene) then return nil end
    safeCall(scene, "SetAllPoints", parent)
    safeCall(scene, "EnableMouse", false)
    if scene.SetFrameStrata and parent and parent.GetFrameStrata then safeCall(scene, "SetFrameStrata", parent:GetFrameStrata()) end
    if scene.SetFrameLevel and parent and parent.GetFrameLevel then safeCall(scene, "SetFrameLevel", (parent:GetFrameLevel() or 0) + 1) end
    local actor
    if scene.CreateActor then
        actor = safeCall(scene, "CreateActor", "ModelSceneActorTemplate") or safeCall(scene, "CreateActor")
    end
    if not actor and scene.GetPlayerActor then actor = safeCall(scene, "GetPlayerActor") end
    if not actor then return nil end
    safeCall(scene, "Show"); safeCall(actor, "Show")
    safeCall(actor, "SetUseCenterForOrigin", true)
    safeCall(actor, "SetDesaturated", false)
    safeCall(scene, "SetCameraNearClip", 0.1)
    safeCall(scene, "SetCameraFarClip", 100)
    safeCall(scene, "SetCameraFieldOfView", 0.8)
    return { kind = "scene", frame = scene, actor = actor }
end

-- =========================================================================
-- Camera State Module Loader
-- =========================================================================
local function requireCameraState()
    CLN.ReplayFrame = CLN.ReplayFrame or {}
    CLN.ReplayFrame.ModelScene = CLN.ReplayFrame.ModelScene or {}
    local mod = CLN.ReplayFrame.ModelScene.CameraState
    if not mod then
        local ok, loaded = pcall(dofile, "Interface\\AddOns\\ChattyLittleNpc\\src\\ReplayFrame\\Renderers\\ModelScene\\CameraState.lua")
        if ok and loaded then
            CLN.ReplayFrame.ModelScene.CameraState = loaded
            mod = loaded
        end
    end
    return mod
end

-- =========================================================================
-- Bounds Helper
-- =========================================================================
local function getBounds(actor)
    if not actor then return end
    local function assign(a,b,c,d,e,f)
        if type(a)=="table" and type(b)=="table" then return a.x or 0,a.y or 0,a.z or 0,b.x or 0,b.y or 0,b.z or 0 end
        if type(a)=="number" and type(f)=="number" then return a,b,c,d,e,f end
    end
    local minX,minY,minZ,maxX,maxY,maxZ
    if actor.GetActiveBoundingBox then local ok,a,b,c,d,e,f = pcall(actor.GetActiveBoundingBox, actor); if ok then minX,minY,minZ,maxX,maxY,maxZ = assign(a,b,c,d,e,f) end end
    if not minX and actor.GetMaxBoundingBox then local ok,a,b,c,d,e,f = pcall(actor.GetMaxBoundingBox, actor); if ok then minX,minY,minZ,maxX,maxY,maxZ = assign(a,b,c,d,e,f) end end
    if not minX and actor.GetModelBounds then local ok,a,b,c,d,e,f = pcall(actor.GetModelBounds, actor); if ok then minX,minY,minZ,maxX,maxY,maxZ = assign(a,b,c,d,e,f) end end
    if not minX then return end
    local cx,cy,cz = (minX+maxX)*0.5,(minY+maxY)*0.5,(minZ+maxZ)*0.5
    local sx,sy,sz = math.abs(maxX-minX), math.abs(maxY-minY), math.abs(maxZ-minZ)
    return { center={x=cx,y=cy,z=cz}, size={x=sx,y=sy,z=sz} }
end

-- =========================================================================
-- Public Attach (Simplified API Only)
-- =========================================================================
function M.Attach(host, backend)
        host._backend = backend
        host._zoom = host._zoom or 0.65
        host._compBias = host._compBias ~= nil and host._compBias or 0.25
        host._autoFaceCamera = host._autoFaceCamera ~= false

        local CamState = requireCameraState()
        if not CamState then dbg("host", "CameraState missing; renderer inactive") return end

        function host:_DebugLog(cat, fmt, ...) dbg(cat or "misc", fmt, ...) end
        function host:GetBounds() return getBounds(backend.actor) end
        function host:GetFovV() local f = safeCall(backend.frame, "GetCameraFieldOfView") or 0.8; if f<=0.05 or f>=3 then f=0.8 end; return f end
        function host:GetAspect() local w,h = self:GetSize(); if not h or h==0 then return 1 end; return w/h end

        function host:_ApplyCameraLookAt(px,py,pz,tx,ty,tz)
            if not backend.frame then return end
            
            dbg("camera", "_ApplyCameraLookAt: pos=(%.4f,%.4f,%.4f) target=(%.4f,%.4f,%.4f)", 
                px or 0, py or 0, pz or 0, tx or 0, ty or 0, tz or 0)
            
            safeCall(backend.frame, "SetCameraPosition", px,py,pz)
            
            -- Calculate forward vector (camera to target)
            local fx,fy,fz = tx-px, ty-py, tz-pz
            local len = math.sqrt(fx*fx+fy*fy+fz*fz)
            
            dbg("camera", "  Forward vector (unnormalized): (%.4f,%.4f,%.4f) len=%.4f", fx, fy, fz, len)
            
            if len<1e-6 then 
                fx,fy,fz=0,1,0
                dbg("camera", "  Forward vector too short, using default (0,1,0)")
            else 
                fx,fy,fz=fx/len,fy/len,fz/len
                dbg("camera", "  Forward vector (normalized): (%.4f,%.4f,%.4f)", fx, fy, fz)
            end
            
            -- Calculate right vector (cross product of world up and forward)
            local upX,upY,upZ = 0,0,1
            local dot = fx*upX+fy*upY+fz*upZ
            if math.abs(dot) > 0.999 then 
                upX,upY,upZ=0,1,0
                dbg("camera", "  World up nearly parallel to forward (dot=%.4f), using fallback (0,1,0)", dot)
            end
            
            -- Right = world_up × forward
            local rx,ry,rz = upY*fz - upZ*fy, upZ*fx - upX*fz, upX*fy - upY*fx
            local rl = math.sqrt(rx*rx+ry*ry+rz*rz)
            
            dbg("camera", "  Right vector (unnormalized): (%.4f,%.4f,%.4f) len=%.4f", rx, ry, rz, rl)
            
            if rl>1e-6 then 
                rx,ry,rz=rx/rl,ry/rl,rz/rl
                dbg("camera", "  Right vector (normalized): (%.4f,%.4f,%.4f)", rx, ry, rz)
            else 
                rx,ry,rz=1,0,0
                dbg("camera", "  Right vector too short, using default (1,0,0)")
            end
            
            -- Up = right × forward
            local ux,uy,uz = ry*fz - rz*fy, rz*fx - rx*fz, rx*fy - ry*fx
            dbg("camera", "  Up vector: (%.4f,%.4f,%.4f)", ux, uy, uz)
            
            local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
            if MS and MS.CameraController and MS.CameraController.setOrientation then
                MS.CameraController.setOrientation(backend.frame, rx,ry,rz, ux,uy,uz, fx,fy,fz)
            elseif backend.frame.SetCameraOrientationByAxisVectors then
                safeCall(backend.frame, "SetCameraOrientationByAxisVectors", rx,ry,rz, ux,uy,uz, fx,fy,fz)
            end
        end

        function host:_ApplyClipsCurrent()
            local cam = host._cam; if not cam then return end
            local b = host._lastBounds or host:GetBounds(); if b then host._lastBounds = b end
            local depthHalf = b and b.size.y*0.5 or 0.5
            local dist = cam.dist or 2.5
            local nearC = math.max(0.05, 0.02 * dist)
            local farC  = math.max(40, dist + depthHalf + (b and b.size.z or 1)*(cam.padFrac or 0.12) + 20)
            
            dbg("camera", "_ApplyClipsCurrent: dist=%.4f depthHalf=%.4f nearC=%.4f farC=%.4f", 
                dist, depthHalf, nearC, farC)
            
            local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
            if MS and MS.CameraController and MS.CameraController.setNearClip then
                MS.CameraController.setNearClip(backend.frame, nearC)
            else
                safeCall(backend.frame, "SetCameraNearClip", nearC)
            end
            safeCall(backend.frame, "SetCameraFarClip", farC)
        end

        function host:FrameFullBodyFront(paddingFrac)
            local cam = CamState.ensure(self)
            local pad = tonumber(paddingFrac) or cam.padFrac or 0.12
            cam.padFrac = pad
            
            dbg("framing", "FrameFullBodyFront: paddingFrac=%.4f", pad)
            
            local b = self:GetBounds()
            if not b then
                dbg("framing", "  No bounds available, using default humanoid bounds")
                -- Fallback: use default humanoid NPC bounds (average height ~1.8 units)
                b = {
                    center = { x = 0, y = 0, z = 0.9 },
                    size = { x = 1.0, y = 0.6, z = 1.8 }
                }
            end
            
            -- Validate and enforce minimum bounds to prevent extreme zoom
            if b.size.x < 0.1 then 
                dbg("framing", "  Width too small (%.4f), using default 1.0", b.size.x)
                b.size.x = 1.0 
            end
            if b.size.y < 0.1 then 
                dbg("framing", "  Depth too small (%.4f), using default 0.6", b.size.y)
                b.size.y = 0.6 
            end
            if b.size.z < 0.1 then 
                dbg("framing", "  Height too small (%.4f), using default 1.8", b.size.z)
                b.size.z = 1.8 
            end
            end
            
            self._lastBounds = b
            dbg("framing", "  Bounds center=(%.4f,%.4f,%.4f) size=(%.4f,%.4f,%.4f)", 
                b.center.x, b.center.y, b.center.z, b.size.x, b.size.y, b.size.z)
            
            cam.vfov = self:GetFovV(); cam.aspect = self:GetAspect()
            cam.targetX, cam.targetY, cam.targetZ = b.center.x, b.center.y, b.center.z
            self._camBaseZ = b.center.z
            
            dbg("framing", "  Camera FOV vfov=%.4f (%.1f deg) aspect=%.4f", 
                cam.vfov, math.deg(cam.vfov), cam.aspect)
            
            local vfov = cam.vfov; local hfov = 2*math.atan(math.tan(vfov*0.5)*math.max(1e-3, cam.aspect))
            dbg("framing", "  Calculated hfov=%.4f (%.1f deg)", hfov, math.deg(hfov))
            
            -- Apply padding and enforce minimum half-sizes to prevent extreme zoom
            local MIN_HALF_SIZE = 0.3  -- Minimum half-size for reasonable framing
            local halfH = math.max(MIN_HALF_SIZE, (b.size.z*0.5)*(1+pad))
            local halfW = math.max(MIN_HALF_SIZE, (b.size.x*0.5)*(1+pad))
            
            dbg("framing", "  Padded half-extents: halfW=%.4f halfH=%.4f", halfW, halfH)
            
            local distV = halfH / math.max(1e-5, math.tan(vfov*0.5))
            local distH = halfW / math.max(1e-5, math.tan(hfov*0.5))
            cam.dist = math.max(0.5, distV, distH)
            
            dbg("framing", "  Distance calc: distV=%.4f distH=%.4f -> final dist=%.4f", 
                distV, distH, cam.dist)
            
            local compBias = self._compBias or 0.25
            local halfView = cam.dist * math.tan(vfov*0.5)
            local slack = math.max(0, halfView - (b.size.z*0.5))
            cam.targetZ = b.center.z + compBias * slack
            
            dbg("framing", "  Composition: compBias=%.4f halfView=%.4f slack=%.4f targetZ=%.4f", 
                compBias, halfView, slack, cam.targetZ)
            
            local sign = (self._camDirY and self._camDirY < 0) and -1 or 1
            cam.axisX, cam.axisY, cam.axisZ = 0, sign, 0
            self._camDirY = sign; self._camAxis = sign>0 and "Y+" or "Y-"
            
            dbg("framing", "  Camera axis: %s direction=(%.0f,%.0f,%.0f)", 
                self._camAxis, cam.axisX, cam.axisY, cam.axisZ)
            
            if self._autoFaceCamera ~= false and backend.actor and backend.actor.SetYaw then
                pcall(backend.actor.SetYaw, backend.actor, (sign>0) and 0 or math.pi)
                self._frontYaw = (sign>0) and 0 or math.pi
                dbg("framing", "  Actor yaw set to %.4f rad (%.1f deg)", 
                    self._frontYaw, math.deg(self._frontYaw))
            end
            CamState.update(self, "frame-fullbody")
            dbg("framing", "SimpleFrame dist=%.2f pad=%.2f size=(%.2f,%.2f,%.2f)", cam.dist, pad, b.size.x, b.size.y, b.size.z)
        end

        function host:SetPortraitZoom(v)
            local cam = CamState.ensure(self)
            self._zoom = tonumber(v) or self._zoom or 0.65
            cam.dist = math.max(1.2, 3.2 - (self._zoom * 2.6))
            CamState.update(self, "zoom")
        end
        function host:GetPortraitZoom() return self._zoom or 0.65 end

        function host:SetPosition(_,_,z)
            local cam = CamState.ensure(self)
            local tz = tonumber(z); if not tz then return end
            cam.targetZ = tz; self._camBaseZ = tz
            CamState.update(self, "panZ")
        end

        function host:SetActorYaw(yaw)
            local val = tonumber(yaw) or 0
            if backend.actor and backend.actor.SetYaw then pcall(backend.actor.SetYaw, backend.actor, val) end
              self._frontYaw = val
        end
        function host:GetActorYaw()
            if backend.actor and backend.actor.GetYaw then local ok,y = pcall(backend.actor.GetYaw, backend.actor); if ok and type(y)=="number" then return y end end
            return self._frontYaw or 0
        end
        function host:FlipFacing() self:SetActorYaw((self._frontYaw or 0)+math.pi) end
        function host:FaceCamera()
            local cam = self._cam; if not cam or self._autoFaceCamera==false then return end
            local px = cam.targetX + cam.axisX * cam.dist
            local py = cam.targetY + cam.axisY * cam.dist
            local dx,dy = px-cam.targetX, py-cam.targetY
            self:SetActorYaw(atan2(dy, dx))
        end

        do
            local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
            if MS and MS.AnimationController and not host._animCtrl then
                host._animCtrl = MS.AnimationController.new()
            end
        end
        function host:SetAnimation(animId)
            self._lastAnimId = animId
            
            -- Use active controller to handle loading state automatically
            if self._animCtrl and self._animCtrl.setDesiredAndApply then
                self._animCtrl:setDesiredAndApply(backend.actor, animId)
            elseif self._animCtrl and self._animCtrl.setDesired then
                -- Fallback to old behavior if new method not available
                self._animCtrl:setDesired(animId)
                if backend.actor and backend.actor.SetAnimation then
                    local okL, loaded = backend.actor.IsLoaded and pcall(backend.actor.IsLoaded, backend.actor)
                    if (okL and loaded) or not backend.actor.IsLoaded then 
                        pcall(backend.actor.SetAnimation, backend.actor, animId) 
                    end
                end
            else
                -- No controller, direct application
                if backend.actor and backend.actor.SetAnimation then
                    local okL, loaded = backend.actor.IsLoaded and pcall(backend.actor.IsLoaded, backend.actor)
                    if (okL and loaded) or not backend.actor.IsLoaded then 
                        pcall(backend.actor.SetAnimation, backend.actor, animId) 
                    end
                end
            end
        end
        function host:GetAnimation() return self._lastAnimId end
        function host:SetPaused(b) safeCall(backend.actor, "SetPaused", b and true or false) end

        function host:OnModelLoadedOnce(cb)
            if type(cb) ~= "function" then return end
            local a = backend.actor; if not a or not a.IsLoaded then return end
            local ok, loaded = pcall(a.IsLoaded, a)
            if ok and loaded then cb(self); return end
            local function poll()
                local ok2,l2 = pcall(a.IsLoaded, a)
                if ok2 and l2 then cb(self); return true end
                return false
            end
            if C_Timer and C_Timer.NewTicker then
                local t; t = C_Timer.NewTicker(0.05, function() if poll() and t and t.Cancel then t:Cancel() end end)
            elseif C_Timer and C_Timer.After then
                local function loop() if not poll() then C_Timer.After(0.05, loop) end end; C_Timer.After(0.05, loop)
            end
        end

        function host:SetDisplayInfo(displayID)
            local a = backend.actor; if not (a and a.SetModelByCreatureDisplayID) then return end
            safeCall(a, "SetModelByCreatureDisplayID", displayID, false)
            self:OnModelLoadedOnce(function()
                self:FrameFullBodyFront(0.12)
                -- Apply animation with verification for reliability
                if self._animCtrl then
                    if self._animCtrl.applyWithVerification then
                        self._animCtrl:applyWithVerification(a, {
                            maxAttempts = 3,
                            attemptDelay = 0.05
                        })
                    elseif self._animCtrl.apply then
                        self._animCtrl:apply(a)
                    end
                end
            end)
        end

        function host:SetUnit(unit)
            local a = backend.actor; if not (a and a.SetModelByUnit) then return end
            safeCall(a, "SetModelByUnit", unit)
            self:OnModelLoadedOnce(function() self:FrameFullBodyFront(0.12) end)
        end

        function host:ClearModel() safeCall(backend.actor, "ClearModel") end
        function host:ApplyPreset(name)
            if tostring(name or "FullBody") == "FullBody" then return self:FrameFullBodyFront(0.12) end
        end

        if host.HookScript then
            host:HookScript("OnShow", function() safeCall(backend.frame, "Show"); safeCall(backend.actor, "Show") end)
            host:HookScript("OnHide", function() safeCall(backend.actor, "Hide"); safeCall(backend.frame, "Hide") end)
        end
    end

    return M

