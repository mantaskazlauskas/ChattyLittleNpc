---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- PlayerModel renderer presets. We approximate via zoom/position/rotation APIs.
-- Exposes: ReplayFrame.PlayerPresets with functions(host) -> ()

ReplayFrame = ReplayFrame or {}
ReplayFrame.PlayerPresets = {}
local P = ReplayFrame.PlayerPresets

-- Full Body
function P.FullBody(host)
    if not host then return end
    if host.SetPortraitZoom then host:SetPortraitZoom(0.3) end
    if host.SetPosition then host:SetPosition(0, 0, 0) end
    if host.SetRotation then host:SetRotation(0) end
    host._lastCamSnapshot = host._lastCamSnapshot or {}
    host._lastCamSnapshot.tz = 0
end

-- Upper Body (upper 2/3 — head to upper thighs)
function P.UpperBody(host)
    if not host then return end
    local z = -0.15
    if host.SetPortraitZoom then host:SetPortraitZoom(0.01) end
    if host.SetPosition then host:SetPosition(0, 0, z) end
    if host.SetRotation then host:SetRotation(0) end
    host._lastCamSnapshot = host._lastCamSnapshot or {}
    host._lastCamSnapshot.tz = z
end

-- Wave (slight zoom-out for arm gesture)
function P.Wave(host)
    if not host then return end
    if host.SetPortraitZoom then host:SetPortraitZoom(0.55) end
    if host.SetPosition then host:SetPosition(0, 0, 0.02) end
    if host.SetRotation then host:SetRotation(0) end
    host._lastCamSnapshot = host._lastCamSnapshot or {}
    host._lastCamSnapshot.tz = 0.02
end

return P
