---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- FramerScene: advanced projector-based fitting for ModelScene backend
-- Provides helpers that accept a host (ModelHost) and optional meta to compute better framing.
-- All functions gracefully fall back if required capabilities are missing.

ReplayFrame.FramerScene = ReplayFrame.FramerScene or {}
local FS = ReplayFrame.FramerScene

local function U()
    return CLN and CLN.Utils
end

local function debugf(cat, fmt, ...)
    local utils = U()
    if not (utils and utils.ShouldLogAnimDebug and utils:ShouldLogAnimDebug(cat) and utils.LogAnimDebug) then return end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    pcall(utils.LogAnimDebug, utils, cat, ok and msg or tostring(fmt))
end

-- Small helpers to read meta from ReplayFrame cache
local function getMetaForCurrent(displayID)
    local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local npcId = cur and cur.npcId or nil
    return ReplayFrame and ReplayFrame.GetModelMeta and ReplayFrame:GetModelMeta(displayID, npcId, false) or nil
end

-- Compute a more stable distance using both H and W at once and add slight composition bias.
local function computeDistanceFromBounds(host, padding)
    if not (host and host.GetBounds and host.GetFovV and host.GetAspect) then return nil end
    local b = host:GetBounds(); if not b then return nil end
    local min, max = b.min, b.max
    local sx = math.abs((max.x or 0) - (min.x or 0))
    local sz = math.abs((max.z or 0) - (min.z or 0))
    local vfov = host:GetFovV() or 0.8
    local aspect = host:GetAspect() or 1.0
    local t = math.tan((vfov) * 0.5)
    local hfov = 2 * math.atan(t * math.max(1e-3, aspect))
    local pad = math.max(0, tonumber(padding) or 0.10)
    local halfH = math.max(1e-3, (sz > 0 and sz * 0.5 or 1) * (1 + pad))
    local halfW = math.max(1e-3, (sx > 0 and sx * 0.5 or 1) * (1 + (pad + 0.03)))
    local dH = halfH / math.tan(vfov * 0.5)
    local dW = halfW / math.tan(hfov * 0.5)
    local dist = math.max(dH, dW)
    return dist
end

-- Place camera using our look-at orbit while preserving actor yaw
local function placeCamera(host, dist, cx, cy, cz)
    if not host then return end
    host._distance = math.max(0.1, tonumber(dist) or (host._distance or 10))
    host._targetX, host._targetY, host._targetZ = tonumber(cx) or 0, tonumber(cy) or 0, tonumber(cz) or 0
    if host._ApplyCamera then host:_ApplyCamera() end
end

local function solveWorldRegionForDisplay(host, displayID, regionName)
    local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
    if not (MS and MS.BodyRegions and MS.BodyRegions.SolveWorldRegion) then return nil, nil end
    local canonEntry = MS.CanonicalBbox and MS.CanonicalBbox.GetCached and displayID and MS.CanonicalBbox.GetCached(displayID)
    if canonEntry and canonEntry.bbox then
        local world, class = MS.BodyRegions.SolveWorldRegion(canonEntry.bbox, regionName, canonEntry.class)
        return world, class
    end
    local b = host and host.GetBounds and host:GetBounds() or nil
    if not b then return nil, nil end
    return MS.BodyRegions.SolveWorldRegion(b, regionName)
end

local function computeDistanceForWorld(host, world, padding)
    if not (host and world) then return nil end
    local MS = CLN.ReplayFrame and CLN.ReplayFrame.ModelScene
    local vfov = host.GetFovV and host:GetFovV() or 0.8
    local aspect = host.GetAspect and host:GetAspect() or 1.0
    local pad = math.max(0, tonumber(padding) or 0.10)
    if MS and MS.BodyRegions and MS.BodyRegions.SolveDistance then
        local dist, details = MS.BodyRegions.SolveDistance(world, vfov, aspect, pad, pad + 0.03)
        return dist, details
    end
    local t = math.tan(vfov * 0.5)
    local hfov = 2 * math.atan(t * math.max(1e-3, aspect))
    local halfH = math.max(1e-3, (world.visibleH * 0.5) * (1 + pad))
    local halfW = math.max(1e-3, (world.fitWidth * 0.5) * (1 + (pad + 0.03)))
    local dH = halfH / math.tan(vfov * 0.5)
    local dW = halfW / math.tan(hfov * 0.5)
    return math.max(dH, dW), nil
