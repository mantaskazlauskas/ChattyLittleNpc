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

local function projectPoint(scene, x, y, z)
    local ok, px, py
    if NS.Diagnostics and NS.Diagnostics.projectPoint then
        ok, px, py = NS.Diagnostics.projectPoint(scene, x, y, z)
    else
        local s, a, b = pcall(scene.Project3DPointTo2D, scene, x, y, z)
        ok = s and type(a) == "number" and type(b) == "number"
        px, py = a, b
    end
    return ok, px, py
end

--- Measure projected region bounds and coverage.
--- @return boolean ok, table metrics
function PV.Measure(scene, worldRegion, frameW, frameH)
    if not (scene and scene.Project3DPointTo2D) then return false, {} end
    if not worldRegion then return false, {} end
    local fw = tonumber(frameW) or 1
    local fh = tonumber(frameH) or 1
    if fw < 1 or fh < 1 then return false, {} end

    local halfW = (worldRegion.fitWidth or 1) * 0.5
    local lo = worldRegion.visibleLo or 0
    local hi = worldRegion.visibleHi or 1
    local tx = worldRegion.targetX or 0
    local ty = worldRegion.targetY or 0
    local tz = worldRegion.targetZ or 0
    local focusZ = worldRegion.focusZ or tz

    local points = {
        { tx - halfW, ty, lo },
        { tx + halfW, ty, lo },
        { tx - halfW, ty, hi },
        { tx + halfW, ty, hi },
    }

    local minPX, minPY = math.huge, math.huge
    local maxPX, maxPY = -math.huge, -math.huge

    for _, p in ipairs(points) do
        local ok, px, py = projectPoint(scene, p[1], p[2], p[3])
        if not ok then return false, {} end
        if px < minPX then minPX = px end
        if px > maxPX then maxPX = px end
        if py < minPY then minPY = py end
        if py > maxPY then maxPY = py end
    end

    local okTarget, targetPX, targetPY = projectPoint(scene, tx, ty, tz)
    local okFocus, _, focusPY = projectPoint(scene, tx, ty, focusZ)
    local okTop, _, topPY = projectPoint(scene, tx, ty, hi)
    local okBottom, _, bottomPY = projectPoint(scene, tx, ty, lo)
    if not (okTarget and okFocus and okTop and okBottom) then return false, {} end

    local projW = maxPX - minPX
    local projH = maxPY - minPY
    local desiredFocusY = worldRegion.desiredFocusY or worldRegion.focusScreenY
    local desiredFocusPY = nil
    local focusErrorPY = nil
    if type(desiredFocusY) == "number" then
        desiredFocusPY = desiredFocusY * fh
        focusErrorPY = focusPY - desiredFocusPY
    end
    return true, {
        minPX = minPX,
        minPY = minPY,
        maxPX = maxPX,
        maxPY = maxPY,
        coverageH = projH / math.max(fh, 1),
        coverageW = projW / math.max(fw, 1),
        targetPX = targetPX,
        targetPY = targetPY,
        focusPY = focusPY,
        topPY = topPY,
        bottomPY = bottomPY,
        desiredFocusPY = desiredFocusPY,
        focusErrorPY = focusErrorPY,
    }
end

--- Project the 4 corners of a target region sub-AABB and measure viewport coverage.
--- @param scene table ModelScene frame with Project3DPointTo2D
--- @param worldRegion table from BodyRegions.ToWorldCoords
--- @param frameW number viewport width in pixels
--- @param frameH number viewport height in pixels
--- @return boolean ok, number coverageH (0..1+), number coverageW (0..1+)
function PV.Verify(scene, worldRegion, frameW, frameH)
    local ok, metrics = PV.Measure(scene, worldRegion, frameW, frameH)
    if not ok then return false, 0, 0 end
    return true, metrics.coverageH or 0, metrics.coverageW or 0
end

