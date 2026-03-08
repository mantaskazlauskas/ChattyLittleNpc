local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.BodyRegions = NS.BodyRegions or {}
local BR = NS.BodyRegions

-- Semantic body anchors per morphology class (0 = feet, 1 = top).
BR.ANCHORS = {
    tall_humanoid = { feet = 0.00, waist = 0.45, chest = 0.68, shoulders = 0.78, chin = 0.84, eyeLine = 0.92, headTop = 1.00, talkFocus = 0.90 },
    stocky_humanoid = { feet = 0.00, waist = 0.40, chest = 0.63, shoulders = 0.74, chin = 0.80, eyeLine = 0.90, headTop = 1.00, talkFocus = 0.88 },
    wide_beast = { feet = 0.00, waist = 0.30, chest = 0.50, shoulders = 0.62, chin = 0.72, eyeLine = 0.82, headTop = 1.00, talkFocus = 0.76 },
    dragon = { feet = 0.00, waist = 0.35, chest = 0.55, shoulders = 0.67, chin = 0.75, eyeLine = 0.86, headTop = 1.00, talkFocus = 0.80 },
    tiny_critter = { feet = 0.00, waist = 0.35, chest = 0.55, shoulders = 0.70, chin = 0.80, eyeLine = 0.88, headTop = 1.00, talkFocus = 0.75 },
}

BR.REGION_WIDTHS = {
    tall_humanoid = { bust = 0.60, head = 0.40, upper_body = 0.65, full_body = 1.00 },
    stocky_humanoid = { bust = 0.65, head = 0.45, upper_body = 0.70, full_body = 1.00 },
    wide_beast = { bust = 0.80, head = 0.60, upper_body = 0.85, full_body = 1.00 },
    dragon = { bust = 0.70, head = 0.50, upper_body = 0.75, full_body = 1.00 },
    tiny_critter = { bust = 1.00, head = 1.00, upper_body = 1.00, full_body = 1.00 },
}

local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function solveAimTargetZ(focusZ, focusY, distance, fovV)
    local zFocus = tonumber(focusZ) or 0
    local yFocus = clamp(tonumber(focusY) or 0.5, 0.05, 0.95)
    local dist = math.max(0, tonumber(distance) or 0)
    local vfov = tonumber(fovV) or 0.8
    local tanHalfV = math.tan(vfov * 0.5)
    if tanHalfV < 1e-4 then tanHalfV = math.tan(0.4) end
    local halfSpanAtTarget = dist * tanHalfV
    return zFocus + halfSpanAtTarget * ((2 * yFocus) - 1)
end

function BR.SolveAimTargetZ(focusZ, focusY, distance, fovV)
    return solveAimTargetZ(focusZ, focusY, distance, fovV)
end

function BR.GetAnchors(class)
    return BR.ANCHORS[class] or BR.ANCHORS.tall_humanoid
end

local function buildRegionFromAnchors(anchors, widths, regionName)
    local spec
    if regionName == "head" then
        spec = {
            focusAnchor = "eyeLine",
            bottomAnchor = "chin",
            topAnchor = "headTop",
            focusScreenY = 0.57,
            widthKey = "head",
        }
    elseif regionName == "upper_body" then
        spec = {
            focusAnchor = "chest",
            bottomAnchor = "waist",
            topAnchor = "headTop",
            focusScreenY = 0.54,
            widthKey = "upper_body",
        }
    elseif regionName == "full_body" then
        spec = {
            focusAnchor = "waist",
            bottomAnchor = "feet",
            topAnchor = "headTop",
            focusScreenY = 0.50,
            widthKey = "full_body",
        }
    else
        spec = {
            focusAnchor = "talkFocus",
            bottomAnchor = "shoulders",
            topAnchor = "headTop",
            focusScreenY = 0.56,
            widthKey = "bust",
        }
    end

    local focusPct = clamp01(anchors[spec.focusAnchor] or anchors.talkFocus or anchors.eyeLine)
    local bottomPct = clamp01(anchors[spec.bottomAnchor] or anchors.chest)
    local topPct = clamp01(anchors[spec.topAnchor] or anchors.headTop)
    if topPct < bottomPct then topPct, bottomPct = bottomPct, topPct end
    focusPct = clamp(focusPct, bottomPct, topPct)

    local widthFitPct = clamp01(widths[spec.widthKey] or widths.bust or 1)

    return {
        focusAnchor = spec.focusAnchor,
        bottomAnchor = spec.bottomAnchor,
        topAnchor = spec.topAnchor,
        focusAnchorPct = focusPct,
        bottomAnchorPct = bottomPct,
        topAnchorPct = topPct,
        focusScreenY = clamp(spec.focusScreenY, 0.05, 0.95),
        widthFitPct = widthFitPct,

        -- Back-compat fields consumed by existing callers.
        targetPct = focusPct,
        rangeLo = bottomPct,
        rangeHi = topPct,
        shoulderW = widthFitPct,
    }
