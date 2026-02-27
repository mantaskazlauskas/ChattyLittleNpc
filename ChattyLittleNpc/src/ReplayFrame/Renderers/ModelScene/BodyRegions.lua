local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.BodyRegions = NS.BodyRegions or {}
local BR = NS.BodyRegions

-- Region definitions per morphology class.
-- targetPct  = vertical center of camera focus (0=feet, 1=top)
-- rangeLo/Hi = visible slice of model height
-- shoulderW  = fraction of bbox width to fit horizontally
BR.REGIONS = {
    tall_humanoid = {
        bust       = { targetPct = 0.875, rangeLo = 0.75, rangeHi = 1.00, shoulderW = 0.55 },
        head       = { targetPct = 0.925, rangeLo = 0.85, rangeHi = 1.00, shoulderW = 0.40 },
        upper_body = { targetPct = 0.700, rangeLo = 0.45, rangeHi = 1.00, shoulderW = 0.65 },
        full_body  = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
    },
    stocky_humanoid = {
        bust       = { targetPct = 0.850, rangeLo = 0.70, rangeHi = 1.00, shoulderW = 0.65 },
        head       = { targetPct = 0.900, rangeLo = 0.80, rangeHi = 1.00, shoulderW = 0.45 },
        upper_body = { targetPct = 0.675, rangeLo = 0.40, rangeHi = 1.00, shoulderW = 0.70 },
        full_body  = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
    },
    wide_beast = {
        bust       = { targetPct = 0.750, rangeLo = 0.50, rangeHi = 1.00, shoulderW = 0.80 },
        head       = { targetPct = 0.850, rangeLo = 0.65, rangeHi = 1.00, shoulderW = 0.60 },
        upper_body = { targetPct = 0.600, rangeLo = 0.30, rangeHi = 1.00, shoulderW = 0.85 },
        full_body  = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
    },
    dragon = {
        bust       = { targetPct = 0.800, rangeLo = 0.55, rangeHi = 1.00, shoulderW = 0.70 },
        head       = { targetPct = 0.875, rangeLo = 0.70, rangeHi = 1.00, shoulderW = 0.50 },
        upper_body = { targetPct = 0.650, rangeLo = 0.35, rangeHi = 1.00, shoulderW = 0.75 },
        full_body  = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
    },
    tiny_critter = {
        bust       = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
        head       = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
        upper_body = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
        full_body  = { targetPct = 0.500, rangeLo = 0.00, rangeHi = 1.00, shoulderW = 1.00 },
    },
}

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
    local classRegions = BR.REGIONS[class] or BR.REGIONS.tall_humanoid
    return classRegions[regionName] or classRegions.bust
end

--- Convert a body region to world-space coordinates using the canonical bbox.
--- @param canonBbox table the cached idle-pose bounding box
--- @param region table region record from GetRegion
--- @return table world-space targeting data
function BR.ToWorldCoords(canonBbox, region)
    if not (canonBbox and canonBbox.min and canonBbox.size and region) then
        return { targetX = 0, targetY = 0, targetZ = 0, visibleH = 1, fitWidth = 1, visibleLo = 0, visibleHi = 1 }
    end
    local minZ   = canonBbox.min.z or 0
    local height = canonBbox.size.z or 1
    local cx     = canonBbox.center.x or 0
    local cy     = canonBbox.center.y or 0

    local targetZ   = minZ + height * region.targetPct
    local visibleLo = minZ + height * region.rangeLo
    local visibleHi = minZ + height * region.rangeHi
    local visibleH  = visibleHi - visibleLo
    local fitWidth  = (canonBbox.size.x or 1) * region.shoulderW

    return {
        targetX   = cx,
        targetY   = cy,
        targetZ   = targetZ,
        visibleH  = visibleH,
        fitWidth  = fitWidth,
        visibleLo = visibleLo,
        visibleHi = visibleHi,
    }
end

return BR