--- Apply top-headroom correction by nudging target Z upward if projected top is too close.
--- @param scene table ModelScene frame
--- @param host table ModelSceneHost with _ApplyCameraLookAt
--- @param worldRegion table from BodyRegions.ToWorldCoords
--- @param distance number current camera distance
--- @param frameW number viewport width
--- @param frameH number viewport height
--- @param opts table|nil { topMarginPct = 0.08 }
--- @return table correctedWorldRegion, boolean changed
function PV.AdjustHeadroom(scene, host, worldRegion, distance, frameW, frameH, opts)
    if not (scene and host and worldRegion and host._ApplyCameraLookAt) then return worldRegion, false end
    local fw = tonumber(frameW) or 0
    local fh = tonumber(frameH) or 0
    if fw <= 1 or fh <= 1 then return worldRegion, false end

    local tx = worldRegion.targetX or 0
    local ty = worldRegion.targetY or 0
    local tz = worldRegion.targetZ or 0
    local d = tonumber(distance) or 2.5
    host:_ApplyCameraLookAt(tx, ty + d, tz, tx, ty, tz)

    local ok, metrics = PV.Measure(scene, worldRegion, fw, fh)
    if not ok then return worldRegion, false end

    local topMarginPct = (opts and tonumber(opts.topMarginPct)) or 0.08
    local focusDeadzonePct = (opts and tonumber(opts.focusDeadzonePct)) or 0.015
    local focusMaxAdjustPct = (opts and tonumber(opts.focusMaxAdjustPct)) or 0.35
    local epsilon = 1e-4
    local desiredTopPx = math.max(0, topMarginPct) * fh
    -- ModelScene projected Y gets smaller toward the top of the viewport.
    -- So currentTopPx < desiredTopPx means the head is too close to the top edge.
    local currentTopPx = tonumber(metrics.minPY) or desiredTopPx
    local worldTopSpan = tonumber(worldRegion.targetToTop)
    if worldTopSpan == nil then
        worldTopSpan = (worldRegion.visibleHi or tz) - tz
    end
    local worldBottomSpan = tonumber(worldRegion.targetToBottom)
    if worldBottomSpan == nil then
        worldBottomSpan = tz - (worldRegion.visibleLo or tz)
    end

    local dzTop = 0
    if currentTopPx < desiredTopPx then
        local pxPerWorld = (tonumber(metrics.targetPY) or 0) - currentTopPx
        if pxPerWorld > epsilon and worldTopSpan > epsilon then
            local shiftPx = desiredTopPx - currentTopPx
            dzTop = (shiftPx / pxPerWorld) * worldTopSpan
            if dzTop > epsilon then
                local maxAdjust = worldTopSpan * 0.9
                if dzTop > maxAdjust then dzTop = maxAdjust end
            else
                dzTop = 0
            end
        end
    end

    local dzFocus = 0
    local focusErrorPx = tonumber(metrics.focusErrorPY)
    if focusErrorPx ~= nil and tonumber(metrics.desiredFocusPY) ~= nil then
        local focusDeadzonePx = math.max(0, focusDeadzonePct) * fh
        if math.abs(focusErrorPx) > math.max(focusDeadzonePx, epsilon) then
            local focusTopPx = tonumber(metrics.topPY) or currentTopPx
            local focusPxPerWorld = (tonumber(metrics.targetPY) or 0) - focusTopPx
            if focusPxPerWorld > epsilon and worldTopSpan > epsilon then
                dzFocus = -(focusErrorPx / focusPxPerWorld) * worldTopSpan
                local focusAvailSpan = dzFocus >= 0 and worldTopSpan or worldBottomSpan
                local focusMaxAdjust = math.max(0, focusAvailSpan) * math.max(0, focusMaxAdjustPct)
                if focusMaxAdjust > epsilon then
                    if dzFocus > focusMaxAdjust then dzFocus = focusMaxAdjust end
                    if dzFocus < -focusMaxAdjust then dzFocus = -focusMaxAdjust end
                else
                    dzFocus = 0
                end
                if math.abs(dzFocus) < epsilon then
                    dzFocus = 0
                end
            end
        end
    end

    local dz = dzTop + dzFocus
    if dzTop > 0 and dz < dzTop then
        dz = dzTop
    end
    local correctedTargetZ = tz + dz
    if worldRegion.visibleHi and correctedTargetZ > worldRegion.visibleHi then
        correctedTargetZ = worldRegion.visibleHi
    end
    if worldRegion.visibleLo and correctedTargetZ < worldRegion.visibleLo then
        correctedTargetZ = worldRegion.visibleLo
    end
    if math.abs(correctedTargetZ - tz) < epsilon then
        return worldRegion, false
    end

    local corrected = {}
    for k, v in pairs(worldRegion) do corrected[k] = v end
    local semanticFocusZ = tonumber(worldRegion.focusZ)
    if semanticFocusZ == nil then semanticFocusZ = tz end
    local semanticTop = tonumber(worldRegion.focusToTop)
    if semanticTop == nil then
        semanticTop = math.max(0, (worldRegion.topZ or worldRegion.visibleHi or semanticFocusZ) - semanticFocusZ)
    end
    local semanticBottom = tonumber(worldRegion.focusToBottom)
    if semanticBottom == nil then
        semanticBottom = math.max(0, semanticFocusZ - (worldRegion.bottomZ or worldRegion.visibleLo or semanticFocusZ))
    end
    corrected.targetZ = correctedTargetZ
    local spanTop = (corrected.visibleHi or correctedTargetZ) - correctedTargetZ
    local spanBottom = correctedTargetZ - (corrected.visibleLo or correctedTargetZ)
    corrected.focusZ = semanticFocusZ
    corrected.focusToTop = semanticTop
    corrected.focusToBottom = semanticBottom
    corrected.targetToTop = spanTop
    corrected.targetToBottom = spanBottom
    corrected.headroomSpan = spanTop
    corrected.chinroomSpan = spanBottom
    log(
        "AdjustHeadroom: topPx=%.1f->%.1f focusErrPx=%.1f dzTop=%.3f dzFocus=%.3f shiftDz=%.3f",
        currentTopPx,
        desiredTopPx,
        focusErrorPx or 0,
        dzTop,
        dzFocus,
        correctedTargetZ - tz
    )
    return corrected, true
