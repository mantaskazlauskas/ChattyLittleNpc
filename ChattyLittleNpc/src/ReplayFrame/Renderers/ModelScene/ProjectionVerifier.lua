local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.ProjectionVerifier = NS.ProjectionVerifier or {}
local PV = NS.ProjectionVerifier

local function log(fmt, ...)
    if NS.Diagnostics and NS.Diagnostics.log then
        NS.Diagnostics.log("projection", fmt, ...)
    end
end

--- Project the 4 corners of a target region sub-AABB and measure viewport coverage.
--- @param scene table ModelScene frame with Project3DPointTo2D
--- @param worldRegion table from BodyRegions.ToWorldCoords
--- @param frameW number viewport width in pixels
--- @param frameH number viewport height in pixels
--- @return boolean ok, number coverageH (0..1+), number coverageW (0..1+)
function PV.Verify(scene, worldRegion, frameW, frameH)
    if not (scene and scene.Project3DPointTo2D) then return false, 0, 0 end
    if not worldRegion then return false, 0, 0 end
    local fw = tonumber(frameW) or 1
    local fh = tonumber(frameH) or 1
    if fw < 1 or fh < 1 then return false, 0, 0 end

    local halfW = (worldRegion.fitWidth or 1) * 0.5
    local lo = worldRegion.visibleLo or 0
    local hi = worldRegion.visibleHi or 1
    local tx = worldRegion.targetX or 0
    local ty = worldRegion.targetY or 0

    -- Sample 4 corners of the visible sub-AABB (front face only, at model Y)
    local points = {
        { tx - halfW, ty, lo },
        { tx + halfW, ty, lo },
        { tx - halfW, ty, hi },
        { tx + halfW, ty, hi },
    }

    local minPX, minPY =  math.huge,  math.huge
    local maxPX, maxPY = -math.huge, -math.huge

    for _, p in ipairs(points) do
        local ok, px, py
        if NS.Diagnostics and NS.Diagnostics.projectPoint then
            ok, px, py = NS.Diagnostics.projectPoint(scene, p[1], p[2], p[3])
        else
            local s, a, b = pcall(scene.Project3DPointTo2D, scene, p[1], p[2], p[3])
            ok = s and type(a) == "number" and type(b) == "number"
            px, py = a, b
        end
        if not ok then return false, 0, 0 end
        if px < minPX then minPX = px end
        if px > maxPX then maxPX = px end
        if py < minPY then minPY = py end
        if py > maxPY then maxPY = py end
    end

    local projW = maxPX - minPX
    local projH = maxPY - minPY
    local coverageH = projH / math.max(fh, 1)
    local coverageW = projW / math.max(fw, 1)

    return true, coverageH, coverageW
end

--- Binary search on camera distance to achieve target coverage (70-85% of viewport).
--- Calls host:_ApplyCameraLookAt internally; restores the best-found distance.
--- @param scene table ModelScene frame
--- @param host table ModelSceneHost with _ApplyCameraLookAt
--- @param worldRegion table from BodyRegions.ToWorldCoords
--- @param initialDist number starting camera distance
--- @param frameW number viewport width
--- @param frameH number viewport height
--- @return number refined distance
function PV.RefineDistance(scene, host, worldRegion, initialDist, frameW, frameH)
    if not (scene and host and worldRegion) then return initialDist end
    local TARGET = 0.775     -- midpoint of 70-85%
    local TOL = 0.05         -- ±5%
    local MAX_ITER = 3

    local d = tonumber(initialDist) or 2.5
    local dLo = d * 0.3
    local dHi = d * 3.0
    local best = d

    for i = 1, MAX_ITER do
        -- Temporarily place camera at distance d
        local tx = worldRegion.targetX or 0
        local ty = worldRegion.targetY or 0
        local tz = worldRegion.targetZ or 0
        if host._ApplyCameraLookAt then
            host:_ApplyCameraLookAt(tx, ty + d, tz, tx, ty, tz)
        end

        local ok, covH, covW = PV.Verify(scene, worldRegion, frameW, frameH)
        if not ok then
            log("RefineDistance: projection failed at iter %d, using d=%.3f", i, best)
            break
        end

        local coverage = math.max(covH, covW)
        log("RefineDistance: iter=%d d=%.3f covH=%.3f covW=%.3f", i, d, covH, covW)

        if math.abs(coverage - TARGET) < TOL then
            best = d
            break
        end

        best = d
        if coverage > TARGET then
            dLo = d   -- too close, need more distance
        else
            dHi = d   -- too far, need less distance
        end
        d = (dLo + dHi) * 0.5
    end

    return best
end

return PV
