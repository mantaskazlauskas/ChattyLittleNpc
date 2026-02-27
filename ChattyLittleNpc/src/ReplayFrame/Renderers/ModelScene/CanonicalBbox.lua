local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.CanonicalBbox = NS.CanonicalBbox or {}
local CB = NS.CanonicalBbox

-- Per-displayID cache of idle-pose bounding boxes.
-- Keyed by displayID (number); each entry is a table:
--   { bbox={min,max,center,size}, class=string, sampledAt=number, modelVer=number, _expanded=bool }
CB._cache = CB._cache or {}

local function log(fmt, ...)
    if NS.Diagnostics and NS.Diagnostics.log then
        NS.Diagnostics.log("canonical", fmt, ...)
    end
end

local function bboxSignature(b)
    if not b then return nil end
    return string.format("%.4f|%.4f|%.4f|%.4f|%.4f|%.4f",
        b.min.x or 0, b.min.y or 0, b.min.z or 0,
        b.max.x or 0, b.max.y or 0, b.max.z or 0)
end

local function readBbox(actor)
    if not (actor and actor.GetActiveBoundingBox) then return nil end
    local ok, a, b, c, d, e, f = pcall(actor.GetActiveBoundingBox, actor)
    local minX, minY, minZ, maxX, maxY, maxZ
    if ok and type(a) == "table" and type(b) == "table" then
        minX = tonumber(a.x) or 0; minY = tonumber(a.y) or 0; minZ = tonumber(a.z) or 0
        maxX = tonumber(b.x) or 0; maxY = tonumber(b.y) or 0; maxZ = tonumber(b.z) or 0
    elseif ok and type(a) == "number" then
        minX = tonumber(a) or 0; minY = tonumber(b) or 0; minZ = tonumber(c) or 0
        maxX = tonumber(d) or 0; maxY = tonumber(e) or 0; maxZ = tonumber(f) or 0
    else
        return nil
    end
    local function isFinite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
    if not (isFinite(minX) and isFinite(minY) and isFinite(minZ) and isFinite(maxX) and isFinite(maxY) and isFinite(maxZ)) then return nil end
    if minX > maxX then minX, maxX = maxX, minX end
    if minY > maxY then minY, maxY = maxY, minY end
    if minZ > maxZ then minZ, maxZ = maxZ, minZ end
    local eps = 1e-3
    local sx = math.max(eps, math.abs(maxX - minX))
    local sy = math.max(eps, math.abs(maxY - minY))
    local sz = math.max(eps, math.abs(maxZ - minZ))
    return {
        min = { x = minX, y = minY, z = minZ },
        max = { x = maxX, y = maxY, z = maxZ },
        center = { x = (minX + maxX) * 0.5, y = (minY + maxY) * 0.5, z = (minZ + maxZ) * 0.5 },
        size = { x = sx, y = sy, z = sz },
    }
end