end

--- Conservatively refine camera distance for projected coverage.
--- Keeps initial distance when coverage is already acceptable; only zooms out when too close.
--- Calls host:_ApplyCameraLookAt internally; restores the best-found distance.
--- @param scene table ModelScene frame
--- @param host table ModelSceneHost with _ApplyCameraLookAt
--- @param worldRegion table from BodyRegions.ToWorldCoords
--- @param initialDist number starting camera distance
--- @param frameW number viewport width
--- @param frameH number viewport height
--- @return number refined distance
function PV.RefineDistance(scene, host, worldRegion, initialDist, frameW, frameH)
    if not (host and worldRegion) then return initialDist end
    local MAX_ACCEPT = 0.85
    local MAX_ITER = 4
    local ZOOM_OUT_STEP = 1.2

    local best = tonumber(initialDist) or 2.5
    local d = best
    local tx = worldRegion.targetX or 0
    local ty = worldRegion.targetY or 0
    local tz = worldRegion.targetZ or 0
    local function applyDistance(dist)
        if host._ApplyCameraLookAt then
            host:_ApplyCameraLookAt(tx, ty + dist, tz, tx, ty, tz)
        end
    end

    if not scene then
        applyDistance(best)
        return best
    end

    applyDistance(d)
    local ok, covH, covW = PV.Verify(scene, worldRegion, frameW, frameH)
    if not ok then
        log("RefineDistance: initial projection failed, using d=%.3f", best)
        applyDistance(best)
        return best
    end

    local coverage = math.max(covH, covW)
    log("RefineDistance: initial d=%.3f covH=%.3f covW=%.3f", d, covH, covW)
    if coverage <= MAX_ACCEPT then
        applyDistance(best)
        return best
    end

    for i = 1, MAX_ITER do
        d = d * ZOOM_OUT_STEP
        applyDistance(d)

        ok, covH, covW = PV.Verify(scene, worldRegion, frameW, frameH)
        if not ok then
            log("RefineDistance: projection failed at iter %d, using d=%.3f", i, best)
            break
        end

        coverage = math.max(covH, covW)
        best = d
        log("RefineDistance: iter=%d d=%.3f covH=%.3f covW=%.3f", i, d, covH, covW)
        if coverage <= MAX_ACCEPT then break end
    end

    applyDistance(best)
    return best
end

return PV
