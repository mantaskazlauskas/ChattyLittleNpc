local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

-- Framing helpers (pure-ish math with minimal engine calls)
NS.Framing = NS.Framing or {}

-- Convert engine F (ambiguous) into vertical/horizontal FOVs depending on assumption
function NS.Framing.FOVPair_FromF(F, assumeHorizontal)
    local vfov, hfov
    local f = tonumber(F) or 0.8
    local aspect = 1.0 -- caller should adapt; this is a pure fallback
    if assumeHorizontal then
        hfov = f
        vfov = 2 * math.atan(math.tan(hfov * 0.5) / math.max(1e-3, aspect))
    else
        vfov = f
        hfov = 2 * math.atan(math.tan(vfov * 0.5) * math.max(1e-3, aspect))
    end
    return vfov, hfov
end

-- Solve camera distance for axis alignment to fit half-extents in view
function NS.Framing.solveAxis(axis, vfov, hfov, halfX, halfY, halfZ)
    local v = tonumber(vfov) or 0.8
    local h = tonumber(hfov) or 1.2
    local hx = math.max(0.01, tonumber(halfX) or 1)
    local hy = math.max(0.00, tonumber(halfY) or 0)
    local hz = math.max(0.01, tonumber(halfZ) or 1)
    local halfViewV = math.tan(v * 0.5)
    local halfViewH = math.tan(h * 0.5)
    local dV = (axis == "Y") and (hz) / math.max(1e-6, halfViewV) or (hz) / math.max(1e-6, halfViewV)
    local dH = (axis == "Y") and (hx)      / math.max(1e-6, halfViewH) or (hy)      / math.max(1e-6, halfViewH)
    local d = math.max(dV, dH)
    local depthHalf = (axis == "Y") and hy or hx
    return d, dV, dH, depthHalf
end

return NS.Framing
