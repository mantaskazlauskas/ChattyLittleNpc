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
    local yaw, pitch = host._yaw or 0, host._pitch or 0
    host._distance = math.max(0.1, tonumber(dist) or (host._distance or 10))
    host._targetX, host._targetY, host._targetZ = tonumber(cx) or 0, tonumber(cy) or 0, tonumber(cz) or 0
    if host._ApplyCamera then host:_ApplyCamera() end
end

-- Public: FitDefault with projector-based tweaks
function FS.FitDefault(host, displayID, padding)
    if not host then return end
    -- Try to shift target slightly below center for nicer composition
    local b = host.GetBounds and host:GetBounds() or nil
    if not b then return end
    local min,max = b.min,b.max
    local cx, cy, cz = (min.x+max.x)*0.5, (min.y+max.y)*0.5, (min.z+max.z)*0.5
    local sz = math.abs((max.z or 0) - (min.z or 0))
    local bias = 0.10 * (sz or 0)
    local dist = computeDistanceFromBounds(host, padding)
    placeCamera(host, dist, cx, cy, cz - bias)
    -- Ensure actor faces the camera
    if host.SetActorYaw then pcall(host.SetActorYaw, host, math.pi) end
    debugf("framing", "FramerScene.FitDefault: dist=%.3f targetZ=%.3f", dist or -1, (cz - bias) or -1)
end

-- Public: Show upper portion (head/shoulders)
function FS.ShowUpper(host, displayID, frac, padding)
    if not host then return end
    local b = host.GetBounds and host:GetBounds() or nil
    if not b then return end
    local min,max = b.min,b.max
    local cx, cy, cz = (min.x+max.x)*0.5, (min.y+max.y)*0.5, (min.z+max.z)*0.5
    local sz = math.abs((max.z or 0) - (min.z or 0))
    local headBias = 0.20 * (sz or 0)
    local useFrac = tonumber(frac) or 0.7
    local vfov = host.GetFovV and host:GetFovV() or 0.8
    local aspect = host.GetAspect and host:GetAspect() or 1.0
    local t = math.tan((vfov) * 0.5)
    local hfov = 2 * math.atan(t * math.max(1e-3, aspect))
    local pad = math.max(0, tonumber(padding) or 0.10)
    local halfH = math.max(1e-3, (sz * useFrac * 0.5) * (1 + pad))
    local halfW = math.max(1e-3, (((max.x-min.x) > 0 and (max.x-min.x) or 1) * 0.5) * (1 + (pad + 0.03)))
    local dH = halfH / math.tan(vfov * 0.5)
    local dW = halfW / math.tan(hfov * 0.5)
    local dist = math.max(dH, dW)
    placeCamera(host, dist, cx, cy, cz + headBias)
    if host.SetActorYaw then pcall(host.SetActorYaw, host, math.pi) end
    debugf("framing", "FramerScene.ShowUpper: frac=%.2f dist=%.3f", useFrac, dist or -1)
end

-- Public: Zoom by a height factor (inverse relationship with distance)
function FS.ZoomToHeightFactor(host, k, padding)
    if not host then return end
    local factor = tonumber(k) or 1.0
    host._distance = math.max(0.1, (host._distance or 10) * factor)
    if host._ApplyCamera then host:_ApplyCamera() end
    debugf("framing", "FramerScene.ZoomToHeightFactor: k=%.3f newD=%.3f", factor, host._distance or -1)
end

-- Public: ProjectFit passthrough that ensures coherent updates
function FS.ProjectFit(host, scale, center)
    if not host then return end
    if scale ~= nil and host.SetActorScale then host:SetActorScale(scale) end
    if center ~= nil and host.SetTarget then host:SetTarget(center) end
    if host._ApplyCamera then host:_ApplyCamera() end
    debugf("projection", "FramerScene.ProjectFit: s=%s center=%s", tostring(scale), tostring(center))
end

return FS
