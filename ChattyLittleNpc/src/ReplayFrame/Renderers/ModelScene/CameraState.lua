---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

-- Lightweight centralized camera state helper used by the simplified framing path.
-- This does NOT replace the legacy snapshot system yet; it co-exists so we can
-- incrementally migrate without breaking PlayerModel or existing debug tooling.
local M = {}

---@param host table
---@return table cam Returns (and creates if missing) the camera state table
function M.ensure(host)
    if host._cam then return host._cam end
    host._cam = {
        targetX = 0, targetY = 0, targetZ = 1.0,
        dist = 2.5,
        axisX = 0, axisY = 1, axisZ = 0,
        upX = 0, upY = 0, upZ = 1,
        padFrac = 0.12,
        vfov = 0.8,
        aspect = 1.0,
    }
    return host._cam
end

---@param host table
---@param reason string|nil
function M.update(host, reason)
    local cam = host._cam; if not cam then return end
    local px = cam.targetX + cam.axisX * cam.dist
    local py = cam.targetY + cam.axisY * cam.dist
    local pz = cam.targetZ + cam.axisZ * cam.dist
    if host._ApplyCameraLookAt then
        host:_ApplyCameraLookAt(px, py, pz, cam.targetX, cam.targetY, cam.targetZ)
    end
    -- Keep legacy snapshot fields in sync so existing UI continues to function.
    host._lastCamSnapshot = host._lastCamSnapshot or {}
    local s = host._lastCamSnapshot
    s.px, s.py, s.pz = px, py, pz
    s.tx, s.ty, s.tz = cam.targetX, cam.targetY, cam.targetZ
    s.dist = cam.dist
    s.vfov = cam.vfov
    s.pad = cam.padFrac
    s.axis = (cam.axisY >= 0) and "Y+" or "Y-"
    if CLN and CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories and CLN.Utils.LogCategories.camera or "camera") then
        local okFmt, msg = pcall(string.format, "[SimpleCam] %s pos=(%.2f,%.2f,%.2f) tgt=(%.2f,%.2f,%.2f) dist=%.2f pad=%.2f", tostring(reason or "update"), px, py, pz, cam.targetX, cam.targetY, cam.targetZ, cam.dist, cam.padFrac)
        if okFmt and CLN.Utils.LogAnimDebug then
            pcall(CLN.Utils.LogAnimDebug, CLN.Utils, CLN.Utils.LogCategories and CLN.Utils.LogCategories.camera or "camera", msg)
        end
    end
    if host._ApplyClipsCurrent then host:_ApplyClipsCurrent() end
end

return M