--- Sample the canonical (idle-pose) bounding box for an actor.
--- Forces idle animation, waits for two consecutive identical bbox readings,
--- then invokes callback(bbox). Restores the previously-desired animation.
---
--- @param actor table ModelScene actor
--- @param displayID number creature display ID
--- @param modelVersion number host._modelVersion at call time (stale guard)
--- @param getModelVersion function returns current model version (for guard checks)
--- @param animCtrl table|nil AnimationController instance to restore desired anim
--- @param callback function(bbox) called on success with the stable bbox
function CB.SampleCanonical(actor, displayID, modelVersion, getModelVersion, animCtrl, callback)
    if not actor then
        log("SampleCanonical: no actor")
        return
    end
    local id = tonumber(displayID)
    if not id then
        log("SampleCanonical: invalid displayID=%s", tostring(displayID))
        return
    end

    -- Already cached?
    if CB._cache[id] then
        log("SampleCanonical: cache hit for %d", id)
        if callback then callback(CB._cache[id].bbox) end
        return
    end

    -- Force idle for a clean reading
    if actor.SetAnimation then pcall(actor.SetAnimation, actor, 0) end

    local lastSig = nil
    local lastBbox = nil
    local ticks = 0
    local MAX_TICKS = 40  -- 2s at 50ms

    local function tick()
        -- Stale guard
        if getModelVersion and getModelVersion() ~= modelVersion then
            log("SampleCanonical: aborted (model version changed) for %d", id)
            return
        end
        ticks = ticks + 1

        local bbox = readBbox(actor)
        if not bbox then
            if ticks < MAX_TICKS then
                if C_Timer and C_Timer.After then C_Timer.After(0.05, tick) end
                return
            end
            log("SampleCanonical: timeout with nil bbox for %d", id)
            -- Restore desired animation
            if animCtrl and animCtrl.apply then animCtrl:apply(actor) end
            return
        end

        local sig = bboxSignature(bbox)
        if lastSig and lastSig == sig then
            -- Stable: two identical readings
            local class = NS.BodyRegions and NS.BodyRegions.Classify(bbox) or "tall_humanoid"
            CB._cache[id] = {
                bbox = bbox,
                class = class,
                sampledAt = GetTime and GetTime() or 0,
                modelVer = modelVersion,
                _expanded = false,
            }
            log("SampleCanonical: cached %d class=%s h=%.2f w=%.2f", id, class, bbox.size.z or 0, bbox.size.x or 0)
            -- Restore desired animation
            if animCtrl and animCtrl.apply then animCtrl:apply(actor) end
            if callback then callback(bbox) end
            return
        end

        lastSig = sig
        lastBbox = bbox

        if ticks >= MAX_TICKS then
            -- Best-effort: use last reading
            local class = NS.BodyRegions and NS.BodyRegions.Classify(bbox) or "tall_humanoid"
            CB._cache[id] = {
                bbox = bbox,
                class = class,
                sampledAt = GetTime and GetTime() or 0,
                modelVer = modelVersion,
                _expanded = false,
            }
            log("SampleCanonical: best-effort cache for %d (ticks=%d)", id, ticks)
            if animCtrl and animCtrl.apply then animCtrl:apply(actor) end
            if callback then callback(bbox) end
            return
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, tick)
        end
    end

    -- Start after one frame to let idle pose settle
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, tick)
    else
        tick()
    end
end

--- Get the cached canonical bbox for a displayID, or nil if not sampled yet.
function CB.GetCached(displayID)
    return CB._cache[tonumber(displayID)]
end

--- Invalidate the canonical bbox cache for a displayID.
function CB.Invalidate(displayID)
    local id = tonumber(displayID)
    if id then
        CB._cache[id] = nil
        log("Invalidate: cleared cache for %d", id)
    end
end

--- One-time divergence check: if live bbox is >30% larger in height than
--- canonical, expand canonical by 50% of the delta to add headroom.
--- Call once on the first non-idle animation for a displayID.
function CB.CheckDivergence(displayID, liveBbox)
    local id = tonumber(displayID)
    if not id then return end
    local entry = CB._cache[id]
    if not entry or entry._expanded then return end
    if not (liveBbox and liveBbox.size and liveBbox.size.z) then return end

    local canonH = entry.bbox.size.z or 0
    local liveH = liveBbox.size.z or 0
    if canonH < 0.01 then return end

    local drift = (liveH - canonH) / canonH
    if drift > 0.30 then
        local expansion = (liveH - canonH) * 0.5
        entry.bbox.size.z = canonH + expansion
        entry.bbox.max.z = entry.bbox.min.z + entry.bbox.size.z
        entry.bbox.center.z = entry.bbox.min.z + entry.bbox.size.z * 0.5
        entry._expanded = true
        log("CheckDivergence: expanded %d by %.2f (drift=%.1f%%)", id, expansion, drift * 100)
    end
end

return CB