end

-- Public: FitDefault with projector-based tweaks
function FS.FitDefault(host, displayID, padding)
    if not host then return end
    if host.FrameRegion then
        host:FrameRegion("bust", padding)
        debugf("framing", "FramerScene.FitDefault(host.FrameRegion)")
        return
    end

    local world, class = solveWorldRegionForDisplay(host, displayID, "bust")
    if not world then
        local dist = computeDistanceFromBounds(host, padding)
        local b = host.GetBounds and host:GetBounds() or nil
        if not (dist and b and b.center) then return end
        placeCamera(host, dist, b.center.x or 0, b.center.y or 0, b.center.z or 0)
        if host.SetActorYaw then pcall(host.SetActorYaw, host, math.pi) end
        debugf("framing", "FramerScene.FitDefault(bounds-fallback): dist=%.3f", dist or -1)
        return
    end

    local dist, solveDetails = computeDistanceForWorld(host, world, padding)
    local aimZ = (solveDetails and solveDetails.aimTargetZ) or world.targetZ or world.focusZ
    placeCamera(host, dist, world.targetX, world.targetY, aimZ)
    if host.SetActorYaw then pcall(host.SetActorYaw, host, math.pi) end
    debugf("framing", "FramerScene.FitDefault: class=%s dist=%.3f focusZ=%.3f targetZ=%.3f", tostring(class), dist or -1, world.focusZ or -1, aimZ or -1)
end

-- Public: Show upper portion (head/shoulders)
function FS.ShowUpper(host, displayID, frac, padding)
    if not host then return end
    if host.FrameRegion then
        host:FrameRegion("upper_body", padding)
        debugf("framing", "FramerScene.ShowUpper(host.FrameRegion)")
        return
    end

    local world, class = solveWorldRegionForDisplay(host, displayID, "upper_body")
    if not world then
        return FS.FitDefault(host, displayID, padding)
    end

    local dist, solveDetails = computeDistanceForWorld(host, world, padding)
    local aimZ = (solveDetails and solveDetails.aimTargetZ) or world.targetZ or world.focusZ
    placeCamera(host, dist, world.targetX, world.targetY, aimZ)
    if host.SetActorYaw then pcall(host.SetActorYaw, host, math.pi) end
    debugf("framing", "FramerScene.ShowUpper: class=%s dist=%.3f focusZ=%.3f targetZ=%.3f frac=%s", tostring(class), dist or -1, world.focusZ or -1, aimZ or -1, tostring(frac))
end

-- Public: Zoom by a height factor (inverse relationship with distance)
function FS.ZoomToHeightFactor(host, k, padding)
    if not host then return end
    local factor = tonumber(k) or 1.0; if factor == 0 then factor = 1.0 end
    host._distance = math.max(0.1, (host._distance or 10) / factor)
    if host._ApplyCamera then host:_ApplyCamera() end
    debugf("framing", "FramerScene.ZoomToHeightFactor: k=%.3f newD=%.3f", factor, host._distance or -1)
end

-- Public: ProjectFit passthrough that ensures coherent updates
function FS.ProjectFit(host, scale, center)
    if not host then return end
    if scale ~= nil and host.SetActorScale then host:SetActorScale(scale) end
    -- Update target coordinates directly so _ApplyCamera positions the camera
    -- at the requested center. Calling delta-based SetTarget before the absolute
    -- _ApplyCamera would discard the center and create a coordinate-space
    -- mismatch between _currentZOffset and the camera snapshot.
    if center ~= nil then
        if center.x ~= nil then host._targetX = tonumber(center.x) end
        if center.y ~= nil then host._targetY = tonumber(center.y) end
        if center.z ~= nil then host._targetZ = tonumber(center.z) end
    end
    if host._ApplyCamera then host:_ApplyCamera() end
    debugf("projection", "FramerScene.ProjectFit: s=%s center=%s", tostring(scale), tostring(center))
end

return FS