end

--- Classify a model by its canonical bounding box aspect ratio and height.
--- @param canonBbox table with .size = { x=width, y=depth, z=height }
--- @return string one of "tall_humanoid","stocky_humanoid","wide_beast","dragon","tiny_critter"
function BR.Classify(canonBbox)
    if not (canonBbox and canonBbox.size) then return "tall_humanoid" end
    local w = tonumber(canonBbox.size.x) or 1
    local h = tonumber(canonBbox.size.z) or 1
    local ar = w / math.max(h, 0.01)

    if h < 0.5 then
        return "tiny_critter"
    elseif ar > 1.8 then
        return "wide_beast"
    elseif ar > 1.2 and h > 2.0 then
        return "dragon"
    elseif ar > 0.8 then
        return "stocky_humanoid"
    else
        return "tall_humanoid"
    end
end

--- Look up a named region for a morphology class.
--- Falls back to tall_humanoid if class or region name is unknown.
--- @param class string morphology class from Classify
--- @param regionName string "bust","head","upper_body","full_body"
--- @return table region record
function BR.GetRegion(class, regionName)
    local useClass = class or "tall_humanoid"
    if useClass == "tiny_critter" then
        return {
            focusAnchor = "eyeLine",
            bottomAnchor = "feet",
            topAnchor = "headTop",
            focusAnchorPct = 0.50,
            bottomAnchorPct = 0.00,
            topAnchorPct = 1.00,
            focusScreenY = 0.55,
            widthFitPct = 1.00,
            targetPct = 0.50,
            rangeLo = 0.00,
            rangeHi = 1.00,
            shoulderW = 1.00,
        }
    end
    local anchors = BR.GetAnchors(useClass)
    local widths = BR.REGION_WIDTHS[useClass] or BR.REGION_WIDTHS.tall_humanoid
    return buildRegionFromAnchors(anchors, widths, regionName)
end

--- Convert a body region to world-space coordinates using the canonical bbox.
--- @param canonBbox table the cached idle-pose bounding box
--- @param region table region record from GetRegion
--- @return table world-space targeting data
function BR.ToWorldCoords(canonBbox, region)
    if not (canonBbox and canonBbox.min and canonBbox.size and region) then
        return {
            targetX = 0, targetY = 0, targetZ = 0, visibleH = 1, fitWidth = 1, visibleLo = 0, visibleHi = 1,
            focusZ = 0, bottomZ = 0, topZ = 1, desiredFocusY = 0.55,
            focusToTop = 1, focusToBottom = 0, targetToTop = 1, targetToBottom = 0,
        }
    end
    local minZ   = canonBbox.min.z or 0
    local height = canonBbox.size.z or 1
    local cx     = canonBbox.center.x or 0
    local cy     = canonBbox.center.y or 0

    local focusPct = clamp(region.focusAnchorPct or region.targetPct or 0.5, 0, 1)
    local bottomPct = clamp(region.bottomAnchorPct or region.rangeLo or 0, 0, 1)
    local topPct = clamp(region.topAnchorPct or region.rangeHi or 1, 0, 1)
    if topPct < bottomPct then topPct, bottomPct = bottomPct, topPct end
    focusPct = clamp(focusPct, bottomPct, topPct)

    local focusZ    = minZ + height * focusPct
    local visibleLo = minZ + height * bottomPct
    local visibleHi = minZ + height * topPct
    local visibleH  = visibleHi - visibleLo
    local fitWidthPct = clamp(region.widthFitPct or region.shoulderW or 1, 0, 1)
    local fitWidth  = (canonBbox.size.x or 1) * fitWidthPct
    local desiredFocusY = clamp(region.focusScreenY or 0.55, 0.05, 0.95)

    return {
        targetX   = cx,
        targetY   = cy,
        targetZ   = focusZ,
        visibleH  = visibleH,
        fitWidth  = fitWidth,
        visibleLo = visibleLo,
        visibleHi = visibleHi,
        focusZ = focusZ,
        bottomZ = visibleLo,
        topZ = visibleHi,
        desiredFocusY = desiredFocusY,
        focusToTop = math.max(0, visibleHi - focusZ),
        focusToBottom = math.max(0, focusZ - visibleLo),
        targetToTop = math.max(0, visibleHi - focusZ),
        targetToBottom = math.max(0, focusZ - visibleLo),
    }
