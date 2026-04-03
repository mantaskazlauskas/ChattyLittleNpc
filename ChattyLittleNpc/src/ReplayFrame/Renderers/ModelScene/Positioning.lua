local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.Positioning = NS.Positioning or {}
local P = NS.Positioning

P.Anchors = {
    TOP_LEFT = "TOP_LEFT",
    TOP = "TOP",
    TOP_RIGHT = "TOP_RIGHT",
    LEFT = "LEFT",
    CENTER = "CENTER",
    RIGHT = "RIGHT",
    BOTTOM_LEFT = "BOTTOM_LEFT",
    BOTTOM = "BOTTOM",
    BOTTOM_RIGHT = "BOTTOM_RIGHT",
}

local DEFAULT_ANCHOR = P.Anchors.BOTTOM

local ANCHOR_NAMES = {
    P.Anchors.TOP_LEFT,
    P.Anchors.TOP,
    P.Anchors.TOP_RIGHT,
    P.Anchors.LEFT,
    P.Anchors.CENTER,
    P.Anchors.RIGHT,
    P.Anchors.BOTTOM_LEFT,
    P.Anchors.BOTTOM,
    P.Anchors.BOTTOM_RIGHT,
}

local ANCHOR_OFFSETS = {
    TOP_LEFT = { x = 0.0, z = 1.0 },
    TOP = { x = 0.5, z = 1.0 },
    TOP_RIGHT = { x = 1.0, z = 1.0 },
    LEFT = { x = 0.0, z = 0.5 },
    CENTER = { x = 0.5, z = 0.5 },
    RIGHT = { x = 1.0, z = 0.5 },
    BOTTOM_LEFT = { x = 0.0, z = 0.0 },
    BOTTOM = { x = 0.5, z = 0.0 },
    BOTTOM_RIGHT = { x = 1.0, z = 0.0 },
}

local function log(fmt, ...)
    if NS.Diagnostics and NS.Diagnostics.log then
        NS.Diagnostics.log("positioning", fmt, ...)
    end
end

local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function isFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function normalizeAnchor(anchor)
    if ANCHOR_OFFSETS[anchor] then
        return anchor
    end
    return DEFAULT_ANCHOR
end

local function isValidBbox(bbox)
    return bbox
        and bbox.min and bbox.max and bbox.center
        and isFinite(bbox.min.x) and isFinite(bbox.min.z)
        and isFinite(bbox.max.x) and isFinite(bbox.max.z)
        and isFinite(bbox.center.y)
end

local function getDisplayID(host)
    if not host then return nil end
    local displayID = host._currentDisplayID
    if displayID == nil then
        displayID = host._displayID
    end
    return tonumber(displayID)
end

local function getBbox(host)
    local displayID = getDisplayID(host)
    if displayID and NS.CanonicalBbox and NS.CanonicalBbox.GetCached then
        local okEntry, entry = pcall(NS.CanonicalBbox.GetCached, displayID)
        if okEntry and entry and isValidBbox(entry.bbox) then
            return entry.bbox, "canonical", displayID
        end
    end

    if host and host.GetBounds then
        local okBounds, bbox = pcall(host.GetBounds, host)
        if okBounds and isValidBbox(bbox) then
            return bbox, "live", displayID
        end
    end

    return nil, nil, displayID
end

function P.ResolveAnchorPoint(bbox, anchor)
    if not isValidBbox(bbox) then return nil end

    local offsets = ANCHOR_OFFSETS[normalizeAnchor(anchor)]
    local minX = bbox.min.x
    local maxX = bbox.max.x
    local minZ = bbox.min.z
    local maxZ = bbox.max.z
    local ay = bbox.center.y
    local ax = minX + ((maxX - minX) * offsets.x)
    local az = minZ + ((maxZ - minZ) * offsets.z)

    if not (isFinite(ax) and isFinite(ay) and isFinite(az)) then
        return nil
    end

    return ax, ay, az
end

function P.GetAnchorNames()
    local out = {}
    for i = 1, #ANCHOR_NAMES do
        out[i] = ANCHOR_NAMES[i]
    end
    return out
end

