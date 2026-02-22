local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.Diagnostics = NS.Diagnostics or {}

local function canLog()
    return CLN and CLN.db and CLN.db.profile and CLN.db.profile.debugMode
end

function NS.Diagnostics.log(cat, fmt, ...)
    if not canLog() then return end
    local msg = string.format(fmt, ...)
    -- Route to Utils logger; LogsWindow captures and keeps it out of chat
    if CLN.Utils and CLN.Utils.LogAnimDebug then
        CLN.Utils:LogAnimDebug(tostring(cat or "misc"), msg)
    elseif CLN and CLN.Logger then
        local logCat = (CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.projection) or "projection"
        CLN.Logger:debug("[CLN:" .. tostring(cat or "?") .. "] " .. msg, false, logCat)
    end
end

-- Project a 3D point to 2D screen space using the ModelScene API.
-- Returns true, px, py on success; false otherwise.
function NS.Diagnostics.projectPoint(scene, x, y, z)
    if not (scene and scene.Project3DPointTo2D) then return false end
    local ok, px, py = pcall(scene.Project3DPointTo2D, scene, x, y, z)
    if not ok then return false end
    if type(px) ~= "number" or type(py) ~= "number" then return false end
    if px ~= px or py ~= py then return false end
    return true, px, py
end

-- Compute coverage stats and screen-space bounding box for an AABB defined by center (cx,cy,cz) and size (sx,sy,sz).
-- frameW/H are the viewport size in pixels used to count how many corners are inside the frame.
-- Returns inside, total, minPX, minPY, maxPX, maxPY.
function NS.Diagnostics.coverageStats(scene, cx, cy, cz, sx, sy, sz, frameW, frameH)
    if not (scene and scene.Project3DPointTo2D) then return 0, 0, 1/0, 1/0, -1/0, -1/0 end
    local hx = (sx and sx > 0) and (sx * 0.5) or 1
    local hy = (sy and sy > 0) and (sy * 0.5) or 1
    local hz = (sz and sz > 0) and (sz * 0.5) or 1
    local yCenter = cy or 0
    local inside, total = 0, 0
    local minPX, minPY, maxPX, maxPY = 1/0, 1/0, -1/0, -1/0
    for sxn = -1, 1, 2 do
        for syn = -1, 1, 2 do
            for szn = -1, 1, 2 do
                local x = (cx or 0) + sxn * hx
                local y = yCenter + syn * hy
                local z = (cz or 0) + szn * hz
                local ok, px, py = NS.Diagnostics.projectPoint(scene, x, y, z)
                total = total + 1
                if ok then
                    if px < minPX then minPX = px end
                    if px > maxPX then maxPX = px end
                    if py < minPY then minPY = py end
                    if py > maxPY then maxPY = py end
                    if frameW and frameH and px >= 0 and px <= frameW and py >= 0 and py <= frameH then
                        inside = inside + 1
                    end
                end
            end
        end
    end
    return inside, total, minPX, minPY, maxPX, maxPY
end

-- Return inside coverage count for the current camera, using a simple AABB corner sampling.
function NS.Diagnostics.computeInsideCount(scene, cx, cy, cz, sx, sy, sz, frameW, frameH)
    if not (scene and scene.Project3DPointTo2D) then return 0, 0 end
    local hx = (sx and sx > 0) and (sx * 0.5) or 1
    local hy = (sy and sy > 0) and (sy * 0.5) or 1
    local hz = (sz and sz > 0) and (sz * 0.5) or 1
    local yCenter = cy or 0
    local inside, total = 0, 0
    for sxn = -1, 1, 2 do
        for syn = -1, 1, 2 do
            for szn = -1, 1, 2 do
                local x = (cx or 0) + sxn * hx
                local y = yCenter + syn * hy
                local z = (cz or 0) + szn * hz
                local ok, px, py = NS.Diagnostics.projectPoint(scene, x, y, z)
                total = total + 1
                if ok and frameW and frameH and px >= 0 and px <= frameW and py >= 0 and py <= frameH then
                    inside = inside + 1
                end
            end
        end
    end
    return inside, total
end

-- Log a projection coverage debug message for the given bounds and viewport.
function NS.Diagnostics.debugProjection(host, scene, cx, cy, cz, sx, sy, sz, frameW, frameH, pad)
    if not (scene and scene.Project3DPointTo2D) then return end
    local okSize = (type(frameW) == "number" and frameW > 0 and type(frameH) == "number" and frameH > 0)
    local hx = (sx and sx > 0) and (sx * 0.5) or 1
    local hy = (sy and sy > 0) and (sy * 0.5) or 1
    local hz = (sz and sz > 0) and (sz * 0.5) or 1
    local yCenter = cy or 0
    local minPX, minPY, maxPX, maxPY = 1/0, 1/0, -1/0, -1/0
    local insideCount, total = 0, 0
    local anyProjected = false
    for sxn = -1, 1, 2 do
        for syn = -1, 1, 2 do
            for szn = -1, 1, 2 do
                local x = (cx or 0) + sxn * hx
                local y = yCenter + syn * hy
                local z = (cz or 0) + szn * hz
                local ok, px, py = NS.Diagnostics.projectPoint(scene, x, y, z)
                total = total + 1
                if ok then
                    anyProjected = true
                    if px < minPX then minPX = px end
                    if px > maxPX then maxPX = px end
                    if py < minPY then minPY = py end
                    if py > maxPY then maxPY = py end
                    if okSize and px >= 0 and px <= frameW and py >= 0 and py <= frameH then
                        insideCount = insideCount + 1
                    end
                end
            end
        end
    end
    if not anyProjected then
        if host and host._DebugLog then
            host:_DebugLog("projection", "Proj2D bbox: projection unavailable; skipping bounds check")
        else
            NS.Diagnostics.log("projection", "Proj2D bbox: projection unavailable; skipping bounds check")
        end
        return
    end
    local verdict = okSize and (insideCount == total) and "IN" or "OUT"
    -- [Check] normalized margins
    local left, right, top, bottom = minPX or 0, maxPX or 0, minPY or 0, maxPY or 0
    local ok = okSize and left >= 0 and right <= (frameW or 0) and top >= 0 and bottom <= (frameH or 0)
    if host and host._DebugLog then
        host:_DebugLog("projection", string.format("[Check] left=%.3f right=%.3f top=%.3f bottom=%.3f (ok=%s)", left, right, top, bottom, tostring(ok)))
    else
        NS.Diagnostics.log("projection", "[Check] left=%.3f right=%.3f top=%.3f bottom=%.3f (ok=%s)", left, right, top, bottom, tostring(ok))
    end
    local msg = string.format(
        "Proj2D bbox: min=(%.1f,%.1f) max=(%.1f,%.1f) frame=(%.0f,%.0f) inside=%d/%d pad=%.2f [%s]",
        minPX, minPY, maxPX, maxPY, frameW or -1, frameH or -1, insideCount, total, tonumber(pad) or 0, verdict
    )
    if host and host._DebugLog then
        host:_DebugLog("projection", msg)
    else
        NS.Diagnostics.log("projection", "%s", msg)
    end
end