end

--- Solve camera distance for composition-driven, asymmetric region framing.
--- @param worldRegion table from ToWorldCoords/SolveWorldRegion
--- @param fovV number vertical field of view in radians
--- @param aspect number viewport aspect ratio
--- @param paddingFrac number|nil composition padding fraction
--- @param widthPaddingFrac number|nil optional separate width padding
--- @return number distance, table details
function BR.SolveDistance(worldRegion, fovV, aspect, paddingFrac, widthPaddingFrac)
    local world = worldRegion or {}
    local vfov = tonumber(fovV) or 0.8
    local viewAspect = math.max(1e-3, tonumber(aspect) or 1.0)
    local tanHalfV = math.tan(vfov * 0.5)
    if tanHalfV < 1e-4 then tanHalfV = math.tan(0.4) end
    local hfov = 2 * math.atan(tanHalfV * viewAspect)

    local pad = math.max(0, tonumber(paddingFrac) or 0.12)
    local widthPad = tonumber(widthPaddingFrac)
    if widthPad == nil then widthPad = pad end
    widthPad = math.max(0, widthPad)
    local padMul = 1 + (2 * pad)

    local focusZ = tonumber(world.focusZ or world.targetZ) or 0
    local topZ = tonumber(world.topZ or world.visibleHi)
    local bottomZ = tonumber(world.bottomZ or world.visibleLo)
    local symmetric = false
    if topZ == nil or bottomZ == nil then
        local half = math.max(0, (tonumber(world.visibleH) or 0) * 0.5)
        topZ = focusZ + half
        bottomZ = focusZ - half
        symmetric = true
    end
    if topZ < bottomZ then topZ, bottomZ = bottomZ, topZ end
    focusZ = clamp(focusZ, bottomZ, topZ)

    local focusY = clamp(world.desiredFocusY or world.focusScreenY or 0.5, 0.05, 0.95)
    local topShare = focusY
    local bottomShare = 1 - focusY
    local topSpan = math.max(0, topZ - focusZ)
    local bottomSpan = math.max(0, focusZ - bottomZ)
    local needDistTop = (topSpan * padMul) / math.max(1e-6, 2 * tanHalfV * topShare)
    local needDistBottom = (bottomSpan * padMul) / math.max(1e-6, 2 * tanHalfV * bottomShare)
    local needDistV = math.max(needDistTop, needDistBottom)

    local fitWidth = math.max(1e-3, tonumber(world.fitWidth) or 1)
    local needDistH = (fitWidth * 0.5 * (1 + 2 * widthPad)) / math.max(1e-6, math.tan(hfov * 0.5))
    local dist = math.max(1.0, needDistV, needDistH)
    local aimTargetZ = solveAimTargetZ(focusZ, focusY, dist, vfov)
    local targetToTop = math.max(0, topZ - aimTargetZ)
    local targetToBottom = math.max(0, aimTargetZ - bottomZ)

    world.focusZ = focusZ
    world.topZ = topZ
    world.bottomZ = bottomZ
    world.visibleHi = world.visibleHi or topZ
    world.visibleLo = world.visibleLo or bottomZ
    world.targetZ = aimTargetZ
    world.desiredFocusY = focusY
    world.focusToTop = topSpan
    world.focusToBottom = bottomSpan
    world.targetToTop = targetToTop
    world.targetToBottom = targetToBottom

    return dist, {
        needDistV = needDistV,
        needDistH = needDistH,
        needDistTop = needDistTop,
        needDistBottom = needDistBottom,
        focusY = focusY,
        focusZ = focusZ,
        aimTargetZ = aimTargetZ,
        focusToTop = topSpan,
        focusToBottom = bottomSpan,
        targetToTop = targetToTop,
        targetToBottom = targetToBottom,
        symmetricFallback = symmetric,
    }
end

--- Solve a named region into world-space coordinates for any bbox source.
--- @param bbox table bounding box (canonical or live)
--- @param regionName string
--- @param classHint string|nil optional morphology class
--- @return table world, string class, table region, table anchors
function BR.SolveWorldRegion(bbox, regionName, classHint)
    if not bbox then
        return BR.ToWorldCoords(nil, nil), "tall_humanoid", BR.GetRegion("tall_humanoid", regionName), BR.GetAnchors("tall_humanoid")
    end
    local useClass = classHint or BR.Classify(bbox)
    local anchors = BR.GetAnchors(useClass)
    local region = BR.GetRegion(useClass, regionName or "bust")
    local world = BR.ToWorldCoords(bbox, region)
    return world, useClass, region, anchors
end

return BR
