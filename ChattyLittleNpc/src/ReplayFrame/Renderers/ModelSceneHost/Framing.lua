-- ModelSceneHost/Framing.lua - Framing body regions on the ModelScene host.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local M = ReplayFrame.ModelSceneHost

function M.AttachFraming(host, backend, MS)
    -- Frame a named body region using the canonical (idle-pose) bounding box.
    -- Uses canonical bbox when available and seamlessly falls back to live bbox.
    function host:FrameRegion(regionName, paddingFrac)
        paddingFrac = tonumber(paddingFrac) or 0.12
        regionName = regionName or "bust"
        self._lastRegionName = regionName
        -- FrameRegion establishes an authoritative camera placement;
        -- clear any SetModelPosition state so it won't be reapplied on resize.
        self._positioning = nil
        local canonEntry = MS and MS.CanonicalBbox and MS.CanonicalBbox.GetCached
            and self._currentDisplayID and MS.CanonicalBbox.GetCached(self._currentDisplayID)
        local bbox = canonEntry and canonEntry.bbox or self:GetBounds()
        local source = canonEntry and "canonical" or "live"
        self._lastBounds = bbox or self._lastBounds
        if not bbox then
            self:_DebugLog("framing", "FrameRegion(%s): no bbox available, fallback to head", regionName)
            self:_SetShotAngles(nil) -- don't keep the previous shot's angle or facing
            self:FaceCamera()
            return self:PointCameraAtHead()
        end

        local classHint = canonEntry and canonEntry.class or nil
        local world, class, region
        if MS and MS.BodyRegions and MS.BodyRegions.SolveWorldRegion then
            world, class, region = MS.BodyRegions.SolveWorldRegion(bbox, regionName, classHint)
        elseif MS and MS.BodyRegions and MS.BodyRegions.GetRegion and MS.BodyRegions.ToWorldCoords then
            class = classHint or (MS.BodyRegions.Classify and MS.BodyRegions.Classify(bbox) or "tall_humanoid")
            region = MS.BodyRegions.GetRegion(class, regionName)
            world = MS.BodyRegions.ToWorldCoords(bbox, region)
        else
            world = {
                targetX = (bbox.center and bbox.center.x) or 0,
                targetY = (bbox.center and bbox.center.y) or 0,
                targetZ = (bbox.center and bbox.center.z) or 0,
                visibleH = (bbox.size and bbox.size.z) or 1,
                fitWidth = (bbox.size and bbox.size.x) or 1,
                visibleLo = (bbox.min and bbox.min.z) or 0,
                visibleHi = (bbox.max and bbox.max.z) or 1,
            }
            class = "fallback"
        end

        local tuning = self:_GetShotTuning(regionName, class)
        self._lastFrameClass = class
        -- Solve and correct with a level camera; the tuned angle goes on at the end,
        -- so the projection corrections don't compensate for it per model
        self:_SetShotAngles(nil)

        local fov = self:GetFovV()
        local aspect = self:GetAspect()
        local d
        local solveDetails
        if MS and MS.BodyRegions and MS.BodyRegions.SolveDistance then
            d, solveDetails = MS.BodyRegions.SolveDistance(world, fov, aspect, paddingFrac, paddingFrac)
        else
            local tanHalfV = math.tan(fov * 0.5)
            if tanHalfV < 1e-4 then tanHalfV = math.tan(0.4) end
            local hfov = 2 * math.atan(tanHalfV * math.max(1e-3, aspect))
            local padZ = world.visibleH * paddingFrac
            local padX = world.fitWidth * paddingFrac
            local needDistV = ((world.visibleH + 2 * padZ) * 0.5) / tanHalfV
            local needDistH = ((world.fitWidth + 2 * padX) * 0.5) / math.max(1e-6, math.tan(hfov * 0.5))
            d = math.max(needDistV, needDistH)
        end
        d = math.max(d, 1.0)
        if solveDetails and solveDetails.aimTargetZ ~= nil then
            world.targetZ = solveDetails.aimTargetZ
            world.targetToTop = solveDetails.targetToTop
            world.targetToBottom = solveDetails.targetToBottom
        elseif world.targetZ == nil then
            world.targetZ = world.focusZ or ((world.visibleLo or 0) + (world.visibleHi or 0)) * 0.5
        end
        world.boundsCenterX = world.boundsCenterX or world.targetX or 0
        world.cameraTargetX = world.cameraTargetX or world.targetX or world.boundsCenterX

        self._camDist = d
        -- Sync _zoom from geometry distance so AnimZoomTo reads correct baseline
        self._zoom = math.max(0, math.min(1.5, (3.2 - math.max(1.2, d)) / 2.6))
        -- Clear stale _distance to prevent _ApplyCamera from overriding this distance
        self._distance = nil
        local aimTargetZ = world.targetZ or world.focusZ or 0
        local cameraTargetX = world.cameraTargetX or world.targetX or world.boundsCenterX or 0

        -- Apply initial camera from SolveDistance so Project3DPointTo2D is valid
        local px, py, pz = cameraTargetX, world.targetY + d, aimTargetZ
        local tx, ty, tz = cameraTargetX, world.targetY, aimTargetZ
        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)

        -- Projection-based corrections (measure actual rendered position, then adjust)
        local fw, fh = 0, 0
        if self.GetSize then fw, fh = self:GetSize() end
        if MS and MS.ProjectionVerifier and MS.ProjectionVerifier.AdjustHeadroom and backend.frame
            and (tonumber(fw) or 0) > 1 and (tonumber(fh) or 0) > 1 then
            local corrected, changed = MS.ProjectionVerifier.AdjustHeadroom(backend.frame, self, world, d, fw, fh, { topMarginPct = 0.12 })
            if changed and corrected then
                world = corrected
                aimTargetZ = world.targetZ or aimTargetZ
            end
        end
        if MS and MS.ProjectionVerifier and MS.ProjectionVerifier.AdjustHorizontalAnchor and backend.frame
            and (tonumber(fw) or 0) > 1 and (tonumber(fh) or 0) > 1 then
            local corrected, changed = MS.ProjectionVerifier.AdjustHorizontalAnchor(backend.frame, world, fw, fh, {
                leftMarginPct = 0.08,
                maxCoverageW = 0.72,
            })
            if changed and corrected then
                world = corrected
                cameraTargetX = world.cameraTargetX or cameraTargetX
            end
        end

        -- Persist anchor state from the projection-corrected result.
        -- Back-compute the effective "anchor world Z" — the point that maps to
        -- paddingFrac from the viewport top at this distance — from the corrected
        -- aimTargetZ.  When distance changes (breathing, resize), re-derive tz
        -- using: tz = _anchorTop - _anchorFactor * d
        do
            local tanHV = math.tan(fov * 0.5)
            if tanHV < 1e-4 then tanHV = math.tan(0.4) end
            local effectiveAnchorZ = aimTargetZ + (1 - 2 * paddingFrac) * d * tanHV
            self._anchorTop = effectiveAnchorZ
            self._anchorFactor = (1 - 2 * paddingFrac) * tanHV
        end
        self._camBaseZ = aimTargetZ

        px, py, pz = cameraTargetX, world.targetY + d, aimTargetZ
        tx, ty, tz = cameraTargetX, world.targetY, aimTargetZ

        self:_DebugLog("framing", "FrameRegion(%s) source=%s class=%s dist=%.2f zoom=%.3f focusZ=%.2f targetZ=%.2f visH=%.2f fitW=%.2f",
            regionName, source, class, d, self._zoom or -1, world.focusZ or -1, aimTargetZ, world.visibleH, world.fitWidth)

        self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
        self:_UpdateClipPlanesForFit(d, bbox, paddingFrac)
        if self._autoFaceCamera ~= false and backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, (self._frontYaw or math.pi) + (self._shotFacing or 0))
        end
        self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz, dist = d })

        -- Optional: projection verification for ModelScene (refine distance)
        if MS.ProjectionVerifier and MS.ProjectionVerifier.RefineDistance and backend.frame then
            if (tonumber(fw) or 0) > 1 and (tonumber(fh) or 0) > 1 then
                local refined = MS.ProjectionVerifier.RefineDistance(backend.frame, self, world, d, fw, fh)
                if refined and math.abs(refined - d) > 0.05 then
                    self:_DebugLog("framing", "FrameRegion: projection refined dist %.2f -> %.2f", d, refined)
                    d = refined
                    self._camDist = d
                    self._zoom = math.max(0, math.min(1.5, (3.2 - math.max(1.2, d)) / 2.6))
                    -- Re-derive tz from anchor state for the new distance
                    if self._anchorTop and self._anchorFactor then
                        tz = self._anchorTop - self._anchorFactor * d
                    end
                    px, py, pz = tx, ty + d, tz
                    self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
                    self:_UpdateClipPlanesForFit(d, bbox, paddingFrac)
                    self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz, dist = d })
                end
            end
        end

        -- Shot tuning position and zoom, on top of the solved and corrected framing.
        -- Offsets are fractions of the model's height so one setting fits all sizes.
        if tuning then
            self:_SetShotAngles(tuning)
            if self._autoFaceCamera ~= false and backend.actor and backend.actor.SetYaw then
                pcall(backend.actor.SetYaw, backend.actor, (self._frontYaw or math.pi) + (self._shotFacing or 0))
            end
            local h = (bbox.size and bbox.size.z) or 1
            d = d / math.max(0.1, tonumber(tuning.zoom) or 1)
            tz = tz + (tonumber(tuning.height) or 0) * h
            tx = tx + (tonumber(tuning.side) or 0) * h
            px, py, pz = tx, ty + d, tz
            self._camDist = d
            self._zoom = math.max(0, math.min(1.5, (3.2 - math.max(1.2, d)) / 2.6))
            self._camBaseZ = tz
            -- Keep the zoom re-derivation (tz = _anchorTop - _anchorFactor * d) on this spot
            if self._anchorFactor then self._anchorTop = tz + self._anchorFactor * d end
            self:_ApplyCameraLookAt(px, py, pz, tx, ty, tz)
            self:_UpdateClipPlanesForFit(d, bbox, paddingFrac)
            self:_UpdateSnapshot({ tx = tx, ty = ty, tz = tz, px = px, py = py, pz = pz, dist = d })
        end

        self:_LogFrameDiagnostics(regionName, source, class, bbox, world, d, fw, fh)
        if self._DumpState then self:_DumpState("after-FrameRegion/" .. regionName) end
    end

    -- Smooth transition to a named body region (delegates to AnimPanTo/AnimZoomTo)
    function host:TransitionToRegion(regionName, duration)
        regionName = regionName or "bust"
        self._lastRegionName = regionName
        -- Animated transition replaces any SetModelPosition placement
        -- and invalidates stale anchor state so zoom animation doesn't fight pan
        self._positioning = nil
        self._anchorTop = nil
        self._anchorFactor = nil
        local canonEntry = MS and MS.CanonicalBbox and MS.CanonicalBbox.GetCached
            and self._currentDisplayID and MS.CanonicalBbox.GetCached(self._currentDisplayID)
        if not (canonEntry and MS.BodyRegions) then
            return self:FrameFullBodyFront_Immediate(0.12)
        end

        local cbox = canonEntry.bbox
        local class = canonEntry.class or "tall_humanoid"
        local region = MS.BodyRegions.GetRegion(class, regionName)
        local world = MS.BodyRegions.ToWorldCoords(cbox, region)

        local fov = self:GetFovV()
        local aspect = self:GetAspect()
        local d
        local solveDetails
        if MS and MS.BodyRegions and MS.BodyRegions.SolveDistance then
            d, solveDetails = MS.BodyRegions.SolveDistance(world, fov, aspect, 0.12, 0.12)
        else
            local tanHalfV = math.tan(fov * 0.5)
            if tanHalfV < 1e-4 then tanHalfV = math.tan(0.4) end
            local hfov = 2 * math.atan(tanHalfV * math.max(1e-3, aspect))
            local padZ = world.visibleH * 0.12
            local padX = world.fitWidth * 0.12
            local needDistV = ((world.visibleH + 2 * padZ) * 0.5) / tanHalfV
            local needDistH = ((world.fitWidth + 2 * padX) * 0.5) / math.max(1e-6, math.tan(hfov * 0.5))
            d = math.max(needDistV, needDistH)
        end
        d = math.max(d, 1.0)
        local aimTargetZ = (solveDetails and solveDetails.aimTargetZ) or world.targetZ or world.focusZ or 0
        -- Same shot tuning as FrameRegion, so the transition ends on the tuned spot
        local tuning = self:_GetShotTuning(regionName, class)
        self:_SetShotAngles(tuning)
        if tuning then
            d = d / math.max(0.1, tonumber(tuning.zoom) or 1)
            aimTargetZ = aimTargetZ + (tonumber(tuning.height) or 0) * ((cbox.size and cbox.size.z) or 1)
        end

        local dur = tonumber(duration) or 0.3
        CLN.ReplayFrame:AnimPanTo(aimTargetZ, dur)
        -- Convert geometry distance to zoom-space for AnimZoomTo
        local zoom = math.max(0, math.min(1.5, (3.2 - math.max(1.2, d)) / 2.6))
        CLN.ReplayFrame:AnimZoomTo(zoom, dur)
        self:_DebugLog("framing", "TransitionToRegion(%s) dist=%.2f focusZ=%.2f targetZ=%.2f dur=%.2f", regionName, d, world.focusZ or -1, aimTargetZ, dur)
    end

    -- Public entry point routed through coordinator
    function host:FrameFullBodyFront(paddingFrac)
        return self:_RequestAutoFrame(paddingFrac, { force = true, reason = "explicit" })
    end
end
