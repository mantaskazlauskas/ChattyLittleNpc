-- ModelSceneHost/Camera.lua - Animation and camera control on the ModelScene host.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local M = ReplayFrame.ModelSceneHost

function M.AttachCamera(host, backend, MS)
    -- Animation
    function host:SetAnimation(animId)
        self._lastAnimId = animId
        if self._animCtrl and self._animCtrl.setDesired then
            self._animCtrl:setDesired(animId)
        end
        
        -- Respect debug no-op mode (global portrait state; a preview host ignores it)
        local r = ReplayFrame
        if r and r:_NoAnimDebugEnabled() and not self._isPreview then return end
        
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

    --- Whether the loaded actor has an animation. nil when unknown (no API, or
    --- the actor hasn't loaded yet), which callers treat as supported.
    function host:HasAnimation(animId)
        local a = backend.actor
        if not (a and a.HasAnimation) then return nil end
        if a.IsLoaded then
            local okL, loaded = pcall(a.IsLoaded, a)
            if not (okL and loaded) then return nil end
        end
        local ok, has = pcall(a.HasAnimation, a, animId)
        if not ok or type(has) ~= "boolean" then return nil end
        return has
    end

    -- Camera and positioning
    function host:SetPortraitZoom(v)
        self._zoom = tonumber(v) or self._zoom or 0.65
        local d = math.max(1.2, 3.2 - (self._zoom * 2.6))
        self._camDist = d
        -- Preserve current camera target instead of resetting to head.
        -- PointCameraAtHead reads animated bounds which shift during
        -- emote animations, causing the camera to drift away from the
        -- intended framing (e.g., sliding down to feet during a bow).
        local s = self._lastCamSnapshot or {}
        if s.tx and s.ty and s.tz then
            local tz = s.tz
            -- Re-derive tz from anchor state so the head stays at the top
            -- even when breathing or resize changes the camera distance.
            if self._anchorTop and self._anchorFactor then
                tz = self._anchorTop - self._anchorFactor * d
            end
            local px, py, pz = s.tx, s.ty + d, tz
            self:_ApplyCameraLookAt(px, py, pz, s.tx, s.ty, tz)
            self:_UpdateSnapshot({ px = px, py = py, pz = pz, tz = tz })
        else
            self:PointCameraAtHead()
        end
    end
    
    function host:GetPortraitZoom()
        return self._zoom or 0.65
    end
    
    function host:PointCameraAtHead()
        if backend.kind ~= "scene" or not backend.frame then return end
        self._anchorTop = nil
        self._anchorFactor = nil
        self._positioning = nil
        local b = self:GetBounds()
        local baseX, baseY, baseZ
        if b and MS and MS.BodyRegions and MS.BodyRegions.SolveWorldRegion then
            local world = MS.BodyRegions.SolveWorldRegion(b, "head")
            baseX, baseY, baseZ = world.targetX, world.targetY, world.targetZ
        else
            baseX = (b and b.center and b.center.x) or 0
            baseY = (b and b.center and b.center.y) or 0
            if b and b.min and b.max then
                baseZ = b.min.z + ((b.max.z - b.min.z) * 0.92)
            else
                local s = self._lastCamSnapshot or {}
                baseZ = s.tz or (self._camBaseZ or 1.0)
            end
        end
        self._camBaseZ = baseZ
        local d = self._camDist or 2.5
        local px, py, pz = baseX, baseY + d, baseZ
        local tx, ty, tz = baseX, baseY, baseZ
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        -- Persist snapshot for subsequent operations (zoom/pan)
        self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz })
        self:_RefreshFrameDiagnostics("head", "point", d, tx, ty, tz)
    end

    -- Apply camera from explicit _distance/_targetX/Y/Z (used by FramerScene)
    function host:_ApplyCamera()
        if backend.kind ~= "scene" or not backend.frame then return end
        local tx = self._targetX or 0
        local ty = self._targetY or 0
        local tz = self._targetZ or (self._camBaseZ or 1.0)
        local d = self._distance or self._camDist or 2.5
        -- Place camera along +Y axis at distance from target (same convention as PointCameraAtHead)
        local px, py, pz = tx, ty + d, tz
        self._camBaseZ = tz
        self._camDist = d
        -- Keep _zoom consistent so GetPortraitZoom won't desync AnimZoomTo
        self._zoom = math.max(0, math.min(1.5, (3.2 - math.max(1.2, d)) / 2.6))
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        if self._lastBounds then self:_UpdateClipPlanesForFit(d, self._lastBounds, 0.12) end
        self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz })
    end

    function host:FaceCamera()
        -- Preserve user camera placement; only rotate actor to face forward
        if self._autoFaceCamera ~= false and backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, (self._frontYaw or math.pi) + (self._shotFacing or 0))
        end
    end

    --- Camera tuning for a shot: the Portrait Tuner's live preview, else saved/default.
    function host:_GetShotTuning(regionName, class)
        if self._tuningPreview then return self._tuningPreview end
        return ReplayFrame.GetShotTuning and ReplayFrame:GetShotTuning(regionName, class) or nil
    end

    --- Set camera angle and model facing from a tuning (nil clears them).
    function host:_SetShotAngles(tuning)
        self._camOrbit = tuning and { pitch = math.rad(tonumber(tuning.pitch) or 0), yaw = math.rad(tonumber(tuning.orbit) or 0) } or nil
        self._shotFacing = tuning and math.rad(tonumber(tuning.facing) or 0) or 0
    end

    -- Enable panning for ModelScene host by explicitly setting camera target
    function host:SetTarget(vec3)
        if backend.kind ~= "scene" or not backend.frame then return end
        vec3 = vec3 or {}
        -- Only mark as user-controlled if NOT called from internal animation pan
        if not self._internalPanActive then
            self._userControlledCamera = true
            -- Manual pan invalidates the top-anchor — don't snap back on zoom/resize.
            self._anchorTop = nil
            self._anchorFactor = nil
            -- Manual pan overrides SetModelPosition — clear so resize doesn't reapply stale positioning
            self._positioning = nil
        end
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
        -- Shot tuning camera angle: every caller places the camera on the +Y axis
        -- in front of the target, so orbit it here (keeping the distance) and the
        -- angle survives zooms, pans and breathing.
        local orbit = self._camOrbit
        if orbit and (orbit.pitch ~= 0 or orbit.yaw ~= 0) then
            local d = math.sqrt(((px or 0) - (tx or 0))^2 + ((py or 0) - (ty or 0))^2 + ((pz or 0) - (tz or 0))^2)
            local cp = math.cos(orbit.pitch)
            px = (tx or 0) + d * cp * math.sin(orbit.yaw)
            py = (ty or 0) + d * cp * math.cos(orbit.yaw)
            pz = (tz or 0) + d * math.sin(orbit.pitch)
        end

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
    function host:FitDistanceForCurrentTarget(paddingFrac)
        -- Use canonical bbox when available (same source as FrameRegion)
        local canonEntry = MS and MS.CanonicalBbox and MS.CanonicalBbox.GetCached
            and self._currentDisplayID and MS.CanonicalBbox.GetCached(self._currentDisplayID)
        local b = canonEntry and canonEntry.bbox or self:GetBounds()
        if not b then return end
        local classHint = canonEntry and canonEntry.class or nil
        local fov = self:GetFovV()
        local aspect = self:GetAspect()
        local usePad = tonumber(paddingFrac) or 0.12
        local regionName = self._lastRegionName or "bust"
        local world
        if MS and MS.BodyRegions and MS.BodyRegions.SolveWorldRegion then
            world = MS.BodyRegions.SolveWorldRegion(b, regionName, classHint)
        end
        world = world or {
            visibleH = (b.size.z or 1),
            fitWidth = (b.size.x or 1),
        }
        local d
        if MS and MS.BodyRegions and MS.BodyRegions.SolveDistance then
            d = MS.BodyRegions.SolveDistance(world, fov, aspect, usePad, usePad)
        else
            local padZ = world.visibleH * usePad
            local padX = world.fitWidth * usePad
            local tanHalfV = math.tan((fov / 2))
            if tanHalfV < 1e-4 then tanHalfV = math.tan(0.4) end
            local needDistV = ((world.visibleH + 2 * padZ) * 0.5) / tanHalfV
            local needDistH = ((world.fitWidth + 2 * padX) * 0.5)
            if aspect and aspect > 0.01 then
                needDistH = needDistH / (tanHalfV * aspect)
            else
                needDistH = 0
            end
            d = math.max(needDistV, needDistH)
        end
        d = d or math.max(tonumber(self._camDist) or 1.0, 1.0)
        d = math.max(d, 1.0)
        -- Same tuned zoom as FrameRegion, so the tz re-derivation below stays on the tuned spot
        local tuning = self:_GetShotTuning(regionName, self._lastFrameClass)
        if tuning then d = d / math.max(0.1, tonumber(tuning.zoom) or 1) end
        self._camDist = d
        -- Keep _zoom consistent so GetPortraitZoom won't desync AnimZoomTo
        self._zoom = math.max(0, math.min(1.5, (3.2 - math.max(1.2, d)) / 2.6))
        -- Clear stale _distance to prevent _ApplyCamera from overriding this distance
        self._distance = nil
        -- Preserve last target center if available
        local s = self._lastCamSnapshot or {}
        local tx = s.tx or b.center.x or 0
        local ty = s.ty or b.center.y or 0
        local tz = s.tz or b.center.z or (self._camBaseZ or 1.0)
        -- Re-derive tz from anchor state so the head stays at the top
        -- even when resize changes the camera distance.
        if self._anchorTop and self._anchorFactor then
            tz = self._anchorTop - self._anchorFactor * d
        end
        local px, py, pz = tx, ty + d, tz
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        self:_UpdateClipPlanesForFit(d, b, paddingFrac)
        -- Persist
        self._lastCamSnapshot = self._lastCamSnapshot or {}
        if not self._lastCamSnapshot.sessionId then self._lastCamSnapshot.sessionId = self._sessionId end
        self._lastCamSnapshot.tx, self._lastCamSnapshot.ty, self._lastCamSnapshot.tz = tx, ty, tz
        self._lastCamSnapshot.px, self._lastCamSnapshot.py, self._lastCamSnapshot.pz = px, py, pz
        self:_RefreshFrameDiagnostics(regionName, "refit", d, tx, ty, tz)
    end
    
    -- Immediate framing implementation (called by coordinator)
    function host:FrameFullBodyFront_Immediate(paddingFrac)
        paddingFrac = tonumber(paddingFrac) or 0.12
        -- _portraitRegion is set by ApplyDefaultFit from the frame style and dock side
        self:FrameRegion(self._portraitRegion or "bust", paddingFrac)
        if self._DumpState then self:_DumpState("after-framing") end
    end
end