function P.SetModelPosition(host, anchor, xPct, yPct)
    if not host then
        log("SetModelPosition: missing host")
        return false
    end

    anchor = normalizeAnchor(anchor)
    xPct = clamp01(xPct)
    yPct = clamp01(yPct)

    local bbox, bboxSource, displayID = getBbox(host)
    if not isValidBbox(bbox) then
        log("SetModelPosition: no bbox available (displayID=%s)", tostring(displayID))
        return false
    end

    local d = tonumber(host._camDist)
    if not (isFinite(d) and d > 0) then
        log("SetModelPosition: invalid camera distance=%s", tostring(host and host._camDist))
        return false
    end

    if type(host.GetFovV) ~= "function" then
        log("SetModelPosition: missing GetFovV")
        return false
    end
    local okFov, fovV = pcall(host.GetFovV, host)
    if not (okFov and isFinite(fovV) and fovV > 0) then
        log("SetModelPosition: invalid fovV=%s", tostring(fovV))
        return false
    end

    if type(host.GetAspect) ~= "function" then
        log("SetModelPosition: missing GetAspect")
        return false
    end
    local okAspect, aspect = pcall(host.GetAspect, host)
    if not (okAspect and isFinite(aspect) and aspect > 0) then
        log("SetModelPosition: invalid aspect=%s", tostring(aspect))
        return false
    end

    local ax, ay, az = P.ResolveAnchorPoint(bbox, anchor)
    if not ax then
        log("SetModelPosition: failed to resolve anchor=%s", tostring(anchor))
        return false
    end

    local halfH = d * math.tan(fovV * 0.5)
    local halfW = halfH * aspect
    if not (isFinite(halfH) and isFinite(halfW)) then
        log("SetModelPosition: invalid viewport half extents halfW=%s halfH=%s", tostring(halfW), tostring(halfH))
        return false
    end

    local tx = ax - halfW * (2 * xPct - 1)
    local tz = az - halfH * (2 * yPct - 1)
    local ty = ay
    local px = tx
    local py = ty + d
    local pz = tz

    if not (isFinite(tx) and isFinite(ty) and isFinite(tz) and isFinite(px) and isFinite(py) and isFinite(pz)) then
        log("SetModelPosition: invalid solved camera values")
        return false
    end

    if type(host._ApplyCameraLookAt) ~= "function" then
        log("SetModelPosition: missing _ApplyCameraLookAt")
        return false
    end
    local okCamera, cameraErr = pcall(host._ApplyCameraLookAt, host, px, py, pz, tx, ty, tz)
    if not okCamera then
        log("SetModelPosition: _ApplyCameraLookAt failed (%s)", tostring(cameraErr))
        return false
    end

    if type(host._UpdateSnapshot) ~= "function" then
        log("SetModelPosition: missing _UpdateSnapshot")
        return false
    end
    local okSnapshot, snapshotErr = pcall(host._UpdateSnapshot, host, {
        tx = tx,
        ty = ty,
        tz = tz,
        px = px,
        py = py,
        pz = pz,
        dist = d,
    })
    if not okSnapshot then
        log("SetModelPosition: _UpdateSnapshot failed (%s)", tostring(snapshotErr))
        return false
    end

    host._camBaseZ = tz
    host._anchorTop = nil
    host._anchorFactor = nil
    host._userControlledCamera = true
    host._positioning = {
        anchor = anchor,
        xPct = xPct,
        yPct = yPct,
    }

    log(
        "SetModelPosition: did=%s bbox=%s anchor=%s xPct=%.3f yPct=%.3f target=(%.2f,%.2f,%.2f) pos=(%.2f,%.2f,%.2f) dist=%.2f",
        tostring(displayID),
        tostring(bboxSource or "?"),
        tostring(anchor),
        xPct,
        yPct,
        tx,
        ty,
        tz,
        px,
        py,
        pz,
        d
    )

    return true
end

function P.ReapplyPosition(host)
    if not (host and host._positioning) then return false end
    local pos = host._positioning
    return P.SetModelPosition(host, pos.anchor, pos.xPct, pos.yPct)
end

function P.ClearPosition(host)
    if not host then return end
    -- Only reset _userControlledCamera if we actually had positioning state.
    -- Otherwise we'd incorrectly clear a manual pan that set the flag independently.
    if host._positioning then
        host._positioning = nil
        host._userControlledCamera = false
    end
end

return P
